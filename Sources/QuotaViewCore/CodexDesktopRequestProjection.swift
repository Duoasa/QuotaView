import Foundation

/// Public confirmation content only. Transcript text and reasoning never cross this boundary.
public struct CodexDesktopPendingRequestIdentity: Hashable, Sendable {
    public let turnID: String
    public let requestID: CodexDesktopIPCRequestID
    public let method: String

    public init(turnID: String, requestID: CodexDesktopIPCRequestID, method: String) {
        self.turnID = turnID; self.requestID = requestID; self.method = method
    }
}

public struct CodexDesktopProjectedRequest: Sendable {
    public let requestID: CodexDesktopIPCRequestID
    public let method: String
    public let turnID: String
    public let paramsData: Data
    public let envelopeData: Data
    public let userInputMode: CodexUserInputMode?
    public let contextItemData: Data?
    public var identity: CodexDesktopPendingRequestIdentity {
        .init(turnID: turnID, requestID: requestID, method: method)
    }
}

/// Async questions are agent-message questions, not app-server pending RPCs.
public struct CodexDesktopProjectedAsyncQuestion: Equatable, Sendable {
    public let questionItemID: String
    public let sourceItemID: String
    public let questionIndex: Int
    public let turnID: String
    public let question: String
    public let options: [String]
    public let resolvedAnswer: String?
    public var userInputMode: CodexUserInputMode { .asynchronous }

    /// Internal presentation envelope only; this is never a server-owned pending RPC.
    public func asyncRequestEnvelopeData(conversationID: String) throws -> Data {
        try PublicJSON.object([
            "id": .string(questionItemID), "method": .string("desktop/tool/requestUserInputAsync"),
            "params": .object(["threadId": .string(conversationID), "turnId": .string(turnID), "itemId": .string(sourceItemID),
                "questions": .array([.object(["id": .string(questionItemID), "question": .string(question),
                    "options": .array(options.map { .object(["label": .string($0), "description": .string("")]) }),
                    "isOther": .bool(true), "isSecret": .bool(false)])])])
        ]).encoded()
    }
}

/// Runtime wait evidence is distinct from a turn's inProgress status.
/// Missing or future flags never prove that an earlier wait has ended.
public enum CodexDesktopThreadWaitStatus: Equatable, Sendable {
    case unavailable
    case running
    case waiting(CodexActivityWaitReason)
}

public struct CodexDesktopInteractionProjection: Sendable {
    public let currentTurnID: String?
    public let status: String
    public let title: String
    public let sourceKind: CodexActivitySessionKind
    public let startedAt: Date?
    public let requests: [CodexDesktopProjectedRequest]
    public let authoritativePendingIdentities: Set<CodexDesktopPendingRequestIdentity>
    public let pendingRequestsAreAuthoritative: Bool
    public let asyncQuestions: [CodexDesktopProjectedAsyncQuestion]
    public let authoritativeAsyncQuestionIDs: Set<String>
    public let threadWaitStatus: CodexDesktopThreadWaitStatus

    public var provesNoPendingConfirmation: Bool {
        status == "inProgress" && pendingRequestsAreAuthoritative
            && threadWaitStatus == .running && authoritativePendingIdentities.isEmpty
    }

    public init(currentTurnID: String?, status: String, title: String,
                sourceKind: CodexActivitySessionKind, startedAt: Date?,
                requests: [CodexDesktopProjectedRequest],
                authoritativePendingIdentities: Set<CodexDesktopPendingRequestIdentity>,
                pendingRequestsAreAuthoritative: Bool,
                asyncQuestions: [CodexDesktopProjectedAsyncQuestion],
                authoritativeAsyncQuestionIDs: Set<String>,
                threadWaitStatus: CodexDesktopThreadWaitStatus = .unavailable) {
        self.currentTurnID = currentTurnID; self.status = status; self.title = title
        self.sourceKind = sourceKind; self.startedAt = startedAt; self.requests = requests
        self.authoritativePendingIdentities = authoritativePendingIdentities
        self.pendingRequestsAreAuthoritative = pendingRequestsAreAuthoritative
        self.asyncQuestions = asyncQuestions; self.authoritativeAsyncQuestionIDs = authoritativeAsyncQuestionIDs
        self.threadWaitStatus = threadWaitStatus
    }
}

public enum CodexDesktopRequestProjectionError: Error, Equatable {
    case oversizedState, malformedState, conversationMismatch, malformedRequests, ambiguousRequest
}

/// Schema references: Desktop conversation `requests` preserve `{id, method, params}`;
/// canonical turn history uses islands/entries/value and entitiesByKey. Async questions
/// use agentMessage.questions and accepted native question-reply steering messages.
public enum CodexDesktopRequestProjector {
    public static let maximumStateBytes = 8 * 1_048_576
    public static let maximumDesktopStateBytes = 64 * 1_048_576
    public static let maximumPendingRequests = 256
    public static let maximumAsyncQuestions = 256
    public static let asyncReplyOpeningTag = "<send_user_message_question_reply>"
    public static let asyncReplyClosingTag = "</send_user_message_question_reply>"

    public static func project(conversationID: String, conversationStateData: Data,
                               maximumBytes: Int = maximumStateBytes) throws -> CodexDesktopInteractionProjection {
        guard conversationStateData.count <= min(maximumBytes, maximumDesktopStateBytes) else { throw CodexDesktopRequestProjectionError.oversizedState }
        let json = try JSONDecoder().decode(DesktopIPCJSON.self, from: conversationStateData)
        return try project(conversationID: conversationID, state: json)
    }

    /// The live follower already owns a decoded, bounded tree. Reuse it without
    /// serializing and decoding the entire history for every streaming patch.
    static func project(conversationID: String, state json: DesktopIPCJSON) throws -> CodexDesktopInteractionProjection {
        guard let state = json.object else { throw CodexDesktopRequestProjectionError.malformedState }
        guard state["id"]?.string == conversationID else { throw CodexDesktopRequestProjectionError.conversationMismatch }
        let source = state["source"].flatMap { try? $0.foundationValue() }
        let kind = CodexActivitySessionKind.classify(source: source,
            threadSource: state["threadSource"]?.string ?? state["thread_source"]?.string)
        // Background memory state is observational; it cannot supply an owner
        // attachment, question content or a submission capability.
        let allRequests: [PublicJSON]
        if kind == .memoryConsolidation { allRequests = [] }
        else {
            guard let values = state["requests"]?.array, values.count <= maximumPendingRequests else {
                throw CodexDesktopRequestProjectionError.malformedRequests
            }
            allRequests = values
        }
        let current = currentTurn(state)
        let currentID = current.value?["turnId"]?.nonemptyString
        let rawStatus = current.value?["status"]?.string ?? "unknown"
        let status = ["inProgress", "completed", "interrupted", "failed"].contains(rawStatus) ? rawStatus : "unknown"
        let startedAt = current.value?["turnStartedAtMs"]?.finiteNumber.map { Date(timeIntervalSince1970: $0 / 1_000) }
        var requests: [CodexDesktopProjectedRequest] = []
        var identities = Set<CodexDesktopPendingRequestIdentity>()
        var requestIDs = Set<CodexDesktopIPCRequestID>()
        let items = current.value?["items"]?.array ?? []
        if let currentID, status == "inProgress" {
            for raw in allRequests {
                if case .bool(true)? = raw.object?["completed"] { continue }
                guard let object = raw.object, let method = object["method"]?.nonemptyString,
                      let requestID = object["id"]?.requestID else {
                    throw CodexDesktopRequestProjectionError.malformedRequests
                }
                // Native Desktop answers these service RPCs without presenting
                // user confirmation. Their parameters are not thread-scoped.
                if automaticServiceMethods.contains(method) { continue }
                guard let params = object["params"]?.object,
                      params["threadId"]?.string == conversationID else {
                    throw CodexDesktopRequestProjectionError.malformedRequests
                }
                // An old pending request cannot restore a prior turn after a newer turn is current.
                let originalTurnID = params["turnId"]?.nonemptyString
                guard originalTurnID == currentID || (originalTurnID == nil && method == "mcpServer/elicitation/request") else { continue }
                let identity = CodexDesktopPendingRequestIdentity(turnID: currentID, requestID: requestID, method: method)
                guard requestIDs.insert(requestID).inserted, identities.insert(identity).inserted else { throw CodexDesktopRequestProjectionError.ambiguousRequest }
                guard let allowed = allowedParams[method] else { continue }
                var publicParams = params.filter { allowed.contains($0.key) }
                // MCP's native request can be thread-scoped (`turnId: null`).
                // Presentation attaches to the owner-proven current turn; the
                // actor retains the original request unchanged for submission.
                if method == "mcpServer/elicitation/request", originalTurnID == nil {
                    publicParams["turnId"] = .string(currentID)
                }
                if method == "item/tool/requestUserInput", let questions = publicParams["questions"]?.array {
                    publicParams["questions"] = .array(questions.map(sanitizeQuestion))
                }
                let publicEnvelope = PublicJSON.object(["id": object["id"]!, "method": .string(method), "params": .object(publicParams)])
                let contextItem = fileContext(method: method, params: params, items: items)
                requests.append(.init(requestID: requestID, method: method, turnID: currentID,
                    paramsData: try PublicJSON.object(publicParams).encoded(), envelopeData: try publicEnvelope.encoded(),
                    userInputMode: method == "item/tool/requestUserInput" ? .synchronous : nil,
                    contextItemData: try contextItem?.encoded()))
            }
        }
        let questions = kind == .memoryConsolidation ? []
            : try currentID.map { try asyncQuestions(items: items, turnID: $0) } ?? []
        let pendingAsync = status == "inProgress" ? Set(questions.filter { $0.resolvedAnswer == nil }.map(\.questionItemID)) : []
        return .init(currentTurnID: currentID, status: status, title: state["title"]?.string ?? "", sourceKind: kind,
            startedAt: startedAt, requests: requests, authoritativePendingIdentities: identities,
            pendingRequestsAreAuthoritative: kind != .memoryConsolidation && current.authoritative && currentID != nil && status != "unknown",
            asyncQuestions: questions, authoritativeAsyncQuestionIDs: pendingAsync,
            threadWaitStatus: threadWaitStatus(state))
    }

    private static func threadWaitStatus(_ state: [String: PublicJSON]) -> CodexDesktopThreadWaitStatus {
        guard let runtime = state["threadRuntimeStatus"]?.object,
              runtime["type"]?.string == "active", let rawFlags = runtime["activeFlags"]?.array,
              rawFlags.allSatisfy({ $0.string != nil }) else { return .unavailable }
        let flags = Set(rawFlags.compactMap(\.string))
        guard flags.isSubset(of: ["waitingOnApproval", "waitingOnUserInput"]) else { return .unavailable }
        if flags.contains("waitingOnUserInput") { return .waiting(.userInput) }
        if flags.contains("waitingOnApproval") { return .waiting(.approval) }
        return .running
    }

    private static let automaticServiceMethods: Set<String> = [
        "account/chatgptAuthTokens/refresh", "attestation/generate", "currentTime/read"
    ]
    private static let commonParams: Set<String> = ["threadId", "turnId", "itemId", "reason"]
    private static let allowedParams: [String: Set<String>] = [
        "item/commandExecution/requestApproval": commonParams.union(["command", "cwd", "kind", "commandActions", "availableDecisions", "proposedExecpolicyAmendment", "proposedNetworkPolicyAmendment", "proposedNetworkPolicyAmendments", "networkApprovalContext", "additionalPermissions"]),
        "item/fileChange/requestApproval": commonParams.union(["grantRoot", "availableDecisions"]),
        "item/permissions/requestApproval": commonParams.union(["environmentId", "cwd", "permissions"]),
        "item/tool/requestUserInput": commonParams.union(["questions", "autoResolutionMs"]),
        "mcpServer/elicitation/request": commonParams.union(["serverName", "mode", "message", "description", "requestedSchema", "url", "elicitationId", "_meta"])
    ]

    private static func sanitizeQuestion(_ question: PublicJSON) -> PublicJSON {
        guard let object = question.object else { return .null }
        let fields: Set<String> = ["id", "header", "question", "options", "isOther", "isSecret", "multiSelect"]
        var result = object.filter { fields.contains($0.key) }
        if let options = object["options"]?.array {
            result["options"] = .array(options.map { option in
                guard let object = option.object else { return option }
                return .object(object.filter { ["id", "label", "description"].contains($0.key) })
            })
        }
        return .object(result)
    }

    private static func fileContext(method: String, params: [String: PublicJSON], items: [PublicJSON]) -> PublicJSON? {
        guard method == "item/fileChange/requestApproval", let itemID = params["itemId"]?.string,
              let item = items.first(where: { $0.object?["id"]?.string == itemID && $0.object?["type"]?.string == "fileChange" })?.object else { return nil }
        var publicItem = item.filter { ["id", "type", "status"].contains($0.key) }
        if let changes = item["changes"]?.array {
            publicItem["changes"] = .array(changes.map { change in
                guard let object = change.object else { return .null }
                return .object(object.filter { ["path", "kind", "diff"].contains($0.key) })
            })
        }
        return .object(publicItem)
    }

    private static func currentTurn(_ state: [String: PublicJSON]) -> (value: [String: PublicJSON]?, authoritative: Bool) {
        let live = state["turns"]?.array?.compactMap(\.object) ?? []
        if let historyWrapper = state["turnHistory"]?.object, historyWrapper["kind"]?.string == "canonical" {
            guard let history = historyWrapper["history"]?.object, let lastIsland = history["islands"]?.array?.last?.object,
                  lastIsland["newerBoundary"]?.object?["status"]?.string == "exhausted",
                  let entries = lastIsland["entries"]?.array, let entities = history["entitiesByKey"]?.object else { return (nil, false) }
            var canonicalTurns: [[String: PublicJSON]] = []
            for entry in entries {
                // Native canonical entries are turn references, not optional
                // display rows. A missing tail entity cannot make an older turn
                // authoritative for settlement or completion/unfollow.
                guard let key = entry.object?["value"]?.nonemptyString, let turn = entities[key]?.object,
                      turn["turnId"]?.nonemptyString != nil else { return (nil, false) }
                canonicalTurns.append(turn)
            }
            guard let canonical = canonicalTurns.last, let id = canonical["turnId"]?.nonemptyString else {
                return (live.last(where: { $0["turnId"]?.nonemptyString != nil }), true)
            }
            // Native zR/Jm inserts unmatched live prefixes before their next
            // canonical anchor and appends the remaining suffix after history.
            // Ordering comes from this owner state, not optional start times.
            let allCanonicalIDs = Set(history["islands"]?.array?.flatMap { island in
                island.object?["entries"]?.array?.compactMap { entry in
                    entry.object?["value"]?.string.flatMap { entities[$0]?.object?["turnId"]?.nonemptyString }
                } ?? []
            } ?? [])
            var suffix: [[String: PublicJSON]] = []
            for turn in live {
                if let liveID = turn["turnId"]?.nonemptyString, allCanonicalIDs.contains(liveID) {
                    suffix.removeAll()
                } else {
                    let errorIsEmpty: Bool
                    switch turn["error"] { case nil, .null?: errorIsEmpty = true; default: errorIsEmpty = false }
                    // Native Km drops only the empty completed placeholder.
                    if turn["turnId"]?.nonemptyString == nil && turn["turnStartedAtMs"]?.finiteNumber == nil
                        && turn["status"]?.string == "completed" && errorIsEmpty
                        && (turn["items"]?.array ?? []).isEmpty { continue }
                    suffix.append(turn)
                }
            }
            if let lastLive = suffix.last {
                guard lastLive["turnId"]?.nonemptyString != nil else { return (nil, false) }
                return (lastLive, true)
            }
            guard let overlay = live.last(where: { $0["turnId"]?.string == id }) else { return (canonical, true) }
            var merged = canonical.merging(overlay) { _, incoming in incoming }
            // Native Gue's normal live merge accepts the incoming status.
            // Its pagination/reconnect overlay retains an existing terminal
            // state; an unpaginated live turn can legitimately become active.
            if canonical["status"]?.string != "inProgress", overlay["status"]?.string == "inProgress",
               canonical["itemsPagination"]?.object != nil || overlay["itemsPagination"]?.object != nil {
                merged["status"] = canonical["status"]
            }
            if canonical["turnStartedAtMs"]?.finiteNumber != nil {
                merged["turnStartedAtMs"] = canonical["turnStartedAtMs"]
            }
            let existingItems = canonical["items"]?.array ?? []
            let incomingItems = overlay["items"]?.array ?? []
            let existingIDs = Set(existingItems.compactMap { $0.object?["id"]?.nonemptyString })
            let incomingByID = Dictionary(incomingItems.compactMap { item -> (String, PublicJSON)? in
                item.object?["id"]?.nonemptyString.map { ($0, item) }
            }, uniquingKeysWith: { _, newest in newest })
            merged["items"] = .array(existingItems.map { incomingByID[$0.object?["id"]?.string ?? ""] ?? $0 }
                + incomingItems.filter { !existingIDs.contains($0.object?["id"]?.string ?? "") })
            return (merged, true)
        }
        return (live.reversed().first(where: { $0["turnId"]?.nonemptyString != nil }), state["turns"]?.array != nil)
    }

    private static func asyncQuestions(items: [PublicJSON], turnID: String) throws -> [CodexDesktopProjectedAsyncQuestion] {
        var questions: [CodexDesktopProjectedAsyncQuestion] = []
        var questionIndices: [String: Int] = [:]
        var answered: [String: String] = [:]
        for (itemIndex, value) in items.enumerated() {
            guard let item = value.object else { continue }
            if item["type"]?.string == "agentMessage", let sourceID = item["id"]?.nonemptyString,
               let rawQuestions = item["questions"]?.array {
                for (index, rawQuestion) in rawQuestions.enumerated() {
                    guard questions.count < maximumAsyncQuestions else { throw CodexDesktopRequestProjectionError.oversizedState }
                    guard let question = rawQuestion.object, let title = question["title"]?.nonemptyString else { continue }
                    let identity = String(decoding: try PublicJSON.array([.string("request_user_input_async"), .string(sourceID), .integer(Int64(index))]).encoded(), as: UTF8.self)
                    guard questionIndices[identity] == nil else { throw CodexDesktopRequestProjectionError.ambiguousRequest }
                    let rawOptions = question["options"]?.array ?? []
                    guard rawOptions.allSatisfy({ $0.string != nil }) else { continue }
                    questionIndices[identity] = itemIndex
                    questions.append(.init(questionItemID: identity, sourceItemID: sourceID, questionIndex: index,
                        turnID: turnID, question: title, options: rawOptions.compactMap(\.string), resolvedAnswer: nil))
                }
            }
            let type = item["type"]?.string
            guard type == "userMessage" || (type == "steeringUserMessage" && item["status"]?.string == "accepted"),
                  let input = item[type == "userMessage" ? "content" : "input"]?.array, input.count == 1,
                  input[0].object?["type"]?.string == "text", let text = input[0].object?["text"]?.string,
                  let replies = questionReplies(text) else { continue }
            for reply in replies {
                guard let originalIndex = questionIndices[reply.id], originalIndex < itemIndex,
                      questions.contains(where: { $0.questionItemID == reply.id && $0.question == reply.question }) else { continue }
                answered[reply.id] = reply.answer
            }
        }
        return questions.map { .init(questionItemID: $0.questionItemID, sourceItemID: $0.sourceItemID, questionIndex: $0.questionIndex,
            turnID: $0.turnID, question: $0.question, options: $0.options, resolvedAnswer: answered[$0.questionItemID]) }
    }

    private static func questionReplies(_ text: String) -> [(id: String, question: String, answer: String)]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(asyncReplyOpeningTag), trimmed.hasSuffix(asyncReplyClosingTag) else { return nil }
        let body = trimmed.dropFirst(asyncReplyOpeningTag.count).dropLast(asyncReplyClosingTag.count)
        guard let json = try? JSONDecoder().decode(PublicJSON.self, from: Data(body.utf8)) else { return nil }
        let replies = json.array ?? (json.object != nil ? [json] : [])
        guard !replies.isEmpty, replies.count <= maximumAsyncQuestions else { return nil }
        var result: [(String, String, String)] = []
        for reply in replies {
            guard let object = reply.object, let id = object["questionItemId"]?.string,
                  let question = object["question"]?.string, let answer = object["answer"]?.string else { return nil }
            result.append((id, question, answer))
        }
        return result
    }
}

// Share the transport's value tree; these helpers encode only the small public
// request envelopes after projection, never the complete conversation history.
private typealias PublicJSON = DesktopIPCJSON

private extension DesktopIPCJSON {
    var nonemptyString: String? { string.flatMap { $0.isEmpty ? nil : $0 } }
    var finiteNumber: Double? {
        switch self { case .integer(let v): return Double(v); case .number(let v): return v; default: return nil }
    }
    var requestID: CodexDesktopIPCRequestID? {
        switch self { case .integer(let v): return .integer(v); case .string(let v) where !v.isEmpty: return .string(v); default: return nil }
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    func foundationValue() throws -> Any { try JSONSerialization.jsonObject(with: encoded(), options: [.fragmentsAllowed]) }
}
