import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexAppServerClientTests: XCTestCase {
    func testClientReadsDelayedJSONLinesFromAppServerProcess() async throws {
        let fixture = try makeFakeAppServer()
        defer {
            try? FileManager.default.removeItem(
                at: fixture.executable.deletingLastPathComponent()
            )
        }

        let client = CodexAppServerClient(
            executablePath: fixture.executable.path,
            requestTimeoutSeconds: 3
        )

        let payload: CodexProviderPayload
        do {
            payload = try await client.fetchPayload(
                now: Date(timeIntervalSince1970: 1_785_000_000)
            )
        } catch {
            let log = (try? String(contentsOf: fixture.log, encoding: .utf8)) ?? "<no log>"
            XCTFail("Client failed with \(error). Fake server log:\n\(log)")
            await client.stop()
            return
        }
        let result = try CodexProviderAdapter.makeResult(
            payload: payload
        )
        let snapshot = result.snapshot
        let primary = try XCTUnwrap(snapshot.rateWindows.first)

        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.plan?.rawValue, "plus")
        XCTAssertEqual(primary.usedFraction, 0.38)
        XCTAssertEqual(primary.remainingFraction, 0.62)
        XCTAssertEqual(
            count(
                CodexDomainCatalog.resetCreditsID,
                in: snapshot
            ),
            2
        )
        XCTAssertEqual(
            count(
                CodexDomainCatalog.lifetimeTokensID,
                in: snapshot
            ),
            9_876
        )

        await client.stop()
    }

    func testOptionalUsageFailureKeepsRequiredRateLimits() async throws {
        let fixture = try makeFakeAppServer(usageFails: true)
        defer {
            try? FileManager.default.removeItem(
                at: fixture.executable.deletingLastPathComponent()
            )
        }
        let client = CodexAppServerClient(
            executablePath: fixture.executable.path,
            requestTimeoutSeconds: 3
        )

        let payload = try await client.fetchPayload()

        XCTAssertNil(payload.usage)
        XCTAssertEqual(payload.optionalIssues.count, 1)
        XCTAssertEqual(
            payload.rateLimits.rateLimits.primary?.usedPercent,
            38
        )
        await client.stop()
    }

    func testOptionalUsageTimeoutDoesNotInvalidateRequiredRateLimits()
        async throws {
        let fixture = try makeFakeAppServer(usageHangs: true)
        defer {
            try? FileManager.default.removeItem(
                at: fixture.executable.deletingLastPathComponent()
            )
        }
        let client = CodexAppServerClient(
            executablePath: fixture.executable.path,
            requestTimeoutSeconds: 1
        )

        let first = try await client.fetchPayload()
        let second = try await client.fetchPayload(
            includeUsage: false
        )

        XCTAssertNil(first.usage)
        XCTAssertEqual(first.optionalIssues.count, 1)
        XCTAssertEqual(
            first.rateLimits.rateLimits.primary?.usedPercent,
            38
        )
        XCTAssertEqual(
            second.rateLimits.rateLimits.primary?.usedPercent,
            38
        )
        await client.stop()
    }

    func testOversizedOutputFailsWithinBound() async throws {
        let fixture = try makeOversizedAppServer()
        defer {
            try? FileManager.default.removeItem(
                at: fixture.deletingLastPathComponent()
            )
        }
        let client = CodexAppServerClient(
            executablePath: fixture.path,
            startupTimeoutSeconds: 2,
            requestTimeoutSeconds: 2,
            maximumLineBytes: 1_024
        )

        do {
            _ = try await client.fetchPayload(includeUsage: false)
            XCTFail("Oversized output should fail")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("超过安全大小限制")
            )
        }
        await client.stop()
    }

    func testThreadLookupRequestsAllSourcesAndReceivesNotifications()
        async throws {
        let fixture = try makeFakeAppServer(emitPlanNotification: true)
        defer {
            try? FileManager.default.removeItem(
                at: fixture.executable.deletingLastPathComponent()
            )
        }
        let client = CodexAppServerClient(
            executablePath: fixture.executable.path,
            requestTimeoutSeconds: 3
        )
        let notification = expectation(
            description: "native plan notification"
        )
        await client.setActivityNotificationHandler { event in
            if event.planSource == .appServer,
               event.planProgress?.totalSteps == 4 {
                notification.fulfill()
            }
        }

        let title = try await client.fetchThreadDisplayName(
            matchingSessionHash:
                CodexActivityPrivacy.hashIdentifier("thread-native")
        )
        await fulfillment(of: [notification], timeout: 2)

        XCTAssertEqual(title, "Native Thread")
        let log = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertTrue(log.contains(#""sourceKinds""#))
        XCTAssertTrue(log.contains("appServer"))
        XCTAssertTrue(log.contains("subAgentThreadSpawn"))
        await client.stop()
    }

    func testThreadLookupFallsBackWhenServerRejectsSourceKinds()
        async throws {
        let fixture = try makeFakeAppServer(
            rejectExpandedThreadList: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: fixture.executable.deletingLastPathComponent()
            )
        }
        let client = CodexAppServerClient(
            executablePath: fixture.executable.path,
            requestTimeoutSeconds: 3
        )

        let title = try await client.fetchThreadDisplayName(
            matchingSessionHash:
                CodexActivityPrivacy.hashIdentifier("thread-native")
        )

        XCTAssertEqual(title, "Native Thread")
        let log = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertEqual(
            log.split(separator: "\n").filter {
                $0.contains("thread") && $0.contains("list")
            }.count,
            2
        )
        await client.stop()
    }

    func testSharedDaemonConfigurationAutoDiscoversWithoutLaunching() {
        let automatic = CodexSharedAppServerActivityClient.Configuration.live(
            environment: [
                "CODEX_HOME": "/private/tmp/quotaview-codex-home"
            ]
        )
        XCTAssertTrue(automatic.isEnabled)
        XCTAssertFalse(automatic.launchServerIfNeeded)
        XCTAssertEqual(
            automatic.socketURL.path,
            "/private/tmp/quotaview-codex-home/app-server-control/app-server-control.sock"
        )

        let managed = CodexSharedAppServerActivityClient.Configuration.live(
            environment: [
                "CODEX_APP_SERVER_USE_LOCAL_DAEMON": "1",
                "CODEX_HOME": "/private/tmp/quotaview-codex-home"
            ]
        )
        XCTAssertTrue(managed.isEnabled)
        XCTAssertTrue(managed.launchServerIfNeeded)

        let disabled = CodexSharedAppServerActivityClient.Configuration.live(
            environment: [
                "QUOTAVIEW_CODEX_SOCKET_DISABLED": "1"
            ]
        )
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertFalse(disabled.launchServerIfNeeded)
    }

    func testSharedDaemonOptsOutOfContentNotificationsOnly() {
        let methods = Set(
            CodexSharedAppServerActivityClient
                .contentNotificationOptOutMethods
        )

        XCTAssertTrue(methods.contains("item/agentMessage/delta"))
        XCTAssertTrue(methods.contains("item/reasoning/textDelta"))
        XCTAssertTrue(methods.contains("turn/diff/updated"))
        XCTAssertTrue(methods.contains("item/commandExecution/outputDelta"))
        XCTAssertFalse(methods.contains("thread/started"))
        XCTAssertFalse(methods.contains("turn/plan/updated"))
        XCTAssertFalse(methods.contains("turn/completed"))
    }

    func testSharedDaemonClientFramesAreMasked() throws {
        let payload = Data(#"{"method":"initialized"}"#.utf8)
        let frame = CodexAppServerWebSocketFrameEncoder.clientFrame(
            opcode: .text,
            payload: payload,
            maskingKey: 0x01020304
        )
        let bytes = [UInt8](frame)

        XCTAssertEqual(bytes[0], 0x81)
        XCTAssertEqual(bytes[1] & 0x80, 0x80)
        XCTAssertEqual(Int(bytes[1] & 0x7F), payload.count)
        XCTAssertEqual(Array(bytes[2..<6]), [1, 2, 3, 4])

        let unmasked = Data(bytes[6...].enumerated().map {
            $0.element ^ [UInt8(1), 2, 3, 4][$0.offset % 4]
        })
        XCTAssertEqual(unmasked, payload)
    }

    func testSharedDaemonDecoderHandlesFragmentedTextPingAndCoalescing()
        throws {
        var decoder = CodexAppServerWebSocketMessageDecoder()
        let first = serverFrame(
            opcode: .text,
            payload: Data("{\"method\":".utf8),
            isFinal: false
        )
        let continuation = serverFrame(
            opcode: .continuation,
            payload: Data("\"initialized\"}".utf8),
            isFinal: true
        )
        let ping = serverFrame(
            opcode: .ping,
            payload: Data("ok".utf8),
            isFinal: true
        )

        XCTAssertTrue(try decoder.append(first.prefix(3)).isEmpty)
        var combined = Data(first.dropFirst(3))
        combined.append(continuation)
        combined.append(ping)
        let events = try decoder.append(combined)

        XCTAssertEqual(
            events,
            [
                .text(Data(#"{"method":"initialized"}"#.utf8)),
                .ping(Data("ok".utf8))
            ]
        )
    }

    private func serverFrame(
        opcode: CodexAppServerWebSocketOpcode,
        payload: Data,
        isFinal: Bool
    ) -> Data {
        precondition(payload.count <= 125)
        var data = Data([
            (isFinal ? 0x80 : 0x00) | opcode.rawValue,
            UInt8(payload.count)
        ])
        data.append(payload)
        return data
    }

    private func makeFakeAppServer(
        usageFails: Bool = false,
        usageHangs: Bool = false,
        emitPlanNotification: Bool = false,
        rejectExpandedThreadList: Bool = false
    ) throws -> (executable: URL, log: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let executable = directory.appendingPathComponent("fake-codex")
        let log = directory.appendingPathComponent("fake-codex.log")
        let usageResponse: String
        if usageHangs {
            usageResponse = ":"
        } else if usageFails {
            usageResponse = """
              printf '{"id":%s,"error":{"code":-32000,"message":"usage unavailable"}}\\n' "$id"
              """
        } else {
            usageResponse = """
              printf '{"id":%s,"result":{"summary":{"lifetimeTokens":9876},"dailyUsageBuckets":[]}}\\n' "$id"
              """
        }
        let planNotification = emitPlanNotification
            ? """
              printf '{"method":"turn/plan/updated","params":{"threadId":"thread-native","turnId":"turn-native","plan":[{"step":"private one","status":"completed"},{"step":"private two","status":"inProgress"},{"step":"private three","status":"pending"},{"step":"private four","status":"pending"}]}}\\n'
              """
            : ":"
        let threadListResponse: String
        if rejectExpandedThreadList {
            threadListResponse = """
              case "$line" in
                *sourceKinds*)
                  printf '{"id":%s,"error":{"code":-32602,"message":"unknown sourceKinds"}}\\n' "$id"
                  ;;
                *)
                  printf '{"id":%s,"result":{"data":[{"id":"thread-native","sessionId":null,"cwd":"/tmp/native","name":"Native Thread"}],"nextCursor":null}}\\n' "$id"
                  ;;
              esac
              """
        } else {
            threadListResponse = """
              printf '{"id":%s,"result":{"data":[{"id":"thread-native","sessionId":null,"cwd":"/tmp/native","name":"Native Thread"}],"nextCursor":null}}\\n' "$id"
              """
        }
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf 'received:%s\\n' "$line" >> "\(log.path)"
          id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p')
          case "$line" in
            *'"method":"initialize"'*)
              sleep 0.05
              printf '{"id":%s,"result":{"userAgent":"fake"}}\\n' "$id"
              \(planNotification)
              ;;
            *thread*list*)
              \(threadListResponse)
              ;;
            *rateLimits*)
              sleep 0.05
              printf '{"id":%s,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":38,"windowDurationMins":10080,"resetsAt":1785303228},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":2,"credits":[]}}}\\n' "$id"
              ;;
            *usage*)
              sleep 0.05
              \(usageResponse)
              ;;
          esac
        done
        """

        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return (executable, log)
    }

    private func makeOversizedAppServer() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let executable = directory.appendingPathComponent("fake-codex")
        let oversizedLine = String(repeating: "x", count: 2_048)
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '\(oversizedLine)\\n'
        done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }

    private func count(
        _ id: MetricID,
        in snapshot: ProviderSnapshot
    ) -> Int64? {
        guard case .count(let value) = snapshot.currentMetrics
            .first(where: { $0.definitionID == id })?
            .value else {
            return nil
        }
        return value
    }
}
