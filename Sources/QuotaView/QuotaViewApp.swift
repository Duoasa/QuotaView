import SwiftUI

@main
@MainActor
struct QuotaViewApp: App {
    @StateObject private var store: CodexStatusStore

    init() {
        let statusStore = CodexStatusStore()
        _store = StateObject(wrappedValue: statusStore)
        statusStore.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Image(systemName: store.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel(store.accessibilityStatus)
        }
        .menuBarExtraStyle(.window)
    }
}
