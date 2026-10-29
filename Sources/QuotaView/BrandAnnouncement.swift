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
                Item(id: "news", title: copy.text("重要消息，一处查看", "Important news, in one place"),
                     body: copy.text("新功能、体验改进和产品公告，现在都可以在这里查看。", "Discover new features, improvements and product announcements here."))
            ]),
            Section(id: "features", category: .feature, items: [
                Item(id: "sections", title: copy.text("按分类阅读", "Browse by category"),
                     body: copy.text("点击分组标题展开或收起，向下滚动即可阅读更多内容。", "Expand or collapse each section, and scroll to read more.")),
                Item(id: "reopen", title: copy.text("随时回看", "Revisit anytime"),
                     body: copy.text("关闭后，可从「设置 → 关于 → 更新与公告」再次打开。", "Open this window again from Settings → About → Updates & announcements."))
            ]),
            Section(id: "improvements", category: .improvement, items: [
                Item(id: "settings", title: copy.text("更自然的设置选择", "Native settings menus"),
                     body: copy.text("语言、固定屏幕、停留时间和代理协议使用系统下拉菜单，当前选项更清晰。", "Language, pinned display, display duration and proxy protocol now use native menus with a clear selection.")),
                Item(id: "proxy", title: copy.text("更简洁的网络代理设置", "Simpler proxy settings"),
                     body: copy.text("直接查看代理配置、测试连接和处理错误，减少界面干扰。", "Access proxy configuration, connection testing and error feedback in a simpler layout."))
            ]),
            Section(id: "brand", category: .announcement, items: [
                Item(id: "brand-refresh", title: copy.text("QuotaView 品牌升级预告", "A fresh look for QuotaView"),
                     body: copy.text("我们正在准备新的品牌形象。继续照常使用，后续进展会在应用内告知。", "We're preparing a new visual identity. Keep using the app as usual; more details will follow here."))
            ])
        ])
    }
}

/// An explicit release list keeps a preview from becoming a public announcement.
struct BrandAnnouncementCampaign {
    let id: String
    let releaseBuilds: Set<String>

    // Configure the two exact release build IDs after the announcement is accepted.
    static let current = Self(id: "brand-refresh-2026", releaseBuilds: [])
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
                        Image(nsImage: SettingsFeedbackResources.appIcon)
                            .resizable().scaledToFit().frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
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
