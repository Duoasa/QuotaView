import AppKit
import SwiftUI
import QuotaViewCore

private struct IslandBoardTaskRow: View {
    @Environment(\.appLanguage) private var appLanguage
    let progressEffect: AppPreferences.CodexActivityProgressEffect
    let task: CodexMultitaskRenderTask
    let selected: Bool
    let metadata: IslandSessionMetadata?
    let english: Bool
    let playback: Bool
    let effectVisible: Bool
    let reduceMotion: Bool
    let subagentsVisible: Bool
    var cardWidth: CGFloat = 656
    let onArchive: () -> Void
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            IslandTaskCard(progressEffect: progressEffect, task: task, selected: selected, metadata: metadata, english: english,
                playback: playback, effectVisible: effectVisible, reduceMotion: reduceMotion,
                subagentsVisible: subagentsVisible, hovered: hovered, showsArchiveButton: true, cardWidth: cardWidth)
        }.buttonStyle(.plain)
            .overlay(alignment: Alignment(horizontal: .trailing, vertical: .islandTaskHeader)) {
                // Sibling hit target: archive must never also select/open the card.
                IslandTaskArchiveButton(english: english, showsArchiveIcon: hovered, provider: task.provider, action: onArchive)
                    .padding(.trailing, IslandVibeLayout.contentInset)
                    .alignmentGuide(.islandTaskHeader) { $0[VerticalAlignment.center] }
            }
            .accessibilityValue(selected ? AppCopy(language: appLanguage ?? (english ? .english : .simplifiedChinese)).text("详情已展开", "Details open") : "")
            .contentShape(IslandVibeLayout.rowShape)
            .onHover { hovered = $0 }
    }
}

// Both hosts keep their final layout throughout a transition. The AppKit surface
// animates only the shell path, mask, opacity and a small content translation.
struct IslandBoardView: View {
    @ObservedObject var state: IslandBoardState
    let compactContent: Bool
    @State private var visibility = IslandListVisibility()
    private var visibleElements: Set<IslandListElement> { visibility.visible }
    private var scrollLink: IslandTaskScrollLink { state.taskScrollLink }
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
                            onDismiss: { state.onDismissConfirmation?(approval.task.id, approval.request.id) },
                            showsLocalDismiss: approval.request.canDismissLocally,
                            onArchive: { state.onArchive?(approval.task.id) },
                            progressEffect: state.display?.effect ?? .dropField, utilities: IslandUtilityActions(state: state))
                            .id(approval.request.id)
                    } else {
                        Group {
                            let layout = IslandTaskListLayout(taskIDs: state.visibleTasks.map(\.id),
                                detailID: state.inlineDetail?.id, detailHeight: state.detailHeight, rowHeights: state.rowHeights)
                            let residents = visibility.residentTaskIDs.union(
                                scrollLink.transitionResidents(layout: layout, viewport: state.listHeight))
                            ScrollView(.vertical) {
                                // A variable-height detail makes LazyVStack estimate offscreen rows
                                // incorrectly. Exact row slots keep rail/visibility geometry deterministic;
                                // viewport/nearby content stays mounted, with offscreen playback stopped.
                                VStack(spacing: IslandVibeLayout.rowSpacing) {
                                    ForEach(state.visibleTasks, id: \.id) { task in
                                        taskGroup(task, residentTaskIDs: residents).id(task.id)
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
                                        layout: layout,
                                        active: !state.compact && state.display?.visible == true,
                                            onVisibilityChange: { visibility = $0 }, link: scrollLink, viewportHeight: state.listHeight))
                            }.scrollIndicators(.never)
                            .frame(height: state.listHeight)
                            .overlay {
                                IslandTaskEdgeOverlay(link: scrollLink)
                                    .padding(.leading, IslandVibeLayout.listInset)
                                    .padding(.trailing, state.showsScrollRail
                                        ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                            .overlay(alignment: .trailing) {
                                if state.showsScrollRail {
                                    IslandTaskScrollRailView(link: scrollLink, label: state.text("任务滚动条", "Task scrollbar"))
                                        .frame(width: IslandVibeLayout.scrollRailWidth, height: state.listHeight - IslandVibeLayout.rowSpacing)
                                        .padding(.trailing, IslandVibeLayout.scrollRailTrailingInset)
                                        .padding(.bottom, IslandVibeLayout.rowSpacing)
                                }
                            }
                            // Target rows are mounted in this body; native layout
                            // restores the anchor before visibility and drawing commit.
                        }
                        IslandChromeFooter {
                            HStack(spacing: 12) {
                                HStack(spacing: 5) {
                                    Text(state.text("\(state.visibleTasks.count) 个会话", "\(state.visibleTasks.count) sessions"))
                                    if state.showsScrollRail { Image(systemName: "arrow.up.arrow.down") }
                                }
                                if let memory = state.memoryActivity {
                                    HStack(spacing: 5) {
                                        IslandSmallActivityOrb(visualState: .compactingContext,
                                            playback: state.playback && !state.compact)
                                        Text(state.text("记忆整理", "Memory consolidation"))
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .help(memory.label(english: state.english, language: state.language))
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(memory.label(english: state.english, language: state.language))
                                }
                            }.lineLimit(1)
                        } trailing: {
                            Text(footerStatus).lineLimit(1).truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                                .accessibilityHint(footerStatus)
                            IslandUtilityActions(state: state)
                        }
                    }
                }
            }
        }
        .task(id: compactContent ? nil : state.selectedConversation) {
            guard !compactContent else { return }
            let target = state.selectedConversation
            state.availableConversation = nil
            guard let target else { return }
            repeat {
                let resolved = await IslandConversationNavigation.resolve(target)
                guard !Task.isCancelled, state.selectedConversation == target else { return }
                if let resolved {
                    if state.availableConversation?.target != resolved { state.availableConversation = (target, resolved) }
                } else if state.availableConversation != nil { state.availableConversation = nil }
                guard target.needsRecheck(after: resolved) else { return }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            } while !Task.isCancelled
        }
        .environment(\.appLanguage, state.language)
        .environment(\.locale, Locale(identifier: state.language.localeIdentifier))
        .environment(\.islandGlassActive, !state.compact)
        .environment(\.islandLiquidGlassEnabled, state.display?.islandMaterial != .classic)
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
        .modifier(IslandGlassAppearanceContext(appearance: state.display?.islandGlassAppearance ?? .dark,
            material: state.display?.islandMaterial ?? .liquidGlass))
        .transaction { $0.animation = nil }
        .accessibilityHidden(compactContent ? !state.compact : state.compact)
    }
    private var usageFlow: some View {
        ZStack(alignment: .top) {
            IslandUsageBento(snapshot: state.display?.usageSnapshot, usageState: state.display?.usageState ?? .loading, english: state.english,
                contentWidth: state.expandedWidth - IslandVibeLayout.listInset * 2,
                options: state.display?.usageOptions ?? .init(),
                privacy: state.display?.privacyMode == true,
                playbackEnabled: !state.compact && state.playback && !state.showsReset && !state.resetTransitionInFlight,
                hidesTicket: state.resetTransitionInFlight, onReset: state.openReset,
                utilities: IslandUtilityActions(state: state), maximumHeight: state.maximumPageHeight, onHeightChange: state.updateUsageHeight,
                claudeUsage: state.display?.claudeUsage, antigravityUsage: state.display?.antigravityUsage, agentQuotas: state.display?.agentQuotas ?? [:], provider: $state.usageProvider)
                .frame(width: state.expandedWidth, height: min(state.usageHeight, state.maximumPageHeight), alignment: .top)
                .environment(\.islandGlassActive, !state.compact && !state.showsReset)
                .opacity(state.showsReset ? 0 : 1)
                .animation(state.reduceMotion ? nil : .easeOut(duration: 0.22), value: state.showsReset)
                .allowsHitTesting(!state.showsReset && !state.resetTransitionInFlight)
                .accessibilityHidden(state.showsReset)
            IslandResetPage(data: .init(snapshot: state.display?.privacyMode == true ? nil
                    : state.effectiveUsageProvider == .claudeCode ? state.display?.claudeUsage?.presentation : state.display?.usageSnapshot),
                usageState: state.effectiveUsageProvider == .claudeCode ? .current : state.display?.usageState ?? .loading,
                english: state.english, playbackEnabled: !state.compact && state.playback && state.showsReset && !state.resetTransitionInFlight,
                hidesTicket: state.resetTransitionInFlight, utilities: IslandUtilityActions(state: state), maximumHeight: state.maximumPageHeight, onHeightChange: state.updateResetHeight,
                provider: state.effectiveUsageProvider, resetController: state.resetController,
                ticketIsEmptyOverride: state.resetTicketIsEmpty,
                isPresented: state.showsReset && !state.compact && !state.resetTransitionInFlight)
                .frame(width: state.resetWidth, height: min(state.resetHeight, state.maximumPageHeight), alignment: .top)
                .environment(\.islandGlassActive, !state.compact && state.showsReset)
                .opacity(state.showsReset ? 1 : 0)
                .animation(state.reduceMotion ? nil : .easeOut(duration: 0.24), value: state.showsReset)
                .allowsHitTesting(state.showsReset && !state.resetTransitionInFlight)
                .accessibilityHidden(!state.showsReset)
        }.frame(width: state.expandedWidth, height: min(max(state.usageHeight, state.resetHeight), state.maximumPageHeight), alignment: .top)
            .overlayPreferenceValue(IslandResetTicketAnchors.self) { anchors in
                GeometryReader { proxy in
                    // Keep the host mounted even while preferences are settling.
                    IslandResetTicketFlightView(serial: state.resetTransitionSerial, toReset: state.showsReset,
                        active: state.resetTransitionInFlight && !state.compact && state.display?.visible != false,
                        source: anchors[.usage].map { proxy[$0] } ?? .zero,
                        destination: anchors[.reset].map { proxy[$0] } ?? .zero,
                        reduceMotion: state.reduceMotion, provider: state.effectiveUsageProvider,
                        isEmpty: state.resetTicketIsEmpty, onStart: state.didStartResetTransition, onCompletion: state.finishResetTransition)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    if let controller = state.resetController {
                        IslandResetDustOverlay(controller: controller,
                            cardRect: anchors[.reset].map { proxy[$0] } ?? .zero,
                            playbackEnabled: state.showsReset && !state.compact && state.playback
                                && state.effectiveUsageProvider == .codex && !state.resetTransitionInFlight,
                            reduceMotion: state.reduceMotion)
                    }
                }
            }
    }
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if state.showsUsage {
                    Button { state.showsReset ? state.closeReset() : state.closeUsage() } label: {
                        Label { Text(state.showsReset ? state.text("返回", "Back") : state.text("返回任务", "Tasks")) } icon: { Image(systemName: "chevron.left").font(IslandChromeMetrics.iconFont) }
                            .font(IslandChromeMetrics.navigationFont).foregroundStyle(.white)
                            .padding(.horizontal, IslandChromeMetrics.labelInset).frame(height: IslandChromeMetrics.buttonSize).contentShape(Capsule())
                    }.buttonStyle(IslandUtilityButtonStyle())
                    if !state.showsReset {
                        Text(state.text("用量统计", "Usage")).font(IslandChromeMetrics.navigationFont).foregroundStyle(IslandBoardStyle.muted)
                    }
                } else if state.approval != nil {
                    Circle().fill(IslandBoardStyle.confirmationHighlight).frame(width: 4, height: 4)
                    Text(state.text("待确认", "Pending request")).font(IslandChromeMetrics.font)
                        .foregroundStyle(IslandBoardStyle.confirmationHighlight)
                } else {
                    Button { state.openUsage() } label: {
                        quotaSummary.padding(.leading, IslandChromeMetrics.quotaRingLeadingInset)
                            .padding(.trailing, IslandChromeMetrics.labelInset)
                            .frame(height: IslandChromeMetrics.buttonSize).contentShape(Capsule())
                    }.buttonStyle(IslandUtilityButtonStyle()).accessibilityLabel(state.text("查看用量统计", "View usage"))
                }
                Spacer(minLength: 0)
            }.frame(width: state.geometry.hasCamera ? state.headerSideWidth : nil)
                .frame(maxWidth: .infinity).clipped()
            if state.geometry.hasCamera { Color.clear.frame(width: state.geometry.cameraWidth + 16) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let approval = state.approval {
                    if approval.request.queueCount > 1 {
                        Button { state.onNextRequest?(approval.task.id) } label: {
                            Text("\(approval.request.queueIndex)/\(approval.request.queueCount) →")
                                .padding(.horizontal, IslandChromeMetrics.labelInset).frame(height: IslandChromeMetrics.buttonSize)
                        }.buttonStyle(IslandUtilityButtonStyle()).accessibilityHint(state.text("下一项待处理请求", "Next pending request"))
                    }
                    Button { state.dismissDetail() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(IslandChromeMetrics.iconFont)
                            Text(state.text("返回列表", "Back to sessions")).font(IslandChromeMetrics.font)
                        }.padding(.horizontal, IslandChromeMetrics.labelInset).frame(height: IslandChromeMetrics.buttonSize).contentShape(Capsule())
                    }.buttonStyle(IslandUtilityButtonStyle()).accessibilityHint(state.text("返回列表，请求保持待确认", "Return to sessions; keep the request pending"))
                } else {
                    if state.attentionCount > 0 && !state.showsUsage {
                        Button { state.toggleAttention() } label: {
                            attentionIndicators(showCounts: true)
                                .font(IslandChromeMetrics.font)
                                .padding(.horizontal, IslandChromeMetrics.labelInset).frame(height: IslandChromeMetrics.buttonSize).contentShape(Capsule())
                        }.buttonStyle(IslandUtilityButtonStyle()).accessibilityHint(state.text("筛选待处理会话", "Filter sessions needing attention"))
                            .accessibilityValue(state.attentionOnly ? state.text("已筛选", "Filtered") : state.text("全部会话", "All sessions"))
                    }
                    Button { state.presentation == .pinned ? state.collapse() : state.pin() } label: {
                        Image(systemName: state.presentation == .pinned ? "pin.fill" : "pin").font(IslandChromeMetrics.iconFont)
                            .frame(width: IslandChromeMetrics.buttonSize, height: IslandChromeMetrics.buttonSize).contentShape(Rectangle())
                    }.buttonStyle(IslandUtilityButtonStyle()).accessibilityHint(state.text("固定展开；再次点击收起", "Pin open; click again to collapse"))
                }
                Button { state.collapse() } label: {
                    Image(systemName: "chevron.up").font(IslandChromeMetrics.iconFont).frame(width: IslandChromeMetrics.buttonSize, height: IslandChromeMetrics.buttonSize).contentShape(Rectangle())
                }.buttonStyle(IslandUtilityButtonStyle()).accessibilityHint(state.text("收起灵动岛", "Collapse island"))
            }.font(IslandChromeMetrics.font).foregroundStyle(IslandBoardStyle.muted)
                .frame(width: state.geometry.hasCamera ? state.headerSideWidth : nil)
                .frame(maxWidth: .infinity)
                .clipped()
        }.padding(.horizontal, IslandChromeMetrics.horizontalInset).font(IslandChromeMetrics.font).frame(width: state.surfaceWidth, height: state.headerHeight)
    }
    private var quotaSummary: some View {
        HStack(spacing: 6) {
            IslandQuotaRing(remainingPercent: state.display?.remainingPercent).fixedSize()
            Text(state.quota).font(IslandChromeMetrics.font).monospacedDigit().foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
        }.help(state.quota)
    }
    private var compactQuotaPercent: some View {
        Text(state.quotaPercent).font(IslandChromeMetrics.font).monospacedDigit().foregroundStyle(.white)
            .lineLimit(1).help(state.quotaPercent)
    }
    @ViewBuilder private var compactLeading: some View {
        if state.showsCompactQuota { compactQuotaPercent }
        else { compactActivitySymbol }
    }
    @ViewBuilder private var compactActivitySymbol: some View {
        compactOrb
    }
    private var compactOrb: some View {
        IslandSmallActivityOrb(visualState: state.focusedTask?.renderState.visualState ?? .standby,
            playback: state.playback && state.compact && state.focusedTask.map(IslandBoardState.playsOrb) == true)
            .frame(width: 30).accessibilityHidden(true)
    }
    private var compactStatistics: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .trailing) {
                // Reserve both labels so switching cannot move the task text.
                Text(state.text("\(state.tasks.count) 会话", "\(state.tasks.count) sessions")).hidden()
                Text(state.text("\(state.completedCount) 完成", "\(state.completedCount) done")).hidden()
                Text(state.showsCompletedStatistic && state.completedCount > 0
                    ? state.text("\(state.completedCount) 完成", "\(state.completedCount) done")
                    : state.text("\(state.tasks.count) 会话", "\(state.tasks.count) sessions"))
            }.foregroundStyle(IslandBoardStyle.muted)
            attentionIndicators(showCounts: false)
        }.font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
            .frame(minWidth: 30, alignment: .trailing)
    }
    private var compactText: some View {
        IslandScrollingText(text: state.compactTaskText,
            font: .systemFont(ofSize: 12, weight: .semibold),
            visible: state.playback && state.compact, reduceMotion: state.reduceMotion)
    }
    private var compact: some View {
        Button { state.preview() } label: {
            Group {
                if state.geometry.hasCamera {
                    HStack(spacing: 0) {
                        Group {
                            if state.showsCompactQuota {
                                compactQuotaPercent.frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                HStack(spacing: 10) {
                                    compactActivitySymbol
                                    compactText.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.frame(width: state.compactSideWidth).frame(maxWidth: .infinity).clipped()
                        Color.clear.frame(width: state.geometry.cameraWidth + 16)
                        HStack(spacing: 6) {
                            if state.showsCompactQuota {
                                compactText.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            }
                            compactStatistics
                        }.frame(width: state.compactSideWidth, alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing).clipped()
                    }
                } else {
                    IslandCompactContentLayout {
                        compactLeading
                        compactText
                        compactStatistics
                    }
                }
            }.padding(.horizontal, 20).frame(height: state.geometry.bandHeight)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityHint(state.text("悬停或点击展开会话详情", "Hover or click to expand session details"))
            .accessibilityLabel("\(state.summary), \(state.showsCompactQuota ? state.quotaPercent : state.quota)")
            .accessibilityValue(state.attentionCount > 0
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
        state.tasks.isEmpty ? state.summary : state.statusCounts.map { "\($0.count) \($0.title)" }.joined(separator: " · ")
    }
    private func taskGroup(_ task: CodexMultitaskRenderTask, residentTaskIDs: Set<Int>) -> some View {
        let layout = IslandTaskListLayout(taskIDs: state.visibleTasks.map(\.id),
            detailID: state.inlineDetail?.id, detailHeight: state.detailHeight, rowHeights: state.rowHeights)
        let origin = layout.offset(for: .init(element: .task(task.id), inset: 0)) ?? 0
        return VStack(spacing: IslandVibeLayout.rowSpacing) {
            if residentTaskIDs.contains(task.id) {
                IslandBoardTaskRow(progressEffect: state.display?.effect ?? .dropField, task: task, selected: (state.detailID ?? state.focusedTask?.id) == task.id,
                    metadata: state.display?.sessionMetadata[task.id], english: state.english,
                    playback: state.playback && !state.compact && visibleElements.contains(.task(task.id))
                        && IslandBoardState.playsOrb(task),
                    effectVisible: state.display?.visible == true && state.display?.playbackEnabled == true
                        && !state.compact && visibleElements.contains(.task(task.id)) && task.playbackEnabled,
                    reduceMotion: state.reduceMotion,
                    subagentsVisible: state.playback && !state.compact && visibleElements.contains(.task(task.id)), cardWidth: state.rowWidth,
                    onArchive: { state.archiveTask(task.id) }) { state.select(task.id) }
                    .modifier(IslandCardBottomFade(link: scrollLink, origin: origin, height: state.rowHeight(task)))
            } else { Color.clear.frame(height: state.rowHeight(task)) }
            if state.inlineDetail?.id == task.id {
                if residentTaskIDs.contains(task.id) {
                    detailView(task)
                        .modifier(IslandCardBottomFade(link: scrollLink,
                            origin: origin + state.rowHeight(task) + IslandVibeLayout.rowSpacing,
                            height: state.detailHeight))
                }
                else { Color.clear.frame(height: state.detailHeight) }
            }
        }.frame(height: state.rowHeight(task) + (state.inlineDetail?.id == task.id ? state.detailHeight + IslandVibeLayout.rowSpacing : 0))
    }
    private func detailView(_ task: CodexMultitaskRenderTask) -> some View {
        IslandTaskDetailView(data: state.detailData(for: task), metrics: state.detailMetrics(for: task), english: state.english,
            onClose: { state.dismissDetail() },
            onDisclosure: { state.toggleTraceDisclosure($0) })
    }
}
