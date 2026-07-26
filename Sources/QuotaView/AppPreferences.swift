import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppPreferences: ObservableObject {
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case light
        case dark

        var id: String { rawValue }

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum Language: String, CaseIterable, Identifiable {
        case simplifiedChinese
        case english

        var id: String { rawValue }

        var localeIdentifier: String {
            switch self {
            case .simplifiedChinese: "zh-Hans"
            case .english: "en"
            }
        }

        static var systemResolved: Language {
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
        }
    }

    enum MenuBarComponent {
        case statusIcon
        case remainingQuota
        case resetCountdown
    }

    private enum Key {
        static let showStatusIcon = "preferences.menuBar.showStatusIcon"
        static let showRemainingQuota = "preferences.menuBar.showRemainingQuota"
        static let showResetCountdown = "preferences.menuBar.showResetCountdown"
        static let showUsageSummary = "preferences.panel.showUsageSummary"
        static let showNextReset = "preferences.panel.showNextReset"
        static let showCreditBalance = "preferences.panel.showCreditBalance"
        static let showDailyTokens = "preferences.panel.showDailyTokens"
        static let showLifetimeTokens = "preferences.panel.showLifetimeTokens"
        static let showResetAction = "preferences.panel.showResetAction"
        static let followsSystemAppearance = "preferences.appearance.followsSystem"
        static let customAppearance = "preferences.appearance.custom"
        // Keep the previous key so older installations migrate without
        // creating a second preference. Legacy preset names normalize to
        // the default frosted mode.
        static let glassMode = "preferences.appearance.glassPreset"
        static let followsSystemLanguage = "preferences.language.followsSystem"
        static let customLanguage = "preferences.language.custom"
    }

    private let defaults: UserDefaults
    private var localeCancellable: AnyCancellable?

    @Published var showStatusIcon: Bool {
        didSet { defaults.set(showStatusIcon, forKey: Key.showStatusIcon) }
    }

    @Published var showRemainingQuota: Bool {
        didSet { defaults.set(showRemainingQuota, forKey: Key.showRemainingQuota) }
    }

    @Published var showResetCountdown: Bool {
        didSet { defaults.set(showResetCountdown, forKey: Key.showResetCountdown) }
    }

    @Published var showUsageSummary: Bool {
        didSet { defaults.set(showUsageSummary, forKey: Key.showUsageSummary) }
    }

    @Published var showNextReset: Bool {
        didSet { defaults.set(showNextReset, forKey: Key.showNextReset) }
    }

    @Published var showCreditBalance: Bool {
        didSet { defaults.set(showCreditBalance, forKey: Key.showCreditBalance) }
    }

    @Published var showDailyTokens: Bool {
        didSet { defaults.set(showDailyTokens, forKey: Key.showDailyTokens) }
    }

    @Published var showLifetimeTokens: Bool {
        didSet { defaults.set(showLifetimeTokens, forKey: Key.showLifetimeTokens) }
    }

    @Published var showResetAction: Bool {
        didSet { defaults.set(showResetAction, forKey: Key.showResetAction) }
    }

    @Published var followsSystemAppearance: Bool {
        didSet {
            defaults.set(
                followsSystemAppearance,
                forKey: Key.followsSystemAppearance
            )
            synchronizeApplicationAppearance()
        }
    }

    @Published var customAppearance: AppearanceMode {
        didSet {
            defaults.set(
                customAppearance.rawValue,
                forKey: Key.customAppearance
            )
            synchronizeApplicationAppearance()
        }
    }

    @Published var glassMode: QuotaViewGlassMode {
        didSet {
            defaults.set(
                glassMode.rawValue,
                forKey: Key.glassMode
            )
        }
    }

    @Published var followsSystemLanguage: Bool {
        didSet {
            defaults.set(
                followsSystemLanguage,
                forKey: Key.followsSystemLanguage
            )
        }
    }

    @Published var customLanguage: Language {
        didSet {
            defaults.set(
                customLanguage.rawValue,
                forKey: Key.customLanguage
            )
        }
    }

    @Published private(set) var systemLocaleRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showStatusIcon = defaults.storedBool(
            forKey: Key.showStatusIcon,
            defaultValue: true
        )
        showRemainingQuota = defaults.storedBool(
            forKey: Key.showRemainingQuota,
            defaultValue: true
        )
        showResetCountdown = defaults.storedBool(
            forKey: Key.showResetCountdown,
            defaultValue: false
        )
        showUsageSummary = defaults.storedBool(
            forKey: Key.showUsageSummary,
            defaultValue: true
        )
        showNextReset = defaults.storedBool(
            forKey: Key.showNextReset,
            defaultValue: true
        )
        showCreditBalance = defaults.storedBool(
            forKey: Key.showCreditBalance,
            defaultValue: true
        )
        showDailyTokens = defaults.storedBool(
            forKey: Key.showDailyTokens,
            defaultValue: true
        )
        showLifetimeTokens = defaults.storedBool(
            forKey: Key.showLifetimeTokens,
            defaultValue: true
        )
        showResetAction = defaults.storedBool(
            forKey: Key.showResetAction,
            defaultValue: true
        )
        followsSystemAppearance = defaults.storedBool(
            forKey: Key.followsSystemAppearance,
            defaultValue: true
        )
        customAppearance = AppearanceMode(
            rawValue: defaults.string(forKey: Key.customAppearance) ?? ""
        ) ?? .dark
        glassMode = QuotaViewGlassMode(
            rawValue: defaults.string(forKey: Key.glassMode) ?? ""
        ) ?? .frosted
        followsSystemLanguage = defaults.storedBool(
            forKey: Key.followsSystemLanguage,
            defaultValue: true
        )
        customLanguage = Language(
            rawValue: defaults.string(forKey: Key.customLanguage) ?? ""
        ) ?? .simplifiedChinese
        defaults.set(glassMode.rawValue, forKey: Key.glassMode)

        localeCancellable = NotificationCenter.default.publisher(
            for: NSLocale.currentLocaleDidChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.systemLocaleRevision += 1
        }

        synchronizeApplicationAppearance()
    }

    var resolvedLanguage: Language {
        _ = systemLocaleRevision
        return followsSystemLanguage ? .systemResolved : customLanguage
    }

    var locale: Locale {
        Locale(identifier: resolvedLanguage.localeIdentifier)
    }

    var copy: AppCopy {
        AppCopy(language: resolvedLanguage)
    }

    private func synchronizeApplicationAppearance() {
        // Keep AppKit as the single appearance authority. Layering a
        // SwiftUI preferredColorScheme on top can leave semantic foreground
        // colors stale when a fixed appearance is changed back to system.
        guard !followsSystemAppearance else {
            NSApplication.shared.appearance = nil
            return
        }

        let appearanceName: NSAppearance.Name = switch customAppearance {
        case .light: .aqua
        case .dark: .darkAqua
        }
        NSApplication.shared.appearance = NSAppearance(named: appearanceName)
    }

    func isVisible(_ component: MenuBarComponent) -> Bool {
        switch component {
        case .statusIcon: showStatusIcon
        case .remainingQuota: showRemainingQuota
        case .resetCountdown: showResetCountdown
        }
    }

    func canHide(_ component: MenuBarComponent) -> Bool {
        guard isVisible(component) else { return true }
        return visibleMenuBarComponentCount > 1
    }

    func binding(for component: MenuBarComponent) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.isVisible(component) ?? false
            },
            set: { [weak self] newValue in
                self?.setVisibility(newValue, for: component)
            }
        )
    }

    private var visibleMenuBarComponentCount: Int {
        [showStatusIcon, showRemainingQuota, showResetCountdown]
            .filter { $0 }
            .count
    }

    private func setVisibility(
        _ isVisible: Bool,
        for component: MenuBarComponent
    ) {
        if !isVisible, !canHide(component) {
            return
        }

        switch component {
        case .statusIcon:
            showStatusIcon = isVisible
        case .remainingQuota:
            showRemainingQuota = isVisible
        case .resetCountdown:
            showResetCountdown = isVisible
        }
    }
}

struct AppCopy {
    let language: AppPreferences.Language

    func text(_ simplifiedChinese: String, _ english: String) -> String {
        switch language {
        case .simplifiedChinese: simplifiedChinese
        case .english: english
        }
    }
}

private extension UserDefaults {
    func storedBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else { return defaultValue }
        return bool(forKey: key)
    }
}
