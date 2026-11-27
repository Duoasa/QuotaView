import AppKit
import QuotaViewCore
import SwiftUI

extension SettingsView {
    // About uses the page's solid background and the exact running build.
    private var aboutIdentity: some View {
        VStack(spacing: 18) {
            Image(nsImage: SettingsFeedbackResources.appIcon)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel(copy.text("QuotaView 应用图标", "QuotaView app icon"))
            Text("QuotaView")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 4) {
                Text(copy.text("Codex 任务与用量灵动岛", "Codex task and usage island"))
                Text(versionAndBuildLabel)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let buildDateLabel {
                Text(buildDateLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
               !copyright.isEmpty {
                Text(copyright)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    var aboutSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            aboutIdentity
            settingsSection(copy.text("软件更新", "Software updates")) {
                NativeSettingsCard {
                    if updateController.availability == .available {
                        NativeSettingsRow(title: copy.text("自动检查更新", "Automatically check for updates"),
                            subtitle: copy.text("每 24 小时；安装前确认。", "Every 24 hours; confirm before installing."),
                            symbol: "clock.arrow.circlepath") {
                            Toggle(copy.text("自动检查更新", "Automatically check for updates"), isOn: Binding(
                                get: { updateController.automaticallyChecksForUpdates },
                                set: { updateController.setAutomaticallyChecksForUpdates($0) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        }
                        NativeSettingsDivider()
                        HStack {
                            Spacer(minLength: 0)
                            Button(copy.text("检查更新…", "Check for Updates…")) { updateController.checkForUpdates() }
                                .nativeSettingsActionStyle().disabled(!updateController.canCheckForUpdates).help(updateCheckHelpText)
                        }.settingsRowInsets()
                    } else {
                        NativeSettingsRow(title: copy.text("当前构建", "Current build"), subtitle: updateStatusText,
                            symbol: "hammer.fill") {}
                    }
                }
            }
            if BrandAnnouncementController.isAvailable {
                NativeSettingsCard {
                    NativeSettingsRow(title: copy.text("更新与公告", "Updates & announcements"),
                        symbol: "list.bullet.clipboard.fill") {
                        Button(copy.text("查看", "View")) {
                            BrandAnnouncementController.shared.showPreview(copy: copy)
                        }.nativeSettingsActionStyle()
                    }
                }
            }
            NativeSettingsCard {
                NativeSettingsRow(title: "GitHub", subtitle: "Duoasa / QuotaView", symbol: "chevron.left.forwardslash.chevron.right") {
                    Link(destination: SettingsFeedbackResources.repositoryURL) {
                        Label(copy.text("访问", "Visit"), systemImage: "arrow.up.right")
                    }
                    .nativeSettingsActionStyle()
                    .help(copy.text("在浏览器中打开 QuotaView GitHub 仓库", "Open the QuotaView GitHub repository in your browser"))
                    .accessibilityLabel(copy.text("访问 QuotaView GitHub 仓库", "Visit the QuotaView GitHub repository"))
                }
            }
        }
    }

    private var updateCheckHelpText: String {
        if updateController.availability == .available {
            return copy.text(
                "检查是否有新版本。",
                "Check for a new version."
            )
        }
        return copy.text(
            "当前构建不支持在线更新。",
            "This build does not support online updates."
        )
    }

    private var updateStatusText: String {
        switch updateController.availability {
        case .available:
            return copy.text(
                "每 24 小时检查一次，安装前会询问。",
                "Check every 24 hours and ask before installing."
            )
        case .debugBuild:
            return copy.text(
                "调试版不支持在线更新。",
                "Online updates are unavailable in debug builds."
            )
        case .notApplicationBundle:
            return copy.text(
                "当前运行方式不支持在线更新。",
                "The current launch environment does not support online updates."
            )
        case .unexpectedBundleIdentifier,
             .untrustedSignature:
            return copy.text(
                "请使用正式签名版本以获取更新。",
                "Use an officially signed release to receive updates."
            )
        case .invalidConfiguration:
            return copy.text(
                "更新配置无效，请重新安装正式版。",
                "Update configuration is invalid. Reinstall the official release."
            )
        }
    }

    private var buildDateLabel: String? {
        guard let executableURL = Bundle.main.executableURL,
              let date = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = preferences.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let formatted = formatter.string(from: date)
        return copy.text("构建于 \(formatted)", "Built on \(formatted)")
    }

    private var versionAndBuildLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.4.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewDisplayBuildNumber"
        ) as? String ?? Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        let isPreview = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewReleaseChannel"
        ) as? String == "preview"
        let previewNumber = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewPreviewNumber"
        ) as? String ?? "1"
        let channelSuffix = isPreview ? " · Preview \(previewNumber)" : ""
        return copy.text(
            "版本 \(version)（\(build)）\(channelSuffix)",
            "Version \(version) (\(build))\(channelSuffix)"
        )
    }
}
