import AppKit
import QuotaViewCore
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
                navigation: appDelegate.settingsNavigation
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
    let settingsNavigation: SettingsNavigation

    private var menuBarController: MenuBarPanelController?
    private var isPreparingTermination = false

    override init() {
        let preferences = AppPreferences()
        let usageSource = CodexPluginUsageSnapshotSource()
        let settingsNavigation = SettingsNavigation()
        self.preferences = preferences
        self.settingsNavigation = settingsNavigation
        self.store = CodexStatusStore(
            provider: CodexPluginUsageProviderAdapter(
                loadSnapshot: {
                    try await usageSource.load()
                }
            ),
            preferences: preferences
        )
        self.activityRuntime = CodexActivityRuntime(preferences: preferences)
        super.init()
        activityRuntime.onBridgeConfigurationChanged = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.store.pluginDataConfigurationDidChange()
            }
        }
        activityRuntime.onUsageSnapshotChanged = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.store.refresh(
                    reason: .configurationChanged,
                    policy: .replace
                )
            }
        }
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        AstaSansFontRegistrar.registerBundledFonts()
        store.start()
        activityRuntime.start()
        menuBarController = MenuBarPanelController(
            store: store,
            preferences: preferences,
            activityRuntime: activityRuntime,
            settingsNavigation: settingsNavigation
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

    func application(
        _ application: NSApplication,
        open urls: [URL]
    ) {
        guard let pairingURL = urls.first(where: {
            $0.scheme?.lowercased() == "quotaview"
                && $0.host?.lowercased() == "pair"
        }) else { return }
        activityRuntime.handlePairingURL(pairingURL)
    }
}
