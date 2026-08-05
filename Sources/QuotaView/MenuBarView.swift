import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences

    private let openSettingsAction: () -> Void

    private var copy: AppCopy { preferences.copy }

    init(
        store: CodexStatusStore,
        preferences: AppPreferences,
        openSettingsAction: @escaping () -> Void = {}
    ) {
        self.store = store
        self.preferences = preferences
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        QuotaViewFigmaMenu(
            store: store,
            preferences: preferences,
            copy: copy,
            refreshAction: refresh,
            openCodexAction: openCodex,
            openSettingsAction: showSettings,
            quitAction: quit
        )
    }

    private func showSettings() {
        openSettingsAction()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func refresh() {
        Task {
            await store.refresh()
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func openCodex() {
        let chatGPTURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard FileManager.default.fileExists(atPath: chatGPTURL.path) else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: chatGPTURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
