import AppKit
import Combine
import Foundation
import QuotaViewCore

@MainActor
enum IslandScreenSelection {
    static func identifier(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func resolvedID(followsFocus: Bool, fixedID: String, focusedID: String?, available: [String]) -> String? {
        if followsFocus, let focusedID, available.contains(focusedID) { return focusedID }
        if !followsFocus, available.contains(fixedID) { return fixedID }
        return available.first
    }

    static func target(followsFocus: Bool, fixedID: String, previous: NSScreen?) -> NSScreen? {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return screens.first }
        var focused: NSScreen?
        if followsFocus {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                focused = previous
            } else if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
                      let entry = windows.first(where: {
                          ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
                          ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
                          (($0[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0
                      }),
                      let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: dictionary) {
                let geometries = screens.compactMap { screen -> CodexActivityScreenLocator.DisplayGeometry? in
                    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
                    return .init(id: id.uint32Value, bounds: CGDisplayBounds(id.uint32Value))
                }
                let id = CodexActivityScreenLocator.bestDisplayID(windowBounds: [bounds], displays: geometries)
                focused = screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            }
            focused = focused ?? previous ?? NSScreen.main
        }
        let id = resolvedID(followsFocus: followsFocus, fixedID: fixedID,
                            focusedID: focused.map(identifier), available: screens.map(identifier))
        return screens.first { identifier($0) == id } ?? screens.first
    }
}

@MainActor
final class IslandSession {
    var onWake: (() -> Void)?
    let model = IslandLiveStore(archiveDefaults: .standard)
    let board = IslandBoardController()
    private var clock: Timer?
    private var contentRefresh: DispatchWorkItem?
    private var stateRefresh: DispatchWorkItem?
    private var followsFocus = false
    private var fixedScreenID = ""
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
    private var expandedWidth = AppPreferences.IslandExpandedWidth.defaultValue
    private var islandUsageCapsuleTone: AppPreferences.UsageCapsuleTone = .dark
    private var islandFloatingUsageEnabled = true
    private var islandGlassDegree = AppPreferences.IslandGlassDegree.defaultValue
    private var islandMaterial: AppPreferences.IslandMaterial = .liquidGlass
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
    func update(english: Bool, remaining: Int?, enabled: Bool, privacy: Bool, weeklyRemaining: Int? = nil, quotaResetsAt: Date? = nil, usageSnapshot: CurrentCodexPresentation? = nil, usageState: IslandUsagePresentation.State = .loading, usageOptions: IslandUsageOptions = .init(), progressEffect: AppPreferences.CodexActivityProgressEffect = .dropField, automaticPopupEnabled: Bool = true, automaticPopupDuration: Int = AppPreferences.CodexActivityAutomaticPopupTiming.defaultDuration, expandedWidth: Double = AppPreferences.IslandExpandedWidth.defaultValue, islandMaterial: AppPreferences.IslandMaterial = .liquidGlass, islandGlassDegree: Double = AppPreferences.IslandGlassDegree.defaultValue, islandFloatingUsageEnabled: Bool = true, islandUsageCapsuleTone: AppPreferences.UsageCapsuleTone = .dark, backgroundMemorySnapshots: [CodexActivitySnapshot] = [], followsFocus: Bool = false, fixedScreenID: String = "") {
        self.followsFocus = followsFocus
        self.fixedScreenID = fixedScreenID
        self.backgroundMemorySnapshots = backgroundMemorySnapshots
        self.usageOptions = usageOptions
        self.automaticPopupEnabled = automaticPopupEnabled
        self.automaticPopupDuration = AppPreferences.CodexActivityAutomaticPopupTiming.normalizedDuration(automaticPopupDuration)
        self.expandedWidth = AppPreferences.IslandExpandedWidth.normalized(expandedWidth)
        self.islandUsageCapsuleTone = islandUsageCapsuleTone
        self.islandFloatingUsageEnabled = islandFloatingUsageEnabled
        self.islandGlassDegree = islandGlassDegree
        self.islandMaterial = islandMaterial
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
        board.screen = IslandScreenSelection.target(followsFocus: followsFocus, fixedID: fixedScreenID, previous: board.screen)
        var display = model.display(english: english, remaining: remaining, enabled: enabled && !locked, privacy: privacy)
        display.weeklyRemainingPercent = weeklyRemaining
        display.quotaResetsAt = quotaResetsAt
        display.usageSnapshot = privacy ? nil : usageSnapshot
        display.claudeUsage = privacy ? nil : claudeUsage
        display.usageState = usageState
        display.usageOptions = usageOptions
        display.automaticPopupEnabled = automaticPopupEnabled
        display.automaticPopupDuration = automaticPopupDuration
        display.expandedWidth = expandedWidth
        display.islandUsageCapsuleTone = islandUsageCapsuleTone
        display.islandFloatingUsageEnabled = islandFloatingUsageEnabled
        display.islandGlassDegree = islandGlassDegree
        display.islandMaterial = islandMaterial
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
