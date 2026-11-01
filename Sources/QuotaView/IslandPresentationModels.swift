import AppKit
import SwiftUI
import Combine
import QuotaViewCore

// Core usage data stays visible; only the two optional charts follow panel preferences.
struct IslandUsageOptions: Equatable {
    var quota = true
    var spark = true
    var credits = true
    var dailyTokens = true
    var monthlyTokens = true
    var lifetimeTokens = true
    var cost = true
    var activity = true
    var reset = true
    var hasTokenMetrics: Bool { dailyTokens || monthlyTokens || lifetimeTokens }
    init() {}
    @MainActor init(preferences: AppPreferences) {
        cost = preferences.showEstimatedCost; activity = preferences.showTokenActivity
    }
}

// Real metadata; nil duration and absent model remain unknown.
struct IslandSessionMetadata: Equatable {
    var modelName: String
    var reasoningEffort: String
    var elapsedSeconds: Int?
    var subagents: [IslandSubagentPresentation] = []
    var modelTitle: String {
        [shortModelName, shortReasoningEffort].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var fullModelTitle: String {
        [modelName, reasoningEffort].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " · ")
    }
    private var shortModelName: String {
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match the human model name used by the native reference, retaining version and family.
        if let range = name.range(of: #"\b\d+(?:\.\d+)*[-\s]+(?:astra|sol|luna|terra)\b"#,
                                  options: [.regularExpression, .caseInsensitive]) {
            return name[range].split(whereSeparator: { $0 == "-" || $0.isWhitespace })
                .map { $0.capitalized }.joined(separator: " ")
        }
        return name
    }
    private var shortReasoningEffort: String {
        let primary = reasoningEffort.components(separatedBy: " · ").first ?? ""
        let key = primary.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "": return ""
        case "none", "无": return "None"
        case "minimal", "min", "最低": return "Min"
        case "low", "低": return "Low"
        case "medium", "med", "中": return "Medium"
        case "high", "高": return "High"
        case "xhigh", "extrahigh", "超高": return "XHigh"
        case "max", "maximum", "maximumreasoning", "最高": return "Max"
        case "ultra": return "Ultra"
        case "auto", "automatic", "自动": return "Auto"
        default: return primary
        }
    }
    var usesExtraLine: Bool {
        (modelTitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]).width > 190
    }
    // Child activity occupies one bounded third row inside the same card.
    // Admitting more children changes horizontal content, never the row height.
    var subagentGroupHeight: CGFloat { subagents.isEmpty ? 0 : IslandVibeLayout.subagentRowHeight }
    var subagentRowHeight: CGFloat { subagentGroupHeight }
    func taskGroupHeight(width: CGFloat) -> CGFloat { cardHeight(width: width) }
    func cardHeight(width: CGFloat) -> CGFloat { primaryContentHeight(width: width) + subagentRowHeight }
    func primaryContentHeight(width: CGFloat) -> CGFloat {
        guard usesExtraLine else { return IslandVibeLayout.rowHeight }
        let rect = (modelTitle as NSString).boundingRect(with: .init(width: max(80, width - IslandVibeLayout.contentInset * 2), height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)])
        return IslandVibeLayout.rowHeight + ceil(rect.height) + IslandVibeLayout.lineGap
    }
    var durationTitle: String {
        guard let elapsedSeconds else { return "—" }; let seconds = max(0, elapsedSeconds)
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}


struct IslandSubagentPresentation: Equatable, Identifiable {
    let id: String
    let title: String
    let status: String
    let visualState: CodexActivityVisualState
    let model: String
    let duration: String
    let detail: String
    var avatar: CodexActivitySubagentAvatar? = nil
    var provider: IslandAgentProvider = .codex
}

extension AppCopy {
    var islandSubagentTitle: String { text("Codex 子 Agent", "Codex agent") }
    var islandSubagentStatusUnavailable: String { text("状态待更新", "Status unavailable") }
    var islandSubagentInterrupted: String { text("已中断", "Interrupted") }
    var islandSubagentGroupName: String { text("Codex子agent", "Codex agents") }
    func islandSubagentGroupName(_ provider: IslandAgentProvider) -> String {
        provider == .codex ? islandSubagentGroupName : text("\(provider.displayName) 子 Agent", "\(provider.displayName) agents")
    }
    func islandSubagentGroupTitle(count: Int) -> String {
        "\(islandSubagentGroupName) (\(count))"
    }
    func islandMoreSubagents(count: Int) -> String {
        text("另有 \(count) 个子 Agent", "\(count) more agents")
    }
}


enum IslandTaskStatus: String, CaseIterable {
    case thinking, working, compacting, waiting, completed, failed, unknown, cancelled, queued
    var visualState: CodexActivityVisualState {
        switch self {
        case .thinking, .queued: .thinking
        case .working: .working
        case .compacting: .compactingContext
        case .waiting: .awaitingConfirmation
        case .completed: .completed
        case .failed: .error
        case .unknown: .unavailable
        case .cancelled: .standby
        }
    }
}
struct IslandDetailText: Equatable {
    var chinese: String { didSet { chineseCopy = nil } }
    var english: String { didSet { englishCopy = nil } }
    private var chineseCopy: LocalizedCopy?
    private var englishCopy: LocalizedCopy?
    init(_ value: String) { chinese = value; english = value }
    init(_ chinese: LocalizedCopy, _ english: LocalizedCopy) {
        self.chinese = chinese.render(); self.english = english.render()
        chineseCopy = chinese; englishCopy = english
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chinese == rhs.chinese && lhs.english == rhs.english
    }
    func value(_ english: Bool) -> String { english ? self.english : chinese }
    func value(_ language: AppPreferences.Language) -> String {
        guard chinese != english else { return chinese }
        return AppCopy(language: language).text(chineseCopy ?? LocalizedCopy(chinese), englishCopy ?? LocalizedCopy(english))
    }
}
struct IslandTraceEntry: Identifiable, Equatable {
    enum Kind { case progress, result, confirmation, failure }
    var id = UUID(); var text: IslandDetailText; var elapsedSeconds: Int = 0
    var kind: Kind = .progress; var publicItem: CodexPublicTraceItem?
}
struct CodexPublicTraceItem: Equatable {
    enum Category { case message, command, fileChange }
    var category: Category; var sourceID: String; var turnID: String
    var status: String?; var output: String?; var sourceTruncated = false; var exitCode: Int?
    var messagePhase: String? = nil
}
enum IslandAgentProvider: String, Equatable, Sendable {
    case codex, claudeCode, dsh, kimiCode, cursor, geminiCLI, openCode, copilotCLI
    var isObserverOnly: Bool { self != .codex && self != .claudeCode }
    var usesExternalHooks: Bool { [.cursor, .geminiCLI, .openCode, .copilotCLI].contains(self) }
    var displayName: String {
        switch self { case .codex: "Codex"; case .claudeCode: "Claude Code"; case .dsh: "DSH"; case .kimiCode: "Kimi Code"; case .cursor: "Cursor"; case .geminiCLI: "Gemini CLI"; case .openCode: "OpenCode"; case .copilotCLI: "GitHub Copilot CLI" }
    }
}
enum IslandConfirmationDecision: Equatable { case allowOnce, reject, skipQuestion, reply(IslandApprovalJSON) }
struct IslandConfirmation: Identifiable, Equatable {
    enum Phase: Equatable {
        case ready, submitting(IslandConfirmationDecision), sent, resultUnknown, resolved
        case failed(IslandConfirmationDecision, IslandDetailText)
        var canSubmit: Bool { switch self { case .ready, .failed: true; default: false } }
    }
    var id = UUID(); var question: IslandDetailText; var impact: IslandDetailText
    var resumeOperation = IslandDetailText(""); var phase: Phase = .ready
    var protocolRequest: IslandCodexApprovalRequest?
    var canRespond = false; var queueIndex = 1; var queueCount = 1
    // Local presentation handoff, never an approval or an answer.
    var canDismissLocally = false
    var provider: IslandAgentProvider = .codex
}
struct IslandTaskDetailData: Equatable {
    var entries: [IslandTraceEntry]; var confirmation: IslandConfirmation?; var status: IslandTaskStatus
    var removedEntryCount = 0
    var provider: IslandAgentProvider = .codex
    var visibleEntries: [IslandTraceEntry] { entries }
    // Older native protocols omit phase. Use their last assistant message only
    // when no explicit final exists; a known commentary/tool is never a result.
    var finalResponse: IslandTraceEntry? {
        entries.last { $0.kind == .result && $0.publicItem?.category == .message }
            ?? entries.last { $0.publicItem?.category == .message && $0.publicItem?.messagePhase == nil }
    }
    var running: Bool { [.thinking, .working, .compacting, .queued].contains(status) }
}
