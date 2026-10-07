import AppKit
import SwiftUI

// Completion presents the original assistant answer; live progress retains its
// bounded trace and optional tool history.
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
    func title(data: IslandTaskDetailData, english: Bool) -> String {
        switch self {
        case .progress: data.status == .compacting ? (english ? "Context compaction" : "上下文压缩")
            : (english ? "Progress and execution" : "公开进展与执行")
        case .approval: english ? "Needs confirmation" : "待确认"
        case .completion: data.status == .cancelled ? (english ? "Operation cancelled" : "操作已取消")
            : (english ? "Result" : "完成结果")
        case .failure: english ? "Execution failed" : "执行失败"
        case .unavailable: english ? "Activity unavailable" : "状态不可用"
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
    init(entry: IslandTraceEntry, english: Bool, expanded: Bool, revealOutput: Bool = true) {
        self.entry = entry; self.expanded = expanded
        let original = entry.text.value(english)
        let originalOutput = entry.publicItem?.output.flatMap { $0.isEmpty ? nil : $0 }
        func preview(_ value: String, lines: Int, characters: Int) -> String {
            String(value.components(separatedBy: "\n").prefix(lines).joined(separator: "\n").prefix(characters))
        }
        let shortPrimary = entry.publicItem?.category == .fileChange ? preview(original, lines: 5, characters: 500)
            : (entry.publicItem?.category == .command ? preview(original, lines: 2, characters: 120)
                : preview(original, lines: 4, characters: 220))
        let shortOutput = revealOutput && entry.publicItem?.category != .command ? originalOutput.map { preview($0, lines: 3, characters: 480) } : nil
        canExpand = entry.publicItem?.category == .command || shortPrimary != original || shortOutput != originalOutput
        primary = expanded ? original : shortPrimary
        output = expanded ? originalOutput : shortOutput
    }
}

// Shared, cached outside this view: native rail and visibility use these exact
// content heights. No nested scroll container or per-frame text measurement.
struct IslandTaskDetailMetrics {
    static let padding: CGFloat = 14
    static let horizontalPadding: CGFloat = 16
    static let headerHeight: CGFloat = 28
    static let gap: CGFloat = 8
    static let entryGap: CGFloat = 12
    static let entryPadding: CGFloat = 10
    static let eventHeader: CGFloat = 22
    static let historyHeader: CGFloat = 28
    let mode: IslandTaskDetailMode
    let focusCount: Int
    let historyCount: Int
    let showsHistory: Bool
    let presentations: [IslandTracePresentation]
    let entryHeights: [CGFloat]
    let primaryHeights: [CGFloat]
    let outputHeights: [CGFloat]
    let result: IslandMarkdownResultLayout?
    let height: CGFloat

    init(data: IslandTaskDetailData, width: CGFloat, english: Bool, expandedEntries: Set<UUID> = [], showsHistory: Bool = false) {
        mode = .init(data: data)
        self.showsHistory = showsHistory && mode != .completion
        let selection = IslandTaskDetailSelection(data: data)
        focusCount = data.confirmation == nil ? selection.focus.count : 0
        historyCount = data.confirmation == nil ? selection.history.count : 0
        let usable = max(80, width - Self.horizontalPadding * 2)
        result = mode == .completion ? data.finalResponse.map {
            IslandMarkdownResultLayout(source: $0.text.value(english), width: usable)
        } : nil
        let entries = data.confirmation == nil && mode != .completion ? selection.focus + (showsHistory ? selection.history : []) : []
        let items = entries.map { IslandTracePresentation(entry: $0, english: english,
            expanded: expandedEntries.contains($0.id), revealOutput: !data.running) }
        presentations = items
        let primary = items.map { item in
            let width = max(40, usable - (item.code ? Self.entryPadding * 2 : 0))
            let full = IslandTaskTextMetrics.height(item.primary, size: item.code ? 11 : 13, code: item.code, width: width)
            return item.compactCommand ? min(full, IslandTaskTextMetrics.height("Ag\nAg", size: 11, code: true, width: width)) : full
        }
        let outputs = items.map { $0.output.map { IslandTaskTextMetrics.height($0, code: true, width: max(40, usable - Self.entryPadding * 2)) } ?? 0 }
        primaryHeights = primary; outputHeights = outputs
        entryHeights = items.indices.map { index in
            let item = items[index]
            return (item.code ? Self.entryPadding * 2 : 4) + Self.eventHeader + Self.gap + primary[index]
                + (item.output != nil ? Self.gap + 16 + 4 + outputs[index] : 0)
                + (item.entry.publicItem?.sourceTruncated == true ? Self.gap + 18 : 0)
        }
        let historyFooter = historyCount == 0 ? 0 : Self.entryGap + Self.historyHeader
        let historySection = showsHistory && historyCount > 0 ? Self.entryGap + 18 : 0
        let cacheNotice: CGFloat = data.removedEntryCount > 0 ? Self.entryGap + 32 : 0
        let body = mode == .completion ? (result?.height ?? 32) + (data.finalResponse?.publicItem?.sourceTruncated == true ? 30 : 0)
            : cacheNotice + (entryHeights.isEmpty ? 32 : entryHeights.reduce(0, +)
            + CGFloat(entryHeights.count - 1) * Self.entryGap + historyFooter + historySection)
        height = max(IslandVibeLayout.minimumDetailHeight, Self.padding * 2 + Self.headerHeight + 12 + body)
    }

}

struct IslandTaskDetailView: View {
    let data: IslandTaskDetailData
    let metrics: IslandTaskDetailMetrics
    let english: Bool
    let onClose: () -> Void
    var onDisclosure: (UUID) -> Void = { _ in }
    var onHistory: () -> Void = {}
    private var muted: Color { Color(nsColor: IslandTextPalette.muted) }
    private var secondary: Color { Color(nsColor: IslandTextPalette.secondary) }
    private var amber: Color { Color(red: 1, green: 0.76, blue: 0.44) }
    private var failure: Color { Color(red: 0.95, green: 0.43, blue: 0.42) }
    private var accent: Color { metrics.mode == .approval ? amber : (metrics.mode == .failure ? failure : .white) }
    private func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    private var agent: String { data.provider.displayName }
    private var sourceName: (String, String) {
        data.provider == .claudeCode ? ("Claude Code 会话记录", "the Claude Code transcript") : (" Codex ", "Codex")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: metrics.mode.symbol).font(.system(size: 12))
                Text(metrics.mode.title(data: data, english: english)).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(metrics.mode == .completion ? agent : text("\(agent) 公开内容", "\(agent) public content"))
                    .font(.system(size: 10)).foregroundStyle(muted)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(secondary).frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint(text("关闭详情", "Close details"))
                    .accessibilityLabel(text("关闭详情", "Close details"))
            }.foregroundStyle(accent).frame(height: IslandTaskDetailMetrics.headerHeight)
            if metrics.mode == .completion { result } else { progress }
        }.padding(.horizontal, IslandTaskDetailMetrics.horizontalPadding)
            .padding(.vertical, IslandTaskDetailMetrics.padding)
            .frame(height: metrics.height, alignment: .top)
            .background(Color(red: 0.035, green: 0.035, blue: 0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 24.0 / 255.0), lineWidth: 1))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let layout = metrics.result {
                IslandMarkdownResultView(layout: layout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: layout.height)
                if data.finalResponse?.publicItem?.sourceTruncated == true {
                    Text(text("回答超出本地缓存，请在\(sourceName.0)查看后续内容", "Answer exceeds the local cache; continue in \(sourceName.1)"))
                        .font(.system(size: 10)).foregroundStyle(muted).frame(height: 18)
                }
            } else {
                Text(text("最终回答尚未同步，请在\(sourceName.0)查看", "Final answer has not synced; view it in \(sourceName.1)"))
                    .font(.system(size: 12)).foregroundStyle(secondary).frame(height: 32)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: IslandTaskDetailMetrics.entryGap) {
            if metrics.presentations.isEmpty {
                Text(text("暂无可公开的进展内容", "No public progress content available"))
                    .font(.system(size: 12)).foregroundStyle(secondary).frame(height: 32)
            }
            ForEach(Array(metrics.presentations.prefix(metrics.focusCount).enumerated()), id: \.element.entry.id) { index, item in
                event(item, index: index, historical: false)
            }
            if data.removedEntryCount > 0 {
                Button { if data.provider == .codex, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) } } label: {
                    Text(text("已加载部分记录，完整内容在\(sourceName.0)查看", "Partial history loaded; see full content in \(sourceName.1)"))
                        .font(.system(size: 11)).foregroundStyle(secondary).frame(height: 32)
                }.buttonStyle(.plain)
            }
            if metrics.historyCount > 0 {
                historyControl
                if metrics.showsHistory {
                    Text(text("较早记录", "Earlier activity")).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(muted).frame(height: 18)
                    ForEach(Array(metrics.presentations.dropFirst(metrics.focusCount).enumerated()), id: \.element.entry.id) { offset, item in
                        event(item, index: offset + metrics.focusCount, historical: true)
                    }
                }
            }
        }
    }
    private var historyControl: some View {
        Button(action: onHistory) {
            HStack {
                Image(systemName: "list.bullet").font(.system(size: 10))
                Text(metrics.showsHistory ? text("收起较早记录", "Hide earlier activity") : text("查看较早记录", "Earlier activity"))
                Text("\(metrics.historyCount)").monospacedDigit().foregroundStyle(muted)
                Spacer()
                Image(systemName: metrics.showsHistory ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
            }.font(.system(size: 11)).foregroundStyle(secondary)
                .padding(.horizontal, 10).frame(height: IslandTaskDetailMetrics.historyHeader)
                .background(Color(red: 0.09, green: 0.09, blue: 0.09), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    private func eventTitle(_ item: IslandTracePresentation, historical: Bool) -> String {
        guard let source = item.entry.publicItem else { return text("公开事件", "Public event") }
        switch source.category {
        case .message: return historical ? text("进度消息", "Progress message") : text("最近进展", "Latest update")
        case .command: return text("命令执行", "Command")
        case .fileChange: return text("文件修改", "File changes")
        }
    }
    private func event(_ item: IslandTracePresentation, index: Int, historical: Bool) -> some View {
        VStack(alignment: .leading, spacing: IslandTaskDetailMetrics.gap) {
            HStack(spacing: 6) {
                if item.code {
                    Image(systemName: item.entry.publicItem?.category == .fileChange ? "doc.text" : "terminal")
                        .font(.system(size: 10))
                }
                Text(eventTitle(item, historical: historical)).font(.system(size: 10, weight: .medium))
                Spacer(minLength: 8)
                if let source = item.entry.publicItem, item.code {
                    if let exit = source.exitCode {
                        Text("exit \(exit)").font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(exit == 0 ? muted : failure)
                    } else {
                        Text(source.status == "completed" ? text("已完成", "Completed")
                            : (source.status == "failed" ? text("失败", "Failed") : (source.status ?? "—")))
                            .font(.system(size: 10)).foregroundStyle(source.status == "failed" ? failure : muted)
                    }
                }
                if item.canExpand {
                    Button { onDisclosure(item.entry.id) } label: {
                        HStack(spacing: 4) {
                            Text(item.expanded ? text("收起", "Collapse") : text("查看原文", "Source"))
                            Image(systemName: item.expanded ? "chevron.up" : "chevron.down")
                        }.font(.system(size: 10)).foregroundStyle(secondary)
                            .padding(.horizontal, 6).frame(height: 22).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.foregroundStyle(muted).frame(height: IslandTaskDetailMetrics.eventHeader)
            Text(item.primary).font(.system(size: item.code ? 11 : 13, design: item.code ? .monospaced : .default))
                .lineLimit(item.compactCommand ? 2 : nil).truncationMode(.tail)
                .lineSpacing(2).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: metrics.primaryHeights[index], alignment: .topLeading)
                .textSelection(.enabled)
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
                    .font(.system(size: 10)).foregroundStyle(muted).frame(height: 18)
            }
        }.padding(.horizontal, item.code ? IslandTaskDetailMetrics.entryPadding : 0)
            .padding(.vertical, item.code ? IslandTaskDetailMetrics.entryPadding : 2)
            .frame(height: metrics.entryHeights[index], alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.code ? Color(red: 0.075, green: 0.075, blue: 0.075) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(item.code ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1))
            .accessibilityHint(item.entry.publicItem.map { "\(agent) · \($0.sourceID)" } ?? text("\(agent) 状态", "\(agent) status"))
    }

}
