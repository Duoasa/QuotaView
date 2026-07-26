import SwiftUI

@main
@MainActor
struct QuotaViewApp: App {
    @StateObject private var store: CodexStatusStore
    @StateObject private var preferences: AppPreferences

    init() {
        let statusStore = CodexStatusStore()
        let appPreferences = AppPreferences()
        _store = StateObject(wrappedValue: statusStore)
        _preferences = StateObject(wrappedValue: appPreferences)
        statusStore.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: store,
                preferences: preferences
            )
            .environment(\.locale, preferences.locale)
            .environment(
                \.quotaViewGlassMode,
                preferences.glassMode
            )
        } label: {
            MenuBarStatusLabel(
                store: store,
                preferences: preferences
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                store: store,
                preferences: preferences
            )
                .environment(\.locale, preferences.locale)
        }
    }
}
