import Foundation

/// Each service uses different units for its allowance, including amounts of money.
enum NativeQuotaResponse {
    typealias Object = [String: Any]
    typealias Window = AgentQuotaReport.Window

    static func number(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { return n.doubleValue }
        if let s = raw as? String, let n = Double(s), n.isFinite { return n }
        return nil
    }

    static func date(_ raw: Any?) -> Date? {
        if let n = number(raw), n > 0 {
            return Date(timeIntervalSince1970: n >= 1e12 ? n / 1000 : n)
        }
        guard let text = raw as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = iso.date(from: text) { return value }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: text.count == 10 ? text + "T00:00:00Z" : text)
    }

    private static func window(_ title: String, left: Double?, reset: Date?) -> Window? {
        guard let left, left.isFinite else { return nil }
        return Window(title: title, remaining: Int(min(100, max(0, left)).rounded()), resetsAt: reset)
    }

    private static func left(afterUsing used: Double?) -> Double? {
        guard let used, used >= 0 else { return nil }
        return 100 - used
    }

    private static func countRemaining(_ row: Object, total: String = "limit") -> Double? {
        guard let limit = number(row[total]), limit > 0 else { return nil }
        if let value = number(row["remaining"]), value >= 0 { return value / limit * 100 }
        return number(row["used"]).flatMap { left(afterUsing: $0 / limit * 100) }
    }

    static func report(for agent: IslandAgentProvider, json: Object, now: Date = Date()) -> AgentQuotaReport? {
        guard let source = agent.quotaSource else { return nil }
        var balance: String?
        let windows: [Window]
        switch agent {
        case .dsh:
            let balances = (json["balance_infos"] as? [Object] ?? []).compactMap { item -> (String, Double)? in
                guard let unit = item["currency"] as? String, !unit.isEmpty,
                      let amount = number(item["total_balance"]) else { return nil }
                return (unit, amount)
            }
            guard let value = balances.first(where: { $0.0 == "USD" && $0.1 > 0 })
                    ?? balances.first(where: { $0.1 > 0 }) ?? balances.first else { return nil }
            balance = String(format: "%.2f %@", locale: Locale(identifier: "en_US_POSIX"), value.1, value.0)
            windows = []
        case .kimiCode: windows = kimi(json)
        case .openCode: windows = openCode(json, now: now)
        case .copilotCLI: windows = copilot(json)
        case .cursor: windows = cursor(json, now: now)
        case .geminiCLI: windows = gemini(json)
        case .devinCLI, .devinDesktop: windows = devin(json)
        default: return nil
        }
        guard balance != nil || !windows.isEmpty else { return nil }
        return AgentQuotaReport(provider: source, windows: windows, balance: balance, updatedAt: now)
    }

    private static func kimi(_ json: Object) -> [Window] {
        let pools = json["usages"] as? Object ?? [:]
        var result: [Window] = []
        for (key, title) in [("limit_5h", "5-hour"), ("limit_7d", "Weekly"), ("limit_month_total", "Monthly")] {
            guard let pool = pools[key] as? Object, let ratio = number(pool["used_ratio"]),
                  let item = window(title, left: left(afterUsing: ratio * 100), reset: date(pool["reset_time"])) else { continue }
            result.append(item)
        }
        func addCounts(_ title: String, _ row: Object?) {
            guard let row, let item = window(title, left: countRemaining(row),
                reset: date(row["resetTime"] ?? row["reset_time"] ?? row["resetAt"] ?? row["reset_at"])) else { return }
            if let i = result.firstIndex(where: { $0.title == title }) {
                if let a = item.resetsAt, let b = result[i].resetsAt, abs(a.timeIntervalSince(b)) <= 2,
                   item.remaining < result[i].remaining { result[i] = item }
            } else { result.append(item) }
        }
        addCounts("Weekly", json["usage"] as? Object)
        for limit in json["limits"] as? [Object] ?? [] {
            guard let period = limit["window"] as? Object, let duration = number(period["duration"]),
                  let unit = period["timeUnit"] as? String,
                  let multiplier = ["TIME_UNIT_HOUR": 60.0, "TIME_UNIT_MINUTE": 1.0, "TIME_UNIT_DAY": 1440.0][unit],
                  let minutes = Int(exactly: duration * multiplier), minutes > 0 else { continue }
            let title = minutes == 300 ? "5-hour" : minutes == 10080 ? "Weekly" : "\(minutes) min"
            addCounts(title, limit["detail"] as? Object)
        }
        return result
    }

    private static func openCode(_ json: Object, now: Date) -> [Window] {
        guard let usage = json["usage"] as? Object else { return [] }
        return [("rolling", "5-hour"), ("weekly", "Weekly"), ("monthly", "Monthly")].compactMap { key, title in
            guard let row = usage[key] as? Object else { return nil }
            let used = ["usagePercent", "usedPercent", "percentUsed", "percent", "usage_percent", "used_percent",
                        "utilization", "utilizationPercent", "utilization_percent", "usage"].lazy.compactMap { number(row[$0]) }.first
            let seconds = ["resetInSec", "resetInSeconds", "resetSeconds", "reset_in_sec"].lazy.compactMap { number(row[$0]) }.first
            let reset = date(row["resetsAt"] ?? row["resetAt"]) ?? seconds.flatMap { $0 >= 0 ? now.addingTimeInterval($0) : nil }
            let consumed = ["used", "usage", "consumed", "count", "usedTokens", "usedMicroCents"].lazy.compactMap { number(row[$0]) }.first
            let limit = ["limit", "total", "quota", "max", "cap", "tokenLimit", "limitMicroCents"].lazy.compactMap { number(row[$0]) }.first
            let calculated = limit.flatMap { cap in cap > 0 ? consumed.map { $0 / cap * 100 } : nil }
            return window(title, left: left(afterUsing: used ?? calculated) ?? countRemaining(row), reset: reset)
        }
    }

    private static func copilot(_ json: Object) -> [Window] {
        let quotas = json["quota_snapshots"] as? Object ?? [:]
        let limits = json["monthly_quotas"] as? Object ?? [:]
        let available = json["limited_user_quotas"] as? Object ?? [:]
        return [("premium_interactions", "Premium"), ("chat", "Chat")].compactMap { key, title in
            let row = quotas[key] as? Object ?? [:]
            let reset = date(json["quota_reset_date"])
            if row["unlimited"] as? Bool == true { return nil }
            if let total = number(row["entitlement"]), total == 0, number(row["remaining"]) == 0 { return nil }
            if let p = number(row["percent_remaining"]) ?? countRemaining(row, total: "entitlement") {
                return window(title, left: p, reset: reset)
            }
            guard let cap = number(limits[key]), cap > 0, let left = number(available[key]) else { return nil }
            return window(title, left: left / cap * 100, reset: reset)
        }
    }

    private static func cursor(_ json: Object, now: Date) -> [Window] {
        let individual = json["individualUsage"] as? Object ?? [:]
        let plan = individual["plan"] as? Object ?? [:]
        let reset = date(json["billingCycleEnd"])
        let sand = json["sand"] as? Object ?? [:]
        let sandEnd = date(sand["nextResetTimestampUtc"])
        let included = (sand["includedLimitZero"] as? Bool).map { !$0 } ?? sand["hasNonZeroIncludedLimit"] as? Bool
        let trial = included != true && date(sand["sandTrialExpiresAt"]).map { $0 > now } == true
        let weekly = included == true || trial
            ? window("Weekly", left: left(afterUsing: number(sand["usagePercent"])), reset: trial ? nil : sandEnd) : nil
        if let legacy = json["requests"] as? Object, let used = number(legacy["numRequestsTotal"] ?? legacy["numRequests"]),
           let cap = number(legacy["maxRequestUsage"]), cap > 0 {
            return [window("Requests", left: left(afterUsing: used / cap * 100), reset: reset), weekly].compactMap { $0 }
        }
        if sand["isUnified"] as? Bool == true, let weekly, let sandEnd, sandEnd > now { return [weekly] }
        var results: [Window] = []
        if plan["enabled"] as? Bool != false, json["isUnlimited"] as? Bool != true {
            let included = left(afterUsing: number(plan["totalPercentUsed"])) ?? countRemaining(plan)
            results = [window("Plan", left: included, reset: reset),
                       window("Auto", left: left(afterUsing: number(plan["autoPercentUsed"])), reset: reset),
                       window("API", left: left(afterUsing: number(plan["apiPercentUsed"])), reset: reset)].compactMap { $0 }
        }
        if let cap = individual["overall"] as? Object, cap["enabled"] as? Bool != false,
           let item = window("Personal limit", left: countRemaining(cap), reset: reset) { results.append(item) }
        if let weekly { results.append(weekly) }
        return results
    }

    private static func gemini(_ json: Object) -> [Window] {
        let buckets = json["buckets"] as? [Object] ?? []
        var lowest: [String: (Double, Date?)] = [:]
        for bucket in buckets {
            guard let model = (bucket["modelId"] as? String)?.lowercased(), let left = number(bucket["remainingFraction"]),
                  (0...1).contains(left) else { continue }
            let tier: String
            if model.contains("flash-lite") { tier = "Flash Lite" }
            else if model.contains("flash") { tier = "Flash" }
            else if model.contains("pro") { tier = "Pro" }
            else { continue }
            if lowest[tier].map({ $0.0 <= left }) != true { lowest[tier] = (left, date(bucket["resetTime"])) }
        }
        return ["Pro", "Flash", "Flash Lite"].compactMap { tier in
            lowest[tier].flatMap { window(tier, left: $0.0 * 100, reset: $0.1) }
        }
    }

    private static func devin(_ json: Object) -> [Window] {
        ["daily", "weekly"].compactMap { period in
            if period == "daily" && json["hide_daily_quota"] as? Bool == true { return nil }
            let nested = (json[period] ?? (json["quotas"] as? Object)?[period]) as? Object ?? [:]
            let raw = number(json[period + "_percentage"])
            let used = raw.map { $0 < 1 ? $0 * 100 : $0 }
            let nestedUsed = number(nested["used_percent"] ?? nested["usedPercent"]).map { $0 <= 1 ? $0 * 100 : $0 }
            let left = Self.left(afterUsing: used ?? nestedUsed) ?? countRemaining(nested)
            return window(period.capitalized, left: left, reset: date(json[period + "_reset_at"] ?? nested["resets_at"]))
        }
    }
}
