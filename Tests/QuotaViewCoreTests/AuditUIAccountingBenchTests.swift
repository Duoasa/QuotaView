import Foundation
import XCTest
@testable import QuotaView

/// Ingress-only accounting checks. No response capability, account, UI launch,
/// animation/display timing or process-memory measurement is involved.
final class AuditUIAccountingBenchTests: XCTestCase {
    private struct Random {
        var state: UInt64 = 0x51564155443135
        mutating func next(_ upper: Int) -> Int {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(upper))
        }
    }

    private func wire(_ method: String, _ params: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
    }

    @MainActor private func check(_ store: IslandLiveStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(store.retainedContentBytes, store.contentAccountingOracle, file: file, line: line)
        XCTAssertGreaterThanOrEqual(store.retainedContentBytes, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(store.retainedContentBytes, 2_097_152, file: file, line: line)
        XCTAssertTrue(store.tasks.allSatisfy { $0.entries.count <= 200 }, file: file, line: line)
    }

    @MainActor private func send(_ store: IslandLiveStore, _ method: String, _ params: [String: Any],
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        store.receive(try wire(method, params))
        check(store, file: file, line: line)
    }

    @MainActor private func start(_ store: IslandLiveStore, thread: String, turn: String) throws {
        try send(store, "turn/started", ["threadId": thread, "turnId": turn, "turn": ["id": turn]])
    }

    @MainActor private func item(_ store: IslandLiveStore, thread: String, turn: String,
                                 id: String, text: String, command: Bool = false) throws {
        var item: [String: Any] = ["id": id, "type": command ? "commandExecution" : "agentMessage", "status": "completed"]
        if command { item["command"] = "fixture command"; item["aggregatedOutput"] = text }
        else { item["text"] = text; item["phase"] = "commentary" }
        try send(store, "item/completed", ["threadId": thread, "turnId": turn, "item": item])
    }

    @MainActor func testDeterministicRandomPublicIngressAccountingMatchesOracle() throws {
        let store = IslandLiveStore()
        XCTAssertNil(store.respond)
        var random = Random()
        var generations = Array(repeating: 0, count: 8)
        func thread(_ i: Int) -> String { "accounting-fixture-\(i)" }
        func turn(_ i: Int) -> String { "turn-\(i)-\(generations[i])" }
        for i in generations.indices { try start(store, thread: thread(i), turn: turn(i)) }
        for step in 0..<800 {
            let i = random.next(generations.count)
            let id = "item-\(random.next(16))"
            let fragments = ["ASCII", "中文", "e\u{301}", "👩🏽‍💻"]
            let body = String(repeating: fragments[random.next(fragments.count)], count: 1 + random.next(80))
            switch random.next(10) {
            case 0, 1:
                try item(store, thread: thread(i), turn: turn(i), id: id, text: body, command: step % 2 == 0)
            case 2, 3:
                try send(store, step % 2 == 0 ? "item/agentMessage/delta" : "item/commandExecution/outputDelta",
                    ["threadId": thread(i), "turnId": turn(i), "itemId": id, "delta": body])
            case 4:
                // A same-source upsert can shrink or replace an earlier output.
                try item(store, thread: thread(i), turn: turn(i), id: id, text: "替换", command: true)
            case 5:
                generations[i] += 1
                try start(store, thread: thread(i), turn: turn(i))
            case 6:
                try send(store, "thread/closed", ["threadId": thread(i)])
                generations[i] += 1
                try start(store, thread: thread(i), turn: turn(i))
            case 7:
                try send(store, "item/started", ["threadId": thread(i), "turnId": turn(i),
                    "item": ["id": id, "type": "contextCompaction", "arguments": ["fixture": body]]])
            case 8:
                try send(store, "turn/completed", ["threadId": thread(i), "turnId": turn(i),
                    "turn": ["id": turn(i), "status": "completed"]])
                generations[i] += 1
                try start(store, thread: thread(i), turn: turn(i))
            default:
                store.reset(); check(store)
                XCTAssertEqual(store.retainedContentBytes, 0)
                for j in generations.indices {
                    generations[j] += 1
                    try start(store, thread: thread(j), turn: turn(j))
                }
            }
        }
        for i in generations.indices { try send(store, "thread/closed", ["threadId": thread(i)]) }
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertEqual(store.retainedContentBytes, 0)
        store.reset(); check(store)
        XCTAssertEqual(store.retainedContentBytes, 0)
    }

    @MainActor func testTwoHundredEntryAndGlobalByteEvictionStayExactlyAccounted() throws {
        let store = IslandLiveStore()
        try start(store, thread: "count", turn: "one")
        for i in 0..<205 { try item(store, thread: "count", turn: "one", id: "count-\(i)", text: "public \(i)") }
        XCTAssertEqual(store.tasks.first?.entries.count, 200)
        XCTAssertEqual(store.tasks.first?.removedEntryCount, 5)
        try start(store, thread: "count", turn: "two")
        XCTAssertEqual(store.retainedContentBytes, 0)

        let large = String(repeating: "字", count: 65_536)
        for thread in 0..<3 {
            let id = "bytes-\(thread)"
            try start(store, thread: id, turn: "one")
            for i in 0..<8 { try item(store, thread: id, turn: "one", id: "large-\(i)", text: large, command: true) }
        }
        XCTAssertGreaterThan(store.tasks.reduce(0) { $0 + $1.removedEntryCount }, 0)
        XCTAssertGreaterThan(store.retainedContentBytes, 0)
        XCTAssertLessThanOrEqual(store.retainedContentBytes, 2_097_152)
        for thread in ["count", "bytes-0", "bytes-1", "bytes-2"] { try send(store, "thread/closed", ["threadId": thread]) }
        XCTAssertEqual(store.retainedContentBytes, 0)

        // Context-only rows also participate in the shared budget even when no
        // display entry exists to evict. Inputs remain below the 1MiB wire bound.
        try start(store, thread: "context-only", turn: "one")
        let arguments = String(repeating: "x", count: 750_000)
        for i in 0..<4 {
            try send(store, "item/started", ["threadId": "context-only", "turnId": "one",
                "item": ["id": "context-\(i)", "type": "contextCompaction", "arguments": ["fixture": arguments]]])
        }
        XCTAssertTrue(store.tasks.first?.entries.isEmpty == true)
        XCTAssertGreaterThan(store.retainedContentBytes, 0)
        try send(store, "thread/closed", ["threadId": "context-only"])
        XCTAssertEqual(store.retainedContentBytes, 0)
        store.reset(); check(store)
    }

    private func microseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1_000_000 + Double(c.attoseconds) / 1e12
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))]
    }

    @MainActor func testIngressLatencyAndAccountingOperationsAcrossHistorySizes() throws {
        for taskCount in [1, 100, 1_000] {
            for deltaCount in [50, 200] {
                let store = IslandLiveStore()
                XCTAssertNil(store.respond)
                // One retained entry per historical task; the newest task stays
                // active and receives deltas. No UI callbacks are installed.
                for i in 0..<taskCount {
                    let thread = "bench-\(i)"
                    try start(store, thread: thread, turn: "one")
                    try item(store, thread: thread, turn: "one", id: "message", text: "public fixture")
                    if i < taskCount - 1 {
                        try send(store, "turn/completed", ["threadId": thread, "turnId": "one",
                            "turn": ["id": "one", "status": "completed"]])
                    }
                }
                XCTAssertEqual(store.tasks.count, taskCount)
                let thread = "bench-\(taskCount - 1)"
                let prepared = try (0..<deltaCount).map { index in
                    try wire("item/agentMessage/delta", ["threadId": thread, "turnId": "one", "itemId": "message", "delta": index % 2 == 0 ? "中" : "a"])
                }
                let beforeOperations = store.contentAccountingOperations
                var samples: [Double] = []; samples.reserveCapacity(deltaCount)
                for data in prepared {
                    let before = ContinuousClock.now
                    store.receive(data)
                    samples.append(microseconds(before.duration(to: .now)))
                    // Independent slow oracle is outside the timing interval.
                    check(store)
                }
                let operations = store.contentAccountingOperations - beforeOperations
                XCTAssertEqual(operations, deltaCount)
                XCTAssertEqual(store.tasks.count, taskCount)
                let p95 = percentile(samples, 0.95), p99 = percentile(samples, 0.99)
                print("QV-AUD-015 ingress tasks=\(taskCount) deltas=\(deltaCount) entriesPerTask=1 accountingOperationsDelta=\(operations) retainedBytes=\(store.retainedContentBytes) p95Microseconds=\(p95) p99Microseconds=\(p99)")
                store.reset(); check(store)
                XCTAssertEqual(store.retainedContentBytes, 0)
            }
        }
    }
}
