import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditRolloutRecoverySliceTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return root
    }
    private func line(_ type: String, _ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload])
        data.append(10); return data
    }
    private func filler(_ mebibytes: Int) throws -> Data {
        let one = try line("event_msg", ["type": "future", "ignored": String(repeating: "x", count: 900)])
        var data = Data(); data.reserveCapacity(mebibytes * 1_048_576)
        while data.count + one.count <= mebibytes * 1_048_576 { data.append(one) }
        return data
    }

    func testRecoveryMatrixYieldsAndNewestHealthyFilePublishesFirst() async throws {
        for count in [1,4,24] {
            for size in [1,8,16] {
                let root = try root()
                defer { try? FileManager.default.removeItem(at: root) }
                let body = try filler(size)
                for index in 1..<count {
                    var data = try line("session_meta", ["id": "slow-\(index)", "source": "vscode"])
                    data.append(body)
                    try data.write(to: root.appendingPathComponent("sessions/slow-\(index).jsonl"))
                }
                // A small new active file precedes the older recovery work.
                var healthy = try line("session_meta", ["id": "healthy", "source": "vscode"])
                healthy.append(try line("event_msg", ["type": "task_started", "turn_id": "live"]))
                if count == 1 { healthy.append(body) }
                let file = root.appendingPathComponent("sessions/healthy.jsonl")
                try healthy.write(to: file)
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(1)], ofItemAtPath: file.path)
                let ready = expectation(description: "bounded recovery completed")
                let sink = AuditRecoverySink()
                let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root,
                    pollIntervalSeconds: 10, maximumCandidateCount: count, startupTailBytes: 16 * 1_048_576))
                let start = ContinuousClock.now
                await client.start(handler: { record, _ in await sink.append(record) }, connectionStateHandler: { _ in },
                    healthHandler: { if $0 == .ready { ready.fulfill() } })
                await fulfillment(of: [ready], timeout: 30)
                let work = await client.parsingWorkSummary
                await client.stop()
                XCTAssertGreaterThan(work.yieldedSlices, 0)
                let first = await sink.records.first
                let firstAt = await sink.firstRecordAt
                let firstDuration = firstAt.map { start.duration(to: $0).components }
                let firstSeconds = firstDuration.map { Double($0.seconds) + Double($0.attoseconds) / 1e18 }
                if count > 1 {
                    guard case .activity(let event) = first?.update else { XCTFail("New healthy start missing"); continue }
                    XCTAssertEqual(event.sessionHash, CodexActivityPrivacy.hashIdentifier("healthy"))
                }
                let elapsed = start.duration(to: .now).components
                let firstLabel = firstSeconds.map { String($0) } ?? "missing"
                let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                print("B recovery candidates=\(count) MiB/file=\(size) lines=\(work.processedLines) yields=\(work.yieldedSlices) maxSliceSeconds=\(work.maximumSliceSeconds) firstEventSeconds=\(firstLabel) elapsedSeconds=\(elapsedSeconds)")
            }
        }
    }

    func testStopAtAnEnteredSlicePreventsOldGenerationPublication() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var data = try line("session_meta", ["id": "fixture", "source": "vscode"])
        data.append(try line("event_msg", ["type": "task_started", "turn_id": "one"]))
        data.append(try filler(8))
        try data.write(to: root.appendingPathComponent("sessions/fixture.jsonl"))
        let entered = expectation(description: "first recovery slice entered")
        let released = expectation(description: "old slice returned")
        let gate = AuditRecoveryGate()
        let sink = AuditRecoverySink()
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root, pollIntervalSeconds: 10))
        await client.setParsingSliceObserverForTesting {
            entered.fulfill(); await gate.wait(); released.fulfill()
        }
        await client.start(handler: { record, _ in await sink.append(record) }, connectionStateHandler: { _ in })
        await fulfillment(of: [entered], timeout: 3)
        let stopStart = ContinuousClock.now
        await client.stop()
        let stopDuration = stopStart.duration(to: .now).components
        await gate.release()
        await fulfillment(of: [released], timeout: 3)
        let records = await sink.records
        XCTAssertTrue(records.isEmpty)
        print("B stop at explicit recovery gate seconds=\(Double(stopDuration.seconds)+Double(stopDuration.attoseconds)/1e18)")
    }

    func testOneEnvelopeFeedsBothProjectionsWithIdenticalTimestampAndNoUserBody() throws {
        let timestamp = "2026-10-06T00:00:00.125Z"
        let raw = try JSONSerialization.data(withJSONObject: ["timestamp": timestamp, "type": "event_msg",
            "payload": ["type": "task_started", "turn_id": "one"]])
        let envelope = try XCTUnwrap(CodexLocalRolloutEnvelope(raw))
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: "fixture", sessionKind: .user)
        let record = try XCTUnwrap(decoder.decode(envelope))
        guard case .activity(let event) = record.update else { return XCTFail("Lifecycle expected") }
        XCTAssertEqual(event.occurredAt, envelope.timestamp)
        let user = try line("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": "private user body"]]])
        XCTAssertNil(CodexLocalPublicContent.decode(try XCTUnwrap(CodexLocalRolloutEnvelope(user)), sessionHash: "fixture", activeTurnHash: decoder.activeTurnHash))
        XCTAssertNil(CodexLocalRolloutEnvelope(Data(repeating: 32, count: 1_048_577)))
        XCTAssertNil(CodexLocalRolloutEnvelope(Data("{incomplete".utf8)))
    }

    func testNearLimitOversizedAndUnfinishedLinesPreserveSubsequentLiveAppend() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/fixture.jsonl")
        var data = try line("session_meta", ["id": "fixture", "source": "vscode"])
        data.append(try line("event_msg", ["type": "task_started", "turn_id": "one"]))
        // A valid near-limit line, followed by a rejected oversized complete line.
        data.append(try line("event_msg", ["type": "future", "ignored": String(repeating: "x", count: 1_048_400)]))
        data.append(Data(repeating: 32, count: 1_048_577)); data.append(10)
        let pending = try line("response_item", ["type": "function_call", "name": "exec_command", "call_id": "pending", "arguments": "{}"])
        let split = pending.count / 2
        data.append(pending.prefix(split))
        try data.write(to: file)
        let ready = expectation(description: "initial bounded lines consumed")
        let sink = AuditRecoverySink()
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root, pollIntervalSeconds: 10))
        await client.start(handler: { record, _ in await sink.append(record) }, connectionStateHandler: { _ in },
            healthHandler: { if $0 == .ready { ready.fulfill() } })
        await fulfillment(of: [ready], timeout: 5)
        let before = await sink.records.count
        XCTAssertEqual(before, 1)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: pending.dropFirst(split)); try handle.close()
        await client.pollOnceForTesting()
        let records = await sink.records
        XCTAssertEqual(records.count, 2)
        guard case .activity(let event) = records.last?.update else { await client.stop(); return XCTFail("Completed append missing") }
        XCTAssertEqual(event.event, .preToolUse)
        XCTAssertEqual(event.toolCallHash, CodexActivityPrivacy.hashIdentifier("pending"))
        await client.stop()
    }
}

private actor AuditRecoverySink {
    private(set) var records: [CodexLocalRolloutDecodedRecord] = []
    private(set) var firstRecordAt: ContinuousClock.Instant?
    func append(_ record: CodexLocalRolloutDecodedRecord) {
        if firstRecordAt == nil { firstRecordAt = .now }
        records.append(record)
    }
}
private actor AuditRecoveryGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { if !released { await withCheckedContinuation { continuation = $0 } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
