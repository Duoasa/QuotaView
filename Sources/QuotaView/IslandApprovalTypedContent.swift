import SwiftUI

// Native presentation: presentation follows the supplied Codex request, never a transport.
enum IslandApprovalLayout: String, CaseIterable {
    case command, terminalInput, fileChange, network, permissions, connector, questions, form, authorization, verification
    init(_ request: IslandCodexApprovalRequest) {
        switch request.kind {
        case .command: self = .command
        case .terminalInput: self = .terminalInput
        case .fileChange: self = .fileChange
        case .network: self = .network
        case .permissions: self = .permissions
        case .questions: self = request.contextItem?["type"].text == "mcpToolCall" ? .connector : .questions
        case .mcpForm: self = request.supportedForm ? .form : .verification
        case .mcpURL: self = .authorization
        case .nativeOnly: self = .verification
        }
    }
    var icon: String {
        switch self {
        case .command: "terminal"
        case .terminalInput: "keyboard"
        case .fileChange: "doc.badge.gearshape"
        case .network: "network"
        case .permissions: "folder.badge.person.crop"
        case .connector: "square.stack.3d.up"
        case .questions: "text.bubble"
        case .form: "list.bullet.rectangle"
        case .authorization: "arrow.up.right.square"
        case .verification: "lock.shield"
        }
    }
}

// Shared with measured layout; all text uses opaque neutral colors.
enum IslandApprovalAppearance {
    static let surface = Color(white: 0.055)
    static let raised = Color(white: 0.085)
    static let border = Color(white: 0.13)
    static let secondary = Color(white: 0.68)
    static let muted = Color(white: 0.47)
    static let radius: CGFloat = 10
}

struct IslandApprovalSelectionStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected)
    }
    private struct Surface: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(Color(white: configuration.isPressed && enabled ? 0.16 : selected ? 0.12 : hovered && enabled ? 0.085 : 0.045),
                    in: RoundedRectangle(cornerRadius: IslandApprovalAppearance.radius))
                .overlay(RoundedRectangle(cornerRadius: IslandApprovalAppearance.radius)
                    .strokeBorder(Color(white: selected ? 0.48 : hovered && enabled ? 0.24 : 0.13), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: IslandApprovalAppearance.radius))
                .onHover { hovered = $0 }
        }
    }
}

struct IslandApprovalInput: View {
    let placeholder: String
    let secret: Bool
    @Binding var value: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            if secret { Image(systemName: "lock").foregroundStyle(IslandApprovalAppearance.muted) }
            Group {
                if secret { SecureField(placeholder, text: $value, prompt: Text(placeholder).foregroundStyle(IslandApprovalAppearance.muted)) }
                else { TextField(placeholder, text: $value, prompt: Text(placeholder).foregroundStyle(IslandApprovalAppearance.muted)) }
            }.textFieldStyle(.plain).focused($focused).accessibilityLabel(placeholder)
        }.font(.system(size: 12)).foregroundStyle(.white).padding(.horizontal, 12)
            .frame(height: IslandApprovalMetrics.inputHeight)
            .background(IslandApprovalAppearance.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? Color(white: 0.5) : IslandApprovalAppearance.border, lineWidth: 1))
    }
}

enum IslandApprovalTypedMetrics {
    static func text(_ value: String, width: CGFloat, code: Bool = false) -> CGFloat {
        IslandTaskTextMetrics.height(value, size: code ? 11 : 12, code: code, width: width)
    }
    static func code(_ value: String, caption: String, width: CGFloat) -> CGFloat {
        36 + 24 + text(value, width: width - 24, code: true)
            + (caption.isEmpty ? 0 : 1 + 20 + text(caption, width: width - 50, code: true))
    }
    static func diffText(_ change: IslandApprovalJSON) -> String {
        change["diff"].text.isEmpty ? change["diff"]["text"].text : change["diff"].text
    }
    static func diff(_ change: IslandApprovalJSON, width: CGFloat) -> CGFloat {
        48 + text(change["path"].text, width: width - 24, code: true)
            + diffText(change).components(separatedBy: "\n").reduce(CGFloat(0)) { $0 + text($1, width: width - 42, code: true) + 4 } + 8
    }
    static func arguments(_ request: IslandCodexApprovalRequest) -> [(String, String)] {
        let arguments = request.contextItem?["arguments"] ?? .null
        if let object = arguments.object {
            return object.keys.sorted().map { ($0, object[$0]!.text.isEmpty ? object[$0]!.pretty : object[$0]!.text) }
        }
        return [("arguments", arguments.pretty)]
    }
    static func argumentsHeight(_ request: IslandCodexApprovalRequest, width: CGFloat) -> CGFloat {
        36 + arguments(request).reduce(CGFloat(0)) {
            $0 + max(text($1.0, width: 112, code: true), text($1.1, width: width - 152, code: true)) + 20
        }
    }
    static func destinationHeight(name: String, subtitle: String, width: CGFloat) -> CGFloat {
        max(76, 28 + IslandTaskTextMetrics.height(name, size: 14, semibold: true, width: width - 180)
            + 5 + IslandTaskTextMetrics.height(subtitle, width: width - 180))
    }
    static func height(_ request: IslandCodexApprovalRequest, width: CGFloat, controls: CGFloat, english: Bool) -> CGFloat {
        let reason = request.params["reason"].text
        let note = reason.isEmpty ? 0 : 12 + 18 + text(reason, width: width - 22)
        switch IslandApprovalLayout(request) {
        case .command: return 24 + 12 + code(request.detail, caption: request.params["cwd"].text, width: width) + note
        case .terminalInput: return 24 + 12 + 28 + 12 + code(request.detail.debugDescription, caption: "", width: width) + note
        case .fileChange:
            let changes = request.contextItem?["changes"].array ?? []
            return 24 + 12 + (changes.isEmpty ? text(request.detail, width: width)
                : changes.reduce(0) { $0 + diff($1, width: width) } + CGFloat(max(0, changes.count - 1)) * 12) + note
        case .network: return 24 + 12 + destinationHeight(name: request.params["networkApprovalContext"]["host"].text,
            subtitle: english ? "Requested network access" : "请求网络访问", width: width) + note
        case .permissions: return 24 + 12 + controls + note
        case .connector: return 24 + 12 + argumentsHeight(request, width: width) + 16 + controls
        case .questions: return controls
        case .form: return 24 + 12 + controls + (request.detail.isEmpty ? 0 : 12 + text(request.detail, width: width))
        case .authorization:
            return 24 + 12 + destinationHeight(name: request.url?.host ?? request.params["serverName"].text,
                subtitle: request.params["serverName"].text, width: width) + 12 + text(request.params["url"].text, width: width, code: true) + 16 + 64
                + (request.detail.isEmpty ? 0 : 12 + text(request.detail, width: width))
        case .verification: return 24 + 12 + destinationHeight(name: english ? "Verify in Codex" : "在 Codex 中验证",
            subtitle: request.params["serverName"].text, width: width) + 12 + text(request.detail, width: width) + 12 + 36
        }
    }
}

struct IslandApprovalTypedContent<Controls: View>: View {
    let request: IslandCodexApprovalRequest
    let width: CGFloat
    let english: Bool
    let openedURL: Bool
    let handoffMessage: String?
    let controls: Controls
    private var layout: IslandApprovalLayout { .init(request) }
    private var muted: Color { IslandApprovalAppearance.muted }
    private var secondary: Color { IslandApprovalAppearance.secondary }
    private func t(_ zh: String, _ en: String) -> String { english ? en : zh }
    private var reason: String { request.params["reason"].text }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch layout {
            case .command:
                heading(t("允许执行这条命令？", "Allow this command?"))
                codePanel(t("执行命令", "Command to run"), value: request.detail, caption: request.params["cwd"].text)
                if !reason.isEmpty { reasonNote }
            case .terminalInput:
                heading(t("发送终端输入", "Send terminal input"))
                HStack(spacing: 8) {
                    Circle().fill(Color(white: 0.65)).frame(width: 5, height: 5)
                    Text(t("终端等待输入", "Terminal awaiting input"))
                    Spacer()
                    Text(t("发送后继续", "Resumes after input")).foregroundStyle(muted)
                }.font(.system(size: 11)).foregroundStyle(secondary).frame(height: 28)
                codePanel(t("待发送内容", "Input to send"), value: request.detail.debugDescription,
                    caption: "", trailing: t("换行以 \\n 表示", "Line endings shown as \\n"))
                if !reason.isEmpty { reasonNote }
            case .fileChange:
                heading(t("检查文件修改", "Review file changes"), trailing: "\(request.contextItem?["changes"].array.count ?? 0) " + t("个文件", "files"))
                let changes = request.contextItem?["changes"].array ?? []
                if changes.isEmpty { note(request.detail) }
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in diffPanel(change) }
                if !reason.isEmpty { reasonNote }
            case .network:
                heading(t("允许访问这个地址？", "Allow access to this host?"))
                destination(icon: "globe", name: request.params["networkApprovalContext"]["host"].text,
                    subtitle: t("请求网络访问", "Requested network access"),
                    badge: request.params["networkApprovalContext"]["protocol"].text.uppercased())
                if !reason.isEmpty { reasonNote }
            case .permissions:
                heading(t("选择授权范围", "Choose access to grant"), trailing: t("按需勾选", "Select as needed"))
                controls
                if !reason.isEmpty { reasonNote }
            case .connector:
                heading(t("确认工具操作", "Review tool action"), trailing: request.contextItem?["server"].text ?? "")
                argumentsPanel
                controls.padding(.top, 4)
            case .questions:
                controls
            case .form:
                heading(t("填写工具表单", "Complete the tool form"), trailing: t("* 必填", "* Required"))
                controls
                if !request.detail.isEmpty { note(request.detail) }
            case .authorization:
                heading(t("连接外部服务", "Connect an external provider"))
                destination(icon: "arrow.up.right.square", name: request.url?.host ?? request.params["serverName"].text,
                    subtitle: request.params["serverName"].text, badge: t("外部授权", "Authorization"))
                note(request.params["url"].text, code: true)
                HStack(spacing: 8) {
                    step(1, title: t("打开授权页面", "Open authorization"), subtitle: t("在服务商页面完成", "Complete with the provider"), complete: openedURL)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(muted)
                    step(2, title: t("返回并继续", "Return and continue"), subtitle: t("继续任务", "Resume this task"), complete: false)
                }.frame(height: 64).padding(.top, 4)
                if !request.detail.isEmpty { note(request.detail) }
            case .verification:
                heading(t("需要身份验证", "Identity verification required"))
                destination(icon: "lock.shield", name: t("在 Codex 中验证", "Verify in Codex"),
                    subtitle: request.params["serverName"].text, badge: "Codex")
                note(request.detail)
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                    Text(handoffMessage ?? t("请在 Codex 中验证", "Verify in Codex"))
                }.font(.system(size: 11)).foregroundStyle(secondary).frame(height: 36)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func heading(_ title: String, trailing: String = "") -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 8)
            if !trailing.isEmpty { Text(trailing).font(.system(size: 10)).foregroundStyle(muted) }
        }.frame(height: 24)
    }
    private func note(_ value: String, code: Bool = false) -> some View {
        Text(value).font(.system(size: code ? 11 : 12, design: code ? .monospaced : .default))
            .foregroundStyle(secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: IslandApprovalTypedMetrics.text(value, width: width, code: code), alignment: .topLeading)
            .textSelection(.enabled)
    }
    private var reasonNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(muted).frame(width: 14, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("请求原因", "Reason")).font(.system(size: 10)).foregroundStyle(muted).frame(height: 16)
                Text(reason).font(.system(size: 12)).foregroundStyle(secondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(height: IslandApprovalTypedMetrics.text(reason, width: width - 22), alignment: .topLeading)
            }
        }
    }
    private func codePanel(_ label: String, value: String, caption: String, trailing: String = "") -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: layout.icon).foregroundStyle(muted)
                Text(label).foregroundStyle(secondary)
                Spacer()
                if !trailing.isEmpty { Text(trailing).foregroundStyle(muted) }
            }.font(.system(size: 10, weight: .medium)).padding(.horizontal, 12).frame(height: 36)
                .background(IslandApprovalAppearance.raised)
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: IslandApprovalTypedMetrics.text(value, width: width - 24, code: true), alignment: .topLeading)
                .textSelection(.enabled).padding(12)
            if !caption.isEmpty {
                Rectangle().fill(IslandApprovalAppearance.border).frame(height: 1)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(muted).frame(width: 18, height: 18)
                    Text(caption).font(.system(size: 11, design: .monospaced)).foregroundStyle(secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: IslandApprovalTypedMetrics.text(caption, width: width - 50, code: true), alignment: .topLeading)
                        .textSelection(.enabled)
                }.padding(.horizontal, 12).padding(.vertical, 10)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(IslandApprovalAppearance.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IslandApprovalAppearance.border, lineWidth: 1))
    }
    private func destination(icon: String, name: String, subtitle: String, badge: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .regular)).foregroundStyle(secondary)
                .frame(width: 40, height: 40).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(height: IslandTaskTextMetrics.height(name, size: 14, semibold: true, width: width - 180), alignment: .topLeading)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(muted).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: IslandTaskTextMetrics.height(subtitle, width: width - 180), alignment: .topLeading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(badge).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
                .frame(width: 88).padding(.vertical, 5).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 5))
        }.padding(.horizontal, 14).frame(maxWidth: .infinity)
            .frame(height: IslandApprovalTypedMetrics.destinationHeight(name: name, subtitle: subtitle, width: width))
            .background(IslandApprovalAppearance.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IslandApprovalAppearance.border, lineWidth: 1))
    }
    private func step(_ number: Int, title: String, subtitle: String, complete: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                .font(.system(size: 20, weight: .light)).foregroundStyle(complete ? Color.white : secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity).frame(height: 64)
            .background(IslandApprovalAppearance.surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private var argumentsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").foregroundStyle(muted)
                Text(request.contextItem?["tool"].text ?? "").foregroundStyle(.white)
                Spacer()
                Text(t("工具参数", "Arguments")).foregroundStyle(muted)
            }.font(.system(size: 11, design: .monospaced)).padding(.horizontal, 12).frame(height: 36)
                .background(IslandApprovalAppearance.raised)
            ForEach(Array(IslandApprovalTypedMetrics.arguments(request).enumerated()), id: \.offset) { _, argument in
                HStack(alignment: .top, spacing: 16) {
                    Text(argument.0).foregroundStyle(muted).frame(width: 112, alignment: .leading)
                    Text(argument.1).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 11, design: .monospaced)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(height: max(IslandApprovalTypedMetrics.text(argument.0, width: 112, code: true),
                        IslandApprovalTypedMetrics.text(argument.1, width: width - 152, code: true)) + 20)
            }
        }.background(IslandApprovalAppearance.surface).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IslandApprovalAppearance.border, lineWidth: 1))
    }
    private func diffPanel(_ change: IslandApprovalJSON) -> some View {
        let lines = IslandApprovalTypedMetrics.diffText(change).components(separatedBy: "\n")
        let addedCount = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let removedCount = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").foregroundStyle(muted)
                    Text((change["path"].text as NSString).lastPathComponent).foregroundStyle(.white)
                    Spacer()
                    Text("+\(addedCount)  −\(removedCount)").foregroundStyle(secondary).monospaced()
                }.font(.system(size: 11, weight: .medium)).frame(height: 20)
                Text(change["path"].text).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(height: IslandApprovalTypedMetrics.text(change["path"].text, width: width - 24, code: true), alignment: .topLeading)
            }.padding(12).background(IslandApprovalAppearance.raised)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let added = line.hasPrefix("+") && !line.hasPrefix("+++")
                let removed = line.hasPrefix("-") && !line.hasPrefix("---")
                HStack(alignment: .top, spacing: 8) {
                    Text(added ? "+" : removed ? "−" : " ").foregroundStyle(secondary).frame(width: 10)
                    Text(added || removed ? String(line.dropFirst()) : line)
                        .foregroundStyle(line.hasPrefix("@@") || removed ? secondary : Color.white)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 11, design: .monospaced)).lineSpacing(2)
                    .padding(.horizontal, 12).padding(.vertical, 2)
                    .frame(minHeight: IslandApprovalTypedMetrics.text(line, width: width - 42, code: true) + 4)
                    .background(added ? Color(red: 0.045, green: 0.10, blue: 0.065)
                        : removed ? Color(red: 0.11, green: 0.06, blue: 0.06) : Color.clear)
            }
        }.padding(.bottom, 8).background(IslandApprovalAppearance.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IslandApprovalAppearance.border, lineWidth: 1))
    }
}

struct IslandApprovalActionStyle: ButtonStyle {
    let primary: Bool
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, primary: primary, destructive: destructive)
    }
    private struct Surface: View {
        let configuration: Configuration
        let primary: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        private var fill: Color {
            if enabled && destructive {
                return configuration.isPressed ? Color(red: 0.58, green: 0.16, blue: 0.17)
                    : hovered ? Color(red: 0.76, green: 0.22, blue: 0.23) : Color(red: 0.68, green: 0.18, blue: 0.19)
            }
            return Color(white: enabled && primary ? (configuration.isPressed ? 0.78 : hovered ? 0.90 : 1)
                : configuration.isPressed ? 0.16 : hovered && enabled ? 0.13 : 0.085)
        }
        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? (primary ? Color.black : Color.white) : IslandApprovalAppearance.muted)
                .background(fill, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(enabled && (primary || destructive) ? Color.clear : IslandApprovalAppearance.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10)).onHover { hovered = $0 }
        }
    }
}

// Allocate the complete action row to the actual buttons; absent actions leave no slot.
struct IslandApprovalActionLayout: Layout {
    private let spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? IslandVibeLayout.expandedWidth - 2 * IslandVibeLayout.listInset,
               height: subviews.isEmpty ? 0 : IslandApprovalMetrics.buttonHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }
        let available = max(0, bounds.width - CGFloat(count - 1) * spacing)
        var x = bounds.minX
        for (index, view) in subviews.enumerated() {
            // One fills the row, two split it equally, three use 3:3:4 with primary last.
            let fraction: CGFloat = count == 3 ? (index == 2 ? 0.4 : 0.3) : 1 / CGFloat(count)
            let width = index == count - 1 ? max(0, bounds.maxX - x) : available * fraction
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: width, height: IslandApprovalMetrics.buttonHeight))
            x += width + spacing
        }
    }
}
