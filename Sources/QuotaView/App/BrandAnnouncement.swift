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
            // 0.9.9 changes since public v0.9.7-build.1.
            Section(id: "announcements", category: .announcement, items: [
                Item(id: "open-source-and-website", title: copy.text("版本与官网说明", "Version and website"),
                     body: copy.text("0.9.9 是 QuotaView 的最后一个开源版本，项目官网即将上线。", "0.9.9 is the last open-source version of QuotaView. The project’s official website is coming soon."))
            ]),
            Section(id: "highlights", category: .highlight, items: [
                Item(id: "steps-and-plan-progress", title: copy.text("步骤与计划进度", "Current step and plan progress"),
                     body: copy.text("Antigravity 卡片同步显示当前步骤，完成后切换为最终回答；Antigravity 与 Claude Code 接入多步骤计划进度条（步骤全勾后停在 95%，确认结束至 100%）。", "The Antigravity card shows the current step, then the final answer. Plans in Antigravity and Claude Code reach 95% when every step is checked off and 100% when the agent confirms completion.")),
                Item(id: "single-question-replies", title: copy.text("岛内直答单题", "Answer a question from the island"),
                     body: copy.text("Codex 桌面端已打开的单题可直接在灵动岛点选或输入答案，结果自动提交回原问题。", "For a single question open in Codex desktop, select an option or type an answer in the island. Your reply is submitted to the original question.")),
                Item(id: "more-agent-approvals", title: copy.text("更多岛内审批", "More approvals in the island"),
                     body: copy.text("DSH、Antigravity 与 OpenCode 支持岛内处理兼容单题与审批；Antigravity 网络命令可选授权范围，Devin 桌面端与 CLI 可分别开启单次审批。", "Handle supported single questions and approvals from DSH, Antigravity, and OpenCode in the island. Choose the permission scope for Antigravity network commands, and enable one-time approvals separately for Devin desktop and CLI.")),
                Item(id: "native-provider-quotas", title: copy.text("多平台额度查询", "Quotas across providers"),
                     body: copy.text("可直接查询 DeepSeek、Kimi Code、Gemini CLI、OpenCode Go、GitHub Copilot、Cursor 与 Devin 额度或余额，DSH 可沿用已有 DeepSeek 凭据。", "Check quotas or balances directly for DeepSeek, Kimi Code, Gemini CLI, OpenCode Go, GitHub Copilot, Cursor, and Devin. DSH can reuse your existing DeepSeek credentials."))
            ]),
            Section(id: "features", category: .feature, items: [
                Item(id: "terminal-open-conversation", title: copy.text("终端「前往对话」", "Open the original terminal conversation"),
                     body: copy.text("使用 Claude Code、Kimi Code、Gemini CLI、Copilot CLI 或 Devin CLI 时，可一键回到对应的 Terminal 标签页或 iTerm2 会话。", "With Claude Code, Kimi Code, Gemini CLI, Copilot CLI, or Devin CLI, return to the matching Terminal tab or iTerm2 session in one click.")),
                Item(id: "antigravity-background-refresh", title: copy.text("Antigravity 后台刷新", "Antigravity background refresh"),
                     body: copy.text("支持通过官方 agy 在后台刷新额度，缺少有效读数时显示为未知，修复离线记录误报剩余 100% 的问题。", "Refresh quotas in the background with the official agy tool. Missing readings are shown as unknown, fixing an issue where offline records showed 100% remaining."))
            ]),
            Section(id: "improvements", category: .improvement, items: [
                Item(id: "agent-connection-management", title: copy.text("Agent 接入管理", "Manage agent connections"),
                     body: copy.text("11 个 Agent 接入项统一开关与状态提示，支持整行拖动排序，并可在详情页分项检查任务、额度、审批与问答连接。", "All 11 agent entries have a connection switch and status indicator. Drag a row to reorder it, or open its details to check tasks, quotas, approvals, and replies individually.")),
                Item(id: "replayed-questions-and-card-highlights", title: copy.text("问答与高亮修复", "Repeated questions and card highlights"),
                     body: copy.text("修复 OpenCode 已答问题重复弹出、Codex 重连重现已答问题及后台完成卡片持续高亮的问题；多任务并行时高亮仅跟随当前选中卡片。", "Answered OpenCode questions no longer reappear, and reconnecting Codex no longer brings back answered questions. When several tasks run, only the selected card stays highlighted after a background task finishes.")),
                Item(id: "quota-countdown-refresh", title: copy.text("局部刷新优化", "Quota countdown refresh"),
                     body: copy.text("额度倒计时改为局部刷新，减少任务无变化时的重复绘制。", "Only the quota countdown refreshes when its timer ticks, reducing redraws while tasks stay unchanged."))
            ])
        ])
    }
}

/// An explicit release list keeps a preview from becoming a public announcement.
struct BrandAnnouncementCampaign {
    let id: String
    let releaseBuilds: Set<String>

    // Each approved stable release has an independent acknowledgement.
    static let current = Self(id: "brand-refresh-2026", releaseBuilds: ["102", "149", "158", "189", "238", "281"])
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
