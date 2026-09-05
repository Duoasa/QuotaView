import Foundation
import SQLite3

public enum CodexLocalRolloutDecodedUpdate: Equatable, Sendable {
    case activity(CodexActivityEvent)
    case tokenUsage(CodexActivityTokenUsageUpdate)
    case tokenUsageReplay([CodexActivityTokenUsageUpdate])
}

public struct CodexLocalRolloutDecodedRecord: Equatable, Sendable {
    public let eventID: String?
    public let update: CodexLocalRolloutDecodedUpdate

    public init(
        eventID: String?,
        update: CodexLocalRolloutDecodedUpdate
    ) {
        self.eventID = eventID
        self.update = update
    }
}

public struct CodexLocalRolloutLineDecoder: Sendable {
    public static let maximumLineBytes = 1_048_576

    private let sessionHash: String
    private let workspaceName: String?
    private let sessionKind: CodexActivitySessionKind
    private var activeTurnHash: String?

    public init(sessionHash: String, workspaceName: String? = nil, sessionKind: CodexActivitySessionKind = .unknown) {
        self.sessionHash = sessionHash
        self.workspaceName = workspaceName
        self.sessionKind = sessionKind
    }

    public mutating func decode(
        line: Data,
        now: Date = Date()
    ) -> CodexLocalRolloutDecodedRecord? {
        guard !line.isEmpty,
              line.count <= Self.maximumLineBytes,
              let object = try? JSONSerialization.jsonObject(with: line),
              let envelope = object as? [String: Any],
              let payload = envelope["payload"] as? [String: Any],
              let recordType = envelope["type"] as? String
        else {
            return nil
        }

        let occurredAt = Self.eventDate(
            from: envelope["timestamp"],
            fallback: now
        )
        let eventID = Self.eventID(
            sessionHash: sessionHash,
            ordinal: envelope["ordinal"],
            recordType: recordType,
            payloadType: payload["type"] as? String
        )

        if recordType == "token_usage_record" {
            guard let turnHash = activeTurnHash,
                  Self.hashedIdentifier(payload["turn_id"]) == turnHash,
                  Self.hashedIdentifier(payload["thread_id"]) == sessionHash,
                  let turn = payload["turn_token_usage"] as? [String: Any],
                  let thread = payload["thread_token_usage"] as? [String: Any],
                  let usage = payload["usage"] as? [String: Any],
                  let direct = CodexActivityNumeric.nonnegativeInteger(turn["total_tokens"]),
                  let cumulative = CodexActivityNumeric.nonnegativeInteger(thread["total_tokens"]),
                  let last = CodexActivityNumeric.nonnegativeInteger(usage["total_tokens"]),
                  cumulative >= direct, direct >= last
            else { return nil }
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .tokenUsage(CodexActivityTokenUsageUpdate(
                    sessionHash: sessionHash,
                    turnHash: turnHash,
                    cumulativeTotalTokens: cumulative,
                    lastReportedTotalTokens: last,
                    directTurnTotalTokens: direct,
                    occurredAt: occurredAt
                ))
            )
        }

        if recordType == "event_msg" {
            return decodeEventMessage(
                payload,
                eventID: eventID,
                occurredAt: occurredAt
            )
        }

        guard recordType == "response_item" else { return nil }
        return decodeToolCall(
            payload,
            eventID: eventID,
            occurredAt: occurredAt
        )
    }

    private mutating func decodeEventMessage(
        _ payload: [String: Any],
        eventID: String?,
        occurredAt: Date
    ) -> CodexLocalRolloutDecodedRecord? {
        guard let type = payload["type"] as? String else { return nil }

        switch type {
        case "item_started", "item_completed":
            guard let turnHash = activeTurnHash,
                  Self.hashedIdentifier(payload["turn_id"]) == turnHash,
                  Self.hashedIdentifier(payload["thread_id"]) == sessionHash,
                  let item = payload["item"] as? [String: Any],
                  item["type"] as? String == "ContextCompaction"
            else { return nil }
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(CodexActivityEvent(
                    event: type == "item_started" ? .preCompact : .postCompact,
                    sessionHash: sessionHash,
                    turnHash: turnHash,
                    workspaceName: workspaceName,
                    sessionKind: sessionKind,
                    source: .localRollout,
                    occurredAt: occurredAt
                ))
            )

        case "task_started":
            guard let turnHash = Self.hashedIdentifier(
                payload["turn_id"]
            ) else {
                return nil
            }
            activeTurnHash = turnHash
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(
                    CodexActivityEvent(
                        event: .userPromptSubmit,
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        workspaceName: workspaceName,
                        sessionKind: sessionKind,
                        source: .localRollout,
                        occurredAt: occurredAt
                    )
                )
            )

        case "token_count":
            guard let turnHash = activeTurnHash,
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"]
                    as? [String: Any],
                  let last = info["last_token_usage"]
                    as? [String: Any],
                  let cumulative = CodexActivityNumeric.nonnegativeInteger(
                    total["total_tokens"]
                  ),
                  let lastReported = CodexActivityNumeric.nonnegativeInteger(
                    last["total_tokens"]
                  ),
                  cumulative >= lastReported
            else {
                return nil
            }
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .tokenUsage(
                    CodexActivityTokenUsageUpdate(
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        cumulativeTotalTokens: cumulative,
                        lastReportedTotalTokens: lastReported,
                        occurredAt: occurredAt
                    )
                )
            )

        case "task_complete":
            guard let turnHash = Self.hashedIdentifier(
                payload["turn_id"]
            ), turnHash == activeTurnHash else {
                return nil
            }
            activeTurnHash = nil
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(
                    CodexActivityEvent(
                        event: .stop,
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        workspaceName: workspaceName,
                        sessionKind: sessionKind,
                        source: .localRollout,
                        turnCompletionStatus: .completed,
                        occurredAt: occurredAt
                    )
                )
            )

        case "turn_aborted":
            guard let turnHash = activeTurnHash else { return nil }
            if let reportedTurn = Self.hashedIdentifier(payload["turn_id"]),
               reportedTurn != turnHash { return nil }
            activeTurnHash = nil
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(
                    CodexActivityEvent(
                        event: .interrupt,
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        workspaceName: workspaceName,
                        sessionKind: sessionKind,
                        source: .localRollout,
                        turnCompletionStatus: .interrupted,
                        occurredAt: occurredAt
                    )
                )
            )

        default:
            return nil
        }
    }

    private func decodeToolCall(
        _ payload: [String: Any],
        eventID: String?,
        occurredAt: Date
    ) -> CodexLocalRolloutDecodedRecord? {
        guard let turnHash = activeTurnHash,
              let itemType = payload["type"] as? String,
              itemType == "function_call"
                || itemType == "custom_tool_call",
              let name = payload["name"] as? String,
              !name.isEmpty
        else {
            return nil
        }

        let planProgress = CodexLocalRolloutPlanParser.parse(
            toolName: name,
            arguments: payload["arguments"],
            input: payload["input"]
        )
        return CodexLocalRolloutDecodedRecord(
            eventID: eventID,
            update: .activity(
                CodexActivityEvent(
                    event: .preToolUse,
                    sessionHash: sessionHash,
                    turnHash: turnHash,
                    workspaceName: workspaceName,
                    toolCategory: CodexActivityPrivacy.toolCategory(
                        for: name
                    ),
                    planProgress: planProgress,
                    sessionKind: sessionKind,
                    source: .localRollout,
                    planSource: planProgress == nil
                        ? nil
                        : .localRollout,
                    occurredAt: occurredAt
                )
            )
        )
    }

    private static func hashedIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return CodexActivityPrivacy.hashIdentifier(value)
    }

    private static func eventID(
        sessionHash: String,
        ordinal: Any?,
        recordType: String,
        payloadType: String?
    ) -> String? {
        guard let ordinal = CodexActivityNumeric.nonnegativeInteger(ordinal) else {
            return nil
        }
        return "rollout:\(sessionHash):\(ordinal):\(recordType):\(payloadType ?? "-")"
    }

    private static func eventDate(
        from value: Any?,
        fallback: Date
    ) -> Date {
        guard let string = value as? String else { return fallback }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractional.date(from: string) {
            return date
        }
        return ISO8601DateFormatter().date(from: string) ?? fallback
    }
}

public actor CodexLocalRolloutActivityClient {
    public struct Configuration: Sendable, Equatable {
        public let isEnabled: Bool
        public let codexHomeURL: URL
        public let pollIntervalSeconds: TimeInterval
        public let candidateRefreshSeconds: TimeInterval
        public let maximumCandidateCount: Int
        public let startupTailBytes: Int

        public init(
            isEnabled: Bool,
            codexHomeURL: URL,
            pollIntervalSeconds: TimeInterval = 0.25,
            candidateRefreshSeconds: TimeInterval = 1,
            maximumCandidateCount: Int = 24,
            startupTailBytes: Int = 16 * 1_048_576
        ) {
            self.isEnabled = isEnabled
            self.codexHomeURL = codexHomeURL.standardizedFileURL
            self.pollIntervalSeconds = max(pollIntervalSeconds, 0.1)
            self.candidateRefreshSeconds = max(
                candidateRefreshSeconds,
                pollIntervalSeconds
            )
            self.maximumCandidateCount = min(128, max(1, maximumCandidateCount))
            self.startupTailBytes = max(
                CodexLocalRolloutLineDecoder.maximumLineBytes,
                min(startupTailBytes, 16 * 1_048_576)
            )
        }

        public static func live(
            environment: [String: String] =
                ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default
        ) -> Configuration {
            let home: URL
            if let configured = environment["CODEX_HOME"],
               !configured.isEmpty
            {
                home = URL(fileURLWithPath: configured)
            } else {
                home = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex", isDirectory: true)
            }
            return Configuration(
                isEnabled:
                    environment["QUOTAVIEW_DISABLE_LOCAL_ROLLOUT"] != "1",
                codexHomeURL: home
            )
        }
    }

    public typealias UpdateHandler = @Sendable (
        CodexLocalRolloutDecodedRecord,
        Bool
    ) async -> Void
    public typealias ConnectionStateHandler = @Sendable (
        CodexSharedAppServerConnectionState
    ) async -> Void

    private struct Candidate: Sendable, Equatable {
        let fileURL: URL
        let sessionHash: String
        let workspaceName: String?
        let sessionKind: CodexActivitySessionKind
    }

    private struct TailState: Sendable {
        var offset: UInt64
        var pending = Data()
        var discardingOversizedLine = false
        var decoder: CodexLocalRolloutLineDecoder
    }

    private let configuration: Configuration
    private let fileManager: FileManager
    private var updateHandler: UpdateHandler?
    private var connectionStateHandler: ConnectionStateHandler?
    private var maintenanceTask: Task<Void, Never>?
    private var tailStates: [URL: TailState] = [:]
    private var candidates: [Candidate] = []
    private var lastCandidateRefresh = Date.distantPast
    private var isStarted = false
    private var generation: UInt64 = 0
    private var pollingGeneration: UInt64?
    private var connectionState:
        CodexSharedAppServerConnectionState = .disabled

    public init(
        configuration: Configuration = .live(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func start(
        handler: @escaping UpdateHandler,
        connectionStateHandler: @escaping ConnectionStateHandler
    ) async {
        updateHandler = handler
        self.connectionStateHandler = connectionStateHandler
        guard configuration.isEnabled else {
            await publishConnectionState(.disabled)
            return
        }
        guard !isStarted else {
            await connectionStateHandler(connectionState)
            return
        }
        isStarted = true
        generation &+= 1
        let run = generation
        await publishConnectionState(.discovering)
        guard isStarted, generation == run else { return }
        let client = self
        maintenanceTask = Task(priority: .utility) {
            await client.runMaintenanceLoop(generation: run)
        }
    }

    public func stop() async {
        isStarted = false
        generation &+= 1
        lastCandidateRefresh = .distantPast
        maintenanceTask?.cancel()
        maintenanceTask = nil
        updateHandler = nil
        connectionStateHandler = nil
        tailStates.removeAll()
        candidates.removeAll()
        await publishConnectionState(.disabled)
    }

    func pollOnceForTesting() async {
        await pollOnce(now: Date())
    }

    private func runMaintenanceLoop(generation run: UInt64) async {
        while isStarted, generation == run, !Task.isCancelled {
            await pollOnce(now: Date())
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        configuration.pollIntervalSeconds
                            * 1_000_000_000
                    )
                )
            } catch {
                return
            }
        }
    }

    private func pollOnce(now: Date) async {
        let run = generation
        guard isStarted, pollingGeneration != run else { return }
        pollingGeneration = run
        defer { if pollingGeneration == run { pollingGeneration = nil } }
        if now.timeIntervalSince(lastCandidateRefresh)
            >= configuration.candidateRefreshSeconds
        {
            candidates = recentCandidates()
            lastCandidateRefresh = now
            let retained = Set(candidates.map(\.fileURL))
            tailStates = tailStates.filter { retained.contains($0.key) }
        }

        for candidate in candidates {
            guard isStarted, generation == run, !Task.isCancelled else { return }
            await consume(candidate: candidate, generation: run)
        }
        guard isStarted, generation == run else { return }
        await publishConnectionState(tailStates.isEmpty ? .discovering : .connected)
    }

    private func consume(candidate: Candidate, generation run: UInt64) async {
        let root = configuration.codexHomeURL.appendingPathComponent("sessions")
        guard Self.isAllowedRollout(candidate.fileURL, sessionsURL: root) else {
            tailStates.removeValue(forKey: candidate.fileURL)
            return
        }
        if tailStates[candidate.fileURL] == nil {
            await bootstrap(candidate: candidate, generation: run)
            return
        }

        guard var state = tailStates[candidate.fileURL],
              let attributes = try? fileManager.attributesOfItem(
                atPath: candidate.fileURL.path
              ),
              let size = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            return
        }

        if size < state.offset {
            tailStates.removeValue(forKey: candidate.fileURL)
            await bootstrap(candidate: candidate, generation: run)
            return
        }
        guard size > state.offset,
              let handle = try? FileHandle(forReadingFrom: candidate.fileURL)
        else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: state.offset)
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            state.offset = try handle.offset()
            state.pending.append(data)
            var records: [CodexLocalRolloutDecodedRecord] = []
            consumeCompleteLines(from: &state.pending, discarding: &state.discardingOversizedLine) { line in
                if let record = state.decoder.decode(line: line) { records.append(record) }
            }
            // Commit the cursor before any reentrant callback can stop/restart us.
            tailStates[candidate.fileURL] = state
            for record in records {
                guard isStarted, generation == run, !Task.isCancelled else { return }
                await updateHandler?(record, false)
            }
        } catch {
            return
        }
    }

    private func bootstrap(candidate: Candidate, generation run: UInt64) async {
        guard let handle = try? FileHandle(forReadingFrom: candidate.fileURL)
        else {
            return
        }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            let start = size > UInt64(configuration.startupTailBytes)
                ? size - UInt64(configuration.startupTailBytes)
                : 0
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: Int(size - start)) ?? Data()
            let actualOffset = try handle.offset()
            var discarding = false
            if start > 0 {
                if let newline = data.firstIndex(of: 0x0A) {
                    data.removeSubrange(data.startIndex...newline)
                } else { data.removeAll(); discarding = true }
            }

            var decoder = CodexLocalRolloutLineDecoder(
                sessionHash: candidate.sessionHash,
                workspaceName: candidate.workspaceName,
                sessionKind: candidate.sessionKind
            )
            var replay = BootstrapReplay()
            var pending = data
            consumeCompleteLines(from: &pending, discarding: &discarding) { line in
                guard let record = decoder.decode(line: line) else {
                    return
                }
                replay.record(record)
            }
            tailStates[candidate.fileURL] = TailState(
                offset: actualOffset, pending: pending,
                discardingOversizedLine: discarding, decoder: decoder
            )
            if replay.isActive {
                for record in replay.records {
                    guard isStarted, generation == run, !Task.isCancelled else { return }
                    await updateHandler?(record, true)
                }
            }
        } catch {
            return
        }
    }

    private func consumeCompleteLines(
        from data: inout Data,
        discarding: inout Bool,
        body: (Data) -> Void
    ) {
        while let newline = data.firstIndex(of: 0x0A) {
            let line = Data(data[..<newline])
            data.removeSubrange(data.startIndex...newline)
            if !discarding, line.count <= CodexLocalRolloutLineDecoder.maximumLineBytes {
                body(line)
            }
            discarding = false
        }
        if data.count > CodexLocalRolloutLineDecoder.maximumLineBytes {
            data.removeAll(keepingCapacity: true)
            discarding = true
        }
    }

    private func recentCandidates() -> [Candidate] {
        let databaseURL = configuration.codexHomeURL
            .appendingPathComponent("state_5.sqlite")
        let sessionsURL = configuration.codexHomeURL
            .appendingPathComponent("sessions", isDirectory: true)
            .standardizedFileURL
        if let fromDatabase = candidatesFromDatabase(
            databaseURL: databaseURL,
            sessionsURL: sessionsURL
        ), !fromDatabase.isEmpty {
            return fromDatabase
        }
        return candidatesFromSessionsDirectory(sessionsURL)
    }

    private func candidatesFromDatabase(
        databaseURL: URL,
        sessionsURL: URL
    ) -> [Candidate]? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database
        else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)

        let sql = """
        SELECT id, rollout_path, cwd, source, thread_source
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at_ms DESC, id DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, sql, -1, &statement, nil) != SQLITE_OK {
            if let statement { sqlite3_finalize(statement) }
            statement = nil
            let legacySQL = sql.replacingOccurrences(of: ", source, thread_source", with: "")
            guard sqlite3_prepare_v2(database, legacySQL, -1, &statement, nil) == SQLITE_OK else { return nil }
        }
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(configuration.maximumCandidateCount, 1024)))

        var result: [Candidate] = []
        while result.count < configuration.maximumCandidateCount, sqlite3_step(statement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let pathPointer = sqlite3_column_text(statement, 1)
            else {
                continue
            }
            let sessionHash = CodexActivityPrivacy.hashIdentifier(
                String(cString: idPointer)
            )
            let fileURL = URL(
                fileURLWithPath: String(cString: pathPointer)
            ).standardizedFileURL
            guard Self.isAllowedRollout(
                fileURL,
                sessionsURL: sessionsURL
            ) else {
                continue
            }
            guard let metadata = Self.readSessionMetadata(from: fileURL),
                  metadata.sessionHash == sessionHash,
                  metadata.kind != .internalTask else { continue }
            let databaseKind = CodexActivitySessionKind.classify(
                source: sqlite3_column_text(statement, 3).map { String(cString: $0) },
                threadSource: sqlite3_column_text(statement, 4).map { String(cString: $0) }
            )
            guard databaseKind != .internalTask else { continue }
            let kind = databaseKind == .unknown ? metadata.kind : databaseKind
            let workspaceName: String?
            if let cwdPointer = sqlite3_column_text(statement, 2) {
                workspaceName = CodexActivityPrivacy.workspaceName(
                    from: String(cString: cwdPointer)
                )
            } else {
                workspaceName = nil
            }
            result.append(
                Candidate(
                    fileURL: fileURL,
                    sessionHash: sessionHash,
                    workspaceName: workspaceName,
                    sessionKind: kind
                )
            )
        }
        return result
    }

    private func candidatesFromSessionsDirectory(
        _ sessionsURL: URL
    ) -> [Candidate] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [(URL, Date)] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(
                    forKeys: Set(keys)
                  ),
                  values.isRegularFile == true
            else {
                continue
            }
            files.append((fileURL, values.contentModificationDate ?? .distantPast))
            if files.count >= 2048 {
                files.sort { $0.1 > $1.1 }
                files.removeLast(files.count - 1024)
            }
        }
        files.sort { $0.1 > $1.1 }

        return Array(files.prefix(1024).lazy.filter { Self.isAllowedRollout($0.0, sessionsURL: sessionsURL) }.compactMap {
            fileURL, _ in
            guard let metadata = Self.readSessionMetadata(from: fileURL), metadata.kind != .internalTask
            else {
                return nil
            }
            return Candidate(
                fileURL: fileURL.standardizedFileURL,
                sessionHash: metadata.sessionHash,
                workspaceName: metadata.workspaceName,
                sessionKind: metadata.kind
            )
        }.prefix(configuration.maximumCandidateCount))
    }

    private static func readSessionMetadata(
        from fileURL: URL
    ) -> (sessionHash: String, workspaceName: String?, kind: CodexActivitySessionKind)? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL)
        else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1_048_576),
              let newline = data.firstIndex(of: 0x0A),
              let object = try? JSONSerialization.jsonObject(
                with: Data(data[..<newline])
              ),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "session_meta",
              let payload = envelope["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              !id.isEmpty
        else {
            return nil
        }
        return (
            CodexActivityPrivacy.hashIdentifier(id),
            CodexActivityPrivacy.workspaceName(
                from: payload["cwd"] as? String
            ),
            CodexActivitySessionKind.classify(source: payload["source"], threadSource: payload["thread_source"] as? String)
        )
    }

    private static func isAllowedRollout(
        _ fileURL: URL,
        sessionsURL: URL
    ) -> Bool {
        let path = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        let root = sessionsURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard path.hasPrefix(root), fileURL.pathExtension == "jsonl" else { return false }
        return (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    private func publishConnectionState(
        _ state: CodexSharedAppServerConnectionState
    ) async {
        guard connectionState != state else { return }
        connectionState = state
        await connectionStateHandler?(state)
    }
}

private struct BootstrapReplay {
    private var start: CodexLocalRolloutDecodedRecord?
    private var plan: CodexLocalRolloutDecodedRecord?
    private var compaction: CodexLocalRolloutDecodedRecord?
    private var legacyTokens: [CodexActivityTokenUsageUpdate] = []
    private var directTokens: CodexLocalRolloutDecodedRecord?
    private(set) var isActive = false

    mutating func record(_ record: CodexLocalRolloutDecodedRecord) {
        switch record.update {
        case .tokenUsageReplay:
            break // Only the recovery projector creates batches, never the line decoder.
        case .activity(let event):
            switch event.event {
            case .userPromptSubmit:
                self = BootstrapReplay()
                start = record
                isActive = true
            case .stop, .interrupt, .sessionEnd:
                self = BootstrapReplay()
            case .preCompact, .postCompact:
                if isActive { compaction = record }
            case .preToolUse:
                if isActive {
                    compaction = nil
                    if event.planProgress != nil { plan = record }
                }
            default:
                break
            }
        case .tokenUsage(let update):
            if isActive {
                if let total = update.directTurnTotalTokens {
                    if case .tokenUsage(let previous) = directTokens?.update,
                       let previousTotal = previous.directTurnTotalTokens,
                       previousTotal > total { break }
                    directTokens = record
                } else {
                    legacyTokens.append(update)
                }
            }
        }
    }

    var records: [CodexLocalRolloutDecodedRecord] {
        // Usage and activity are independent streams. Preserve direct usage
        // even when the final record is a legacy rebroadcast without ordinal.
        var result = [start, plan, compaction].compactMap { $0 }
        var usage = legacyTokens
        if case .tokenUsage(let direct) = directTokens?.update { usage.append(direct) }
        // Preserve every numeric segment, but publish only the recovered total.
        if !usage.isEmpty {
            result.append(.init(eventID: nil, update: .tokenUsageReplay(usage)))
        }
        return result
    }
}

private enum CodexLocalRolloutPlanParser {
    private static let wrappedToolNames: Set<String> = [
        "exec", "functions.exec", "functions__exec"
    ]

    static func parse(
        toolName: String,
        arguments: Any?,
        input: Any?
    ) -> CodexActivityPlanProgress? {
        if toolName == "update_plan" {
            return direct(arguments ?? input)
        }
        guard wrappedToolNames.contains(toolName),
              let source = input as? String,
              source.utf8.count
                <= CodexLocalRolloutLineDecoder.maximumLineBytes
        else {
            return nil
        }
        return LoosePlanScanner(source: source).lastPlan()
    }

    private static func direct(_ value: Any?) -> CodexActivityPlanProgress? {
        let object: [String: Any]?
        if let value = value as? [String: Any] {
            object = value
        } else if let value = value as? String,
                  let data = value.data(using: .utf8),
                  data.count <= CodexLocalRolloutLineDecoder.maximumLineBytes
        {
            object = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any]
        } else {
            object = nil
        }
        guard let plan = object?["plan"] as? [[String: Any]],
              (1...CodexActivityPlanProgress.maximumStepCount)
                .contains(plan.count)
        else {
            return nil
        }
        var counts = PlanCounts()
        for item in plan {
            guard let status = item["status"] as? String,
                  counts.record(status)
            else {
                return nil
            }
        }
        return counts.progress
    }
}

private struct PlanCounts {
    var completed = 0
    var inProgress = 0
    var pending = 0

    mutating func record(_ status: String) -> Bool {
        switch status {
        case "completed": completed += 1
        case "in_progress", "inProgress": inProgress += 1
        case "pending": pending += 1
        default: return false
        }
        return true
    }

    var progress: CodexActivityPlanProgress {
        CodexActivityPlanProgress(
            completedSteps: completed,
            inProgressSteps: inProgress,
            pendingSteps: pending
        )
    }
}

private struct LoosePlanScanner {
    private let bytes: [UInt8]

    init(source: String) {
        bytes = Array(source.utf8)
    }

    func lastPlan() -> CodexActivityPlanProgress? {
        var result: CodexActivityPlanProgress?
        var index = 0
        while index < bytes.count {
            if let end = triviaOrLiteralEnd(at: index) {
                index = end
                continue
            }
            guard let argument = updatePlanArgument(at: index) else {
                index += 1
                continue
            }
            if let planRange = planArrayRange(in: argument),
               let progress = countPlan(in: planRange)
            {
                result = progress
            }
            index = max(argument.upperBound, index + 1)
        }
        return result
    }

    private func updatePlanArgument(at start: Int) -> Range<Int>? {
        guard matches("tools", at: start) else { return nil }
        var cursor = start + 5
        skipTrivia(&cursor)
        guard consume(46, &cursor) else { return nil }
        skipTrivia(&cursor)
        guard matches("update_plan", at: cursor) else { return nil }
        cursor += 11
        skipTrivia(&cursor)
        guard consume(40, &cursor),
              let closing = matchingDelimiter(
                from: cursor - 1,
                open: 40,
                close: 41
              )
        else {
            return nil
        }
        return cursor..<closing
    }

    private func planArrayRange(in argument: Range<Int>) -> Range<Int>? {
        var index = argument.lowerBound
        while index < argument.upperBound {
            if let end = commentEnd(at: index) {
                index = end
                continue
            }
            let keyEnd: Int?
            if bytes[index] == 34 || bytes[index] == 39 {
                let literal = stringLiteral(at: index)
                keyEnd = literal?.value == "plan" ? literal?.end : nil
                if keyEnd == nil {
                    index = literal?.end ?? argument.upperBound
                    continue
                }
            } else if matches("plan", at: index) {
                keyEnd = index + 4
            } else {
                keyEnd = nil
            }
            guard let keyEnd else {
                index += 1
                continue
            }
            var cursor = keyEnd
            skipTrivia(&cursor)
            guard cursor < argument.upperBound,
                  consume(58, &cursor)
            else {
                index += 1
                continue
            }
            skipTrivia(&cursor)
            guard cursor < argument.upperBound,
                  bytes[cursor] == 91,
                  let closing = matchingDelimiter(
                    from: cursor,
                    open: 91,
                    close: 93
                  ),
                  closing <= argument.upperBound
            else {
                index += 1
                continue
            }
            return (cursor + 1)..<closing
        }
        return nil
    }

    private func countPlan(
        in range: Range<Int>
    ) -> CodexActivityPlanProgress? {
        var counts = PlanCounts()
        var rootItems = 0
        var objectDepth = 0
        var arrayDepth = 0
        var index = range.lowerBound

        while index < range.upperBound {
            if let end = commentEnd(at: index) {
                index = end
                continue
            }
            if bytes[index] == 34 || bytes[index] == 39 {
                let parsed = stringLiteral(at: index)
                guard let parsed else { return nil }
                if objectDepth == 1, arrayDepth == 0,
                   parsed.value == "status",
                   let status = propertyStringValue(
                    after: parsed.end,
                    upperBound: range.upperBound
                   ), !counts.record(status.value)
                {
                    return nil
                }
                index = parsed.end
                continue
            }
            switch bytes[index] {
            case 123:
                objectDepth += 1
                if objectDepth == 1, arrayDepth == 0 { rootItems += 1 }
            case 125:
                objectDepth -= 1
                if objectDepth < 0 { return nil }
            case 91:
                arrayDepth += 1
            case 93:
                arrayDepth -= 1
                if arrayDepth < 0 { return nil }
            default:
                if objectDepth == 1, arrayDepth == 0,
                   matches("status", at: index),
                   let status = propertyStringValue(
                    after: index + 6,
                    upperBound: range.upperBound
                   ), !counts.record(status.value)
                {
                    return nil
                }
            }
            index += 1
        }

        let statusCount = counts.completed + counts.inProgress + counts.pending
        guard objectDepth == 0,
              arrayDepth == 0,
              rootItems == statusCount,
              (1...CodexActivityPlanProgress.maximumStepCount)
                .contains(rootItems)
        else {
            return nil
        }
        return counts.progress
    }

    private func propertyStringValue(
        after keyEnd: Int,
        upperBound: Int
    ) -> (value: String, end: Int)? {
        var cursor = keyEnd
        skipTrivia(&cursor)
        guard cursor < upperBound, consume(58, &cursor) else {
            return nil
        }
        skipTrivia(&cursor)
        guard cursor < upperBound,
              let value = stringLiteral(at: cursor),
              value.end <= upperBound
        else {
            return nil
        }
        return value
    }

    private func matchingDelimiter(
        from start: Int,
        open: UInt8,
        close: UInt8
    ) -> Int? {
        var depth = 0
        var index = start
        while index < bytes.count {
            if let end = triviaOrLiteralEnd(at: index) {
                index = end
                continue
            }
            if bytes[index] == open { depth += 1 }
            if bytes[index] == close {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private func stringLiteral(
        at start: Int
    ) -> (value: String, end: Int)? {
        guard start < bytes.count,
              bytes[start] == 34 || bytes[start] == 39
        else {
            return nil
        }
        let quote = bytes[start]
        var value: [UInt8] = []
        var index = start + 1
        while index < bytes.count {
            if bytes[index] == 92 {
                guard index + 1 < bytes.count else { return nil }
                value.append(bytes[index + 1])
                index += 2
            } else if bytes[index] == quote {
                return (String(decoding: value, as: UTF8.self), index + 1)
            } else {
                value.append(bytes[index])
                index += 1
            }
        }
        return nil
    }

    private func triviaOrLiteralEnd(at index: Int) -> Int? {
        if let end = commentEnd(at: index) { return end }
        guard index < bytes.count,
              bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96
        else {
            return nil
        }
        let quote = bytes[index]
        var cursor = index + 1
        while cursor < bytes.count {
            if bytes[cursor] == 92 {
                cursor = min(cursor + 2, bytes.count)
            } else if bytes[cursor] == quote {
                return cursor + 1
            } else {
                cursor += 1
            }
        }
        return bytes.count
    }

    private func commentEnd(at index: Int) -> Int? {
        guard index + 1 < bytes.count, bytes[index] == 47 else {
            return nil
        }
        if bytes[index + 1] == 47 {
            var cursor = index + 2
            while cursor < bytes.count,
                  bytes[cursor] != 10,
                  bytes[cursor] != 13
            {
                cursor += 1
            }
            return cursor
        }
        if bytes[index + 1] == 42 {
            var cursor = index + 2
            while cursor + 1 < bytes.count,
                  !(bytes[cursor] == 42 && bytes[cursor + 1] == 47)
            {
                cursor += 1
            }
            return min(cursor + 2, bytes.count)
        }
        return nil
    }

    private func skipTrivia(_ index: inout Int) {
        while index < bytes.count {
            if [9, 10, 13, 32].contains(bytes[index]) {
                index += 1
            } else if let end = commentEnd(at: index) {
                index = end
            } else {
                return
            }
        }
    }

    private func consume(_ byte: UInt8, _ index: inout Int) -> Bool {
        guard index < bytes.count, bytes[index] == byte else {
            return false
        }
        index += 1
        return true
    }

    private func matches(_ value: String, at index: Int) -> Bool {
        let token = Array(value.utf8)
        guard index >= 0,
              index + token.count <= bytes.count,
              Array(bytes[index..<(index + token.count)]) == token
        else {
            return false
        }
        if index > 0, Self.isIdentifier(bytes[index - 1]) { return false }
        let end = index + token.count
        if end < bytes.count, Self.isIdentifier(bytes[end]) { return false }
        return true
    }

    private static func isIdentifier(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 95
            || byte == 36
    }
}
