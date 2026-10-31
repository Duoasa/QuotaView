import AppKit
import SwiftUI

// Completion presents the original assistant answer; live progress retains its
// latest public progress and tool activity.
struct IslandTaskDetailSelection {
    let focus: [IslandTraceEntry]
    let history: [IslandTraceEntry]
    init(data: IslandTaskDetailData) {
        if data.status == .completed {
            focus = data.finalResponse.map { [$0] } ?? []
            history = []
            return
        }
        let entries = data.visibleEntries
        let message = (data.status == .failed ? entries.last(where: { $0.kind == .failure && $0.publicItem?.category != .command && $0.publicItem?.category != .fileChange }) : nil)
            ?? entries.last(where: { $0.publicItem == nil || $0.publicItem?.category == .message })
        let tools = entries.filter { $0.publicItem?.category == .command || $0.publicItem?.category == .fileChange }
        let tool = (data.status == .failed ? tools.last(where: { $0.kind == .failure }) : nil) ?? tools.last
        var selected: [IslandTraceEntry] = []
        if let message { selected.append(message) }
        if let tool, !selected.contains(where: { $0.id == tool.id }) { selected.append(tool) }
        focus = selected
        let ids = Set(selected.map(\.id))
        history = entries.filter { !ids.contains($0.id) }
    }
}

enum IslandTaskDetailMode: Equatable {
    case progress, approval, completion, failure, unavailable
    init(data: IslandTaskDetailData) {
        if data.confirmation != nil { self = .approval }
        else {
            switch data.status {
            case .completed: self = .completion
            case .cancelled: self = .unavailable
            case .failed: self = .failure
            case .unknown: self = .unavailable
            default: self = .progress
            }
        }
    }
    var symbol: String {
        switch self {
        case .progress: "text.bubble"
        case .approval: "hand.raised"
        case .completion: "checkmark.circle"
        case .failure: "exclamationmark.circle"
        case .unavailable: "questionmark.circle"
        }
    }
    func title(data: IslandTaskDetailData, english: Bool, language: AppPreferences.Language? = nil) -> String {
        let copy = AppCopy(language: language ?? (english ? .english : .simplifiedChinese))
        return switch self {
        case .progress: data.status == .compacting ? (copy.text("上下文压缩", "Context compaction"))
            : (copy.text("任务进展", "Progress"))
        case .approval: copy.text("待确认", "Needs confirmation")
        case .completion: data.status == .cancelled ? (copy.text("操作已取消", "Operation cancelled"))
            : (copy.text("完成结果", "Result"))
        case .failure: copy.text("执行失败", "Execution failed")
        case .unavailable: copy.text("状态不可用", "Activity unavailable")
        }
    }
}

struct IslandTracePresentation {
    let entry: IslandTraceEntry
    let primary: String
    let output: String?
    let canExpand: Bool
    let expanded: Bool
    var code: Bool { entry.publicItem?.category != nil && entry.publicItem?.category != .message }
    var compactCommand: Bool { entry.publicItem?.category == .command && !expanded }
    var showsHeader: Bool { code || canExpand }
    init(entry: IslandTraceEntry, english: Bool, expanded: Bool, revealOutput: Bool = true, language: AppPreferences.Language? = nil) {
        self.entry = entry; self.expanded = expanded
        let original = entry.text.value(language ?? (english ? .english : .simplifiedChinese))
        let originalOutput = entry.publicItem?.output.flatMap { $0.isEmpty ? nil : $0 }
        func preview(_ value: String, lines: Int, characters: Int) -> String {
            String(value.components(separatedBy: "\n").prefix(lines).joined(separator: "\n").prefix(characters))
        }
        let shortPrimary = entry.publicItem?.category == .fileChange ? preview(original, lines: 5, characters: 500)
            : (entry.publicItem?.category == .command ? preview(original, lines: 2, characters: 120)
                : original)
        let shortOutput = revealOutput && entry.publicItem?.category != .command ? originalOutput.map { preview($0, lines: 3, characters: 480) } : nil
        canExpand = entry.publicItem?.category == .command || shortPrimary != original || shortOutput != originalOutput
        primary = expanded ? original : shortPrimary
        output = expanded ? originalOutput : shortOutput
    }
}

// Cache text geometry once per content/width change. The outer task list uses
// the bounded card height; only the detail body scrolls through longer content.
struct IslandTaskDetailMetrics {
    static let padding: CGFloat = IslandVibeLayout.contentInset
    static let horizontalPadding: CGFloat = IslandVibeLayout.contentInset
    static let headerHeight: CGFloat = 24
    static let bodyGap: CGFloat = 6
    static let bodyFont: CGFloat = 12
    static let scrollGutter: CGFloat = 12
    static let gap: CGFloat = 4
    static let entryGap: CGFloat = 6
    static let entryPadding: CGFloat = 6
    static let eventHeader: CGFloat = 18
    let mode: IslandTaskDetailMode
    let focusCount: Int
    let presentations: [IslandTracePresentation]
    let entryHeights: [CGFloat]
    let primaryHeights: [CGFloat]
    let proseLayouts: [IslandMarkdownResultLayout?]
    let outputHeights: [CGFloat]
    let result: IslandMarkdownResultLayout?
    let cardWidth: CGFloat
    let contentWidth: CGFloat
    let bodyHeight: CGFloat
    let height: CGFloat
    var viewportHeight: CGFloat { height - Self.padding * 2 - Self.headerHeight - Self.bodyGap }
    var overflows: Bool { bodyHeight > viewportHeight }

    init(data: IslandTaskDetailData, width: CGFloat, english: Bool, expandedEntries: Set<UUID> = [], language: AppPreferences.Language? = nil) {
        mode = .init(data: data)
        cardWidth = width
        let selection = IslandTaskDetailSelection(data: data)
        focusCount = data.confirmation == nil ? selection.focus.count : 0
        let usable = max(80, width - Self.horizontalPadding * 2 - Self.scrollGutter)
        contentWidth = usable
        result = mode == .completion ? data.finalResponse.map {
            IslandMarkdownResultLayout(source: $0.text.value(language ?? (english ? .english : .simplifiedChinese)), width: usable)
        } : nil
        let entries = data.confirmation == nil && mode != .completion ? selection.focus : []
        let items = entries.map { IslandTracePresentation(entry: $0, english: english,
            expanded: expandedEntries.contains($0.id), revealOutput: !data.running, language: language) }
        presentations = items
        let prose = items.map { item -> IslandMarkdownResultLayout? in
            item.code ? nil : IslandMarkdownResultLayout(plainText: item.primary, width: usable)
        }
        proseLayouts = prose
        let primary = items.indices.map { index in
            let item = items[index]
            if let layout = prose[index] { return layout.height }
            let width = max(40, usable - (item.code ? Self.entryPadding * 2 : 0))
            let full = IslandTaskTextMetrics.height(item.primary, size: item.code ? 11 : Self.bodyFont, code: item.code, width: width)
            return item.compactCommand ? min(full, IslandTaskTextMetrics.height("Ag\nAg", size: 11, code: true, width: width)) : full
        }
        let outputs = items.map { $0.output.map { IslandTaskTextMetrics.height($0, code: true, width: max(40, usable - Self.entryPadding * 2)) } ?? 0 }
        primaryHeights = primary; outputHeights = outputs
        entryHeights = items.indices.map { index in
            let item = items[index]
            return (item.code ? Self.entryPadding * 2 : 0) + (item.showsHeader ? Self.eventHeader + Self.gap : 0) + primary[index]
                + (item.output != nil ? Self.gap + 16 + 4 + outputs[index] : 0)
                + (item.entry.publicItem?.sourceTruncated == true ? Self.gap + 18 : 0)
        }
        var sections: [CGFloat] = []
        if mode == .completion {
            sections.append(result?.height ?? 20)
            if result != nil, data.finalResponse?.publicItem?.sourceTruncated == true { sections.append(18) }
        } else {
            if items.isEmpty { sections.append(20) }
            sections.append(contentsOf: entryHeights.prefix(focusCount))

        }
        bodyHeight = sections.reduce(0, +) + CGFloat(max(0, sections.count - 1)) * Self.entryGap
        let naturalHeight = Self.padding * 2 + Self.headerHeight + Self.bodyGap + bodyHeight
        height = min(IslandVibeLayout.maximumDetailViewportHeight,
            max(IslandVibeLayout.minimumDetailHeight, naturalHeight))
    }

}

struct IslandTaskDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    let data: IslandTaskDetailData
    let metrics: IslandTaskDetailMetrics
    let english: Bool
    let onClose: () -> Void
    var onDisclosure: (UUID) -> Void = { _ in }
    private var muted: Color { Color(nsColor: IslandTextPalette.muted) }
    private var secondary: Color { Color(nsColor: IslandTextPalette.secondary) }
    private var amber: Color { Color(red: 1, green: 0.76, blue: 0.44) }
    private var failure: Color { Color(red: 0.95, green: 0.43, blue: 0.42) }
    private var accent: Color { metrics.mode == .approval ? amber : (metrics.mode == .failure ? failure : .white) }
    private func text(_ zh: LocalizedCopy, _ en: LocalizedCopy) -> String { AppCopy(language: appLanguage ?? (english ? .english : .simplifiedChinese)).text(zh, en) }
    private var agent: String { data.provider.displayName }
    private var sourceName: (String, String) {
        switch data.provider {
        case .codex: (" Codex ", "Codex")
        case .claudeCode: ("Claude Code 会话记录", "the Claude Code transcript")
        case .dsh, .kimiCode: (data.provider.displayName, data.provider.displayName)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTaskDetailMetrics.bodyGap) {
            HStack(spacing: 8) {
                Image(systemName: metrics.mode.symbol).font(.system(size: 12))
                Text(metrics.mode.title(data: data, english: english, language: appLanguage)).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(secondary).frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint(text("关闭详情", "Close details"))
                    .accessibilityLabel(text("关闭详情", "Close details"))
            }.foregroundStyle(accent).frame(height: IslandTaskDetailMetrics.headerHeight)
            ScrollView(.vertical) {
                Group {
                    if metrics.mode == .completion { result } else { progress }
                }
                .frame(width: metrics.contentWidth, alignment: .leading)
                .frame(height: metrics.bodyHeight, alignment: .topLeading)
                .padding(.trailing, IslandTaskDetailMetrics.scrollGutter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IslandDetailScrollConfiguration())
            }
            .scrollIndicators(metrics.overflows ? .visible : .hidden)
            .modifier(IslandSoftScrollEdges())
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(!metrics.overflows)
            .frame(width: metrics.cardWidth - IslandTaskDetailMetrics.horizontalPadding * 2,
                height: metrics.viewportHeight)
            .accessibilityLabel(text("详情内容", "Detail content"))
        }.padding(.horizontal, IslandTaskDetailMetrics.horizontalPadding)
            .padding(.vertical, IslandTaskDetailMetrics.padding)
            .frame(width: metrics.cardWidth, height: metrics.height, alignment: .top)
            // Keep the glass outside the clipped body scroll view so its native
            // contour and highlights remain a single, complete card surface.
            .islandGlass(IslandVibeLayout.rowShape, tint: .black.opacity(0.42), solidTint: Color(white: 0.055))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: IslandTaskDetailMetrics.entryGap) {
            if let layout = metrics.result {
                IslandMarkdownResultView(layout: layout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: layout.height)
                if data.finalResponse?.publicItem?.sourceTruncated == true {
                    Text(text("回答超出本地缓存，请在\(sourceName.0)查看后续内容", "Answer exceeds the local cache; continue in \(sourceName.1)"))
                        .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1).truncationMode(.middle).frame(height: 18)
                }
            } else {
                Text(data.provider == .dsh || data.provider == .kimiCode
                    ? text("任务已完成，请在 \(agent) 查看完整回答", "Task completed. View the full answer in \(agent)")
                    : text("最终回答尚未同步，请在\(sourceName.0)查看", "Final answer has not synced; view it in \(sourceName.1)"))
                    .font(.system(size: 12)).foregroundStyle(secondary).frame(height: 20)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: IslandTaskDetailMetrics.entryGap) {
            if metrics.presentations.isEmpty {
                Text(text("暂无可公开的进展内容", "No public progress content available"))
                    .font(.system(size: 12)).foregroundStyle(secondary).frame(height: 20)
            }
            ForEach(Array(metrics.presentations.prefix(metrics.focusCount).enumerated()), id: \.element.entry.id) { index, item in
                event(item, index: index, historical: false)
            }
        }
    }
    private func eventTitle(_ item: IslandTracePresentation, historical: Bool) -> String {
        guard let source = item.entry.publicItem else { return text("公开事件", "Public event") }
        switch source.category {
        case .message: return historical ? text("进度消息", "Progress message") : text("最近进展", "Latest update")
        case .command: return text("命令", "Command")
        case .fileChange: return text("文件修改", "File changes")
        }
    }
    private func event(_ item: IslandTracePresentation, index: Int, historical: Bool) -> some View {
        VStack(alignment: .leading, spacing: IslandTaskDetailMetrics.gap) {
            if item.showsHeader {
                HStack(spacing: 6) {
                    if item.code {
                        Image(systemName: item.entry.publicItem?.category == .fileChange ? "doc.text" : "terminal")
                            .font(.system(size: 10))
                    }
                    Text(eventTitle(item, historical: historical)).font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 8)
                    if let source = item.entry.publicItem, item.code {
                        if let exit = source.exitCode, exit != 0 {
                            Text("exit \(exit)").font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(failure)
                        } else if let status = source.status, status != "completed" {
                            Text(status == "failed" ? text("失败", "Failed") : status)
                                .font(.system(size: 10)).foregroundStyle(source.status == "failed" ? failure : muted)
                        }
                    }
                    if item.canExpand {
                        Button { onDisclosure(item.entry.id) } label: {
                            HStack(spacing: 4) {
                                Text(item.expanded ? text("收起", "Collapse") : text("查看原文", "Source"))
                                Image(systemName: item.expanded ? "chevron.up" : "chevron.down")
                            }.font(.system(size: 10)).foregroundStyle(secondary)
                                .padding(.horizontal, 6).frame(height: IslandTaskDetailMetrics.eventHeader).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.foregroundStyle(muted).frame(height: IslandTaskDetailMetrics.eventHeader)
            }
            if let layout = metrics.proseLayouts[index] {
                IslandMarkdownResultView(layout: layout)
                    .frame(width: layout.width, height: layout.height, alignment: .topLeading)
            } else {
                Text(item.primary).font(.system(size: item.code ? 11 : IslandTaskDetailMetrics.bodyFont, design: item.code ? .monospaced : .default))
                    .lineLimit(item.compactCommand ? 2 : nil).truncationMode(.tail)
                    .lineSpacing(2).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: metrics.primaryHeights[index], alignment: .topLeading)
                    .textSelection(.enabled)
            }
            if let output = item.output {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("输出", "Output")).font(.system(size: 10)).foregroundStyle(muted).frame(height: 16)
                    Text(output).font(.system(size: 11, design: .monospaced)).lineSpacing(2).foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: metrics.outputHeights[index], alignment: .topLeading).textSelection(.enabled)
                }
            }
            if item.entry.publicItem?.sourceTruncated == true {
                Text(text("本地缓存已截断，请在\(sourceName.0)查看完整原文", "Local cache truncated; see the full source in \(sourceName.1)"))
                    .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1).truncationMode(.middle).frame(height: 18)
            }
        }.padding(.horizontal, item.code ? IslandTaskDetailMetrics.entryPadding : 0)
            .padding(.vertical, item.code ? IslandTaskDetailMetrics.entryPadding : 0)
            .frame(height: metrics.entryHeights[index], alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.code ? Color(red: 0.075, green: 0.075, blue: 0.075) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.code ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1))
            .accessibilityHint(item.entry.publicItem.map { "\(agent) · \($0.sourceID)" } ?? text("\(agent) 状态", "\(agent) status"))
    }

}

// A user's "always show scroll bars" preference can select a legacy scroller
// that takes layout width. Keep this compact, explicitly sized viewport on the
// overlay style so revealing its rail cannot widen the card or the task list.
private struct IslandDetailScrollConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> IslandDetailScrollProbe { IslandDetailScrollProbe() }
    func updateNSView(_ view: IslandDetailScrollProbe, context: Context) { view.configure() }
}

private final class IslandDetailScrollProbe: NSView {
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configure() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func layout() { super.layout(); configure() }
    func configure() {
        guard let scroll = enclosingScrollView else { return }
        if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
    }
}
