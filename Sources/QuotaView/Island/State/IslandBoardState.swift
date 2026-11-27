import AppKit
import Combine
import Observation
import SwiftUI
import QuotaViewCore

/// The floating capsule alone reads the minute used for its quota countdown.
@MainActor
@Observable
final class IslandFloatingUsageClock {
    private(set) var now = Date()

    func advance(to date: Date) {
        if Int(date.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) {
            now = date
        }
    }
}

// Native presentation: an independent presentation of the console's fixture adapter.
// Selection means inspecting a task, never inferred Codex window focus.
@MainActor
final class IslandBoardState: ObservableObject {
    @Published private(set) var display: CodexMultitaskDisplay?
    @Published private(set) var detailID: Int?
    @Published var availableConversation: (source: IslandConversationTarget, target: IslandConversationTarget)?
    var selectedConversation: IslandConversationTarget? {
        guard !compact, !showsUsage, let detail else { return nil }
        return display?.taskDetails[detail.id]?.nativeConversation
    }
    let taskScrollLink = IslandTaskScrollLink()
    @Published private(set) var expandedTraceEntries: Set<UUID> = []
    private struct DetailMetricsKey: Equatable {
        let data: IslandTaskDetailData
        let english: Bool
        let language: AppPreferences.Language
        let expanded: Set<UUID>
    }
    // At most the normal and rail-adjusted widths; clocks and scrolling reuse
    // identical content metrics instead of repeatedly measuring source output.
    private var detailMetricsCache: [CGFloat: (DetailMetricsKey, IslandTaskDetailMetrics)] = [:]
    private struct ApprovalMetricsKey: Equatable {
        let request: IslandConfirmation
        let english: Bool
        let language: AppPreferences.Language
        let maximumViewportHeight: CGFloat
        let cardHeight: CGFloat
        let conversationURL: URL?
    }
    private var approvalMetricsCache: [CGFloat: (ApprovalMetricsKey, IslandApprovalMetrics)] = [:]
    @Published private var approvalDrafts: [UUID: IslandApprovalDraft] = [:]
    func approvalDraftBinding(for id: UUID) -> Binding<IslandApprovalDraft> {
        .init(get: { self.approvalDrafts[id] ?? .init() }, set: { value in
            guard value != (self.approvalDrafts[id] ?? .init()) else { return }
            self.approvalDrafts[id] = value
            if let task = self.tasks.first(where: { self.detailData(for: $0).confirmation?.id == id }) {
                self.onClaimConfirmation?(task.id, id)
            }
        })
    }
    @Published private(set) var attentionOnly = false
    enum Presentation: Equatable { case resting, preview, pinned }
    @Published private(set) var presentation: Presentation = .resting {
        didSet { if presentation != oldValue { reconcileCompactSignals() } }
    }
    @Published private(set) var geometry = IslandNotchGeometry(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
    var reviewingCompletion: Bool { presentation != .resting && display?.state.allCompleted == true }
    @Published private(set) var reduceMotion = false
    var onChange: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    var onArchive: ((Int) -> Void)?
    var onNextRequest: ((Int) -> Void)?
    var onRefreshUsage: (() async -> Void)?
    private var resetPhaseObservation: AnyCancellable?
    @Published private(set) var resetConfirming = false
    var resetController: CodexResetController? {
        didSet {
            guard resetController !== oldValue else { return }
            resetPhaseObservation = resetController?.$phase
                .map { phase in switch phase { case .confirming: return true; default: return false } }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] confirming in
                    guard let self else { return }
                    self.resetConfirming = confirming
                    self.onChange?()
                }
            if resetController == nil { resetConfirming = false; onChange?() }
        }
    }
    var resetTicketIsEmpty: Bool {
        guard display?.privacyMode != true else { return false }
        let snapshot = effectiveUsageProvider == .claudeCode ? display?.claudeUsage?.presentation : display?.usageSnapshot
        return IslandResetPageData(snapshot: snapshot).creditAvailability == .empty
    }
    var showsResetConfirmationGlow: Bool {
        resetConfirming && showsUsage && showsReset && !compact
            && effectiveUsageProvider == .codex && display?.visible == true
    }
    var onOpenSettings: (() -> Void)?
    @Published private(set) var isRefreshingUsage = false
    func refreshUsage() async {
        guard !isRefreshingUsage, let onRefreshUsage else { return }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }
        await onRefreshUsage()
    }
    @Published private(set) var showsUsage = false
    @Published private(set) var usageHeight: CGFloat = 500
    @Published private(set) var showsReset = false
    /// Usage page source; Claude Code applies only while its usage exists.
    @Published var usageProvider: IslandAgentProvider = .codex
    var effectiveUsageProvider: IslandAgentProvider {
        if display?.agentQuotas[usageProvider] != nil { return usageProvider }
        if usageProvider == .antigravity, display?.antigravityUsage != nil { return .antigravity }
        return usageProvider == .claudeCode && display?.claudeUsage != nil ? .claudeCode : .codex
    }
    @Published private(set) var resetHeight: CGFloat = 434
    @Published private(set) var resetTransitionInFlight = false
    @Published private(set) var resetTransitionSerial: UInt64 = 0
    private var resetTransitionStartTimeout: DispatchWorkItem?
    var resetWidth: CGFloat { min(max(378, geometry.cameraWidth + 200), maximumExpandedWidth) }
    let floatingUsageClock = IslandFloatingUsageClock()
    var showsFloatingUsage: Bool {
        display?.islandFloatingUsageEnabled == true && display?.privacyMode != true
    }
    var availableIslandHeight: CGFloat { max(0, geometry.maximumExpandedHeight - (showsFloatingUsage ? 44 : 0)) }
    var maximumPageHeight: CGFloat { max(IslandChromeMetrics.footerHeight + 10, availableIslandHeight - headerHeight) }
    var expandedCanvasHeight: CGFloat {
        showsUsage ? headerHeight + min(max(usageHeight, resetHeight), maximumPageHeight) : expandedHeight
    }
    func updateResetHeight(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let height = ceil(value)
        guard abs(resetHeight - height) > 0.5 else { return }
        resetHeight = height
        if showsReset { onChange?() }
    }
    func openReset() {
        guard showsUsage, !showsReset, [.codex, .claudeCode].contains(effectiveUsageProvider) else { return }
        cancelAutomaticPreview(); showsReset = true; beginResetTransition()
    }
    func closeReset() {
        guard showsReset else { return }
        showsReset = false; beginResetTransition()
    }
    private func beginResetTransition() {
        resetTransitionStartTimeout?.cancel(); resetTransitionStartTimeout = nil
        resetTransitionSerial &+= 1
        resetTransitionInFlight = !reduceMotion && display?.playbackEnabled != false
        if resetTransitionInFlight {
            let serial = resetTransitionSerial
            // Only recover if no flight can start (for example a missing slot).
            // Once Core Animation starts, its completion owns the handoff.
            let timeout = DispatchWorkItem { [weak self] in self?.finishResetTransition(serial: serial) }
            resetTransitionStartTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
        }
        onChange?()
    }
    func didStartResetTransition(serial: UInt64) {
        guard serial == resetTransitionSerial, resetTransitionInFlight else { return }
        resetTransitionStartTimeout?.cancel(); resetTransitionStartTimeout = nil
    }
    func finishResetTransition(serial: UInt64) {
        guard serial == resetTransitionSerial, resetTransitionInFlight else { return }
        resetTransitionStartTimeout?.cancel(); resetTransitionStartTimeout = nil
        resetTransitionInFlight = false
    }
    private func clearResetPresentation() {
        resetTransitionStartTimeout?.cancel(); resetTransitionStartTimeout = nil
        resetTransitionSerial &+= 1; resetTransitionInFlight = false; showsReset = false
    }
    func updateUsageHeight(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let height = ceil(value)
        guard abs(usageHeight - height) > 0.5 else { return }
        usageHeight = height
        if showsUsage { onChange?() }
    }
    func openUsage() {
        claimManualPresentation(); showsUsage = true
        if compact { presentation = .preview }
        onChange?()
    }
    func closeUsage() { clearResetPresentation(); showsUsage = false; onChange?() }
    func clearDrafts() { approvalDrafts.removeAll() }
    var onConfirmation: ((Int, UUID, IslandConfirmationDecision) -> Void)?
    var onClaimConfirmation: ((Int, UUID) -> Void)?
    var onDismissConfirmation: ((Int, UUID) -> Void)?
    var english: Bool { display?.english ?? false }
    var language: AppPreferences.Language { display?.language ?? (english ? .english : .simplifiedChinese) }
    var tasks: [CodexMultitaskRenderTask] { display?.state.tasks ?? [] }
    var memoryActivity: IslandMemoryActivity? { IslandMemoryActivity(snapshots: display?.backgroundMemorySnapshots ?? []) }
    static func needsAttention(_ task: CodexMultitaskRenderTask) -> Bool { task.hasPendingRequest || task.renderState.visualState == .awaitingConfirmation }
    static func isRunning(_ task: CodexMultitaskRenderTask) -> Bool {
        [.working, .thinking, .compactingContext].contains(task.renderState.visualState)
    }
    static func playsOrb(_ task: CodexMultitaskRenderTask) -> Bool {
        task.playbackEnabled && (isRunning(task) || task.renderState.visualState == .completed)
    }
    var attentionCount: Int { tasks.filter(Self.needsAttention).count }
    var runningCount: Int { tasks.filter(Self.isRunning).count }
    var completedCount: Int { tasks.filter { $0.renderState.visualState == .completed }.count }
    var statusCounts: [(state: CodexActivityVisualState, title: String, count: Int)] {
        CodexActivityVisualState.allCases.compactMap { visualState in
            let matching = tasks.filter { $0.renderState.visualState == visualState }
            guard let first = matching.first else { return nil }
            return (visualState, first.renderState.statusTitle, matching.count)
        }
    }
    var visibleTasks: [CodexMultitaskRenderTask] { attentionOnly ? tasks.filter(Self.needsAttention) : tasks }
    var detail: CodexMultitaskRenderTask? { guard let detailID else { return nil }; return visibleTasks.first { $0.id == detailID } }
    var approval: (task: CodexMultitaskRenderTask, request: IslandConfirmation)? {
        guard !showsUsage, let detail, let request = detailData(for: detail).confirmation else { return nil }
        return (detail, request)
    }
    var inlineDetail: CodexMultitaskRenderTask? { approval == nil ? detail : nil }
    var compact: Bool { presentation == .resting }
    var playback: Bool { display?.visible == true && display?.playbackEnabled == true && !reduceMotion }
    // The list has a bounded viewport; 128 tasks do not create a 128-row window.
    var maximumExpandedWidth: CGFloat { geometry.maximumExpandedWidth }
    var compactWidth: CGFloat { min(geometry.compactWidth, maximumExpandedWidth) }
    var expandedWidth: CGFloat {
        // Approval has its own layout contract; only the task list and usage respond.
        if approval != nil { return maximumExpandedWidth }
        return geometry.expandedWidth(preferred: display?.expandedWidth ?? AppPreferences.IslandExpandedWidth.defaultValue)
    }
    var headerHeight: CGFloat { max(IslandVibeLayout.headerHeight, geometry.bandHeight) }
    var maximumApprovalViewportHeight: CGFloat {
        max(0, availableIslandHeight - headerHeight - IslandApprovalMetrics.fixedHeight)
    }
    var compactSideWidth: CGFloat { max(0, (compactWidth - 40 - geometry.cameraWidth - 16) / 2) }
    var headerSideWidth: CGFloat { max(0, (surfaceWidth - IslandChromeMetrics.horizontalInset * 2 - geometry.cameraWidth - 16) / 2) }
    private struct CardGeometryKey: Hashable { let model: String; let effort: String; let width: CGFloat }
    private var cardGeometryCache: [CardGeometryKey: CGFloat] = [:]
    private func measuredCardHeight(_ metadata: IslandSessionMetadata?, width: CGFloat) -> CGFloat {
        guard let metadata else { return IslandVibeLayout.rowHeight }
        let key = CardGeometryKey(model: metadata.modelName, effort: metadata.reasoningEffort, width: width)
        if let height = cardGeometryCache[key] { return height + metadata.subagentRowHeight }
        if cardGeometryCache.count >= 256 { cardGeometryCache.removeAll() }
        // Cache static text geometry only. Live child membership changes the
        // group height without changing model/effort, even on the same card.
        let height = metadata.primaryContentHeight(width: width)
        cardGeometryCache[key] = height
        return height + metadata.subagentRowHeight
    }
    var rowWidth: CGFloat { expandedWidth - IslandVibeLayout.listInset - (showsScrollRail ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset) }
    func rowHeight(_ task: CodexMultitaskRenderTask) -> CGFloat { measuredCardHeight(display?.sessionMetadata[task.id], width: rowWidth) }
    var rowHeights: [Int: CGFloat] { Dictionary(uniqueKeysWithValues: visibleTasks.map { ($0.id, rowHeight($0)) }) }
    var listHeight: CGFloat {
        let rows = visibleTasks.isEmpty ? IslandVibeLayout.rowPitch : visibleTasks.prefix(4).reduce(0) { $0 + rowHeight($1) + IslandVibeLayout.rowSpacing }
        let detail = inlineDetail == nil ? 0 : detailHeight + IslandVibeLayout.rowSpacing
        return min(rows + detail + IslandVibeLayout.listVerticalInset * 2 - IslandVibeLayout.rowSpacing, max(60, availableIslandHeight - headerHeight - IslandVibeLayout.footerHeight))
    }
    func detailData(for task: CodexMultitaskRenderTask) -> IslandTaskDetailData {
        var data = display?.taskDetails[task.id] ?? .init(entries: [], confirmation: nil, status: .unknown)
        data.nativeConversation = data.nativeConversation == availableConversation?.source ? availableConversation?.target : nil
        return data
    }
    private var unrailedDetailHeight: CGFloat {
        guard let detail = inlineDetail else { return 0 }
        return measuredDetail(for: detail, width: expandedWidth - IslandVibeLayout.listInset * 2).height
    }
    var showsScrollRail: Bool {
        guard approval == nil else { return false }
        if visibleTasks.count > 4 { return true }
        let width = expandedWidth - IslandVibeLayout.listInset * 2
        let rows = visibleTasks.reduce(CGFloat(0)) { $0 + measuredCardHeight(display?.sessionMetadata[$1.id], width: width) + IslandVibeLayout.rowSpacing }
        let detail = inlineDetail == nil ? 0 : unrailedDetailHeight + IslandVibeLayout.rowSpacing
        return rows + detail + IslandVibeLayout.listVerticalInset * 2 - IslandVibeLayout.rowSpacing > availableIslandHeight - headerHeight - IslandVibeLayout.footerHeight
    }
    func approvalMetrics(request: IslandConfirmation) -> IslandApprovalMetrics {
        let width = expandedWidth - IslandVibeLayout.listInset * 2
        let metrics = measuredApproval(request: request, width: width)
        return metrics.showsRail ? measuredApproval(request: request,
            width: expandedWidth - IslandVibeLayout.listInset - IslandVibeLayout.scrollingListTrailingInset) : metrics
    }
    private func measuredApproval(request: IslandConfirmation, width: CGFloat) -> IslandApprovalMetrics {
        let key = ApprovalMetricsKey(request: request, english: english, language: language, maximumViewportHeight: maximumApprovalViewportHeight, cardHeight: approval.flatMap { display?.sessionMetadata[$0.task.id] }?.taskGroupHeight(width: width) ?? IslandVibeLayout.rowHeight,
            conversationURL: approval.flatMap { detailData(for: $0.task).conversationURL })
        if let cached = approvalMetricsCache[width], cached.0 == key { return cached.1 }
        let result = IslandApprovalMetrics(request: request, width: width, english: english,
            maximumViewportHeight: key.maximumViewportHeight, cardHeight: key.cardHeight, language: language, conversationURL: key.conversationURL)
        if approvalMetricsCache[width] == nil && approvalMetricsCache.count >= 2 { approvalMetricsCache.removeAll() }
        approvalMetricsCache[width] = (key, result)
        return result
    }
    func detailMetrics(for task: CodexMultitaskRenderTask) -> IslandTaskDetailMetrics {
        measuredDetail(for: task, width: expandedWidth - IslandVibeLayout.listInset
            - (showsScrollRail ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset))
    }
    private func measuredDetail(for task: CodexMultitaskRenderTask, width: CGFloat) -> IslandTaskDetailMetrics {
        let key = DetailMetricsKey(data: detailData(for: task), english: english, language: language, expanded: expandedTraceEntries)
        if let cached = detailMetricsCache[width], cached.0 == key { return cached.1 }
        let result = IslandTaskDetailMetrics(data: key.data, width: width, english: english, expandedEntries: key.expanded, language: language)
        if detailMetricsCache[width] == nil && detailMetricsCache.count >= 2 { detailMetricsCache.removeAll() }
        detailMetricsCache[width] = (key, result)
        return result
    }
    var detailHeight: CGFloat { inlineDetail.map { detailMetrics(for: $0).height } ?? 0 }
    var expandedHeight: CGFloat {
        if showsUsage { return headerHeight + min(showsReset ? resetHeight : usageHeight, maximumPageHeight) }
        if let approval { return headerHeight + approvalMetrics(request: approval.request).height }
        return headerHeight + listHeight + IslandVibeLayout.footerHeight
    }
    var surfaceWidth: CGFloat { compact ? compactWidth : (showsReset ? resetWidth : expandedWidth) }
    var height: CGFloat { compact ? geometry.bandHeight : expandedHeight }
    var focusedTask: CodexMultitaskRenderTask? {
        let selected = tasks.first { $0.id == display?.state.selectedID } ?? tasks.first
        // Compact focus follows activity without changing the task or detail
        // the user selected in the expanded list.
        guard compact else { return selected }
        if let selected, Self.needsAttention(selected) { return selected }
        if let attention = tasks.first(where: Self.needsAttention) { return attention }
        if let completed = compactCompletionTask { return completed }
        if let selected, Self.isRunning(selected) { return selected }
        return tasks.first(where: Self.isRunning) ?? selected
    }
    var showsCompactQuota: Bool {
        tasks.isEmpty || tasks.allSatisfy {
            $0.renderState.visualState == .completed && !Self.needsAttention($0)
        }
    }
    @Published private(set) var showsCompletedStatistic = false
    private struct CompactCompletion: Equatable {
        let id: Int
        let identity: CodexActivityTaskIdentity?
    }
    @Published private var compactCompletion: CompactCompletion?
    private var compactCompletionTask: CodexMultitaskRenderTask? {
        guard let compactCompletion, runningCount > 0 else { return nil }
        return tasks.first {
            $0.id == compactCompletion.id && $0.renderState.taskIdentity == compactCompletion.identity
                && $0.renderState.visualState == .completed && !Self.needsAttention($0)
        }
    }
    private var completionFocusClose: DispatchWorkItem?
    private var statisticRotation: DispatchWorkItem?
    private var completionFocusSerial: UInt64 = 0
    private var statisticSerial: UInt64 = 0
    private func noteCompletion(_ task: CodexMultitaskRenderTask) {
        // A burst is one presentation, extended by each new completion. Never
        // queue one animation per task or replay completions from initial sync.
        cancelCompletionFocus()
        compactCompletion = CompactCompletion(id: task.id, identity: task.renderState.taskIdentity)
        showsCompletedStatistic = true
        cancelStatisticRotation()
        reconcileCompactSignals()
    }
    private func cancelCompletionFocus() {
        completionFocusClose?.cancel(); completionFocusClose = nil
        completionFocusSerial &+= 1
    }
    private func cancelStatisticRotation() {
        statisticRotation?.cancel(); statisticRotation = nil
        statisticSerial &+= 1
    }
    private func reconcileCompactSignals() {
        guard display?.visible == true, !tasks.isEmpty else {
            cancelCompletionFocus(); cancelStatisticRotation()
            if compactCompletion != nil { compactCompletion = nil }
            if showsCompletedStatistic { showsCompletedStatistic = false }
            return
        }
        // A new turn, removal, pending request, or the last running task ending
        // invalidates the receipt immediately, even while the island is open.
        if compactCompletion != nil && (compactCompletionTask == nil || attentionCount > 0) {
            cancelCompletionFocus(); compactCompletion = nil
        }
        guard compact else {
            // Count the receipt only while the compact island is visible.
            // Expanded/manual details keep their own selection and timing.
            cancelCompletionFocus(); cancelStatisticRotation()
            return
        }
        if compactCompletion != nil, completionFocusClose == nil {
            let serial = completionFocusSerial
            let work = DispatchWorkItem { [weak self] in
                guard let self, serial == completionFocusSerial else { return }
                completionFocusClose = nil; compactCompletion = nil
            }
            completionFocusClose = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
        guard completedCount > 0 else {
            cancelStatisticRotation()
            if showsCompletedStatistic { showsCompletedStatistic = false }
            return
        }
        guard statisticRotation == nil else { return }
        let serial = statisticSerial
        let work = DispatchWorkItem { [weak self] in
            guard let self, serial == statisticSerial else { return }
            statisticRotation = nil; showsCompletedStatistic.toggle()
            reconcileCompactSignals()
        }
        statisticRotation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    var compactTaskText: String {
        if showsCompactQuota { return summary }
        guard let task = focusedTask else { return summary }
        let render = task.renderState
        let copy = IslandOperationText(operation: render.operation,
            statusTitle: render.statusTitle, completed: render.visualState == .completed)
        let detail = copy.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = detail.isEmpty ? title : detail
        let status = render.statusTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return [status, content == status ? "" : content].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    func setGeometry(_ value: IslandNotchGeometry) { if geometry != value { geometry = value } }
    func preview() { claimManualPresentation(); guard compact else { return }; presentation = .preview; onChange?() }
    private var automaticClose: DispatchWorkItem?
    private var automaticallyPresented = false
    private(set) var automaticPreviewDeadline: Date?
    private func claimManualPresentation() {
        cancelAutomaticPreview(); automaticallyPresented = false
    }
    private func cancelAutomaticPreview() {
        automaticClose?.cancel(); automaticClose = nil; automaticPreviewDeadline = nil
    }
    private func showAutomaticPreview(at now: Date) {
        guard display?.automaticPopupEnabled != false, !showsUsage,
            presentation == .resting || automaticallyPresented else { return }
        cancelAutomaticPreview()
        automaticallyPresented = true
        presentation = .preview
        let duration = TimeInterval(AppPreferences.CodexActivityAutomaticPopupTiming.normalizedDuration(
            display?.automaticPopupDuration ?? AppPreferences.CodexActivityAutomaticPopupTiming.defaultDuration))
        automaticPreviewDeadline = now.addingTimeInterval(duration)
        let work = DispatchWorkItem { [weak self] in self?.finishAutomaticPreview(at: Date()) }
        automaticClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
    func finishAutomaticPreview(at now: Date) {
        guard let deadline = automaticPreviewDeadline, now >= deadline else { return }
        cancelAutomaticPreview()
        guard attentionCount == 0, presentation == .preview else { return }
        collapse()
    }
    func endPreview() {
        guard !showsReset, !resetTransitionInFlight, automaticPreviewDeadline == nil, attentionCount == 0 else { return }
        if presentation == .preview { collapse() }
    }
    func pin() { claimManualPresentation(); presentation = .pinned; onChange?() }
    func collapse() {
        // Explicit dismissal changes presentation only. Active requests and
        // their drafts remain available when the user opens the island again.
        claimManualPresentation()
        clearResetPresentation(); showsUsage = false; presentation = .resting; detailID = nil; onChange?()
    }
    func dismissFromOutside() {
        guard presentation != .pinned else { return }
        collapse()
    }
    func text(_ zh: LocalizedCopy, _ en: LocalizedCopy) -> String { AppCopy(language: language).text(zh, en) }
    var summary: String {
        if tasks.isEmpty { return display?.connectionTitle.isEmpty == false ? display!.connectionTitle : text("暂无运行任务", "No running tasks") }
        if completedCount == tasks.count { return text("全部任务已完成", "All tasks completed") }
        return text("\(runningCount) 项运行中 · \(completedCount) 项完成", "\(runningCount) running · \(completedCount) done")
    }
    var totalTokens: String {
        guard let tokens = display?.totalTokens else { return "Token —" }
        return text("会话累计 ", "Session total ") + CodexActivityTokenUsageFormatter.string(for: tokens) + " tokens"
    }
    var quotaPercent: String {
        display?.remainingPercent.map { "\(min(100, max(0, $0)))%" } ?? "—"
    }
    var quota: String {
        let countdown = AppCopy(language: language).quotaCountdown(until: display?.quotaResetsAt, now: Date())
        return quotaPercent + " · " + countdown
    }

    func update(_ incoming: CodexMultitaskDisplay, reduceMotion: Bool, now: Date = Date()) {
        let value = incoming
        if value.islandFloatingUsageEnabled && !value.privacyMode {
            floatingUsageClock.advance(to: now)
        }
        let previous = display
        let hadAttention = attentionCount > 0
        let wasCompact = display?.state.compact == true
        let previousApprovalID = approval?.task.id
        let previousRequestIDs = (previous?.activeRequestIDs ?? []).union(
            previous?.taskDetails.values.compactMap { $0.confirmation?.id } ?? [])
        var automaticSelection: Int?
        // Repeated source/clock snapshots must not invalidate both hosting trees.
        if display != value { display = value }
        // Changing this preference only dismisses content opened by an automatic event.
        // A manually opened request, usage page or pinned island keeps its presentation.
        if !value.automaticPopupEnabled && automaticallyPresented {
            claimManualPresentation()
            if presentation == .preview && !showsUsage { presentation = .resting; detailID = nil }
        }
        let requestIDs = value.activeRequestIDs.union(value.taskDetails.values.compactMap { $0.confirmation?.id })
        let newRequestIDs = requestIDs.subtracting(previousRequestIDs)
        let newAttention = tasks.contains { task in
            guard Self.needsAttention(task) else { return false }
            guard let old = previous?.state.tasks.first(where: { $0.id == task.id }) else { return true }
            return !Self.needsAttention(old) || old.renderState.taskIdentity != task.renderState.taskIdentity
        }
        let drafts = approvalDrafts.filter { requestIDs.contains($0.key) }
        if drafts != approvalDrafts { approvalDrafts = drafts }
        if let previousApprovalID, value.taskDetails[previousApprovalID]?.confirmation == nil {
            detailID = nil
        }
        let sourceIDs = Set(value.taskDetails.values.flatMap { $0.entries.map(\.id) })
        let remaining = expandedTraceEntries.intersection(sourceIDs)
        if remaining != expandedTraceEntries { expandedTraceEntries = remaining }
        if self.reduceMotion != reduceMotion { self.reduceMotion = reduceMotion }
        if reduceMotion || !value.playbackEnabled { finishResetTransition(serial: resetTransitionSerial) }
        if !value.visible { clearResetPresentation(); showsUsage = false }
        if !wasCompact && value.state.compact && presentation != .pinned {
            presentation = .resting; detailID = nil
        }
        // Request identities, rather than polling/activity changes, open the
        // matching detail. Keep a request the user is already reviewing intact;
        // its queue control provides an explicit way to switch pending requests.
        if value.visible, value.automaticPopupEnabled, !showsUsage, presentation != .pinned,
           !(previousApprovalID != nil && approval != nil),
           let task = tasks.first(where: { task in
               guard let request = value.taskDetails[task.id]?.confirmation,
                     request.protocolRequest != nil else { return false }
               return newRequestIDs.contains(request.id)
                   || (!newRequestIDs.isEmpty && request.queueCount > (previous?.taskDetails[task.id]?.confirmation?.queueCount ?? 0))
           }) {
            cancelAutomaticPreview(); automaticallyPresented = true; presentation = .preview
            detailID = task.id
            automaticSelection = task.id
        }
        if !value.visible {
            claimManualPresentation(); presentation = .resting; detailID = nil
        } else if attentionCount > 0 {
            cancelAutomaticPreview()
            // A pending state keeps an automatic presentation open, but cannot
            // undo an explicit collapse on each ordinary activity refresh.
            if compact && value.automaticPopupEnabled && (newAttention || !newRequestIDs.isEmpty) {
                automaticallyPresented = true; presentation = .preview
            }
        } else {
            // Compare semantic task/turn transitions, not selection, progress or text.
            // First sync (and wake) is a baseline so historical completions do not replay.
            let event = previous?.visible == true && tasks.contains { task in
                let old = previous?.state.tasks.first { $0.id == task.id }
                if Self.isRunning(task) {
                    return old == nil || old?.renderState.taskIdentity != task.renderState.taskIdentity
                        || (old.map { !Self.isRunning($0) && !Self.needsAttention($0) } ?? false)
                }
                return task.renderState.visualState == .completed
                    && old != nil && old?.renderState.visualState != .completed
            }
            if event && value.automaticPopupEnabled { showAutomaticPreview(at: now) }
            else if hadAttention && presentation != .pinned && !showsUsage { collapse() }
        }
        if attentionOnly && attentionCount == 0 { attentionOnly = false }
        if let detailID, !visibleTasks.contains(where: { $0.id == detailID }) { self.detailID = nil }
        let newCompletion = previous?.visible == true && value.visible ? tasks.first { task in
            guard task.renderState.visualState == .completed,
                  let old = previous?.state.tasks.first(where: { $0.id == task.id }) else { return false }
            return old.renderState.visualState != .completed
                || old.renderState.taskIdentity != task.renderState.taskIdentity
        } : nil
        if let newCompletion { noteCompletion(newCompletion) }
        else { reconcileCompactSignals() }
        // Selection synchronously publishes the model in production. Avoid a
        // second layout pass before that selected model reaches the board.
        if let automaticSelection, let onSelect { onSelect(automaticSelection) }
        else { onChange?() }
    }
    func select(_ id: Int) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        taskScrollLink.prepareLayoutChange()
        claimManualPresentation()
        if compact { presentation = .preview }
        detailID = detailID == id ? nil : id
        // Selection publishes the resulting model synchronously. Avoid laying out
        // the old selection first, then repeating layout for the new selection.
        if let onSelect { onSelect(id) } else { onChange?() }
    }
    func toggleAttention() {
        showsUsage = false
        guard attentionCount > 0 else { return }
        claimManualPresentation()
        attentionOnly.toggle(); if compact { presentation = .preview }
        if !visibleTasks.contains(where: { $0.id == detailID }) { detailID = nil }
        onChange?()
    }
    func toggleCompact() {
        if compact { preview() } else { collapse() }
    }
    func dismissDetail() { taskScrollLink.prepareLayoutChange(); detailID = nil; onChange?() }
    func archiveTask(_ id: Int) {
        onArchive?(id)
    }
    func toggleTraceDisclosure(_ id: UUID) {
        guard let detail = inlineDetail, detailData(for: detail).visibleEntries.contains(where: { $0.id == id }) else { return }
        taskScrollLink.prepareLayoutChange()
        if expandedTraceEntries.contains(id) { expandedTraceEntries.remove(id) } else { expandedTraceEntries.insert(id) }
        onChange?()
    }
    func escape() {
        if showsReset { closeReset() }
        else if showsUsage { closeUsage() }
        else if detailID != nil { dismissDetail() }
        else if attentionOnly { attentionOnly = false; onChange?() }
        else if !compact { toggleCompact() }
    }
}
