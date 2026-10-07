import Foundation
import QuotaViewCore

struct DailyTokenActivity: Equatable, Sendable, Identifiable {
    let date: Date
    let tokens: Int64
    /// Model-priced estimate when the source knows each token's model; nil
    /// there means an unpriced model, never the generic token-rate estimate.
    var modelPriced = false
    var estimatedCost: Double? = nil

    var id: Date { date }
}

struct CodexQuotaWindowPresentation: Equatable, Sendable, Identifiable {
    let id: EntityID
    let usedPercent: Int
    let remainingPercent: Int
    let windowDurationMinutes: Int?
    let resetsAt: Date?
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
    let quotaWindows: [CodexQuotaWindowPresentation]
    let sparkQuota: CodexQuotaWindowPresentation?
    let creditBalance: String?
    let hasCredits: Bool
    let unlimitedCredits: Bool
    let availableResetCredits: Int?
    let lifetimeTokens: Int64?
    let recentDailyTokens: Int64?
    let recentDailyDate: String?
    let tokenActivity: [DailyTokenActivity]
    let lastUpdatedAt: Date

    var weeklyRemainingPercent: Int? {
        quotaWindows.first { $0.windowDurationMinutes == 7 * 24 * 60 }?.remainingPercent
            ?? (windowDurationMinutes == 7 * 24 * 60 ? remainingPercent : nil)
    }

    var canUseResetCredit: Bool {
        availableResetCredits.map { $0 > 0 } ?? false
    }

    var availableResetCreditsAfterOne: Int {
        max(0, (availableResetCredits ?? 0) - 1)
    }
}

// Island content may retain the last successful read, while current-status
// indicators and account operations continue to require a successful latest read.
struct IslandUsagePresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case loading
        case current
        case stale(ProviderError)
        case unavailable(ProviderError)

        var isCurrent: Bool { self == .current }
        var isStale: Bool {
            if case .stale = self { return true }
            return false
        }
        func message(copy: AppCopy) -> String {
            switch self {
            case .loading: return copy.text("正在读取用量…", "Loading usage…")
            case .current: return ""
            case .stale(let error), .unavailable(let error):
                switch error {
                case .timedOut: return copy.text("读取 Codex 状态超时", "Codex status read timed out")
                case .processExited: return copy.text("Codex 数据连接已断开", "Codex data connection disconnected")
                case .notConfigured: return copy.text("找不到 Codex 程序", "Codex executable not found")
                case .permissionDenied: return copy.text("Codex 拒绝了读取请求，请检查登录状态", "Codex denied the read request; check sign-in")
                case .protocolViolation, .unsupportedSchema: return copy.text("Codex 数据格式不兼容", "Unsupported Codex data format")
                case .cancelled: return copy.text("读取已取消", "Read cancelled")
                case .transient: return copy.text("Codex 暂未返回用量", "Codex usage temporarily unavailable")
                case .unavailable: return copy.text("暂时无法连接 Codex", "Codex temporarily unreachable")
                }
            }
        }
    }
    let snapshot: CurrentCodexPresentation?
    let state: State
    static let loading = Self(snapshot: nil, state: .loading)

    func failed(_ error: ProviderError) -> Self {
        switch error {
        case .unavailable, .timedOut, .processExited, .transient, .cancelled:
            if let snapshot { return Self(snapshot: snapshot, state: .stale(error)) }
        case .notConfigured, .permissionDenied, .protocolViolation, .unsupportedSchema:
            break
        }
        return Self(snapshot: nil, state: .unavailable(error))
    }
}

extension ProviderError {
    // Persist only this category across successful reads, never a response body.
    var islandDiagnosticCategory: String {
        switch self {
        case .unavailable: "unavailable"
        case .notConfigured: "notConfigured"
        case .timedOut: "timedOut"
        case .processExited: "processExited"
        case .protocolViolation: "protocolViolation"
        case .unsupportedSchema: "unsupportedSchema"
        case .permissionDenied: "permissionDenied"
        case .cancelled: "cancelled"
        case .transient: "transient"
        }
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
        let tokenActivity = tokenActivity(
            from: result.historicalObservations
        )
        let latestDailyActivity = tokenActivity.last
        let quotaWindows = coreQuotaWindows(from: snapshot)
        let sparkQuota = snapshot.rateWindows
            .first(where: {
                $0.id == CodexDomainCatalog.sparkRateWindowID
            })
            .flatMap(quotaWindowPresentation)

        return CurrentCodexPresentation(
            availability: availability,
            planType: snapshot.plan?.rawValue ?? "unknown",
            usedPercent: percent(from: usedFraction),
            remainingPercent: percent(from: remainingFraction),
            windowDurationMinutes: durationMinutes(
                primaryWindow.period
            ),
            resetsAt: primaryWindow.resetsAt,
            quotaWindows: quotaWindows,
            sparkQuota: sparkQuota,
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
            recentDailyTokens: latestDailyActivity?.tokens,
            recentDailyDate: latestDailyActivity.map {
                Self.dailyDateFormatter.string(from: $0.date)
            },
            tokenActivity: tokenActivity,
            lastUpdatedAt: snapshot.capturedAt
        )
    }

    private func quotaWindowPresentation(
        _ window: RateWindow
    ) -> CodexQuotaWindowPresentation? {
        guard let usedFraction = window.usedFraction,
              let remainingFraction = window.remainingFraction
        else {
            return nil
        }

        return CodexQuotaWindowPresentation(
            id: window.id,
            usedPercent: percent(from: usedFraction),
            remainingPercent: percent(from: remainingFraction),
            windowDurationMinutes: durationMinutes(window.period),
            resetsAt: window.resetsAt
        )
    }

    private func coreQuotaWindows(
        from snapshot: ProviderSnapshot
    ) -> [CodexQuotaWindowPresentation] {
        let stableOrder = [
            CodexDomainCatalog.primaryRateWindowID: 0,
            CodexDomainCatalog.secondaryRateWindowID: 1
        ]

        return snapshot.rateWindows
            .filter { stableOrder[$0.id] != nil }
            .compactMap(quotaWindowPresentation)
            .sorted { left, right in
                let leftDuration = left.windowDurationMinutes ?? Int.max
                let rightDuration = right.windowDurationMinutes ?? Int.max
                if leftDuration != rightDuration {
                    return leftDuration < rightDuration
                }
                return stableOrder[left.id, default: Int.max]
                    < stableOrder[right.id, default: Int.max]
            }
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
            let (combinedTokens, overflow) = valuesByDay[
                day,
                default: 0
            ].addingReportingOverflow(tokens)
            guard !overflow else { continue }
            valuesByDay[day] = combinedTokens
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
