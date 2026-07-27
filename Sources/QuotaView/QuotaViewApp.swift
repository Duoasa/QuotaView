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
                preferences: appDelegate.preferences
            )
            .environment(\.locale, appDelegate.preferences.locale)
        }
    }
}

@MainActor
final class QuotaViewAppDelegate: NSObject, NSApplicationDelegate {
    let store = CodexStatusStore()
    let preferences = AppPreferences()

    private var menuBarController: MenuBarPanelController?

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        AstaSansFontRegistrar.registerBundledFonts()
        store.start()
        menuBarController = MenuBarPanelController(
            store: store,
            preferences: preferences
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}
