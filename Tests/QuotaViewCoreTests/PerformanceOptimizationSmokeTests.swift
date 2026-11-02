import AppKit
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class PerformanceOptimizationSmokeTests: XCTestCase {
    func testHeaderCacheBenchmarkWith24UnchangedCandidates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qv-header-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try (0..<24).map { index in
            let file = root.appendingPathComponent("\(index).jsonl")
            try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-\(index)\",\"source\":\"cli\"}}\n".utf8).write(to: file)
            return file
        }
        let iterations = 40
        let baselineStart = Date()
        var baselineIDs: [String] = []
        for _ in 0..<iterations {
            for file in files { baselineIDs.append(try XCTUnwrap(CodexLocalRolloutDiscovery.readSessionMetadata(from: file)).sessionHash) }
        }
        let baselineMS = Date().timeIntervalSince(baselineStart) * 1000
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        let cachedStart = Date()
        var cachedIDs: [String] = []
        for _ in 0..<iterations {
            for file in files { cachedIDs.append(try XCTUnwrap(discovery.sessionMetadata(from: file)).sessionHash) }
        }
        let cachedMS = Date().timeIntervalSince(cachedStart) * 1000
        XCTAssertEqual(cachedIDs, baselineIDs)
        XCTAssertEqual(discovery.metadataReadCount, 24)
        print("HEADER_MICROBENCH candidates=24 polls=40 uncached_reads=960 cached_reads=24 uncached_ms=\(baselineMS) cached_ms=\(cachedMS)")
    }

    func testUnchangedRolloutHeaderIsReadOnceAndInvalidatesOnEveryFileChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qv-header-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        func header(_ id: String) -> Data {
            Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"source\":\"cli\"}}\n".utf8)
        }
        try header("first").write(to: file)
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        for _ in 0..<96 { XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "first") }
        XCTAssertEqual(discovery.metadataReadCount, 1, "96 unchanged polls open/decode the header only once")

        let modified = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: header("other")); try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "other", "same-size rewrites cannot reuse stale identity")
        XCTAssertEqual(discovery.metadataReadCount, 2)

        try header("third").write(to: file, options: .atomic)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "third", "atomic replacement invalidates inode")
        let append = try FileHandle(forWritingTo: file)
        try append.seekToEnd(); try append.write(contentsOf: Data("{}\n".utf8)); try append.close()
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "third")
        XCTAssertEqual(discovery.metadataReadCount, 4)

        try Data("{\"type\":".utf8).write(to: file)
        XCTAssertNil(discovery.sessionMetadata(from: file))
        try header("ready").write(to: file)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "ready", "partial writes are not cached")
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(discovery.sessionMetadata(from: file), "deleted paths must not return cached identities")
        try header("again").write(to: file)
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "again")
        let beforeReset = discovery.metadataReadCount
        discovery.reset()
        XCTAssertEqual(discovery.sessionMetadata(from: file)?.threadID, "again")
        XCTAssertEqual(discovery.metadataReadCount, beforeReset + 1)
    }

    @MainActor
    func testRippleOrbAvoidsParticleInitializationUntilSelectedAndReusesViews() throws {
        let view = ActivitySelectableOrbView(frame: NSRect(x: 0, y: 0, width: 48, height: 48),
            initialState: .working, animation: .rippleGlow)
        guard view.hasRippleGlowRenderer else { throw XCTSkip("Metal ripple renderer unavailable on this host") }
        XCTAssertFalse(view.hasParticleRenderer)
        let ripple = try XCTUnwrap(view.subviews.first)
        view.setState(.completed)
        view.setReduceMotion(true)
        view.setPlaybackEnabled(false)
        view.layoutSubtreeIfNeeded()
        view.redrawIfPaused()
        XCTAssertFalse(view.hasParticleRenderer, "state/layout/playback changes must not instantiate the unused fallback")
        view.setAnimation(.particleOrb)
        XCTAssertTrue(view.hasParticleRenderer)
        XCTAssertEqual(view.subviews.count, 1)
        let particle = try XCTUnwrap(view.subviews.first)
        view.setAnimation(.rippleGlow)
        XCTAssertTrue(view.subviews.first === ripple)
        view.setAnimation(.particleOrb)
        XCTAssertTrue(view.subviews.first === particle)
    }
}
