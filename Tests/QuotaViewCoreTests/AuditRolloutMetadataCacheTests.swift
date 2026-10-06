import Foundation
import SQLite3
import XCTest
@testable import QuotaViewCore

final class AuditRolloutMetadataCacheTests: XCTestCase {
    private func line(_ id: String) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": ["id": id, "source": "vscode"]], options: [.sortedKeys])
        data.append(10); return data
    }

    func testTwentyFourStationaryFilesShareDiscoveryAndConsumerHeaderCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,archived INTEGER,updated_at_ms INTEGER)", nil, nil, nil), SQLITE_OK)
        for index in 0..<24 {
            let id = "fixture-\(index)", file = sessions.appendingPathComponent("\(index).jsonl")
            try line(id).write(to: file)
            let escaped = file.path.replacingOccurrences(of: "'", with: "''")
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO threads VALUES('\(id)','\(escaped)','/fixture',0,1)", nil, nil, nil), SQLITE_OK)
        }
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        var candidates = discovery.recentCandidates()
        XCTAssertEqual(candidates.count, 24)
        // The lookup schedule of 60 seconds at 250ms, without a wall-clock sleep.
        for poll in 0..<240 {
            if poll % 4 == 0 { candidates = discovery.recentCandidates() }
            for candidate in candidates {
                XCTAssertEqual(discovery.sessionMetadata(from: candidate.fileURL)?.threadID, candidate.threadID)
            }
        }
        XCTAssertEqual(discovery.metadataReadCount, 24)
        XCTAssertEqual(discovery.metadataDecodeCount, 24)
        print("B metadata cache: 24 headers / 240 consumer polls + 60 database/directory discoveries; reads=24 decodes=24")
    }

    func testHeaderCacheInvalidatesOnAppendReplacementTruncationAndSameSizeRewrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.jsonl")
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        try line("fixture-a").write(to: file)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "fixture-a")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("{}\n".utf8)); try handle.close()
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "fixture-a")
        let oldInode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        try line("fixture-b").write(to: file, options: .atomic)
        let newInode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        XCTAssertNotEqual(oldInode, newInode)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "fixture-b")
        try Data().write(to: file)
        XCTAssertNil(discovery.sessionMetadata(from: file))
        try line("fixture-a").write(to: file)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "fixture-a")
        let date = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: file.path))[.modificationDate] as? Date)
        // Rewrite in place with identical length and restore mtime. ctime remains evidence.
        let rewrite = try FileHandle(forWritingTo: file)
        try rewrite.write(contentsOf: line("fixture-b")); try rewrite.close()
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "fixture-b")
        XCTAssertEqual(discovery.metadataReadCount, 6)
        discovery.reset()
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "fixture-b")
        XCTAssertEqual(discovery.metadataReadCount, 1)
    }
}
