import SwiftUI
import WidgetKit

private struct WidgetTextLineBox: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: height)
    }
}

private extension View {
    func widgetTextLineBox(height: CGFloat) -> some View {
        modifier(WidgetTextLineBox(height: height))
    }
}

struct QuotaViewWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaViewWidgetSnapshot?
    let isPlaceholder: Bool
}

struct QuotaViewWidgetProvider: TimelineProvider {
    func placeholder(
        in context: Context
    ) -> QuotaViewWidgetEntry {
        QuotaViewWidgetEntry(
            date: Date(),
            snapshot: nil,
            isPlaceholder: true
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (QuotaViewWidgetEntry) -> Void
    ) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(loadEntry(now: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<QuotaViewWidgetEntry>) -> Void
    ) {
        let now = Date()
        let entry = loadEntry(now: now)
        let earliestReload = now.addingTimeInterval(
            QuotaViewWidgetConfiguration.minimumTimelineReloadInterval
        )
        let latestReload = now.addingTimeInterval(
            QuotaViewWidgetConfiguration.snapshotLifetime
        )
        let snapshotExpiry = entry.snapshot?.expiresAt ?? latestReload
        let reloadDate = min(
            max(snapshotExpiry, earliestReload),
            latestReload
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(reloadDate)
            )
        )
    }

    private func loadEntry(now: Date) -> QuotaViewWidgetEntry {
        let appGroupIdentifier = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewAppGroupIdentifier"
        ) as? String
            ?? QuotaViewWidgetConfiguration.defaultAppGroupIdentifier
        guard !appGroupIdentifier.isEmpty,
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
              ),
              let snapshot = try? WidgetSnapshotFileStore(
                containerURL: containerURL
              ).read(now: now)
        else {
            return QuotaViewWidgetEntry(
                date: now,
                snapshot: nil,
                isPlaceholder: false
            )
        }

        return QuotaViewWidgetEntry(
            date: now,
            snapshot: snapshot,
            isPlaceholder: false
        )
    }
}

struct QuotaViewWidgetView: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    let entry: QuotaViewWidgetEntry

    private var copy: WidgetCopy {
        WidgetCopy(
            localeIdentifier: entry.snapshot?.localeIdentifier
                ?? Locale.current.identifier
        )
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme: colorScheme)
    }

    private var displayData: WidgetDisplayData {
        if entry.isPlaceholder {
            return .placeholder
        }

        guard let snapshot = entry.snapshot,
              snapshot.availability == .available,
              let provider = snapshot.provider,
              let window = provider.primaryWindow,
              let remainingFraction = window.remainingFraction
        else {
            return .unavailable(copy: copy)
        }

        return WidgetDisplayData(
            isAvailable: true,
            remainingFraction: remainingFraction,
            plan: normalizedPlan(provider.plan),
            resetText: copy.resetCountdown(window.resetsAt),
            footerText: copy.resetCountdown(window.resetsAt),
            creditsBalance: metricValue(
                WidgetAuxiliaryMetricIdentifier.creditsBalance,
                in: provider
            ),
            todayTokens: metricValue(
                WidgetAuxiliaryMetricIdentifier.todayTokens,
                in: provider
            ),
            lifetimeTokens: metricValue(
                WidgetAuxiliaryMetricIdentifier.lifetimeTokens,
                in: provider
            )
        )
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumContent(displayData)
            } else {
                smallContent(displayData)
            }
        }
        .padding(16)
        .redacted(
            reason: entry.isPlaceholder ? .placeholder : []
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(displayData))
        .accessibilityHidden(entry.isPlaceholder)
        .containerBackground(for: .widget) {
            palette.background
        }
    }

    private func smallContent(
        _ data: WidgetDisplayData
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(showsConnectionAtTrailingEdge: true, data: data)
            Spacer(minLength: 8)
            quotaSummary(data)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private func mediumContent(
        _ data: WidgetDisplayData
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                header(
                    showsConnectionAtTrailingEdge: false,
                    data: data
                )
                Spacer(minLength: 8)
                quotaSummary(data)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            Rectangle()
                .fill(palette.divider)
                .frame(width: 0.5)
                .padding(.vertical, 2)
                .accessibilityHidden(true)

            VStack(alignment: .trailing, spacing: 0) {
                connectionIndicator(isAvailable: data.isAvailable)
                Spacer(minLength: 8)
                VStack(spacing: 0) {
                    metricRow(
                        title: copy.nextReset,
                        value: data.resetText,
                        hasDivider: true
                    )
                    metricRow(
                        title: copy.creditsBalance,
                        value: data.creditsBalance,
                        hasDivider: true
                    )
                    metricRow(
                        title: copy.todayTokens,
                        value: data.todayTokens,
                        hasDivider: true
                    )
                    metricRow(
                        title: copy.lifetimeTokens,
                        value: data.lifetimeTokens,
                        hasDivider: false
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topTrailing
            )
        }
    }

    private func header(
        showsConnectionAtTrailingEdge: Bool,
        data: WidgetDisplayData
    ) -> some View {
        HStack(spacing: 4) {
            Image(palette.logoAssetName)
                .resizable()
                .frame(width: 10.875, height: 12)
                .accessibilityHidden(true)
            Text("QuotaView")
                .font(AstaSans.semiBold(12))
                .tracking(-0.12)
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .widgetTextLineBox(height: 12)
            if showsConnectionAtTrailingEdge {
                Spacer(minLength: 4)
                connectionIndicator(isAvailable: data.isAvailable)
            }
        }
        .frame(height: 12)
    }

    private func connectionIndicator(
        isAvailable: Bool
    ) -> some View {
        Circle()
            .fill(
                isAvailable
                    ? WidgetPalette.connected
                    : WidgetPalette.disconnected
            )
            .frame(width: 5, height: 5)
            .accessibilityLabel(
                isAvailable ? copy.connected : copy.disconnected
            )
    }

    private func quotaSummary(
        _ data: WidgetDisplayData
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                percentageText(data.remainingFraction)
                Spacer(minLength: 4)
                planTag(data.plan)
            }
            .frame(height: 40)

            Text(
                data.isAvailable
                    ? copy.weeklyRemaining
                    : copy.unavailable
            )
            .font(AstaSans.regular(weeklyLabelFontSize))
            .foregroundStyle(palette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .widgetTextLineBox(height: 10)

            quotaProgress(data.remainingFraction)

            HStack(alignment: .center, spacing: 4) {
                Image(palette.clockAssetName)
                    .resizable()
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(data.footerText)
                    .font(AstaSans.regular(11))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .widgetTextLineBox(height: 10)
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func percentageText(
        _ remainingFraction: Double?
    ) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if let remainingFraction {
                Text(percentNumberText(remainingFraction))
                    .font(AstaSans.semiBold(32))
                    .tracking(-0.32)
                    .frame(height: 40, alignment: .center)

                Text("%")
                    .font(AstaSans.semiBold(16))
                    .tracking(-0.16)
                    .frame(height: 32, alignment: .center)
            } else {
                Text("—")
                    .font(AstaSans.semiBold(32))
                    .tracking(-0.32)
                    .frame(height: 40, alignment: .center)
            }
        }
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)
        .contentTransition(.numericText())
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: 0.24),
            value: remainingFraction
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percentText(remainingFraction))
    }

    private func planTag(_ plan: String?) -> some View {
        Text(plan ?? "—")
            .font(AstaSans.semiBold(9))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .widgetTextLineBox(height: 8)
            .padding(4)
            .background(
                RoundedRectangle(
                    cornerRadius: 4,
                    style: .continuous
                )
                .fill(palette.tagFill)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 4,
                    style: .continuous
                )
                .strokeBorder(palette.tagBorder, lineWidth: 0.5)
            }
            .accessibilityLabel(
                copy.planAccessibility(plan ?? "—")
            )
    }

    private var weeklyLabelFontSize: CGFloat {
        colorScheme == .dark ? 11 : 10
    }

    private func quotaProgress(
        _ remainingFraction: Double?
    ) -> some View {
        GeometryReader { proxy in
            let fraction = remainingFraction.map {
                min(max($0, 0), 1)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(
                    cornerRadius: 4,
                    style: .continuous
                )
                .fill(
                    palette.progressTrack
                        .shadow(
                            .inner(
                                color: Color.black.opacity(0.12),
                                radius: 30,
                                x: -3.75,
                                y: -3
                            )
                        )
                )

                if let fraction, fraction > 0 {
                    if fraction < 1 {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 4,
                                bottomLeading: 4,
                                bottomTrailing: 2,
                                topTrailing: 2
                            ),
                            style: .continuous
                        )
                        .fill(palette.quotaColor(fraction))
                        .frame(
                            width: proxy.size.width * fraction
                        )
                    } else {
                        RoundedRectangle(
                            cornerRadius: 4,
                            style: .continuous
                        )
                        .fill(palette.quotaColor(fraction))
                    }
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 4,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 4,
                    style: .continuous
                )
                .strokeBorder(
                    palette.progressBorder,
                    lineWidth: 1
                )
            }
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.3),
                value: remainingFraction
            )
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func metricRow(
        title: String,
        value: String,
        hasDivider: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(AstaSans.regular(10))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .widgetTextLineBox(height: 12)
            Spacer(minLength: 4)
            Text(value)
                .font(AstaSans.regular(10))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
                .privacySensitive()
                .widgetTextLineBox(height: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            if hasDivider {
                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 0.5)
            }
        }
    }

    private func percentText(_ fraction: Double?) -> String {
        guard let fraction else {
            return "—"
        }
        return "\(percentValue(fraction))%"
    }

    private func percentNumberText(_ fraction: Double) -> String {
        "\(percentValue(fraction))"
    }

    private func percentValue(_ fraction: Double) -> Int {
        min(
            max(Int((fraction * 100).rounded()), 0),
            100
        )
    }

    private func metricValue(
        _ identifier: String,
        in provider: ProviderWidgetPayload
    ) -> String {
        guard let value = provider.auxiliaryMetrics.first(
            where: { $0.id == identifier }
        )?.formattedValue,
              !value.isEmpty
        else {
            return "—"
        }
        return value
    }

    private func normalizedPlan(_ rawPlan: String?) -> String? {
        OpenAIPlanDisplayName.resolve(rawPlan)
    }

    private func accessibilityLabel(
        _ data: WidgetDisplayData
    ) -> String {
        guard data.isAvailable,
              let remainingFraction = data.remainingFraction
        else {
            return copy.unavailableAccessibility
        }

        return copy.accessibilitySummary(
            remainingPercent: min(
                max(Int((remainingFraction * 100).rounded()), 0),
                100
            ),
            resetText: data.resetText,
            creditsBalance: data.creditsBalance,
            todayTokens: data.todayTokens,
            lifetimeTokens: data.lifetimeTokens
        )
    }
}

private struct WidgetDisplayData {
    let isAvailable: Bool
    let remainingFraction: Double?
    let plan: String?
    let resetText: String
    let footerText: String
    let creditsBalance: String
    let todayTokens: String
    let lifetimeTokens: String

    static let placeholder = WidgetDisplayData(
        isAvailable: true,
        remainingFraction: 0.64,
        plan: "Plus",
        resetText: "6d 18h",
        footerText: "6d 15h",
        creditsBalance: "0",
        todayTokens: "62M",
        lifetimeTokens: "917M"
    )

    static func unavailable(copy: WidgetCopy) -> WidgetDisplayData {
        WidgetDisplayData(
            isAvailable: false,
            remainingFraction: nil,
            plan: nil,
            resetText: "—",
            footerText: copy.refreshInAppShort,
            creditsBalance: "—",
            todayTokens: "—",
            lifetimeTokens: "—"
        )
    }
}

private struct WidgetPalette {
    let colorScheme: ColorScheme

    static let connected = Color(
        red: 0,
        green: 213.0 / 255.0,
        blue: 67.0 / 255.0
    )
    static let disconnected = Color(
        red: 1,
        green: 69.0 / 255.0,
        blue: 58.0 / 255.0
    )

    private var isDark: Bool {
        colorScheme == .dark
    }

    var background: Color {
        isDark
            ? Color(
                red: 26.0 / 255.0,
                green: 26.0 / 255.0,
                blue: 28.0 / 255.0
            )
            : .white
    }

    var primaryText: Color {
        isDark
            ? .white
            : Color(
                red: 58.0 / 255.0,
                green: 58.0 / 255.0,
                blue: 58.0 / 255.0
            )
    }

    var secondaryText: Color {
        isDark
            ? Color.white.opacity(0.75)
            : Color(
                red: 87.0 / 255.0,
                green: 87.0 / 255.0,
                blue: 87.0 / 255.0
            )
    }

    var divider: Color {
        isDark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.12)
    }

    var tagFill: Color {
        isDark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }

    var tagBorder: Color {
        isDark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.24)
    }

    var progressTrack: Color {
        isDark
            ? Color.white.opacity(0.32)
            : Color.black.opacity(0.12)
    }

    var progressBorder: Color {
        isDark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    var logoAssetName: String {
        isDark
            ? "QuotaViewWidgetLogoOnDark"
            : "QuotaViewWidgetLogoOnLight"
    }

    var clockAssetName: String {
        isDark
            ? "QuotaViewWidgetClockOnDark"
            : "QuotaViewWidgetClockOnLight"
    }

    func quotaColor(_ remainingFraction: Double) -> Color {
        let percent = Int((remainingFraction * 100).rounded())
        switch percent {
        case 50...:
            return Color(
                red: 0,
                green: 1,
                blue: 17.0 / 255.0
            )
            .opacity(0.8)
        case 20..<50:
            return Color(
                red: 1,
                green: 204.0 / 255.0,
                blue: 0
            )
            .opacity(0.8)
        default:
            return Color(
                red: 1,
                green: 69.0 / 255.0,
                blue: 58.0 / 255.0
            )
            .opacity(0.8)
        }
    }
}

private struct WidgetCopy {
    let isChinese: Bool
    let locale: Locale

    init(localeIdentifier: String) {
        isChinese = localeIdentifier.lowercased().hasPrefix("zh")
        locale = Locale(identifier: localeIdentifier)
    }

    var weeklyRemaining: String {
        text("本周剩余", "Weekly Remaining")
    }

    var nextReset: String {
        text("下次重置", "Next Reset")
    }

    var creditsBalance: String {
        text("Credits 余额", "Credits Balance")
    }

    var todayTokens: String {
        text("今日 Tokens", "Today Tokens")
    }

    var lifetimeTokens: String {
        text("累计 Tokens", "Lifetime Tokens")
    }

    var connected: String {
        text("Codex 数据连接可用", "Codex data connection available")
    }

    var disconnected: String {
        text("Codex 数据连接不可用", "Codex data connection unavailable")
    }

    var unavailable: String {
        text("额度数据不可用", "Quota data unavailable")
    }

    var refreshInAppShort: String {
        text("在 App 中刷新", "Refresh in app")
    }

    var unavailableAccessibility: String {
        text(
            "QuotaView，Codex 数据连接不可用，额度数据不可用，请在 QuotaView 中刷新",
            "QuotaView, Codex data connection unavailable, quota data unavailable, refresh in QuotaView"
        )
    }

    func resetCountdown(_ resetDate: Date?) -> String {
        guard let resetDate else {
            return "—"
        }

        let totalMinutes = max(
            0,
            Int(resetDate.timeIntervalSinceNow / 60)
        )
        let days = totalMinutes / 1_440
        let hours = totalMinutes % 1_440 / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return text(
                "\(days)天 \(hours)小时",
                "\(days)d \(hours)h"
            )
        }
        if hours > 0 {
            return text(
                "\(hours)小时 \(minutes)分",
                "\(hours)h \(minutes)m"
            )
        }
        return text("\(minutes)分", "\(minutes)m")
    }

    func planAccessibility(_ plan: String) -> String {
        text("订阅类型 \(plan)", "Plan \(plan)")
    }

    func accessibilitySummary(
        remainingPercent: Int,
        resetText: String,
        creditsBalance: String,
        todayTokens: String,
        lifetimeTokens: String
    ) -> String {
        text(
            "QuotaView，Codex 数据连接可用，本周剩余 \(remainingPercent)%，下次重置 \(resetText)，Credits 余额 \(creditsBalance)，今日 Tokens \(todayTokens)，累计 Tokens \(lifetimeTokens)",
            "QuotaView, Codex data connection available, \(remainingPercent) percent remaining this week, next reset \(resetText), credits balance \(creditsBalance), today tokens \(todayTokens), lifetime tokens \(lifetimeTokens)"
        )
    }

    private func text(
        _ simplifiedChinese: String,
        _ english: String
    ) -> String {
        isChinese ? simplifiedChinese : english
    }
}

@main
struct QuotaViewUsageWidget: Widget {
    init() {
        AstaSansFontRegistrar.registerBundledFonts()
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: QuotaViewWidgetConfiguration.kind,
            provider: QuotaViewWidgetProvider()
        ) { entry in
            QuotaViewWidgetView(entry: entry)
        }
        .configurationDisplayName("QuotaView")
        .description("Codex quota status at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
