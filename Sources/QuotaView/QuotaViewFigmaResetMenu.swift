import AppKit
import Foundation
import QuotaViewCore
import SwiftUI

struct QuotaViewFigmaResetMenu: View {
    nonisolated static let designSize = CGSize(width: 274, height: 473)

    @ObservedObject var store: CodexStatusStore
    @Environment(\.colorScheme) private var colorScheme

    let copy: AppCopy
    let returnAction: () -> Void
    let resetAction: () -> Void
    let refreshAction: () -> Void
    let openCodexAction: () -> Void
    let openSettingsAction: () -> Void

    private enum Layout {
        static let width = QuotaViewFigmaResetMenu.designSize.width
        static let height = QuotaViewFigmaResetMenu.designSize.height
        static let headerHeight: CGFloat = 48
        static let heroHeight: CGFloat = 128
        static let detailsHeight: CGFloat = 249
        static let footerHeight: CGFloat = 48
        static let contentWidth: CGFloat = 250
        static let ticketIconWidth: CGFloat = 22.7907
        static let ticketIconHeight: CGFloat = 16
        static let ticketSpacing: CGFloat = 8
        static let ticketStripMaxWidth: CGFloat = 176.744
        static let resetButtonCornerRadius: CGFloat = 8
    }

    private enum Palette {
        static let darkPrimary = Color.white
        static let darkSecondary = Color.white.opacity(0.75)
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
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            creditsHero
            details
            footer
        }
        .frame(width: Layout.width, height: Layout.height)
        .quotaViewMenuContentSurface()
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: returnAction) {
                appearanceImage("QuotaViewFigmaBack")
                    .contentShape(Circle())
            }
            .quotaViewInteractiveButton(.compact)
            .help(
                copy.text("返回额度概览", "Return to quota overview")
            )
            .accessibilityLabel(
                copy.text("返回额度概览", "Return to quota overview")
            )

            Text(copy.text("额度重置", "Quota Reset"))
                .font(AstaSans.semiBold(15))
                .tracking(-0.15)
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .frame(height: 24)

            Spacer(minLength: 6)

            Text(copy.text("演示", "Demo"))
                .font(AstaSans.semiBold(9))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .frame(height: 9)
                .padding(4.5)
                .background(
                    demoFillColor,
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
                        demoStrokeColor,
                        lineWidth: 0.5
                    )
                }
        }
        .padding(12)
        .frame(width: Layout.width, height: Layout.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 0.75)
        }
    }

    private var creditsHero: some View {
        VStack(spacing: 8) {
            resetCreditTickets

            VStack(spacing: 8) {
                Text(availableResetCreditsText)
                    .font(AstaSans.semiBold(32))
                    .tracking(-0.32)
                    .foregroundStyle(primaryTextColor)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .frame(height: 32)

                Text(resetCreditsAvailableLabel)
                    .font(
                        AstaSans.regular(
                            isLightAppearance ? 10 : 10.5
                        )
                    )
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .frame(height: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(width: Layout.width, height: Layout.heroHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            resetCreditsAccessibilityLabel
        )
    }

    private var resetCreditTickets: some View {
        let count = availableResetCredits
        let naturalWidth = ticketStripWidth(for: count)
        let scale = naturalWidth > 0
            ? min(1, Layout.ticketStripMaxWidth / naturalWidth)
            : 1

        return HStack(spacing: Layout.ticketSpacing) {
            ForEach(0..<count, id: \.self) { _ in
                resetCreditTicketIcon
            }
        }
        .frame(
            width: naturalWidth,
            height: Layout.ticketIconHeight
        )
        .scaleEffect(scale)
        .frame(
            width: min(naturalWidth, Layout.ticketStripMaxWidth),
            height: Layout.ticketIconHeight
        )
        .accessibilityHidden(true)
    }

    private var resetCreditTicketIcon: some View {
        Image(
            isLightAppearance
                ? "QuotaViewFigmaResetCreditsLight"
                : "QuotaViewFigmaResetCredits"
        )
        .resizable()
        .interpolation(.high)
        .frame(
            width: Layout.ticketStripMaxWidth,
            height: Layout.ticketIconHeight,
            alignment: .leading
        )
        .frame(
            width: Layout.ticketIconWidth,
            height: Layout.ticketIconHeight,
            alignment: .leading
        )
        .clipped()
    }

    private func ticketStripWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * Layout.ticketIconWidth
            + CGFloat(count - 1) * Layout.ticketSpacing
    }

    private var details: some View {
        VStack(spacing: 9) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(
                        copy.text(
                            "当前可用额度",
                            "Current Quota Available"
                        )
                    )

                    Spacer(minLength: 6)

                    Text(currentQuotaText)
                        .contentTransition(.numericText())
                }
                .font(AstaSans.semiBold(10.5))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(width: Layout.contentWidth, height: 36)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(separatorColor)
                        .frame(height: 0.5)
                }
                .accessibilityElement(children: .combine)

                resetWarnings
            }
            .frame(width: Layout.contentWidth, height: 168)

            resetButton

            Text(resetActionCaption)
                .font(
                    AstaSans.regular(
                        isLightAppearance ? 10.5 : 10
                    )
                )
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: Layout.contentWidth, height: 15)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: Layout.width, height: Layout.detailsHeight)
    }

    private var resetWarnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.text("⚠️ 重置前请确认", "⚠️ Before Resetting"))
                .font(AstaSans.semiBold(10.5))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .frame(height: 16)

            warningLine(
                copy.text(
                    "此操作会消耗 1 次额度重置机会。",
                    "This action consumes one reset credit."
                ),
                height: 15
            )
            warningLine(
                copy.text(
                    "符合条件的 Codex 用量周期将立即重置。",
                    "Your eligible Codex usage cycle resets immediately."
                ),
                height: 30
            )
            warningLine(
                copy.text(
                    "额度重置完成后无法撤销。",
                    "A completed quota reset cannot be undone."
                ),
                height: 15
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 16)
        .frame(width: Layout.contentWidth, height: 132)
        .accessibilityElement(children: .combine)
    }

    private func warningLine(
        _ text: String,
        height: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("•")
                .frame(width: 5, alignment: .leading)

            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AstaSans.regular(10))
        .foregroundStyle(secondaryTextColor)
        .lineLimit(2)
        .frame(height: height, alignment: .top)
    }

    private var resetButton: some View {
        Button(action: resetAction) {
            Text(copy.text("重置额度", "Quota Reset"))
                .font(AstaSans.semiBold(10.5))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .frame(
                    width: Layout.contentWidth,
                    height: 32
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: Layout.resetButtonCornerRadius,
                        style: .continuous
                    )
                )
        }
        .quotaViewInteractiveButton(.reset)
        .background {
            ZStack {
                QuotaViewFigmaDropShadow(
                    cornerRadius: Layout.resetButtonCornerRadius,
                    color: .red,
                    opacity: 0.16,
                    radius: 20,
                    offset: CGSize(width: 0, height: 4)
                )

                QuotaViewFigmaLocalGlass(
                    frostRadius: 10.5,
                    cornerRadius: Layout.resetButtonCornerRadius,
                    tintColor: NSColor.red.withAlphaComponent(0.12)
                )

                RoundedRectangle(
                    cornerRadius: Layout.resetButtonCornerRadius,
                    style: .continuous
                )
                .fill(
                    Color.black.opacity(0.001)
                        .shadow(
                            .inner(
                                color: Color.red.opacity(0.32),
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
                    cornerRadius: Layout.resetButtonCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    Color.red.opacity(0.16),
                    lineWidth: 1
                )
            }
        }
        .frame(width: Layout.contentWidth, height: 32)
        .disabled(!canResetQuota)
        .help(resetButtonHelp)
        .accessibilityLabel(copy.text("重置额度", "Reset quota"))
        .accessibilityHint(resetButtonHelp)
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
                    .font(
                        AstaSans.regular(
                            isLightAppearance ? 10 : 10.5
                        )
                    )
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
                    appearanceImage("QuotaViewFigmaSync")
                        .contentShape(Circle())
                }
                .quotaViewInteractiveButton(.compact)
                .disabled(store.isRefreshing)
                .help(copy.text("同步", "Sync"))
                .accessibilityLabel(copy.text("同步", "Sync"))

                Button(action: openCodexAction) {
                    appearanceImage("QuotaViewFigmaOpenCodex")
                        .contentShape(Circle())
                }
                .quotaViewInteractiveButton(.compact)
                .help(copy.text("打开 Codex", "Open Codex"))
                .accessibilityLabel(
                    copy.text("打开 Codex", "Open Codex")
                )

                Button(action: openSettingsAction) {
                    appearanceImage("QuotaViewFigmaSettings")
                        .contentShape(Circle())
                }
                .quotaViewInteractiveButton(.compact)
                .help(copy.text("打开设置", "Open Settings"))
                .accessibilityLabel(
                    copy.text("打开设置", "Open Settings")
                )
            }
        }
        .padding(12)
        .frame(width: Layout.width, height: Layout.footerHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 0.5)
        }
    }

    private func appearanceImage(
        _ name: String,
        width: CGFloat = 24,
        height: CGFloat = 24
    ) -> some View {
        Image(isLightAppearance ? "\(name)Light" : name)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
    }

    private var isLightAppearance: Bool {
        colorScheme == .light
    }

    private var primaryTextColor: Color {
        isLightAppearance
            ? Palette.lightPrimary
            : Palette.darkPrimary
    }

    private var secondaryTextColor: Color {
        isLightAppearance
            ? Palette.lightSecondary
            : Palette.darkSecondary
    }

    private var separatorColor: Color {
        isLightAppearance
            ? Palette.lightSeparator
            : Palette.darkSeparator
    }

    private var demoFillColor: Color {
        isLightAppearance
            ? Color.black.opacity(0.04)
            : Color.white.opacity(0.13)
    }

    private var demoStrokeColor: Color {
        Color.white.opacity(0.24)
    }

    private var canResetQuota: Bool {
        store.hasAvailableResetCredit
    }

    private var connectionIndicatorColor: Color {
        store.hasCurrentCodexStatus
            ? Palette.connected
            : Palette.disconnected
    }

    private var connectionStatusText: String {
        copy.text(
            store.hasCurrentCodexStatus
                ? "Codex 数据连接可用"
                : "Codex 数据连接不可用",
            store.hasCurrentCodexStatus
                ? "Codex data connection available"
                : "Codex data connection unavailable"
        )
    }

    private var availableResetCredits: Int {
        max(0, store.snapshot?.availableResetCredits ?? 0)
    }

    private var availableResetCreditsText: String {
        guard let count = store.snapshot?.availableResetCredits else {
            return "—"
        }
        return String(count)
    }

    private var resetCreditsAvailableLabel: String {
        copy.text(
            "可用重置次数",
            availableResetCredits == 1
                ? "Reset Credit Available"
                : "Reset Credits Available"
        )
    }

    private var resetCreditsAccessibilityLabel: String {
        copy.text(
            "\(availableResetCredits) 次额度重置机会可用",
            "\(availableResetCredits) reset "
                + (availableResetCredits == 1 ? "credit" : "credits")
                + " available"
        )
    }

    private var currentQuotaText: String {
        guard let snapshot = store.snapshot else { return "—" }
        return "\(snapshot.remainingPercent)%"
    }

    private var resetActionCaption: String {
        if !store.hasCurrentCodexStatus {
            return store.errorMessage == nil
                ? copy.text("正在加载额度数据…", "Loading quota data…")
                : copy.text("额度数据不可用", "Quota data unavailable")
        }
        guard let snapshot = store.snapshot,
              snapshot.canUseResetCredit else {
            return copy.text(
                "当前没有可用重置次数",
                "No reset credits are available"
            )
        }
        let remaining = snapshot.availableResetCreditsAfterOne
        return copy.text(
            "重置后将剩余 \(remaining) 次",
            "\(remaining) reset "
                + (remaining == 1 ? "credit" : "credits")
                + " will remain after reset"
        )
    }

    private var resetButtonHelp: String {
        canResetQuota
            ? copy.text(
                "检查并确认额度重置",
                "Review and confirm a quota reset"
            )
            : resetActionCaption
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
}
