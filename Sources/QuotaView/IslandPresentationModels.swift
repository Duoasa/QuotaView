import AppKit
import SwiftUI
import Combine
import QuotaViewCore

// Real metadata; nil duration and absent model remain unknown.
struct IslandSessionMetadata: Equatable {
    var modelName: String
    var reasoningEffort: String
    var elapsedSeconds: Int?
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
    func cardHeight(width: CGFloat) -> CGFloat {
        guard usesExtraLine else { return IslandVibeLayout.rowHeight }
        let rect = (modelTitle as NSString).boundingRect(with: .init(width: max(80, width - 20), height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)])
        return IslandVibeLayout.rowHeight + ceil(rect.height) + 6
    }
    var durationTitle: String {
        guard let elapsedSeconds else { return "—" }; let seconds = max(0, elapsedSeconds)
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
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
    var chinese: String; var english: String
    init(_ chinese: String, _ english: String? = nil) { self.chinese = chinese; self.english = english ?? chinese }
    func value(_ english: Bool) -> String { english ? self.english : chinese }
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
}
enum IslandConfirmationDecision: Equatable { case allowOnce, reject, reply(IslandApprovalJSON) }
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
}
struct IslandTaskDetailData: Equatable {
    var entries: [IslandTraceEntry]; var confirmation: IslandConfirmation?; var status: IslandTaskStatus
    var removedEntryCount = 0
    var visibleEntries: [IslandTraceEntry] { entries }
    var running: Bool { [.thinking, .working, .compacting, .queued].contains(status) }
}
