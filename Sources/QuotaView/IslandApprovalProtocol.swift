import Foundation
import QuotaViewCore

// Typed protocol adapter. Unknown decisions never produce an approval action.
indirect enum IslandApprovalJSON: Codable, Equatable, Sendable {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([Self].self) { self = .array(v) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    init(any: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed])
        self = try JSONDecoder().decode(Self.self, from: data)
    }
    subscript(_ key: String) -> Self { object?[key] ?? .null }
    var object: [String: Self]? { if case .object(let v) = self { v } else { nil } }
    var array: [Self] { if case .array(let v) = self { v } else { [] } }
    var text: String { if case .string(let v) = self { v } else { "" } }
    var boolean: Bool { if case .bool(let v) = self { v } else { false } }
    var number: Double? { if case .number(let v) = self { v } else { nil } }
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    var pretty: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

struct IslandApprovalAction: Identifiable, Equatable {
    var id: String
    var label: IslandDetailText
    var result: IslandApprovalJSON
    var affirmative: Bool
}
struct IslandApprovalQuestion: Identifiable, Equatable {
    var id: String
    var title: String
    var options: [IslandApprovalJSON]
    var other: Bool
    var secret: Bool
    var multiple: Bool = false
    var allowsCustomAnswer: Bool { other || options.isEmpty }
    var header: String = ""
}
struct IslandApprovalField: Identifiable, Equatable {
    var id: String
    var schema: IslandApprovalJSON
    var required: Bool
    var title: String { schema["title"].text.isEmpty ? id : schema["title"].text }
    var choices: [IslandApprovalJSON] {
        let direct = schema["enum"].array
        if !direct.isEmpty { return direct }
        let titled = schema["oneOf"].array
        if !titled.isEmpty { return titled.map { $0["const"] } }
        let items = schema["items"]["enum"].array
        return items.isEmpty ? schema["items"]["anyOf"].array.map { $0["const"] } : items
    }
    func label(for choice: IslandApprovalJSON) -> String {
        let titled = schema["oneOf"].array + schema["items"]["anyOf"].array
        if let title = titled.first(where: { $0["const"] == choice })?["title"].text, !title.isEmpty { return title }
        if let index = schema["enum"].array.firstIndex(of: choice),
           schema["enumNames"].array.indices.contains(index),
           !schema["enumNames"].array[index].text.isEmpty { return schema["enumNames"].array[index].text }
        return choice.text.isEmpty ? choice.pretty : choice.text
    }
    var supported: Bool {
        // External backtracking regexes have no enforceable computation budget.
        // Preserve their constraint through Codex's UI instead of evaluating
        // them on MainActor or silently ignoring them when approving a form.
        if schema["pattern"] != .null { return false }
        if ["allOf", "anyOf", "$ref", "not", "if", "then", "else"].contains(where: { schema[$0] != .null }) { return false }
        if schema["oneOf"] != .null && (schema["type"].text != "string"
            || schema["oneOf"].array.isEmpty || schema["oneOf"].array.contains(where: { $0["const"].text.isEmpty })) { return false }
        return switch schema["type"].text {
        case "string", "number", "integer", "boolean": true
        case "array": !choices.isEmpty && choices.allSatisfy { !$0.text.isEmpty }
        default: false
        }
    }
}
struct IslandApprovalPermission: Identifiable, Equatable {
    var id: String
    var title: String
    var value: IslandApprovalJSON
    var group: String
}

struct IslandCodexApprovalRequest: Equatable {
    enum Kind: String, CaseIterable {
        case command, terminalInput, fileChange, network, permissions, questions, mcpForm, mcpURL, nativeOnly
        var title: IslandDetailText {
            switch self {
            case .command: .init("执行命令", "Run command")
            case .terminalInput: .init("终端输入", "Terminal input")
            case .fileChange: .init("修改文件", "Change files")
            case .network: .init("网络访问", "Network access")
            case .permissions: .init("访问权限", "Access permissions")
            case .questions: .init("回答问题", "Answer questions")
            case .mcpForm: .init("工具表单", "Tool form")
            case .mcpURL: .init("外部授权", "External authorization")
            case .nativeOnly: .init("在 Codex 中处理", "Continue in Codex")
            }
        }
    }
    let raw: Data
    let envelope: IslandApprovalJSON
    let rpcIdentity: CodexDesktopIPCRequestID
    /// A public rollout projection has no RPC owner and can never send a reply.
    private(set) var localObservation: LocalObservation?
    /// An opaque capability minted by the Desktop owner stream, never decoded
    /// from a public JSON envelope or a local rollout projection.
    private(set) var desktopHandle: CodexDesktopIPCRequestHandle? = nil
    struct LocalObservation: Equatable {
        let sessionHash: String; let turnHash: String; let callID: String
        let mode: CodexUserInputMode
        var asynchronous: Bool { mode == .asynchronous }
    }
    var userInputMode: CodexUserInputMode? {
        method == "desktop/tool/requestUserInputAsync" ? .asynchronous : localObservation?.mode
    }
    var observationOnly: Bool { localObservation != nil }
    var contextItem: IslandApprovalJSON? = nil
    var params: IslandApprovalJSON { envelope["params"] }
    var rpcID: IslandApprovalJSON { envelope["id"] }
    var key: String {
        guard let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let id = object["id"],
              let data = try? JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    var threadID: String { params["threadId"].text }
    var turnID: String { params["turnId"].text }
    var method: String { envelope["method"].text }
    var answerContent: IslandApprovalJSON {
        let common: Set<String> = ["threadId", "turnId", "itemId", "reason"]
        let fields: Set<String>
        switch kind {
        case .command, .terminalInput, .network:
            fields = common.union(["command", "cwd", "kind", "commandActions", "availableDecisions",
                "proposedExecpolicyAmendment", "proposedNetworkPolicyAmendment", "proposedNetworkPolicyAmendments",
                "networkApprovalContext", "additionalPermissions"])
        case .fileChange: fields = common.union(["grantRoot", "availableDecisions"])
        case .permissions: fields = common.union(["environmentId", "cwd", "permissions"])
        case .questions: fields = common.union(["questions", "autoResolutionMs"])
        case .mcpForm, .mcpURL:
            fields = common.union(["serverName", "mode", "message", "description", "requestedSchema", "url", "elicitationId", "_meta"])
        case .nativeOnly: fields = Set(params.object?.keys.map { $0 } ?? [])
        }
        // Owner projection removes unrelated fields from observed envelopes.
        // Gaining its response handle is not an answer-content revision.
        let content = IslandApprovalJSON.object((params.object ?? [:]).filter { fields.contains($0.key) })
        let context: IslandApprovalJSON = [.fileChange, .questions, .mcpForm, .mcpURL].contains(kind)
            ? contextItem ?? .null : .null
        return .object(["method": .string(method), "params": content, "context": context])
    }
    var kind: Kind {
        switch method {
        case "item/commandExecution/requestApproval":
            if params["networkApprovalContext"].object != nil { return .network }
            return params["kind"].text == "writeStdin" ? .terminalInput : .command
        case "item/fileChange/requestApproval": return .fileChange
        case "item/permissions/requestApproval": return .permissions
        case "item/tool/requestUserInput", "local/tool/requestUserInput", "local/tool/requestUserInputAsync", "desktop/tool/requestUserInputAsync": return .questions
        case "mcpServer/elicitation/request":
            if params["mode"].text == "url" { return .mcpURL }
            return ["form", "openai/form", "openaiForm"].contains(params["mode"].text) ? .mcpForm : .nativeOnly
        default: return .nativeOnly
        }
    }
    init(data: Data) throws {
        guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
        let v = try JSONDecoder().decode(IslandApprovalJSON.self, from: data)
        guard v.object != nil, v["params"].object != nil, !v["params"]["threadId"].text.isEmpty,
              let identity = CodexSharedMessageIdentity.rpcID(messageData: data) else { throw CocoaError(.fileReadCorruptFile) }
        raw = data; envelope = v; rpcIdentity = identity
        localObservation = ["local/tool/requestUserInput", "local/tool/requestUserInputAsync"].contains(v["method"].text)
            ? .init(sessionHash: v["params"]["threadId"].text, turnHash: v["params"]["turnId"].text,
                callID: v["id"].text, mode: v["method"].text == "local/tool/requestUserInputAsync" ? .asynchronous : .synchronous)
            : nil
    }
    init(localQuestions: [[String: Any]], callID: String, sessionHash: String, turnHash: String, asynchronous: Bool = false) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "method": asynchronous ? "local/tool/requestUserInputAsync" : "local/tool/requestUserInput", "id": callID,
            "params": ["threadId": sessionHash, "turnId": turnHash, "itemId": callID, "questions": localQuestions]
        ], options: [.sortedKeys])
        self = try Self(data: data)
        localObservation = .init(sessionHash: sessionHash, turnHash: turnHash, callID: callID, mode: asynchronous ? .asynchronous : .synchronous)
    }
    func attachingDesktopHandle(_ handle: CodexDesktopIPCRequestHandle?) -> Self {
        var copy = self
        // The caller must correlate an actor-issued handle with its exact
        // projected request. Local question IDs never obtain a write capability.
        guard !observationOnly, let handle, handle.conversationID == threadID,
              handle.turnID == turnID, handle.method == method,
              let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let id = object["id"], let encoded = try? JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed]),
              let originalID = try? JSONDecoder().decode(CodexDesktopIPCRequestID.self, from: encoded),
              originalID == handle.requestID else { return copy }
        copy.desktopHandle = handle
        return copy
    }
    init(desktopAsyncQuestion question: CodexDesktopProjectedAsyncQuestion, conversationID: String) throws {
        let data = try question.asyncRequestEnvelopeData(conversationID: conversationID)
        self = try Self(data: data)
    }
    var titleText: IslandDetailText {
        for title in [questions.first?.title ?? "", params["message"].text, params["reason"].text] where !title.isEmpty { return .init(title) }
        return .init("Codex 请求你的处理", "Codex requests your input")
    }
    var detailText: IslandDetailText {
        if kind == .fileChange, contextItem?["changes"].array.isEmpty != false, params["grantRoot"].text.isEmpty {
            return .init("Codex 未提供文件差异，请在 Codex 中审阅后批准。", "Codex has not supplied the file diff. Review it in Codex before approving.")
        }
        return .init(detail)
    }
    var detail: String {
        switch kind {
        case .command, .terminalInput: return params["command"].text
        case .network:
            let n = params["networkApprovalContext"]
            return n["protocol"].text + " · " + n["host"].text
        case .fileChange:
            let changes = contextItem?["changes"].array ?? []
            if !changes.isEmpty {
                return changes.map { $0["path"].text + "\n" + ($0["diff"].text.isEmpty ? $0["diff"]["text"].text : $0["diff"].text) }.joined(separator: "\n\n")
            }
            return params["grantRoot"].text.isEmpty ? "Codex has not supplied the file diff. Review it in Codex before approving." : params["grantRoot"].text
        case .permissions: return params["cwd"].text
        case .questions: return ""
        case .nativeOnly: return ""
        case .mcpForm, .mcpURL: return params["message"].text.isEmpty ? params["description"].text : params["message"].text
        }
    }
    var context: String {
        [params["reason"].text, params["cwd"].text, params["serverName"].text,
         params["proposedExecpolicyAmendment"].array.isEmpty ? "" : "Remembered command rule: " + params["proposedExecpolicyAmendment"].array.map(\.text).joined(separator: " "),
         params["additionalPermissions"].object == nil ? "" : params["additionalPermissions"].pretty]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
    var questions: [IslandApprovalQuestion] {
        params["questions"].array.map {
            .init(id: $0["id"].text, title: $0["question"].text, options: $0["options"].array,
                  other: $0["isOther"].boolean, secret: $0["isSecret"].boolean, multiple: $0["multiSelect"].boolean, header: $0["header"].text)
        }
    }
    var supportedQuestions: Bool {
        !questions.isEmpty && questions.count <= 32
            && Set(questions.map(\.id)).count == questions.count
            && questions.allSatisfy { q in
                !q.id.isEmpty && !q.title.isEmpty && !q.multiple
                    && q.options.allSatisfy { !$0["label"].text.isEmpty }
                    && Set(q.options.map { $0["label"].text }).count == q.options.count
            }
    }
    /// Native synchronous Skip responds with an empty answer collection.
    /// Async Skip is only a local dismissal and must never send an empty answer.
    var questionSkipResult: IslandApprovalJSON? {
        guard kind == .questions, method == "item/tool/requestUserInput", supportedQuestions else { return nil }
        return .object(["answers": .object([:])])
    }
    var fields: [IslandApprovalField] {
        let schema = params["requestedSchema"]
        let required = Set(schema["required"].array.map(\.text))
        return (schema["properties"].object ?? [:]).keys.sorted().map {
            .init(id: $0, schema: schema["properties"][$0], required: required.contains($0))
        }
    }
    var supportedForm: Bool {
        let schema = params["requestedSchema"]
        return schema["type"].text == "object" && fields.count <= 32
            && (schema.object?.keys.contains("properties") != true || schema["properties"].object != nil)
            && fields.allSatisfy(\.supported)
            && Set(schema["required"].array.map(\.text)).isSubset(of: Set(fields.map(\.id)))
            && !["allOf", "anyOf", "oneOf", "$ref", "not", "if", "then", "else"].contains(where: { schema[$0] != .null })
    }
    /// MCP uses form mode for both parameter entry and consent-only requests.
    /// The schema, rather than the message or server name, determines whether
    /// there is anything to fill in. Unsupported schemas never gain approval UI.
    var isApprovalOnlyForm: Bool { kind == .mcpForm && supportedForm && fields.isEmpty }
    var permissions: [IslandApprovalPermission] {
        let p = params["permissions"]; var result: [IslandApprovalPermission] = []
        if p["network"]["enabled"].boolean {
            result.append(.init(id: "network", title: "Network", value: p["network"], group: "network"))
        }
        for group in ["read", "write"] {
            for value in p["fileSystem"][group].array {
                result.append(.init(id: permissionID(group, value), title: "\(group) · \(value.text)", value: value, group: group))
            }
        }
        for value in p["fileSystem"]["entries"].array {
            let path = value["path"]
            let title = path["path"].text.isEmpty ? (path["pattern"].text.isEmpty ? path["value"].pretty : path["pattern"].text) : path["path"].text
            result.append(.init(id: permissionID("entries", value), title: value["access"].text + " · " + title, value: value, group: "entries"))
        }
        return result
    }
    private func permissionID(_ group: String, _ value: IslandApprovalJSON) -> String {
        group + ":" + CodexActivityPrivacy.hashIdentifier(value.pretty)
    }
    var url: URL? {
        guard let url = URL(string: params["url"].text), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    /// Codex 0.159.2 command/file response enums are implicit in its Desktop
    /// protocol: those native params do not carry availableDecisions. This
    /// compatibility default belongs only to an actor-issued owner request.
    /// Explicit future decision lists, including empty/unknown lists, win.
    private var approvalDecisions: [IslandApprovalJSON] {
        if params.object?.keys.contains("availableDecisions") == true {
            return params["availableDecisions"].array
        }
        guard desktopHandle?.kind == .serverRequest,
              ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(method) else { return [] }
        var decisions: [IslandApprovalJSON] = [.string("accept"), .string("acceptForSession")]
        if method == "item/commandExecution/requestApproval" {
            let amendment = params["proposedExecpolicyAmendment"]
            if case .array(let parts) = amendment, !parts.isEmpty,
               parts.allSatisfy({ if case .string(let part) = $0 { return !part.isEmpty }; return false }) {
                decisions.append(.object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": amendment])]))
            }
            for amendment in params["proposedNetworkPolicyAmendments"].array {
                guard amendment.object != nil, ["allow", "deny"].contains(amendment["action"].text),
                      !amendment["host"].text.isEmpty else { continue }
                decisions.append(.object(["applyNetworkPolicyAmendment": .object(["network_policy_amendment": amendment])]))
            }
        }
        return decisions + [.string("decline"), .string("cancel")]
    }
    var actions: [IslandApprovalAction] {
        switch kind {
        case .command, .terminalInput, .network, .fileChange:
            let decisions = approvalDecisions
            return decisions.enumerated().compactMap { i, d in
                let label: IslandDetailText; let positive: Bool
                switch d.text {
                case "accept": label = .init("允许一次", "Allow once"); positive = true
                case "acceptForSession": label = .init("本会话允许", "Allow for session"); positive = true
                case "decline": label = .init("拒绝", "Decline"); positive = false
                case "cancel": label = .init("取消本次", "Cancel"); positive = false
                default:
                    guard method == "item/commandExecution/requestApproval" else { return nil }
                    if d["acceptWithExecpolicyAmendment"].object != nil {
                        label = .init("允许并记住命令规则", "Allow and remember command"); positive = true
                    } else if d["applyNetworkPolicyAmendment"].object != nil {
                        positive = d["applyNetworkPolicyAmendment"]["network_policy_amendment"]["action"].text == "allow"
                        label = positive ? .init("允许并记住网络规则", "Allow and remember host") : .init("拒绝并记住网络规则", "Deny and remember host")
                    } else { return nil }
                }
                return .init(id: "decision-\(i)", label: label, result: .object(["decision": d]), affirmative: positive)
            }
        case .permissions:
            return [.init(id: "deny", label: .init("不授予", "Deny"), result: .object(["permissions": .object([:]), "scope": .string("turn")]), affirmative: false)]
        case .questions: return []
        case .nativeOnly: return []
        case .mcpForm, .mcpURL:
            return ["decline", "cancel"].map {
                .init(id: $0, label: $0 == "decline" ? .init("拒绝", "Decline") : .init("取消", "Cancel"),
                    result: .object(["action": .string($0), "content": .null, "_meta": .null]), affirmative: false)
            }
        }
    }

    func permits(_ result: IslandApprovalJSON) -> Bool {
        guard !observationOnly else { return false }
        if actions.contains(where: { $0.result == result }) { return true }
        if let skip = questionSkipResult, result == skip { return true }
        var draft = IslandApprovalDraft()
        switch kind {
        case .questions:
            guard supportedQuestions, let answers = result["answers"].object, Set(answers.keys) == Set(questions.map(\.id)) else { return false }
            for q in questions {
                guard let list = answers[q.id]?["answers"].array, list.count == 1, !list[0].text.isEmpty else { return false }
                if q.options.contains(where: { $0["label"].text == list[0].text }) { draft.selections[q.id] = [list[0].text] }
                else { draft.values[q.id] = list[0].text }
            }
        case .permissions:
            guard ["turn", "session"].contains(result["scope"].text) else { return false }
            draft.sessionScope = result["scope"].text == "session"
            var chosen: Set<String> = []
            for permission in permissions {
                if permission.group == "network" && result["permissions"]["network"] == permission.value { chosen.insert(permission.id) }
                else if result["permissions"]["fileSystem"][permission.group].array.contains(permission.value) { chosen.insert(permission.id) }
            }
            draft.selections["permissions"] = chosen
        case .mcpForm:
            guard result["action"].text == "accept", let content = result["content"].object else { return false }
            for field in fields {
                if let value = content[field.id] {
                    if field.schema["type"].text == "array" { draft.selections[field.id] = Set(value.array.map(\.pretty)) }
                    else { draft.values[field.id] = value.text.isEmpty ? value.pretty : value.text }
                }
            }
        case .mcpURL: draft.openedURL = true
        default: return false
        }
        return draft.result(for: self) == result
    }
}

struct IslandApprovalDraft: Equatable {
    var values: [String: String] = [:]
    var selections: [String: Set<String>] = [:]
    var sessionScope = false
    var openedURL = false
    var decisionID: String? = nil
    var customAnswers: Set<String> = []

    mutating func selectAnswer(_ label: String, for question: IslandApprovalQuestion) {
        guard question.options.contains(where: { $0["label"].text == label }) else { return }
        selections[question.id] = [label]
        customAnswers.remove(question.id)
    }
    mutating func selectCustomAnswer(for question: IslandApprovalQuestion) {
        guard question.allowsCustomAnswer else { return }
        selections[question.id] = []
        customAnswers.insert(question.id)
    }
    mutating func setAnswer(_ text: String, for question: IslandApprovalQuestion) {
        guard question.allowsCustomAnswer else { return }
        selectCustomAnswer(for: question)
        values[question.id] = text
    }
    func usesCustomAnswer(for question: IslandApprovalQuestion) -> Bool {
        customAnswers.contains(question.id)
            || ((selections[question.id] ?? []).isEmpty && !(values[question.id] ?? "").isEmpty)
    }
    func answer(for question: IslandApprovalQuestion) -> String? {
        let selected = selections[question.id] ?? []
        let allowed = Set(question.options.map { $0["label"].text })
        guard selected.count <= 1, selected.isSubset(of: allowed) else { return nil }
        if let answer = selected.first, !answer.isEmpty { return answer }
        let text = values[question.id] ?? ""
        guard question.allowsCustomAnswer, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    func result(for request: IslandCodexApprovalRequest) -> IslandApprovalJSON? {
        switch request.kind {
        case .questions:
            guard request.supportedQuestions else { return nil }
            var answers: [String: IslandApprovalJSON] = [:]
            for q in request.questions {
                guard let answer = answer(for: q) else { return nil }
                answers[q.id] = .object(["answers": .array([.string(answer)])])
            }
            return .object(["answers": .object(answers)])
        case .permissions:
            let selected = selections["permissions"] ?? []; var grants: [String: IslandApprovalJSON] = [:]
            let chosen = request.permissions.filter { selected.contains($0.id) }
            guard !chosen.isEmpty else { return nil }
            if let network = chosen.first(where: { $0.group == "network" }) { grants["network"] = network.value }
            var fs: [String: IslandApprovalJSON] = [:]
            for group in ["read", "write", "entries"] {
                let paths = chosen.filter { $0.group == group }.map(\.value)
                if !paths.isEmpty { fs[group] = .array(paths) }
            }
            if !fs.isEmpty { grants["fileSystem"] = .object(fs) }
            return .object(["permissions": .object(grants), "scope": .string(sessionScope ? "session" : "turn")])
        case .mcpForm:
            guard request.supportedForm else { return nil }
            var content: [String: IslandApprovalJSON] = [:]
            for field in request.fields {
                let raw = values[field.id] ?? ""
                let selected = selections[field.id] ?? []
                if raw.isEmpty && selected.isEmpty && !field.required { continue }
                let value: IslandApprovalJSON
                switch field.schema["type"].text {
                case "boolean":
                    guard raw == "true" || raw == "false" else { return nil }; value = .bool(raw == "true")
                case "number", "integer":
                    guard let n = Double(raw), n.isFinite, field.schema["type"].text != "integer" || n.rounded() == n else { return nil }
                    if let min = field.schema["minimum"].number, n < min { return nil }
                    if let max = field.schema["maximum"].number, n > max { return nil }
                    value = .number(n)
                case "array":
                    let choices = field.choices.filter { selected.contains($0.pretty) }
                    if field.required && choices.isEmpty { return nil }
                    if let min = field.schema["minItems"].number, Double(choices.count) < min { return nil }
                    if let max = field.schema["maxItems"].number, Double(choices.count) > max { return nil }
                    guard selected.count == choices.count else { return nil }
                    value = .array(choices)
                default:
                    if field.required && raw.isEmpty { return nil }
                    if let min = field.schema["minLength"].number, Double(raw.count) < min { return nil }
                    if let max = field.schema["maxLength"].number, Double(raw.count) > max { return nil }
                    switch field.schema["format"].text {
                    case "email":
                        guard raw.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else { return nil }
                    case "uri": guard let url = URL(string: raw), url.scheme != nil else { return nil }
                    case "date":
                        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
                        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
                    case "date-time":
                        let formatter = ISO8601DateFormatter()
                        if formatter.date(from: raw) == nil {
                            formatter.formatOptions.insert(.withFractionalSeconds)
                            guard formatter.date(from: raw) != nil else { return nil }
                        }
                    default: break
                    }
                    value = .string(raw)
                }
                if !field.schema["enum"].array.isEmpty && !field.schema["enum"].array.contains(value) { return nil }
                if field.schema["type"].text != "array" && !field.choices.isEmpty && !field.choices.contains(value) { return nil }
                content[field.id] = value
            }
            return .object(["action": .string("accept"), "content": .object(content), "_meta": .null])
        case .mcpURL:
            return openedURL && request.url != nil ? .object(["action": .string("accept"), "content": .null, "_meta": .null]) : nil
        default: return nil
        }
    }
}
