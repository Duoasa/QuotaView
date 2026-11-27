import Combine
import Foundation
import QuotaViewCore

/// Keep one generation per provider while the page is open. Only build a heatmap
/// when its mode is displayed; hover and selection reuse the same model.
final class IslandUsageChartCache: ObservableObject {
    fileprivate struct Key: Equatable {
        let activity: [DailyTokenActivity]
        let lifetimeTokens: Int64?
        let utcDay: Double
    }

    final class Models {
        fileprivate let key: Key
        private let endingAt: Date
        private var heatmaps: [IslandActivityHeatmap.Mode: IslandActivityHeatmap] = [:]
        lazy var cost = EstimatedCostChartModel(activity: key.activity, endingAt: endingAt)

        fileprivate init(key: Key, endingAt: Date) {
            self.key = key
            self.endingAt = endingAt
        }

        func activity(mode: IslandActivityHeatmap.Mode) -> IslandActivityHeatmap {
            if let cached = heatmaps[mode] { return cached }
            let model = IslandActivityHeatmap(activity: key.activity, endingAt: endingAt,
                                             mode: mode, lifetimeTokens: key.lifetimeTokens)
            heatmaps[mode] = model
            return model
        }
    }

    private var generations: [IslandAgentProvider: Models] = [:]

    func models(provider: IslandAgentProvider, activity: [DailyTokenActivity], lifetimeTokens: Int64?, endingAt: Date) -> Models {
        let key = Key(activity: activity, lifetimeTokens: lifetimeTokens,
                      utcDay: floor(endingAt.timeIntervalSince1970 / 86_400))
        if let cached = generations[provider], key == cached.key { return cached }
        let models = Models(key: key, endingAt: endingAt)
        generations[provider] = models
        return models
    }
}

struct IslandActivityHeatmap {
    enum Mode: CaseIterable { case daily, weekly, cumulative }
    struct Cell { let date: Date; let tokens: Int64?; let future: Bool }
    struct Month { let column: Int; let date: Date }
    static let gap: CGFloat = 3
    static func cellSize(width: CGFloat) -> CGFloat { max(1, (width - gap * 52) / 53) }
    static func chartHeight(width: CGFloat) -> CGFloat { cellSize(width: width) * 7 + gap * 6 + 21 }
    let cells: [Cell]
    let months: [Month]
    let maximum: Int64
    let rows = 7
    let mode: Mode
    func cellIndex(column: Int, row: Int) -> Int { mode == .daily ? column * 7 + row : column }
    func cellIndex(at point: CGPoint, size: CGFloat) -> Int? {
        let pitch = size + Self.gap
        guard point.x >= 0, point.y >= 0, point.x < 53 * pitch, point.y < CGFloat(rows) * pitch else { return nil }
        let column = Int(point.x / pitch), row = Int(point.y / pitch)
        guard point.x - CGFloat(column) * pitch < size, point.y - CGFloat(row) * pitch < size else { return nil }
        let index = cellIndex(column: column, row: row)
        return cells[index].future ? nil : index
    }
    func isFilled(column: Int, row: Int) -> Bool {
        guard let value = cells[cellIndex(column: column, row: row)].tokens, value > 0, maximum > 0 else { return false }
        let count = max(1, min(7, Int(ceil(Double(value) / Double(maximum) * 7))))
        return row >= 7 - count
    }
    init(activity: [DailyTokenActivity], endingAt: Date, mode: Mode, lifetimeTokens: Int64? = nil) {
        self.mode = mode
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: endingAt)
        let weekStart = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today) - 1), to: today)!
        let start = calendar.date(byAdding: .day, value: -52 * 7, to: weekStart)!
        var values: [Date: Int64] = [:]
        for item in activity where item.tokens >= 0 { values[calendar.startOfDay(for: item.date)] = item.tokens }
        func sum(_ values: [Int64]) -> Int64 {
            values.reduce(0) { result, value in
                let added = result.addingReportingOverflow(value)
                return added.overflow ? Int64.max : added.partialValue
            }
        }
        var daily: [Cell] = []
        for index in 0..<371 {
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            daily.append(.init(date: date, tokens: date > today ? nil : values[date], future: date > today))
        }
        if mode == .daily { cells = daily }
        else {
            // Carry pre-window usage into the cumulative series; never add daily cumulative values together.
            let windowTotal = sum(daily.compactMap(\.tokens))
            let earlier = values.filter { $0.key < start }.map(\.value)
            var running = lifetimeTokens.map { max(0, $0 - windowTotal) } ?? sum(earlier)
            var hasData = running > 0 || !earlier.isEmpty
            cells = (0..<53).map { column in
                let week = Array(daily[(column * 7)..<(column * 7 + 7)])
                let known = week.compactMap(\.tokens)
                let total = sum(known)
                if !known.isEmpty { hasData = true }
                running = sum([running, total])
                return .init(date: week[0].date,
                    tokens: mode == .weekly ? (known.isEmpty ? nil : total) : (hasData ? running : nil),
                    future: false)
            }
        }
        maximum = cells.compactMap(\.tokens).max() ?? 0
        var labels: [Month] = []
        for column in 0..<53 {
            let date = daily[column * 7].date
            if column == 0 || calendar.component(.month, from: date) != calendar.component(.month, from: daily[(column - 1) * 7].date) {
                if let last = labels.last, column - last.column < 3 { labels.removeLast() }
                labels.append(.init(column: column, date: date))
            }
        }
        months = labels
    }
}
