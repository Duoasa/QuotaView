import AppKit
import QuotaViewCore
#if canImport(QuotaViewWidgetContract)
import QuotaViewWidgetContract
#endif
import SwiftUI

struct QuotaViewFigmaMenu: View {
    nonisolated static let designSize = CGSize(width: 274, height: 433)

    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme

    let copy: AppCopy
    let openResetAction: () -> Void
    let refreshAction: () -> Void
    let openCodexAction: () -> Void
    let openSettingsAction: () -> Void
    let quitAction: () -> Void

    private enum Layout {
        static let width = QuotaViewFigmaMenu.designSize.width
        static let headerHeight: CGFloat = 48
        static let summaryHeight: CGFloat = 117
        static let footerHeight: CGFloat = 48
        static let metricRowHeight: CGFloat = 36
        static let resetCardHeight: CGFloat = 51
        static let detailTypeSpacing: CGFloat = 9
        static let detailsBottomInset: CGFloat = 16
        static let headerInset: CGFloat = 12
        static let summaryInset: CGFloat = 16
        static let detailsInset: CGFloat = 12
        static let contentWidth: CGFloat = 250
        static let progressHeight: CGFloat = 8
        static let progressTrackCornerRadius: CGFloat = 6
        static let progressOuterCornerRadius: CGFloat = 4
        static let progressInnerCornerRadius: CGFloat = 2
    }

    private enum Palette {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.75)
        static let lightPrimary = Color(
            red: 58.0 / 255.0,
            green: 58.0 / 255.0,
            blue: 58.0 / 255.0
        )
        static let lightSecondary = Color(
            red: 87.0 / 255.0,
            green: 87.0 / 255.0,
            blue: 87.0 / 255.0
        )
        static let darkSeparator = Color.white.opacity(0.12)
        static let lightSeparator = Color.black.opacity(0.12)
        static let remainingGreen = Color(
            red: 0,
            green: 1,
            blue: 17.0 / 255.0
        )
        static let remainingYellow = Color(
            red: 1,
            green: 0.80,
            blue: 0
        )
        static let connected = Color(
            red: 0,
            green: 213.0 / 255.0,
            blue: 67.0 / 255.0
        )
        static let danger = Color(
            red: 1,
            green: 69.0 / 255.0,
            blue: 58.0 / 255.0
        )
    }

    private struct Metric: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    private enum ContentType: Equatable {
        case info
        case interactive
    }

    private enum InfoItem {
        case usageSummary
        case metric(Metric)
    }

    private enum PanelItem: Identifiable {
        case info(InfoItem)
        case resetEntry

        var id: String {
            switch self {
            case .info(.usageSummary):
                "usage-summary"
            case let .info(.metric(metric)):
                metric.id
            case .resetEntry:
                "quota-reset"
            }
        }

        var type: ContentType {
            switch self {
            case .info:
                .info
            case .resetEntry:
                .interactive
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if showsUsageSummary {
                summary
            }

            if !detailItems.isEmpty {
                details
            }

            footer
        }
        .frame(width: Layout.width, height: menuHeight)
        .quotaViewMenuContentSurface()
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 6) {
            appIcon

            Text("QuotaView")
                .font(AstaSans.semiBold(15))
                .tracking(-0.15)
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .frame(height: 24)

            Spacer(minLength: 6)

            Button(action: quitAction) {
                figmaIcon("QuotaViewFigmaPower")
            }
            .quotaViewInteractiveButton(.compact)
            .help(copy.text("退出 QuotaView", "Quit QuotaView"))
            .accessibilityLabel(
                copy.text("退出 QuotaView", "Quit QuotaView")
            )
        }
        .padding(Layout.headerInset)
        .frame(height: Layout.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 0.75)
        }
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 7.5,
                style: .continuous
            )
            .fill(Color.white.opacity(0.10))

            Image("QuotaViewFigmaAppIcon")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 31.474, height: 31.474)
        }
        .frame(width: 24, height: 24)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 7.5,
                style: .continuous
            )
        )
        .shadow(
            color: Color.black.opacity(0.25),
            radius: 1.2,
            x: 0,
            y: 0.24
        )
        .accessibilityHidden(true)
    }

    private var summary: some View {
        VStack(alignment: .trailing, spacing: 9) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.text("本周期剩余", "Period Remaining"))
                        .font(AstaSans.regular(10.5))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .frame(height: 16)

                    Text(remainingPercentLabel)
                        .font(AstaSans.semiBold(21))
                        .tracking(-0.21)
                        .foregroundStyle(primaryTextColor)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .frame(height: 24)
                }

                Spacer(minLength: 6)

                Text(subscriptionLabel)
                    .font(AstaSans.semiBold(10.5))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: 16)
                    .accessibilityLabel(
                        copy.text(
                            "Codex 订阅：\(subscriptionLabel)",
                            "Codex subscription: \(subscriptionLabel)"
                        )
                    )
            }
            .frame(height: 43)

            progressBar

            Text(usedPercentLabel)
                .font(AstaSans.regular(10.5))
                .foregroundStyle(secondaryTextColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .frame(height: 16)
        }
        .padding(Layout.summaryInset)
        .frame(width: Layout.width, height: Layout.summaryHeight)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let showsBothSegments = progressRemainingPercent > 0
                && progressRemainingPercent < 100
            let segmentGap: CGFloat = showsBothSegments ? 1 : 0
            let segmentWidth = max(0, proxy.size.width - segmentGap)
            let remainingWidth =
                segmentWidth * CGFloat(progressRemainingPercent) / 100
            let usedWidth = segmentWidth - remainingWidth

            ZStack {
                RoundedRectangle(
                    cornerRadius: Layout.progressTrackCornerRadius,
                    style: .continuous
                )
                .fill(
                    Color.black.opacity(0.16)
                        .shadow(
                            .inner(
                                color: Color.black.opacity(0.12),
                                radius: 30,
                                x: -3.75,
                                y: -3
                            )
                        )
                )

                if hasCodexStatus {
                    HStack(spacing: segmentGap) {
                        if remainingWidth > 0 {
                            if showsBothSegments {
                                UnevenRoundedRectangle(
                                    cornerRadii: .init(
                                        topLeading:
                                            Layout.progressOuterCornerRadius,
                                        bottomLeading:
                                            Layout.progressOuterCornerRadius,
                                        bottomTrailing:
                                            Layout.progressInnerCornerRadius,
                                        topTrailing:
                                            Layout.progressInnerCornerRadius
                                    ),
                                    style: .continuous
                                )
                                .fill(remainingQuotaColor)
                                .frame(width: remainingWidth)
                            } else {
                                RoundedRectangle(
                                    cornerRadius:
                                        Layout.progressOuterCornerRadius,
                                    style: .continuous
                                )
                                .fill(remainingQuotaColor)
                                .frame(width: remainingWidth)
                            }
                        }

                        if usedWidth > 0 {
                            if showsBothSegments {
                                UnevenRoundedRectangle(
                                    cornerRadii: .init(
                                        topLeading:
                                            Layout.progressInnerCornerRadius,
                                        bottomLeading:
                                            Layout.progressInnerCornerRadius,
                                        bottomTrailing:
                                            Layout.progressOuterCornerRadius,
                                        topTrailing:
                                            Layout.progressOuterCornerRadius
                                    ),
                                    style: .continuous
                                )
                                .fill(progressUsedColor)
                                .frame(width: usedWidth)
                            } else {
                                RoundedRectangle(
                                    cornerRadius:
                                        Layout.progressOuterCornerRadius,
                                    style: .continuous
                                )
                                .fill(progressUsedColor)
                                .frame(width: usedWidth)
                            }
                        }
                    }
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Layout.progressTrackCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: Layout.progressTrackCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    Color.white.opacity(0.12),
                    lineWidth: 1
                )
            }
        }
        .frame(height: Layout.progressHeight)
        .accessibilityLabel(
            copy.text("本周期额度", "Period quota")
        )
        .accessibilityValue(progressAccessibilityValue)
    }

    private var details: some View {
        let items = detailItems

        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) {
                index,
                item in
                switch item {
                case let .info(.metric(metric)):
                    metricRow(
                        metric,
                        showsSeparator: hasFollowingItem(
                            of: item.type,
                            after: index,
                            in: items
                        )
                    )
                case .info(.usageSummary):
                    EmptyView()
                case .resetEntry:
                    resetCard
                        .padding(
                            .top,
                            resetEntryNeedsTypeSpacing
                                ? Layout.detailTypeSpacing
                                : 0
                        )
                }
            }
        }
        .padding(.horizontal, Layout.detailsInset)
        .padding(.bottom, Layout.detailsBottomInset)
        .frame(
            width: Layout.width,
            height: detailsHeight(for: items),
            alignment: .top
        )
    }

    private func metricRow(
        _ metric: Metric,
        showsSeparator: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Text(metric.title)
                .font(AstaSans.semiBold(10.5))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .frame(height: 16)

            Spacer(minLength: 6)

            Text(metric.value)
                .font(AstaSans.regular(10.5))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .frame(height: 16)
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(separatorColor)
                    .frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resetCard: some View {
        Button(action: openResetAction) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.text("额度重置", "Quota Reset"))
                        .font(AstaSans.semiBold(10.5))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                        .frame(height: 16)

                    Text(
                        copy.text(
                            "重置符合条件的 Codex 用量周期",
                            "Reset an eligible Codex usage cycle"
                        )
                    )
                        .font(AstaSans.regular(9))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(availableResetCreditsLabel)
                    .font(AstaSans.medium(9))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .frame(height: 9)
                    .padding(4.5)
                    .background(
                        Color.white.opacity(0.80),
                        in: RoundedRectangle(
                            cornerRadius: 6,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 6,
                            style: .continuous
                        )
                        .strokeBorder(
                            Color.white.opacity(0.32),
                            lineWidth: 0.75
                        )
                    }
            }
            .padding(.leading, 9)
            .padding(.trailing, 14.25)
            .padding(.vertical, 9)
            .frame(width: Layout.contentWidth, height: 51)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
        }
        .quotaViewInteractiveButton(.regular)
        .background {
            ZStack {
                QuotaViewFigmaDropShadow(
                    cornerRadius: 12,
                    color: .black,
                    opacity: resetCardShadowOpacity,
                    radius: 20,
                    offset: CGSize(width: 0, height: 4)
                )

                QuotaViewFigmaLocalGlass(
                    frostRadius: 10.5,
                    cornerRadius: 12,
                    tintColor: resetCardTintColor
                )

                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(
                    Color.black.opacity(0.001)
                        .shadow(
                            .inner(
                                color: Color.black.opacity(0.05),
                                radius: 10,
                                x: -2,
                                y: -2
                            )
                        )
                )
            }
            .allowsHitTesting(false)
            .overlay {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .strokeBorder(
                    resetCardStrokeColor,
                    lineWidth: 1
                )
            }
        }
        .frame(width: Layout.contentWidth, height: 51)
        .help(copy.text("打开额度重置", "Open quota reset"))
        .accessibilityLabel(
            copy.text(
                "额度重置，\(availableResetCredits) 次可用",
                "Quota Reset, \(availableResetCredits) Available"
            )
        )
    }

    private var footer: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(
                    copy.text(
                        "更新于 \(updatedTime)",
                        "Update \(updatedTime)"
                    )
                )
                    .font(AstaSans.regular(10.5))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .frame(height: 16)

                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 5, height: 5)
                    .help(connectionStatusText)
                    .accessibilityLabel(connectionStatusText)
            }

            Spacer(minLength: 6)

            HStack(spacing: 9) {
                Button(action: refreshAction) {
                    figmaIcon("QuotaViewFigmaSync")
                }
                .quotaViewInteractiveButton(.compact)
                .disabled(store.isRefreshing)
                .help(copy.text("同步", "Sync"))
                .accessibilityLabel(copy.text("同步", "Sync"))

                Button(action: openCodexAction) {
                    figmaIcon("QuotaViewFigmaOpenCodex")
                }
                .quotaViewInteractiveButton(.compact)
                .help(copy.text("打开 Codex", "Open Codex"))
                .accessibilityLabel(
                    copy.text("打开 Codex", "Open Codex")
                )

                Button(action: openSettingsAction) {
                    figmaIcon("QuotaViewFigmaSettings")
                }
                .quotaViewInteractiveButton(.compact)
                .help(copy.text("打开设置", "Open Settings"))
                .accessibilityLabel(
                    copy.text("打开设置", "Open Settings")
                )
            }
        }
        .padding(Layout.headerInset)
        .frame(height: Layout.footerHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 0.5)
        }
    }

    private func figmaIcon(_ name: String) -> some View {
        Image(isLightAppearance ? "\(name)Light" : name)
            .resizable()
            .interpolation(.high)
            .frame(width: 24, height: 24)
            .contentShape(Circle())
    }

    private var isLightAppearance: Bool {
        colorScheme == .light
    }

    private var primaryTextColor: Color {
        isLightAppearance ? Palette.lightPrimary : Palette.primary
    }

    private var secondaryTextColor: Color {
        isLightAppearance ? Palette.lightSecondary : Palette.secondary
    }

    private var separatorColor: Color {
        isLightAppearance
            ? Palette.lightSeparator
            : Palette.darkSeparator
    }

    private var resetCardStrokeColor: Color {
        Color.white.opacity(0.12)
    }

    private var resetCardShadowOpacity: CGFloat {
        isLightAppearance ? 0.12 : 0.20
    }

    private var resetCardTintColor: NSColor {
        (
            isLightAppearance ? NSColor.white : NSColor.black
        ).withAlphaComponent(0.12)
    }

    private var remainingPercent: Int {
        store.snapshot?.remainingPercent ?? 0
    }

    private var usedPercent: Int {
        min(max(store.snapshot?.usedPercent ?? 0, 0), 100)
    }

    private var hasCodexStatus: Bool {
        store.hasCurrentCodexStatus
    }

    private var subscriptionLabel: String {
        guard hasCodexStatus,
              let rawPlan = store.snapshot?.planType
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawPlan.isEmpty,
            rawPlan.caseInsensitiveCompare("unknown") != .orderedSame
        else {
            return "—"
        }

        return OpenAIPlanDisplayName.resolve(rawPlan) ?? "—"
    }

    private var remainingPercentLabel: String {
        hasCodexStatus ? "\(remainingPercent)%" : "—"
    }

    private var usedPercentLabel: String {
        guard hasCodexStatus else {
            return copy.text("已使用 —", "— Used")
        }
        return copy.text(
            "已使用 \(usedPercent)%",
            "\(usedPercent)% Used"
        )
    }

    private var progressRemainingPercent: Int {
        hasCodexStatus
            ? min(max(remainingPercent, 0), 100)
            : 0
    }

    private var remainingQuotaColor: Color {
        guard hasCodexStatus else {
            return Palette.danger
        }

        switch remainingPercent {
        case 50...:
            return Palette.remainingGreen
        case 20..<50:
            return Palette.remainingYellow
        default:
            return Palette.danger
        }
    }

    private var progressUsedColor: Color {
        Color.white.opacity(0.32)
    }

    private var progressAccessibilityValue: String {
        guard hasCodexStatus else {
            return copy.text("不可用", "Unavailable")
        }
        return copy.text(
            "剩余 \(remainingPercent)%，已使用 \(usedPercent)%",
            "\(remainingPercent) percent remaining, \(usedPercent) percent used"
        )
    }

    private var availableResetCredits: Int {
        store.snapshot?.availableResetCredits ?? 0
    }

    private var connectionIndicatorColor: Color {
        hasCodexStatus ? Palette.connected : Palette.danger
    }

    private var connectionStatusText: String {
        copy.text(
            hasCodexStatus
                ? "Codex 数据连接可用"
                : "Codex 数据连接不可用",
            hasCodexStatus
                ? "Codex data connection available"
                : "Codex data connection unavailable"
        )
    }

    private var visibleItems: [PanelItem] {
        let snapshot = store.snapshot
        var result: [PanelItem] = []

        if preferences.showUsageSummary {
            result.append(.info(.usageSummary))
        }

        if preferences.showNextReset {
            result.append(
                .info(
                    .metric(
                        Metric(
                            id: "next-reset",
                            title: copy.text("下次重置", "Next Reset"),
                            value: resetCountdown(snapshot?.resetsAt)
                        )
                    )
                )
            )
        }

        if preferences.showCreditBalance {
            result.append(
                .info(
                    .metric(
                        Metric(
                            id: "credits-balance",
                            title: copy.text("积分余额", "Credits Balance"),
                            value: creditBalance(snapshot)
                        )
                    )
                )
            )
        }

        if preferences.showDailyTokens {
            result.append(
                .info(
                    .metric(
                        Metric(
                            id: "today-tokens",
                            title: copy.text("今日 Tokens", "Today Tokens"),
                            value: compactTokenCount(
                                snapshot?.recentDailyTokens
                            )
                        )
                    )
                )
            )
        }

        if preferences.showLifetimeTokens {
            result.append(
                .info(
                    .metric(
                        Metric(
                            id: "lifetime-tokens",
                            title: copy.text("累计 Tokens", "Lifetime Tokens"),
                            value: compactTokenCount(
                                snapshot?.lifetimeTokens
                            )
                        )
                    )
                )
            )
        }

        if showsResetEntry {
            result.append(.resetEntry)
        }

        return result
    }

    private var showsResetEntry: Bool {
        preferences.showResetAction
            && store.hasAvailableResetCredit
    }

    private var showsUsageSummary: Bool {
        visibleItems.contains {
            if case .info(.usageSummary) = $0 {
                return true
            }
            return false
        }
    }

    private var detailItems: [PanelItem] {
        visibleItems.filter {
            if case .info(.usageSummary) = $0 {
                return false
            }
            return true
        }
    }

    private var resetEntryNeedsTypeSpacing: Bool {
        visibleItems.contains { $0.type == .info }
            && visibleItems.contains { $0.type == .interactive }
    }

    private var menuHeight: CGFloat {
        Layout.headerHeight
            + (showsUsageSummary ? Layout.summaryHeight : 0)
            + detailsHeight(for: detailItems)
            + Layout.footerHeight
    }

    private func detailsHeight(
        for items: [PanelItem]
    ) -> CGFloat {
        guard !items.isEmpty else { return 0 }

        let infoCount = items.filter { $0.type == .info }.count
        let interactiveCount = items.filter {
            $0.type == .interactive
        }.count
        let typeSpacing = resetEntryNeedsTypeSpacing
            ? Layout.detailTypeSpacing
            : 0

        return CGFloat(infoCount) * Layout.metricRowHeight
            + CGFloat(interactiveCount) * Layout.resetCardHeight
            + typeSpacing
            + Layout.detailsBottomInset
    }

    private func hasFollowingItem(
        of type: ContentType,
        after index: Int,
        in items: [PanelItem]
    ) -> Bool {
        items.dropFirst(index + 1).contains {
            $0.type == type
        }
    }

    private var availableResetCreditsLabel: String {
        copy.text(
            "\(availableResetCredits) 次可用",
            "\(availableResetCredits) Available"
        )
    }

    private var updatedTime: String {
        guard let date = store.snapshot?.lastUpdatedAt else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: copy.language.localeIdentifier
        )
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func resetCountdown(_ resetDate: Date?) -> String {
        guard let resetDate else { return "—" }

        let totalMinutes = max(
            0,
            Int(resetDate.timeIntervalSinceNow / 60)
        )
        let days = totalMinutes / 1_440
        let hours = totalMinutes % 1_440 / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return copy.text(
                "\(days)天 \(hours)小时",
                "\(days)d \(hours)h"
            )
        }
        if hours > 0 {
            return copy.text(
                "\(hours)小时 \(minutes)分",
                "\(hours)h \(minutes)m"
            )
        }
        return copy.text("\(minutes)分", "\(minutes)m")
    }

    private func creditBalance(
        _ snapshot: CurrentCodexPresentation?
    ) -> String {
        guard let snapshot else { return "—" }
        if snapshot.unlimitedCredits {
            return copy.text("无限", "Unlimited")
        }
        return snapshot.creditBalance ?? "—"
    }

    private func compactTokenCount(_ count: Int64?) -> String {
        guard let count else { return "—" }

        let formatter = NumberFormatter()
        formatter.locale = Locale(
            identifier: copy.language.localeIdentifier
        )
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false

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

        return (formatter.string(from: magnitude as NSNumber) ?? "—")
            + suffix
    }
}

struct QuotaViewFigmaDropShadow: NSViewRepresentable {
    let cornerRadius: CGFloat
    let color: NSColor
    let opacity: CGFloat
    let radius: CGFloat
    let offset: CGSize

    func makeNSView(context: Context) -> QuotaViewFigmaCardShadowView {
        QuotaViewFigmaCardShadowView(
            cornerRadius: cornerRadius,
            color: color,
            opacity: opacity,
            radius: radius,
            offset: offset
        )
    }

    func updateNSView(
        _ nsView: QuotaViewFigmaCardShadowView,
        context: Context
    ) {
        nsView.update(
            cornerRadius: cornerRadius,
            color: color,
            opacity: opacity,
            radius: radius,
            offset: offset
        )
    }
}

final class QuotaViewFigmaCardShadowView: NSView {
    private var cornerRadius: CGFloat

    override var isOpaque: Bool { false }

    init(
        cornerRadius: CGFloat,
        color: NSColor,
        opacity: CGFloat,
        radius: CGFloat,
        offset: CGSize
    ) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        update(
            cornerRadius: cornerRadius,
            color: color,
            opacity: opacity,
            radius: radius,
            offset: offset
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateShadowPath()
    }

    func update(
        cornerRadius: CGFloat,
        color: NSColor,
        opacity: CGFloat,
        radius: CGFloat,
        offset: CGSize
    ) {
        self.cornerRadius = cornerRadius
        layer?.shadowColor = color.cgColor
        layer?.shadowOpacity = Float(opacity)
        layer?.shadowRadius = radius
        layer?.shadowOffset = CGSize(
            width: offset.width,
            height: -offset.height
        )
        updateShadowPath()
    }

    private func updateShadowPath() {
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }
}

struct QuotaViewFigmaLocalGlass: NSViewRepresentable {
    @Environment(\.quotaViewGlassMode) private var glassMode

    let frostRadius: CGFloat
    let cornerRadius: CGFloat
    let tintColor: NSColor

    func makeNSView(context: Context) -> QuotaViewFigmaLocalGlassView {
        QuotaViewFigmaLocalGlassView(
            mode: glassMode,
            frostRadius: frostRadius,
            cornerRadius: cornerRadius,
            tintColor: tintColor
        )
    }

    func updateNSView(
        _ nsView: QuotaViewFigmaLocalGlassView,
        context: Context
    ) {
        nsView.update(
            mode: glassMode,
            frostRadius: frostRadius,
            cornerRadius: cornerRadius,
            tintColor: tintColor
        )
    }
}

final class QuotaViewFigmaLocalGlassView: NSView {
    private let effectView: NSView
    private let tintView = NSView()

    override var isOpaque: Bool { false }

    init(
        mode: QuotaViewGlassMode,
        frostRadius: CGFloat,
        cornerRadius: CGFloat,
        tintColor: NSColor
    ) {
        if #available(macOS 26.0, *) {
            effectView = NSGlassEffectView()
        } else {
            effectView = NSVisualEffectView()
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        effectView.wantsLayer = true
        tintView.wantsLayer = true
        addSubview(effectView)
        addSubview(tintView)
        update(
            mode: mode,
            frostRadius: frostRadius,
            cornerRadius: cornerRadius,
            tintColor: tintColor
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        tintView.frame = bounds
    }

    func update(
        mode: QuotaViewGlassMode,
        frostRadius: CGFloat,
        cornerRadius: CGFloat,
        tintColor: NSColor
    ) {
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        tintView.layer?.cornerRadius = cornerRadius
        tintView.layer?.cornerCurve = .continuous
        tintView.layer?.masksToBounds = true
        tintView.layer?.backgroundColor = tintColor.cgColor

        if #available(macOS 26.0, *),
           let glassView = effectView as? NSGlassEffectView {
            glassView.cornerRadius = cornerRadius
            glassView.style = mode == .clear ? .clear : .regular
            glassView.tintColor = .clear
        } else if let materialView = effectView as? NSVisualEffectView {
            materialView.material = .underWindowBackground
            materialView.blendingMode = .withinWindow
            materialView.state = .active
            materialView.alphaValue = min(max(frostRadius / 10.5, 0), 1)
        }
    }
}
