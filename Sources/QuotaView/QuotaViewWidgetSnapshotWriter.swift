#if canImport(QuotaViewWidgetContract)
import QuotaViewWidgetContract
#endif

import Foundation
import OSLog
import QuotaViewCore
import WidgetKit

struct QuotaViewWidgetSnapshotProjector {
    func makeSnapshot(
        presentation: CurrentCodexPresentation?,
        isAvailable: Bool,
        localeIdentifier: String,
        now: Date
    ) -> QuotaViewWidgetSnapshot {
        guard isAvailable, let presentation else {
            return QuotaViewWidgetSnapshot(
                generatedAt: now,
                expiresAt: now.addingTimeInterval(
                    QuotaViewWidgetConfiguration.snapshotLifetime
                ),
                updatedAt: nil,
                localeIdentifier: localeIdentifier,
                availability: .unavailable,
                provider: nil
            )
        }

        let normalizedPlan = OpenAIPlanDisplayName.resolve(
            presentation.planType
        )
        let metricFormatter = WidgetMetricFormatter(
            localeIdentifier: localeIdentifier
        )
        return QuotaViewWidgetSnapshot(
            generatedAt: now,
            expiresAt: now.addingTimeInterval(
                QuotaViewWidgetConfiguration.snapshotLifetime
            ),
            updatedAt: presentation.lastUpdatedAt,
            localeIdentifier: localeIdentifier,
            availability: .available,
            provider: ProviderWidgetPayload(
                providerID: CodexDomainCatalog.providerID.rawValue,
                displayName: "Codex",
                plan: normalizedPlan,
                primaryWindow: WidgetQuotaWindow(
                    usedFraction: fraction(
                        fromPercent: presentation.usedPercent
                    ),
                    remainingFraction: fraction(
                        fromPercent: presentation.remainingPercent
                    ),
                    resetsAt: presentation.resetsAt
                ),
                auxiliaryMetrics: [
                    WidgetAuxiliaryMetric(
                        id: WidgetAuxiliaryMetricIdentifier
                            .creditsBalance,
                        label: metricFormatter.creditsBalanceLabel,
                        formattedValue: metricFormatter.creditBalance(
                            presentation
                        )
                    ),
                    WidgetAuxiliaryMetric(
                        id: WidgetAuxiliaryMetricIdentifier.todayTokens,
                        label: metricFormatter.todayTokensLabel,
                        formattedValue: metricFormatter.compactTokenCount(
                            presentation.recentDailyTokens
                        )
                    ),
                    WidgetAuxiliaryMetric(
                        id: WidgetAuxiliaryMetricIdentifier
                            .lifetimeTokens,
                        label: metricFormatter.lifetimeTokensLabel,
                        formattedValue: metricFormatter.compactTokenCount(
                            presentation.lifetimeTokens
                        )
                    )
                ]
            )
        )
    }

    private func fraction(fromPercent percent: Int) -> Double {
        Double(min(max(percent, 0), 100)) / 100
    }

}

private struct WidgetMetricFormatter {
    let localeIdentifier: String

    private var isChinese: Bool {
        localeIdentifier.lowercased().hasPrefix("zh")
    }

    var creditsBalanceLabel: String {
        isChinese ? "Credits 余额" : "Credits Balance"
    }

    var todayTokensLabel: String {
        isChinese ? "今日 Tokens" : "Today Tokens"
    }

    var lifetimeTokensLabel: String {
        isChinese ? "累计 Tokens" : "Lifetime Tokens"
    }

    func creditBalance(
        _ presentation: CurrentCodexPresentation
    ) -> String {
        if presentation.unlimitedCredits {
            return isChinese ? "无限" : "Unlimited"
        }
        return presentation.creditBalance ?? "—"
    }

    func compactTokenCount(_ count: Int64?) -> String {
        guard let count else {
            return "—"
        }

        let magnitude: Double
        let suffix: String
        switch abs(count) {
        case 1_000_000_000...:
            magnitude = Double(count) / 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            magnitude = Double(count) / 1_000_000
            suffix = "M"
        case 1_000...:
            magnitude = Double(count) / 1_000
            suffix = "K"
        default:
            return String(count)
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false

        return (formatter.string(from: magnitude as NSNumber) ?? "—")
            + suffix
    }
}

@MainActor
final class QuotaViewWidgetSnapshotWriter {
    typealias ContainerURLProvider = (String) -> URL?
    typealias TimelineReloader = (String) -> Void

    private struct ReloadSignature: Equatable {
        let availability: WidgetDataAvailability
        let localeIdentifier: String
        let provider: ProviderWidgetPayload?
    }

    private static let logger = Logger(
        subsystem: "com.quotaview.menubar",
        category: "widget-snapshot"
    )

    private let appGroupIdentifier: String
    private let containerURLProvider: ContainerURLProvider
    private let timelineReloader: TimelineReloader
    private let projector: QuotaViewWidgetSnapshotProjector
    private var lastReloadAt: Date?
    private var lastReloadSignature: ReloadSignature?
    private var didLogUnavailableContainer = false

    init(
        appGroupIdentifier: String? = nil,
        containerURLProvider: @escaping ContainerURLProvider = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: $0
            )
        },
        timelineReloader: @escaping TimelineReloader = {
            WidgetCenter.shared.reloadTimelines(ofKind: $0)
        },
        projector: QuotaViewWidgetSnapshotProjector =
            QuotaViewWidgetSnapshotProjector()
    ) {
        self.appGroupIdentifier =
            appGroupIdentifier ?? Self.configuredAppGroupIdentifier
        self.containerURLProvider = containerURLProvider
        self.timelineReloader = timelineReloader
        self.projector = projector
    }

    @discardableResult
    func publish(
        presentation: CurrentCodexPresentation?,
        isAvailable: Bool,
        localeIdentifier: String,
        now: Date = Date()
    ) -> Bool {
        guard !appGroupIdentifier.isEmpty,
              let containerURL = containerURLProvider(
                appGroupIdentifier
              )
        else {
            logUnavailableContainerOnce()
            return false
        }

        let snapshot = projector.makeSnapshot(
            presentation: presentation,
            isAvailable: isAvailable,
            localeIdentifier: localeIdentifier,
            now: now
        )

        do {
            try WidgetSnapshotFileStore(
                containerURL: containerURL
            ).write(snapshot)
        } catch {
            Self.logger.error(
                "Unable to write the sanitized widget snapshot."
            )
            return false
        }

        reloadTimelineIfNeeded(for: snapshot, now: now)
        return true
    }

    private func reloadTimelineIfNeeded(
        for snapshot: QuotaViewWidgetSnapshot,
        now: Date
    ) {
        let signature = ReloadSignature(
            availability: snapshot.availability,
            localeIdentifier: snapshot.localeIdentifier,
            provider: snapshot.provider
        )
        let reloadInterval =
            QuotaViewWidgetConfiguration.minimumTimelineReloadInterval
        let intervalElapsed = lastReloadAt.map {
            now.timeIntervalSince($0) >= reloadInterval
        } ?? true

        guard signature != lastReloadSignature || intervalElapsed else {
            return
        }

        lastReloadAt = now
        lastReloadSignature = signature
        timelineReloader(QuotaViewWidgetConfiguration.kind)
    }

    private func logUnavailableContainerOnce() {
        guard !didLogUnavailableContainer else {
            return
        }
        didLogUnavailableContainer = true
        Self.logger.notice(
            "The widget App Group container is unavailable in this signing environment."
        )
    }

    private static var configuredAppGroupIdentifier: String {
        Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewAppGroupIdentifier"
        ) as? String
            ?? QuotaViewWidgetConfiguration.defaultAppGroupIdentifier
    }
}
