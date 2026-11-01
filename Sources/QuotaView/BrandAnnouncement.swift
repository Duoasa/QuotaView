import AppKit
import SwiftUI

/// Content is independent of the campaign's delivery and acknowledgement policy.
struct AnnouncementContent {
    struct VersionTransition {
        let previous: String?
        let current: String
    }

    enum Category {
        case highlight, feature, improvement, announcement, reminder

        func title(copy: AppCopy) -> String {
            switch self {
            case .highlight: return copy.text("亮点", "Highlights")
            case .feature: return copy.text("新功能", "What's new")
            case .improvement: return copy.text("改进", "Improvements")
            case .announcement: return copy.text("公告", "Announcements")
            case .reminder: return copy.text("提醒", "Reminders")
            }
        }

        var symbol: String {
            switch self {
            case .highlight: return "star.fill"
            case .feature: return "sparkles"
            case .improvement: return "bolt.fill"
            case .announcement: return "megaphone.fill"
            case .reminder: return "bell.fill"
            }
        }

        var color: Color {
            switch self {
            case .highlight: return .orange
            case .feature: return .purple
            case .improvement: return .blue
            case .announcement: return .indigo
            case .reminder: return .teal
            }
        }
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let body: String
    }

    struct Section: Identifiable {
        let id: String
        let category: Category
        let items: [Item]
        var initiallyExpanded = true
    }

    let title: String
    let version: VersionTransition?
    let sections: [Section]

    static func current(copy: AppCopy, bundle: Bundle = .main) -> Self {
        // Do not infer an upgrade source from the latest public version: users may skip releases.
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap { $0.isEmpty ? nil : VersionTransition(previous: nil, current: $0) }
        return Self(title: copy.text("更新与公告", "Updates & announcements"), version: version, sections: [
            Section(id: "highlights", category: .highlight, items: [
                Item(id: "appearance", title: copy.text("全新外观", "Fresh look"),
                     body: copy.text("更新应用与 Agent 图标，优化任务卡片着色和完成态流动高光。", "Refreshed app and agent icons, refined task card colors, and flowing highlights for completed tasks."))
            ]),
            Section(id: "improvements", category: .improvement, items: [
                Item(id: "settings", title: copy.text("设置体验", "Settings experience"),
                     body: copy.text("重新整理设置布局与分类，优化灵动岛预览、玻璃分层和控件样式。", "Reorganized settings with a clearer layout, improved island previews, glass layers, and refined controls."))
            ]),
            Section(id: "features", category: .feature, items: [
                Item(id: "agent-integrations", title: copy.text("Agent 接入（预览）", "Agent integrations (preview)"),
                     body: copy.text("新增 Cursor、Gemini CLI、OpenCode、GitHub Copilot CLI 任务状态接入。", "Added task status integrations for Cursor, Gemini CLI, OpenCode, and GitHub Copilot CLI.")),
                Item(id: "languages", title: copy.text("多语言支持", "More languages"),
                     body: copy.text("新增日语、韩语、繁体中文和西班牙语。", "Added Japanese, Korean, Traditional Chinese, and Spanish.")),
                Item(id: "reset-protection", title: copy.text("重置保护", "Reset protection"),
                     body: copy.text("新增「禁用重置卡使用」选项，避免误触 Codex 额度重置。", "Added Disable reset credit use to help prevent accidental Codex quota resets."))
            ])
        ])
    }
}

/// An explicit release list keeps a preview from becoming a public announcement.
struct BrandAnnouncementCampaign {
    let id: String
    let releaseBuilds: Set<String>

    // This release is approved; add the second exact build when its release is scheduled.
    static let current = Self(id: "brand-refresh-2026", releaseBuilds: ["102"])
    var storageKey: String { "announcement.\(id).acknowledgedBuilds" }

    func shouldPresent(build: String, acknowledged: Set<String>) -> Bool {
        releaseBuilds.contains(build) && !acknowledged.contains(build)
    }

    func acknowledging(build: String, in acknowledged: Set<String>) -> Set<String> {
        guard releaseBuilds.contains(build) else { return acknowledged }
        return acknowledged.union([build])
    }
}

@MainActor
final class BrandAnnouncementController: NSObject, NSWindowDelegate {
    static let shared = BrandAnnouncementController()
    private var controller: NSWindowController?
    private var acknowledge: (() -> Void)?

    static var isAvailable: Bool {
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.quotaview.development073" { return true }
        #endif
        return !BrandAnnouncementCampaign.current.releaseBuilds.isEmpty
    }

    func presentOnLaunch(copy: AppCopy, bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        #if DEBUG
        if bundle.bundleIdentifier == "com.quotaview.development073",
           ProcessInfo.processInfo.arguments.contains("--preview-brand-announcement") {
            showPreview(copy: copy)
            return
        }
        #endif
        let campaign = BrandAnnouncementCampaign.current
        guard bundle.bundleIdentifier == "com.quotaview.menubar",
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              campaign.shouldPresent(build: build, acknowledged: Set(defaults.stringArray(forKey: campaign.storageKey) ?? []))
        else { return }
        present(copy: copy, preview: false) {
            let seen = Set(defaults.stringArray(forKey: campaign.storageKey) ?? [])
            defaults.set(campaign.acknowledging(build: build, in: seen).sorted(), forKey: campaign.storageKey)
        }
    }

    func showPreview(copy: AppCopy) {
        // Manual viewing never consumes either release's first-launch reminder.
        present(copy: copy, preview: BrandAnnouncementCampaign.current.releaseBuilds.isEmpty, onDismiss: nil)
    }

    private func present(copy: AppCopy, preview: Bool, onDismiss: (() -> Void)?) {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        acknowledge = onDismiss
        let announcement = AnnouncementContent.current(copy: copy)
        let content = AnnouncementView(copy: copy, announcement: announcement, preview: preview) { [weak self] in
            self?.controller?.window?.performClose(nil)
        }
        let window = BrandAnnouncementWindow(contentViewController: NSHostingController(rootView: content))
        window.title = announcement.title
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        SettingsWindowMetrics.applyOuterShape(to: window)
        window.contentMinSize = NSSize(width: 400, height: 360)
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 900, height: 900)
        window.setContentSize(NSSize(width: min(460, available.width - 48),
                                     height: min(580, available.height - 64)))
        window.center()
        controller = NSWindowController(window: window)
        controller?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        let action = acknowledge
        acknowledge = nil
        controller = nil
        action?()
    }
}

private final class BrandAnnouncementWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

private enum BrandAnnouncementResources {
    @MainActor
    static let appIcon: NSImage = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        // Load the original PNG directly, without asset-catalog or ICNS representations.
        guard let url = bundle.url(forResource: "QuotaViewAppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            assertionFailure("Missing announcement PNG icon")
            return NSImage(size: NSSize(width: 64, height: 64))
        }
        return image
    }()
}

private struct AnnouncementView: View {
    let copy: AppCopy
    let announcement: AnnouncementContent
    let preview: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if preview {
                    Text(copy.text("预览", "Preview"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }.frame(height: 24).padding(.horizontal, 20).padding(.top, 4)

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(nsImage: BrandAnnouncementResources.appIcon)
                            .renderingMode(.original)
                            .resizable().interpolation(.high)
                            .scaledToFit().frame(width: 64, height: 64)
                            .accessibilityHidden(true)
                        Text(announcement.title)
                            .font(.system(size: 18, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        if let version = announcement.version {
                            HStack(spacing: 12) {
                                if let previous = version.previous {
                                    Text(previous).foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                        .accessibilityLabel(copy.text("更新至", "updated to"))
                                }
                                Text(version.current)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(.primary.opacity(0.04), in: Capsule())
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.09), lineWidth: 1))
                            .accessibilityElement(children: .combine)
                        }
                    }.padding(.top, 8).padding(.bottom, 4)

                    VStack(spacing: 10) {
                        ForEach(announcement.sections.filter { !$0.items.isEmpty }) { section in
                            AnnouncementSectionView(copy: copy, section: section)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }

            Divider()
            Button(action: dismiss) {
                Text(copy.text("好", "OK"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(BrandAnnouncementButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea(.container, edges: .top)
        .onExitCommand(perform: dismiss)
    }
}

private struct AnnouncementSectionView: View {
    let copy: AppCopy
    let section: AnnouncementContent.Section
    @State private var expanded: Bool

    init(copy: AppCopy, section: AnnouncementContent.Section) {
        self.copy = copy
        self.section = section
        _expanded = State(initialValue: section.initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: section.category.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(section.category.color.gradient,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .accessibilityHidden(true)
                    Text(section.category.title(copy: copy))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(expanded ? copy.text("已展开", "Expanded") : copy.text("已收起", "Collapsed"))
            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                            (Text(item.title + copy.text("：", ": ")).fontWeight(.semibold)
                             + Text(item.body).foregroundColor(.secondary))
                                .font(.system(size: 12)).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .background(.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.primary.opacity(0.1), lineWidth: 1))
    }
}

private struct BrandAnnouncementButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}
