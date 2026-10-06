import AppKit
import SwiftUI

@MainActor
final class QuotaViewSettingsWindowController {
    private let store: CodexStatusStore
    private let preferences: AppPreferences
    private let activityRuntime: CodexActivityRuntime
    private let updateController: AppUpdateController
    private var settingsWindowController: NSWindowController?

    init(store: CodexStatusStore, preferences: AppPreferences, activityRuntime: CodexActivityRuntime, updateController: AppUpdateController) {
        self.store = store; self.preferences = preferences
        self.activityRuntime = activityRuntime; self.updateController = updateController
    }

    func openSettings() {
        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
        } else {
            let rootView = QuotaViewSettingsWindowRoot(
                store: store,
                preferences: preferences,
                activityRuntime: activityRuntime,
                updateController: updateController
            )
            let hostingController = NSHostingController(
                rootView: rootView
            )
            let window = NSWindow(
                contentViewController: hostingController
            )
            window.title = preferences.copy.text(
                "QuotaView 设置",
                "QuotaView Settings"
            )
            window.styleMask = [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
            window.isMovableByWindowBackground = true
            SettingsWindowMetrics.applyOuterShape(to: window)
            window.minSize = NSSize(width: 780, height: 560)
            window.setContentSize(
                NSSize(width: 872, height: 637)
            )
            window.isReleasedWhenClosed = false
            window.center()

            let controller = NSWindowController(window: window)
            settingsWindowController = controller
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct QuotaViewSettingsWindowRoot: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var activityRuntime: CodexActivityRuntime
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        SettingsView(
            store: store,
            preferences: preferences,
            activityRuntime: activityRuntime,
            updateController: updateController
        )
        .environment(\.locale, preferences.locale)
    }
}
