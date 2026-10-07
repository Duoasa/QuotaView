import AppKit
import Combine
import Foundation
import QuotaViewCore

@MainActor
final class IslandSession {
    var onWake: (() -> Void)?
    let model = IslandLiveStore(archiveDefaults: .standard)
    let board = IslandBoardController()
    private var clock: Timer?
    private var contentRefresh: DispatchWorkItem?
    private var stateRefresh: DispatchWorkItem?
    private var enabled = false
    private var english = false
    private var remaining: Int?
    private var weeklyRemaining: Int?
    private var quotaResetsAt: Date?
    private var usageSnapshot: CurrentCodexPresentation?
    private var usageState: IslandUsagePresentation.State = .loading
    private var usageOptions = IslandUsageOptions()
    private var automaticPopupEnabled = true
    private var automaticPopupDuration = AppPreferences.CodexActivityAutomaticPopupTiming.defaultDuration
    private var progressEffect: AppPreferences.CodexActivityProgressEffect = .dropField
    private var locked = false
    private var observations: [NSObjectProtocol] = []
    private var lockObservations: [NSObjectProtocol] = []
    private var privacy = false
    private var backgroundMemorySnapshots: [CodexActivitySnapshot] = []
    var claudeUsage: IslandClaudeUsage? {
        didSet {
            guard claudeUsage != oldValue, stateRefresh == nil else { return }
            let work = DispatchWorkItem { [weak self] in self?.stateRefresh = nil; self?.refresh() }
            stateRefresh = work
            DispatchQueue.main.async(execute: work)
        }
    }
    init() {
        board.onSelect = { [weak self] in self?.model.select($0) }
        board.state.onArchive = { [weak self] in self?.model.archiveFromIsland($0) }
        board.onConfirmation = { [weak self] id, rid, decision in self?.model.submit(id, requestID: rid, decision: decision) }
        board.onClaimConfirmation = { [weak self] id, rid in self?.model.claimConfirmation(taskID: id, requestID: rid) }
        board.onDismissConfirmation = { [weak self] id, rid in self?.model.dismissConfirmation(taskID: id, requestID: rid) }
        board.state.onNextRequest = { [weak self] in self?.model.nextRequest($0) }
        model.onChange = { [weak self] in self?.refresh() }
        model.onPublicChange = { [weak self] in
            guard let self, enabled, !locked, contentRefresh == nil else { return }
            let work = DispatchWorkItem { [weak self] in self?.contentRefresh = nil; self?.refresh() }
            contentRefresh = work; DispatchQueue.main.asyncAfter(deadline: .now() + (board.state.compact ? 0.5 : 0.1), execute: work)
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservations.append(distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(value) }
            })
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(true) }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(false) }
            })
        }
    }
    func update(english: Bool, remaining: Int?, enabled: Bool, privacy: Bool, weeklyRemaining: Int? = nil, quotaResetsAt: Date? = nil, usageSnapshot: CurrentCodexPresentation? = nil, usageState: IslandUsagePresentation.State = .loading, usageOptions: IslandUsageOptions = .init(), progressEffect: AppPreferences.CodexActivityProgressEffect = .dropField, automaticPopupEnabled: Bool = true, automaticPopupDuration: Int = AppPreferences.CodexActivityAutomaticPopupTiming.defaultDuration, backgroundMemorySnapshots: [CodexActivitySnapshot] = []) {
        self.backgroundMemorySnapshots = backgroundMemorySnapshots
        self.usageOptions = usageOptions
        self.automaticPopupEnabled = automaticPopupEnabled
        self.automaticPopupDuration = AppPreferences.CodexActivityAutomaticPopupTiming.normalizedDuration(automaticPopupDuration)
        self.progressEffect = progressEffect
        self.usageSnapshot = usageSnapshot
        self.usageState = usageState
        self.quotaResetsAt = quotaResetsAt
        self.weeklyRemaining = weeklyRemaining
        if self.privacy != privacy { self.privacy = privacy; board.state.clearDrafts() }
        self.english = english; self.remaining = remaining; self.enabled = enabled
        updateClock()
        // A source batch can update connection, titles, usage and activity in
        // one main-loop turn. Publish its latest display once. Direct selection
        // and approval callbacks still use the synchronous model.onChange path.
        guard stateRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.stateRefresh = nil; self?.refresh() }
        stateRefresh = work
        DispatchQueue.main.async(execute: work)
    }
    private func updateClock() {
        if enabled && !locked && clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }; clock?.tolerance = 0.2
        } else if !enabled || locked { clock?.invalidate(); clock = nil }
    }
    private func setLocked(_ value: Bool) {
        locked = value; board.state.clearDrafts(); contentRefresh?.cancel(); contentRefresh = nil
        if !value { model.setConnection(.discovering); onWake?() }
        updateClock(); refresh()
    }
    private func refresh() {
        stateRefresh?.cancel(); stateRefresh = nil
        contentRefresh?.cancel(); contentRefresh = nil
        if (!enabled || locked) && !board.isVisible { return }
        model.preservedID = board.state.detailID
        board.screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        var display = model.display(english: english, remaining: remaining, enabled: enabled && !locked, privacy: privacy)
        display.weeklyRemainingPercent = weeklyRemaining
        display.quotaResetsAt = quotaResetsAt
        display.usageSnapshot = privacy ? nil : usageSnapshot
        display.claudeUsage = privacy ? nil : claudeUsage
        display.usageState = usageState
        display.usageOptions = usageOptions
        display.automaticPopupEnabled = automaticPopupEnabled
        display.automaticPopupDuration = automaticPopupDuration
        display.effect = progressEffect
        display.backgroundMemorySnapshots = backgroundMemorySnapshots
        board.update(model: display,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func stop() {
        stateRefresh?.cancel(); stateRefresh = nil
        clock?.invalidate(); clock = nil; contentRefresh?.cancel(); contentRefresh = nil
        observations.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observations.removeAll()
        lockObservations.forEach { DistributedNotificationCenter.default().removeObserver($0) }; lockObservations.removeAll()
        board.state.clearDrafts(); board.stop()
    }
}
