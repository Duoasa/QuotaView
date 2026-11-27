import AppKit
import SwiftUI

@MainActor
final class QuotaViewSettingsWindowController {
    private let store: CodexStatusStore
    private let preferences: AppPreferences
    private let activityRuntime: CodexActivityRuntime
    private let updateController: AppUpdateController
    private var settingsWindowController: NSWindowController?

    init(
        store: CodexStatusStore,
        preferences: AppPreferences,
        activityRuntime: CodexActivityRuntime,
        updateController: AppUpdateController
    ) {
        self.store = store
        self.preferences = preferences
        self.activityRuntime = activityRuntime
        self.updateController = updateController
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
            let window = QuotaViewSettingsWindow(
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
            SettingsWindowMetrics.configureTitlebar(of: window)
            window.isMovableByWindowBackground = true
            SettingsWindowMetrics.applyOuterShape(to: window)
            SettingsWindowMetrics.applySizingPolicy(to: window)
            window.setContentSize(
                SettingsWindowMetrics.defaultContentSize
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

enum SettingsWindowMetrics {
    // User-confirmed fixed width (2026-11-01).
    static let fixedContentWidth: CGFloat = 820
    static let defaultContentSize = NSSize(width: fixedContentWidth, height: 680)
    static let minimumContentSize = NSSize(width: fixedContentWidth, height: 680)
    static let outerCornerRadius: CGFloat = 24
    static let quitButtonInset: CGFloat = 10
    static let quitButtonCornerRadius = outerCornerRadius - quitButtonInset
    static let contentMaxWidth: CGFloat = 560
    static let contentInset: CGFloat = 20
    static let headerHeight: CGFloat = 52
    static let sidebarWidth: CGFloat = 180
    static let sidebarInset: CGFloat = 16
    static let fallbackSidebarCornerRadius: CGFloat =
        outerCornerRadius - sidebarInset

    @MainActor
    static func applyAppearance(_ mode: AppPreferences.IslandGlassAppearance, to window: NSWindow) {
        let name: NSAppearance.Name? = switch mode {
        case .light: .aqua
        case .dark: .darkAqua
        case .automatic: nil
        }
        if window.appearance?.name != name {
            window.appearance = name.flatMap(NSAppearance.init(named:))
        }
    }

    @MainActor
    static func applySizingPolicy(to window: NSWindow) {
        let maximumHeight = max(minimumContentSize.height, window.contentMaxSize.height)
        window.contentMinSize = minimumContentSize
        window.contentMaxSize = NSSize(width: fixedContentWidth, height: maximumHeight)
        window.collectionBehavior.remove([.fullScreenPrimary, .fullScreenAllowsTiling])
        window.collectionBehavior.insert([.fullScreenNone, .fullScreenDisallowsTiling])
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    @MainActor
    static func configureTitlebar(of window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        let identifier = NSToolbar.Identifier("QuotaViewSettingsToolbar")
        if window.toolbar?.identifier != identifier {
            let toolbar = NSToolbar(identifier: identifier)
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
    }

    @MainActor
    static func applyOuterShape(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = outerCornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        window.invalidateShadow()
    }
}

@MainActor
final class QuotaViewSettingsWindow: NSWindow {
    override func zoom(_ sender: Any?) {}
    override func toggleFullScreen(_ sender: Any?) {}
}
