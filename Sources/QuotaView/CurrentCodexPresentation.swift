import Foundation
import QuotaViewCore

struct DailyTokenActivity: Equatable, Sendable, Identifiable {
    let date: Date
    let tokens: Int64

    var id: Date { date }
}

struct CurrentCodexPresentation: Equatable, Sendable {
    enum Availability: String, Equatable, Sendable {
        case ready
        case limited
        case exhausted

        var displayName: String {
            switch self {
            case .ready: "可用"
            case .limited: "接近限额"
            case .exhausted: "额度已耗尽"
            }
        }
    }

    let availability: Availability
    let planType: String
    let usedPercent: Int
    let remainingPercent: Int
    let windowDurationMinutes: Int?
    let resetsAt: Date?
    let creditBalance: String?
    let hasCredits: Bool
    let unlimitedCredits: Bool
    let availableResetCredits: Int?
    let lifetimeTokens: Int64?
    let recentDailyTokens: Int64?
    let recentDailyDate: String?
    let tokenActivity: [DailyTokenActivity]
    let lastUpdatedAt: Date

    var canUseResetCredit: Bool {
        availableResetCredits.map { $0 > 0 } ?? false
    }

    var availableResetCreditsAfterOne: Int {
        max(0, (availableResetCredits ?? 0) - 1)
    }
}

struct CurrentCodexPresentationProjector {
    func makePresentation(
        from result: ProviderFetchResult
    ) -> CurrentCodexPresentation? {
        let snapshot = result.snapshot
        guard snapshot.providerID == CodexDomainCatalog.providerID,
              snapshot.availability == .available,
              let primaryWindow = snapshot.rateWindows.first(
                where: {
                    $0.id == CodexDomainCatalog.primaryRateWindowID
                }
              ),
              let usedFraction = primaryWindow.usedFraction,
              let remainingFraction = primaryWindow.remainingFraction
        else {
            return nil
        }

        let availability: CurrentCodexPresentation.Availability
        switch primaryWindow.quotaRisk {
        case .exhausted:
            availability = .exhausted
        case .warning:
            availability = .limited
        case .normal, .unknown:
            availability = .ready
        }

        let creditBalance = snapshot.balances.first(
            where: { $0.kind == .credits }
        )
        let latestDailyObservation = result.historicalObservations
            .filter {
                $0.definitionID == CodexDomainCatalog.dailyTokensID
            }
            .max(by: { $0.observedAt < $1.observedAt })
        let tokenActivity = tokenActivity(
            from: result.historicalObservations
        )

        return CurrentCodexPresentation(
            availability: availability,
            planType: snapshot.plan?.rawValue ?? "unknown",
            usedPercent: percent(from: usedFraction),
            remainingPercent: percent(from: remainingFraction),
            windowDurationMinutes: durationMinutes(
                primaryWindow.period
            ),
            resetsAt: primaryWindow.resetsAt,
            creditBalance: decimalString(creditBalance?.value),
            hasCredits: creditBalance?.hasBalance ?? false,
            unlimitedCredits: creditBalance?.isUnlimited ?? false,
            availableResetCredits: intValue(
                metric(
                    CodexDomainCatalog.resetCreditsID,
                    in: snapshot
                )
            ),
            lifetimeTokens: int64Value(
                metric(
                    CodexDomainCatalog.lifetimeTokensID,
                    in: snapshot
                )
            ),
            recentDailyTokens: int64Value(
                metric(
                    CodexDomainCatalog.dailyTokensID,
                    in: snapshot
                )
            ),
            recentDailyDate: latestDailyObservation.map {
                Self.dailyDateFormatter.string(from: $0.observedAt)
            },
            tokenActivity: tokenActivity,
            lastUpdatedAt: snapshot.capturedAt
        )
    }

    private func tokenActivity(
        from observations: [MetricObservation]
    ) -> [DailyTokenActivity] {
        var valuesByDay: [Date: Int64] = [:]

        for observation in observations
        where observation.definitionID == CodexDomainCatalog.dailyTokensID {
            guard case .count(let tokens) = observation.value,
                  tokens >= 0
            else {
                continue
            }

            let sourceDate = observation.interval?.start
                ?? observation.observedAt
            let day = Self.utcCalendar.startOfDay(for: sourceDate)
            valuesByDay[day] = tokens
        }

        return valuesByDay
            .map { DailyTokenActivity(date: $0.key, tokens: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func metric(
        _ id: MetricID,
        in snapshot: ProviderSnapshot
    ) -> MetricValue? {
        snapshot.currentMetrics.first(
            where: { $0.definitionID == id }
        )?.value
    }

    private func int64Value(_ value: MetricValue?) -> Int64? {
        guard case .count(let count) = value else {
            return nil
        }
        return count
    }

    private func intValue(_ value: MetricValue?) -> Int? {
        guard let count = int64Value(value),
              count <= Int64(Int.max),
              count >= Int64(Int.min)
        else {
            return nil
        }
        return Int(count)
    }

    private func percent(from fraction: Double) -> Int {
        min(max(Int((fraction * 100).rounded()), 0), 100)
    }

    private func durationMinutes(_ period: WindowPeriod) -> Int? {
        guard case .duration(let minutes) = period else {
            return nil
        }
        return minutes
    }

    private func decimalString(_ value: MetricValue?) -> String? {
        guard case .decimal(let decimal) = value else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).stringValue
    }

    private static let dailyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
