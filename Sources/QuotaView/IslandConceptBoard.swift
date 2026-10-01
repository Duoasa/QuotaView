import AppKit
import SwiftUI
import QuotaViewCore
#if canImport(QuotaViewWidgetContract)
import QuotaViewWidgetContract
#endif

// Measured from the visible native Vibe Island reference, in logical points.
// Shared metrics keep row layout, hit regions and the fixed canvas consistent.
enum IslandVibeLayout {
    static let expandedWidth: CGFloat = 680
    static let compactWidth: CGFloat = 340
    static let compactContentGap: CGFloat = 16
    static let headerHeight: CGFloat = 36
    static let footerHeight: CGFloat = 28
    static let outerEffectInset = CodexActivityIslandProgressBarGeometry.effectInset
    static let screenBottomClearance = outerEffectInset
    static let rowHeight: CGFloat = 60
    static let rowSpacing: CGFloat = 8
    static let rowPitch: CGFloat = rowHeight + rowSpacing
    static let minimumDetailHeight: CGFloat = 100
    static let maximumDetailViewportHeight: CGFloat = 200
    static let listInset: CGFloat = 28
    static let listVerticalInset: CGFloat = 12
    static let maximumNotchLip: CGFloat = 16
    static let scrollRailWidth: CGFloat = 14
    static let scrollThumbWidth: CGFloat = 6
    static let scrollRailGap: CGFloat = 8
    // Equal visible spacing on both sides of the thumb, inside the notch lip.
    static let scrollRailTrailingInset = maximumNotchLip + scrollRailGap - (scrollRailWidth - scrollThumbWidth) / 2
    static let scrollingListTrailingInset = maximumNotchLip + scrollRailGap * 2 + scrollThumbWidth
    static let rowRadius: CGFloat = 10
    static let iconSlot: CGFloat = 34
    static let orbDiameter: CGFloat = 28
    static let contentGap: CGFloat = 12
    static let lineGap: CGFloat = 5
    static let titleFont: CGFloat = 13
    static let operationFont: CGFloat = 11
    static let metadataFont: CGFloat = 10
}

@MainActor
private enum IslandProviderIcon {
    static let image = Bundle.main.url(forResource: "CodexProviderIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
}

// Geometry uses NSScreen's public safe/auxiliary regions, not model-specific sizes.
struct IslandNotchGeometry: Equatable {
    let screenFrame: CGRect
    let usableBottomY: CGFloat
    let cameraWidth: CGFloat
    let centerX: CGFloat
    let bandHeight: CGFloat
    let isSimulated: Bool
    var hasCamera: Bool { cameraWidth > 0 }
    var compactWidth: CGFloat { hasCamera && !isSimulated ? cameraWidth + 280 : IslandVibeLayout.compactWidth }
    var maximumExpandedHeight: CGFloat { max(0, screenFrame.maxY - usableBottomY - IslandVibeLayout.screenBottomClearance) }
    init(frame: CGRect, safeTop: CGFloat = 0, left: CGRect? = nil, right: CGRect? = nil, simulated: Bool = false, visibleFrame: CGRect? = nil) {
        screenFrame = frame
        // Keep the top attached to the display edge, reserving only the Dock/bottom clearance.
        usableBottomY = max(frame.minY, min(frame.maxY, visibleFrame?.minY ?? frame.minY))
        isSimulated = simulated
        if safeTop > 0, let left, let right, right.minX > left.maxX {
            cameraWidth = right.minX - left.maxX
            centerX = (left.maxX + right.minX) / 2
            bandHeight = simulated ? safeTop : max(32, safeTop)
        } else {
            cameraWidth = 0; centerX = frame.midX; bandHeight = 30
        }
    }
    static func simulated(in frame: CGRect, visibleFrame: CGRect? = nil) -> Self {
        // Fit the mock camera inside the existing 340 x 30 compact island.
        let halfWidth = (frame.width - 96) / 2
        return Self(frame: frame, safeTop: 30,
            left: CGRect(x: frame.minX, y: frame.maxY - 30, width: halfWidth, height: 30),
            right: CGRect(x: frame.midX + 48, y: frame.maxY - 30, width: halfWidth, height: 30),
            simulated: true, visibleFrame: visibleFrame)
    }
}

// One continuous silhouette grows from the display edge. Hardware avoidance
// belongs to the content layout, not a narrow neck above a separate wide tray.
struct IslandNotchShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // Vibe Island's visible reference uses small concave top corners and
        // larger convex bottom corners. Scale both continuously on expansion.
        let lip = min(bottomRadius * 2 / 3, min(IslandVibeLayout.maximumNotchLip, min(w / 6, h / 3)))
        let bottom = min(bottomRadius, min((w - lip * 2) / 2, h / 2))
        let arc: CGFloat = 0.5522847498
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        // Small concave upper corners join the screen, with no horizontal shelf.
        p.addCurve(to: CGPoint(x: w - lip, y: lip), control1: CGPoint(x: w - lip * arc, y: 0), control2: CGPoint(x: w - lip, y: lip * (1 - arc)))
        p.addLine(to: CGPoint(x: w - lip, y: h - bottom))
        p.addCurve(to: CGPoint(x: w - lip - bottom, y: h), control1: CGPoint(x: w - lip, y: h - bottom * (1 - arc)), control2: CGPoint(x: w - lip - bottom * (1 - arc), y: h))
        p.addLine(to: CGPoint(x: lip + bottom, y: h))
        p.addCurve(to: CGPoint(x: lip, y: h - bottom), control1: CGPoint(x: lip + bottom * (1 - arc), y: h), control2: CGPoint(x: lip, y: h - bottom * (1 - arc)))
        p.addLine(to: CGPoint(x: lip, y: lip))
        p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: lip, y: lip * (1 - arc)), control2: CGPoint(x: lip * arc, y: 0))
        p.closeSubpath(); return p
    }
}

// Native presentation: an independent presentation of the console's fixture adapter.
// Selection means inspecting a task, never inferred Codex window focus.
@MainActor
final class IslandBoardState: ObservableObject {
    @Published private(set) var display: CodexMultitaskDisplay?
    @Published private(set) var detailID: Int?
    @Published private(set) var expandedTraceEntries: Set<UUID> = []
    @Published private(set) var showingTraceHistory = false
    private struct DetailMetricsKey: Equatable {
        let data: IslandTaskDetailData
        let english: Bool
        let expanded: Set<UUID>
        let history: Bool
    }
    // At most the normal and rail-adjusted widths; clocks and scrolling reuse
    // identical content metrics instead of repeatedly measuring source output.
    private var detailMetricsCache: [CGFloat: (DetailMetricsKey, IslandTaskDetailMetrics)] = [:]
    private struct ApprovalMetricsKey: Equatable {
        let request: IslandConfirmation
        let english: Bool
        let maximumViewportHeight: CGFloat
        let cardHeight: CGFloat
    }
    private var approvalMetricsCache: [CGFloat: (ApprovalMetricsKey, IslandApprovalMetrics)] = [:]
    @Published private var approvalDrafts: [UUID: IslandApprovalDraft] = [:]
    func approvalDraftBinding(for id: UUID) -> Binding<IslandApprovalDraft> {
        .init(get: { self.approvalDrafts[id] ?? .init() }, set: { self.approvalDrafts[id] = $0 })
    }
    @Published private(set) var attentionOnly = false
    enum Presentation: Equatable { case resting, preview, pinned }
    @Published private(set) var presentation: Presentation = .resting
    @Published private(set) var geometry = IslandNotchGeometry(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
    var reviewingCompletion: Bool { presentation != .resting && display?.state.allCompleted == true }
    @Published private(set) var reduceMotion = false
    var onChange: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    var onArchive: ((Int) -> Void)?
    var onNextRequest: ((Int) -> Void)?
    var onRefreshUsage: (() async -> Void)?
    @Published private(set) var showsUsage = false
    @Published private(set) var usageHeight: CGFloat = 500
    @Published private(set) var showsReset = false
    @Published private(set) var resetHeight: CGFloat = 434
    @Published private(set) var resetTransitionInFlight = false
    @Published private(set) var resetTransitionSerial: UInt64 = 0
    private var resetTransitionFinish: DispatchWorkItem?
    var resetWidth: CGFloat { min(max(378, geometry.cameraWidth + 200), expandedWidth) }
    var expandedCanvasHeight: CGFloat {
        showsUsage ? headerHeight + max(usageHeight, resetHeight) : expandedHeight
    }
    func updateResetHeight(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let height = ceil(value)
        guard abs(resetHeight - height) > 0.5 else { return }
        resetHeight = height
        if showsReset { onChange?() }
    }
    func openReset() {
        guard showsUsage, !showsReset else { return }
        cancelAutomaticPreview(); showsReset = true; beginResetTransition()
    }
    func closeReset() {
        guard showsReset else { return }
        showsReset = false; beginResetTransition()
    }
    private func beginResetTransition() {
        resetTransitionFinish?.cancel(); resetTransitionSerial &+= 1
        resetTransitionInFlight = !reduceMotion && display?.playbackEnabled != false
        if resetTransitionInFlight {
            let serial = resetTransitionSerial
            let finish = DispatchWorkItem { [weak self] in self?.finishResetTransition(serial: serial) }
            resetTransitionFinish = finish
            DispatchQueue.main.asyncAfter(deadline: .now() + IslandResetTicketFlight.duration + 0.04, execute: finish)
        }
        onChange?()
    }
    func finishResetTransition(serial: UInt64) {
        guard serial == resetTransitionSerial else { return }
        resetTransitionFinish?.cancel(); resetTransitionFinish = nil
        resetTransitionInFlight = false
    }
    private func clearResetPresentation() {
        resetTransitionFinish?.cancel(); resetTransitionFinish = nil
        resetTransitionSerial &+= 1; resetTransitionInFlight = false; showsReset = false
    }
    func updateUsageHeight(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let height = ceil(value)
        guard abs(usageHeight - height) > 0.5 else { return }
        usageHeight = height
        if showsUsage { onChange?() }
    }
    func openUsage() { cancelAutomaticPreview(); showsUsage = true; if compact { presentation = .preview }; onChange?() }
    func closeUsage() { clearResetPresentation(); showsUsage = false; onChange?() }
    func clearDrafts() { approvalDrafts.removeAll() }
    var onConfirmation: ((Int, UUID, IslandConfirmationDecision) -> Void)?
    var english: Bool { display?.english ?? false }
    var tasks: [CodexMultitaskRenderTask] { display?.state.tasks ?? [] }
    static func needsAttention(_ task: CodexMultitaskRenderTask) -> Bool { task.hasPendingRequest || task.renderState.visualState == .awaitingConfirmation }
    static func isRunning(_ task: CodexMultitaskRenderTask) -> Bool {
        [.working, .thinking, .compactingContext].contains(task.renderState.visualState)
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
    var expandedWidth: CGFloat { min(max(IslandVibeLayout.expandedWidth, geometry.compactWidth + 64), geometry.screenFrame.width - 48) }
    var headerHeight: CGFloat { max(IslandVibeLayout.headerHeight, geometry.bandHeight) }
    var maximumApprovalViewportHeight: CGFloat {
        max(0, geometry.maximumExpandedHeight - headerHeight - IslandApprovalMetrics.fixedHeight)
    }
    var compactSideWidth: CGFloat { max(0, (min(geometry.compactWidth, expandedWidth) - 40 - geometry.cameraWidth - 16) / 2) }
    var headerSideWidth: CGFloat { max(0, (surfaceWidth - (showsReset ? 56 : 76) - geometry.cameraWidth - 16) / 2) }
    private struct CardGeometryKey: Hashable { let model: String; let effort: String; let width: CGFloat }
    private var cardGeometryCache: [CardGeometryKey: CGFloat] = [:]
    private func measuredCardHeight(_ metadata: IslandSessionMetadata?, width: CGFloat) -> CGFloat {
        guard let metadata else { return IslandVibeLayout.rowHeight }
        let key = CardGeometryKey(model: metadata.modelName, effort: metadata.reasoningEffort, width: width)
        if let height = cardGeometryCache[key] { return height }
        if cardGeometryCache.count >= 256 { cardGeometryCache.removeAll() }
        let height = metadata.cardHeight(width: width); cardGeometryCache[key] = height; return height
    }
    var rowWidth: CGFloat { expandedWidth - IslandVibeLayout.listInset - (showsScrollRail ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset) }
    func rowHeight(_ task: CodexMultitaskRenderTask) -> CGFloat { measuredCardHeight(display?.sessionMetadata[task.id], width: rowWidth) }
    var rowHeights: [Int: CGFloat] { Dictionary(uniqueKeysWithValues: visibleTasks.map { ($0.id, rowHeight($0)) }) }
    var listHeight: CGFloat {
        let rows = visibleTasks.isEmpty ? IslandVibeLayout.rowPitch : visibleTasks.prefix(4).reduce(0) { $0 + rowHeight($1) + IslandVibeLayout.rowSpacing }
        let detail = inlineDetail == nil ? 0 : min(detailHeight, IslandVibeLayout.maximumDetailViewportHeight) + IslandVibeLayout.rowSpacing
        return min(rows + detail + IslandVibeLayout.listVerticalInset * 2 - IslandVibeLayout.rowSpacing, max(60, geometry.maximumExpandedHeight - headerHeight - IslandVibeLayout.footerHeight))
    }
    func detailData(for task: CodexMultitaskRenderTask) -> IslandTaskDetailData {
        display?.taskDetails[task.id] ?? .init(entries: [], confirmation: nil, status: .unknown)
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
        return approval == nil && (visibleTasks.count > 4 || unrailedDetailHeight > IslandVibeLayout.maximumDetailViewportHeight || rows + IslandVibeLayout.listVerticalInset * 2 - IslandVibeLayout.rowSpacing > geometry.maximumExpandedHeight - headerHeight - IslandVibeLayout.footerHeight)
    }
    func approvalMetrics(request: IslandConfirmation) -> IslandApprovalMetrics {
        let width = expandedWidth - IslandVibeLayout.listInset * 2
        let metrics = measuredApproval(request: request, width: width)
        return metrics.showsRail ? measuredApproval(request: request,
            width: expandedWidth - IslandVibeLayout.listInset - IslandVibeLayout.scrollingListTrailingInset) : metrics
    }
    private func measuredApproval(request: IslandConfirmation, width: CGFloat) -> IslandApprovalMetrics {
        let key = ApprovalMetricsKey(request: request, english: english, maximumViewportHeight: maximumApprovalViewportHeight, cardHeight: approval.flatMap { display?.sessionMetadata[$0.task.id] }?.cardHeight(width: width) ?? IslandVibeLayout.rowHeight)
        if let cached = approvalMetricsCache[width], cached.0 == key { return cached.1 }
        let result = IslandApprovalMetrics(request: request, width: width, english: english,
            maximumViewportHeight: key.maximumViewportHeight, cardHeight: key.cardHeight)
        if approvalMetricsCache[width] == nil && approvalMetricsCache.count >= 2 { approvalMetricsCache.removeAll() }
        approvalMetricsCache[width] = (key, result)
        return result
    }
    func detailMetrics(for task: CodexMultitaskRenderTask) -> IslandTaskDetailMetrics {
        measuredDetail(for: task, width: expandedWidth - IslandVibeLayout.listInset
            - (showsScrollRail ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset))
    }
    private func measuredDetail(for task: CodexMultitaskRenderTask, width: CGFloat) -> IslandTaskDetailMetrics {
        let key = DetailMetricsKey(data: detailData(for: task), english: english, expanded: expandedTraceEntries, history: showingTraceHistory)
        if let cached = detailMetricsCache[width], cached.0 == key { return cached.1 }
        let result = IslandTaskDetailMetrics(data: key.data, width: width, english: english, expandedEntries: key.expanded, showsHistory: key.history)
        if detailMetricsCache[width] == nil && detailMetricsCache.count >= 2 { detailMetricsCache.removeAll() }
        detailMetricsCache[width] = (key, result)
        return result
    }
    var detailHeight: CGFloat { inlineDetail.map { detailMetrics(for: $0).height } ?? 0 }
    var expandedHeight: CGFloat {
        if showsUsage { return headerHeight + (showsReset ? resetHeight : usageHeight) }
        if let approval { return headerHeight + approvalMetrics(request: approval.request).height }
        return headerHeight + listHeight + IslandVibeLayout.footerHeight
    }
    var surfaceWidth: CGFloat { compact ? min(geometry.compactWidth, expandedWidth) : (showsReset ? resetWidth : expandedWidth) }
    var height: CGFloat { compact ? geometry.bandHeight : expandedHeight }
    var focusedTask: CodexMultitaskRenderTask? {
        tasks.first { $0.id == display?.state.selectedID } ?? tasks.first
    }
    var compactTaskText: String {
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
    func preview() { guard compact else { return }; presentation = .preview; onChange?() }
    private var automaticClose: DispatchWorkItem?
    private(set) var automaticPreviewDeadline: Date?
    private func cancelAutomaticPreview() {
        automaticClose?.cancel(); automaticClose = nil; automaticPreviewDeadline = nil
    }
    private func showAutomaticPreview(at now: Date) {
        guard presentation != .pinned, !showsUsage else { return }
        cancelAutomaticPreview()
        presentation = .preview
        automaticPreviewDeadline = now.addingTimeInterval(3)
        let work = DispatchWorkItem { [weak self] in self?.finishAutomaticPreview(at: Date()) }
        automaticClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
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
    func pin() { cancelAutomaticPreview(); presentation = .pinned; onChange?() }
    func collapse() {
        guard attentionCount == 0 else { return }
        cancelAutomaticPreview()
        clearResetPresentation(); showsUsage = false; presentation = .resting; detailID = nil; onChange?()
    }
    func dismissFromOutside() {
        guard presentation != .pinned else { return }
        collapse()
    }
    func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    var summary: String {
        if tasks.isEmpty { return display?.connectionTitle.isEmpty == false ? display!.connectionTitle : text("暂无运行任务", "No running tasks") }
        if completedCount == tasks.count { return text("全部任务已完成", "All tasks completed") }
        return text("\(runningCount) 项运行中 · \(completedCount) 项完成", "\(runningCount) running · \(completedCount) done")
    }
    var totalTokens: String {
        guard let tokens = display?.totalTokens else { return "Token —" }
        return text("会话合计 ", "Sessions total ") + CodexActivityTokenUsageFormatter.string(for: tokens) + " tokens"
    }
    var quota: String {
        let percent = display?.remainingPercent.map { "\(min(100, max(0, $0)))%" } ?? "—"
        let countdown = MenuBarQuotaImage.countdown(until: display?.quotaResetsAt, now: Date(),
            copy: AppCopy(language: english ? .english : .simplifiedChinese))
        return percent + " · " + countdown
    }
    func update(_ value: CodexMultitaskDisplay, reduceMotion: Bool, now: Date = Date()) {
        let previous = display
        let hadAttention = attentionCount > 0
        let wasCompact = display?.state.compact == true
        let previousApprovalID = approval?.task.id
        display = value
        let requestIDs = value.activeRequestIDs.union(value.taskDetails.values.compactMap { $0.confirmation?.id })
        let drafts = approvalDrafts.filter { requestIDs.contains($0.key) }
        if drafts != approvalDrafts { approvalDrafts = drafts }
        if let previousApprovalID, value.taskDetails[previousApprovalID]?.confirmation == nil {
            detailID = nil; showingTraceHistory = false
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
        if !value.visible {
            cancelAutomaticPreview(); presentation = .resting; detailID = nil
        } else if attentionCount > 0 {
            cancelAutomaticPreview()
            if compact { presentation = .preview }
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
            if event { showAutomaticPreview(at: now) }
            else if hadAttention && presentation != .pinned && !showsUsage { collapse() }
        }
        if attentionCount == 0 { attentionOnly = false }
        if !visibleTasks.contains(where: { $0.id == detailID }) { detailID = nil }
        onChange?()
    }
    func select(_ id: Int) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        if compact { presentation = .preview }
        detailID = detailID == id ? nil : id
        showingTraceHistory = false
        // Selection publishes the resulting model synchronously. Avoid laying out
        // the old selection first, then repeating layout for the new selection.
        if let onSelect { onSelect(id) } else { onChange?() }
    }
    func toggleAttention() {
        showsUsage = false
        guard attentionCount > 0 else { return }
        attentionOnly.toggle(); if compact { presentation = .preview }
        if !visibleTasks.contains(where: { $0.id == detailID }) { detailID = nil }
        onChange?()
    }
    func toggleCompact() {
        if compact { preview() } else { collapse() }
    }
    func dismissDetail() { detailID = nil; onChange?() }
    func toggleTraceHistory() {
        guard let detail, detailData(for: detail).confirmation == nil else { return }
        showingTraceHistory.toggle(); onChange?()
    }
    func toggleTraceDisclosure(_ id: UUID) {
        guard let detail = inlineDetail, detailData(for: detail).visibleEntries.contains(where: { $0.id == id }) else { return }
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

private enum IslandBoardStyle {
    static let secondary = Color(nsColor: IslandTextPalette.secondary)
    static let muted = Color(nsColor: IslandTextPalette.muted)
    static let attention = Color(nsColor: .init(srgbRed: 0.90, green: 0.66, blue: 0.35, alpha: 1))
    // Keep the original amber hue, with more luminance and full opacity.
    static let confirmationHighlight = Color(nsColor: .init(srgbRed: 1, green: 0.76, blue: 0.44, alpha: 1))
    static let failure = Color(nsColor: .init(srgbRed: 0.95, green: 0.43, blue: 0.42, alpha: 1))
    static func statusColor(_ state: CodexActivityVisualState) -> Color {
        // Color marks a need for attention; ordinary state names use the text hierarchy.
        switch state {
        case .awaitingConfirmation: attention
        case .error: failure
        case .completed: Color(red: 0.36, green: 0.80, blue: 0.55)
        case .unavailable, .disconnectedCodex, .standby: muted
        case .thinking, .working, .compactingContext: Color(white: 0.92)
        }
    }
    static func attentionColor(for tasks: [CodexMultitaskRenderTask]) -> Color {
        if tasks.contains(where: { $0.renderState.visualState == .error }) { return failure }
        if tasks.contains(where: { $0.renderState.visualState == .awaitingConfirmation }) { return attention }
        return secondary
    }
    static func quotaColor(for percent: Int?) -> Color {
        switch CodexActivityQuotaRingContract.riskBand(for: percent) {
        case .healthy: secondary
        case .warning: attention
        case .critical: failure
        case .unavailable: muted
        }
    }
    static func icon(_ state: CodexActivityVisualState) -> String {
        switch state {
        case .completed: "checkmark"
        case .awaitingConfirmation: "hand.raised.fill"
        case .error: "exclamationmark"
        case .unavailable: "questionmark"
        case .compactingContext: "arrow.triangle.2.circlepath"
        default: "sparkle"
        }
    }
}

private struct IslandQuotaRing: View {
    let remainingPercent: Int?
    var body: some View {
        let fraction = CGFloat(min(100, max(0, remainingPercent ?? 0))) / 100
        let color = Color(nsColor: CodexActivityQuotaRingContract.color(for: remainingPercent))
        ZStack {
            Circle().stroke(Color(white: 0.18), lineWidth: 2.8)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.padding(1.4).frame(width: 14, height: 14).accessibilityHidden(true)
    }
}

// Native Metal draws independently of SwiftUI layout; hidden hosts never play.
private struct IslandActivityOrb: NSViewRepresentable {
    let visualState: CodexActivityVisualState
    let playback: Bool
    func makeNSView(context: Context) -> IslandActivityOrbHost { .init(state: visualState) }
    func updateNSView(_ view: IslandActivityOrbHost, context: Context) {
        view.configure(state: visualState, playback: playback)
    }
    static func dismantleNSView(_ view: IslandActivityOrbHost, coordinator: ()) { view.stop() }
}

private struct IslandQuantumProgress: NSViewRepresentable {
    let renderState: CodexActivityRenderState
    let visible: Bool
    let reduceMotion: Bool
    func makeNSView(context: Context) -> IslandQuantumProgressHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandQuantumProgressHost, context: Context) {
        view.configure(renderState: renderState, visible: visible, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: IslandQuantumProgressHost, coordinator: ()) { view.stop() }
}

private struct IslandOperationLine: View {
    let renderState: CodexActivityRenderState
    let visible: Bool
    let reduceMotion: Bool
    var body: some View {
        let completed = renderState.visualState == .completed
        let running = [.working, .thinking, .compactingContext].contains(renderState.visualState)
        let copy = IslandOperationText(operation: renderState.operation,
                                        statusTitle: renderState.statusTitle, completed: completed)
        HStack(spacing: 5) {
            IslandScrollingText(text: copy.status,
                font: .monospacedSystemFont(ofSize: IslandVibeLayout.operationFont, weight: .medium),
                color: NSColor(IslandBoardStyle.statusColor(renderState.visualState)),
                visible: visible, reduceMotion: reduceMotion, shimmer: running)
                .fixedSize()
            if !copy.detail.isEmpty {
                Text("·").font(.system(size: IslandVibeLayout.operationFont))
                    .foregroundStyle(IslandBoardStyle.muted).fixedSize()
                IslandScrollingText(text: copy.detail,
                    font: .monospacedSystemFont(ofSize: IslandVibeLayout.operationFont, weight: .medium),
                    color: completed ? .white : IslandTextPalette.detail,
                    visible: visible, reduceMotion: reduceMotion, shimmer: running)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityHint("\(copy.status) · \(copy.detail)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(copy.status), \(copy.detail)")
    }
}

// Shared presentation: list rows add selection, approval headers are read-only.
struct IslandTaskCard: View {
    let task: CodexMultitaskRenderTask
    let selected: Bool
    let metadata: IslandSessionMetadata?
    let english: Bool
    let playback: Bool
    let effectVisible: Bool
    let reduceMotion: Bool
    var hovered = false
    var showsArchiveButton = false
    var cardWidth: CGFloat = 656
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: IslandVibeLayout.contentGap) {
            if !selected {
                IslandActivityOrb(visualState: task.renderState.visualState, playback: playback)
                    .frame(width: IslandVibeLayout.orbDiameter, height: IslandVibeLayout.orbDiameter)
                    .frame(width: IslandVibeLayout.iconSlot).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: IslandVibeLayout.lineGap) {
                HStack(spacing: 6) {
                    IslandScrollingText(text: task.title,
                        font: .systemFont(ofSize: IslandVibeLayout.titleFont, weight: .semibold),
                        color: .white, visible: effectVisible, reduceMotion: reduceMotion)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).accessibilityHint(task.title)
                    if let metadata, !metadata.modelTitle.isEmpty, !metadata.usesExtraLine {
                        Text(metadata.modelTitle).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityHint(metadata.fullModelTitle)
                    }
                    if let icon = IslandProviderIcon.image {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                            .opacity(0.72)
                            .accessibilityLabel("Codex").accessibilityHint("Codex")
                    } else { Text("Codex").foregroundStyle(IslandBoardStyle.muted) }
                    if let metadata {
                        Text(metadata.durationTitle).monospacedDigit()
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
                    }
                }.padding(.trailing, showsArchiveButton ? 28 : 0)
                    .font(.system(size: IslandVibeLayout.metadataFont, weight: .semibold))
                    .foregroundStyle(IslandBoardStyle.muted)
                HStack(spacing: 8) {
                    IslandOperationLine(renderState: task.renderState, visible: effectVisible, reduceMotion: reduceMotion)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Text(task.renderState.tokenUsageTitle ?? "— tokens")
                        .font(.system(size: IslandVibeLayout.metadataFont, weight: .medium)).monospacedDigit()
                        .foregroundStyle(IslandBoardStyle.muted).fixedSize()
                        .accessibilityHint(english ? "Session total" : "会话累计")
                }
            }
        }.frame(height: IslandVibeLayout.rowHeight - 8)
        if let metadata, metadata.usesExtraLine {
            Text(metadata.modelTitle).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(IslandBoardStyle.muted).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityHint(metadata.fullModelTitle)
        }
        }.padding(.leading, 10).padding(.trailing, 8).frame(height: metadata?.cardHeight(width: cardWidth) ?? IslandVibeLayout.rowHeight)
            .background {
                if selected {
                    IslandQuantumProgress(renderState: task.renderState, visible: effectVisible, reduceMotion: reduceMotion)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else {
                    RoundedRectangle(cornerRadius: IslandVibeLayout.rowRadius)
                        .fill(Color.white.opacity(hovered ? 0.07 : 0.045))
                }
            }
            .overlay {
                // Selected completion already owns the single-island outline/glow.
                if !(selected && task.renderState.visualState == .completed) {
                    RoundedRectangle(cornerRadius: IslandVibeLayout.rowRadius)
                        .strokeBorder(task.renderState.visualState == .completed
                            ? Color(red: hovered ? 0.40 : 0.29, green: hovered ? 0.59 : 0.44, blue: hovered ? 0.47 : 0.35)
                            : Color.white.opacity(selected ? 0.22 : (hovered ? 0.095 : 0.055)), lineWidth: 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: IslandVibeLayout.rowRadius))
            .accessibilityHint("\(task.title) · \(task.renderState.statusTitle)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(task.title), \(task.renderState.statusTitle), \(task.renderState.operation), \(metadata?.modelTitle ?? ""), \(metadata?.durationTitle ?? ""), \(task.renderState.tokenUsageTitle ?? "—")")
    }
}

private struct IslandBoardTaskRow: View {
    let task: CodexMultitaskRenderTask
    let selected: Bool
    let metadata: IslandSessionMetadata?
    let english: Bool
    let playback: Bool
    let effectVisible: Bool
    let reduceMotion: Bool
    var cardWidth: CGFloat = 656
    let onArchive: () -> Void
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            IslandTaskCard(task: task, selected: selected, metadata: metadata, english: english,
                playback: playback, effectVisible: effectVisible, reduceMotion: reduceMotion, hovered: hovered, showsArchiveButton: true, cardWidth: cardWidth)
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .overlay(alignment: .topTrailing) {
                // Sibling hit target: archive must never also select/open the card.
                IslandTaskArchiveButton(english: english, action: onArchive)
                    .padding(.top, 6).padding(.trailing, 8)
            }
            .accessibilityValue(selected ? (english ? "Details open" : "详情已展开") : "")
    }
}

struct IslandTaskArchiveButton: View {
    let english: Bool
    let action: () -> Void
    @State private var hovered = false
    private var copy: AppCopy { .init(language: english ? .english : .simplifiedChinese) }
    var body: some View {
        Button(action: action) {
            Image(systemName: "archivebox")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(hovered ? 1 : 0.55))
                .frame(width: 24, height: 24).contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(IslandArchiveButtonStyle(hovered: hovered))
            .onHover { hovered = $0 }
            .accessibilityLabel(copy.islandArchiveTask)
            .accessibilityHint(copy.islandArchiveTaskHint)
    }
}
private struct IslandArchiveButtonStyle: ButtonStyle {
    let hovered: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.white.opacity(configuration.isPressed ? 0.16 : (hovered ? 0.10 : 0)),
            in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct IslandUsageEntryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .background(Color.white.opacity(isEnabled
                ? (configuration.isPressed ? 0.16 : (hovered ? 0.10 : 0)) : 0), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovered = isEnabled && $0 }
            .onChange(of: isEnabled) { _, enabled in if !enabled { hovered = false } }
    }
}

// Both hosts keep their final layout throughout a transition. The AppKit surface
// animates only the shell path, mask, opacity and a small content translation.
struct IslandBoardView: View {
    @ObservedObject var state: IslandBoardState
    let compactContent: Bool
    @State private var visibility = IslandListVisibility()
    private var visibleElements: Set<IslandListElement> { visibility.visible }
    @State private var scrollLink = IslandTaskScrollLink()
    @State private var approvalScrollLink = IslandTaskScrollLink()
    var body: some View {
        Group {
            if compactContent { compact }
            else {
                VStack(spacing: 0) {
                    header
                    if state.showsUsage {
                        usageFlow
                    } else if let approval = state.approval {
                        IslandApprovalView(task: approval.task, metadata: state.display?.sessionMetadata[approval.task.id],
                            request: approval.request, metrics: state.approvalMetrics(request: approval.request),
                            english: state.english, visible: !state.compact && state.display?.visible == true,
                            playbackEnabled: state.display?.playbackEnabled == true, reduceMotion: state.reduceMotion,
                            scrollLink: approvalScrollLink,
                            draft: state.approvalDraftBinding(for: approval.request.id),
                            onDecision: { requestID, decision in state.onConfirmation?(approval.task.id, requestID, decision) },
                            onArchive: { state.onArchive?(approval.task.id) })
                            .id(approval.request.id)
                    } else {
                        Group {
                            ScrollView(.vertical) {
                                // A variable-height detail makes LazyVStack estimate offscreen rows
                                // incorrectly. Exact row slots keep rail/visibility geometry deterministic;
                                // viewport/nearby content stays mounted, with offscreen playback stopped.
                                VStack(spacing: IslandVibeLayout.rowSpacing) {
                                    ForEach(state.visibleTasks, id: \.id) { task in
                                        taskGroup(task).id(task.id)
                                    }
                                    if state.visibleTasks.isEmpty {
                                        Text(state.text("等待任务开始", "Waiting for tasks"))
                                            .font(.system(size: 12)).foregroundStyle(IslandBoardStyle.muted)
                                            .frame(maxWidth: .infinity).frame(height: IslandVibeLayout.rowHeight)
                                    }
                                }.padding(.leading, IslandVibeLayout.listInset)
                                    .padding(.trailing, state.showsScrollRail
                                        ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset)
                                    .padding(.vertical, IslandVibeLayout.listVerticalInset)
                                    .background(IslandTaskScrollConfiguration(
                                        layout: .init(taskIDs: state.visibleTasks.map(\.id), detailID: state.inlineDetail?.id, detailHeight: state.detailHeight, rowHeights: state.rowHeights),
                                        active: !state.compact && state.display?.visible == true,
                                            onVisibilityChange: { visibility = $0 }, link: scrollLink))
                            }.scrollIndicators(.never).frame(height: state.listHeight)
                            .overlay(alignment: .trailing) {
                                if state.showsScrollRail {
                                    IslandTaskScrollRailView(link: scrollLink, label: state.text("任务滚动条", "Task scrollbar"))
                                        .frame(width: IslandVibeLayout.scrollRailWidth, height: state.listHeight - IslandVibeLayout.rowSpacing)
                                        .padding(.trailing, IslandVibeLayout.scrollRailTrailingInset)
                                        .padding(.bottom, IslandVibeLayout.rowSpacing)
                                }
                            }
                            // Keep native scroll position when details change. Scrolling
                            // the whole card/detail group would consume the top inset.
                        }
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Text(state.text("\(state.visibleTasks.count) 个会话", "\(state.visibleTasks.count) sessions"))
                                if state.showsScrollRail { Image(systemName: "arrow.up.arrow.down") }
                            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            Text(footerStatus).lineLimit(1).truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                                .accessibilityHint(footerStatus)
                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(IslandBoardStyle.muted)
                            .padding(.horizontal, 38).frame(height: IslandVibeLayout.footerHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if state.geometry.isSimulated {
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black)
                    .overlay {
                        UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .overlay { Circle().fill(Color(white: 0.12)).frame(width: 7, height: 7) }
                    .frame(width: state.geometry.cameraWidth, height: state.geometry.bandHeight)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
        .accessibilityHidden(compactContent ? !state.compact : state.compact)
    }
    private var usageFlow: some View {
        ZStack(alignment: .top) {
            IslandUsageBento(snapshot: state.display?.usageSnapshot, usageState: state.display?.usageState ?? .loading, english: state.english,
                contentWidth: state.expandedWidth - IslandVibeLayout.listInset * 2,
                privacy: state.display?.privacyMode == true,
                playbackEnabled: !state.compact && state.playback && !state.showsReset && !state.resetTransitionInFlight,
                hidesTicket: state.resetTransitionInFlight, onReset: state.openReset,
                onRefresh: state.onRefreshUsage, onHeightChange: state.updateUsageHeight)
                .frame(width: state.expandedWidth, height: state.usageHeight, alignment: .top)
                .opacity(state.showsReset ? 0 : 1)
                .animation(state.reduceMotion ? nil : .easeOut(duration: 0.22), value: state.showsReset)
                .allowsHitTesting(!state.showsReset && !state.resetTransitionInFlight)
                .accessibilityHidden(state.showsReset)
            IslandResetPage(data: .init(snapshot: state.display?.privacyMode == true ? nil : state.display?.usageSnapshot),
                usageState: state.display?.usageState ?? .loading, english: state.english, playbackEnabled: !state.compact && state.playback && state.showsReset && !state.resetTransitionInFlight,
                hidesTicket: state.resetTransitionInFlight, onRefresh: state.onRefreshUsage, onHeightChange: state.updateResetHeight)
                .frame(width: state.resetWidth, height: state.resetHeight, alignment: .top)
                .opacity(state.showsReset ? 1 : 0)
                .animation(state.reduceMotion ? nil : .easeOut(duration: 0.24), value: state.showsReset)
                .allowsHitTesting(state.showsReset && !state.resetTransitionInFlight)
                .accessibilityHidden(!state.showsReset)
        }.frame(width: state.expandedWidth, height: max(state.usageHeight, state.resetHeight), alignment: .top)
            .overlayPreferenceValue(IslandResetTicketAnchors.self) { anchors in
                GeometryReader { proxy in
                    if let source = anchors[.usage], let destination = anchors[.reset] {
                        IslandResetTicketFlightView(serial: state.resetTransitionSerial, toReset: state.showsReset,
                            active: state.resetTransitionInFlight && !state.compact && state.display?.visible != false,
                            source: proxy[source], destination: proxy[destination], reduceMotion: state.reduceMotion)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
    }
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if state.showsUsage {
                    Button { state.showsReset ? state.closeReset() : state.closeUsage() } label: {
                        Label(state.showsReset ? state.text("返回", "Back") : state.text("返回任务", "Tasks"), systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                            .frame(height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if !state.showsReset {
                        Text(state.text("用量统计", "Usage")).font(.system(size: 11)).foregroundStyle(IslandBoardStyle.muted)
                    }
                } else if state.approval != nil {
                    Circle().fill(IslandBoardStyle.confirmationHighlight).frame(width: 4, height: 4)
                    Text(state.text("待确认", "Permission request")).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IslandBoardStyle.confirmationHighlight)
                } else {
                    Button { state.openUsage() } label: {
                        HStack(spacing: 6) {
                            IslandQuotaRing(remainingPercent: state.display?.remainingPercent)
                            Text(state.quota).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                        }.frame(height: 28).contentShape(Rectangle())
                    }.buttonStyle(IslandUsageEntryButtonStyle()).accessibilityLabel(state.text("查看用量统计", "View usage"))
                }
                Spacer(minLength: 0)
            }.frame(width: state.geometry.hasCamera ? state.headerSideWidth : nil)
                .frame(maxWidth: .infinity).clipped()
            if state.geometry.hasCamera { Color.clear.frame(width: state.geometry.cameraWidth + 16) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let approval = state.approval {
                    if approval.request.queueCount > 1 {
                        Button("\(approval.request.queueIndex)/\(approval.request.queueCount) →") { state.onNextRequest?(approval.task.id) }.buttonStyle(.plain).accessibilityHint(state.text("下一项待处理请求", "Next pending request"))
                    }
                    Button { state.dismissDetail() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(state.text("返回列表", "Back to sessions")).font(.system(size: 11))
                        }.frame(height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityHint(state.text("返回任务列表，保留待确认请求", "Return to sessions without rejecting the request"))
                } else {
                    if state.attentionCount > 0 && !state.showsUsage {
                        Button { state.toggleAttention() } label: {
                            attentionIndicators(showCounts: true)
                                .font(.system(size: 11, weight: state.attentionOnly ? .bold : .semibold))
                                .frame(height: 28).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint(state.text("筛选待处理会话", "Filter sessions needing attention"))
                            .accessibilityValue(state.attentionOnly ? state.text("已筛选", "Filtered") : state.text("全部会话", "All sessions"))
                    }
                    Button { state.presentation == .pinned ? state.collapse() : state.pin() } label: {
                        Image(systemName: state.presentation == .pinned ? "pin.fill" : "pin")
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityHint(state.text("固定展开；再次点击收起", "Pin open; click again to collapse"))
                }
                Button { state.collapse() } label: {
                    Image(systemName: "chevron.up").frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint(state.text("收起灵动岛", "Collapse island"))
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(IslandBoardStyle.muted)
                .frame(width: state.geometry.hasCamera ? state.headerSideWidth : nil)
                .frame(maxWidth: .infinity)
                .clipped()
        }.padding(.horizontal, state.showsReset ? 28 : 38).frame(width: state.surfaceWidth, height: state.headerHeight)
    }
    private var compactOrb: some View {
        IslandActivityOrb(visualState: state.focusedTask?.renderState.visualState ?? .standby,
            playback: state.playback && state.compact && state.focusedTask.map(IslandBoardState.isRunning) == true)
            .frame(width: 18, height: 18).frame(width: 30).accessibilityHidden(true)
    }
    private var compactStatistics: some View {
        HStack(spacing: 8) {
            Text(state.text("\(state.tasks.count) 会话", "\(state.tasks.count) sessions"))
                .foregroundStyle(IslandBoardStyle.muted)
            attentionIndicators(showCounts: false)
        }.font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
            .frame(minWidth: 30, alignment: .trailing)
    }
    private var compactText: some View {
        IslandScrollingText(text: state.compactTaskText,
            font: .monospacedSystemFont(ofSize: 12, weight: .semibold),
            visible: state.playback && state.compact, reduceMotion: state.reduceMotion)
    }
    private var compact: some View {
        Button { state.preview() } label: {
            Group {
                if state.geometry.hasCamera {
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                            compactOrb
                            compactText.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }.frame(width: state.compactSideWidth)
                            .frame(maxWidth: .infinity).clipped()
                        Color.clear.frame(width: state.geometry.cameraWidth + 16)
                        compactStatistics.frame(width: state.compactSideWidth, alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing).clipped()
                    }
                } else {
                    // Equal side regions keep the text centered on the island,
                    // even when the session count or attention indicators change.
                    HStack(spacing: IslandVibeLayout.compactContentGap) {
                        compactStatistics.hidden().accessibilityHidden(true)
                            .overlay(alignment: .leading) { compactOrb }
                        GeometryReader { proxy in
                            compactText.frame(width: min(proxy.size.width,
                                IslandScrollingTextHost.width(of: state.compactTaskText,
                                    font: .monospacedSystemFont(ofSize: 12, weight: .semibold))))
                                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                        }.frame(maxWidth: .infinity).clipped()
                        compactStatistics
                    }
                }
            }.padding(.horizontal, 20).frame(height: state.geometry.bandHeight)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityHint(state.text("悬停或点击展开会话详情", "Hover or click to expand session details"))
            .accessibilityLabel("\(state.summary), \(state.quota)")
            .accessibilityValue(state.tasks.contains(where: { $0.renderState.visualState == .awaitingConfirmation })
                ? state.text("待确认", "Awaiting confirmation") : "")
    }
    private func attentionIndicators(showCounts: Bool) -> some View {
        let confirmations = state.tasks.filter { IslandBoardState.needsAttention($0) }.count
        let otherAttention = state.tasks.filter {
            [.error, .unavailable].contains($0.renderState.visualState)
        }
        return HStack(spacing: 8) {
            if confirmations > 0 {
                HStack(spacing: 4) {
                    Text(state.text("待确认", "Confirm"))
                    if showCounts { Text("\(confirmations)").monospacedDigit() }
                }.foregroundStyle(IslandBoardStyle.confirmationHighlight)
            }
            // Preserve separate failure/unavailable signals when confirmation coexists.
            if !otherAttention.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                    if showCounts { Text("\(otherAttention.count)").monospacedDigit() }
                }.foregroundStyle(IslandBoardStyle.attentionColor(for: otherAttention))
            }
        }.fixedSize()
    }
    private var footerStatus: String {
        state.tasks.isEmpty ? state.summary : state.statusCounts.map { "\($0.count) \($0.title)" }.joined(separator: " ")
    }
    private func taskGroup(_ task: CodexMultitaskRenderTask) -> some View {
        VStack(spacing: IslandVibeLayout.rowSpacing) {
            if visibility.residentTaskIDs.contains(task.id) {
                IslandBoardTaskRow(task: task, selected: (state.detailID ?? state.focusedTask?.id) == task.id,
                    metadata: state.display?.sessionMetadata[task.id], english: state.english,
                    playback: state.playback && !state.compact && visibleElements.contains(.task(task.id))
                        && task.playbackEnabled && (IslandBoardState.isRunning(task) || task.renderState.visualState == .completed),
                    effectVisible: state.display?.visible == true && state.display?.playbackEnabled == true
                        && !state.compact && visibleElements.contains(.task(task.id)) && task.playbackEnabled,
                    reduceMotion: state.reduceMotion, cardWidth: state.rowWidth,
                    onArchive: { state.onArchive?(task.id) }) { state.select(task.id) }
            } else { Color.clear.frame(height: state.rowHeight(task)) }
            if state.inlineDetail?.id == task.id {
                if visibleElements.contains(.detail(task.id)) { detailView(task) }
                else { Color.clear.frame(height: state.detailHeight) }
            }
        }.frame(height: state.rowHeight(task) + (state.inlineDetail?.id == task.id ? state.detailHeight + IslandVibeLayout.rowSpacing : 0))
    }
    private func detailView(_ task: CodexMultitaskRenderTask) -> some View {
        IslandTaskDetailView(data: state.detailData(for: task), metrics: state.detailMetrics(for: task), english: state.english,
            onClose: { state.dismissDetail() },
            onDisclosure: { state.toggleTraceDisclosure($0) },
            onHistory: { state.toggleTraceHistory() })
    }
}

/// Fixed native window + compositor-only path animation. No per-frame SwiftUI
/// resizing, view snapshots, display timer, or spring-driven window frame writes.
@MainActor
final class IslandNotchSurface: NSView {
    override var isFlipped: Bool { true }
    let confirmationGlow = ActivityIslandCompletionGlowView(frame: .zero)
    private let shell = CAShapeLayer()
    private let clipping = CAShapeLayer()
    private let content = NSView()
    private let compactHost: NSHostingView<IslandBoardView>
    private let expandedHost: NSHostingView<IslandBoardView>
    private(set) var targetRect = CGRect.zero
    private var lastCompact: Bool?
    private(set) var transitionCount = 0
    private(set) var layoutCommitCount = 0


    init(state: IslandBoardState) {
        compactHost = NSHostingView(rootView: IslandBoardView(state: state, compactContent: true))
        expandedHost = NSHostingView(rootView: IslandBoardView(state: state, compactContent: false))
        super.init(frame: .zero)
        wantsLayer = true; content.wantsLayer = true
        compactHost.wantsLayer = true; expandedHost.wantsLayer = true
        compactHost.sizingOptions = []; expandedHost.sizingOptions = []
        shell.fillColor = NSColor.black.cgColor
        shell.shadowColor = NSColor.black.cgColor
        shell.shadowOpacity = 0.26; shell.shadowRadius = 10
        shell.shadowOffset = CGSize(width: 0, height: 4)
        // Outside the content mask and behind the opaque shell: the original
        // yellow glow follows the whole island without tinting its contents.
        addSubview(confirmationGlow)
        confirmationGlow.layer?.zPosition = -1
        layer?.addSublayer(shell)
        addSubview(content); content.layer?.mask = clipping
        content.addSubview(expandedHost); content.addSubview(compactHost)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    func update(state: IslandBoardState, animated: Bool) {
        let newRect = CGRect(x: (bounds.width - state.surfaceWidth) / 2, y: 0,
                             width: state.surfaceWidth, height: state.height)
        let changed = targetRect != newRect || lastCompact != state.compact || content.frame != bounds
        let radius: CGFloat = state.compact ? 13 : 24
        let compactFrame = CGRect(x: (bounds.width - min(state.geometry.compactWidth, state.expandedWidth)) / 2,
                                  y: bounds.height - state.geometry.bandHeight,
                                  width: min(state.geometry.compactWidth, state.expandedWidth), height: state.geometry.bandHeight)
        let expandedFrame = CGRect(x: (bounds.width - state.expandedWidth) / 2,
                                   y: bounds.height - state.expandedCanvasHeight,
                                   width: state.expandedWidth, height: state.expandedCanvasHeight)
        // content is unflipped. Its hosted views are laid out once at final size.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if confirmationGlow.frame != bounds { confirmationGlow.frame = bounds }
        if content.frame != bounds { content.frame = bounds }
        if compactHost.frame != compactFrame { compactHost.frame = compactFrame; layoutCommitCount += 1 }
        if expandedHost.frame != expandedFrame { expandedHost.frame = expandedFrame; layoutCommitCount += 1 }
        CATransaction.commit()
        if !animated { cancelAnimations() }
        confirmationGlow.update(
            edgeEmphasis: state.tasks.contains { IslandBoardState.needsAttention($0) }
                ? .confirmationReminder : .none,
            reduceMotion: state.reduceMotion || state.display?.playbackEnabled != true,
            playbackVisible: state.display?.visible == true && window != nil)
        confirmationGlow.updateIslandConfirmationPulse(animated: state.playback)
        guard changed else { return }
        let oldPath = shell.presentation()?.path ?? shell.path
        let path = shapePath(rect: newRect, radius: radius)
        // Mask lives on an unflipped content layer; mirror only its geometry.
        var mirror = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        let maskPath = path.copy(using: &mirror)!
        let oldMask = clipping.presentation()?.path ?? clipping.path
        let duration = state.compact ? 0.25 : 0.38
        let sourceInset = CodexActivityIslandCompletionGlowGeometry.sourceInset
        let glowPath = shapePath(rect: newRect.insetBy(dx: sourceInset, dy: sourceInset), radius: radius - sourceInset)
        confirmationGlow.setIslandContour(glowPath.copy(using: &mirror)!,
            duration: animated && !confirmationGlow.isHidden ? duration : nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shell.path = path; shell.shadowPath = path; clipping.path = maskPath
        shell.shadowOpacity = state.compact ? 0.10 : 0.26
        shell.shadowRadius = state.compact ? 5 : 10
        CATransaction.commit()
        if animated, let oldPath, let oldMask {
            transitionCount += 1
            animate(layer: shell, key: "path", from: oldPath, to: path, duration: duration)
            animate(layer: shell, key: "shadowPath", from: oldPath, to: path, duration: duration)
            animate(layer: clipping, key: "path", from: oldMask, to: maskPath, duration: duration)
        }
        if lastCompact != state.compact {
            setContent(compactHost, visible: state.compact, animated: animated, opening: state.compact)
            setContent(expandedHost, visible: !state.compact, animated: animated, opening: !state.compact)
        }
        targetRect = newRect; lastCompact = state.compact
        compactHost.setAccessibilityHidden(!state.compact)
        expandedHost.setAccessibilityHidden(state.compact)
    }
    private func shapePath(rect: CGRect, radius: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        return IslandNotchShape(bottomRadius: radius).path(in: CGRect(origin: .zero, size: rect.size)).cgPath.copy(using: &transform)!
    }
    private func animate(layer: CALayer, key: String, from: Any, to: Any, duration: Double) {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from; animation.toValue = to; animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        layer.add(animation, forKey: key)
    }
    private func setContent(_ host: NSView, visible: Bool, animated: Bool, opening: Bool) {
        guard let layer = host.layer else { return }
        let previous = layer.presentation()?.opacity ?? layer.opacity
        let oldTransform = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = visible ? 1 : 0
        layer.transform = visible ? CATransform3DIdentity : CATransform3DMakeTranslation(0, 5, 0)
        CATransaction.commit()
        if animated {
            animate(layer: layer, key: "opacity", from: previous, to: layer.opacity, duration: visible ? 0.23 : 0.10)
            animate(layer: layer, key: "transform", from: NSValue(caTransform3D: oldTransform),
                    to: NSValue(caTransform3D: layer.transform), duration: opening ? 0.32 : 0.16)
        }
    }
    func containsSurfacePoint(_ point: CGPoint) -> Bool {
        (shell.presentation()?.path ?? shell.path)?.contains(point) ?? false
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit supplies hitTest points in the superview's coordinates. This
        // surface is flipped; using the raw point mirrors the clickable areas.
        let local = convert(point, from: superview)
        guard containsSurfacePoint(local) else { return nil }
        let host: NSView = lastCompact == true ? compactHost : expandedHost
        return host.hitTest(convert(local, to: content))
    }
    var hasActiveAnimations: Bool {
        [shell, clipping, compactHost.layer, expandedHost.layer].compactMap { $0 }
            .contains { !($0.animationKeys() ?? []).isEmpty }
            || (confirmationGlow.layer?.sublayers ?? []).contains { !($0.animationKeys() ?? []).isEmpty }
    }
    func cancelAnimations() {
        [shell, clipping, compactHost.layer, expandedHost.layer].compactMap { $0 }.forEach { $0.removeAllAnimations() }
        confirmationGlow.cancelIslandContourAnimations()
    }
    func stop() {
        cancelAnimations()
        confirmationGlow.update(edgeEmphasis: .none, reduceMotion: true, playbackVisible: false)
    }
}

private final class IslandNotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class IslandBoardController {
    let state = IslandBoardState()
    private let panel: NSPanel
    let surface: IslandNotchSurface
    private let presentsWindows: Bool
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var hoverOpen: DispatchWorkItem?
    private var hoverClose: DispatchWorkItem?
    private var transitionHitUpdate: DispatchWorkItem?
    private var pointerInside = false
    private var suppressHoverUntilExit = false
    private var lastPresentation: IslandBoardState.Presentation = .resting
    var screen: NSScreen?
    private var simulateHardwareNotch = false
    var onSelect: ((Int) -> Void)?
    var onConfirmation: ((Int, UUID, IslandConfirmationDecision) -> Void)?
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    init(presentsWindows: Bool = true) {
        self.presentsWindows = presentsWindows
        panel = IslandNotchPanel(contentRect: .init(x: 0, y: 0, width: 468, height: 352),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        surface = IslandNotchSurface(state: state)
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.canHide = false
        panel.hidesOnDeactivate = false; panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.animationBehavior = .none; panel.contentView = surface
        panel.title = "QuotaView 0.7.3 · 任务"
        panel.isExcludedFromWindowsMenu = false
        panel.acceptsMouseMovedEvents = true
        state.onSelect = { [weak self] in self?.onSelect?($0) }
        state.onConfirmation = { [weak self] id, requestID, decision in self?.onConfirmation?(id, requestID, decision) }
        state.onChange = { [weak self] in self?.refresh() }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, panel.isVisible else { return event }
            trackPointer()
            if event.type == .keyDown, event.keyCode == 53, panel.isKeyWindow, !(panel.firstResponder is NSTextView) {
                state.escape(); return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown { dismissOutside() }
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            self?.trackPointer()
            if event.type == .leftMouseDown || event.type == .rightMouseDown { self?.dismissOutside() }
        }) { monitors.append(global) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncGeometry(); self?.refresh() }
            }
    }
    deinit {
        monitors.forEach(NSEvent.removeMonitor)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        hoverOpen?.cancel(); hoverClose?.cancel(); transitionHitUpdate?.cancel()
    }
    private func syncGeometry() {
        let target = screen.flatMap { requested in NSScreen.screens.first { $0 == requested } } ?? NSScreen.main
        guard let target else { return }
        if simulateHardwareNotch {
            state.setGeometry(.simulated(in: target.frame, visibleFrame: target.visibleFrame))
            return
        }
        state.setGeometry(IslandNotchGeometry(frame: target.frame, safeTop: target.safeAreaInsets.top,
            left: target.auxiliaryTopLeftArea, right: target.auxiliaryTopRightArea, visibleFrame: target.visibleFrame))
    }
    func update(model: CodexMultitaskDisplay, reduceMotion: Bool, simulateHardwareNotch: Bool = false) {
        self.simulateHardwareNotch = simulateHardwareNotch
        syncGeometry(); state.update(model, reduceMotion: reduceMotion)
    }
    private func refresh() {
        if state.presentation == .resting && lastPresentation != .resting {
            suppressHoverUntilExit = pointerInside
            hoverOpen?.cancel(); hoverOpen = nil
        }
        let becamePinned = state.presentation == .pinned && lastPresentation != .pinned
        lastPresentation = state.presentation
        let area = state.geometry.screenFrame
        // Reserve the usable display height once, allowing confirmation content
        // to grow without resizing the native window on each request or animation frame.
        let width = state.expandedWidth + IslandVibeLayout.outerEffectInset * 2
        let height = min(area.height, state.geometry.maximumExpandedHeight + IslandVibeLayout.screenBottomClearance)
        // Anchor to the actual display edge, never the menu-bar-excluding visibleFrame.
        let next = CGRect(x: state.geometry.centerX - width / 2, y: area.maxY - height, width: width, height: height)
        let geometryChanged = panel.frame != next
        if geometryChanged { panel.setFrame(next, display: false) }
        surface.update(state: state, animated: panel.isVisible && !geometryChanged && !state.reduceMotion && state.display?.visible == true)
        if state.display?.visible == true && presentsWindows {
            if !panel.isVisible {
                panel.orderFrontRegardless()
                NSApp.addWindowsItem(panel, title: panel.title, filename: false)
            }
            if becamePinned { panel.makeKey() }
        } else {
            hoverOpen?.cancel(); hoverClose?.cancel(); hoverOpen = nil; hoverClose = nil
            pointerInside = false; suppressHoverUntilExit = false
            panel.orderOut(nil)
        }
        // Do not synthesize a hover entry on launch/resize; only real mouse events
        // drive the dwell timer. This also prevents collapse/reopen loops.
        panel.ignoresMouseEvents = !containsPointer()
        transitionHitUpdate?.cancel(); transitionHitUpdate = nil
        if panel.isVisible && !state.reduceMotion {
            // One completion check releases transparent space even when the
            // pointer stays still while the shell shrinks underneath it.
            let work = DispatchWorkItem { [weak self] in
                guard let self, panel.isVisible else { return }
                transitionHitUpdate = nil; trackPointer()
            }
            transitionHitUpdate = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40, execute: work)
        }
    }
    private func containsPointer() -> Bool {
        let point = NSEvent.mouseLocation
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        return surface.containsSurfacePoint(local)
    }
    private func trackPointer() {
        guard panel.isVisible else { return }
        let inside = containsPointer()
        panel.ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverOpen?.cancel(); hoverClose?.cancel(); hoverOpen = nil; hoverClose = nil
        if inside && state.compact && !suppressHoverUntilExit {
            let work = DispatchWorkItem { [weak self] in
                guard let self, pointerInside, panel.isVisible, !suppressHoverUntilExit else { return }
                hoverOpen = nil; state.preview()
            }
            hoverOpen = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else if !inside {
            suppressHoverUntilExit = false
            if state.presentation == .preview {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, !pointerInside, !(panel.firstResponder is NSTextView), state.approval?.request.phase.canSubmit != false else { return }
                    hoverClose = nil; state.endPreview()
                }
                hoverClose = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
            }
        }
    }
    private func dismissOutside() {
        if panel.isVisible && !containsPointer() && !state.compact { state.dismissFromOutside() }
    }
    func stop() {
        surface.stop()
        transitionHitUpdate?.cancel(); transitionHitUpdate = nil
        hoverOpen?.cancel(); hoverClose?.cancel(); hoverOpen = nil; hoverClose = nil
        if var display = state.display { display.visible = false; state.update(display, reduceMotion: state.reduceMotion) }
        panel.orderOut(nil)
        NSApp.removeWindowsItem(panel)
    }
}

// Usage stays inside the notch; charts reuse the menu's quota/cost data contracts.
// The pointer tracks the fixed 53.677 × 32 pt plane, never the transformed
// face. SwiftUI interpolates only the small visual layers; layout stays fixed.
struct IslandResetTicket: View {
    let playbackEnabled: Bool
    var size = CGSize(width: 53.6774, height: 32)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = CGSize.zero
    @State private var hovered = false
    private var scale: CGFloat { size.height / 32 }
    private var motion: CGSize { reduceMotion ? .zero : tilt }
    var body: some View {
        ZStack {
            ZStack {
                Image("IslandResetTicket").resizable().scaledToFit()
                RadialGradient(colors: [.white.opacity(hovered ? 0.28 : 0), .clear],
                    center: UnitPoint(x: 0.5 + motion.width * 0.25, y: 0.5 + motion.height * 0.25),
                    startRadius: 0, endRadius: 42 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 2.3 * scale))
                Image("IslandResetMark").resizable().scaledToFit().frame(width: 12.0973 * scale, height: 12.0805 * scale)
                    .offset(x: motion.width * 0.9 * scale, y: motion.height * 0.6 * scale)
                IslandResetTicketSweep(active: playbackEnabled)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height)
            .rotation3DEffect(.degrees(Double(-motion.height * 7)), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.degrees(Double(motion.width * 10)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .shadow(color: .black.opacity(hovered ? 0.3 : 0), radius: hovered ? 4 * min(2, scale) : 0,
                x: -motion.width * 2 * scale, y: hovered ? 3 * min(2, scale) : 0)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height).contentShape(Rectangle())
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: tilt)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                guard point.x.isFinite, point.y.isFinite else { return }
                hovered = true
                tilt = CGSize(width: min(1, max(-1, point.x / size.width * 2 - 1)),
                    height: min(1, max(-1, point.y / size.height * 2 - 1)))
            case .ended: hovered = false; tilt = .zero
            }
        }
        .onDisappear { hovered = false; tilt = .zero }
    }
}
// One compositor animation on the ticket face. No frame timer, page redraw,
// data refresh or hover dependency. Hidden/detached/reduced-motion views stop.
final class IslandResetTicketSweepHost: NSView {
    private let stripe = CAGradientLayer()
    private static let animationKey = "island.reset-ticket.sweep"
    private var enabled = false
    private var renderedSize = CGSize.zero
    var sweepAnimation: CAKeyframeAnimation? { stripe.animation(forKey: Self.animationKey) as? CAKeyframeAnimation }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true; layer?.cornerRadius = 2.3
        stripe.colors = [NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0.70).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        stripe.locations = [0, 0.3, 0.5, 0.7, 1]
        stripe.startPoint = CGPoint(x: 0, y: 0.5); stripe.endPoint = CGPoint(x: 1, y: 0.5)
        stripe.isHidden = true; layer?.addSublayer(stripe)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }
    func configure(active: Bool, reduceMotion: Bool) {
        let next = active && !reduceMotion
        guard enabled != next else { return }
        enabled = next; updateAnimation()
    }
    override func layout() {
        super.layout()
        if renderedSize != bounds.size {
            renderedSize = bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.cornerRadius = 2.3 * bounds.height / 32
            stripe.bounds = CGRect(x: 0, y: 0, width: 20 * bounds.height / 32, height: bounds.height * 3)
            stripe.position = CGPoint(x: bounds.midX, y: bounds.midY)
            stripe.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 7))
            CATransaction.commit()
            stripe.removeAnimation(forKey: Self.animationKey)
        }
        updateAnimation()
    }
    private func updateAnimation() {
        guard enabled, window != nil, bounds.width > 0, bounds.height > 0 else { stop(); return }
        CATransaction.begin(); CATransaction.setDisableActions(true); stripe.isHidden = false; CATransaction.commit()
        guard sweepAnimation == nil else { return }
        let travel = bounds.width + bounds.height
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-travel, -travel, travel, travel]
        animation.keyTimes = [0, 0.10, 0.90, 1]
        animation.timingFunctions = [.init(name: .linear), .init(name: .easeInEaseOut), .init(name: .linear)]
        animation.duration = 2; animation.repeatCount = .infinity
        animation.beginTime = stripe.convertTime(CACurrentMediaTime(), from: nil)
        stripe.add(animation, forKey: Self.animationKey)
    }
    func stop() {
        stripe.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin(); CATransaction.setDisableActions(true); stripe.isHidden = true; CATransaction.commit()
    }
}
private struct IslandResetTicketSweep: NSViewRepresentable {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> IslandResetTicketSweepHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandResetTicketSweepHost, context: Context) {
        view.configure(active: active, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: IslandResetTicketSweepHost, coordinator: ()) { view.stop() }
}

private struct IslandResetTicketButtonStyle: ButtonStyle {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : (hovered ? 0.085 : 0)),
                in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .brightness(configuration.isPressed ? -0.06 : (hovered ? 0.04 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { inside in
                let next = active && isEnabled && inside
                hovered = next
            }
            .onChange(of: active && isEnabled) { _, enabled in
                if !enabled { clearHover() }
            }
            .onDisappear { clearHover() }
    }
    private func clearHover() {
        hovered = false
    }
}

private struct IslandUsageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct IslandUsageBento: View {
    let snapshot: CurrentCodexPresentation?
    let usageState: IslandUsagePresentation.State
    let english: Bool
    let contentWidth: CGFloat
    let privacy: Bool
    let playbackEnabled: Bool
    let hidesTicket: Bool
    let onReset: () -> Void
    let onRefresh: (() async -> Void)?
    let onHeightChange: (CGFloat) -> Void
    @State private var refreshing = false
    @State private var selectedDay: Date?
    @State private var hoveredCost: Date?
    @State private var hoveredActivity: Int?
    @State private var selectedActivity: Date?
    @State private var activityMode: IslandActivityHeatmap.Mode = .daily
    private let secondary = Color(white: 0.68)
    private func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    private func tokens(_ value: Int64?) -> String { value.map { CodexActivityTokenUsageFormatter.string(for: $0) } ?? "—" }
    private func money(_ value: Double?) -> String { value.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—" }
    private var copy: AppCopy { .init(language: english ? .english : .simplifiedChinese) }
    private var chart: EstimatedCostChartModel { .init(activity: snapshot?.tokenActivity ?? [], endingAt: Date()) }
    private var quota: CodexQuotaWindowPresentation? {
        snapshot?.quotaWindows.first { $0.windowDurationMinutes == 10080 } ?? snapshot?.quotaWindows.first
    }
    private var percent: Int? { quota?.remainingPercent ?? snapshot?.remainingPercent }
    private var selectedCost: EstimatedCostChartModel.Day? { chart.days.first { $0.date == selectedDay } }
    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color(white: 0.13), lineWidth: 0.5) }
    }
    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        surface { VStack(alignment: .leading, spacing: 10) { heading(title); content() } }
    }
    private var quotaCountdown: String {
        guard let date = quota?.resetsAt ?? snapshot?.resetsAt else { return "—" }
        let hours = max(0, Int(ceil(date.timeIntervalSinceNow / 3600)))
        let days = hours / 24, remainder = hours % 24
        if days > 0 {
            return text("\(days)天\(remainder)小时后重置", "Resets in \(days)d \(remainder)h")
        }
        return text("\(hours)小时后重置", "Resets in \(hours)h")
    }
    var body: some View {
        Group {
            VStack(spacing: 10) {
                if privacy || snapshot == nil {
                    card(text("用量数据", "Usage data")) {
                        Text(privacy ? text("隐私模式已隐藏统计", "Statistics hidden in privacy mode") : usageState.message(copy: copy))
                            .font(.system(size: 14, weight: .medium))
                        Text(text("不会把缺失数据显示为零。", "Missing data is not shown as zero.")).font(.system(size: 11)).foregroundStyle(secondary)
                    }
                } else {
                    if usageState.isStale {
                        Text(copy.text("上次成功数据 · 等待刷新", "Last successful data · awaiting refresh") + " · " + usageState.message(copy: copy))
                            .font(.system(size: 10)).foregroundStyle(secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 10) {
                            quotaCard
                            HStack(spacing: 10) {
                                metric(text("最近一天 Tokens", "Latest day tokens"), value: tokens(snapshot?.recentDailyTokens))
                                metric(text("30日 Tokens", "30-day tokens"), value: tokens(chart.periodTokens))
                                metric(text("累计 Tokens", "Total tokens"), value: tokens(snapshot?.lifetimeTokens))
                            }
                        }.frame(maxWidth: .infinity)

                        // Match the left stack naturally without a second height-measurement loop.
                        Color.clear.frame(width: 204).overlay { accountCard }
                    }.fixedSize(horizontal: false, vertical: true)
                    // Elevate at the sibling-card boundary: a chart-local zIndex cannot
                    // place its tooltip above a different card's surface.
                    costCard.zIndex(hoveredCost == nil ? 0 : 1)
                    activityCard.zIndex(hoveredActivity == nil ? 0 : 1)
                }
                HStack {
                    if let date = snapshot?.lastUpdatedAt {
                        Text(text("更新于 ", "Updated ") + date.formatted(date: .omitted, time: .shortened))
                    } else { Text(text("等待数据更新", "Waiting for data")) }
                    Spacer()
                    Button {
                        guard !refreshing else { return }; refreshing = true
                        Task { await onRefresh?(); refreshing = false }
                    } label: {
                        Label(refreshing ? text("刷新中", "Refreshing") : text("刷新", "Refresh"), systemImage: "arrow.clockwise")
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Color(white: 0.10), in: Capsule())
                    }.buttonStyle(.plain).disabled(refreshing || onRefresh == nil)
                }.font(.system(size: 10)).foregroundStyle(secondary).padding(.horizontal, 4)
            }.padding(.horizontal, IslandVibeLayout.listInset).padding(.top, 10).padding(.bottom, 14)
        }.fixedSize(horizontal: false, vertical: true)
        .background { GeometryReader { proxy in Color.clear.preference(key: IslandUsageHeightKey.self, value: proxy.size.height) } }
        .onPreferenceChange(IslandUsageHeightKey.self, perform: onHeightChange)
        .foregroundStyle(.white)
    }
    private var quotaCard: some View {
        surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    heading(text("额度剩余", "Quota remaining"))
                    Spacer(minLength: 4)
                    Text(quotaCountdown).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
                }
                VStack(spacing: 9) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(percent.map { "\($0)%" } ?? "—").font(AstaSans.semiBold(21)).tracking(-0.21)
                        Spacer()
                        Text(percent.map { text("已使用 \(100 - min(100, max(0, $0)))%", "\(100 - min(100, max(0, $0)))% Used") } ?? "—")
                            .font(AstaSans.regular(10.5))
                    }
                    GeometryReader { proxy in
                        let fraction = CGFloat(min(100, max(0, percent ?? 0))) / 100
                        HStack(spacing: fraction > 0 && fraction < 1 ? 1 : 0) {
                            if fraction > 0 {
                                RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: CodexActivityQuotaRingContract.color(for: percent)))
                                    .frame(width: max(0, proxy.size.width * fraction - (fraction < 1 ? 0.5 : 0)))
                            }
                            if fraction < 1 { RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.32)) }
                        }.clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(white: 0.22), lineWidth: 0.5) }
                    }.frame(height: 8).accessibilityHidden(true)
                }
            }
        }
    }
    private var accountCard: some View {
        surface {
            VStack(alignment: .leading, spacing: 10) {
                heading(text("账户", "Account"))
                Text(snapshot.flatMap { OpenAIPlanDisplayName.resolve($0.planType) } ?? "—")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 10)
                HStack {
                    Text(text("积分余额", "Credit balance")).foregroundStyle(secondary)
                    Spacer()
                    Text(snapshot?.creditBalance ?? "—")
                }.font(.system(size: 10))
                Rectangle().fill(Color(white: 0.21)).frame(height: 0.5)
                Button(action: onReset) {
                    HStack {
                        IslandResetTicket(playbackEnabled: playbackEnabled).opacity(hidesTicket ? 0 : 1)
                            .anchorPreference(key: IslandResetTicketAnchors.self, value: .bounds) { [.usage: $0] }
                            .accessibilityHidden(true)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 7) {
                            Text(text("额度重置", "Quota reset")).foregroundStyle(secondary)
                            Text(snapshot?.availableResetCredits.map { text("\($0)次", "\($0) left") } ?? "—")
                        }.font(.system(size: 10))
                    }.contentShape(Rectangle())
                }.buttonStyle(IslandResetTicketButtonStyle(active: !hidesTicket))
                    .accessibilityLabel(copy.text("打开额度重置页面", "Open quota reset page"))
                    .accessibilityHint(text("仅展示重置演示", "Preview only"))
            }.frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        surface {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.8)
                Text(value).font(AstaSans.semiBold(21)).tracking(-0.21).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
    private var chartCellWidth: CGFloat { IslandActivityHeatmap.cellSize(width: contentWidth - 28) }
    private var costPlotWidth: CGFloat {
        CGFloat(chart.days.count) * chartCellWidth + CGFloat(max(0, chart.days.count - 1)) * IslandActivityHeatmap.gap
    }
    private var costSummaryWidth: CGFloat { max(1, (contentWidth - 28 - costPlotWidth - 28) / 2) }
    private var costCard: some View {
        surface {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    heading(text("成本估算", "Cost estimate"))
                    Text(money(chart.periodCost)).font(AstaSans.semiBold(21)).tracking(-0.21)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(text("最近30天", "Last 30 days")).font(.system(size: 10)).foregroundStyle(secondary)
                }.frame(width: costSummaryWidth, alignment: .leading)
                Color.clear.frame(width: costPlotWidth).overlay { costChart.padding(.top, 14) }.zIndex(10)
                VStack(alignment: .trailing, spacing: 10) {
                    Text(selectedCost.map { $0.date.formatted(.dateTime.month().day()) } ?? text("最近一天", "Latest day"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
                    Text(money(selectedCost != nil ? selectedCost?.estimatedCost : chart.latestCost))
                        .font(AstaSans.semiBold(21)).tracking(-0.21).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(text("估算值 · 非账单", "Estimate · not a bill"))
                        .font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(width: costSummaryWidth, alignment: .trailing)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    private var costChart: some View {
            GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: IslandActivityHeatmap.gap) {
                ForEach(chart.days) { day in
                    Button { selectedDay = selectedDay == day.date ? nil : day.date } label: {
                        RoundedRectangle(cornerRadius: min(2, chartCellWidth / 4))
                            .fill(selectedDay == day.date || hoveredCost == day.date
                                ? Color.white
                                : costBarColor(day.estimatedCost))
                            .overlay {
                                if selectedDay == day.date || hoveredCost == day.date {
                                    RoundedRectangle(cornerRadius: min(2, chartCellWidth / 4)).strokeBorder(.white, lineWidth: 1)
                                }
                            }
                            .frame(width: chartCellWidth, height: max(3, proxy.size.height * (day.estimatedCost ?? 0) / max(0.001, chart.maximumCost)))
                            .frame(height: proxy.size.height, alignment: .bottom).contentShape(Rectangle())
                    }.buttonStyle(.plain).onHover { inside in
                        if inside { hoveredCost = day.date }
                        else if hoveredCost == day.date { hoveredCost = nil }
                    }.accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted) + ": " + money(day.estimatedCost))
                }
            }.overlay(alignment: .topLeading) {
                if let index = chart.days.firstIndex(where: { $0.date == hoveredCost }) {
                    let day = chart.days[index]
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.date.formatted(.dateTime.year().month().day()))
                        Text(money(day.estimatedCost) + text(" · 估算值", " · estimated"))
                        Text(tokens(day.tokens) + " Tokens")
                    }.font(.system(size: 11)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 8).frame(width: 214, alignment: .leading)
                        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.23), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                        .offset(x: min(max(0, CGFloat(index) * (chartCellWidth + IslandActivityHeatmap.gap) + chartCellWidth / 2 - 107), max(0, proxy.size.width - 214)), y: -78)
                        .allowsHitTesting(false)
                }
            }.zIndex(10)
            }
    }
    private var activityCard: some View {
        let grid = IslandActivityHeatmap(activity: snapshot?.tokenActivity ?? [], endingAt: Date(), mode: activityMode, lifetimeTokens: snapshot?.lifetimeTokens)
        return surface {
            VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                heading(text("Token 活动", "Token activity"))
                if let cell = grid.cells.first(where: { $0.date == selectedActivity }) {
                    Text(cell.date.formatted(.dateTime.month().day()) + " · " + tokens(cell.tokens))
                        .font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                ForEach(IslandActivityHeatmap.Mode.allCases, id: \.self) { mode in
                    Button { activityMode = mode; selectedActivity = nil; hoveredActivity = nil } label: {
                        Text(activityLabel(mode)).font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .foregroundStyle(activityMode == mode ? .white : secondary)
                    }.buttonStyle(.plain)
                }
            }
            GeometryReader { proxy in
                let size = IslandActivityHeatmap.cellSize(width: proxy.size.width)
                let gap = IslandActivityHeatmap.gap
                let pitch = size + gap
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<53, id: \.self) { column in
                            VStack(spacing: gap) {
                                ForEach(0..<grid.rows, id: \.self) { row in
                                    let index = grid.cellIndex(column: column, row: row)
                                    let cell = grid.cells[index]
                                    Button { selectedActivity = cell.date } label: {
                                        RoundedRectangle(cornerRadius: min(2, size / 4))
                                            .fill(activityMode == .daily ? heatColor(cell.tokens, maximum: grid.maximum) : (grid.isFilled(column: column, row: row) ? (hoveredActivity == index || cell.date == selectedActivity ? Color(red: 0.39, green: 0.71, blue: 1) : Color(red: 0.02, green: 0.53, blue: 0.92)) : Color(white: 0.13)))
                                            .frame(width: size, height: size)
                                            .overlay { if activityMode == .daily && (cell.date == selectedActivity || hoveredActivity == index) { RoundedRectangle(cornerRadius: 2).strokeBorder(.white, lineWidth: 1) } }
                                    }.buttonStyle(.plain).disabled(cell.future)
                                        .onHover { inside in
                                            if inside && !cell.future { hoveredActivity = index }
                                            else if hoveredActivity == index { hoveredActivity = nil }
                                        }
                                        .opacity(cell.future ? 0 : 1)
                                        .accessibilityLabel(cell.date.formatted(date: .abbreviated, time: .omitted) + ": " + tokens(cell.tokens))
                                }
                            }
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        ForEach(grid.months, id: \.column) { month in
                            Text(month.date.formatted(english ? .dateTime.month(.abbreviated) : .dateTime.month()))
                                .font(.system(size: 9)).foregroundStyle(secondary)
                                .fixedSize().offset(x: min(CGFloat(month.column) * pitch, max(0, proxy.size.width - 25)))
                        }
                    }.frame(height: 13)
                }
                .overlay(alignment: .topLeading) {
                    if let index = hoveredActivity, grid.cells.indices.contains(index) {
                        let cell = grid.cells[index]
                        let column = activityMode == .daily ? index / 7 : index
                        let row = activityMode == .daily ? index % 7 : 0
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activityDate(cell.date))
                            Text(activityTokens(cell.tokens))
                        }.font(.system(size: 11)).foregroundStyle(.white)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .frame(width: 214, alignment: .leading)
                            .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.23), lineWidth: 1) }
                            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                            .offset(x: min(max(0, CGFloat(column) * pitch + size / 2 - 107), max(0, proxy.size.width - 214)),
                                    y: CGFloat(row) * pitch - 58)
                            .allowsHitTesting(false)
                    }
                }.zIndex(10)
            }.frame(height: IslandActivityHeatmap.chartHeight(width: contentWidth - 28))
            }
        }
    }
    private func activityDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: english ? "en_US" : "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = english ? "MMM d, yyyy" : "yyyy年M月d日"
        let label = formatter.string(from: date)
        switch activityMode {
        case .daily: return label
        case .weekly: return label + text(" 起的一周", " · week starting")
        case .cumulative: return text("累计至 ", "Total through ") + label + text(" 起的一周", " · week starting")
        }
    }
    private func activityTokens(_ value: Int64?) -> String {
        guard let value else { return text("暂无数据", "No data") }
        let label: String
        if !english && value >= 100_000_000 { label = String(format: "%.1f亿", Double(value) / 100_000_000) }
        else if !english && value >= 10_000 { label = String(format: "%.1f万", Double(value) / 10_000) }
        else { label = value.formatted() }
        return label + text(" 个 Token", " tokens")
    }
    private func costBarColor(_ value: Double?) -> Color {
        guard let value, value > 0 else { return Color(white: 0.18) }
        let level = value / max(0.001, chart.maximumCost)
        return Color(white: level < 0.25 ? 0.35 : level < 0.5 ? 0.48 : level < 0.75 ? 0.62 : 0.76)
    }
    private func heatColor(_ value: Int64?, maximum: Int64) -> Color {
        guard let value, value > 0 else { return Color(white: 0.18) }
        let level = Double(value) / Double(max(1, maximum))
        if level < 0.25 { return Color(red: 0.02, green: 0.23, blue: 0.40) }
        if level < 0.5 { return Color(red: 0.02, green: 0.35, blue: 0.61) }
        if level < 0.75 { return Color(red: 0.02, green: 0.53, blue: 0.92) }
        return Color(red: 0.39, green: 0.71, blue: 1)
    }
    private func activityLabel(_ mode: IslandActivityHeatmap.Mode) -> String {
        switch mode {
        case .daily: text("每天", "Daily")
        case .weekly: text("每周", "Weekly")
        case .cumulative: text("累计总量", "Cumulative")
        }
    }
}

struct IslandActivityHeatmap {
    enum Mode: CaseIterable { case daily, weekly, cumulative }
    struct Cell { let date: Date; let tokens: Int64?; let future: Bool }
    struct Month { let column: Int; let date: Date }
    static let gap: CGFloat = 3
    static func cellSize(width: CGFloat) -> CGFloat { max(1, (width - gap * 52) / 53) }
    static func chartHeight(width: CGFloat) -> CGFloat { cellSize(width: width) * 7 + gap * 6 + 21 }
    let cells: [Cell]
    let months: [Month]
    let maximum: Int64
    let rows = 7
    let mode: Mode
    func cellIndex(column: Int, row: Int) -> Int { mode == .daily ? column * 7 + row : column }
    func isFilled(column: Int, row: Int) -> Bool {
        guard let value = cells[cellIndex(column: column, row: row)].tokens, value > 0, maximum > 0 else { return false }
        let count = max(1, min(7, Int(ceil(Double(value) / Double(maximum) * 7))))
        return row >= 7 - count
    }
    init(activity: [DailyTokenActivity], endingAt: Date, mode: Mode, lifetimeTokens: Int64? = nil) {
        self.mode = mode
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: endingAt)
        let weekStart = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today) - 1), to: today)!
        let start = calendar.date(byAdding: .day, value: -52 * 7, to: weekStart)!
        var values: [Date: Int64] = [:]
        for item in activity where item.tokens >= 0 { values[calendar.startOfDay(for: item.date)] = item.tokens }
        func sum(_ values: [Int64]) -> Int64 {
            values.reduce(0) { result, value in
                let added = result.addingReportingOverflow(value)
                return added.overflow ? Int64.max : added.partialValue
            }
        }
        var daily: [Cell] = []
        for index in 0..<371 {
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            daily.append(.init(date: date, tokens: date > today ? nil : values[date], future: date > today))
        }
        if mode == .daily { cells = daily }
        else {
            // Carry pre-window usage into the cumulative series; never add daily cumulative values together.
            let windowTotal = sum(daily.compactMap(\.tokens))
            let earlier = values.filter { $0.key < start }.map(\.value)
            var running = lifetimeTokens.map { max(0, $0 - windowTotal) } ?? sum(earlier)
            var hasData = running > 0 || !earlier.isEmpty
            cells = (0..<53).map { column in
                let week = Array(daily[(column * 7)..<(column * 7 + 7)])
                let known = week.compactMap(\.tokens)
                let total = sum(known)
                if !known.isEmpty { hasData = true }
                running = sum([running, total])
                return .init(date: week[0].date,
                    tokens: mode == .weekly ? (known.isEmpty ? nil : total) : (hasData ? running : nil),
                    future: false)
            }
        }
        maximum = cells.compactMap(\.tokens).max() ?? 0
        var labels: [Month] = []
        for column in 0..<53 {
            let date = daily[column * 7].date
            if column == 0 || calendar.component(.month, from: date) != calendar.component(.month, from: daily[(column - 1) * 7].date) {
                if let last = labels.last, column - last.column < 3 { labels.removeLast() }
                labels.append(.init(column: column, date: date))
            }
        }
        months = labels
    }
}
