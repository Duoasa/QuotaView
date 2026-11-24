import AppKit
import ApplicationServices

/// Mirrors the official desktop client's mounted, runtime permission card.
enum AntigravityDesktopApproval {
    enum Scope: String {
        case once = "Allow once"
        case conversation = "Allow for conversation"
        case project = "Allow in project"
        case workspace = "Allow in workspace"
        case always = "Always allow"

        var label: IslandDetailText {
            switch self {
            case .once: .init("仅本次允许", "Allow once")
            case .conversation: .init("本会话允许", "Allow for session")
            case .project: .init("在此项目中允许", "Allow in project")
            case .workspace: .init("在此工作区中允许", "Allow in workspace")
            case .always: .init("始终允许", "Always allow")
            }
        }
    }

    struct Card: Equatable {
        let conversation: UUID
        let content: String
        let scope: Scope
        let element: AXUIElement
        let allow: AXUIElement
        let deny: AXUIElement
    }

    struct Control {
        let element: AXUIElement
        let role: String
        let label: String
        let value: String?
        let enabled: Bool
        var selected = false
    }

    enum Surface {
        case inline, questionnaire

        init?(classes: Set<String>) {
            if classes.isSuperset(of: ["no-focus-agent-input", "border-warning/40", "bg-card", "rounded-xl"]) {
                self = .inline
            } else if classes.isSuperset(of: ["no-focus-agent-input", "outline-none", "no-focus-ring", "flex-col"]) {
                self = .questionnaire
            } else { return nil }
        }
    }

    static func parse(_ controls: [Control], conversation: UUID, element: AXUIElement) -> Card? {
        let labels = controls.filter { $0.role == "AXStaticText" }.map { $0.value ?? $0.label }
        guard labels.contains("Runtime permission"),
              controls.contains(where: { $0.role == "AXRadioGroup" && $0.label == "Permission approval scope" }),
              !controls.contains(where: { $0.role == "AXButton" && $0.label.hasPrefix("Open Subagent:") })
        else { return nil }
        let buttons = controls.filter { $0.role == "AXButton" && $0.enabled }
        let allow = buttons.filter { Scope(rawValue: $0.label) != nil }, deny = buttons.filter { $0.label == "Deny" }
        guard allow.count == 1, deny.count == 1, let scope = Scope(rawValue: allow[0].label) else { return nil }
        let selected = controls.filter { $0.role == "AXRadioButton" && $0.selected && $0.enabled }
        guard selected.count <= 1 else { return nil }
        // A saved rule can cover a broader pattern than the editable target.
        // Require the native selected option's wording before offering a lasting grant.
        if scope != .once && selected.first?.label.isEmpty != false { return nil }

        // The target is user-editable in Antigravity. Include its current value verbatim,
        // along with the actual question, reason and warnings above the scope picker.
        let description = controls.prefix { $0.role != "AXRadioGroup" }.compactMap { item -> String? in
            if item.role == "AXTextArea" && item.label == "Edit permission target" { return item.value }
            guard item.role == "AXStaticText" else { return nil }
            let text = item.value ?? item.label
            return text.isEmpty || text == "Runtime permission" ? nil : text
        }
        guard controls.filter({ $0.role == "AXTextArea" }).allSatisfy({ $0.label == "Edit permission target" && $0.value?.isEmpty == false }),
              !description.isEmpty else { return nil }
        let text = (description + selected.map(\.label)).joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 48_000 else { return nil }
        return Card(conversation: conversation, content: text, scope: scope, element: element, allow: allow[0].element, deny: deny[0].element)
    }

    // The command permission composer shares its outer wrapper with ordinary questions.
    // Its editable permission target and its single-choice controls identify the form.
    static func parseQuestionnaire(_ controls: [Control], conversation: UUID, element: AXUIElement) -> Card? {
        guard let divider = controls.firstIndex(where: { $0.role == "AXRadioGroup" }),
              controls[(divider + 1)...].allSatisfy({ $0.role != "AXRadioGroup" }) else { return nil }
        let header = controls[..<divider], choices = controls[divider...]
        let editors = header.filter { $0.role == "AXTextArea" }
        guard editors.count == 1, editors[0].label == "Edit permission target",
              let target = editors[0].value, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              choices.filter({ $0.role == "AXTextArea" }).allSatisfy({ ($0.value ?? "").isEmpty }) else { return nil }

        let radios = choices.filter { $0.role == "AXRadioButton" }
        let selected = radios.filter(\.selected)
        guard selected.count == 1, selected[0].enabled,
              let scope = commandScope(option: selected[0].label),
              radios.contains(where: { optionText($0.label) == "No" || optionText($0.label).hasPrefix("No (tell the agent what to do instead)") })
        else { return nil }

        let buttons = choices.filter { $0.role == "AXButton" && $0.enabled }
        let submit = buttons.filter { ["Submit", "Submit ↵", "Submit ⏎", "Submit↵", "Submit⏎"].contains($0.label) }
        let skip = buttons.filter { $0.label == "Skip" }
        guard submit.count == 1, skip.count == 1 else { return nil }
        let details = header.compactMap { item -> String? in
            if item.role == "AXTextArea" { return target }
            guard item.role == "AXStaticText" else { return nil }
            let text = item.value ?? item.label
            return text.isEmpty ? nil : text
        }
        guard details.count > 1 else { return nil }
        let content = (details + [optionText(selected[0].label)]).joined(separator: "\n")
        guard content.utf8.count <= 48_000 else { return nil }
        // In this specific permission form Submit confirms the native selection,
        // and Skip calls the client's explicit one-time denial handler.
        return Card(conversation: conversation, content: content, scope: scope, element: element,
                    allow: submit[0].element, deny: skip[0].element)
    }

    private static func optionText(_ label: String) -> String {
        String(label.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0.isNumber }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func commandScope(option: String) -> Scope? {
        let text = optionText(option)
        if text == "Yes, allow this time" { return .once }
        let prefix = "Yes, and always allow '"
        guard text.hasPrefix(prefix) else { return nil }
        let rule = text.dropFirst(prefix.count)
        for (suffix, scope) in [("' in this conversation", Scope.conversation), ("'", Scope.always)]
        where rule.hasSuffix(suffix) && rule.count > suffix.count { return scope }
        return nil
    }

    static func scan(_ conversations: Set<UUID>) -> [UUID: Card] {
        guard !conversations.isEmpty, AXIsProcessTrusted() else { return [:] }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity")
        guard apps.count == 1, let app = apps.first else { return [:] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows) == .success,
              let windows = windows as? [AXUIElement] else { return [:] }
        let fields = [kAXRoleAttribute, kAXURLAttribute, "AXDOMClassList", kAXChildrenAttribute] as CFArray
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var cards: [UUID: Card] = [:], ambiguous = Set<UUID>()
        var nodes = windows.map { ($0, nil as UUID?, false) }
        while let (element, parent, inWeb) = nodes.popLast() {
            guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return [:] }
            guard let row = attributes(element, fields), let role = row[0] as? String else { continue }
            var session = parent
            if role == "AXWebArea" {
                guard !inWeb, let page = row[1] as? URL, let id = UUID(uuidString: page.lastPathComponent),
                      conversations.contains(id), IslandConversationSidebar.matchesAntigravity(page, session: id.uuidString) else { continue }
                session = id
            }
            let classes = Set(row[2] as? [String] ?? [])
            if let session, let surface = Surface(classes: classes) {
                if let card = readCard(element, surface: surface, session: session, deadline: deadline) {
                    if cards.updateValue(card, forKey: session) != nil { ambiguous.insert(session) }
                }
                continue
            }
            // The inline permission composer is outside message history and child webviews.
            if classes.contains("group/bubble") || ["AXStaticText", "AXTextArea", "AXButton", "AXLink", "AXImage"].contains(role) { continue }
            if let children = row[3] as? [AXUIElement] {
                nodes.append(contentsOf: children.map { ($0, session, inWeb || role == "AXWebArea") })
            }
        }
        for id in ambiguous { cards.removeValue(forKey: id) }
        return cards
    }

    private static func readCard(_ root: AXUIElement, surface: Surface, session: UUID, deadline: TimeInterval) -> Card? {
        let fields = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXEnabledAttribute, kAXChildrenAttribute] as CFArray
        var nodes = [root], controls: [Control] = []
        while let current = nodes.popLast() {
            guard controls.count < 256, ProcessInfo.processInfo.systemUptime < deadline,
                  let row = attributes(current, fields), let role = row[0] as? String, role != "AXWebArea" else { return nil }
            let title = row[1] as? String ?? ""
            controls.append(.init(element: current, role: role, label: title.isEmpty ? row[2] as? String ?? "" : title,
                                  value: row[3] as? String, enabled: row[4] as? Bool == true, selected: (row[3] as? NSNumber)?.boolValue == true))
            if let children = row[5] as? [AXUIElement] { nodes.append(contentsOf: children.reversed()) }
        }
        switch surface {
        case .inline: return parse(controls, conversation: session, element: root)
        case .questionnaire: return parseQuestionnaire(controls, conversation: session, element: root)
        }
    }

    private static func attributes(_ node: AXUIElement, _ names: CFArray) -> [Any]? {
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, names, [], &result) == .success,
              let row = result as? [Any], row.count == CFArrayGetCount(names) else { return nil }
        return row
    }

    static func press(_ card: Card, allow: Bool) -> Bool {
        // A window-wide scan can encounter this card early. Check its current scope,
        // editable target and both button handles again immediately before AXPress.
        guard AXIsProcessTrusted(), let row = attributes(card.element, ["AXDOMClassList"] as CFArray),
              let surface = Surface(classes: Set(row[0] as? [String] ?? [])),
              readCard(card.element, surface: surface, session: card.conversation,
                deadline: ProcessInfo.processInfo.systemUptime + 0.5) == card else { return false }
        return AXUIElementPerformAction(allow ? card.allow : card.deny, kAXPressAction as CFString) == .success
    }
}
