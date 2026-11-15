import Foundation
import Darwin
import XCTest
import QuotaViewCore
import QuotaViewActivityHookSupport
@testable import QuotaView

final class AgentOutputRateSmokeTests: XCTestCase {
    @MainActor
    func testRateSnapshotPersistsDuringWaitingAndUsesCompletedAverage() throws {
        let model = IslandLiveStore(), now = Date()
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: "rate-session", turnHash: "rate-turn"))
        let latest = try XCTUnwrap(CodexOutputRateSample(outputTokens: 300,
            startedAt: now.addingTimeInterval(-5), endedAt: now))
        let previous = try XCTUnwrap(CodexOutputRateSample(outputTokens: 100,
            startedAt: now.addingTimeInterval(-30), endedAt: now.addingTimeInterval(-20)))
        let average = latest.combined(with: previous)
        model.receiveOutputRate(session: "rate-session", turn: "rate-turn", latest: latest, average: average)
        model.receiveToken(.init(sessionHash: "rate-session", turnHash: "rate-turn", cumulativeTotalTokens: 1234, lastReportedTotalTokens: 1234))
        func card() throws -> CodexMultitaskRenderTask {
            try XCTUnwrap(model.display(english: true, remaining: nil, enabled: true, privacy: false,
                at: now.addingTimeInterval(3600)).state.tasks.first)
        }
        XCTAssertEqual(try card().outputRate, latest, "Snapshot must survive the previous 30-second expiry")
        XCTAssertTrue(try card().renderState.tokenUsageTitle?.hasSuffix(" tok") == true)
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: "rate-session", turnHash: "rate-turn"))
        XCTAssertEqual(try card().outputRate, latest, "Waiting must not remove the last sample")
        model.receiveLegacy(.init(event: .stop, sessionHash: "rate-session", turnHash: "rate-turn", turnCompletionStatus: .completed))
        XCTAssertEqual(try card().outputRate, average)
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: "rate-session", turnHash: "next-turn"))
        XCTAssertNil(try card().outputRate, "Do not carry the previous task snapshot into a new turn")
    }

    @MainActor
    func testNativeRateIPCCompletionLateUsageAndNextTurn() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/qv-rate-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "QuotaView.RateSmoke." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults), island = IslandSession()
        let helper = root.appendingPathComponent("helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let socket = root.appendingPathComponent("events.sock")
        let installer = NativeAgentInstaller(provider: .openCode, socketURL: socket, authenticationToken: "fixture",
            homeOverride: home, supportOverride: root.appendingPathComponent("support"), helperOverride: helper)
        preferences.openCodeEnabled = true
        let runtime = NativeAgentRuntime(provider: .openCode, preferences: preferences, island: island,
            defaults: defaults, installer: installer)
        defer { runtime.stop(); island.stop() }
        runtime.start()
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertTrue(condition())
        }
        try await wait { runtime.status == .waiting }
        var sequence = 0
        func send(_ event: String, turn: String = "t1", fields: [String: Any] = [:]) async throws {
            sequence += 1
            var payload: [String: Any] = ["session_id": "s", "hook_event_name": event, "turn_id": turn,
                "source_epoch": "fixture", "source_sequence": sequence]
            payload.merge(fields) { _, b in b }
            var line = try JSONSerialization.data(withJSONObject: ["authenticationToken": "fixture",
                "eventID": UUID().uuidString, "kind": "hook", "awaitDecision": false, "payload": payload])
            line.append(10)
            let body = line
            let accepted = await Task.detached {
                let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { return false }; defer { Darwin.close(fd) }
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
                withUnsafeMutableBytes(of: &address.sun_path) { target in
                    target.copyBytes(from: Array(socket.path.utf8CString).map { UInt8(bitPattern: $0) })
                }
                let connected = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
                }
                guard connected == 0, body.withUnsafeBytes({ Darwin.send(fd, $0.baseAddress, $0.count, 0) }) == body.count else { return false }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = Darwin.recv(fd, &buffer, buffer.count, 0)
                guard count > 0, let ack = (try? JSONSerialization.jsonObject(with: Data(buffer.prefix(count)))) as? [String: Any] else { return false }
                return ack["accepted"] as? Bool == true
            }.value
            XCTAssertTrue(accepted)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        let now = Date().timeIntervalSince1970 * 1000
        try await send("TurnStarted")
        try await send("Usage", fields: ["usage_id": "a", "output_tokens": 100, "rate_start_ms": now-20000, "rate_end_ms": now-10000])
        try await send("Usage", fields: ["usage_id": "b", "output_tokens": 300, "rate_start_ms": now-6000, "rate_end_ms": now-1000])
        try await send("Usage", fields: ["usage_id": "b", "output_tokens": 300, "rate_start_ms": now-6000, "rate_end_ms": now-1000])
        try await wait { island.model.tasks.first?.averageOutputRate?.outputTokens == 400 }
        XCTAssertEqual(island.model.tasks.first?.outputRate?.tokensPerSecond, 60)
        XCTAssertEqual(island.model.tasks.first?.averageOutputRate?.duration, 15)
        XCTAssertNil(island.model.tasks.first?.tokens, "A rate-only update must not invent total usage")
        try await send("Stop")
        try await wait { island.model.tasks.first?.status == .completed }
        try await send("Usage", fields: ["usage_id": "c", "output_tokens": 100, "rate_start_ms": now-1000, "rate_end_ms": now])
        try await wait { island.model.tasks.first?.averageOutputRate?.outputTokens == 500 }
        XCTAssertEqual(island.model.tasks.first?.averageOutputRate?.tokensPerSecond, 31.25)
        XCTAssertEqual(island.model.tasks.first?.status, .completed)
        try await send("Usage", turn: "stale", fields: ["usage_id": "old", "output_tokens": 999, "rate_start_ms": now-1000, "rate_end_ms": now+1])
        XCTAssertEqual(island.model.tasks.first?.averageOutputRate?.outputTokens, 500)
        try await send("TurnStarted", turn: "t2")
        try await wait { island.model.tasks.first?.terminal == false }
        XCTAssertNil(island.model.tasks.first?.outputRate)
        XCTAssertNil(island.model.tasks.first?.averageOutputRate)
    }
}
