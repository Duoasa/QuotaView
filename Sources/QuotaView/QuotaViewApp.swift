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
    private static var runtimeDisabledForTests: Bool {
        ProcessInfo.processInfo.environment["QUOTAVIEW_DISABLE_RUNTIME_FOR_TESTS"] == "1"
    }
    let store: CodexStatusStore
    let preferences: AppPreferences
    let activityRuntime: CodexActivityRuntime
    let updateController: AppUpdateController

    private var settingsWindowController: QuotaViewSettingsWindowController?
    private var isPreparingTermination = false

    override init() {
        let defaults = Self.runtimeDisabledForTests
            ? UserDefaults(suiteName: "com.quotaview.hosted-tests.\(ProcessInfo.processInfo.processIdentifier)")!
            : CodexActivityChannelIdentity.current.defaults
        let preferences = AppPreferences(defaults: defaults)
        if !Self.runtimeDisabledForTests,
           Bundle.main.bundleIdentifier == "com.quotaview.development073",
           defaults.object(forKey: "development073.initialized") == nil {
            preferences.codexActivityIslandEnabled = true
            defaults.set(true, forKey: "development073.initialized")
        }
        let statusStore = CodexStatusStore(preferences: preferences)
        self.preferences = preferences
        self.store = statusStore
        self.activityRuntime = CodexActivityRuntime(
            preferences: preferences,
            quotaStatusStore: statusStore,
            defaults: defaults
        )
        self.updateController = AppUpdateController()
        super.init()
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        guard !Self.runtimeDisabledForTests else { return }
        AstaSansFontRegistrar.registerBundledFonts()
        // The controller admits only the official, trusted Release identity.
        // Debug and isolated development builds remain inactive.
        updateController.start()
        let settings = QuotaViewSettingsWindowController(
            store: store,
            preferences: preferences,
            activityRuntime: activityRuntime,
            updateController: updateController
        )
        settingsWindowController = settings
        activityRuntime.onOpenSettings = { [weak settings] in settings?.openSettings() }
        store.start()
        activityRuntime.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController?.openSettings()
        return true
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
