import Combine
import Foundation
import QuotaViewCore

@MainActor
final class CodexActivityStore: ObservableObject {
    nonisolated static let compactDelay: TimeInterval = 20
    nonisolated static let hiddenDelayAfterCompact: TimeInterval = 100
    nonisolated static let missingStopHideDelay: TimeInterval = 120

    @Published private(set) var snapshot: CodexActivitySnapshot?
    @Published private(set) var presentation:
        CodexActivityPresentation = .hidden
    @Published private(set) var resolvedThreadTitle: String?

    var stateDidChange: (() -> Void)?

    private let compactDelayNanoseconds: UInt64
    private let hiddenDelayNanoseconds: UInt64
    private let missingStopHideDelayNanoseconds: UInt64
    private var inactivityTask: Task<Void, Never>?
    private var latestEventAtBySession: [String: Date] = [:]
    private var revision: UInt64 = 0

    init(
        compactDelay: TimeInterval = CodexActivityStore.compactDelay,
        hiddenDelayAfterCompact: TimeInterval =
            CodexActivityStore.hiddenDelayAfterCompact,
        missingStopHideDelay: TimeInterval =
            CodexActivityStore.missingStopHideDelay
    ) {
        compactDelayNanoseconds = UInt64(
            max(compactDelay, 0) * 1_000_000_000
        )
        hiddenDelayNanoseconds = UInt64(
            max(hiddenDelayAfterCompact, 0) * 1_000_000_000
        )
        missingStopHideDelayNanoseconds = UInt64(
            max(missingStopHideDelay, 0) * 1_000_000_000
        )
    }

    func receive(_ event: CodexActivityEvent) {
        guard let nextSnapshot = CodexActivityReducer.snapshot(for: event)
        else {
            return
        }

        if let latestEventAt = latestEventAtBySession[event.sessionHash],
           event.occurredAt < latestEventAt
        {
            return
        }
        latestEventAtBySession[event.sessionHash] = event.occurredAt
        if let snapshot,
           event.sessionHash != snapshot.sessionHash,
           event.occurredAt < snapshot.occurredAt
        {
            return
        }

        revision &+= 1
        let eventRevision = revision
        inactivityTask?.cancel()

        if CodexActivityReducer.shouldHideImmediately(after: event) {
            if snapshot?.sessionHash == event.sessionHash {
                snapshot = nextSnapshot
                presentation = .hidden
                resolvedThreadTitle = nil
                notifyChange()
            }
            return
        }

        snapshot = nextSnapshot
        // The App Store plugin contract intentionally excludes task titles
        // because they may reveal prompt content. The island uses the
        // sanitized workspace name and operation state instead.
        resolvedThreadTitle = nil
        presentation = .expanded
        notifyChange()

        if CodexActivityReducer.shouldStartInactivityCycle(after: event) {
            scheduleInactivityCycle(revision: eventRevision)
        } else if shouldHideIfStopIsMissing(after: event) {
            scheduleMissingStopFallback(revision: eventRevision)
        }
    }

    func hide() {
        revision &+= 1
        inactivityTask?.cancel()
        presentation = .hidden
        notifyChange()
    }

    func stop() async {
        hide()
    }

    private func scheduleInactivityCycle(revision: UInt64) {
        inactivityTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: compactDelayNanoseconds
                )
                guard !Task.isCancelled, self.revision == revision else {
                    return
                }
                presentation = .compact
                notifyChange()

                try await Task.sleep(
                    nanoseconds: hiddenDelayNanoseconds
                )
                guard !Task.isCancelled, self.revision == revision else {
                    return
                }
                presentation = .hidden
                notifyChange()
            } catch {
                return
            }
        }
    }

    private func scheduleMissingStopFallback(revision: UInt64) {
        inactivityTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: missingStopHideDelayNanoseconds
                )
                guard !Task.isCancelled, self.revision == revision else {
                    return
                }
                // A missing Stop must not leave a transitional state visible
                // forever. Hide it without synthesizing a completed event;
                // any genuine new activity expands the island again.
                presentation = .hidden
                resolvedThreadTitle = nil
                notifyChange()
            } catch {
                return
            }
        }
    }

    private func shouldHideIfStopIsMissing(
        after event: CodexActivityEvent
    ) -> Bool {
        switch event.event {
        case .postToolUse, .postCompact, .subagentStop:
            true
        default:
            false
        }
    }

    private func notifyChange() {
        stateDidChange?()
    }
}
