import Foundation
import QuotaViewCore

// Request state is independent of retained task content and display focus.
extension IslandLiveStore {
    /// Pure, task-scoped request state. Activity and thread wait are separate
    /// evidence; neither an unrelated tool nor a thread flag answers a request.
    struct RequestLifecycle {
        struct WaitEvidence {
            var reason: CodexActivityWaitReason?
            var epoch: UInt64?
            var observedAt: Date = .distantPast
            var source: CodexActivityEventSource? = nil
            // Only owner-proven runtime wait evidence carries this owner. A
            // new connection's empty set cannot settle an old owner's wait.
            var desktopOwner: String? = nil
            // nil means the source reported waiting before a request identity
            // was available. A bound set is scoped to this task, turn and epoch.
            var requestIdentities: Set<String>? = nil
            var toolName: String? = nil
            var toolCallHash: String? = nil
            var toolCallIsExplicit = false
            // A complete positive owner ledger binds every matching blocker,
            // rather than guessing which one caused an anonymous Hook notice.
            var nativeRequestIdentities: Set<CodexDesktopPendingRequestIdentity>? = nil
            var boundAt: Date? = nil
        }
        private struct HookToolObservation {
            var toolName: String
            var startedAt: Date
            var endedAt: Date? = nil
        }
        var requests: [Pending] = []
        private var selectedRequestID: UUID?
        private var selectionFallbackIndex = 0
        var requestIndex: Int {
            get {
                if let selectedRequestID, let index = visibleRequests.firstIndex(where: { $0.value.id == selectedRequestID }) { return index }
                return min(selectionFallbackIndex, max(0, visibleRequests.count - 1))
            }
            set {
                selectionFallbackIndex = min(max(0, newValue), max(0, visibleRequests.count - 1))
                selectedRequestID = visibleRequests.indices.contains(selectionFallbackIndex) ? visibleRequests[selectionFallbackIndex].value.id : nil
            }
        }
        private(set) var desktopAsyncQuestionsAuthoritative = false
        // Native async Skip dismisses a prompt without answering the task. Keep
        // this per-turn presentation preference separate from settlement proof.
        private(set) var skippedAsyncQuestionIDs: Set<String> = []
        var sourceWait: WaitEvidence?
        private var unidentifiedWaits: [WaitEvidence] = []
        private var unidentifiedWaitOverflow = false
        private var unidentifiedWaitOverflowIsWeak = true
        var unidentifiedWait: WaitEvidence? { unidentifiedWaits.first }
        // The current Desktop runtime may still be waiting after a typed RPC
        // disappears, or have an unsupported concurrent request. Keep its
        // evidence independent of observer request bindings and settlements.
        private var desktopRuntimeWait: WaitEvidence?
        private struct DesktopSettlementPresentation {
            let owner: String
            let epoch: UInt64
            let reason: CodexActivityWaitReason
            let settledAt: Date
            let identities: Set<CodexDesktopPendingRequestIdentity>
            let callHashes: Set<String>
            var continuationObserved = false
        }
        private var desktopSettlementPresentation: DesktopSettlementPresentation?
        enum DesktopSettlementDisplay { case synchronizing, resumed }
        /// A settled RPC and its observer flags can arrive on different ticks.
        /// Explicit owner continuation retires only the older observer presentation.
        /// The two-second grace applies only while runtime continuation is unproven;
        /// elapsed time cannot resurrect old observer evidence after that proof.
        func desktopSettlementDisplay(at now: Date) -> DesktopSettlementDisplay? {
            guard let receipt = desktopSettlementPresentation,
                  now >= receipt.settledAt,
                  waitingOnSource, sourceWait == nil, !unidentifiedWaitOverflow,
                  visibleRequests.allSatisfy(\.isGeneric) else { return nil }
            if let wait = desktopRuntimeWait,
               receipt.continuationObserved || wait.desktopOwner != receipt.owner
                    || wait.epoch != receipt.epoch || wait.reason != receipt.reason { return nil }
            func isEarlierObserver(_ wait: WaitEvidence) -> Bool {
                guard wait.source != .appServer, wait.reason == receipt.reason, wait.observedAt <= receipt.settledAt,
                      wait.desktopOwner == nil || (wait.desktopOwner == receipt.owner && wait.epoch == receipt.epoch) else { return false }
                // Once the owner has bound this observer to native requests,
                // those identities are the correlation proof. Hook tool call
                // IDs and native item IDs belong to different namespaces.
                if let identities = wait.nativeRequestIdentities, !identities.isEmpty {
                    return wait.desktopOwner == receipt.owner && wait.epoch == receipt.epoch
                        && identities.isSubset(of: receipt.identities)
                }
                if wait.toolCallIsExplicit, let call = wait.toolCallHash, !receipt.callHashes.contains(call) { return false }
                return true
            }
            guard unidentifiedWaits.allSatisfy(isEarlierObserver)
                && requests.allSatisfy({ request in
                    request.isGeneric && genericWaitEvidence[request.key].map(isEarlierObserver) == true
                }) else { return nil }
            if receipt.continuationObserved { return .resumed }
            return now.timeIntervalSince(receipt.settledAt) < 2 ? .synchronizing : nil
        }
        private var sourcePlaceholder = Pending(key: "observer-placeholder", value: .init(
            question: .init("请求详情暂不可用", "Request details unavailable"),
            impact: .init("正在同步请求详情。如有 macOS 权限弹窗，请在系统弹窗中处理。",
                "Syncing request details. If macOS shows a permission dialog, respond in that system dialog.")), isGeneric: true)
        var resolvedCallHashes: [String] = []
        private(set) var retiredObserverCallHashes: [String] = []
        var resolvedRequestKeys: [String] = []
        private var acceptedAsyncReplyProofs: [String: String] = [:]
        private var acceptedAsyncReplyOrder: [String] = []
        private var callModes: [String: CodexUserInputMode] = [:]
        private var callModeOrder: [String] = []
        private var genericWaitEvidence: [String: WaitEvidence] = [:]
        private var hookTools: [String: HookToolObservation] = [:]
        private var hookToolsOverflowed = false
        private var hookHistoryFloor = Date.distantPast
        private var uncertainHistoricalHookCalls: Set<String> = []
        private var completedHookTools: [String: Date] = [:]
        private var completedHookToolOrder: [String] = []

        var waitingOnSource: Bool {
            sourceWait != nil || unidentifiedWait != nil || unidentifiedWaitOverflow || desktopRuntimeWait != nil
        }
        var hasBlockingRequest: Bool { requests.contains(where: \.blocksExecution) }
        var visibleRequests: [Pending] { requests.isEmpty && waitingOnSource ? [sourcePlaceholder] : requests }
        var canHideObserverReminder: Bool {
            guard !visibleRequests.isEmpty, visibleRequests.allSatisfy(\.isGeneric),
                  sourceWait == nil, desktopRuntimeWait == nil,
                  !unidentifiedWaitOverflow || unidentifiedWaitOverflowIsWeak else { return false }
            return unidentifiedWaits.allSatisfy {
                ($0.source == .hook || $0.source == nil) && $0.desktopOwner == nil && $0.nativeRequestIdentities == nil
            } && requests.allSatisfy {
                $0.desktopIdentity == nil && $0.rpcEpoch == nil && $0.value.protocolRequest == nil
                    && genericWaitEvidence[$0.key]?.source != .appServer
                    && genericWaitEvidence[$0.key]?.desktopOwner == nil
            }
        }
        var waitReason: CodexActivityWaitReason? {
            if let desktopRuntimeWait { return desktopRuntimeWait.reason }
            if let sourceWait { return sourceWait.reason }
            if let unidentifiedWait { return unidentifiedWait.reason }
            if unidentifiedWaitOverflow { return .approval }
            guard let blocker = requests.first(where: \.blocksExecution) else { return nil }
            return blocker.mode == .synchronous ? .userInput : .approval
        }
        /// Fixed metadata for diagnosing cross-source ordering, no request content or IDs.
        func desktopDiagnosticSummary(at now: Date) -> String {
            let observers = unidentifiedWaits + Array(genericWaitEvidence.values)
            let bound = observers.filter { $0.nativeRequestIdentities?.isEmpty == false }.count
            let untyped = observers.filter { $0.reason == nil }.count
            let presentation: String
            switch desktopSettlementDisplay(at: now) {
            case .synchronizing: presentation = "sync"
            case .resumed: presentation = "resumed"
            case nil: presentation = "none"
            }
            return "source_wait=\(sourceWait != nil) runtime_wait=\(desktopRuntimeWait != nil) observers=\(observers.count) untyped_observers=\(untyped) bound_observers=\(bound) settlement=\(desktopSettlementPresentation != nil) presentation=\(presentation)"
        }
        var asynchronousCallHashes: Set<String> { Set(callModes.filter { $0.value == .asynchronous }.map(\.key)) }
        func mode(for call: String) -> CodexUserInputMode? { callModes[call] }
        static func rpcKey(_ id: CodexDesktopIPCRequestID, epoch: UInt64) -> String {
            switch id {
            case .integer(let value): "\(epoch):integer:\(value)"
            case .string(let value): "\(epoch):string:\(value.utf8.count):\(value)"
            }
        }
        static func rpcKey(_ id: IslandApprovalJSON, epoch: UInt64) -> String {
            guard let typed = CodexSharedMessageIdentity.rpcID(messageData: IslandApprovalJSON.object(["id": id]).data) else { return "unsupported" }
            return rpcKey(typed, epoch: epoch)
        }
        mutating func observeMode(_ mode: CodexUserInputMode?, callHash: String?) {
            guard let mode, let callHash else { return }
            callModes[callHash] = mode; callModeOrder.removeAll { $0 == callHash }; callModeOrder.append(callHash)
            while callModeOrder.count > 256 { callModes.removeValue(forKey: callModeOrder.removeFirst()) }
            for i in requests.indices where requests[i].callHash == callHash
                && (requests[i].isGeneric || (requests[i].value.protocolRequest?.kind == .questions
                    && requests[i].value.protocolRequest?.observationOnly == true)) {
                // Local or Hook mode evidence cannot downgrade a real native
                // question RPC's independently assigned blocking mode.
                requests[i].mode = mode
            }
        }
        mutating func observeWait(callHash: String?, mode: CodexUserInputMode?, reason: CodexActivityWaitReason?,
            epoch: UInt64? = nil, toolName: String? = nil, at: Date = Date(), source: CodexActivityEventSource? = nil) {
            observeMode(mode, callHash: callHash)
            guard mode != .asynchronous else { return }
            var evidence = WaitEvidence(reason: reason, epoch: epoch, observedAt: at, source: source,
                toolName: toolName, toolCallHash: callHash, toolCallIsExplicit: callHash != nil)
            guard let callHash else {
                if source == .hook { evidence.toolCallHash = uniqueHookCall(toolName: toolName, before: at) }
                if let call = evidence.toolCallHash, completedHookTools[call].map({ $0 > at }) == true { return }
                guard !unidentifiedWaits.contains(where: {
                    $0.observedAt == at && $0.reason == reason && $0.source == source && $0.toolName == toolName
                        && $0.epoch == epoch
                }) else { return }
                if unidentifiedWaits.count < 32 { unidentifiedWaits.append(evidence) }
                else {
                    // Fail closed until turn termination. Neither a single
                    // call result nor another owner's snapshot covers overflow.
                    unidentifiedWaitOverflow = true
                    unidentifiedWaitOverflowIsWeak = unidentifiedWaitOverflowIsWeak && (source == .hook || source == nil)
                }
                return
            }
            if source == .hook, completedHookTools[callHash].map({ $0 > at }) == true { return }
            if let existing = requests.first(where: { $0.isGeneric && $0.callHash == callHash }) {
                if genericWaitEvidence[existing.key]?.desktopOwner != nil {
                    guard genericWaitEvidence[existing.key].map({ at > $0.observedAt }) ?? true,
                          !unidentifiedWaits.contains(where: {
                              $0.observedAt == at && $0.source == source && $0.toolCallHash == callHash
                                  && $0.reason == reason && $0.epoch == epoch
                          }) else { return }
                    // A new Hook notice cannot erase an earlier owner's
                    // binding. Keep the new weak wait as separate evidence.
                    if unidentifiedWaits.count < 32 { unidentifiedWaits.append(evidence) }
                    else {
                        unidentifiedWaitOverflow = true
                        unidentifiedWaitOverflowIsWeak = unidentifiedWaitOverflowIsWeak && (source == .hook || source == nil)
                    }
                    return
                }
                if genericWaitEvidence[existing.key].map({ at > $0.observedAt }) ?? true {
                    genericWaitEvidence[existing.key] = evidence
                }
                return
            }
            guard !resolvedCallHashes.contains(callHash), !retiredObserverCallHashes.contains(callHash),
                  !requests.contains(where: { $0.callHash == callHash }) else { return }
            guard requests.count < 32 else {
                unidentifiedWaitOverflow = true
                unidentifiedWaitOverflowIsWeak = unidentifiedWaitOverflowIsWeak && source != .appServer
                return
            }
            let key = "observer-call:\(callHash)"
            genericWaitEvidence[key] = evidence
            requests.append(.init(key: key, value: .init(
                question: .init("请求详情暂不可用", "Request details unavailable"),
                impact: .init("请在 Codex 查看并处理。", "Review and handle this request in Codex.")),
                callHash: callHash, mode: mode, isGeneric: true))
        }
        mutating func observeToolStart(callHash: String?, toolName: String?, at: Date, source: CodexActivityEventSource?) {
            guard source == .hook, let callHash, !callHash.isEmpty, let toolName, !toolName.isEmpty else { return }
            pruneHookHistory(before: at)
            if let existing = hookTools[callHash] {
                // A changed tool name does not identify the old call's wait.
                guard existing.toolName == toolName else { return }
                hookTools[callHash]?.startedAt = min(existing.startedAt, at)
            } else if at <= hookHistoryFloor {
                // A previously unobserved start below the retained history
                // floor may still be active. It cannot support unique matching
                // until its exact result removes that uncertainty.
                if let endedAt = completedHookTools[callHash], endedAt > hookHistoryFloor {
                    if hookTools.count < 128 {
                        hookTools[callHash] = .init(toolName: toolName, startedAt: at, endedAt: endedAt)
                    } else { hookToolsOverflowed = true }
                } else if completedHookTools[callHash] == nil {
                    if uncertainHistoricalHookCalls.count < 128 { uncertainHistoricalHookCalls.insert(callHash) }
                    else { hookToolsOverflowed = true }
                }
            } else if hookTools.count < 128 {
                hookTools[callHash] = .init(toolName: toolName, startedAt: at,
                    endedAt: completedHookTools[callHash])
            } else { hookToolsOverflowed = true }
            refreshHookBindings()
            // A result may have arrived before its start or permission notice.
            // Retain its event timestamp instead of reviving an already-ended call.
            if let completedAt = completedHookTools[callHash] {
                settleHookWait(callHash, at: completedAt, source: .hook)
            }
        }
        private func uniqueHookCall(toolName: String?, before at: Date) -> String? {
            guard !hookToolsOverflowed, uncertainHistoricalHookCalls.isEmpty, at > hookHistoryFloor,
                  let toolName, !toolName.isEmpty else { return nil }
            let matching = hookTools.filter {
                $0.value.toolName == toolName && $0.value.startedAt < at
                    && ($0.value.endedAt.map { $0 > at } ?? true)
            }
            return matching.count == 1 ? matching.first?.key : nil
        }
        private mutating func refreshHookBindings() {
            for i in unidentifiedWaits.indices where unidentifiedWaits[i].source == .hook
                && unidentifiedWaits[i].desktopOwner == nil && !unidentifiedWaits[i].toolCallIsExplicit {
                // A late second start invalidates an earlier unique match;
                // direct call IDs never depend on tool-name inference.
                unidentifiedWaits[i].toolCallHash = uniqueHookCall(toolName: unidentifiedWaits[i].toolName,
                    before: unidentifiedWaits[i].observedAt)
            }
        }
        private mutating func pruneHookHistory(before at: Date) {
            let earliestWait = unidentifiedWaits.filter {
                $0.source == .hook && $0.desktopOwner == nil && !$0.toolCallIsExplicit
                    && $0.observedAt > hookHistoryFloor
            }.map(\.observedAt).min() ?? at
            let obsolete = hookTools.filter { $0.value.endedAt.map { $0 < earliestWait } ?? false }
            for (call, tool) in obsolete {
                if let endedAt = tool.endedAt { hookHistoryFloor = max(hookHistoryFloor, endedAt) }
                hookTools.removeValue(forKey: call)
            }
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
            if !pending.isGeneric { desktopSettlementPresentation = nil }
            if Self.asyncQuestionsAreAnswered(pending, proofs: acceptedAsyncReplyProofs) { return }
            if case .asynchronousQuestion(let id)? = pending.desktopIdentity,
               skippedAsyncQuestionIDs.contains(id) { return }
            if desktopAsyncQuestionsAuthoritative, pending.mode == .asynchronous,
               pending.value.protocolRequest?.observationOnly == true { return }
            // The current owner ledger is authoritative for real Desktop
            // requests. A shared item/call observer tombstone cannot veto a
            // separate still-pending RPC that happens to use that same item.
            if pending.desktopIdentity == nil, pending.rpcEpoch == nil,
               let call = pending.callHash, resolvedCallHashes.contains(call) { return }
            if let wire = pending.value.protocolRequest, let epoch = pending.rpcEpoch,
               resolvedRequestKeys.contains(Self.rpcKey(wire.rpcIdentity, epoch: epoch)) { return }
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
                if existing.value.protocolRequest?.answerContent == pending.value.protocolRequest?.answerContent {
                    replacement.value.id = existing.value.id
                    replacement.value.phase = existing.value.phase
                    replacement.value.contentRevised = existing.value.contentRevised
                } else {
                    // Answerable content revisions are independent of reconnect
                    // nonces. Old drafts and late results cannot cross revisions.
                    replacement.value.contentRevised = true
                    if selectedRequestID == existing.value.id { selectedRequestID = replacement.value.id }
                }
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
            for old in previous { genericWaitEvidence.removeValue(forKey: old.key) }
            let insertion = requests.firstIndex(where: replaces) ?? requests.count
            requests.removeAll(where: replaces)
            requests.insert(replacement, at: min(insertion, requests.count))
            bindUnidentifiedSourceWait(to: replacement); clampSelection()
        }
        private static func asyncQuestionProofs(_ pending: Pending) -> [(String, String)] {
            guard pending.mode == .asynchronous, let wire = pending.value.protocolRequest,
                  wire.kind == .questions else { return [] }
            if case .asynchronousQuestion(let identity)? = pending.desktopIdentity, wire.questions.count == 1 {
                return [(CodexActivityPrivacy.hashIdentifier(identity),
                    CodexActivityPrivacy.hashIdentifier(wire.questions[0].title))]
            }
            guard let local = wire.localObservation, local.mode == .asynchronous else { return [] }
            // This is an equality check on an explicit call ID and question index;
            // it never maps a differing native agent-message ID by matching text.
            return wire.questions.enumerated().compactMap { index, question in
                CodexLocalAsyncReplyContent.identityHash(source: local.callID, index: index).map {
                    ($0, CodexActivityPrivacy.hashIdentifier(question.title))
                }
            }
        }
        private static func asyncQuestionsAreAnswered(_ pending: Pending, proofs: [String: String]) -> Bool {
            let identities = asyncQuestionProofs(pending)
            return !identities.isEmpty && identities.allSatisfy { proofs[$0.0] == $0.1 }
        }
        @discardableResult mutating func receiveAcceptedAsyncReplies(_ proofs: [(String, String)]) -> Bool {
            let observed = Set(requests.flatMap(Self.asyncQuestionProofs).map { $0.0 + ":" + $0.1 })
            // A reply preceding the original request, another question's text,
            // or an unobserved call cannot create a future-answer tombstone.
            for (identity, question) in proofs where observed.contains(identity + ":" + question) {
                acceptedAsyncReplyProofs[identity] = question
                acceptedAsyncReplyOrder.removeAll { $0 == identity }; acceptedAsyncReplyOrder.append(identity)
            }
            let settled = requests.filter { Self.asyncQuestionsAreAnswered($0, proofs: acceptedAsyncReplyProofs) }
            let keys = Set(settled.map(\.key))
            requests.removeAll { keys.contains($0.key) }
            for call in settled.compactMap(\.callHash) { rememberCall(call) }
            // Retain proofs still needed by a partially answered group and a
            // bounded replay window. A full window must never reject a new
            // answer for a question we are currently showing.
            let active = Set(requests.flatMap(Self.asyncQuestionProofs).map(\.0))
            var retired = acceptedAsyncReplyOrder.filter { !active.contains($0) }
            while retired.count > 256 {
                let oldest = retired.removeFirst()
                acceptedAsyncReplyProofs.removeValue(forKey: oldest)
                acceptedAsyncReplyOrder.removeAll { $0 == oldest }
            }
            // Async replies settle their questions only, never unrelated native
            // blocking RPCs, anonymous source waits, or runtime compaction.
            clampSelection()
            return !settled.isEmpty
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
        mutating func continueCall(_ callHash: String?, at: Date = Date(), source: CodexActivityEventSource? = .appServer) {
            guard let callHash else { return }
            let retiredAnonymous = settleHookWait(callHash, at: at, source: source)
            guard mode(for: callHash) != .asynchronous else { return }
            let matching = requests.filter {
                $0.isGeneric && $0.desktopIdentity == nil && $0.callHash == callHash
                    && (genericWaitEvidence[$0.key].map {
                        source != nil && $0.source == source && at > $0.observedAt
                    } ?? false)
                    && genericWaitEvidence[$0.key]?.desktopOwner == nil
            }
            let keys = Set(matching.map(\.key))
            requests.removeAll { keys.contains($0.key) }
            for key in keys { genericWaitEvidence.removeValue(forKey: key) }
            // A Hook only withdraws its weak observation. It cannot settle an
            // independent native thread flag even when a call ID is shared.
            if source != .hook { settleSourceWait(for: matching) }
            if mode(for: callHash) == .synchronous, !matching.isEmpty { rememberCall(callHash) }
            else if !matching.isEmpty || retiredAnonymous { rememberObserverCall(callHash) }
            guard !matching.isEmpty || retiredAnonymous else { return }
            clampSelection()
        }
        @discardableResult mutating func resolveCall(_ callHash: String, proofMode: CodexUserInputMode? = nil,
            epoch: UInt64? = nil, at: Date = Date(), source: CodexActivityEventSource? = .appServer) -> Bool {
            guard source != nil else { return false }
            if source == .hook { recordHookCompletion(callHash, at: at) }
            let retiredAnonymous = settleObserverCompletion(callHash, at: at, source: source)
            guard proofMode != .asynchronous, mode(for: callHash) != .asynchronous else { return false }
            let matches: (Pending) -> Bool = { request in
                request.desktopIdentity == nil && request.rpcEpoch == nil && request.callHash == callHash
                    && (request.isGeneric || request.value.protocolRequest?.observationOnly == true)
                    && (epoch == nil || request.rpcEpoch == nil || request.rpcEpoch == epoch)
                    && (genericWaitEvidence[request.key].map { at > $0.observedAt } ?? true)
                    && genericWaitEvidence[request.key]?.desktopOwner == nil
            }
            let matching = requests.filter(matches)
            guard !matching.contains(where: { $0.mode == .asynchronous }) else { return false }
            // Retiring unknown observer evidence is not an answered question.
            // Its replay record cannot veto a later typed async question or RPC.
            guard !matching.isEmpty || mode(for: callHash) == .synchronous || retiredAnonymous else { return false }
            if mode(for: callHash) == .synchronous || matching.contains(where: { !$0.isGeneric }) { rememberCall(callHash) }
            else { rememberObserverCall(callHash) }
            requests.removeAll(where: matches)
            for request in matching { genericWaitEvidence.removeValue(forKey: request.key) }
            if source != .hook { settleSourceWait(for: matching) }
            clampSelection(); return true
        }
        private mutating func recordHookCompletion(_ callHash: String, at: Date) {
            completedHookTools[callHash] = max(completedHookTools[callHash] ?? .distantPast, at)
            completedHookToolOrder.removeAll { $0 == callHash }; completedHookToolOrder.append(callHash)
            while completedHookToolOrder.count > 256 {
                completedHookTools.removeValue(forKey: completedHookToolOrder.removeFirst())
            }
            if let tool = hookTools[callHash], at >= tool.startedAt {
                hookTools[callHash]?.endedAt = min(tool.endedAt ?? at, at)
            }
            uncertainHistoricalHookCalls.remove(callHash)
            refreshHookBindings()
        }
        @discardableResult private mutating func settleHookWait(_ callHash: String, at: Date,
            source: CodexActivityEventSource?) -> Bool {
            guard source == .hook else { return false }
            let oldCount = unidentifiedWaits.count
            unidentifiedWaits.removeAll {
                $0.source == .hook && $0.desktopOwner == nil && $0.nativeRequestIdentities == nil
                    && $0.toolCallHash == callHash && at > $0.observedAt
            }
            return unidentifiedWaits.count != oldCount
        }
        @discardableResult private mutating func settleObserverCompletion(_ callHash: String, at: Date,
            source: CodexActivityEventSource?) -> Bool {
            guard source != nil else { return false }
            let oldCount = unidentifiedWaits.count
            unidentifiedWaits.removeAll {
                $0.desktopOwner == nil && $0.nativeRequestIdentities == nil && $0.source != .appServer
                    && $0.toolCallHash == callHash && at > $0.observedAt
            }
            return unidentifiedWaits.count != oldCount
        }
        @discardableResult mutating func resolveRPC(_ id: IslandApprovalJSON, epoch: UInt64) -> Bool {
            guard let typed = CodexSharedMessageIdentity.rpcID(messageData: IslandApprovalJSON.object(["id": id]).data) else { return false }
            return resolveRPC(typed, epoch: epoch)
        }
        @discardableResult mutating func resolveRPC(_ id: CodexDesktopIPCRequestID, epoch: UInt64) -> Bool {
            let key = Self.rpcKey(id, epoch: epoch)
            resolvedRequestKeys.removeAll { $0 == key }; resolvedRequestKeys.append(key)
            if resolvedRequestKeys.count > 256 { resolvedRequestKeys.removeFirst() }
            let matching = requests.filter { $0.rpcEpoch == epoch && $0.value.protocolRequest?.rpcIdentity == id }
            for request in matching { if let call = request.callHash { rememberCall(call) } }
            requests.removeAll { $0.rpcEpoch == epoch && $0.value.protocolRequest?.rpcIdentity == id }
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
        mutating func observeDesktopRuntimeWait(_ projection: CodexDesktopInteractionProjection,
            owner: String, epoch: UInt64, at: Date = Date()) {
            guard projection.pendingRequestsAreAuthoritative else { return }
            if let receipt = desktopSettlementPresentation {
                let changedReason: Bool
                if case .waiting(let reason) = projection.threadWaitStatus { changedReason = reason != receipt.reason }
                else { changedReason = false }
                if receipt.owner != owner || receipt.epoch != epoch || changedReason
                    || (receipt.continuationObserved && projection.threadWaitStatus != .running)
                    || !projection.authoritativePendingIdentities.isEmpty || !projection.authoritativeAsyncQuestionIDs.isEmpty {
                    desktopSettlementPresentation = nil
                }
            }
            let represented = Set(projection.requests.map(\.identity))
            let unknownPending = projection.authoritativePendingIdentities.subtracting(represented)
            reconcileObserverDesktopEvidence(projection, owner: owner, epoch: epoch, at: at)
            let blocker = projection.requests.first {
                $0.turnID == projection.currentTurnID && $0.userInputMode != .asynchronous
                    && projection.authoritativePendingIdentities.contains($0.identity)
            }
            // Reobserving a real blocker is positive evidence in the new owner
            // scope even before runtime flags catch up. An empty set cannot
            // migrate an older owner's aggregate wait.
            if let previous = desktopRuntimeWait, at >= previous.observedAt, let blocker,
               projection.threadWaitStatus != .waiting(.approval),
               projection.threadWaitStatus != .waiting(.userInput) {
                desktopRuntimeWait = .init(reason: blocker.method == "item/tool/requestUserInput" ? .userInput : .approval,
                    epoch: epoch, observedAt: at, source: .appServer, desktopOwner: owner)
                return
            }
            let currentScope = desktopRuntimeWait == nil || (desktopRuntimeWait?.desktopOwner == owner
                && desktopRuntimeWait?.epoch == epoch)
            switch projection.threadWaitStatus {
            case .waiting(let reason):
                // Positively observing waiting again can migrate the aggregate
                // runtime evidence. A negative snapshot cannot do that.
                if desktopRuntimeWait.map({ at >= $0.observedAt }) ?? true {
                    desktopRuntimeWait = .init(reason: reason, epoch: epoch, observedAt: at,
                        source: .appServer, desktopOwner: owner)
                }
            case .running:
                // An unknown RPC does not invent a new user-facing wait. It
                // does prevent discarding a wait already observed on this turn.
                if !unknownPending.isEmpty, waitingOnSource || hasBlockingRequest {
                    if currentScope {
                        desktopRuntimeWait = .init(reason: waitReason ?? .approval, epoch: epoch,
                            observedAt: at, source: .appServer, desktopOwner: owner)
                    }
                } else if currentScope, desktopRuntimeWait.map({ at > $0.observedAt }) ?? true {
                    desktopRuntimeWait = nil
                }
            case .unavailable:
                if currentScope, !unknownPending.isEmpty, waitingOnSource || hasBlockingRequest {
                    desktopRuntimeWait = .init(reason: waitReason ?? .approval, epoch: epoch,
                        observedAt: at, source: .appServer, desktopOwner: owner)
                }
            }
        }
        mutating func reconcileDesktopContinuation(_ projection: CodexDesktopInteractionProjection,
            owner: String, epoch: UInt64, at: Date = Date()) {
            reconcileObserverDesktopEvidence(projection, owner: owner, epoch: epoch, at: at)
            guard Self.hasExecutionContinuation(projection) else { return }
            if let receipt = desktopSettlementPresentation, receipt.owner == owner, receipt.epoch == epoch,
               at >= receipt.settledAt, projection.provesNoPendingConfirmation {
                desktopSettlementPresentation?.continuationObserved = true
            }
            if let wait = sourceWait, wait.requestIdentities == nil,
               wait.desktopOwner == owner, wait.epoch == epoch, at > wait.observedAt {
                sourceWait = nil
            }
            clampSelection()
        }
        private static func hasExecutionContinuation(_ projection: CodexDesktopInteractionProjection) -> Bool {
            // Async questions may remain unanswered while execution resumes.
            // This proof retires an owner-bound anonymous wait only; question
            // settlement still requires complete absence or an exact answer.
            projection.status == "inProgress" && projection.pendingRequestsAreAuthoritative
                && projection.threadWaitStatus == .running && projection.authoritativePendingIdentities.isEmpty
        }
        private mutating func reconcileObserverDesktopEvidence(_ projection: CodexDesktopInteractionProjection,
            owner: String, epoch: UInt64, at: Date) {
            guard projection.pendingRequestsAreAuthoritative,
                  projection.authoritativePendingIdentities.subtracting(Set(projection.requests.map(\.identity))).isEmpty else { return }
            let blockers = projection.requests.filter {
                $0.turnID == projection.currentTurnID && $0.userInputMode != .asynchronous
                    && projection.authoritativePendingIdentities.contains($0.identity)
            }
            func reconcile(_ evidence: WaitEvidence) -> WaitEvidence? {
                var wait = evidence
                guard at >= wait.observedAt else { return wait }
                let matching = Set(blockers.filter {
                    ($0.method == "item/tool/requestUserInput" ? CodexActivityWaitReason.userInput : .approval) == wait.reason
                }.map(\.identity))
                if let existingOwner = wait.desktopOwner {
                    guard existingOwner == owner, wait.epoch == epoch,
                          at > (wait.boundAt ?? wait.observedAt) else { return wait }
                    if let identities = wait.nativeRequestIdentities, !identities.isEmpty,
                       identities.isDisjoint(with: projection.authoritativePendingIdentities),
                       blockers.isEmpty { return nil }
                    // An exact pending-set removal settles its bound observer
                    // alias even if the aggregate runtime flag arrives later.
                    // desktopRuntimeWait independently retains that flag; this
                    // cannot answer a system prompt or another pending RPC.
                    // A flag-only positive witness needs an explicit running
                    // transition; absent runtime fields cannot settle it.
                    if wait.nativeRequestIdentities == nil, Self.hasExecutionContinuation(projection) { return nil }
                    if !matching.isEmpty {
                        wait.nativeRequestIdentities = matching; wait.boundAt = at
                    }
                    return wait
                }
                guard wait.source != .appServer, wait.epoch == nil || wait.epoch == epoch else { return wait }
                let matchingRuntimeWait: Bool
                if case .waiting(let reason) = projection.threadWaitStatus { matchingRuntimeWait = reason == wait.reason }
                else { matchingRuntimeWait = false }
                guard !matching.isEmpty || matchingRuntimeWait else { return wait }
                wait.desktopOwner = owner; wait.epoch = epoch; wait.boundAt = at
                if !matching.isEmpty { wait.nativeRequestIdentities = matching }
                return wait
            }
            unidentifiedWaits = unidentifiedWaits.compactMap(reconcile)
            let genericKeys = Set(requests.filter { $0.isGeneric && $0.desktopIdentity == nil }.map(\.key))
            var settledKeys: Set<String> = []
            for key in genericKeys {
                guard let evidence = genericWaitEvidence[key] else { continue }
                if let updated = reconcile(evidence) { genericWaitEvidence[key] = updated }
                else { genericWaitEvidence.removeValue(forKey: key); settledKeys.insert(key) }
            }
            requests.removeAll { $0.isGeneric && settledKeys.contains($0.key) }
            // Received-at guards replay only. A negative snapshot alone never
            // establishes ordering with a Hook from another transport.
            clampSelection()
        }
        @discardableResult
        mutating func resolveDesktopRequests(owner: String, epoch: UInt64,
            pending: Set<CodexDesktopPendingRequestIdentity>, asyncQuestions: Set<String>,
            asyncQuestionsAreAuthoritative: Bool = true, at: Date = Date()) -> Bool {
            let matching = requests.filter { request in
                guard request.desktopEpoch == epoch, request.desktopOwner == owner,
                      let identity = request.desktopIdentity else { return false }
                switch identity {
                case .server(let identity): return !pending.contains(identity)
                case .asynchronousQuestion(let id): return asyncQuestionsAreAuthoritative && !asyncQuestions.contains(id)
                }
            }
            // Only disappearance from the admitted owner's complete pending
            // set starts this transition. A click, ACK or timeout cannot do so.
            if pending.isEmpty, asyncQuestions.isEmpty,
               let settled = matching.first(where: { $0.blocksExecution && !$0.isGeneric && $0.desktopIdentity != nil }) {
                desktopSettlementPresentation = .init(owner: owner, epoch: epoch,
                    reason: settled.mode == .synchronous ? .userInput : .approval, settledAt: at,
                    identities: Set(matching.compactMap { if case .server(let id)? = $0.desktopIdentity { return id }; return nil }),
                    callHashes: Set(matching.compactMap(\.callHash)))
            }
            let keys = Set(matching.map(\.key))
            requests.removeAll { keys.contains($0.key) }
            for call in Set(matching.compactMap(\.callHash))
                where !requests.contains(where: { $0.callHash == call }) { rememberCall(call) }
            settleSourceWait(for: matching); clampSelection()
            return !matching.isEmpty
        }
        mutating func resolveDesktopAnswers(owner: String, epoch: UInt64, answered: Set<String>) {
            requests.removeAll {
                guard $0.desktopOwner == owner, $0.desktopEpoch == epoch,
                      case .asynchronousQuestion(let id)? = $0.desktopIdentity else { return false }
                return answered.contains(id)
            }
            clampSelection()
        }
        mutating func invalidateDesktopResponses(epoch: UInt64? = nil) {
            desktopSettlementPresentation = nil
            for i in requests.indices where requests[i].desktopIdentity != nil && (epoch == nil || requests[i].desktopEpoch == epoch) {
                requests[i].value.canRespond = false
                if !requests[i].value.phase.canSubmit { requests[i].value.phase = .resultUnknown }
            }
        }
        mutating func setSourceWait(_ reason: CodexActivityWaitReason?, waiting: Bool, epoch: UInt64, at: Date = Date()) {
            if waiting {
                guard sourceWait.map({ at >= $0.observedAt }) ?? true else { return }
                let identities = Set(requests.filter { belongsToSourceWait($0, reason: reason, epoch: epoch) }.compactMap(requestIdentity))
                sourceWait = .init(reason: reason, epoch: epoch, observedAt: at, source: .appServer,
                    requestIdentities: identities.isEmpty ? nil : identities)
            } else if let wait = sourceWait, wait.epoch == epoch, at > wait.observedAt {
                sourceWait = nil
            }
            // Direct flags can retire this connection's own source wait. They
            // do not identify a Hook notice on an independent transport.
        }
        private func requestIdentity(_ request: Pending) -> String? {
            if request.desktopIdentity != nil { return request.key }
            if let epoch = request.rpcEpoch, let wire = request.value.protocolRequest {
                return "rpc:" + Self.rpcKey(wire.rpcIdentity, epoch: epoch)
            }
            if let call = request.callHash { return "call:" + call }
            return nil
        }
        private func belongsToSourceWait(_ request: Pending, reason: CodexActivityWaitReason?, epoch: UInt64) -> Bool {
            guard request.blocksExecution, !request.isGeneric,
                  request.value.protocolRequest?.observationOnly != true else { return false }
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
        mutating func finishTurn() {
            desktopSettlementPresentation = nil
            requests.removeAll(); sourceWait = nil; unidentifiedWaits.removeAll(); unidentifiedWaitOverflow = false
            unidentifiedWaitOverflowIsWeak = true
            desktopRuntimeWait = nil; genericWaitEvidence.removeAll(); hookTools.removeAll(); hookToolsOverflowed = false
            hookHistoryFloor = .distantPast; uncertainHistoricalHookCalls.removeAll()
            completedHookTools.removeAll(); completedHookToolOrder.removeAll(); requestIndex = 0
            retiredObserverCallHashes.removeAll()
        }
        private mutating func rememberObserverCall(_ hash: String) {
            retiredObserverCallHashes.removeAll { $0 == hash }; retiredObserverCallHashes.append(hash)
            if retiredObserverCallHashes.count > 256 { retiredObserverCallHashes.removeFirst() }
        }
        private mutating func rememberCall(_ hash: String) {
            resolvedCallHashes.removeAll { $0 == hash }; resolvedCallHashes.append(hash)
            if resolvedCallHashes.count > 256 { resolvedCallHashes.removeFirst() }
        }
        private mutating func clampSelection() { requestIndex = requestIndex }
    }
}
