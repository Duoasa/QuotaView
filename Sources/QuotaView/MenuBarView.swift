import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var activityRuntime: CodexActivityRuntime

    private let openSettingsAction: () -> Void
    private let openCodexConnectionSettingsAction: () -> Void

    private var copy: AppCopy { preferences.copy }

    init(
        store: CodexStatusStore,
        preferences: AppPreferences,
        activityRuntime: CodexActivityRuntime,
        openSettingsAction: @escaping () -> Void = {},
        openCodexConnectionSettingsAction: @escaping () -> Void = {}
    ) {
        self.store = store
        self.preferences = preferences
        self.activityRuntime = activityRuntime
        self.openSettingsAction = openSettingsAction
        self.openCodexConnectionSettingsAction =
            openCodexConnectionSettingsAction
    }

    var body: some View {
        QuotaViewFigmaMenu(
            store: store,
            preferences: preferences,
            activityRuntime: activityRuntime,
            copy: copy,
            refreshAction: refresh,
            openCodexAction: openCodex,
            openSettingsAction: showSettings,
            openCodexConnectionSettingsAction: showCodexConnectionSettings,
            quitAction: quit
        )
    }

    private func showSettings() {
        openSettingsAction()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showCodexConnectionSettings() {
        openCodexConnectionSettingsAction()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func refresh() {
        activityRuntime.refreshConnectionStatus()
        Task {
            await store.refresh()
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func openCodex() {
        activityRuntime.openOfficialCodex()
    }
}
