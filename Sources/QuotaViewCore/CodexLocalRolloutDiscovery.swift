import Foundation
import SQLite3
import Darwin

/// Actor-confined discovery. It does not decode activity, publish UI or modify Codex files.
final class CodexLocalRolloutDiscovery {
    typealias SessionMetadata = (threadID: String, sessionHash: String, workspaceName: String?,
        kind: CodexActivitySessionKind, subagentIdentity: CodexActivitySubagentIdentity?)
    private struct MetadataSignature: Equatable {
        let device: UInt64, inode: UInt64, size: Int64
        let modifiedSeconds: Int, modifiedNanoseconds: Int
        let changedSeconds: Int, changedNanoseconds: Int
        init?(_ file: URL) {
            var info = stat()
            guard file.path.withCString({ fstatat(AT_FDCWD, $0, &info, 0) }) == 0 else { return nil }
            device = UInt64(info.st_dev); inode = UInt64(info.st_ino); size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanoseconds = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec; changedNanoseconds = info.st_ctimespec.tv_nsec
        }
    }
    private struct CachedMetadata {
        let signature: MetadataSignature
        let value: SessionMetadata?
        let unsupported: Bool
        var lastAccess: UInt64
    }
    struct Candidate: Sendable, Equatable {
        let fileURL: URL
        let threadID: String
        let sessionHash: String
        let workspaceName: String?
        let sessionKind: CodexActivitySessionKind
        let metadataKind: CodexActivitySessionKind
        let title: String?
        let threadMetadata: CodexLocalRolloutThreadMetadata?
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
    private var metadataCache: [URL: CachedMetadata] = [:]
    private var metadataAccess: UInt64 = 0
    private(set) var metadataReadCount = 0
    private(set) var metadataDecodeCount = 0

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
        metadataCache.removeAll()
        metadataReadCount = 0; metadataDecodeCount = 0
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

        // Columns differ across Codex releases. Project each optional field into
        // a stable position instead of making all metadata depend on one schema.
        var columns = Set<String>()
        var schema: OpaquePointer?
        if sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &schema, nil) == SQLITE_OK,
           let schema {
            while sqlite3_step(schema) == SQLITE_ROW {
                if let name = sqlite3_column_text(schema, 1) { columns.insert(String(cString: name)) }
            }
        }
        if let schema { sqlite3_finalize(schema) }
        func field(_ name: String) -> String { columns.contains(name) ? name : "NULL" }
        let sql = """
        SELECT id, rollout_path, cwd, \(field("source")), \(field("thread_source")),
               \(field("title")), \(field("name")), \(field("model")),
               \(field("reasoning_effort")), \(field("tokens_used"))
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at_ms DESC, id DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, sql, -1, &statement, nil) != SQLITE_OK {
            if let statement { sqlite3_finalize(statement) }
            return nil
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
                if let metadata = sessionMetadata(from: fileURL), metadata.sessionHash == sessionHash {
                    excludedIdentities[fileURL] = .init(threadID: metadata.threadID, sessionHash: sessionHash,
                                                         sessionKind: .internalTask)
                }
                continue
            }
            guard result.count < maximumCandidateCount else { continue }
            guard let metadata = sessionMetadata(from: fileURL),
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
            func text(_ index: Int32) -> String? {
                sqlite3_column_text(statement, index).map { String(cString: $0) }
            }
            let explicitName = text(6)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasExplicitName = explicitName.map { !$0.isEmpty && $0.utf8.count <= 512 } ?? false
            let total = sqlite3_column_type(statement, 9) == SQLITE_INTEGER
                ? sqlite3_column_int64(statement, 9) : nil
            let displayMetadata = CodexLocalRolloutThreadMetadata(
                title: hasExplicitName ? explicitName : text(5), titleIsExplicitName: hasExplicitName,
                model: text(7), reasoningEffort: text(8), cumulativeTotalTokens: total
            )
            result.append(
                Candidate(
                    fileURL: fileURL,
                    threadID: metadata.threadID,
                    sessionHash: sessionHash,
                    workspaceName: workspaceName,
                    sessionKind: kind,
                    metadataKind: metadata.kind,
                    title: displayMetadata.title ?? metadata.subagentIdentity?.title,
                    threadMetadata: displayMetadata.isEmpty ? nil : displayMetadata
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
            guard let metadata = sessionMetadata(from: file) else {
                // Only a complete incompatible metadata envelope is an error;
                // partial writes and ordinary future event types remain harmless.
                if metadataCache[file]?.unsupported == true {
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
                                    title: metadata.subagentIdentity?.title, threadMetadata: nil))
            if result.count == maximumCandidateCount { break }
        }
        return result
    }

    static func readSessionMetadata(
        from fileURL: URL
    ) -> SessionMetadata? {
        guard let line = readMetadataLine(from: fileURL),
              let envelope = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        return decodeSessionMetadata(envelope)
    }

    /// Discovery and consumption share one actor-confined bounded cache.
    /// Device/inode and nanosecond mtime/ctime also detect same-size rewrites.
    func sessionMetadata(from fileURL: URL) -> SessionMetadata? {
        let file = fileURL.standardizedFileURL
        guard let signature = MetadataSignature(file) else { metadataCache.removeValue(forKey: file); return nil }
        metadataAccess &+= 1
        if var cached = metadataCache[file], cached.signature == signature {
            cached.lastAccess = metadataAccess; metadataCache[file] = cached
            return cached.value
        }
        metadataReadCount += 1
        let line = Self.readMetadataLine(from: file)
        let envelope: [String: Any]?
        if let line {
            metadataDecodeCount += 1
            envelope = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        } else { envelope = nil }
        guard MetadataSignature(file) == signature else { metadataCache.removeValue(forKey: file); return nil }
        let value = envelope.flatMap(Self.decodeSessionMetadata)
        metadataCache[file] = .init(signature: signature, value: value,
            unsupported: value == nil && envelope?["type"] as? String == "session_meta", lastAccess: metadataAccess)
        if metadataCache.count > 1024,
           let oldest = metadataCache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            metadataCache.removeValue(forKey: oldest)
        }
        return value
    }

    private static func decodeSessionMetadata(_ envelope: [String: Any]) -> SessionMetadata? {
        guard
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
