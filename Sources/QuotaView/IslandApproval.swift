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
            case "accept": return .init(action: action, title: .init("仅这一次", "This request"), detail: .init("后续请求仍需确认", "Ask again for future requests"))
            case "acceptForSession": return .init(action: action, title: .init("本会话", "This session"), detail: .init("按本会话批准范围处理", "Apply the session approval scope"))
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
        IslandTaskTextMetrics.height(option.title.value(english), size: 12, semibold: true, width: width - 54)
            + 4 + IslandTaskTextMetrics.height(option.detail.value(english), size: 11, code: option.isRule, width: width - 54) + 20
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
    static let gap: CGFloat = 12
    static let inset: CGFloat = 12
    static let buttonHeight: CGFloat = 42
    static let inputHeight: CGFloat = 36
    static let footerHeight: CGFloat = 20
    static var fixedHeight: CGFloat { gap + 1 + gap + buttonHeight + 8 + footerHeight + 16 }
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
        IslandTaskTextMetrics.height(label, size: 12, semibold: true, width: width - 54)
            + (description.isEmpty ? 0 : IslandTaskTextMetrics.height(description, width: width - 54) + 4) + 20
    }
    static func questionHeader(_ question: IslandApprovalQuestion, width: CGFloat) -> CGFloat {
        max(24, IslandTaskTextMetrics.height(question.title, size: 13, semibold: true, width: width - 60))
    }
    static func permissionHeight(_ permission: IslandApprovalPermission, width: CGFloat) -> CGFloat {
        max(60, IslandTaskTextMetrics.height(permission.title, size: 11, code: true, width: width - 100) + 44)
    }
    static func formFieldHeight(_ field: IslandApprovalField) -> CGFloat {
        let label = IslandTaskTextMetrics.height(field.title + (field.required ? " *" : ""), size: 12, semibold: true, width: 140)
            + (field.schema["description"].text.isEmpty ? 0 : 4 + IslandTaskTextMetrics.height(field.schema["description"].text, width: 140))
        let control = field.schema["type"].text == "array"
            ? CGFloat(field.choices.count) * 32 + CGFloat(max(0, field.choices.count - 1)) * 6 : inputHeight
        return max(label, control) + 24
    }
    init(request: IslandConfirmation, width: CGFloat, english: Bool, maximumViewportHeight: CGFloat, cardHeight: CGFloat = IslandVibeLayout.rowHeight) {
        self.maximumViewportHeight = max(0, maximumViewportHeight)
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
                    if q.other || q.options.isEmpty { group += 8 + Self.inputHeight }
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
    var onArchive: (() -> Void)? = nil
    @State private var codexJumpMessage = ""
    @State private var headerVisible = false
    private var muted: Color { IslandApprovalAppearance.muted }
    private var secondary: Color { IslandApprovalAppearance.secondary }
    private func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    private var wire: IslandCodexApprovalRequest? { request.protocolRequest }
    private var actions: [IslandApprovalAction] {
        wire?.actions ?? [
            .init(id: "decline", label: .init("拒绝", "Decline"), result: .object(["decision": .string("decline")]), affirmative: false),
            .init(id: "accept", label: .init("允许一次", "Allow once"), result: .object(["decision": .string("accept")]), affirmative: true)
        ]
    }
    private var firstNegative: IslandApprovalAction? {
        actions.first { $0.result["decision"].text == "decline" || $0.result["action"].text == "decline" || $0.id == "deny" }
    }
    private var primaryAction: IslandApprovalAction? {
        if let wire, [.questions, .permissions, .mcpForm, .mcpURL].contains(wire.kind) {
            return .init(id: "submit", label: wire.kind == .questions || wire.kind == .mcpForm
                ? (IslandApprovalLayout(wire) == .connector ? .init("提交选择", "Submit choice")
                    : wire.kind == .mcpForm ? .init("提交参数", "Submit form") : .init("提交回答", "Submit answers"))
                : (wire.kind == .mcpURL ? .init("已完成，继续", "Finished, continue") : .init("授予所选权限", "Grant selected")),
                result: draft.result(for: wire) ?? .null, affirmative: true)
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                requestContent.padding(.leading, IslandVibeLayout.listInset)
                    .padding(.trailing, metrics.showsRail ? IslandVibeLayout.scrollingListTrailingInset : IslandVibeLayout.listInset)
                    .padding(.bottom, IslandVibeLayout.rowSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: metrics.contentHeight, alignment: .top)
                    .background(IslandTaskScrollConfiguration(layout: .init(taskIDs: [task.id], detailID: nil),
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
            HStack(spacing: 6) {
                Text("Codex").font(.system(size: 8, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(IslandApprovalAppearance.raised, in: RoundedRectangle(cornerRadius: 4))
                Text(request.canRespond ? text("可应答", "Interactive") : text("观察模式", "Observer"))
                Spacer()
                Text(footerStatus)
            }.font(.system(size: 10)).foregroundStyle(muted).frame(height: IslandApprovalMetrics.footerHeight)
                .padding(.horizontal, IslandVibeLayout.listInset).padding(.top, 8)
        }.padding(.bottom, 16).frame(height: metrics.height, alignment: .top)
            .preferredColorScheme(.dark)
    }

    private var actionBar: some View {
        IslandApprovalActionLayout {
            if !request.canRespond || wire?.kind == .nativeOnly || (wire?.kind == .mcpForm && wire?.supportedForm == false) || wire?.kind == .mcpURL {
                specialButton(text("在 Codex 处理", "Open Codex"), icon: "arrow.up.right", enabled: true) { openCodex() }
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
            }
        }
    }

    var requestContent: some View {
        VStack(alignment: .leading, spacing: IslandApprovalMetrics.gap) {
            IslandTaskCard(task: task, selected: true, metadata: metadata, english: english,
                playback: false, effectVisible: visible && headerVisible && playbackEnabled && task.playbackEnabled,
                reduceMotion: reduceMotion, showsArchiveButton: onArchive != nil, cardWidth: metrics.contentWidth)
                .overlay(alignment: .topTrailing) {
                    if let onArchive {
                        IslandTaskArchiveButton(english: english, action: onArchive)
                            .padding(.top, 6).padding(.trailing, 8)
                    }
                }
            if let wire {
                IslandApprovalTypedContent(request: wire, width: metrics.contentWidth, english: english,
                    openedURL: draft.openedURL, handoffMessage: codexJumpMessage,
                    controls: controls(wire).disabled(!request.phase.canSubmit))
            } else {
            Text(request.question.value(english)).font(.system(size: 13, weight: .semibold)).lineSpacing(2)
                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: metrics.questionHeight, alignment: .topLeading)
                .textSelection(.enabled)
            if !request.impact.value(english).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wire == nil ? text("操作影响", "Impact") : text("请求内容与范围", "Request and scope"))
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
                ForEach(Array(request.questions.enumerated()), id: \.element.id) { index, q in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(secondary).frame(width: 24, height: 24)
                                .background(IslandApprovalAppearance.raised, in: RoundedRectangle(cornerRadius: 6))
                            Text(q.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: answered(q) ? "checkmark.circle.fill" : "circle.dotted")
                                .font(.system(size: 12)).foregroundStyle(answered(q) ? secondary : muted).frame(width: 16, height: 24)
                                .accessibilityLabel(answered(q) ? text("已回答", "Answered") : text("未回答", "Unanswered"))
                        }.frame(height: IslandApprovalMetrics.questionHeader(q, width: metrics.contentWidth), alignment: .top)
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
                        if q.other || q.options.isEmpty {
                            IslandApprovalInput(placeholder: text(q.options.isEmpty ? "输入你的回答" : "其他答案，请补充…",
                                q.options.isEmpty ? "Your answer" : "Or enter another answer…"), secret: q.secret, value: answerBinding(q.id))
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
                                        .foregroundStyle(secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
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
            if request.supportedForm {
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
                Text(label).foregroundStyle(.white)
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
        let selected = draft.selections[q.id]?.contains(label) == true
        return Button {
            draft.selections[q.id] = [label]; draft.values[q.id] = ""
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: IslandTaskTextMetrics.height(label, size: 12, semibold: true, width: availableWidth - 54), alignment: .topLeading)
                    if !option["description"].text.isEmpty {
                        Text(option["description"].text).font(.system(size: 11)).foregroundStyle(secondary).lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: IslandTaskTextMetrics.height(option["description"].text, width: availableWidth - 54), alignment: .topLeading)
                    }
                }.fixedSize(horizontal: false, vertical: true)
                selectionMark(selected, multiple: false)
            }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height ?? IslandApprovalMetrics.optionHeight(label, description: option["description"].text, width: availableWidth))
        }.buttonStyle(IslandApprovalSelectionStyle(selected: selected))
            .accessibilityValue(selected ? text("已选择", "Selected") : text("未选择", "Not selected"))
    }
    private func selectionMark(_ selected: Bool, multiple: Bool) -> some View {
        Image(systemName: multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "checkmark.circle.fill" : "circle"))
            .font(.system(size: 15, weight: .regular)).foregroundStyle(selected ? Color.white : muted).frame(width: 20, height: 20)
    }
    private func answered(_ question: IslandApprovalQuestion) -> Bool {
        !(draft.selections[question.id] ?? []).isEmpty
            || !(draft.values[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var footerStatus: String {
        if !codexJumpMessage.isEmpty { return codexJumpMessage }
        switch request.phase {
        case .submitting: return text("正在提交…", "Submitting…")
        case .sent: return text("已发送，等待 Codex 确认", "Sent, awaiting Codex confirmation")
        case .resultUnknown: return text("处理结果尚未确认，请在 Codex 核对", "Result unknown; check in Codex")
        case .resolved: return text("请求已处理", "Request resolved")
        default: break
        }
        if !request.canRespond { return text("仅观察，请在 Codex 查看并处理", "Observer only; handle in Codex") }
        guard let wire else { return text("等待你的选择", "Awaiting your choice") }
        switch wire.kind {
        case .questions:
            return text("已回答 \(wire.questions.filter { answered($0) }.count) / \(wire.questions.count) 个问题",
                "\(wire.questions.filter { answered($0) }.count) of \(wire.questions.count) answered")
        case .permissions:
            return text("已选 \((draft.selections["permissions"] ?? []).count) 项 · \(draft.sessionScope ? "本会话" : "仅本轮")",
                "\((draft.selections["permissions"] ?? []).count) selected · \(draft.sessionScope ? "This session" : "This turn")")
        case .mcpForm: return draft.result(for: wire) == nil ? text("请完成必填项并检查格式", "Complete required fields and check the format") : text("参数已就绪", "Ready to submit")
        case .mcpURL: return draft.openedURL ? text("完成授权后继续", "Continue when authorization is complete") : text("等待打开授权页面", "Ready to open authorization")
        case .nativeOnly: return text("需在 Codex 中完成", "Continue in Codex")
        default: return text("确认后继续当前任务", "This task resumes after approval")
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: IslandTaskTextMetrics.height(option.title.value(english), size: 12, semibold: true, width: width - 54), alignment: .topLeading)
                    Text(option.detail.value(english)).font(.system(size: 11, design: option.isRule ? .monospaced : .default)).foregroundStyle(secondary).lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: IslandTaskTextMetrics.height(option.detail.value(english), size: 11, code: option.isRule, width: width - 54), alignment: .topLeading)
                }.fixedSize(horizontal: false, vertical: true)
                selectionMark(selected, multiple: false)
            }.padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: height)
        }.buttonStyle(IslandApprovalSelectionStyle(selected: selected)).disabled(!self.request.phase.canSubmit)
            .accessibilityValue(selected ? text("已选择", "Selected") : text("未选择", "Not selected"))
    }
    private func valueBinding(_ key: String) -> Binding<String> {
        .init(get: { draft.values[key] ?? "" }, set: { draft.values[key] = $0 })
    }
    private func answerBinding(_ key: String) -> Binding<String> {
        .init(get: { draft.values[key] ?? "" }, set: { draft.values[key] = $0; draft.selections[key] = [] })
    }
    private func selectionBinding(_ key: String, value: String) -> Binding<Bool> {
        .init(get: { draft.selections[key]?.contains(value) == true }, set: { enabled in
            var values = draft.selections[key] ?? []
            if enabled { values.insert(value) } else { values.remove(value) }
            draft.selections[key] = values
        })
    }
    private func actionButton(_ action: IslandApprovalAction, primary: Bool = false, destructive: Bool = false) -> some View {
        let enabled = request.phase.canSubmit && action.result != .null
        return Button { send(action) } label: {
            HStack(spacing: 8) {
                if submitting && primary { ProgressView().controlSize(.small).tint(secondary) }
                Text(submitting && primary ? text("正在提交…", "Submitting…") : action.label.value(english))
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
                codexJumpMessage = error == nil ? text("已打开 Codex，请选择此任务处理", "Codex opened; select this task to continue")
                    : text("未能打开 Codex，请手动打开对应任务", "Could not open Codex; open the task manually")
            }
        }
    }
}
