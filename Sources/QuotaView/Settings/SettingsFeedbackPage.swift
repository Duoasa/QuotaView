import AppKit
import QuotaViewCore
import SwiftUI

extension SettingsView {
    func feedbackSettings(showQRCode: @escaping () -> Void) -> some View {
        NativeSettingsCard {
            Button(action: showQRCode) {
                feedbackRow(
                    title: copy.text("QQ群", "QQ group"),
                    detail: copy.text("群号：1108649282", "Group: 1108649282"),
                    symbol: "qrcode"
                )
            }
            .buttonStyle(SettingsFeedbackRowStyle())
            .help(copy.text("显示群二维码", "Show the group QR code"))

            NativeSettingsDivider()
            Link(destination: SettingsFeedbackResources.issuesURL) {
                feedbackRow(
                    title: "GitHub Issues",
                    detail: "Duoasa / QuotaView",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    trailingSymbol: "arrow.up.right"
                )
            }
            .buttonStyle(SettingsFeedbackRowStyle())
            .help(copy.text("在浏览器中打开反馈页面", "Open the feedback page in your browser"))
        }
    }

    private func feedbackRow(title: String, detail: String, symbol: String,
                             trailingSymbol: String = "chevron.right") -> some View {
        NativeSettingsRow(title: title, subtitle: detail, symbol: symbol) {
            Image(systemName: trailingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    func feedbackQRCode(close: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            if let image = SettingsFeedbackResources.groupQRCode {
                SettingsFeedbackQRCodeImage(image: image)
                    .accessibilityLabel(copy.text(
                        "QuotaView 反馈群二维码，群号 1108649282",
                        "QuotaView feedback group QR code, group 1108649282"
                    ))
            } else {
                Text(copy.text("二维码暂时无法显示。", "The QR code is unavailable."))
                    .foregroundStyle(.secondary)
            }
            Button(copy.text("关闭", "Close"), action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 360)
        .background(SettingsPalette.canvas)
    }
}

enum SettingsFeedbackResources {
    @MainActor
    static let appIcon: NSImage = {
        // Prefer the original PNG; the compiled ICNS only carries reduced representations.
        if let image = NSImage(named: "QuotaViewAppIcon") { return image }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApplication.shared.applicationIconImage
    }()

    static let repositoryURL = URL(string: "https://github.com/Duoasa/QuotaView")!
    static let issuesURL = URL(string: "https://github.com/Duoasa/QuotaView/issues")!

    @MainActor
    static let groupQRCode: NSImage? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "QuotaViewFeedbackQQ", withExtension: "jpg")
            .flatMap { NSImage(contentsOf: $0) }
    }()
}

/// Display only the QR region of the bundled 1284 × 2289 poster, including
/// its quiet border. The original pixels/resource stay intact at every size.
private struct SettingsFeedbackQRCodeImage: View {
    let image: NSImage
    private static let region = CGRect(x: 180.0 / 1284, y: 724.0 / 2289,
                                       width: 924.0 / 1284, height: 924.0 / 2289)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / Self.region.width
            let height = geometry.size.height / Self.region.height
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: width, height: height)
                .offset(x: -width * Self.region.minX, y: -height * Self.region.minY)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

private struct SettingsFeedbackRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.05 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}
