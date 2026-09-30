import AppKit
import Foundation
import QuotaViewCore

/// Identity, ordering and request lifecycle are independent of presentation/focus.
/// Shared Desktop connections are observers until response ownership is established.
@MainActor
final class IslandLiveStore {
    struct TaskRecord {
        let id: Int
        let key: String
        var threadID: String?
        var turnKey: String?
        var title = ""
        var model = ""
        var effort = ""
        var status: IslandTaskStatus = .thinking
        var operation = ""
        var tokens: Int64?
        var startedAt: Date?
        var endedAt: Date?
        var updatedAt = Date.distantPast
        // nil means no structured plan: let the shared single-island resolver
        // perform its 4-second discovery and bounded unplanned estimate.
        var progress: Double?
        var progressResolver = CodexActivityStateSmokeProgressResolver()
        var progressUpdatedAt: Date?
        var displayedProgress: Double = 0.01
        var legacyEventDates: [String: Date] = [:]
        var nativeContentAvailable = false
        var nativeState = false
        var waitingOnSource = false
        var entries: [IslandTraceEntry] = []
        var requests: [Pending] = []
        var requestIndex = 0
        var removedEntryCount = 0
        var activeItems: [String: String] = [:]
        var terminal: Bool { [.completed, .failed, .cancelled].contains(status) }
    }
    struct Pending: Equatable {
        let key: String
        var value: IslandConfirmation
    }
    private(set) var tasks: [TaskRecord] = []
    private(set) var selectedID = 0
    private(set) var connection = CodexSharedAppServerConnectionState.discovering
    private(set) var connectionEpoch = 0
    var preservedID: Int?
    private var nextID = 1
    private var priorTurnKeys: [String: Set<String>] = [:]
    private var metadata: [String: [String: Any]] = [:]
    var onChange: (() -> Void)?
    var onPublicChange: (() -> Void)?
    private var pendingLocalContent: [CodexLocalPublicContent] = []
    var responseCapability: ((IslandCodexApprovalRequest) -> Bool)?
    var respond: ((IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void)?

    func reset() { tasks.removeAll(); metadata.removeAll(); priorTurnKeys.removeAll(); itemContexts.removeAll(); pendingLocalContent.removeAll(); selectedID = 0; connectionEpoch += 1; onChange?() }
    func select(_ id: Int) { if tasks.contains(where: { $0.id == id }) { selectedID = id; onChange?() } }
    func setConnection(_ state: CodexSharedAppServerConnectionState) {
        guard state != connection else { return }
        if state != .connected {
            connectionEpoch += 1
            for i in tasks.indices {
                for j in tasks[i].requests.indices {
                    tasks[i].requests[j].value.canRespond = false
                    if !tasks[i].requests[j].value.phase.canSubmit { tasks[i].requests[j].value.phase = .resultUnknown }
                }
            }
        }
        connection = state; onChange?()
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
        // Socket content uses receipt time; rollout lifecycle uses persisted event
        // time. Comparing those clocks drops a delayed, authoritative completion.
        let source = event.source?.rawValue ?? "legacy"
        guard event.occurredAt >= (tasks[i].legacyEventDates[source] ?? .distantPast) else { return }
        if let key, tasks[i].turnKey != nil, tasks[i].turnKey != key { return }
        if tasks[i].terminal && !active { return }
        tasks[i].legacyEventDates[source] = event.occurredAt
        tasks[i].updatedAt = max(tasks[i].updatedAt, event.occurredAt)
        if tasks[i].title.isEmpty { tasks[i].title = event.workspaceName ?? "" }
        switch event.event {
        case .userPromptSubmit: tasks[i].status = .thinking; tasks[i].operation = ""
        case .preToolUse: tasks[i].status = .working; tasks[i].operation = ""
        case .permissionRequest: tasks[i].status = .waiting; ensureReadOnlyRequest(i)
        case .preCompact: tasks[i].status = .compacting
        case .postCompact: if tasks[i].status == .compacting { tasks[i].status = .thinking }
        case .stop:
            switch event.turnCompletionStatus {
            case .failed: tasks[i].status = .failed
            case .interrupted: tasks[i].status = .cancelled
            default: tasks[i].status = .completed; tasks[i].progress = 1
            }
            tasks[i].endedAt = event.occurredAt; tasks[i].requests.removeAll(); tasks[i].activeItems.removeAll()
        case .interrupt: tasks[i].status = .cancelled; tasks[i].endedAt = event.occurredAt; tasks[i].requests.removeAll(); tasks[i].activeItems.removeAll()
        default: break
        }
        if !tasks[i].terminal && (tasks[i].waitingOnSource || tasks[i].requests.contains(where: { $0.value.protocolRequest?.kind != .questions })) { tasks[i].status = .waiting }
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
        if type == "metadata" {
            if let model = p["model"] as? String, !model.isEmpty { tasks[i].model = model }
            if let effort = p["effort"] as? String, !effort.isEmpty { tasks[i].effort = effort }
        } else {
            guard !(tasks[i].nativeContentAvailable && connection == .connected), let id = p["id"] as? String else { return }
            if type == "output" {
                if let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == id }) {
                    let output = p["text"] as? String ?? ""
                    tasks[i].entries[j].publicItem?.output = String(output.prefix(65536))
                    tasks[i].entries[j].publicItem?.sourceTruncated = output.count > 65536
                    tasks[i].entries[j].publicItem?.status = "completed"
                }
                tasks[i].activeItems.removeValue(forKey: id)
                if tasks[i].activeItems.isEmpty && tasks[i].status == .working { tasks[i].status = .thinking; tasks[i].operation = "" }
            } else {
                let message = type == "message"
                let name = p["name"] as? String ?? ""
                let body = p["text"] as? String ?? ""
                let text = message ? body : name + "\n" + body
                upsert(.init(text: .init(String(text.prefix(65536))), publicItem: .init(category: message ? .message : .command,
                    sourceID: id, turnID: content.turnHash, status: message ? "completed" : "inProgress", sourceTruncated: text.count > 65536)), at: i)
                if message && tasks[i].status == .thinking { tasks[i].operation = String(body.prefix(240)) }
                else if !message && !tasks[i].terminal && tasks[i].status != .waiting {
                    let args = body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    let detail = args?["cmd"] as? String ?? args?["code"] as? String ?? args?["command"] as? String ?? body
                    let label = name.split(separator: ".").last.map(String.init) ?? name
                    let description = label + " · " + String(detail.replacingOccurrences(of: "\n", with: " ").prefix(240))
                    tasks[i].activeItems[id] = description; tasks[i].status = .working; tasks[i].operation = description
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
        tasks[i].status = .thinking; tasks[i].waitingOnSource = false; tasks[i].progress = nil; tasks[i].operation = ""
        tasks[i].progressResolver.reset(); tasks[i].progressUpdatedAt = date; tasks[i].displayedProgress = 0.01
        tasks[i].legacyEventDates.removeAll()
        tasks[i].activeItems.removeAll(); tasks[i].requests.removeAll(); tasks[i].requestIndex = 0; tasks[i].nativeContentAvailable = false
        tasks[i].entries.removeAll(); tasks[i].removedEntryCount = 0; tasks[i].updatedAt = date
    }
    private func ensureReadOnlyRequest(_ i: Int) {
        guard tasks[i].requests.isEmpty else { return }
        tasks[i].requests.append(.init(key: "observer-placeholder", value: .init(
            question: .init("Codex 正在等待确认", "Codex is waiting for confirmation"),
            impact: .init("当前来源只提供等待状态。请在 Codex 查看完整请求并处理。", "This source supplies the waiting status only. Review and handle the request in Codex."))))
    }
    func nextRequest(_ id: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), !tasks[i].requests.isEmpty else { return }
        tasks[i].requestIndex = (tasks[i].requestIndex + 1) % tasks[i].requests.count; onChange?()
    }
    func receive(_ data: Data, at now: Date = Date()) {
        guard data.count <= 1_048_576, let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = m["method"] as? String, !method.contains("reasoning"),
              let p = m["params"] as? [String: Any] else { return }
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
            if active { tasks[i].nativeState = true; applyFlags(status, at: i) }
            onChange?(); return
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
            let requestKey = "\(connectionEpoch):\(wire.key)"
            if let j = tasks[i].requests.firstIndex(where: { $0.key == requestKey }) {
                if tasks[i].requests[j].value.protocolRequest?.raw == data { return }
                tasks[i].requests.remove(at: j)
            }
            guard !tasks[i].terminal else { return }
            tasks[i].requests.removeAll { $0.key == "observer-placeholder" }
            let question = !wire.questions.isEmpty ? wire.questions[0].title : wire.params["message"].text.isEmpty ? (wire.params["reason"].text.isEmpty ? "Codex 请求你的处理" : wire.params["reason"].text) : wire.params["message"].text
            let canRespond = respond != nil && responseCapability?(wire) == true && wire.kind != .nativeOnly && wire.kind != .mcpURL && (wire.kind != .mcpForm || wire.supportedForm)
            tasks[i].requests.append(.init(key: requestKey, value: .init(question: .init(question),
                impact: .init("当前连接为观察模式，请在 Codex 完成处理。", "This connection is an observer. Handle this request in Codex."), protocolRequest: wire, canRespond: canRespond)))
            if wire.kind != .questions { tasks[i].status = .waiting }
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
            tasks[i].status = status == "completed" ? .completed : status == "interrupted" ? .cancelled : .failed
            tasks[i].progress = status == "completed" ? 1 : tasks[i].progress
            tasks[i].endedAt = eventDate(turn?["completedAtMs"], fallback: now)
            tasks[i].requests.removeAll(); tasks[i].activeItems.removeAll()
            if let error = turn?["error"] as? [String: Any], let message = error["message"] as? String {
                upsert(.init(text: .init(message), kind: .failure), at: i)
            }
        case "thread/status/changed": applyFlags(p["status"] as? [String: Any], at: i)
        case "thread/tokenUsage/updated":
            if let usage = CodexAppServerActivityNotificationDecoder.decodeTokenUsage(data: data, now: now) { receiveToken(usage) }
        case "turn/plan/updated":
            if !tasks[i].terminal, let event = CodexAppServerActivityNotificationDecoder.decode(data: data, now: now) {
                tasks[i].progress = event.planProgress?.approximateFraction
            }
        case "serverRequest/resolved":
            if let raw = p["requestId"], let id = try? IslandApprovalJSON(any: raw) {
                tasks[i].requests.removeAll { $0.value.protocolRequest?.rpcID == id }
                if tasks[i].requests.isEmpty && tasks[i].status == .waiting { tasks[i].waitingOnSource = false; tasks[i].status = tasks[i].activeItems.isEmpty ? .thinking : .working }
                tasks[i].requestIndex = min(tasks[i].requestIndex, max(0, tasks[i].requests.count - 1))
            }
        case "item/started", "item/completed":
            guard !tasks[i].terminal, let item = p["item"] as? [String: Any], let type = item["type"] as? String,
                  type != "reasoning", let itemID = item["id"] as? String else { break }
            if let context = try? IslandApprovalJSON(any: item) { itemContexts[key + ":" + itemID] = context }
            if type == "contextCompaction" { tasks[i].status = method == "item/started" ? .compacting : .thinking; break }
            if method == "item/started" && type != "agentMessage" {
                let description = operationDescription(type, item: item)
                tasks[i].activeItems[itemID] = description
                if !tasks[i].waitingOnSource && !tasks[i].requests.contains(where: { $0.value.protocolRequest?.kind != .questions }) { tasks[i].status = .working }
                tasks[i].operation = description
            }
            if method == "item/completed" {
                tasks[i].activeItems.removeValue(forKey: itemID)
                if tasks[i].waitingOnSource || tasks[i].requests.contains(where: { $0.value.protocolRequest?.kind != .questions }) { tasks[i].status = .waiting }
                else if tasks[i].activeItems.isEmpty {
                    tasks[i].status = .thinking
                    tasks[i].operation = String((tasks[i].entries.last(where: { $0.publicItem?.category == .message })?.text.chinese ?? "").prefix(240))
                }
                else { tasks[i].operation = tasks[i].activeItems.sorted { $0.key < $1.key }.last!.value }
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
    private func applyFlags(_ status: [String: Any]?, at i: Int) {
        guard !tasks[i].terminal, let status else { return }
        let flags = status["activeFlags"] as? [String] ?? []
        tasks[i].waitingOnSource = flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput")
        if tasks[i].waitingOnSource { tasks[i].status = .waiting; ensureReadOnlyRequest(i) }
        else if status["type"] as? String == "active", tasks[i].status == .waiting {
            tasks[i].status = tasks[i].activeItems.isEmpty ? .thinking : .working
            tasks[i].requests.removeAll { $0.key == "observer-placeholder" }
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
              let j = tasks[i].requests.firstIndex(where: { $0.value.id == requestID }),
              tasks[i].requests[j].value.canRespond, tasks[i].requests[j].value.phase.canSubmit,
              let wire = tasks[i].requests[j].value.protocolRequest, case .reply(let result) = decision,
              wire.permits(result), let respond else { return }
        tasks[i].requests[j].value.phase = .submitting(decision); onChange?()
        let epoch = connectionEpoch
        Task { [weak self] in
            do {
                try await respond(wire, result)
                guard let self, epoch == connectionEpoch, let i = tasks.firstIndex(where: { $0.id == id }),
                      let j = tasks[i].requests.firstIndex(where: { $0.value.id == requestID }) else { return }
                tasks[i].requests[j].value.phase = .sent; onChange?()
            } catch {
                guard let self, let i = tasks.firstIndex(where: { $0.id == id }), let j = tasks[i].requests.firstIndex(where: { $0.value.id == requestID }) else { return }
                tasks[i].requests[j].value.phase = .resultUnknown; tasks[i].requests[j].value.canRespond = false; onChange?()
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
        let items = tasks.map { task -> CodexMultitaskRenderTask in
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
            else if task.status == .waiting && request?.protocolRequest?.kind == .questions { status = english ? "Awaiting answer" : "等待回答" }
            else { status = copy.statusTitle(for: visual) }
            let render = CodexActivityRenderState(taskIdentity: .init(sessionHash: task.key, turnHash: task.turnKey),
                visualState: visual, approximateProgressFraction: task.displayedProgress,
                windowTitle: title, statusTitle: status, operation: privacy || task.status == .compacting ? "" : (task.status == .waiting
                    ? status + " · " + (request?.question.value(english) ?? "") : task.operation),
                tokenUsageTitle: task.tokens.map { CodexActivityTokenUsageFormatter.string(for: $0) + " tokens" },
                accessibilityLabel: "\(title), \(status)")
            return .init(id: task.id, renderState: render, playbackEnabled: !task.terminal || task.status == .completed, hasPendingRequest: !task.requests.isEmpty)
        }
        return .init(state: .init(tasks: items, selectedID: selectedID, allCompleted: !tasks.isEmpty && tasks.allSatisfy(\.terminal), compact: true, receiptStartedAt: nil),
            english: english, effect: .dropField, visible: enabled, playbackEnabled: true, totalTokens: nil, remainingPercent: remaining,
            sessionMetadata: metas, taskDetails: details, connectionTitle: connection == .connected ? (english ? "Connected" : "已连接") : (tasks.isEmpty ? (english ? "Waiting for Codex" : "等待 Codex 任务") : (english ? "Local activity" : "本地活动数据")), privacyMode: privacy, activeRequestIDs: privacy ? [] : Set(tasks.flatMap { $0.requests.map { $0.value.id } }))
    }
}
