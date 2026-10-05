import AppKit
import SwiftUI

enum IslandTaskTextMetrics {
    static func height(_ text: String, size: CGFloat = 11, semibold: Bool = false,
                       code: Bool = false, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 2
        let font = code ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
        let rect = (text as NSString).boundingRect(with: CGSize(width: max(40, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph])
        return max(18, ceil(rect.height) + 2)
    }
    static func limitedHeight(_ text: String, lines: Int, size: CGFloat = 11,
                              semibold: Bool = false, code: Bool = false, width: CGFloat) -> CGFloat {
        let font = code ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
        let limit = ceil(font.ascender - font.descender + font.leading) * CGFloat(lines)
            + CGFloat(max(0, lines - 1)) * 2 + 2
        return min(height(text, size: size, semibold: semibold, code: code, width: width), max(18, limit))
    }
}

struct IslandApprovalDecisionOption: Identifiable {
    let action: IslandApprovalAction
    let title: IslandDetailText
    let detail: IslandDetailText
    var id: String { action.id }
    var isRule: Bool { action.result["decision"].object != nil }
}

enum IslandApprovalDecisionChoices {
    static func options(_ request: IslandCodexApprovalRequest) -> [IslandApprovalDecisionOption] {
        request.actions.compactMap { action in
            let decision = action.result["decision"]
            switch decision.text {
            case "accept": return .init(action: action, title: .init("仅一次", "Once"), detail: .init("下次仍需确认", "Ask again next time"))
            case "acceptForSession": return .init(action: action, title: .init("本会话", "This session"), detail: .init("本次批准在会话内有效", "This approval lasts for the session"))
            default:
                if let rule = decision["acceptWithExecpolicyAmendment"].object {
                    let prefix = rule["execpolicy_amendment"]?.array.map(\.text).joined(separator: " ") ?? ""
                    return .init(action: action, title: .init("允许并记住命令规则", "Allow and remember command rule"), detail: .init(prefix))
                }
                let rule = decision["applyNetworkPolicyAmendment"]["network_policy_amendment"]
                if rule.object != nil {
                    return .init(action: action, title: rule["action"].text == "allow"
                        ? .init("允许并记住此域名", "Allow and remember this host") : .init("阻止并记住此域名", "Block and remember this host"),
                        detail: .init(rule["host"].text))
                }
                return nil
            }
        }
    }
    static func selected(_ request: IslandCodexApprovalRequest, id: String?) -> IslandApprovalDecisionOption? {
        let options = options(request)
        return options.first { $0.id == id } ?? options.first { $0.action.result["decision"].text == "accept" }
    }
    static func optionHeight(_ option: IslandApprovalDecisionOption, width: CGFloat, english: Bool) -> CGFloat {
        IslandTaskTextMetrics.limitedHeight(option.title.value(english), lines: 2, size: 12, semibold: true, width: width - 54)
            + 4 + IslandTaskTextMetrics.limitedHeight(option.detail.value(english), lines: 2, size: 11, code: option.isRule, width: width - 54) + 20
    }
    static func height(_ request: IslandCodexApprovalRequest, width: CGFloat, english: Bool) -> CGFloat {
        let options = options(request)
        guard options.count > 1 else { return 0 }
        let scopes = options.filter { !$0.isRule }, rules = options.filter(\.isRule)
        let scopeWidth = (width - CGFloat(max(0, scopes.count - 1)) * 8) / CGFloat(max(1, scopes.count))
        let scopeHeight = scopes.map { optionHeight($0, width: scopeWidth, english: english) }.max() ?? 0
        return 24 + (scopes.isEmpty ? 0 : scopeHeight + 8)
            + rules.reduce(0) { $0 + optionHeight($1, width: width, english: english) + 8 } - 8
    }
}

struct IslandApprovalMetrics {
    static let maximumContentViewport: CGFloat = 440
    static let gap: CGFloat = 12
    static let inset: CGFloat = 12
    static let buttonHeight: CGFloat = 42
    static let inputHeight: CGFloat = 36
    static let footerHeight: CGFloat = IslandChromeMetrics.footerHeight
    static var fixedHeight: CGFloat { gap + 1 + gap + buttonHeight + 8 + footerHeight }
    let maximumViewportHeight: CGFloat
    let questionHeight: CGFloat
    let impactHeight: CGFloat
    let failureHeight: CGFloat
    let controlsHeight: CGFloat
    let decisionsHeight: CGFloat
    let contentHeight: CGFloat
    let contentWidth: CGFloat
    var viewportHeight: CGFloat { min(contentHeight, maximumViewportHeight) }
    var showsRail: Bool { contentHeight > maximumViewportHeight }
    var height: CGFloat { viewportHeight + Self.fixedHeight }

    static func optionHeight(_ label: String, description: String, width: CGFloat) -> CGFloat {
        IslandTaskTextMetrics.limitedHeight(label, lines: 2, size: 12, semibold: true, width: width - 54)
            + (description.isEmpty ? 0 : IslandTaskTextMetrics.limitedHeight(description, lines: 2, width: width - 54) + 4) + 20
    }
    static let questionNumberSize: CGFloat = 24
    static let questionHeadingGap: CGFloat = 10
    static func questionTextWidth(_ width: CGFloat) -> CGFloat { max(40, width - questionNumberSize - questionHeadingGap) }
    static func questionTitleRowHeight(_ question: IslandApprovalQuestion, width: CGFloat) -> CGFloat {
        max(questionNumberSize, IslandTaskTextMetrics.height(question.title, size: 13, semibold: true,
            width: questionTextWidth(width)))
    }
    static func questionHeaderLabelHeight(_ question: IslandApprovalQuestion, width: CGFloat) -> CGFloat {
        question.header.isEmpty ? 0 : IslandTaskTextMetrics.height(question.header, size: 10, width: questionTextWidth(width))
    }
    static func questionHeader(_ question: IslandApprovalQuestion, width: CGFloat) -> CGFloat {
        questionTitleRowHeight(question, width: width)
            + (question.header.isEmpty ? 0 : 4 + questionHeaderLabelHeight(question, width: width))
    }
    static func permissionHeight(_ permission: IslandApprovalPermission, width: CGFloat) -> CGFloat {
        max(60, IslandTaskTextMetrics.limitedHeight(permission.title, lines: 2, size: 11, code: true, width: width - 100) + 44)
    }
    static func formFieldHeight(_ field: IslandApprovalField) -> CGFloat {
        let label = IslandTaskTextMetrics.height(field.title + (field.required ? " *" : ""), size: 12, semibold: true, width: 140)
            + (field.schema["description"].text.isEmpty ? 0 : 4 + IslandTaskTextMetrics.height(field.schema["description"].text, width: 140))
        let control = field.schema["type"].text == "array"
            ? CGFloat(field.choices.count) * 32 + CGFloat(max(0, field.choices.count - 1)) * 6 : inputHeight
        return max(label, control) + 24
    }
    init(request: IslandConfirmation, width: CGFloat, english: Bool, maximumViewportHeight: CGFloat, cardHeight: CGFloat = IslandVibeLayout.rowHeight) {
        self.maximumViewportHeight = max(0, min(Self.maximumContentViewport, maximumViewportHeight))
        contentWidth = width
        questionHeight = IslandTaskTextMetrics.height(request.question.value(english), size: 13, semibold: true, width: width)
        impactHeight = IslandTaskTextMetrics.height(request.impact.value(english), size: 12, width: width - Self.inset * 2)
        let failure: String
        switch request.phase {
        case .failed(_, let message): failure = message.value(english)
        default: failure = ""
        }
        failureHeight = failure.isEmpty ? 0 : IslandTaskTextMetrics.height(failure, width: width - 48) + 24
        var h: CGFloat = 0
        if let wire = request.protocolRequest {
            switch wire.kind {
            case .questions:
                for q in wire.questions {
                    var group = Self.questionHeader(q, width: width)
                    if !q.options.isEmpty {
                        if IslandApprovalLayout(wire) == .connector {
                            let optionWidth = (width - CGFloat(max(0, q.options.count - 1)) * 8) / CGFloat(max(1, q.options.count))
                            group += 8 + (q.options.map { Self.optionHeight($0["label"].text, description: $0["description"].text, width: optionWidth) }.max() ?? 0)
                        } else {
                            group += q.options.reduce(0) { $0 + Self.optionHeight($1["label"].text, description: $1["description"].text, width: width) + 8 }
                        }
                    }
                    if q.allowsCustomAnswer { group += 8 + Self.inputHeight }
                    h += group
                }
                h += CGFloat(max(0, wire.questions.count - 1)) * 20
            case .permissions:
                h = wire.permissions.reduce(0) { $0 + Self.permissionHeight($1, width: width) }
                    + CGFloat(max(0, wire.permissions.count - 1)) * 8 + 12 + Self.inputHeight
            case .mcpForm:
                if wire.supportedForm { h = wire.fields.reduce(0) { $0 + Self.formFieldHeight($1) } }
            default: break
            }
        }
        controlsHeight = h
        decisionsHeight = request.protocolRequest.map { IslandApprovalDecisionChoices.height($0, width: width, english: english) } ?? 0
        let impactBlock = request.impact.value(english).isEmpty ? 0 : Self.inset * 2 + 16 + 4 + impactHeight + Self.gap
        let bodyHeight = request.protocolRequest.map { IslandApprovalTypedMetrics.height($0, width: width, controls: h, english: english) }
            ?? (questionHeight + Self.gap + impactBlock + controlsHeight)
        contentHeight = cardHeight + Self.gap + bodyHeight
            + (decisionsHeight > 0 ? Self.gap + decisionsHeight : 0)
            + (failureHeight > 0 ? Self.gap + failureHeight : 0) + IslandVibeLayout.rowSpacing
    }
}

struct IslandApprovalQuestionHeading: View {
    let question: IslandApprovalQuestion
    let number: Int
    let width: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !question.header.isEmpty {
                Text(question.header).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandApprovalAppearance.muted).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: IslandApprovalMetrics.questionTextWidth(width),
                        height: IslandApprovalMetrics.questionHeaderLabelHeight(question, width: width), alignment: .topLeading)
                    .padding(.leading, IslandApprovalMetrics.questionNumberSize + IslandApprovalMetrics.questionHeadingGap)
            }
            HStack(alignment: .firstTextBaseline, spacing: IslandApprovalMetrics.questionHeadingGap) {
                Text(String(format: "%02d", number)).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(IslandApprovalAppearance.secondary)
                    .frame(width: IslandApprovalMetrics.questionNumberSize, height: IslandApprovalMetrics.questionNumberSize)
                    .background(IslandApprovalAppearance.raised, in: RoundedRectangle(cornerRadius: 6))
                Text(question.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: IslandApprovalMetrics.questionTextWidth(width), alignment: .leading)
            }.frame(height: IslandApprovalMetrics.questionTitleRowHeight(question, width: width), alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// The View and interaction smokes share this entry, including the actual
// request-specific Board binding. Choosing or editing only changes its draft;
// response capability and phase are checked again at the explicit send action.
@MainActor
struct IslandQuestionInteractionEntry {
    let request: IslandConfirmation
    let draft: Binding<IslandApprovalDraft>
    let onDecision: (UUID, IslandConfirmationDecision) -> Void

    private var wire: IslandCodexApprovalRequest? {
        guard let wire = request.protocolRequest, wire.kind == .questions,
              wire.supportedQuestions, !wire.observationOnly else { return nil }
        return wire
    }
    var canEdit: Bool { request.canRespond && request.phase.canSubmit && wire != nil }
    var canConfirm: Bool { confirmationResult != nil }
    var canSkip: Bool {
        guard canEdit, let wire else { return false }
        return wire.questionSkipResult != nil
            || (wire.userInputMode == .asynchronous && wire.desktopHandle?.kind == .asynchronousQuestion)
    }
    private var confirmationResult: IslandApprovalJSON? {
        guard canEdit, let wire, let result = draft.wrappedValue.result(for: wire),
              wire.permits(result) else { return nil }
        return result
    }
    private func question(_ id: String) -> IslandApprovalQuestion? {
        request.protocolRequest?.questions.first { $0.id == id }
    }
    func isSelected(_ label: String, questionID: String) -> Bool {
        guard let question = question(questionID), question.options.contains(where: { $0["label"].text == label }) else { return false }
        return draft.wrappedValue.selections[questionID]?.contains(label) == true
    }
    func isCustomSelected(questionID: String) -> Bool {
        guard let question = question(questionID) else { return false }
        return question.allowsCustomAnswer && draft.wrappedValue.usesCustomAnswer(for: question)
    }
    func isAnswered(questionID: String) -> Bool {
        guard let question = question(questionID) else { return false }
        return draft.wrappedValue.answer(for: question) != nil
    }
    @discardableResult
    func choose(_ label: String, questionID: String) -> Bool {
        guard canEdit, let question = question(questionID),
              question.options.contains(where: { $0["label"].text == label }) else { return false }
        var value = draft.wrappedValue
        value.selectAnswer(label, for: question)
        draft.wrappedValue = value
        return true
    }
    @discardableResult
    func chooseCustom(questionID: String) -> Bool {
        guard canEdit, let question = question(questionID), question.allowsCustomAnswer else { return false }
        var value = draft.wrappedValue
        value.selectCustomAnswer(for: question)
        draft.wrappedValue = value
        return true
    }
    @discardableResult
    func edit(_ text: String, questionID: String) -> Bool {
        guard canEdit, let question = question(questionID), question.allowsCustomAnswer else { return false }
        var value = draft.wrappedValue
        value.setAnswer(text, for: question)
        draft.wrappedValue = value
        return true
    }
    func answerBinding(questionID: String) -> Binding<String> {
        .init(get: { draft.wrappedValue.values[questionID] ?? "" },
              set: { _ = edit($0, questionID: questionID) })
    }
    @discardableResult
    func confirm() -> Bool {
        guard let result = confirmationResult else { return false }
        onDecision(request.id, .reply(result))
        return true
    }
    @discardableResult
    func skip() -> Bool {
        guard canSkip else { return false }
        onDecision(request.id, .skipQuestion)
        return true
    }
}

struct IslandApprovalView: View {
    let task: CodexMultitaskRenderTask
    let metadata: IslandSessionMetadata?
    let request: IslandConfirmation
    let metrics: IslandApprovalMetrics
    let english: Bool
    let visible: Bool
    let playbackEnabled: Bool
    let reduceMotion: Bool
    let scrollLink: IslandTaskScrollLink
    @Binding var draft: IslandApprovalDraft
    let onDecision: (UUID, IslandConfirmationDecision) -> Void
    var onDismiss: (() -> Void)? = nil
    var showsLocalDismiss = false
    var onArchive: (() -> Void)? = nil
    var progressEffect: AppPreferences.CodexActivityProgressEffect = .dropField
    var utilities: IslandUtilityActions? = nil
    @State private var codexJumpMessage = ""
    @State private var headerVisible = false
    @State private var taskHeaderHovered = false
    private var muted: Color { IslandApprovalAppearance.muted }
    private var secondary: Color { IslandApprovalAppearance.secondary }
    private func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    private var wire: IslandCodexApprovalRequest? { request.protocolRequest }
    var questionInteraction: IslandQuestionInteractionEntry {
        .init(request: request, draft: $draft, onDecision: onDecision)
    }
    private var actions: [IslandApprovalAction] {
        wire?.actions ?? []
    }
    private var firstNegative: IslandApprovalAction? {
        actions.first { $0.result["decision"].text == "decline" || $0.result["action"].text == "decline" || $0.id == "deny" }
    }
    var primaryAction: IslandApprovalAction? {
        if let wire {
            let label: IslandDetailText? = switch wire.kind {
            case .questions: .init("确认", "Confirm")
            case .permissions: .init("授予所选权限", "Grant selected")
            case .mcpForm: wire.isApprovalOnlyForm ? .init("批准", "Approve") : .init("提交参数", "Submit form")
            case .mcpURL: .init("完成授权，继续", "Authorization complete, continue")
            default: nil
            }
            if let label {
                return .init(id: "submit", label: label, result: draft.result(for: wire) ?? .null, affirmative: true)
            }
        }
        guard var action = wire.flatMap({ IslandApprovalDecisionChoices.selected($0, id: draft.decisionID)?.action })
            ?? actions.first(where: { $0.result["decision"] == .string("accept") }) else { return nil }
        if let wire, action.result["decision"] == .string("accept") {
            switch wire.kind {
            case .command: action.label = .init("允许执行", "Allow command")
            case .terminalInput: action.label = .init("发送输入", "Send input")
            case .fileChange: action.label = .init("允许修改", "Allow changes")
            case .network: action.label = .init("允许访问", "Allow access")
            default: break
            }
        }
        return action
    }
    private var cancelAction: IslandApprovalAction? {
        guard var action = actions.first(where: { $0.result["decision"].text == "cancel" || $0.result["action"].text == "cancel" }) else { return nil }
        action.label = .init("取消请求", "Cancel request")
        return action
    }
    private var submitting: Bool { if case .submitting = request.phase { true } else { false } }
    private var canDismissLocally: Bool { showsLocalDismiss && onDismiss != nil && !submitting }
    private var submittingTitle: String {
        wire?.isApprovalOnlyForm == true ? text("批准中…", "Approving…") : text("提交中…", "Submitting…")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                requestContent.padding(.leading, IslandVibeLayout.listInset)
                    .padding(.trailing, metrics.showsRail ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset)
                    .padding(.bottom, IslandVibeLayout.rowSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: metrics.contentHeight, alignment: .top)
                    .background(IslandTaskScrollConfiguration(layout: .init(taskIDs: [task.id], detailID: nil,
                        rowHeights: [task.id: metadata?.taskGroupHeight(width: metrics.contentWidth) ?? IslandVibeLayout.rowHeight]),
                        active: visible, onVisibilityChange: { headerVisible = $0.visible.contains(.task(task.id)) }, link: scrollLink))
            }.scrollIndicators(.never).frame(height: metrics.viewportHeight)
                .overlay(alignment: .trailing) {
                    if metrics.showsRail {
                        IslandTaskScrollRailView(link: scrollLink, label: text("请求内容滚动条", "Request scrollbar"))
                            .frame(width: IslandVibeLayout.scrollRailWidth, height: metrics.viewportHeight - IslandVibeLayout.rowSpacing)
                            .padding(.trailing, IslandVibeLayout.scrollRailTrailingInset).padding(.bottom, IslandVibeLayout.rowSpacing)
                    }
                }
            Rectangle().fill(IslandApprovalAppearance.border).frame(height: 1)
                .padding(.horizontal, IslandVibeLayout.listInset).padding(.top, IslandApprovalMetrics.gap)
            actionBar.padding(.horizontal, IslandVibeLayout.listInset).padding(.top, IslandApprovalMetrics.gap)
            IslandChromeFooter {
                Text("Codex · " + (request.canRespond ? text("可处理", "Interactive") : text("仅查看", "Read-only")))
                    .lineLimit(1)
            } trailing: {
                Text(footerStatus).lineLimit(1).truncationMode(.tail)
                if let utilities { utilities }
            }.padding(.top, 8)
        }.frame(height: metrics.height, alignment: .top)
            .preferredColorScheme(.dark)
    }

    private var actionBar: some View {
        IslandApprovalActionLayout {
            if !request.canRespond || wire?.kind == .nativeOnly || (wire?.kind == .mcpForm && wire?.supportedForm == false) || (wire?.kind == .questions && wire?.supportedQuestions == false) || wire?.kind == .mcpURL {
                specialButton(text("在 Codex 处理", "Open Codex"), icon: "arrow.up.right", enabled: true) { openCodex() }
                if showsLocalDismiss { localDismissButton }
            } else if wire?.kind == .questions {
                if wire?.userInputMode == .asynchronous || (showsLocalDismiss && !request.phase.canSubmit) {
                    if showsLocalDismiss { localDismissButton }
                } else {
                    Button { questionInteraction.skip() } label: {
                        Text(text("跳过", "Skip")).font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
                    }.buttonStyle(IslandApprovalActionStyle(primary: false)).disabled(!questionInteraction.canSkip)
                        .help(text("跳过这些问题并通知 Codex", "Skip these questions and notify Codex"))
                }
                if let action = primaryAction { actionButton(action, primary: true) }
            } else {
            if let action = cancelAction { actionButton(action) }
            if let action = firstNegative { actionButton(action, destructive: true) }
            if wire?.kind == .mcpURL && !draft.openedURL {
                specialButton(text("打开授权页面", "Open authorization page"), icon: "arrow.up.right", enabled: wire?.url != nil) { draft.openedURL = true }
            } else if wire?.kind == .nativeOnly || (wire?.kind == .mcpForm && wire?.supportedForm == false) {
                specialButton(text("在 Codex 中验证", "Verify in Codex"), icon: "arrow.up.right", enabled: true) { openCodex() }
            } else if let action = primaryAction { actionButton(action, primary: true) }
            else if firstNegative == nil {
                specialButton(text("在 Codex 中处理", "Continue in Codex"), icon: "arrow.up.right", enabled: true) { openCodex() }
            }
            if showsLocalDismiss { localDismissButton }
            }
        }
    }

    private var localDismissButton: some View {
        Button {
            guard canDismissLocally else { return }
            onDismiss?()
        } label: {
            Text(text("隐藏此提醒", "Hide reminder")).font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
        }.buttonStyle(IslandApprovalActionStyle(primary: false)).disabled(!canDismissLocally)
            .help(text("仅隐藏灵动岛提醒，请在 Codex 继续处理", "Hide this island reminder; continue in Codex"))
    }

    var requestContent: some View {
        VStack(alignment: .leading, spacing: IslandApprovalMetrics.gap) {
            IslandTaskCardStack(children: metadata?.subagents ?? [], english: english,
                visible: visible && headerVisible && playbackEnabled, reduceMotion: reduceMotion,
                appearance: .init(visualState: task.renderState.visualState, selected: true, hovered: taskHeaderHovered)) {
            IslandTaskCard(progressEffect: progressEffect, task: task, selected: true, metadata: metadata, english: english,
                playback: false, effectVisible: visible && headerVisible && playbackEnabled && task.playbackEnabled,
                reduceMotion: reduceMotion, hovered: taskHeaderHovered, showsArchiveButton: onArchive != nil, cardWidth: metrics.contentWidth)
                .overlay(alignment: .topTrailing) {
                    if let onArchive {
                        IslandTaskArchiveButton(english: english, showsArchiveIcon: taskHeaderHovered, action: onArchive)
                            .padding(.top, 6).padding(.trailing, 8)
                    }
                }
            }.contentShape(RoundedRectangle(cornerRadius: IslandVibeLayout.rowRadius))
                .onHover { taskHeaderHovered = $0 }
            if let wire {
                IslandApprovalTypedContent(request: wire, width: metrics.contentWidth, english: english,
                    openedURL: draft.openedURL, handoffMessage: codexJumpMessage,
                    controls: controls(wire).disabled(wire.kind == .questions
                        ? !questionInteraction.canEdit : !request.canRespond || !request.phase.canSubmit))
            } else {
            Text(request.question.value(english)).font(.system(size: 13, weight: .semibold)).lineSpacing(2)
                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: metrics.questionHeight, alignment: .topLeading)
                .textSelection(.enabled)
            if !request.impact.value(english).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wire == nil ? text("请求状态", "Request status") : text("请求内容与范围", "Request and scope"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(muted).frame(height: 16)
                    Text(request.impact.value(english)).font(.system(size: 12)).lineSpacing(2)
                        .foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: metrics.impactHeight, alignment: .topLeading)
                        .textSelection(.enabled)
                }.padding(IslandApprovalMetrics.inset).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.075, green: 0.075, blue: 0.075), in: RoundedRectangle(cornerRadius: 8))
            }
            }
            if let wire, metrics.decisionsHeight > 0 { decisionChoices(wire) }
            if let failure = failureMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").frame(width: 16)
                    Text(failure).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 11)).foregroundStyle(Color(red: 0.95, green: 0.43, blue: 0.42))
                    .padding(12).frame(height: metrics.failureHeight, alignment: .topLeading)
                    .background(Color(red: 0.12, green: 0.065, blue: 0.065), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    private var failureMessage: String? {
        switch request.phase {
        case .failed(_, let message): message.value(english)
        default: nil
        }
    }
    @ViewBuilder private func controls(_ request: IslandCodexApprovalRequest) -> some View {
        switch request.kind {
        case .questions:
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(request.questions.enumerated()), id: \.offset) { index, q in
                    VStack(alignment: .leading, spacing: 8) {
                        IslandApprovalQuestionHeading(question: q, number: index + 1, width: metrics.contentWidth)
                        if IslandApprovalLayout(request) == .connector {
                            HStack(spacing: 8) {
                                let optionWidth = (metrics.contentWidth - CGFloat(max(0, q.options.count - 1)) * 8) / CGFloat(max(1, q.options.count))
                                let rowHeight = q.options.map { IslandApprovalMetrics.optionHeight($0["label"].text,
                                    description: $0["description"].text, width: optionWidth) }.max() ?? 0
                                ForEach(Array(q.options.enumerated()), id: \.offset) { _, option in
                                    optionButton(q, option: option, width: optionWidth, height: rowHeight)
                                }
                            }
                        } else { ForEach(Array(q.options.enumerated()), id: \.offset) { _, option in optionButton(q, option: option) } }
                        if q.allowsCustomAnswer {
                            IslandApprovalInput(placeholder: text(q.options.isEmpty ? "输入你的回答" : "自行输入…",
                                q.options.isEmpty ? "Your answer" : "Enter your own answer…"), secret: q.secret,
                                value: questionInteraction.answerBinding(questionID: q.id),
                                selected: questionInteraction.isCustomSelected(questionID: q.id),
                                onSelect: { questionInteraction.chooseCustom(questionID: q.id) })
                        }
                    }
                }
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 8) {
                    ForEach(request.permissions) { permission in
                        let selected = draft.selections["permissions"]?.contains(permission.id) == true
                        Button { selectionBinding("permissions", value: permission.id).wrappedValue.toggle() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: permission.group == "network" ? "network" : permission.group == "write" ? "square.and.pencil" : "folder")
                                    .font(.system(size: 16)).foregroundStyle(secondary).frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(permission.group == "network" ? text("访问网络", "Network access")
                                        : permission.group == "read" ? text("读取文件", "Read files")
                                        : permission.group == "write" ? text("写入文件", "Write files") : text("文件访问", "File access"))
                                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                                    Text(permission.group == "network" ? text("允许此任务建立网络连接", "Allow network connections for this task")
                                        : permission.group == "read" || permission.group == "write" ? permission.value.text : permission.title)
                                        .font(.system(size: 11, design: permission.group == "network" ? .default : .monospaced))
                                        .foregroundStyle(secondary).lineSpacing(2).lineLimit(2).truncationMode(.middle)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                selectionMark(selected, multiple: true)
                            }.padding(.horizontal, 12).frame(height: IslandApprovalMetrics.permissionHeight(permission, width: metrics.contentWidth))
                        }.buttonStyle(IslandApprovalSelectionStyle(selected: selected))
                            .accessibilityValue(selected ? text("已选择", "Selected") : text("未选择", "Not selected"))
                    }
                }
                HStack(spacing: 12) {
                    Text(text("授权期限", "Access duration")).font(.system(size: 11)).foregroundStyle(secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        scopeButton(text("仅本轮", "This turn"), session: false)
                        scopeButton(text("本会话", "This session"), session: true)
                    }.frame(width: 240)
                }.frame(height: IslandApprovalMetrics.inputHeight)
            }
        case .mcpForm:
            if request.supportedForm && !request.isApprovalOnlyForm {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(request.fields.enumerated()), id: \.element.id) { index, field in
                        formField(field).overlay(alignment: .top) {
                            if index > 0 { Rectangle().fill(IslandApprovalAppearance.border).frame(height: 1).padding(.horizontal, 12) }
                        }
                    }
                }.background(IslandApprovalAppearance.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IslandApprovalAppearance.border, lineWidth: 1))
            }
        default: EmptyView()
        }
    }
    private func formField(_ field: IslandApprovalField) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.title + (field.required ? " *" : "")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !field.schema["description"].text.isEmpty {
                    Text(field.schema["description"].text).font(.system(size: 11)).foregroundStyle(secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(width: 140, alignment: .leading)
            Group {
                if field.schema["type"].text == "array" {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(field.choices.enumerated()), id: \.offset) { _, choice in
                            let selected = draft.selections[field.id]?.contains(choice.pretty) == true
                            Button { selectionBinding(field.id, value: choice.pretty).wrappedValue.toggle() } label: {
                                HStack(spacing: 8) {
                                    selectionMark(selected, multiple: true)
                                    Text(field.label(for: choice)).foregroundStyle(.white)
                                    Spacer()
                                }.padding(.horizontal, 10).frame(height: 32)
                            }.buttonStyle(IslandApprovalSelectionStyle(selected: selected))
                                .accessibilityValue(selected ? text("已选择", "Selected") : text("未选择", "Not selected"))
                        }
                    }
                } else if field.schema["type"].text == "boolean" {
                    HStack(spacing: 6) {
                        booleanButton(field, value: "true", label: text("是", "Yes"))
                        booleanButton(field, value: "false", label: text("否", "No"))
                    }.accessibilityLabel(field.title)
                } else if !field.choices.isEmpty {
                    Menu {
                        Button(text("清除选择", "Clear selection")) { draft.values[field.id] = "" }
                        ForEach(Array(field.choices.enumerated()), id: \.offset) { _, choice in
                            Button(field.label(for: choice)) { draft.values[field.id] = choice.text.isEmpty ? choice.pretty : choice.text }
                        }
                    } label: {
                        HStack {
                            let chosen = field.choices.first { ($0.text.isEmpty ? $0.pretty : $0.text) == (draft.values[field.id] ?? "") }
                            Text(chosen.map { field.label(for: $0) } ?? text("请选择", "Choose an option"))
                                .foregroundStyle(chosen == nil ? muted : .white)
                                .lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(secondary)
                        }.padding(.horizontal, 12).frame(height: IslandApprovalMetrics.inputHeight)
                            .background(IslandApprovalAppearance.raised, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(IslandApprovalAppearance.border, lineWidth: 1))
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel(field.title)
                } else {
                    IslandApprovalInput(placeholder: text("请输入", "Enter value"), secret: false, value: valueBinding(field.id))
                        .accessibilityLabel(field.title)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 12)).padding(12)
            .frame(height: IslandApprovalMetrics.formFieldHeight(field), alignment: .top)
    }
    private func booleanButton(_ field: IslandApprovalField, value: String, label: String) -> some View {
        let selected = draft.values[field.id] == value
        return Button { draft.values[field.id] = value } label: {
            HStack(spacing: 8) {
                selectionMark(selected, multiple: false)
                Text(label).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
            }.frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.inputHeight)
        }.buttonStyle(IslandApprovalSelectionStyle(selected: selected))
            .accessibilityValue(selected ? text("已选择", "Selected") : text("未选择", "Not selected"))
    }
    private func scopeButton(_ label: String, session: Bool) -> some View {
        Button { draft.sessionScope = session } label: {
            Text(label).font(.system(size: 11, weight: draft.sessionScope == session ? .semibold : .regular))
                .foregroundStyle(draft.sessionScope == session ? Color.white : secondary)
                .frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.inputHeight)
        }.buttonStyle(IslandApprovalSelectionStyle(selected: draft.sessionScope == session))
            .accessibilityValue(draft.sessionScope == session ? text("已选择", "Selected") : text("未选择", "Not selected"))
    }
    private func optionButton(_ q: IslandApprovalQuestion, option: IslandApprovalJSON, width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        let label = option["label"].text
        let availableWidth = width ?? metrics.contentWidth
        let selected = questionInteraction.isSelected(label, questionID: q.id)
        return Button {
            questionInteraction.choose(label, questionID: q.id)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineSpacing(2)
                        .lineLimit(2).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: IslandTaskTextMetrics.limitedHeight(label, lines: 2, size: 12, semibold: true, width: availableWidth - 54), alignment: .topLeading)
                    if !option["description"].text.isEmpty {
                        Text(option["description"].text).font(.system(size: 11)).foregroundStyle(secondary).lineSpacing(2)
                            .lineLimit(2).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: IslandTaskTextMetrics.limitedHeight(option["description"].text, lines: 2, width: availableWidth - 54), alignment: .topLeading)
                    }
                }.fixedSize(horizontal: false, vertical: true)
                selectionMark(selected, multiple: false)
            }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height ?? IslandApprovalMetrics.optionHeight(label, description: option["description"].text, width: availableWidth))
        }.buttonStyle(IslandApprovalSelectionStyle(selected: selected))
            .contextMenu { copyContentButton(label + (option["description"].text.isEmpty ? "" : "\n" + option["description"].text)) }
            .accessibilityValue(selected ? text("已选择", "Selected") : text("未选择", "Not selected"))
    }
    private func selectionMark(_ selected: Bool, multiple: Bool) -> some View {
        Image(systemName: multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "checkmark.circle.fill" : "circle"))
            .font(.system(size: 15, weight: .regular)).foregroundStyle(selected ? Color.white : muted).frame(width: 20, height: 20)
    }
    private func answered(_ question: IslandApprovalQuestion) -> Bool {
        questionInteraction.isAnswered(questionID: question.id)
    }
    var footerStatus: String {
        if !codexJumpMessage.isEmpty { return codexJumpMessage }
        switch request.phase {
        case .submitting: return submittingTitle
        case .sent: return text("已发送，等待 Codex 确认", "Sent, awaiting Codex confirmation")
        case .resultUnknown: return text("结果未确认，请在 Codex 核对", "Result unconfirmed; check in Codex")
        case .resolved: return text("请求已处理", "Request resolved")
        default: break
        }
        if !request.canRespond { return text("请在 Codex 处理", "Handle this request in Codex") }
        guard let wire else { return text("等待选择", "Awaiting a choice") }
        switch wire.kind {
        case .questions:
            return text("已填写 \(wire.questions.filter { answered($0) }.count) / \(wire.questions.count) · 确认后发送",
                "\(wire.questions.filter { answered($0) }.count) of \(wire.questions.count) ready · Confirm to send")
        case .permissions:
            return text("已选 \((draft.selections["permissions"] ?? []).count) 项 · \(draft.sessionScope ? "本会话" : "仅本轮")",
                "\((draft.selections["permissions"] ?? []).count) selected · \(draft.sessionScope ? "This session" : "This turn")")
        case .mcpForm:
            if wire.isApprovalOnlyForm { return text("批准后继续", "Resumes after approval") }
            return draft.result(for: wire) == nil ? text("请填写必填项并检查格式", "Complete required fields in the requested format") : text("参数已就绪", "Ready to submit")
        case .mcpURL: return draft.openedURL ? text("完成授权后继续", "Continue when authorization is complete") : text("请打开授权页面", "Open the authorization page")
        case .nativeOnly: return text("请在 Codex 处理", "Continue in Codex")
        default: return text("确认后继续", "Resumes after approval")
        }
    }
    private func decisionChoices(_ request: IslandCodexApprovalRequest) -> some View {
        let options = IslandApprovalDecisionChoices.options(request)
        let scopes = options.filter { !$0.isRule }
        let rules = options.filter(\.isRule)
        return VStack(alignment: .leading, spacing: 8) {
            Text(request.kind == .network ? text("访问范围与规则", "Access scope and rules") : text("批准范围", "Approval scope"))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(muted).frame(height: 16)
            if !scopes.isEmpty {
                let width = (metrics.contentWidth - CGFloat(max(0, scopes.count - 1)) * 8) / CGFloat(scopes.count)
                let height = scopes.map { IslandApprovalDecisionChoices.optionHeight($0, width: width, english: english) }.max() ?? 0
                HStack(spacing: 8) {
                    ForEach(scopes) { option in decisionOption(option, request: request, width: width, height: height) }
                }
            }
            ForEach(rules) { option in
                decisionOption(option, request: request, width: metrics.contentWidth,
                    height: IslandApprovalDecisionChoices.optionHeight(option, width: metrics.contentWidth, english: english))
            }
        }
    }
    private func decisionOption(_ option: IslandApprovalDecisionOption, request: IslandCodexApprovalRequest, width: CGFloat, height: CGFloat) -> some View {
        let selected = IslandApprovalDecisionChoices.selected(request, id: draft.decisionID)?.id == option.id
        return Button { draft.decisionID = option.id } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title.value(english)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineSpacing(2)
                        .lineLimit(2).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: IslandTaskTextMetrics.limitedHeight(option.title.value(english), lines: 2, size: 12, semibold: true, width: width - 54), alignment: .topLeading)
                    Text(option.detail.value(english)).font(.system(size: 11, design: option.isRule ? .monospaced : .default)).foregroundStyle(secondary).lineSpacing(2)
                        .lineLimit(2).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: IslandTaskTextMetrics.limitedHeight(option.detail.value(english), lines: 2, size: 11, code: option.isRule, width: width - 54), alignment: .topLeading)
                }.fixedSize(horizontal: false, vertical: true)
                selectionMark(selected, multiple: false)
            }.padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: height)
        }.buttonStyle(IslandApprovalSelectionStyle(selected: selected)).disabled(!self.request.phase.canSubmit)
            .contextMenu { copyContentButton(option.title.value(english) + "\n" + option.detail.value(english)) }
            .accessibilityValue(selected ? text("已选择", "Selected") : text("未选择", "Not selected"))
    }
    private func copyContentButton(_ value: String) -> some View {
        Button(text("复制完整内容", "Copy full text")) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        }
    }
    private func valueBinding(_ key: String) -> Binding<String> {
        .init(get: { draft.values[key] ?? "" }, set: { draft.values[key] = $0 })
    }
    private func selectionBinding(_ key: String, value: String) -> Binding<Bool> {
        .init(get: { draft.selections[key]?.contains(value) == true }, set: { enabled in
            var values = draft.selections[key] ?? []
            if enabled { values.insert(value) } else { values.remove(value) }
            draft.selections[key] = values
        })
    }
    private func actionButton(_ action: IslandApprovalAction, primary: Bool = false, destructive: Bool = false) -> some View {
        let enabled = wire?.kind == .questions ? questionInteraction.canConfirm
            : request.canRespond && request.phase.canSubmit && action.result != .null
        return Button { send(action) } label: {
            HStack(spacing: 8) {
                if submitting && primary { ProgressView().controlSize(.small).tint(secondary) }
                Text(submitting && primary ? submittingTitle : action.label.value(english))
                if primary && !submitting { Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)) }
            }.font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
        }.buttonStyle(IslandApprovalActionStyle(primary: primary, destructive: destructive)).disabled(!enabled)
            .keyboardShortcut(primary && (wire?.kind == .questions || wire?.kind == .mcpForm) ? KeyboardShortcut(.return, modifiers: .command) : nil)
    }
    private func specialButton(_ title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            }.font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
        }.buttonStyle(IslandApprovalActionStyle(primary: true)).disabled(!enabled)
    }
    private func send(_ action: IslandApprovalAction) {
        if wire?.kind == .questions { questionInteraction.confirm(); return }
        guard request.canRespond, request.phase.canSubmit, action.result != .null else { return }
        if wire == nil { onDecision(request.id, action.affirmative ? .allowOnce : .reject) }
        else { onDecision(request.id, .reply(action.result)) }
    }
    private func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            codexJumpMessage = text("未找到 Codex，请手动打开对应任务", "Codex not found; open the task manually"); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            DispatchQueue.main.async {
                codexJumpMessage = error == nil ? text("已打开 Codex，请选择对应任务", "Codex opened; select this task")
                    : text("未能打开 Codex，请手动打开对应任务", "Could not open Codex; open the task manually")
            }
        }
    }
}
