import AppKit
import ApplicationServices
import SQLite3

/// Operates only on the question form mounted by the desktop app. The ordinary
/// composer is outside that form, even though both expose a ProseMirror editor.
enum CodexDesktopQuestionInput {
    struct Target: Equatable {
        let thread: UUID
        let turnHash: String
        let callID: String
        let question: String
        let options: [String]
    }

    struct Card: Equatable {
        let target: Target
        let window: AXUIElement
        let form: AXUIElement
        let editor: AXUIElement
        let send: AXUIElement
    }

    private struct Node {
        let role: String
        let label: String
        let text: String
        let classes: Set<String>
        let children: [AXUIElement]
        let url: URL?

        init?(_ element: AXUIElement) {
            let keys = ["AXRole", "AXTitle", "AXDescription", "AXValue", "AXDOMClassList", "AXChildren", "AXURL"] as CFArray
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, keys, [], &values) == .success,
                  let row = values as? [Any], row.count == 7, let role = row[0] as? String else { return nil }
            self.role = role
            let title = row[1] as? String ?? ""
            label = title.isEmpty ? row[2] as? String ?? "" : title
            text = row[3] as? String ?? ""
            classes = Set(row[4] as? [String] ?? [])
            children = row[5] as? [AXUIElement] ?? []
            url = row[6] as? URL
        }
    }

    static func thread(named title: String, home: URL) -> UUID? {
        guard !title.isEmpty else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(home.appendingPathComponent("state_5.sqlite").path, &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT id FROM threads WHERE coalesce(nullif(trim(name), ''), title) = ? LIMIT 2"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return title.withCString { name in
            guard sqlite3_bind_text(stmt, 1, name, -1, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW,
                  let bytes = sqlite3_column_text(stmt, 0), let id = UUID(uuidString: String(cString: bytes)),
                  sqlite3_step(stmt) == SQLITE_DONE else { return nil }
            return id
        }
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }

    static func matchesPrompt(_ source: String, fragments: [String]) -> Bool {
        guard !source.isEmpty, !fragments.isEmpty else { return false }
        if fragments == [source] { return true }
        func words(_ text: String) -> [Substring] { text.split(whereSeparator: { $0.isWhitespace }) }
        let rendered = words(fragments.joined(separator: " "))
        guard !rendered.isEmpty else { return false }
        if words(source) == rendered { return true }
        guard let attributed = try? AttributedString(markdown: source) else { return false }
        let markdown = attributed.runs.map { String(attributed[$0.range].characters) }.joined(separator: " ")
        return words(markdown) == rendered
    }

    private static func readForm(_ form: AXUIElement, window: AXUIElement, targets: [Target], deadline: TimeInterval) -> Card? {
        var nodes = [form], titles = [String](), labels = [String]()
        var editors = [AXUIElement](), buttons = [AXUIElement](), hasSkip = false, count = 0
        while let element = nodes.popLast() {
            count += 1
            guard count <= 1024, ProcessInfo.processInfo.systemUptime < deadline, let node = Node(element) else { return nil }
            switch node.role {
            case "AXStaticText": titles.append(node.text.isEmpty ? node.label : node.text)
            case "AXRadioButton":
                labels.append(node.label)
            case "AXTextArea":
                guard node.classes.contains("ProseMirror") else { return nil }
                editors.append(element)
            case "AXButton":
                if ["Send", "Submit", "发送", "提交", "傳送", "送出", "發送"].contains(node.label) { buttons.append(element) }
                if ["Skip", "跳过", "略過", "跳過"].contains(node.label) { hasSkip = true }
            case "AXWebArea", "AXCheckBox", "AXSecureTextField": return nil
            default: nodes.append(contentsOf: node.children.reversed())
            }
        }
        guard let header = titles.first, ["Question", "问题", "問題"].contains(header) else { return nil }
        let fragments = Array(titles.dropFirst())
        let matches = targets.filter { $0.options == labels && matchesPrompt($0.question, fragments: fragments) }
        guard matches.count == 1, let target = matches.first,
              hasSkip,
              editors.count == 1, buttons.count == 1 else { return nil }
        return Card(target: target, window: window, form: form, editor: editors[0], send: buttons[0])
    }

    static func scan(_ targets: [Target], home: URL) -> [Card] {
        guard !targets.isEmpty, AXIsProcessTrusted() else { return [] }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        guard apps.count == 1, let app = apps.first else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let windows = attribute(root, "AXWindows") as? [AXUIElement] else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var cards = [Card]()
        for window in windows {
            guard let title = attribute(window, "AXTitle") as? String, let thread = thread(named: title, home: home) else { continue }
            let candidates = targets.filter { $0.thread == thread }
            guard !candidates.isEmpty else { continue }
            // A hit test initializes Chromium's lazy accessibility tree without moving the pointer or focusing the window.
            if let pos = attribute(window, "AXPosition"), CFGetTypeID(pos) == AXValueGetTypeID() {
                var point = CGPoint.zero, hit: AXUIElement?
                if AXValueGetValue(pos as! AXValue, .cgPoint, &point) {
                    _ = AXUIElementCopyElementAtPosition(root, Float(point.x + 32), Float(point.y + 80), &hit)
                }
            }
            var pending = [(window, false, false)]
            while let (element, inWeb, inFooter) = pending.popLast() {
                guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return [] }
                guard let node = Node(element) else { continue }
                var web = inWeb
                if node.role == "AXWebArea" {
                    guard !inWeb, node.url?.scheme == "app", node.url?.host == "-", node.label == title else { continue }
                    web = true
                }
                let footer = inFooter || (web && node.classes.contains(where: { $0.hasPrefix("footer-") }))
                if footer && node.classes.isSuperset(of: ["flex-col", "overflow-hidden", "text-default", "focus:outline-none"]) {
                    if let card = readForm(element, window: window, targets: candidates, deadline: deadline) { cards.append(card) }
                    continue
                }
                if node.classes.contains(where: { $0.hasPrefix("transcriptContent-") }) || ["AXStaticText", "AXTextArea", "AXLink", "AXButton", "AXRadioButton", "AXImage"].contains(node.role) { continue }
                pending.append(contentsOf: node.children.reversed().map { ($0, web, footer) })
            }
        }
        return cards.filter { card in cards.filter { $0.target == card.target }.count == 1 }
    }

    static func submit(_ card: Card, answer: String, home: URL,
                       stillPending: @MainActor () -> Bool) async throws {
        guard await stillPending(), !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              answer.utf8.count <= 64_000, scan([card.target], home: home) == [card],
              let initial = Node(card.editor), let draft = editorDraft(initial),
              draft.isEmpty || draft == answer else { throw CocoaError(.userCancelled) }
        // Clicking a native radio can submit immediately. Feed option labels and
        // free text through the same editor, then explicitly press Send once.
        if draft != answer {
            guard AXUIElementSetAttributeValue(card.editor, kAXValueAttribute as CFString, answer as CFString) == .success
            else { throw CocoaError(.userCancelled) }
        }
        // React enables Send only after its own draft state updates. Recheck the
        // original form, selected text and window immediately before pressing it.
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 80_000_000)
            guard scan([card.target], home: home) == [card] else { throw CocoaError(.userCancelled) }
            if Node(card.editor).flatMap(editorDraft) == answer, (attribute(card.send, "AXEnabled") as? Bool) == true {
                guard await stillPending(), performPress(card.send) else { throw CocoaError(.userCancelled) }
                return
            }
        }
        throw CocoaError(.userCancelled)
    }

    private static func editorDraft(_ node: Node) -> String? {
        guard node.role == "AXTextArea" else { return nil }
        // Chromium exposes the placeholder decoration as a line in an empty ProseMirror.
        if node.text == node.label + "\n" || node.text == "\n" { return "" }
        return node.text.hasSuffix("\n") ? String(node.text.dropLast()) : node.text
    }

    private static func performPress(_ element: AXUIElement) -> Bool {
        (attribute(element, "AXEnabled") as? Bool) == true
            && AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}
