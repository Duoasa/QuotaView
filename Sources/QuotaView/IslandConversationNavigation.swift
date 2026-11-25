import AppKit
import Foundation
import SQLite3

/// Targets are assembled from native identifiers. No incoming hook supplies an executable or URL.
enum IslandConversationTarget: Equatable {
    case claudeHook(UUID, desktop: UUID? = nil, terminal: Bool = false), claudeTerminal(UUID), claude(UUID), cursor(UUID), devin(String), dsh(String), antigravity(UUID), antigravityHook(UUID)

    case agentTerminal(IslandAgentProvider, UUID)

    var provider: IslandAgentProvider {
        switch self {
        case let .agentTerminal(provider, _): provider
        case .dsh: .dsh
        case .antigravity, .antigravityHook: .antigravity
        case .claudeHook, .claudeTerminal, .claude: .claudeCode
        case .cursor: .cursor
        case .devin: .devinDesktop
        }
    }

    /// These destinations depend on live permissions, sidebar rows or a terminal session.
    func needsRecheck(after resolved: Self?) -> Bool {
        switch self {
        case .dsh, .antigravity, .antigravityHook, .agentTerminal: return true
        case .claudeHook(_, _, true):
            if case .claude = resolved { return false }
            return true
        default: return false
        }
    }

    var url: URL? {
        switch self {
        case .claudeHook, .antigravityHook: return nil
        case .agentTerminal(_, let id): return ClaudeTerminalNavigation.link(for: id, nativeAgent: true)
        case .claudeTerminal(let id): return ClaudeTerminalNavigation.link(for: id)
        case .claude(let id):
            return URL(string: "claude://claude.ai/epitaxy/local_" + id.uuidString.lowercased())
        case .cursor(let id):
            return URL(string: "cursor.composer:" + id.uuidString.lowercased())
        case .dsh(let id):
            guard Self.isSessionID(id) else { return nil }
            return URL(string: "quotaview-dsh-row://session/" + id)
        case .antigravity(let id):
            return URL(string: "quotaview-antigravity-row://session/" + id.uuidString.lowercased())
        case .devin(let id):
            guard Self.isSessionID(id) else { return nil }
            return URL(string: "vscode-cascade-editor:/cascade-devin-acp/devin-cli/" + id)
        }
    }

    static func isSessionID(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    static func cursorHasComposer(_ id: UUID, database: URL) -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM cursorDiskKV WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return false }
        let key = "composerData:" + id.uuidString.lowercased()
        return key.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, nil) == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW
        }
    }

    static func claudeSession(for cliID: UUID, roots: [URL], desktop: UUID? = nil) -> UUID? {
        struct Metadata: Decodable { let sessionId: String; let cliSessionId: UUID?; let lastAssistantCliSessionId: UUID?; let isArchived: Bool? }
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        func children(_ directory: URL) -> [URL]? {
            try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        }
        func isDirectory(_ file: URL) -> Bool {
            let info = try? file.resourceValues(forKeys: Set(keys))
            return info?.isDirectory == true && info?.isSymbolicLink == false
        }
        var match: UUID?
        for root in roots {
            guard isDirectory(root.deletingLastPathComponent()), isDirectory(root), let accounts = children(root) else { continue }
            for account in accounts where isDirectory(account) {
                guard let organizations = children(account) else { continue }
                for org in organizations where isDirectory(org) {
                    guard let files = children(org) else { continue }
                    for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                        let name = file.deletingPathExtension().lastPathComponent
                        guard let id = UUID(uuidString: String(name.dropFirst(6))) else { continue }
                        guard let info = try? file.resourceValues(forKeys: Set(keys)), info.isRegularFile == true,
                              info.isSymbolicLink == false, let size = info.fileSize, size <= 4_194_304,
                              let bytes = try? Data(contentsOf: file, options: .mappedIfSafe),
                              let row = try? JSONDecoder().decode(Metadata.self, from: bytes) else { continue }
                        guard desktop == nil || desktop == id, row.cliSessionId == cliID || row.lastAssistantCliSessionId == cliID, row.isArchived != true, row.sessionId == name else { continue }
                        guard match == nil else { return nil }
                        match = id
                    }
                }
            }
        }
        return match
    }
}

enum IslandConversationNavigation {
    static func bundleID(for url: URL) -> String? {
        switch url.scheme {
        case "quotaview-dsh-row": "com.deepseek.dsh"
        case "quotaview-antigravity-row": "com.google.antigravity"
        case "codex": "com.openai.codex"
        case "claude": "com.anthropic.claudefordesktop"
        case "cursor.composer": "com.todesktop.230313mzl4w4u92"
        case "vscode-cascade-editor": "com.exafunction.windsurf"
        default: nil
        }
    }

    static func resolve(_ candidate: IslandConversationTarget) async -> IslandConversationTarget? {
        if case let .claudeHook(cliID, desktop, terminal) = candidate {
            let hasDesktop = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
            let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            let roots = ["Claude", "Claude-3p"].map { support.appendingPathComponent($0 + "/claude-code-sessions") }
            func mappedDesktop(_ hint: UUID?) async -> IslandConversationTarget? {
                guard hasDesktop else { return nil }
                let local = await Task.detached(priority: .utility) {
                    IslandConversationTarget.claudeSession(for: cliID, roots: roots, desktop: hint)
                }.value
                return local.map(IslandConversationTarget.claude)
            }
            if let desktop, let mapped = await mappedDesktop(desktop) { return mapped }
            if terminal {
                return await ClaudeTerminalNavigation.perform(cliID, select: false) ? .claudeTerminal(cliID) : nil
            }
            return await mappedDesktop(nil)
        }
        if case .antigravityHook(let id) = candidate {
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")
            let desktop = await Task.detached(priority: .utility) {
                let session = id.uuidString.lowercased()
                guard let logs = AntigravityHistory.logs(root: root, session: session, client: nil) else { return false }
                return logs == AntigravityHistory.logs(root: root, session: session, client: "antigravity")
            }.value
            guard desktop else { return nil }
            return await resolve(.antigravity(id))
        }
        guard let url = candidate.url, await available(url) else { return nil }
        return candidate
    }

    static func available(_ url: URL) async -> Bool {
        if let id = ClaudeTerminalNavigation.session(in: url) { return await ClaudeTerminalNavigation.perform(id, select: false) }
        guard let bundle = bundleID(for: url) else { return false }
        if isSidebar(url) {
            return await Task.detached(priority: .userInitiated) { IslandConversationSidebar.perform(url, press: false) }.value
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil else { return false }
        if url.scheme == "cursor.composer" {
            guard let id = UUID(uuidString: String(url.absoluteString.dropFirst("cursor.composer:".count))),
                  let client = IslandConversationEditor.client(.cursor), IslandConversationEditor.installed(client) else { return false }
            let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            return await Task.detached(priority: .utility) { IslandConversationTarget.cursorHasComposer(id, database: database) }.value
        }
        if url.scheme == "vscode-cascade-editor" {
            return IslandConversationEditor.client(.devinDesktop).map(IslandConversationEditor.installed) == true
        }
        return true
    }

    static func isSidebar(_ url: URL) -> Bool {
        url.scheme == "quotaview-dsh-row" || url.scheme == "quotaview-antigravity-row"
    }

    @MainActor static func open(_ url: URL) async -> Bool {
        if let id = ClaudeTerminalNavigation.session(in: url) { return await ClaudeTerminalNavigation.perform(id, select: true) }
        if isSidebar(url) {
            return await Task.detached(priority: .userInitiated) { IslandConversationSidebar.perform(url, press: true) }.value
        }
        let workspace = NSWorkspace.shared
        guard let bundle = bundleID(for: url), let app = workspace.urlForApplication(withBundleIdentifier: bundle) else { return false }
        if url.scheme == "cursor.composer" || url.scheme == "vscode-cascade-editor" {
            return await IslandConversationEditor.open(url: url, app: app)
        }
        return await withCheckedContinuation { continuation in
            workspace.open([url], withApplicationAt: app, configuration: .init()) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}

/// Check the official app's existing sidebar row before offering navigation.
enum IslandConversationSidebar {
    static func perform(_ url: URL, press: Bool) -> Bool {
        guard AXIsProcessTrusted(), let bundle = IslandConversationNavigation.bundleID(for: url),
              let id = url.pathComponents.last, IslandConversationTarget.isSessionID(id) else { return false }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
        guard apps.count == 1, let app = apps.first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.12)
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        // Electron exposes Chromium's full accessibility tree to assistive clients on demand.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        let dsh = url.scheme == "quotaview-dsh-row"
        let fields = [kAXRoleAttribute, kAXURLAttribute, "AXDOMIdentifier", kAXChildrenAttribute] as CFArray
        for window in windows {
            var pending: [(AXUIElement, URL?)] = [(window, nil)]
            while let (element, parentPage) = pending.popLast() {
                guard ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return false }
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(element, fields, [], &values) == .success,
                      let row = values as? [Any], row.count == 4, let role = row[0] as? String else { continue }
                var page = parentPage
                if role == "AXWebArea" {
                    guard parentPage == nil, let origin = row[1] as? URL,
                          dsh ? (origin.scheme == "dsh-app" && origin.host == "app")
                              : (origin.scheme == "https" && origin.host == "127.0.0.1") else { continue }
                    page = origin
                }
                if let page {
                    let link = row[1] as? URL
                    let matches = dsh ? row[2] as? String == "quotaview-session-" + id
                        : role == "AXLink" && link?.port == page.port && matchesAntigravity(link, session: id)
                    if matches {
                        var actions: CFArray?
                        guard AXUIElementCopyActionNames(element, &actions) == .success,
                              (actions as? [String])?.contains(kAXPressAction) == true else { continue }
                        guard press else { return true }
                        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { return false }
                        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        return app.isActive || app.activate(options: [])
                    }
                }
                if let children = row[3] as? [AXUIElement], !["AXStaticText", "AXTextArea", "AXImage"].contains(role) {
                    pending.append(contentsOf: children.reversed().map { ($0, page) })
                }
            }
        }
        return false
    }

    static func matchesAntigravity(_ url: URL?, session: String) -> Bool {
        guard let url, url.scheme == "https", url.host == "127.0.0.1", url.port != nil, url.user == nil, url.password == nil,
              let id = UUID(uuidString: session) else { return false }
        return url.path.lowercased() == "/c/" + id.uuidString.lowercased()
    }
}

/// VS Code-based clients have a session editor but don't register its internal
/// URI as a macOS URL scheme. A channel-owned URI handler opens that editor.
enum IslandConversationEditor {
    static let version = "1.0.0"
    static var name: String { "session-navigation-" + ClaudeCodeChannel.identifier.replacingOccurrences(of: ".", with: "-") }
    static var identifier: String { "quotaview." + name }

    struct Client {
        let provider: IslandAgentProvider
        let scheme: String
        let bundle: String
        let command: String
        let dataFolder: String

        var support: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/QuotaView/Channels/" + ClaudeCodeChannel.identifier + "/" + provider.rawValue) }
        var extensions: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(dataFolder + "/extensions") }
    }

    static func client(_ provider: IslandAgentProvider) -> Client? {
        switch provider {
        case .cursor: Client(provider: provider, scheme: "cursor", bundle: "com.todesktop.230313mzl4w4u92", command: "cursor", dataFolder: ".cursor")
        case .devinDesktop: Client(provider: provider, scheme: "devin", bundle: "com.exafunction.windsurf", command: "devin-desktop", dataFolder: ".devin")
        default: nil
        }
    }

    static let handler = #"""
const vscode = require('vscode');
const fs = require('node:fs/promises');
const path = require('node:path');
const {scheme, support} = require('./navigation.json');
exports.activate = context => {
  context.subscriptions.push(vscode.window.registerUriHandler({async handleUri(uri) {
    if (uri.scheme !== scheme || uri.path !== '/session') return;
    const nonce = new URLSearchParams(uri.query).get('request');
    if (!/^[a-f0-9-]{36}$/.test(nonce || '')) return;
    const base = path.join(support, 'open-' + nonce);
    let request;
    try { request = JSON.parse(await fs.readFile(base + '.json', 'utf8')); }
    catch { return; }
    if (!request || !Number.isFinite(request.expires) || Date.now() > request.expires || typeof request.session !== 'string' ||
        !/^[A-Za-z0-9_-]{1,128}$/.test(request.session)) return;
    let ok = false;
    try {
      const cursor = scheme === 'cursor';
      const resource = cursor ? vscode.Uri.from({scheme:'cursor.composer', path:request.session}) :
        vscode.Uri.from({scheme:'vscode-cascade-editor', path:'/cascade-devin-acp/devin-cli/' + request.session});
      const viewType = cursor ? 'workbench.editor.composer' : 'workbench.editor.cascadeEditor';
      await vscode.commands.executeCommand('vscode.openWith', resource, viewType, {preview:false});
      // Confirm the actual selected resource, including its provider and ID.
      const input = vscode.window.tabGroups.activeTabGroup.activeTab?.input;
      ok = input?.uri?.toString() === resource.toString();
      // Native workbench editors may expose an opaque TabInput. vscode.openWith
      // resolves after opening the exact resource with the requested editor.
      if (!input?.uri) ok = true;
    } catch { /* Report failure to the originating island button. */ }
    if (Date.now() <= request.expires) {
      await fs.writeFile(base + '.ack', ok ? '1' : '0', {flag:'wx',mode:0o600}).catch(() => {});
    }
  }}));
};
"""#

    static func installed(_ client: Client) -> Bool {
        let index = client.extensions.appendingPathComponent("extensions.json")
        guard let bytes = try? Data(contentsOf: index), bytes.count <= 8_388_608,
              let entries = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else { return false }
        return entries.contains { entry in
            guard (entry["identifier"] as? [String: Any])?["id"] as? String == identifier,
                  entry["version"] as? String == version,
                  let folder = entry["relativeLocation"] as? String, !folder.contains("/"), !folder.hasPrefix(".") else { return false }
            let file = client.extensions.appendingPathComponent(folder + "/extension.js")
            return (try? Data(contentsOf: file)) == Data(handler.utf8)
        }
    }

    static func package(for client: Client, in directory: URL) throws -> URL {
        let fm = FileManager.default, ext = directory.appendingPathComponent("extension")
        try fm.createDirectory(at: ext, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let manifest: [String: Any] = ["name": name, "publisher": "quotaview", "version": version,
            "displayName": "QuotaView Session Navigation", "engines": ["vscode": "^1.85.0"],
            "main": "./extension.js", "activationEvents": ["onUri"], "extensionKind": ["ui"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: ext.appendingPathComponent("package.json"))
        try JSONSerialization.data(withJSONObject: ["scheme": client.scheme, "support": client.support.path]).write(to: ext.appendingPathComponent("navigation.json"))
        try Data(handler.utf8).write(to: ext.appendingPathComponent("extension.js"))
        let metadata = """
        <PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"><Metadata>
        <Identity Language="en-US" Id="\(name)" Version="\(version)" Publisher="quotaview"/><DisplayName>QuotaView Session Navigation</DisplayName>
        <Description>Open a local QuotaView task in its session editor.</Description><Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.85.0"/></Properties>
        </Metadata><Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/><Assets>
        <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets></PackageManifest>
        """
        try Data(metadata.utf8).write(to: directory.appendingPathComponent("extension.vsixmanifest"))
        let types = #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="js" ContentType="application/javascript"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>"#
        try Data(types.utf8).write(to: directory.appendingPathComponent("[Content_Types].xml"))
        let archive = directory.appendingPathComponent("navigation.vsix")
        try run(URL(fileURLWithPath: "/usr/bin/zip"), ["-q", "-r", archive.path, "extension", "extension.vsixmanifest", "[Content_Types].xml"], cwd: directory)
        return archive
    }

    private static func run(_ command: URL, _ args: [String], cwd: URL? = nil) throws {
        let process = Process()
        process.executableURL = command
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { process.terminate(); throw CocoaError(.executableRuntimeMismatch) }
        if process.terminationStatus != 0 { throw CocoaError(.executableRuntimeMismatch) }
    }

    static func configure(_ provider: IslandAgentProvider, enabled: Bool) throws {
        guard let client = client(provider), installed(client) != enabled,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client.bundle) else { return }
        let cli = app.appendingPathComponent("Contents/Resources/app/bin/" + client.command)
        guard FileManager.default.isExecutableFile(atPath: cli.path) else { return }
        if !enabled { try run(cli, ["--uninstall-extension", identifier]); return }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let vsix = try package(for: client, in: temp)
        try run(cli, ["--install-extension", vsix.path])
    }

    @MainActor static func open(url: URL, app: URL) async -> Bool {
        let cursor = url.scheme == "cursor.composer"
        guard let client = client(cursor ? .cursor : .devinDesktop) else { return false }
        let session = cursor ? String(url.absoluteString.dropFirst("cursor.composer:".count)) : url.lastPathComponent
        guard IslandConversationTarget.isSessionID(session) else { return false }
        let nonce = UUID().uuidString.lowercased()
        let request = client.support.appendingPathComponent("open-" + nonce + ".json")
        let ack = client.support.appendingPathComponent("open-" + nonce + ".ack")
        defer { try? FileManager.default.removeItem(at: request); try? FileManager.default.removeItem(at: ack) }
        let deadline = Date().addingTimeInterval(35)
        guard let data = try? JSONSerialization.data(withJSONObject: ["session":session, "expires":deadline.timeIntervalSince1970 * 1000]),
              FileManager.default.createFile(atPath: request.path, contents: data, attributes: [.posixPermissions: 0o600]),
              let link = URL(string: client.scheme + "://" + identifier + "/session?request=" + nonce) else { return false }
        let dispatched = await withCheckedContinuation { continuation in
            NSWorkspace.shared.open([link], withApplicationAt: app, configuration: .init()) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
        guard dispatched else { return false }
        while Date() < deadline, !Task.isCancelled {
            if let bytes = try? Data(contentsOf: ack), !bytes.isEmpty { return bytes == Data("1".utf8) }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }
}
