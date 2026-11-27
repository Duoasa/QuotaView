import Foundation
import QuotaViewCore

/// Presentation state for admitted user tasks. Execution state remains owned by the store.
struct CodexActivityMultitaskState {
    struct Entry {
        let id: Int
        var snapshot: CodexActivitySnapshot
        var lifecycle: CodexActivityTurnLifecycle
        var compactionSource: CodexActivityEventSource?
    }
    private(set) var enabled = false
    private(set) var entries: [Entry] = []
    private(set) var selectedID: Int?
    private(set) var presentation: CodexActivityPresentation = .hidden
    private(set) var completionStartedAt: TimeInterval?
    private(set) var nextDeadline: TimeInterval?
    private var nextID = 1
    var compactDelay: TimeInterval = 20
    var hiddenDelay: TimeInterval = 100
    var selected: Entry? { entries.first { $0.id == selectedID } }
    var allCompleted: Bool { !entries.isEmpty && entries.allSatisfy { $0.lifecycle == .completed && $0.snapshot.state == .completed } }

    mutating func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        entries = []; selectedID = nil; nextID = 1
        presentation = .hidden; completionStartedAt = nil; nextDeadline = nil
    }

    mutating func receive(_ snapshot: CodexActivitySnapshot, lifecycle: CodexActivityTurnLifecycle,
                          compactionSource: CodexActivityEventSource?, now: TimeInterval,
                          permitsNewEntry: Bool) {
        guard enabled else { return }
        if lifecycle == .active, permitsNewEntry, allCompleted, presentation != .expanded {
            entries = []; selectedID = nil
            completionStartedAt = nil; nextDeadline = nil
        }
        if let index = entries.firstIndex(where: { $0.snapshot.sessionHash == snapshot.sessionHash }) {
            let previous = entries[index]
            entries[index].snapshot = snapshot; entries[index].lifecycle = lifecycle
            entries[index].compactionSource = compactionSource
            if previous.snapshot.taskIdentity != snapshot.taskIdentity || previous.lifecycle != lifecycle {
                reconcile(now: now)
            }
            return
        }
        // A terminal/history-only record cannot establish an active task group.
        guard permitsNewEntry, lifecycle == .active else { return }
        let entry = Entry(id: nextID, snapshot: snapshot, lifecycle: lifecycle, compactionSource: compactionSource)
        nextID += 1
        let insertion = selectedID.flatMap { selected in entries.firstIndex { $0.id == selected } }.map { $0 + 1 } ?? entries.endIndex
        entries.insert(entry, at: insertion)
        if selectedID == nil { selectedID = entry.id }
        reconcile(now: now)
    }

    mutating func select(_ id: Int) {
        guard enabled, entries.contains(where: { $0.id == id }), selectedID != id else { return }
        selectedID = id
    }

    mutating func remove(_ session: String, now: TimeInterval) {
        guard entries.contains(where: { $0.snapshot.sessionHash == session }) else { return }
        entries.removeAll { $0.snapshot.sessionHash == session }
        if !entries.contains(where: { $0.id == selectedID }) { selectedID = entries.first?.id }
        reconcile(now: now)
    }

    mutating func advance(now: TimeInterval) {
        guard enabled, allCompleted, let deadline = nextDeadline, now >= deadline else { return }
        if presentation == .expanded {
            presentation = .compact; nextDeadline = now + hiddenDelay
        } else {
            presentation = .hidden; nextDeadline = nil
        }
    }

    mutating func updateDelays(compact: TimeInterval, hidden: TimeInterval, now: TimeInterval) {
        guard compactDelay != compact || hiddenDelay != hidden else { return }
        compactDelay = compact; hiddenDelay = hidden
        if allCompleted, presentation == .expanded, let start = completionStartedAt {
            nextDeadline = start + max(compactDelay, entries.count > 1 ? CodexMultitaskCompletionTiming.duration(taskCount: entries.count) : 0)
        } else if allCompleted, presentation == .compact { nextDeadline = now + hiddenDelay }
    }

    private mutating func reconcile(now: TimeInterval) {
        if entries.isEmpty {
            presentation = .hidden; nextDeadline = nil; completionStartedAt = nil
        } else if !allCompleted {
            presentation = .expanded; nextDeadline = nil; completionStartedAt = nil
        } else if completionStartedAt == nil {
            completionStartedAt = now; presentation = .expanded
            nextDeadline = now + max(compactDelay, entries.count > 1 ? CodexMultitaskCompletionTiming.duration(taskCount: entries.count) : 0)
        }
    }
}

enum CodexMultitaskCompletionTiming {
    static let lead: TimeInterval = 0.20
    static let merge: TimeInterval = 0.46
    static let settle: TimeInterval = 0.55
    static func duration(taskCount: Int) -> TimeInterval { taskCount > 1 ? lead + merge + settle : 0 }
}
