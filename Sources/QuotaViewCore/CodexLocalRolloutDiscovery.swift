import Foundation
import SQLite3

/// Actor-confined discovery. It does not decode activity, publish UI or modify Codex files.
final class CodexLocalRolloutDiscovery {
    struct Candidate: Sendable, Equatable {
        let fileURL: URL
        let threadID: String
        let sessionHash: String
        let workspaceName: String?
        let sessionKind: CodexActivitySessionKind
        let metadataKind: CodexActivitySessionKind
        let title: String?
    }

    private let codexHomeURL: URL
    private let maximumCandidateCount: Int
    private let fileManager: FileManager
    private var directoryEnumerator: FileManager.DirectoryEnumerator?
    private var discoveredFiles: [URL: Date] = [:]
    private var databaseInternalPaths: Set<URL> = []
    /// Authoritative exclusions can retract an already-observed identity without
    /// admitting a new internal task to the visible activity stream.
    private(set) var excludedIdentities: [URL: CodexLocalRolloutThreadIdentity] = [:]
    private(set) var readFailed = false
    private(set) var unsupportedMetadata = false

    init(codexHomeURL: URL, maximumCandidateCount: Int, fileManager: FileManager) {
        self.codexHomeURL = codexHomeURL
        self.maximumCandidateCount = maximumCandidateCount
        self.fileManager = fileManager
    }

    func reset() {
        directoryEnumerator = nil
        discoveredFiles.removeAll()
        databaseInternalPaths.removeAll()
        excludedIdentities.removeAll()
    }

    func recheck() { directoryEnumerator = nil }

    func recentCandidates() -> [Candidate] {
        let databaseURL = codexHomeURL
            .appendingPathComponent("state_5.sqlite")
        let sessionsURL = codexHomeURL
            .appendingPathComponent("sessions", isDirectory: true)
            .standardizedFileURL
        readFailed = false
        unsupportedMetadata = false
        databaseInternalPaths.removeAll()
        excludedIdentities.removeAll()
        let fromDatabase = candidatesFromDatabase(
            databaseURL: databaseURL,
            sessionsURL: sessionsURL
        ) ?? []
        let fromDirectory = candidatesFromSessionsDirectory(sessionsURL)
        var merged = Dictionary(fromDirectory.map { ($0.fileURL, $0) }, uniquingKeysWith: { a, _ in a })
        for candidate in fromDatabase { merged[candidate.fileURL] = candidate }
        return Array(merged.values.sorted {
            let left = (try? $0.fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let right = (try? $1.fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return left == right ? $0.fileURL.path < $1.fileURL.path : left > right
        }.prefix(maximumCandidateCount))
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
        SELECT id, rollout_path, cwd, source, thread_source, title
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at_ms DESC, id DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        let withoutTitle = sql.replacingOccurrences(of: ", title", with: "")
        let legacy = withoutTitle.replacingOccurrences(of: ", source, thread_source", with: "")
        for query in [sql, withoutTitle, legacy] {
            if sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK { break }
            if let statement { sqlite3_finalize(statement) }
            statement = nil
        }
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(maximumCandidateCount, 1024)))

        var result: [Candidate] = []
        // The UI candidate cap must not truncate internal-task exclusions.
        // SQL still bounds this scan to 1024 rows.
        while sqlite3_step(statement) == SQLITE_ROW {
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
            let databaseKind = CodexActivitySessionKind.classify(
                source: sqlite3_column_text(statement, 3).map { String(cString: $0) },
                threadSource: sqlite3_column_text(statement, 4).map { String(cString: $0) }
            )
            guard databaseKind != .internalTask else {
                databaseInternalPaths.insert(fileURL)
                if let metadata = Self.readSessionMetadata(from: fileURL), metadata.sessionHash == sessionHash {
                    excludedIdentities[fileURL] = .init(threadID: metadata.threadID, sessionHash: sessionHash,
                                                         sessionKind: .internalTask)
                }
                continue
            }
            guard result.count < maximumCandidateCount else { continue }
            guard let metadata = Self.readSessionMetadata(from: fileURL),
                  metadata.sessionHash == sessionHash else { continue }
            guard metadata.kind != .internalTask else {
                excludedIdentities[fileURL] = .init(threadID: metadata.threadID, sessionHash: sessionHash,
                                                     sessionKind: .internalTask)
                continue
            }
            let kind = CodexActivitySessionKind.resolving(databaseKind, metadata.kind)
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
                    threadID: metadata.threadID,
                    sessionHash: sessionHash,
                    workspaceName: workspaceName,
                    sessionKind: kind,
                    metadataKind: metadata.kind,
                    title: sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? metadata.subagentIdentity?.title
                )
            )
        }
        return result
    }

    private func candidatesFromSessionsDirectory(
        _ sessionsURL: URL
    ) -> [Candidate] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsURL.path, isDirectory: &isDirectory) else {
            // Missing is normal on first install; inaccessible ancestors are not.
            var ancestor = sessionsURL.deletingLastPathComponent()
            while !fileManager.fileExists(atPath: ancestor.path), ancestor.path != "/" {
                ancestor.deleteLastPathComponent()
            }
            if !fileManager.isReadableFile(atPath: ancestor.path)
                || !fileManager.isExecutableFile(atPath: ancestor.path) { readFailed = true }
            return []
        }
        guard isDirectory.boolValue, fileManager.isReadableFile(atPath: sessionsURL.path),
              fileManager.isExecutableFile(atPath: sessionsURL.path) else {
            readFailed = true
            return []
        }
        if directoryEnumerator == nil {
            directoryEnumerator = fileManager.enumerator(
                at: sessionsURL, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in false }
            )
        }
        // Keep the traversal cursor across polls; large histories cannot block a poll
        // or permanently starve records past the first page.
        var files: [URL] = []
        for _ in 0..<512 {
            guard let next = directoryEnumerator?.nextObject() as? URL else {
                directoryEnumerator = nil
                break
            }
            if (try? next.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
               (!fileManager.isReadableFile(atPath: next.path) || !fileManager.isExecutableFile(atPath: next.path)) {
                readFailed = true
            }
            files.append(next)
        }
        // Codex's dated layout gives new tasks a fast path while history is scanned.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        for calendar in [Calendar.current, utc] {
            for offset in [0, -1] {
                let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                let relative = String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                let today = sessionsURL.appendingPathComponent(relative)
                if let scan = fileManager.enumerator(at: today, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) {
                    for _ in 0..<128 {
                        guard let next = scan.nextObject() as? URL else { break }
                        files.append(next)
                    }
                }
            }
        }
        for file in files where Self.isAllowedRollout(file, sessionsURL: sessionsURL) {
            discoveredFiles[file.standardizedFileURL] =
                (try? file.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
        }
        discoveredFiles = Dictionary(uniqueKeysWithValues: discoveredFiles.keys.compactMap { file in
            guard Self.isAllowedRollout(file, sessionsURL: sessionsURL) else { return nil }
            // Refresh cached metadata dates so an older task that resumes is promoted.
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return (file, date)
        })
        let recent = discoveredFiles.sorted { $0.value > $1.value }.prefix(1024)
        discoveredFiles = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
        var result: [Candidate] = []
        for (file, _) in recent {
            guard !databaseInternalPaths.contains(file) else { continue }
            guard fileManager.isReadableFile(atPath: file.path) else { readFailed = true; continue }
            guard let metadata = Self.readSessionMetadata(from: file) else {
                // Only a complete incompatible metadata envelope is an error;
                // partial writes and ordinary future event types remain harmless.
                if let line = Self.readMetadataLine(from: file),
                   let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                   object["type"] as? String == "session_meta" {
                    unsupportedMetadata = true
                }
                continue
            }
            guard metadata.kind != .internalTask else {
                excludedIdentities[file] = .init(threadID: metadata.threadID, sessionHash: metadata.sessionHash,
                                                  sessionKind: .internalTask)
                continue
            }
            result.append(Candidate(fileURL: file, threadID: metadata.threadID, sessionHash: metadata.sessionHash,
                                    workspaceName: metadata.workspaceName, sessionKind: metadata.kind, metadataKind: metadata.kind,
                                    title: metadata.subagentIdentity?.title))
            if result.count == maximumCandidateCount { break }
        }
        return result
    }

    static func readSessionMetadata(
        from fileURL: URL
    ) -> (threadID: String, sessionHash: String, workspaceName: String?, kind: CodexActivitySessionKind,
          subagentIdentity: CodexActivitySubagentIdentity?)? {
        guard let line = readMetadataLine(from: fileURL),
              let object = try? JSONSerialization.jsonObject(with: line),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "session_meta",
              let payload = envelope["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              !id.isEmpty, id.utf8.count <= 1024
        else {
            return nil
        }
        return (
            id,
            CodexActivityPrivacy.hashIdentifier(id),
            CodexActivityPrivacy.workspaceName(
                from: payload["cwd"] as? String
            ),
            CodexActivitySessionKind.classify(metadata: payload),
            CodexActivitySubagentIdentity.decode(payload, expectedThreadID: id)
        )
    }

    private static func readMetadataLine(from file: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while data.count < CodexLocalRolloutLineDecoder.maximumLineBytes {
            guard let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty else { return nil }
            data.append(chunk)
            if let newline = data.firstIndex(of: 10) { return Data(data[..<newline]) }
        }
        return nil
    }

    static func isAllowedRollout(
        _ fileURL: URL,
        sessionsURL: URL
    ) -> Bool {
        let path = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        let root = sessionsURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard path.hasPrefix(root), fileURL.pathExtension == "jsonl" else { return false }
        return (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

}
