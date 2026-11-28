import Foundation
import QuotaViewCore
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

/// Desktop approval observation, history and account reads for Antigravity.
@MainActor
final class AntigravityAgentAdapter {
    private let context: NativeAgentHookContext
    var accountAvailabilityChanged: (() -> Void)?
    var installationChanged: ((NativeAgentRuntime.AGYInstallation) -> Void)?
    private var agyInstallation: NativeAgentRuntime.AGYInstallation = .missing {
        didSet { installationChanged?(agyInstallation) }
    }
    private struct Metadata {
        var lineageTask: Task<Void, Never>?
        var lineageResolved = false
        var turnStep: Int?
        var client: String?
        var firstStep: Int?
        var progressTask: Task<Void, Never>?
        var countedSteps: Set<Int> = []
    }
    private var metadata: [String: Metadata] = [:]
    private var usageTasks: [UUID: Task<Void, Never>] = [:]
    private let readsInstalledAccount: Bool
    private var accountTimer: Task<Void, Never>?
    private var accountRead: Task<AntigravityAccount?, Never>?
    private let scanner = AntigravityUsageScanner()
    private var detailTasks: [String: Task<Void, Never>] = [:]
    private var usageScan: Task<Void, Never>?
    private var scanDirty = false
    private struct ApprovalRequest {
        let key: String
        let turn: String
        let card: AntigravityDesktopApproval.Card
        let rpcID: IslandApprovalJSON
    }
    private var requests: [String: ApprovalRequest] = [:]
    private var approvalPoll: Task<Void, Never>?
    private var handledCards: [UUID: AntigravityDesktopApproval.Card] = [:]
    private let readApprovalCards: (Set<UUID>) async -> [UUID: AntigravityDesktopApproval.Card]
    private let answerNativeQuestion: NativeAgentRuntime.AnswerNativeQuestion
    private let pressApprovalButton: (AntigravityDesktopApproval.Card, Bool) -> Bool

    init(context hookContext: NativeAgentHookContext, readsInstalledAccount: Bool,
         readApprovalCards: @escaping (Set<UUID>) async -> [UUID: AntigravityDesktopApproval.Card],
         pressApprovalButton: @escaping (AntigravityDesktopApproval.Card, Bool) -> Bool,
         answerNativeQuestion: @escaping NativeAgentRuntime.AnswerNativeQuestion) {
        self.context = hookContext
        self.readsInstalledAccount = readsInstalledAccount
        self.readApprovalCards = readApprovalCards
        self.pressApprovalButton = pressApprovalButton
        self.answerNativeQuestion = answerNativeQuestion
        context.island.model.antigravityResponseCapability = { [weak self] wire in
            guard let self, wire.isAntigravity, context.enabled, context.listening, antigravityApprovalsEnabled,
                  let live = requests[String(wire.rpcID.text.dropFirst("antigravity:".count))] else { return false }
            return handledCards[live.card.conversation] != live.card && live.key == wire.threadID && live.turn == wire.turnID && context.sessions[live.key]?.active == true
                && context.sessions[live.key]?.turn == live.turn
        }
        context.island.model.antigravityRespond = { [weak self] wire, result in
            guard let self, context.island.model.antigravityResponseCapability?(wire) == true, wire.permits(result) else { throw CocoaError(.userCancelled) }
            let id = String(wire.rpcID.text.dropFirst("antigravity:".count))
            guard let request = requests[id] else { throw CancellationError() }
            let session = request.card.conversation
            let current = await self.readApprovalCards([session])
            guard context.island.model.antigravityResponseCapability?(wire) == true,
                  current[session] == request.card else {
                removeApprovalRequest(id)
                throw CancellationError()
            }
            if request.card.question != nil {
                guard let answer = result["answers"]["answer"]["answers"].array.first?.text,
                      await answerNativeQuestion(request.card, answer, {
                          self.context.island.model.antigravityResponseCapability?(wire) == true
                      }) else { throw CocoaError(.userCancelled) }
                handledCards[session] = request.card
                // AXPress confirms dispatch. The next native scan retires
                // the card when the original question actually disappears.
                return
            }
            let allow: Bool
            switch result["decision"].text {
            case "accept": allow = true
            case "decline": allow = false
            default: throw CocoaError(.coderInvalidValue)
            }
            guard self.pressApprovalButton(request.card, allow) else { throw CocoaError(.userCancelled) }
            handledCards[session] = request.card
            removeApprovalRequest(id)
        }
    }

    func checkAGYInstallation() {
        guard context.provider == .antigravity, agyInstallation != .installing else { return }
        if AntigravityCLI.executable() != nil {
            agyInstallation = .installed
        } else if agyInstallation != .failed {
            agyInstallation = .missing
        }
    }

    func installAGY() {
        checkAGYInstallation()
        guard context.provider == .antigravity, agyInstallation == .missing || agyInstallation == .failed else { return }
        agyInstallation = .installing
        Task {
            let installed = await Task.detached(priority: .utility) { AntigravityCLI.install() }.value
            agyInstallation = installed ? .installed : .failed
            if installed { await refreshAntigravityAccount() }
        }
    }
    private var antigravityApprovalsEnabled: Bool {
        context.preferences.antigravityInteractiveApprovals && context.preferences.codexActivityIslandEnabled && !context.preferences.codexIslandPrivacy
    }

    func start() {
        context.island.antigravityUsage = .init()
        if readsInstalledAccount {
            accountTimer = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshAntigravityAccount()
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                }
            }
        }
        Task { await refreshAntigravityUsage() }
    }

    func stop() {
        approvalPoll?.cancel()
        approvalPoll = nil
        handledCards.removeAll()
        for id in Array(requests.keys) { removeApprovalRequest(id) }
        for task in detailTasks.values { task.cancel() }
        detailTasks.removeAll()
        usageScan?.cancel(); usageScan = nil; scanDirty = false
        accountTimer?.cancel(); accountTimer = nil
        accountRead?.cancel(); accountRead = nil
        context.island.antigravityUsage = nil
        for task in usageTasks.values { task.cancel() }
        usageTasks.removeAll()
        for state in metadata.values { state.progressTask?.cancel(); state.lineageTask?.cancel() }
        metadata.removeAll()
    }

    func removeSession(_ key: String) {
        let state = metadata.removeValue(forKey: key)
        state?.progressTask?.cancel()
        state?.lineageTask?.cancel()
        detailTasks.removeValue(forKey: key)?.cancel()
    }

    func prepareSession(_ key: String, source: String, name: String, payload: [String: Any], startedTurn: Bool, session: inout NativeAgentHookContext.Session) {
        var state = metadata[key] ?? Metadata()
        if startedTurn {
            state.countedSteps.removeAll()
            state.turnStep = payload["first_step"] as? Int
        }
        let previousClient = state.client
        if let client = payload["log_client"] as? String,
           AntigravityHistory.clients.contains(client) { state.client = client }
        if name == "TurnStarted", let ms = payload["rate_event_ms"] as? Double {
            state.firstStep = payload["first_step"] as? Int
            session.rateRequestStart = Date(timeIntervalSince1970: ms / 1000)
            session.rateRequestID = UUID().uuidString
        }
        let ended = ["Stop", "Interrupt", "StopFailure", "SessionEnd"].contains(name)
        if startedTurn || ended || previousClient != state.client {
            state.progressTask?.cancel()
            state.progressTask = nil
        }
        if !ended, session.active, session.parent == nil, let turn = session.turn, state.progressTask == nil {
            let root = context.installer.home.deletingLastPathComponent()
            let client = state.client, first = state.turnStep, start = session.turnStartedAt
            state.progressTask = Task.detached(priority: .utility) { [weak self] in
                var reader = AntigravityHistory.ProgressReader()
                while !Task.isCancelled {
                    let batch = reader.read(root: root, session: source, client: client, first: first, start: start)
                    if !batch.focuses.isEmpty || batch.planChanged {
                        await self?.publishProgress(batch, key: key, turn: turn)
                    }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        }
        if previousClient != state.client {
            state.lineageTask?.cancel()
            state.lineageTask = nil
            state.lineageResolved = false
        }
        if !state.lineageResolved, state.lineageTask == nil {
            let client = state.client
            state.lineageTask = Task { [weak self] in
                await self?.resolveLineage(key: key, source: source, client: client)
            }
        }
        metadata[key] = state
    }

    private func resolveLineage(key: String, source: String, client: String?) async {
        let root = context.installer.home.deletingLastPathComponent()
        var attempt = 0
        while !Task.isCancelled {
            let relation = await Task.detached(priority: .utility) {
                AntigravityHistory.lineage(root: root, session: source, client: client)
            }.value
            guard !Task.isCancelled, context.running, let session = context.sessions[key] else { return }
            if case .root = relation, session.parent == nil {
                metadata[key]?.lineageResolved = true
                break
            }
            if case let .child(parent, role) = relation, session.parent == nil || session.parent == parent,
               let identity = CodexActivitySubagentIdentity(threadID: "antigravity:" + source.lowercased(),
                   parentThreadID: "antigravity:" + parent, role: role) {
                if session.parent == nil || role != nil {
                    context.sessions[key]?.parent = parent
                    context.sessions[key]?.conversation = nil
                    metadata[key]?.progressTask?.cancel()
                    metadata[key]?.progressTask = nil
                    context.island.model.receiveSubagentIdentity(identity, migratingTurn: session.turn)
                    refreshApprovalMonitor()
                }
                if role != nil || attempt >= 5 {
                    metadata[key]?.lineageResolved = true
                    break
                }
            }
            if attempt >= 5 && !session.active { break }
            attempt += 1
            // Keep a quiet active turn recoverable without scanning every hook or every second.
            let delay: Duration = attempt < 5 ? .milliseconds(400) : .seconds(min(30, attempt))
            do { try await Task.sleep(for: delay) } catch { return }
        }
        if !Task.isCancelled { metadata[key]?.lineageTask = nil }
    }

    private func publishProgress(_ batch: AntigravityHistory.ProgressBatch, key: String, turn: String) {
        guard !Task.isCancelled, context.enabled, context.running, context.sessions[key]?.active == true, context.sessions[key]?.parent == nil,
              context.sessions[key]?.turn == turn else { return }
        if batch.planChanged { context.island.model.receiveObservedPlan(batch.plan, key: key, turn: turn) }
        if !batch.focuses.isEmpty { context.island.model.receiveAntigravityFocus(batch.focuses, key: key, turn: turn) }
    }

    func conversation(_ key: String, id: UUID) -> IslandConversationTarget? {
        switch metadata[key]?.client {
        case "antigravity": return .antigravity(id)
        case nil: return .antigravityHook(id)
        default: return nil
        }
    }

    func observeUsage(key: String, sourceSession: String, turn: String, session: NativeAgentHookContext.Session, name: String, payload: [String: Any]) {
        if session.parent != nil {
            if ["Usage", "Stop"].contains(name) { Task { await refreshAntigravityUsage() } }
            return
        }
        if ["Usage", "Stop"].contains(name), let id = session.rateRequestID,
           let start = session.rateRequestStart, let endMS = payload["rate_event_ms"] as? Double,
           UUID(uuidString: sourceSession) != nil {
            context.sessions[key]?.rateRequestStart = nil
            let root = context.installer.home.deletingLastPathComponent()
            let hint = metadata[key]?.client
            let step = metadata[key]?.firstStep
            let end = Date(timeIntervalSince1970: endMS / 1000)
            let version = context.revision
            let taskID = UUID()
            usageTasks[taskID] = Task { [weak self] in
                defer { self?.usageTasks.removeValue(forKey: taskID) }
                for _ in 0..<40 {
                    guard let self, !Task.isCancelled, context.running, context.enabled, context.revision == version, context.sessions[key]?.turn == turn else { return }
                    if let usage = await Task.detached(priority: .utility, operation: { () -> (step: Int, output: Int64, total: Int64?)? in
                        guard let logs = AntigravityHistory.logs(root: root, session: sourceSession, client: hint) else { return nil }
                        return Self.antigravityUsage(logs.appendingPathComponent("transcript_full.jsonl"), step: step, start: start, end: end)
                    }).value {
                        guard !Task.isCancelled, context.revision == version, context.enabled, context.sessions[key]?.turn == turn else { return }
                        guard context.sessions[key]?.parent == nil else { await refreshAntigravityUsage(); return }
                        guard metadata[key]?.countedSteps.insert(usage.step).inserted == true else { return }
                        if let rate = AgentRateObservation(id: id, output: usage.output, durationMS: end.timeIntervalSince(start) * 1000, end: end) {
                            context.receiveRates([rate], key: key, turn: turn)
                        }
                        if let total = usage.total {
                            context.sessions[key]?.tokens += total
                            let sum = context.sessions[key]?.tokens ?? total
                            context.island.model.receiveToken(.init(sessionHash: key, turnHash: turn, cumulativeTotalTokens: sum, lastReportedTotalTokens: total, directTurnTotalTokens: sum))
                        }
                        await refreshAntigravityUsage()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
    }

    private struct AntigravityTurn: Equatable {
        let key: String
        let turn: String
    }

    private var approvalTurns: [UUID: AntigravityTurn] {
        guard context.running, context.enabled, context.listening, antigravityApprovalsEnabled else { return [:] }
        var targets: [UUID: AntigravityTurn] = [:]
        for (key, session) in context.sessions where session.active && session.parent == nil {
            guard let turn = session.turn else { continue }
            switch session.conversation {
            case .antigravity(let id), .antigravityHook(let id): targets[id] = .init(key: key, turn: turn)
            default: break
            }
        }
        return targets
    }

    func refreshApprovalMonitor() {
        let turns = approvalTurns
        for (id, request) in requests where turns[request.card.conversation]?.turn != request.turn {
            removeApprovalRequest(id)
        }
        handledCards = handledCards.filter { turns[$0.key] != nil }
        guard !turns.isEmpty else {
            approvalPoll?.cancel()
            approvalPoll = nil
            return
        }
        guard approvalPoll == nil else { return }
        approvalPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let turns = self?.approvalTurns, !turns.isEmpty else { return }
                let cards = await self?.readApprovalCards(Set(turns.keys)) ?? [:]
                guard !Task.isCancelled else { return }
                self?.updateAntigravityCards(cards, scannedTurns: turns)
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            }
        }
    }

    private func updateAntigravityCards(_ cards: [UUID: AntigravityDesktopApproval.Card], scannedTurns: [UUID: AntigravityTurn]) {
        let turns = approvalTurns
        for (id, request) in requests where cards[request.card.conversation] != request.card {
            removeApprovalRequest(id)
        }
        for (conversation, card) in cards {
            guard conversation == card.conversation, let scope = turns[conversation], scope == scannedTurns[conversation],
                  handledCards[conversation] != card,
                  !requests.values.contains(where: { $0.card == card }) else { continue }
            let key = scope.key, turn = scope.turn
            let id = UUID().uuidString
            var params: [String: Any] = ["antigravity": true, "threadId": key, "turnId": turn, "itemId": id]
            let method: String
            if let question = card.question {
                method = "item/tool/requestUserInput"
                params["questions"] = [["id": "answer", "question": card.content, "isOther": true,
                    "options": question.options.map { ["label": $0.label] }]]
            } else if let nativeScope = card.scope {
                method = "item/commandExecution/requestApproval"
                params["command"] = card.content
                params["nativeScope"] = nativeScope.rawValue
                params["availableDecisions"] = ["accept", "decline"]
            } else { continue }
            guard let data = try? JSONSerialization.data(withJSONObject: ["id": "antigravity:" + id,
                "method": method, "params": params]),
                  let wire = try? IslandCodexApprovalRequest(data: data) else { continue }
            requests[id] = .init(key: key, turn: turn, card: card, rpcID: wire.rpcID)
            if !context.island.model.observeNativeToolRequest(wire, sessionKey: key, turnKey: turn, callHash: id) {
                removeApprovalRequest(id)
            }
        }
    }

    private func removeApprovalRequest(_ id: String) {
        guard let request = requests.removeValue(forKey: id) else { return }
        context.island.model.resolveLocalHookRequest(sessionKey: request.key, rpcID: request.rpcID)
    }

    func refreshAntigravityAccount(manual: Bool = false) async {
        guard context.provider == .antigravity, readsInstalledAccount, context.running, context.enabled else { return }
        if let read = accountRead { _ = await read.value; return }
        let version = context.revision
        let read = Task.detached(priority: .utility) { AntigravityAccount.read(manual: manual) }
        accountRead = read
        let account = await read.value
        guard context.revision == version, context.enabled else { return }
        accountRead = nil
        if var usage = context.island.antigravityUsage {
            if !usage.didCheckAccount || (usage.account?.windows.isEmpty == false) != (account?.windows.isEmpty == false) {
                accountAvailabilityChanged?()
            }
            usage.account = account
            usage.didCheckAccount = true
            context.island.antigravityUsage = usage
        }
    }

    func refreshAntigravityUsage() async {
        guard context.provider == .antigravity, context.running, context.enabled else { return }
        if let usageScan {
            scanDirty = true
            await usageScan.value
            return
        }
        let version = context.revision, root = context.installer.home.deletingLastPathComponent()
        let task = Task {
            repeat {
                scanDirty = false
                var usage = await scanner.scan(root: root)
                guard !Task.isCancelled, context.revision == version, context.enabled else { return }
                usage.account = context.island.antigravityUsage?.account
                usage.didCheckAccount = context.island.antigravityUsage?.didCheckAccount ?? false
                context.island.antigravityUsage = usage
            } while scanDirty
            usageScan = nil
        }
        usageScan = task
        await task.value
    }

    func refreshDetail(key: String, source: String, turn: String, session: NativeAgentHookContext.Session, event: String) {
        detailTasks[key]?.cancel()
        let version = context.revision, root = context.installer.home.deletingLastPathComponent()
        let state = metadata[key]
        let client = state?.client, first = state?.turnStep, start = session.turnStartedAt
        let end = Date(), finished = event == "Stop"
        detailTasks[key] = Task { [weak self] in
            var receivedFinal = false
            for attempt in 0..<(finished ? 17 : 3) {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: attempt < 10 ? 400_000_000 : 8_000_000_000)
                }
                guard !Task.isCancelled else { return }
                let needsReplies = !receivedFinal
                let (title, replies) = await Task.detached(priority: .utility) {
                    guard let logs = AntigravityHistory.logs(root: root, session: source, client: client) else {
                        return (nil as String?, [AntigravityHistory.Reply]())
                    }
                    let database = logs.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        .deletingLastPathComponent().appendingPathComponent("conversation_summaries.db")
                    return (AntigravityHistory.title(database: database, session: source),
                            needsReplies ? AntigravityHistory.replies(logs: logs, firstStep: first, start: start, end: end) : [])
                }.value
                guard let self, !Task.isCancelled, context.revision == version, context.enabled, context.sessions[key]?.turn == turn else { return }
                if let title, context.sessions[key]?.title != title { context.sessions[key]?.title = title; context.publishMetadata(key) }
                let finalIndex = replies.last.flatMap { last in
                    finished && !last.hasTools && last.index >= (state?.firstStep ?? 0) ? last.index : nil
                }
                for reply in replies {
                    let final = reply.index == finalIndex
                    let row: [String: Any] = ["type": "message", "id": "antigravity-step-" + String(reply.index),
                        "channel": final ? "final" : "commentary", "text": reply.text, "sourceTruncated": reply.truncated]
                    if let data = try? JSONSerialization.data(withJSONObject: row) {
                        context.island.model.receiveLocalContent(.init(publicSessionHash: key, turnHash: turn, data: data, occurredAt: reply.date))
                    }
                }
                receivedFinal = receivedFinal || finalIndex != nil
                if title != nil && (event == "TurnStarted" || receivedFinal || (!finished && !replies.isEmpty)) { break }
            }
            self?.detailTasks[key] = nil
        }
    }

    nonisolated static func antigravityUsage(_ file: URL, step: Int?, start: Date, end: Date) -> (step: Int, output: Int64, total: Int64?)? {
        guard file.resolvingSymlinksInPath().standardizedFileURL == file.standardizedFileURL,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return nil }
        let size = min(length, 2_097_152)
        guard (try? handle.seek(toOffset: length - size)) != nil, let data = try? handle.read(upToCount: Int(size)) else { return nil }
        // created_at has one-second resolution in desktop logs. Intermediate
        // system and tool steps can precede the actual planner response.
        let clock = ISO8601DateFormatter()
        var matches: [(step: Int, output: Int64, total: Int64?)] = []
        for line in data.split(separator: 10) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  row["type"] as? String == "PLANNER_RESPONSE", let index = row["step_index"] as? Int,
                  let timestamp = row["created_at"] as? String, let date = clock.date(from: timestamp),
                  date.timeIntervalSince1970 >= floor(start.timeIntervalSince1970) - 1, date <= end,
                  let output = AgentRateObservation.integer(row["output_tokens"]), (0...1_000_000_000).contains(output) else { continue }
            matches.append((index, output, AntigravityHistory.tokens(row)))
        }
        let candidates = matches.filter { candidate in step.map { candidate.step >= $0 } ?? true }
        guard let selected = candidates.first, candidates.count == 1 || selected.step == step else { return nil }
        return selected
    }
}
