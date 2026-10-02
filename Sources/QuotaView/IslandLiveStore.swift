import AppKit
import Foundation
import QuotaViewCore

/// Identity, ordering and request lifecycle are independent of presentation/focus.
/// Shared Desktop connections are observers until response ownership is established.
@MainActor
final class IslandLiveStore {
    enum DesktopRequestIdentity: Hashable {
        case server(CodexDesktopPendingRequestIdentity)
        case asynchronousQuestion(String)
    }
    struct Pending: Equatable {
        let key: String
        var value: IslandConfirmation
        var callHash: String? = nil
        var rpcEpoch: UInt64? = nil
        var desktopIdentity: DesktopRequestIdentity? = nil
        var desktopOwner: String? = nil
        var desktopEpoch: UInt64? = nil
        var mode: CodexUserInputMode? = nil
        var isGeneric = false
        var blocksExecution: Bool {
            if isGeneric { return mode != .asynchronous }
            return value.protocolRequest?.kind != .questions || mode == .synchronous
        }
    }

    /// Pure, task-scoped request state. Activity and thread wait are separate
    /// evidence; neither an unrelated tool nor a thread flag answers a request.
    struct RequestLifecycle {
        struct WaitEvidence {
            var reason: CodexActivityWaitReason?
            var epoch: UInt64?
            // Only owner-proven runtime wait evidence carries this owner. A
            // new connection's empty set cannot settle an old owner's wait.
            var desktopOwner: String? = nil
            // nil means the source reported waiting before a request identity
            // was available. A bound set is scoped to this task, turn and epoch.
            var requestIdentities: Set<String>? = nil
        }
        var requests: [Pending] = []
        var requestIndex = 0
        private(set) var desktopAsyncQuestionsAuthoritative = false
        // Native async Skip dismisses a prompt without answering the task. Keep
        // this per-turn presentation preference separate from settlement proof.
        private(set) var skippedAsyncQuestionIDs: Set<String> = []
        var sourceWait: WaitEvidence?
        var unidentifiedWait: WaitEvidence?
        // The current Desktop runtime may still be waiting after a typed RPC
        // disappears, or have an unsupported concurrent request. Keep its
        // evidence independent of observer request bindings and settlements.
        private var desktopRuntimeWait: WaitEvidence?
        private var sourcePlaceholder = Pending(key: "observer-placeholder", value: .init(
            question: .init("请求详情暂不可用", "Request details unavailable"),
            impact: .init("请在 Codex 查看并处理。", "Review and handle this request in Codex.")), isGeneric: true)
        var resolvedCallHashes: [String] = []
        var resolvedRequestKeys: [String] = []
        private var callModes: [String: CodexUserInputMode] = [:]
        private var callModeOrder: [String] = []

        var waitingOnSource: Bool { sourceWait != nil || unidentifiedWait != nil || desktopRuntimeWait != nil }
        var hasBlockingRequest: Bool { requests.contains(where: \.blocksExecution) }
        var visibleRequests: [Pending] { requests.isEmpty && waitingOnSource ? [sourcePlaceholder] : requests }
        var waitReason: CodexActivityWaitReason? {
            if let desktopRuntimeWait { return desktopRuntimeWait.reason }
            if let sourceWait { return sourceWait.reason }
            if let unidentifiedWait { return unidentifiedWait.reason }
            guard let blocker = requests.first(where: \.blocksExecution) else { return nil }
            return blocker.mode == .synchronous ? .userInput : .approval
        }
        var asynchronousCallHashes: Set<String> { Set(callModes.filter { $0.value == .asynchronous }.map(\.key)) }
        func mode(for call: String) -> CodexUserInputMode? { callModes[call] }
        static func rpcKey(_ id: IslandApprovalJSON, epoch: UInt64) -> String { "\(epoch):\(String(decoding: id.data, as: UTF8.self))" }
        mutating func observeMode(_ mode: CodexUserInputMode?, callHash: String?) {
            guard let mode, let callHash else { return }
            callModes[callHash] = mode; callModeOrder.removeAll { $0 == callHash }; callModeOrder.append(callHash)
            while callModeOrder.count > 256 { callModes.removeValue(forKey: callModeOrder.removeFirst()) }
            for i in requests.indices where requests[i].callHash == callHash
                && (requests[i].isGeneric || requests[i].value.protocolRequest?.kind == .questions) {
                requests[i].mode = mode
            }
        }
        mutating func observeWait(callHash: String?, mode: CodexUserInputMode?, reason: CodexActivityWaitReason?, epoch: UInt64? = nil) {
            observeMode(mode, callHash: callHash)
            guard mode != .asynchronous else { return }
            guard let callHash else { unidentifiedWait = .init(reason: reason, epoch: epoch); return }
            guard !resolvedCallHashes.contains(callHash), !requests.contains(where: { $0.callHash == callHash }), requests.count < 32 else { return }
            requests.append(.init(key: "observer-call:\(callHash)", value: .init(
                question: .init("请求详情暂不可用", "Request details unavailable"),
                impact: .init("请在 Codex 查看并处理。", "Review and handle this request in Codex.")),
                callHash: callHash, mode: mode, isGeneric: true))
        }
        private static func sameLogicalRequest(_ a: Pending, _ b: Pending) -> Bool {
            if let call = a.callHash, call == b.callHash {
                if a.isGeneric || b.isGeneric { return true }
                if a.value.protocolRequest?.observationOnly == true || b.value.protocolRequest?.observationOnly == true {
                    return a.value.protocolRequest?.kind == b.value.protocolRequest?.kind
                }
                // Multiple real approval RPCs may share an item. Their actual
                // typed IDs and methods must still identify the same request.
            }
            guard let left = a.value.protocolRequest, let right = b.value.protocolRequest,
                  !left.observationOnly, !right.observationOnly else { return false }
            return left.threadID == right.threadID && left.turnID == right.turnID
                && left.method == right.method && left.key == right.key
        }
        mutating func observe(_ pending: Pending) {
            if case .asynchronousQuestion(let id)? = pending.desktopIdentity,
               skippedAsyncQuestionIDs.contains(id) { return }
            if desktopAsyncQuestionsAuthoritative, pending.mode == .asynchronous,
               pending.value.protocolRequest?.observationOnly == true { return }
            // The current owner ledger is authoritative for real Desktop
            // requests. A shared item/call observer tombstone cannot veto a
            // separate still-pending RPC that happens to use that same item.
            if pending.desktopIdentity == nil,
               let call = pending.callHash, resolvedCallHashes.contains(call) { return }
            if let wire = pending.value.protocolRequest, let epoch = pending.rpcEpoch,
               resolvedRequestKeys.contains(Self.rpcKey(wire.rpcID, epoch: epoch)) { return }
            observeMode(pending.mode, callHash: pending.callHash)
            // Observer/public duplicates can enrich known mode, but they cannot
            // replace or manufacture the Desktop owner's response capability.
            if pending.desktopIdentity == nil,
               requests.contains(where: { $0.desktopIdentity != nil && Self.sameLogicalRequest($0, pending) }) { return }
            var replacement = pending
            if replacement.mode == nil, let call = replacement.callHash { replacement.mode = mode(for: call) }
            let existing = requests.first { $0.key == pending.key
                || (pending.desktopIdentity != nil && Self.sameLogicalRequest($0, pending)) }
            if let existing {
                replacement.value.id = existing.value.id
                replacement.value.phase = existing.value.phase
            }
            if pending.desktopIdentity == nil,
               requests.contains(where: { $0.key == pending.key && $0.value.protocolRequest?.raw == pending.value.protocolRequest?.raw }) { return }
            let replaces: (Pending) -> Bool = { old in
                old.key == pending.key
                    || (pending.desktopIdentity != nil && Self.sameLogicalRequest(old, pending))
                    || (pending.callHash != nil && old.callHash == pending.callHash
                        && (old.isGeneric || (pending.rpcEpoch != nil && old.value.protocolRequest?.observationOnly == true)))
            }
            let previous = requests.filter(replaces)
            guard requests.count - previous.count < 32 else { return }
            migrateSourceWait(from: previous, to: replacement)
            requests.removeAll(where: replaces)
            requests.append(replacement)
            bindUnidentifiedSourceWait(to: replacement); clampSelection()
        }
        @discardableResult mutating func skipAsyncQuestion(_ requestID: UUID) -> Bool {
            guard let pending = requests.first(where: { $0.value.id == requestID }),
                  pending.mode == .asynchronous,
                  case .asynchronousQuestion(let id)? = pending.desktopIdentity,
                  skippedAsyncQuestionIDs.count < 256 else { return false }
            skippedAsyncQuestionIDs.insert(id)
            requests.removeAll { $0.value.id == requestID }
            clampSelection()
            return true
        }
        mutating func continueCall(_ callHash: String?) {
            guard let callHash, requests.contains(where: { $0.isGeneric && $0.callHash == callHash }), mode(for: callHash) != .asynchronous else { return }
            let identifiedQuestion = mode(for: callHash) == .synchronous
            let matching = requests.filter { $0.isGeneric && $0.callHash == callHash }
            requests.removeAll { $0.isGeneric && $0.callHash == callHash }
            settleSourceWait(for: matching)
            if identifiedQuestion { rememberCall(callHash) }
            clampSelection()
        }
        @discardableResult mutating func resolveCall(_ callHash: String, proofMode: CodexUserInputMode? = nil, epoch: UInt64? = nil) -> Bool {
            guard proofMode != .asynchronous, mode(for: callHash) != .asynchronous else { return false }
            let matches: (Pending) -> Bool = { request in
                request.desktopIdentity == nil && request.callHash == callHash
                    && (epoch == nil || request.rpcEpoch == nil || request.rpcEpoch == epoch)
            }
            let matching = requests.filter(matches)
            guard !matching.contains(where: { $0.mode == .asynchronous }) else { return false }
            // A correlated result may clear missing-detail wait evidence. Only
            // a known request can leave an answered-call tombstone for replay.
            guard !matching.isEmpty || mode(for: callHash) == .synchronous else { return false }
            if mode(for: callHash) == .synchronous || matching.contains(where: { !$0.isGeneric }) { rememberCall(callHash) }
            requests.removeAll(where: matches)
            settleSourceWait(for: matching)
            clampSelection(); return true
        }
        @discardableResult mutating func resolveRPC(_ id: IslandApprovalJSON, epoch: UInt64) -> Bool {
            let key = Self.rpcKey(id, epoch: epoch)
            resolvedRequestKeys.removeAll { $0 == key }; resolvedRequestKeys.append(key)
            if resolvedRequestKeys.count > 256 { resolvedRequestKeys.removeFirst() }
            let matching = requests.filter { $0.rpcEpoch == epoch && $0.value.protocolRequest?.rpcID == id }
            for request in matching { if let call = request.callHash { rememberCall(call) } }
            requests.removeAll { $0.rpcEpoch == epoch && $0.value.protocolRequest?.rpcID == id }
            settleSourceWait(for: matching)
            clampSelection()
            return !matching.isEmpty
        }
        mutating func admitAuthoritativeDesktopQuestions() {
            // Native async questionItemIDs and rollout tool callIDs have no
            // identity mapping. The full current-owner question set supersedes
            // only this turn's read-only async source; text is never correlation.
            desktopAsyncQuestionsAuthoritative = true
            let local = requests.filter { $0.mode == .asynchronous && $0.value.protocolRequest?.observationOnly == true }
            let keys = Set(local.map(\.key))
            requests.removeAll { keys.contains($0.key) }
            if var wait = sourceWait, var identities = wait.requestIdentities {
                identities.subtract(local.compactMap(requestIdentity))
                // Removing a read-only projection is not proof of answering a
                // thread wait. A later real RPC can bind this unidentified wait.
                wait.requestIdentities = identities.isEmpty ? nil : identities
                sourceWait = wait
            }
            clampSelection()
        }
        mutating func observeDesktopRuntimeWait(_ projection: CodexDesktopInteractionProjection, owner: String, epoch: UInt64) {
            guard projection.pendingRequestsAreAuthoritative else { return }
            let represented = Set(projection.requests.map(\.identity))
            let unknownPending = projection.authoritativePendingIdentities.subtracting(represented)
            let blocker = projection.requests.first { $0.turnID == projection.currentTurnID
                && $0.userInputMode != .asynchronous }
            // A real blocking RPC is positive waiting evidence even if runtime
            // flags have not caught up. Reobserving it migrates aggregate wait
            // scope along with the typed request, allowing later settlement.
            if desktopRuntimeWait != nil, projection.threadWaitStatus != .waiting(.approval),
               projection.threadWaitStatus != .waiting(.userInput), let blocker {
                desktopRuntimeWait = .init(reason: blocker.method == "item/tool/requestUserInput" ? .userInput : .approval,
                    epoch: epoch, desktopOwner: owner)
                return
            }
            let currentScope = desktopRuntimeWait == nil || (desktopRuntimeWait?.desktopOwner == owner
                && desktopRuntimeWait?.epoch == epoch)
            switch projection.threadWaitStatus {
            case .waiting(let reason):
                // Positively observing waiting again can migrate the aggregate
                // runtime evidence. A negative snapshot cannot do that.
                desktopRuntimeWait = .init(reason: reason, epoch: epoch, desktopOwner: owner)
            case .running:
                // An unknown RPC does not invent a new user-facing wait. It
                // does prevent discarding a wait already observed on this turn.
                if !unknownPending.isEmpty, waitingOnSource || hasBlockingRequest {
                    if currentScope {
                        desktopRuntimeWait = .init(reason: waitReason ?? .approval, epoch: epoch, desktopOwner: owner)
                    }
                } else if currentScope { desktopRuntimeWait = nil }
            case .unavailable:
                if currentScope, !unknownPending.isEmpty, waitingOnSource || hasBlockingRequest {
                    desktopRuntimeWait = .init(reason: waitReason ?? .approval, epoch: epoch, desktopOwner: owner)
                }
            }
        }
        mutating func reconcileDesktopContinuation(_ projection: CodexDesktopInteractionProjection) {
            guard projection.provesNoPendingConfirmation else { return }
            // Explicit running flags plus the full owner's empty pending set
            // retire stale, unanswerable observer evidence. This does not mark
            // an async question or a typed request as answered.
            let generic = requests.filter { $0.isGeneric && $0.desktopIdentity == nil }
            let keys = Set(generic.map(\.key))
            requests.removeAll { keys.contains($0.key) }
            settleSourceWait(for: generic)
            if sourceWait?.requestIdentities == nil { sourceWait = nil }
            unidentifiedWait = nil
            // Runtime evidence was reconciled separately in its exact owner
            // scope. Preserve an older scope until it is positively reobserved.
            clampSelection()
        }
        @discardableResult
        mutating func resolveDesktopRequests(owner: String, epoch: UInt64,
            pending: Set<CodexDesktopPendingRequestIdentity>, asyncQuestions: Set<String>) -> Bool {
            let matching = requests.filter { request in
                guard request.desktopEpoch == epoch, request.desktopOwner == owner,
                      let identity = request.desktopIdentity else { return false }
                switch identity {
                case .server(let identity): return !pending.contains(identity)
                case .asynchronousQuestion(let id): return !asyncQuestions.contains(id)
                }
            }
            let keys = Set(matching.map(\.key))
            requests.removeAll { keys.contains($0.key) }
            for call in Set(matching.compactMap(\.callHash))
                where !requests.contains(where: { $0.callHash == call }) { rememberCall(call) }
            settleSourceWait(for: matching); clampSelection()
            return !matching.isEmpty
        }
        mutating func invalidateDesktopResponses(epoch: UInt64? = nil) {
            for i in requests.indices where requests[i].desktopIdentity != nil && (epoch == nil || requests[i].desktopEpoch == epoch) {
                requests[i].value.canRespond = false
                if !requests[i].value.phase.canSubmit { requests[i].value.phase = .resultUnknown }
            }
        }
        mutating func setSourceWait(_ reason: CodexActivityWaitReason?, waiting: Bool, epoch: UInt64) {
            if waiting {
                let identities = Set(requests.filter { belongsToSourceWait($0, reason: reason, epoch: epoch) }.compactMap(requestIdentity))
                sourceWait = .init(reason: reason, epoch: epoch, requestIdentities: identities.isEmpty ? nil : identities)
            } else { sourceWait = nil }
            // Missing-ID Hook notices are wait evidence, never answerable requests.
            // Explicit active flags can clear that evidence without resolving calls.
            if !waiting { unidentifiedWait = nil }
        }
        private func requestIdentity(_ request: Pending) -> String? {
            if let call = request.callHash { return "call:" + call }
            if request.desktopIdentity != nil { return request.key }
            if let epoch = request.rpcEpoch, let wire = request.value.protocolRequest {
                return "rpc:" + Self.rpcKey(wire.rpcID, epoch: epoch)
            }
            return nil
        }
        private func belongsToSourceWait(_ request: Pending, reason: CodexActivityWaitReason?, epoch: UInt64) -> Bool {
            if let requestEpoch = request.rpcEpoch, requestEpoch != epoch { return false }
            let question = request.mode != nil || request.value.protocolRequest?.kind == .questions
            switch reason {
            case .userInput: return question
            case .approval: return !question
            default: return false
            }
        }
        private mutating func migrateSourceWait(from oldRequests: [Pending], to request: Pending) {
            guard var wait = sourceWait, var identities = wait.requestIdentities,
                  let newIdentity = requestIdentity(request) else { return }
            let oldIdentities = Set(oldRequests.compactMap(requestIdentity))
            guard !identities.isDisjoint(with: oldIdentities) else { return }
            identities.subtract(oldIdentities); identities.insert(newIdentity)
            wait.requestIdentities = identities; sourceWait = wait
        }
        private mutating func bindUnidentifiedSourceWait(to request: Pending) {
            // A later local question cannot identify an earlier thread wait.
            // A native request on the waiting connection supplies that identity.
            guard var wait = sourceWait, let epoch = wait.epoch,
                  (request.rpcEpoch == epoch || (request.desktopIdentity != nil && request.mode != .asynchronous)),
                  belongsToSourceWait(request, reason: wait.reason, epoch: epoch),
                  let identity = requestIdentity(request) else { return }
            var identities = wait.requestIdentities ?? []
            identities.insert(identity); wait.requestIdentities = identities; sourceWait = wait
        }
        private mutating func settleSourceWait(for resolved: [Pending]) {
            guard var wait = sourceWait, var identities = wait.requestIdentities else { return }
            for request in resolved {
                guard request.rpcEpoch == nil || request.rpcEpoch == wait.epoch,
                      let identity = requestIdentity(request) else { continue }
                identities.remove(identity)
            }
            if identities.isEmpty { sourceWait = nil }
            else { wait.requestIdentities = identities; sourceWait = wait }
        }
        mutating func invalidateResponses(except epoch: UInt64? = nil) {
            for i in requests.indices where requests[i].desktopIdentity == nil && (epoch == nil || requests[i].rpcEpoch != epoch) {
                requests[i].value.canRespond = false
                if !requests[i].value.phase.canSubmit { requests[i].value.phase = .resultUnknown }
            }
        }
        mutating func finishTurn() { requests.removeAll(); sourceWait = nil; unidentifiedWait = nil; desktopRuntimeWait = nil; requestIndex = 0 }
        private mutating func rememberCall(_ hash: String) {
            resolvedCallHashes.removeAll { $0 == hash }; resolvedCallHashes.append(hash)
            if resolvedCallHashes.count > 256 { resolvedCallHashes.removeFirst() }
        }
        private mutating func clampSelection() { requestIndex = min(requestIndex, max(0, visibleRequests.count - 1)) }
    }

    struct TaskRecord {
        let id: Int
        let key: String
        var threadID: String?
        var turnKey: String?
        var title = ""
        var model = ""
        var effort = ""
        var activityStatus: IslandTaskStatus = .thinking
        var requestLifecycle = RequestLifecycle()
        var status: IslandTaskStatus {
            if terminal { return activityStatus }
            return requestLifecycle.waitingOnSource || requestLifecycle.hasBlockingRequest ? .waiting : activityStatus
        }
        var requests: [Pending] { requestLifecycle.visibleRequests }
        var requestIndex: Int { get { requestLifecycle.requestIndex } set { requestLifecycle.requestIndex = newValue } }
        var waitingOnSource: Bool { requestLifecycle.waitingOnSource }
        var sourceWaitReason: CodexActivityWaitReason? { requestLifecycle.waitReason }
        var genericWaitCallHash: String? { requestLifecycle.requests.first(where: \.isGeneric)?.callHash }
        var resolvedCallHashes: [String] { requestLifecycle.resolvedCallHashes }
        var resolvedRequestKeys: [String] { requestLifecycle.resolvedRequestKeys }
        var asynchronousQuestionCallHashes: Set<String> { requestLifecycle.asynchronousCallHashes }
        var operation = ""
        var tokens: Int64?
        var startedAt: Date?
        var endedAt: Date?
        var updatedAt = Date.distantPast
        var progress: Double?
        var progressResolver = CodexActivityStateSmokeProgressResolver()
        var progressUpdatedAt: Date?
        var displayedProgress: Double = 0.01
        var nativeContentAvailable = false
        var nativeState = false
        var entries: [IslandTraceEntry] = []
        var removedEntryCount = 0
        var activeItems: [String: String] = [:]
        var terminal: Bool { [.completed, .failed, .cancelled].contains(activityStatus) }
    }
    // QuotaView-only display suppression. This never archives a Codex thread,
    // stops a turn, or resolves a request. Persist only existing one-way hashes.
    private static let archivedTurnsKey = "island.archivedTurns"
    private static let unknownTurn = "unknown-turn"
    private let archiveDefaults: UserDefaults?
    private var archivedTurns: [String: String]
    init(archiveDefaults: UserDefaults? = nil) {
        self.archiveDefaults = archiveDefaults
        archivedTurns = archiveDefaults?.dictionary(forKey: Self.archivedTurnsKey) as? [String: String] ?? [:]
    }
    private func isArchived(_ task: TaskRecord) -> Bool {
        guard let turn = archivedTurns[task.key] else { return false }
        // A reconnect snapshot may precede the identified turn; keep it hidden
        // until a different, positively identified turn starts.
        return task.turnKey == nil || turn == Self.unknownTurn || task.turnKey == turn
    }
    private func saveArchives() { archiveDefaults?.set(archivedTurns, forKey: Self.archivedTurnsKey) }
    func archiveFromIsland(_ id: Int) {
        let visible = tasks.filter { !isArchived($0) }
        guard let position = visible.firstIndex(where: { $0.id == id }) else { return }
        let task = visible[position]
        archivedTurns[task.key] = task.turnKey ?? Self.unknownTurn
        saveArchives()
        if selectedID == id {
            let remaining = visible.filter { $0.id != id }
            selectedID = remaining.isEmpty ? 0 : remaining[min(position, remaining.count - 1)].id
        }
        if preservedID == id { preservedID = nil }
        onChange?()
    }
    private(set) var tasks: [TaskRecord] = []
    private(set) var selectedID = 0
    private(set) var connection = CodexSharedAppServerConnectionState.discovering
    private(set) var connectionEpoch = 0
    var preservedID: Int?
    private var nextID = 1
    private var nativeConnectionEpoch: UInt64?
    private var desktopConnected = false
    private var desktopConnectionEpoch: UInt64?
    private struct DesktopScope { let owner: String; let epoch: UInt64; let revision: Int64 }
    private var desktopScopes: [String: DesktopScope] = [:]
    private var priorTurnKeys: [String: Set<String>] = [:]
    private var metadata: [String: [String: Any]] = [:]
    var onChange: (() -> Void)?
    var onPublicChange: (() -> Void)?
    var nativeRequestSettlementDidReceive: ((CodexActivityRequestSettlement) -> Void)?
    var desktopRequestSettlementDidReceive: ((String, String, UInt64, Bool) -> Void)?
    private var pendingLocalContent: [CodexLocalPublicContent] = []
    var responseCapability: ((IslandCodexApprovalRequest) -> Bool)?
    var respond: ((IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void)?

    func reset() { tasks.removeAll(); metadata.removeAll(); priorTurnKeys.removeAll(); itemContexts.removeAll(); pendingLocalContent.removeAll(); selectedID = 0; nativeConnectionEpoch = nil; desktopConnected = false; desktopConnectionEpoch = nil; desktopScopes.removeAll(); connectionEpoch += 1; onChange?() }
    func select(_ id: Int) { if tasks.contains(where: { $0.id == id }) { selectedID = id; onChange?() } }
    func setConnection(_ state: CodexSharedAppServerConnectionState) {
        guard state != connection else { return }
        if state != .connected {
            connectionEpoch += 1
            for i in tasks.indices { tasks[i].requestLifecycle.invalidateResponses() }
        }
        connection = state; onChange?()
    }
    func setDesktopConnection(connected: Bool, epoch: UInt64?) {
        let changedEpoch = epoch != nil && desktopConnectionEpoch != epoch
        if !connected || changedEpoch {
            for i in tasks.indices { tasks[i].requestLifecycle.invalidateDesktopResponses() }
        }
        desktopConnected = connected
        if !connected { desktopConnectionEpoch = nil; desktopScopes.removeAll() }
        else if let epoch { desktopConnectionEpoch = epoch }
        onChange?()
    }
    /// Resource admission failure revokes the affected transport capability;
    /// it supplies no evidence that the owner answered its pending request.
    func invalidateDesktopResponses(conversationID: String?, epoch: UInt64) {
        guard desktopConnectionEpoch == epoch else { return }
        let key = conversationID.map(CodexActivityPrivacy.hashIdentifier)
        for i in tasks.indices where key == nil || tasks[i].key == key {
            tasks[i].requestLifecycle.invalidateDesktopResponses(epoch: epoch)
        }
        onChange?()
    }
    /// Store has already admitted the conversation and identified current turn.
    /// Only actor-minted handles, correlated below, can make a form interactive.
    func receiveDesktopProjection(_ projection: CodexDesktopInteractionProjection,
                                  snapshot: CodexDesktopConversationSnapshot) {
        guard desktopConnected, projection.sourceKind != .internalTask,
              let turn = projection.currentTurnID, !turn.isEmpty else { return }
        if let epoch = desktopConnectionEpoch, epoch != snapshot.connectionEpoch { return }
        desktopConnectionEpoch = snapshot.connectionEpoch
        let key = CodexActivityPrivacy.hashIdentifier(snapshot.conversationID)
        guard let i = tasks.firstIndex(where: { $0.key == key }), tasks[i].turnKey == CodexActivityPrivacy.hashIdentifier(turn) else { return }
        if let prior = desktopScopes[key], prior.epoch == snapshot.connectionEpoch {
            guard prior.owner != snapshot.ownerClientID || snapshot.revision >= prior.revision else { return }
            if prior.owner != snapshot.ownerClientID { tasks[i].requestLifecycle.invalidateDesktopResponses() }
        }
        desktopScopes[key] = .init(owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch, revision: snapshot.revision)
        tasks[i].threadID = snapshot.conversationID
        if !projection.title.isEmpty { tasks[i].title = projection.title }
        guard !tasks[i].terminal, projection.status == "inProgress" else { onChange?(); return }
        func handle(_ id: CodexDesktopIPCRequestID, method: String, turn: String) -> CodexDesktopIPCRequestHandle? {
            snapshot.requests.first { $0.requestID == id && $0.method == method && $0.turnID == turn
                && $0.ownerClientID == snapshot.ownerClientID && $0.connectionEpoch == snapshot.connectionEpoch
                && $0.conversationID == snapshot.conversationID }
        }
        func pending(_ wire: IslandCodexApprovalRequest, identity: DesktopRequestIdentity,
                     call: String?, mode: CodexUserInputMode?) -> Pending {
            let identityKey: String
            switch identity {
            case .server(let identity): identityKey = Data(identity.turnID.utf8).base64EncodedString() + ":" + identity.method
                + ":" + ((try? JSONEncoder().encode(identity.requestID)) ?? Data()).base64EncodedString()
            case .asynchronousQuestion(let id): identityKey = "async:" + Data(id.utf8).base64EncodedString()
            }
            let availableControls: Bool
            switch wire.kind {
            case .command, .terminalInput, .network, .fileChange: availableControls = !wire.actions.isEmpty
            case .questions: availableControls = wire.supportedQuestions
            default: availableControls = true
            }
            let canRespond = availableControls && snapshot.supportsUntrustedAppInput && wire.desktopHandle != nil
                && respond != nil && responseCapability?(wire) == true && wire.kind != .nativeOnly
                && wire.kind != .mcpURL && (wire.kind != .mcpForm || wire.supportedForm)
            let title = wire.questions.first?.title ?? (wire.params["message"].text.isEmpty
                ? (wire.params["reason"].text.isEmpty ? "Codex 请求你的处理" : wire.params["reason"].text) : wire.params["message"].text)
            return .init(key: "desktop:" + CodexActivityPrivacy.hashIdentifier(snapshot.ownerClientID) + ":\(snapshot.connectionEpoch):" + identityKey,
                value: .init(question: .init(title), impact: canRespond ? .init("处理后同步至 Codex。", "Send this response to Codex.")
                    : .init("请在 Codex 处理。", "Handle this request in Codex."), protocolRequest: wire, canRespond: canRespond),
                callHash: call, desktopIdentity: identity, desktopOwner: snapshot.ownerClientID,
                desktopEpoch: snapshot.connectionEpoch, mode: mode)
        }
        if projection.pendingRequestsAreAuthoritative {
            tasks[i].requestLifecycle.admitAuthoritativeDesktopQuestions()
            tasks[i].requestLifecycle.observeDesktopRuntimeWait(projection, owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch)
        }
        for request in projection.requests where request.turnID == turn {
            guard var wire = try? IslandCodexApprovalRequest(data: request.envelopeData) else { continue }
            wire = wire.attachingDesktopHandle(handle(request.requestID, method: request.method, turn: turn))
            if let context = request.contextItemData { wire.contextItem = try? JSONDecoder().decode(IslandApprovalJSON.self, from: context) }
            let item = wire.params["itemId"].text
            tasks[i].requestLifecycle.observe(pending(wire, identity: .server(request.identity),
                call: item.isEmpty ? nil : CodexActivityPrivacy.hashIdentifier(item), mode: request.userInputMode))
        }
        for question in projection.asyncQuestions where question.turnID == turn && question.resolvedAnswer == nil {
            guard var wire = try? IslandCodexApprovalRequest(desktopAsyncQuestion: question, conversationID: snapshot.conversationID) else { continue }
            wire = wire.attachingDesktopHandle(handle(.string(question.questionItemID), method: wire.method, turn: turn))
            tasks[i].requestLifecycle.observe(pending(wire, identity: .asynchronousQuestion(question.questionItemID),
                call: CodexActivityPrivacy.hashIdentifier(question.questionItemID), mode: .asynchronous))
        }
        if projection.pendingRequestsAreAuthoritative {
            let settled = tasks[i].requestLifecycle.resolveDesktopRequests(owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch,
                pending: projection.authoritativePendingIdentities, asyncQuestions: projection.authoritativeAsyncQuestionIDs)
            tasks[i].requestLifecycle.reconcileDesktopContinuation(projection)
            if settled || projection.provesNoPendingConfirmation {
                desktopRequestSettlementDidReceive?(key, CodexActivityPrivacy.hashIdentifier(turn), snapshot.connectionEpoch,
                    tasks[i].requestLifecycle.waitingOnSource || tasks[i].requestLifecycle.hasBlockingRequest)
            }
        }
        onChange?()
    }
    private func index(_ key: String, admit: Bool) -> Int? {
        if let i = tasks.firstIndex(where: { $0.key == key }) { return i }
        guard admit else { return nil }
        if !tasks.isEmpty && tasks.allSatisfy({ $0.terminal && $0.requests.isEmpty }) {
            tasks.removeAll { $0.id != preservedID && $0.status != .failed }
        }
        tasks.append(.init(id: nextID, key: key)); nextID += 1
        if !tasks.contains(where: { $0.id == selectedID }) { selectedID = tasks.last!.id }
        return tasks.count - 1
    }
    func receiveLegacy(_ event: CodexActivityEvent) {
        guard event.sessionKind != .internalTask else { return }
        let active = [.userPromptSubmit, .preToolUse, .permissionRequest, .preCompact].contains(event.event)
        guard let i = index(event.sessionHash, admit: active) else { return }
        let key = event.turnHash
        if let key, priorTurnKeys[event.sessionHash]?.contains(key) == true { return }
        if tasks[i].terminal && (key == nil || tasks[i].turnKey == key) { return }
        if let key, tasks[i].turnKey != key, active {
            startTurn(i, key: key, at: event.occurredAt)
        }
        if let key, tasks[i].turnKey != nil, tasks[i].turnKey != key { return }
        if tasks[i].terminal && !active { return }
        if let call = event.toolCallHash, tasks[i].resolvedCallHashes.contains(call), event.event == .permissionRequest { return }
        if [.preToolUse, .permissionRequest].contains(event.event) {
            tasks[i].requestLifecycle.observeMode(event.userInputMode, callHash: event.toolCallHash)
        }
        tasks[i].updatedAt = max(tasks[i].updatedAt, event.occurredAt)
        if tasks[i].title.isEmpty { tasks[i].title = event.workspaceName ?? "" }
        switch event.event {
        case .userPromptSubmit: tasks[i].activityStatus = .thinking; tasks[i].operation = ""
        case .preToolUse:
            tasks[i].requestLifecycle.continueCall(event.toolCallHash)
            tasks[i].activityStatus = .working; tasks[i].operation = ""
        case .postToolUse:
            if let call = event.toolCallHash {
                tasks[i].requestLifecycle.resolveCall(call, proofMode: event.userInputMode)
            }
            if event.userInputMode != .asynchronous && event.toolCallHash.flatMap({ tasks[i].requestLifecycle.mode(for: $0) }) != .asynchronous {
                tasks[i].activityStatus = tasks[i].activeItems.isEmpty ? .thinking : .working
            }
        case .permissionRequest:
            if event.source == .appServer, event.toolCallHash == nil, event.userInputMode != .asynchronous {
                tasks[i].requestLifecycle.setSourceWait(event.effectiveWaitReason, waiting: true,
                    epoch: nativeConnectionEpoch ?? UInt64(connectionEpoch))
            } else {
                tasks[i].requestLifecycle.observeWait(callHash: event.toolCallHash, mode: event.userInputMode, reason: event.effectiveWaitReason)
            }
            if event.userInputMode == .asynchronous { tasks[i].activityStatus = .working }
        case .preCompact: tasks[i].activityStatus = .compacting
        case .postCompact: if tasks[i].activityStatus == .compacting { tasks[i].activityStatus = .thinking }
        case .stop:
            switch event.turnCompletionStatus {
            case .failed: tasks[i].activityStatus = .failed
            case .interrupted: tasks[i].activityStatus = .cancelled
            default: tasks[i].activityStatus = .completed; tasks[i].progress = 1
            }
            tasks[i].endedAt = event.occurredAt; tasks[i].requestLifecycle.finishTurn(); tasks[i].activeItems.removeAll()
        case .interrupt:
            tasks[i].activityStatus = .cancelled; tasks[i].endedAt = event.occurredAt
            tasks[i].requestLifecycle.finishTurn(); tasks[i].activeItems.removeAll()
        default: break
        }
        if !tasks[i].terminal, let progress = event.planProgress?.approximateFraction { tasks[i].progress = progress }
        let pending = pendingLocalContent.filter { $0.sessionHash == event.sessionHash && $0.turnHash == tasks[i].turnKey }
        pendingLocalContent.removeAll { $0.sessionHash == event.sessionHash }
        for content in pending { receiveLocalContent(content) }
        onChange?()
    }
    func receiveToken(_ update: CodexActivityTokenUsageUpdate) {
        guard let i = tasks.firstIndex(where: { $0.key == update.sessionHash }),
              tasks[i].turnKey == nil || tasks[i].turnKey == update.turnHash,
              update.occurredAt >= (tasks[i].startedAt ?? .distantPast) else { return }
        tasks[i].tokens = update.cumulativeTotalTokens; onChange?()
    }
    func receiveLocalContent(_ content: CodexLocalPublicContent) {
        guard let p = try? JSONSerialization.jsonObject(with: content.data) as? [String: Any] else { return }
        guard let i = tasks.firstIndex(where: { $0.key == content.sessionHash }) else {
            pendingLocalContent.append(content)
            while pendingLocalContent.count > 200 || pendingLocalContent.reduce(0, { $0 + $1.data.count }) > 2_097_152 { pendingLocalContent.removeFirst() }
            return
        }
        guard tasks[i].turnKey == content.turnHash else { return }
        let type = p["type"] as? String
        if type == "questionRequest", let id = p["id"] as? String,
           let questions = p["questions"] as? [[String: Any]] {
            let mode = (p["userInputMode"] as? String).flatMap(CodexUserInputMode.init(rawValue:))
                ?? (p["asynchronous"] as? Bool == true ? .asynchronous : .synchronous)
            receiveLocalQuestions(questions, callID: id, content: content, mode: mode, at: i)
            return
        }
        if type == "output", let id = p["id"] as? String {
            let mode = (p["userInputMode"] as? String).flatMap(CodexUserInputMode.init(rawValue:))
                ?? (p["asynchronous"] as? Bool == true ? .asynchronous : nil)
            if tasks[i].requestLifecycle.resolveCall(CodexActivityPrivacy.hashIdentifier(id), proofMode: mode) { onChange?() }
        }
        if type == "metadata" {
            if let model = p["model"] as? String, !model.isEmpty { tasks[i].model = model }
            if let effort = p["effort"] as? String, !effort.isEmpty { tasks[i].effort = effort }
        } else {
            guard !(tasks[i].nativeContentAvailable && connection == .connected), let id = p["id"] as? String else {
                if type == "output" { onChange?() }
                return
            }
            if type == "output" {
                if let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == id }) {
                    let output = p["text"] as? String ?? ""
                    tasks[i].entries[j].publicItem?.output = String(output.prefix(65536))
                    tasks[i].entries[j].publicItem?.sourceTruncated = output.count > 65536
                    tasks[i].entries[j].publicItem?.status = "completed"
                }
                tasks[i].activeItems.removeValue(forKey: id)
                if tasks[i].activeItems.isEmpty && tasks[i].activityStatus == .working { tasks[i].activityStatus = .thinking; tasks[i].operation = "" }
            } else {
                let message = type == "message"
                let name = p["name"] as? String ?? ""
                let body = p["text"] as? String ?? ""
                let text = message ? body : name + "\n" + body
                upsert(.init(text: .init(String(text.prefix(65536))), publicItem: .init(category: message ? .message : .command,
                    sourceID: id, turnID: content.turnHash, status: message ? "completed" : "inProgress", sourceTruncated: text.count > 65536)), at: i)
                if message && tasks[i].status == .thinking { tasks[i].operation = String(body.prefix(240)) }
                else if !message && !tasks[i].terminal {
                    let args = body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    let detail = args?["cmd"] as? String ?? args?["code"] as? String ?? args?["command"] as? String ?? body
                    let label = name.split(separator: ".").last.map(String.init) ?? name
                    let description = label + " · " + String(detail.replacingOccurrences(of: "\n", with: " ").prefix(240))
                    tasks[i].activeItems[id] = description; tasks[i].activityStatus = .working; tasks[i].operation = description
                }
            }
        }
        trim(i); onPublicChange?()
    }
    func setTitle(_ title: String?, for key: String) {
        guard let title, !title.isEmpty, let i = tasks.firstIndex(where: { $0.key == key }), tasks[i].title != title else { return }
        tasks[i].title = title; onChange?()
    }
    private func startTurn(_ i: Int, key: String?, at date: Date) {
        if let key, priorTurnKeys[tasks[i].key]?.contains(key) == true { return }
        if let key, let archived = archivedTurns[tasks[i].key], archived != key {
            if archived == Self.unknownTurn && tasks[i].turnKey == nil && tasks[i].nativeState {
                // The existing native snapshot has just acquired its turn ID.
                archivedTurns[tasks[i].key] = key
            } else { archivedTurns.removeValue(forKey: tasks[i].key) }
            saveArchives()
        }
        if tasks[i].turnKey == key && !tasks[i].terminal {
            if tasks[i].startedAt == nil { tasks[i].startedAt = date }
            return
        }
        if tasks[i].turnKey == nil && tasks[i].nativeState {
            tasks[i].turnKey = key; tasks[i].startedAt = date
            return
        }
        if let old = tasks[i].turnKey { priorTurnKeys[tasks[i].key, default: []].insert(old) }
        tasks[i].turnKey = key; tasks[i].startedAt = date; tasks[i].endedAt = nil
        tasks[i].activityStatus = .thinking; tasks[i].requestLifecycle = RequestLifecycle(); tasks[i].progress = nil; tasks[i].operation = ""
        tasks[i].progressResolver.reset(); tasks[i].progressUpdatedAt = date; tasks[i].displayedProgress = 0.01
        tasks[i].activeItems.removeAll(); tasks[i].nativeContentAvailable = false
        tasks[i].entries.removeAll(); tasks[i].removedEntryCount = 0; tasks[i].updatedAt = date
    }
    private func receiveLocalQuestions(_ questions: [[String: Any]], callID: String, content: CodexLocalPublicContent, mode: CodexUserInputMode, at i: Int) {
        guard !tasks[i].terminal, !callID.isEmpty,
              let wire = try? IslandCodexApprovalRequest(localQuestions: questions, callID: callID,
                  sessionHash: content.sessionHash, turnHash: content.turnHash, asynchronous: mode == .asynchronous), !wire.questions.isEmpty else { return }
        let call = CodexActivityPrivacy.hashIdentifier(callID)
        tasks[i].requestLifecycle.observeMode(mode, callHash: call)
        if tasks[i].requests.contains(where: { ($0.rpcEpoch != nil || $0.desktopIdentity != nil) && $0.callHash == call }) { onChange?(); return }
        tasks[i].requestLifecycle.observe(.init(key: "local:\(content.turnHash):\(callID)", value: .init(
            question: .init(wire.questions[0].title), impact: .init("请在 Codex 回答。", "Answer in Codex."),
            protocolRequest: wire, canRespond: false), callHash: call, mode: mode))
        onChange?()
    }
    @discardableResult
    private func resolveRequest(_ i: Int, id: IslandApprovalJSON, epoch: UInt64) -> Bool {
        guard tasks[i].requestLifecycle.resolveRPC(id, epoch: epoch) else { return false }
        if let turn = tasks[i].turnKey {
            nativeRequestSettlementDidReceive?(.init(sessionHash: tasks[i].key,
                turnHash: turn, connectionEpoch: epoch,
                stillWaiting: tasks[i].requestLifecycle.waitingOnSource || tasks[i].requestLifecycle.hasBlockingRequest))
        }
        return true
    }
    func nextRequest(_ id: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), !tasks[i].requests.isEmpty else { return }
        tasks[i].requestIndex = (tasks[i].requestIndex + 1) % tasks[i].requests.count; onChange?()
    }
    func receive(_ data: Data, at now: Date = Date()) {
        guard data.count <= 1_048_576, let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = m["method"] as? String, !method.contains("reasoning"),
              let p = m["params"] as? [String: Any] else { return }
        let scope = (m["_quotaViewConnectionEpoch"] as? NSNumber)?.uint64Value ?? UInt64(connectionEpoch)
        if m["_quotaViewConnectionEpoch"] != nil {
            if let latest = nativeConnectionEpoch, scope < latest { return }
            if nativeConnectionEpoch != scope {
                nativeConnectionEpoch = scope
                for i in tasks.indices { tasks[i].requestLifecycle.invalidateResponses(except: scope) }
            }
        }
        if method == "thread/started" || method == "thread/snapshot" {
            guard let thread = p["thread"] as? [String: Any], let tid = thread["id"] as? String else { return }
            let key = CodexActivityPrivacy.hashIdentifier(tid)
            if CodexActivitySessionKind.classify(source: thread["source"], threadSource: thread["threadSource"] as? String) == .internalTask {
                tasks.removeAll { $0.key == key }; metadata.removeValue(forKey: key); onChange?(); return
            }
            metadata[key] = thread
            let status = thread["status"] as? [String: Any]
            let active = status?["type"] as? String == "active"
            guard let i = index(key, admit: active) else { return }
            applyMetadata(thread, at: i); tasks[i].threadID = tid
            if active { tasks[i].nativeState = true; applyFlags(status, at: i, epoch: scope) }
            onChange?(); return
        }
        if method == "serverRequest/resolved", p["threadId"] == nil,
           let raw = p["requestId"], let id = try? IslandApprovalJSON(any: raw) {
            let matches = tasks.indices.filter { i in
                tasks[i].requests.contains { $0.rpcEpoch == scope && $0.value.protocolRequest?.rpcID == id }
            }
            // Some protocol versions omit threadId. Resolve only an unambiguous
            // pending request, never an unrelated session with a reused ID.
            if matches.count == 1 { resolveRequest(matches[0], id: id, epoch: scope); onChange?() }
            return
        }
        guard let tid = p["threadId"] as? String else { return }
        let key = CodexActivityPrivacy.hashIdentifier(tid)
        let turn = p["turn"] as? [String: Any]
        let turnID = p["turnId"] as? String ?? turn?["id"] as? String
        let turnKey = turnID.map(CodexActivityPrivacy.hashIdentifier)
        let serverRequest = m["id"] != nil
        let activeStatus = (p["status"] as? [String: Any])?["type"] as? String == "active"
        let admit = method == "turn/started" || serverRequest || activeStatus
        guard let i = index(key, admit: admit) else { return }
        if let turnKey, priorTurnKeys[key]?.contains(turnKey) == true { return }
        if let turnKey, tasks[i].turnKey != nil, tasks[i].turnKey != turnKey, method != "turn/started" { return }
        tasks[i].threadID = tid
        if let meta = metadata[key] { applyMetadata(meta, at: i) }
        if serverRequest {
            guard var wire = try? IslandCodexApprovalRequest(data: data) else { return }
            if wire.kind == .nativeOnly && !["mcpServer/elicitation/request"].contains(method) { return }
            if let itemID = p["itemId"] as? String, let entry = tasks[i].entries.last(where: { $0.publicItem?.sourceID == itemID }) {
                if let context = itemContexts[key + ":" + itemID] { wire.contextItem = context }
                _ = entry
            }
            if tasks[i].turnKey == nil { tasks[i].turnKey = turnKey }
            let requestKey = RequestLifecycle.rpcKey(wire.rpcID, epoch: scope)
            guard !tasks[i].resolvedRequestKeys.contains(requestKey) else { return }
            let itemID = wire.params["itemId"].text
            if wire.kind == .questions, !itemID.isEmpty,
               tasks[i].resolvedCallHashes.contains(CodexActivityPrivacy.hashIdentifier(itemID)) { return }
            guard !tasks[i].terminal else { return }
            let question = !wire.questions.isEmpty ? wire.questions[0].title : wire.params["message"].text.isEmpty ? (wire.params["reason"].text.isEmpty ? "Codex 请求你的处理" : wire.params["reason"].text) : wire.params["message"].text
            let canRespond = !wire.observationOnly && respond != nil && responseCapability?(wire) == true && wire.kind != .nativeOnly && wire.kind != .mcpURL && (wire.kind != .mcpForm || wire.supportedForm) && (wire.kind != .questions || wire.supportedQuestions)
            tasks[i].requestLifecycle.observe(.init(key: requestKey, value: .init(question: .init(question),
                impact: canRespond ? .init("确认后继续任务。", "Approve to resume the task.")
                    : .init("此连接仅支持查看，请在 Codex 处理。", "This connection is read-only; handle the request in Codex."), protocolRequest: wire, canRespond: canRespond),
                callHash: itemID.isEmpty ? nil : CodexActivityPrivacy.hashIdentifier(itemID), rpcEpoch: scope))
            onChange?(); return
        }
        switch method {
        case "turn/started":
            guard !(tasks[i].terminal && tasks[i].turnKey == turnKey) else { return }
            startTurn(i, key: turnKey, at: eventDate(p["startedAtMs"] ?? turn?["startedAtMs"], fallback: now))
            tasks[i].nativeState = true
            if let model = p["model"] as? String { tasks[i].model = model }
            if let effort = p["reasoningEffort"] as? String { tasks[i].effort = effort }
        case "turn/completed":
            guard !tasks[i].terminal else { return }
            let status = turn?["status"] as? String
            guard ["completed", "interrupted", "failed"].contains(status) else { return }
            tasks[i].activityStatus = status == "completed" ? .completed : status == "interrupted" ? .cancelled : .failed
            tasks[i].progress = status == "completed" ? 1 : tasks[i].progress
            tasks[i].endedAt = eventDate(turn?["completedAtMs"], fallback: now)
            tasks[i].requestLifecycle.finishTurn(); tasks[i].activeItems.removeAll()
            if let error = turn?["error"] as? [String: Any], let message = error["message"] as? String {
                upsert(.init(text: .init(message), kind: .failure), at: i)
            }
        case "thread/status/changed": applyFlags(p["status"] as? [String: Any], at: i, epoch: scope)
        case "thread/tokenUsage/updated":
            if let usage = CodexAppServerActivityNotificationDecoder.decodeTokenUsage(data: data, now: now) { receiveToken(usage) }
        case "turn/plan/updated":
            if !tasks[i].terminal, let event = CodexAppServerActivityNotificationDecoder.decode(data: data, now: now) {
                tasks[i].progress = event.planProgress?.approximateFraction
            }
        case "serverRequest/resolved":
            if let raw = p["requestId"], let id = try? IslandApprovalJSON(any: raw) {
                resolveRequest(i, id: id, epoch: scope)
            }
        case "item/started", "item/completed":
            guard !tasks[i].terminal, let item = p["item"] as? [String: Any], let type = item["type"] as? String,
                  type != "reasoning", let itemID = item["id"] as? String else { break }
            if let context = try? IslandApprovalJSON(any: item) { itemContexts[key + ":" + itemID] = context }
            if type == "contextCompaction" { tasks[i].activityStatus = method == "item/started" ? .compacting : .thinking; break }
            let mode = CodexUserInputMode.forToolName(item["tool"] as? String ?? item["name"] as? String ?? item["toolName"] as? String)
            if method == "item/started" { tasks[i].requestLifecycle.observeMode(mode, callHash: CodexActivityPrivacy.hashIdentifier(itemID)) }
            if method == "item/started" && type != "agentMessage" {
                tasks[i].requestLifecycle.continueCall(CodexActivityPrivacy.hashIdentifier(itemID))
                let description = operationDescription(type, item: item)
                tasks[i].activeItems[itemID] = description
                tasks[i].activityStatus = .working
                tasks[i].operation = description
            }
            if method == "item/completed" {
                tasks[i].requestLifecycle.resolveCall(CodexActivityPrivacy.hashIdentifier(itemID), proofMode: mode, epoch: scope)
                tasks[i].activeItems.removeValue(forKey: itemID)
                if tasks[i].activeItems.isEmpty {
                    tasks[i].activityStatus = .thinking
                    tasks[i].operation = String((tasks[i].entries.last(where: { $0.publicItem?.category == .message })?.text.chinese ?? "").prefix(240))
                }
                else { tasks[i].activityStatus = .working; tasks[i].operation = tasks[i].activeItems.sorted { $0.key < $1.key }.last!.value }
            }
            appendItem(item, turnID: turnID ?? "", at: i)
        case "item/agentMessage/delta", "item/commandExecution/outputDelta":
            guard !tasks[i].terminal, let itemID = p["itemId"] as? String, let delta = p["delta"] as? String else { break }
            appendDelta(delta, itemID: itemID, message: method.contains("agentMessage"), at: i)
            onPublicChange?(); return
        case "thread/archived", "thread/closed":
            tasks.removeAll { $0.key == key }; onChange?(); return
        default: return
        }
        tasks[i].updatedAt = now; onChange?()
    }
    private var itemContexts: [String: IslandApprovalJSON] = [:]
    private func applyMetadata(_ data: [String: Any], at i: Int) {
        let name = (data["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (data["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let name { tasks[i].title = name }
        if let model = data["model"] as? String { tasks[i].model = model }
        if let effort = data["reasoningEffort"] as? String ?? data["effort"] as? String { tasks[i].effort = effort }
    }
    private func applyFlags(_ status: [String: Any]?, at i: Int, epoch: UInt64) {
        guard !tasks[i].terminal, let status, status["type"] as? String == "active" else { return }
        let flags = status["activeFlags"] as? [String] ?? []
        let reason: CodexActivityWaitReason? = flags.contains("waitingOnUserInput") ? .userInput
            : flags.contains("waitingOnApproval") ? .approval : nil
        tasks[i].requestLifecycle.setSourceWait(reason, waiting: reason != nil, epoch: epoch)
        // Thread continuation says execution resumed. It never says which
        // independent async question was answered, so request identities survive.
        if tasks[i].activityStatus != .compacting {
            tasks[i].activityStatus = tasks[i].activeItems.isEmpty ? .thinking : .working
        }
    }
    private func toolName(_ type: String, item: [String: Any]) -> String {
        switch type { case "commandExecution": return "exec"; case "fileChange": return "apply_patch"
        case "webSearch": return "web"; default: return item["tool"] as? String ?? type }
    }
    private func operationDescription(_ type: String, item: [String: Any]) -> String {
        let name = toolName(type, item: item)
        let detail: String
        if type == "commandExecution" { detail = item["command"] as? String ?? "" }
        else if type == "fileChange" { detail = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }.joined(separator: ", ") }
        else { detail = "" }
        return name + " · " + String(detail.replacingOccurrences(of: "\n", with: " ").prefix(240))
    }
    private func appendItem(_ item: [String: Any], turnID: String, at i: Int) {
        guard let type = item["type"] as? String, let itemID = item["id"] as? String else { return }
        let category: CodexPublicTraceItem.Category
        let text: String; var output: String?; var truncated = false
        switch type {
        case "agentMessage": category = .message; text = item["text"] as? String ?? ""
        case "commandExecution": category = .command; text = item["command"] as? String ?? ""; output = item["aggregatedOutput"] as? String
        case "fileChange":
            category = .fileChange
            text = (item["changes"] as? [[String: Any]] ?? []).map { ($0["path"] as? String ?? "") + "\n" + ($0["diff"] as? String ?? "") }.joined(separator: "\n\n")
        case "mcpToolCall", "dynamicToolCall", "webSearch", "collabToolCall":
            category = .command
            let args = item["arguments"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) }.flatMap { String(data: $0, encoding: .utf8) }
            text = toolName(type, item: item) + (args.map { "\n" + $0 } ?? "")
            output = (item["error"] as? [String: Any])?["message"] as? String
        default: return
        }
        guard !text.isEmpty else { return }
        beginNativeContent(i)
        if text.utf8.count > 131072 || (output?.utf8.count ?? 0) > 131072 { truncated = true }
        let status = item["status"] as? String
        let exit = item["exitCode"] as? Int
        let failed = status == "failed" || exit.map { $0 != 0 } == true
        upsert(.init(text: .init(String(text.prefix(65536))), kind: failed ? .failure : .progress,
            publicItem: .init(category: category, sourceID: itemID, turnID: turnID, status: status,
                output: output.map { String($0.prefix(65536)) }, sourceTruncated: truncated, exitCode: exit)), at: i)
        if category == .message && tasks[i].status == .thinking { tasks[i].operation = String(text.prefix(240)) }
    }
    private func beginNativeContent(_ i: Int) {
        if !tasks[i].nativeContentAvailable { tasks[i].entries.removeAll(); tasks[i].nativeContentAvailable = true }
    }
    private func appendDelta(_ delta: String, itemID: String, message: Bool, at i: Int) {
        beginNativeContent(i)
        if let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == itemID }) {
            if message { tasks[i].entries[j].text.chinese += delta; tasks[i].entries[j].text.english = tasks[i].entries[j].text.chinese }
            else { let output = (tasks[i].entries[j].publicItem?.output ?? "") + delta; tasks[i].entries[j].publicItem?.output = output }
            if tasks[i].entries[j].text.chinese.count > 65536 || (tasks[i].entries[j].publicItem?.output?.count ?? 0) > 65536 {
                tasks[i].entries[j].text = .init(String(tasks[i].entries[j].text.chinese.prefix(65536)))
                let output = tasks[i].entries[j].publicItem?.output.map { String($0.prefix(65536)) }
                tasks[i].entries[j].publicItem?.output = output
                tasks[i].entries[j].publicItem?.sourceTruncated = true
            }
        } else if message {
            upsert(.init(text: .init(delta), publicItem: .init(category: .message, sourceID: itemID, turnID: tasks[i].turnKey ?? "")), at: i)
        }
        trim(i)
    }
    private func upsert(_ entry: IslandTraceEntry, at i: Int) {
        var entry = entry
        if let source = entry.publicItem?.sourceID, let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == source }) {
            entry.id = tasks[i].entries[j].id; tasks[i].entries[j] = entry
        } else { tasks[i].entries.append(entry) }
        trim(i)
    }
    private func trim(_ i: Int) {
        func discardOldest(_ index: Int) {
            let entry = tasks[index].entries.removeFirst(); tasks[index].removedEntryCount += 1
            if let id = entry.publicItem?.sourceID { itemContexts.removeValue(forKey: tasks[index].key + ":" + id) }
        }
        while tasks[i].entries.count > 200 { discardOldest(i) }
        func bytes() -> Int { tasks.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.text.chinese.utf8.count + ($1.publicItem?.output?.utf8.count ?? 0) } } }
        while bytes() > 2_097_152,
              let old = tasks.indices.filter({ !tasks[$0].entries.isEmpty }).min(by: { tasks[$0].updatedAt < tasks[$1].updatedAt }) {
            discardOldest(old)
        }
    }
    private func eventDate(_ value: Any?, fallback: Date) -> Date {
        guard let n = value as? NSNumber, n.doubleValue > 0 else { return fallback }
        return Date(timeIntervalSince1970: n.doubleValue / 1000)
    }
    func submit(_ id: Int, requestID: UUID, decision: IslandConfirmationDecision) {
        guard let i = tasks.firstIndex(where: { $0.id == id }),
              let j = tasks[i].requestLifecycle.requests.firstIndex(where: { $0.value.id == requestID }),
              tasks[i].requestLifecycle.requests[j].value.canRespond, tasks[i].requestLifecycle.requests[j].value.phase.canSubmit,
              let wire = tasks[i].requestLifecycle.requests[j].value.protocolRequest,
              !wire.observationOnly, responseCapability?(wire) == true else { return }
        let turn = tasks[i].turnKey
        let epoch = connectionEpoch
        let handle = wire.desktopHandle
        if let handle {
            guard desktopConnected, desktopConnectionEpoch == handle.connectionEpoch,
                  turn == CodexActivityPrivacy.hashIdentifier(handle.turnID),
                  desktopScopes[tasks[i].key]?.owner == handle.ownerClientID else { return }
        }
        if decision == .skipQuestion {
            guard wire.kind == .questions, wire.supportedQuestions else { return }
            if let skip = wire.questionSkipResult {
                submit(id, requestID: requestID, decision: .reply(skip))
            } else if wire.userInputMode == .asynchronous, handle?.kind == .asynchronousQuestion,
                      tasks[i].requestLifecycle.skipAsyncQuestion(requestID) {
                // No RPC, answer tombstone, or source-wait settlement is emitted.
                onChange?()
            }
            return
        }
        guard case .reply(let result) = decision, wire.permits(result), let respond else { return }
        tasks[i].requestLifecycle.requests[j].value.phase = .submitting(decision); onChange?()
        Task { [weak self] in
            guard let self else { return }
            @MainActor func currentRequest() -> (Int, Int)? {
                guard let i = tasks.firstIndex(where: { $0.id == id && $0.turnKey == turn }),
                      let j = tasks[i].requestLifecycle.requests.firstIndex(where: { $0.value.id == requestID }),
                      tasks[i].requestLifecycle.requests[j].value.canRespond,
                      tasks[i].requestLifecycle.requests[j].value.phase == .submitting(decision) else { return nil }
                if let handle {
                    guard desktopConnected, desktopConnectionEpoch == handle.connectionEpoch,
                          tasks[i].requestLifecycle.requests[j].value.protocolRequest?.desktopHandle == handle,
                          desktopScopes[tasks[i].key]?.owner == handle.ownerClientID else { return nil }
                } else if epoch != connectionEpoch { return nil }
                return (i, j)
            }
            guard let (i, j) = currentRequest() else { return }
            guard responseCapability?(wire) == true else {
                tasks[i].requestLifecycle.requests[j].value.phase = .resultUnknown
                tasks[i].requestLifecycle.requests[j].value.canRespond = false; onChange?(); return
            }
            do {
                try await respond(wire, result)
                guard let (i, j) = currentRequest() else { return }
                tasks[i].requestLifecycle.requests[j].value.phase = .sent; onChange?()
            } catch {
                guard let (i, j) = currentRequest() else { return }
                tasks[i].requestLifecycle.requests[j].value.phase = .resultUnknown
                tasks[i].requestLifecycle.requests[j].value.canRespond = false; onChange?()
            }
        }
    }
    private func advanceProgress(at now: Date) {
        for i in tasks.indices {
            if tasks[i].status == .completed { tasks[i].displayedProgress = 1; continue }
            guard !tasks[i].terminal else { continue }
            let previous = tasks[i].progressUpdatedAt ?? tasks[i].startedAt ?? now
            guard now >= previous else { continue }
            // Resolve using the existing single-island algorithm, owned by the
            // task rather than a disposable selected-row renderer. Bound catch-up.
            var remaining = min(60, now.timeIntervalSince(previous))
            repeat {
                let step = min(0.25, remaining)
                if let value = tasks[i].progressResolver.resolve(state: tasks[i].status.visualState,
                    plannedFraction: tasks[i].progress, elapsed: Float(step), reduceMotion: false) {
                    tasks[i].displayedProgress = max(tasks[i].displayedProgress, min(value, 0.95))
                }
                remaining -= step
            } while remaining > 0.000001
            tasks[i].progressUpdatedAt = now
        }
    }
    func display(english: Bool, remaining: Int?, enabled: Bool, privacy: Bool, at now: Date = Date()) -> CodexMultitaskDisplay {
        advanceProgress(at: now)
        var details: [Int: IslandTaskDetailData] = [:]; var metas: [Int: IslandSessionMetadata] = [:]
        let copy = CodexActivityCopy(language: english ? .english : .simplifiedChinese)
        let visibleTasks = tasks.filter { !isArchived($0) }
        let items = visibleTasks.map { task -> CodexMultitaskRenderTask in
            let visual = task.status.visualState
            let duration = task.startedAt.map { max(0, Int((task.endedAt ?? now).timeIntervalSince($0))) }
            metas[task.id] = .init(modelName: task.model.isEmpty ? (english ? "Unknown model" : "模型未知") : task.model, reasoningEffort: task.effort, elapsedSeconds: duration)
            var request = task.requests.isEmpty ? nil : task.requests[min(task.requestIndex, task.requests.count - 1)].value
            request?.queueIndex = task.requestIndex + 1; request?.queueCount = task.requests.count
            details[task.id] = .init(entries: privacy ? [] : task.entries, confirmation: privacy ? nil : request, status: task.status, removedEntryCount: task.removedEntryCount)
            let title = privacy ? (english ? "Codex task" : "Codex 任务") : (task.title.isEmpty ? (english ? "Untitled task" : "未命名任务") : task.title)
            let status: String
            if task.status == .cancelled { status = english ? "Interrupted" : "已中断" }
            else if task.status == .queued { status = english ? "Queued" : "排队中" }
            else if task.status == .waiting && task.sourceWaitReason == .userInput { status = english ? "Awaiting answer" : "等待回答" }
            else { status = copy.statusTitle(for: visual) }
            let operation: String
            if task.operation == "exec" || task.operation.hasPrefix("exec · ") {
                operation = (english ? "Executing" : "执行中") + task.operation.dropFirst(4)
            } else { operation = task.operation }
            let render = CodexActivityRenderState(taskIdentity: .init(sessionHash: task.key, turnHash: task.turnKey),
                visualState: visual, approximateProgressFraction: task.displayedProgress,
                windowTitle: title, statusTitle: status, operation: privacy || task.status == .compacting ? "" : (task.status == .waiting
                    ? status + " · " + (request?.question.value(english) ?? "") : operation),
                tokenUsageTitle: task.tokens.map { CodexActivityTokenUsageFormatter.string(for: $0) + " tokens" },
                accessibilityLabel: "\(title), \(status)")
            return .init(id: task.id, renderState: render, playbackEnabled: !task.terminal || task.status == .completed, hasPendingRequest: !task.requests.isEmpty)
        }
        return .init(state: .init(tasks: items, selectedID: selectedID, allCompleted: !visibleTasks.isEmpty && visibleTasks.allSatisfy(\.terminal), compact: true, receiptStartedAt: nil),
            english: english, effect: .dropField, visible: enabled, playbackEnabled: true, totalTokens: nil, remainingPercent: remaining,
            sessionMetadata: metas, taskDetails: details, connectionTitle: connection == .connected || desktopConnected ? (english ? "Connected" : "已连接") : (visibleTasks.isEmpty ? (english ? "Waiting for Codex" : "等待 Codex 任务") : (english ? "Local activity" : "本地活动数据")), privacyMode: privacy, activeRequestIDs: privacy ? [] : Set(visibleTasks.flatMap { $0.requests.map { $0.value.id } }))
    }
}
