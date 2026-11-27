import Foundation

struct EstimatedCostChartModel: Equatable {
    private static let dayCount = 30
    private static let cachedInputUSDPerMillionTokens = 0.50

    struct Day: Identifiable, Equatable {
        let date: Date
        let tokens: Int64?
        let estimatedCost: Double?

        var id: Date { date }
    }

    let days: [Day]
    let todayCost: Double?
    let latestCost: Double?
    let periodTokens: Int64?
    let periodCost: Double?
    let maximumCost: Double

    init(
        activity: [DailyTokenActivity],
        endingAt endDate: Date
    ) {
        let normalizedEnd = Self.utcCalendar.startOfDay(for: endDate)
        let startDate = Self.utcCalendar.date(
            byAdding: .day,
            value: -(Self.dayCount - 1),
            to: normalizedEnd
        ) ?? normalizedEnd
        var activityByDay: [Date: Int64] = [:]
        var pricedCosts: [Date: Double?] = [:]
        for value in activity {
            let day = Self.utcCalendar.startOfDay(for: value.date)
            activityByDay[day] = value.tokens
            if value.modelPriced { pricedCosts[day] = .some(value.estimatedCost) }
        }

        var resolvedDays: [Day] = []
        resolvedDays.reserveCapacity(Self.dayCount)
        var date = startDate
        for _ in 0..<Self.dayCount {
            let tokens = activityByDay[date]
            resolvedDays.append(
                Day(
                    date: date,
                    tokens: tokens,
                    estimatedCost: pricedCosts[date] ?? tokens.flatMap(Self.estimatedCost)
                )
            )
            guard let nextDate = Self.utcCalendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }
            date = nextDate
        }

        days = resolvedDays
        todayCost = resolvedDays.last?.estimatedCost
        latestCost = resolvedDays.last(where: {
            $0.tokens != nil
        })?.estimatedCost
        let tokenCounts = resolvedDays.compactMap(\.tokens)
        periodTokens = tokenCounts.isEmpty
            ? nil
            : tokenCounts.reduce(0, +)
        let costs = resolvedDays.compactMap(\.estimatedCost)
        periodCost = costs.isEmpty ? nil : costs.reduce(0, +)
        maximumCost = costs.max() ?? 0
    }

    static func estimatedCost(tokens: Int64) -> Double? {
        guard tokens >= 0 else { return nil }
        return Double(tokens) / 1_000_000
            * Self.cachedInputUSDPerMillionTokens
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
