import AppKit
import SwiftUI

@main
@MainActor
struct QuotaViewApp: App {
    @NSApplicationDelegateAdaptor(QuotaViewAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                store: appDelegate.store,
                preferences: appDelegate.preferences,
                activityRuntime: appDelegate.activityRuntime,
                updateController: appDelegate.updateController
            )
            .environment(\.locale, appDelegate.preferences.locale)
        }
    }
}

@MainActor
final class QuotaViewAppDelegate: NSObject, NSApplicationDelegate {
    let store: CodexStatusStore
    let preferences: AppPreferences
    let activityRuntime: CodexActivityRuntime
    let updateController: AppUpdateController

    private var menuBarController: MenuBarPanelController?
    private var isPreparingTermination = false

    override init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        self.store = CodexStatusStore(preferences: preferences)
        self.activityRuntime = CodexActivityRuntime(
            preferences: preferences
        )
        self.updateController = AppUpdateController()
        super.init()
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        AstaSansFontRegistrar.registerBundledFonts()
        updateController.start()
        store.start()
        activityRuntime.start()
        menuBarController = MenuBarPanelController(
            store: store,
            preferences: preferences,
            activityRuntime: activityRuntime,
            updateController: updateController
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !isPreparingTermination else {
            return .terminateLater
        }

        isPreparingTermination = true
        Task {
            async let stopStatus: Void = store.stop()
            async let stopActivity: Void = activityRuntime.stop()
            _ = await (stopStatus, stopActivity)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
