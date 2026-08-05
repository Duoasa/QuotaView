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

    private func makeFakeAppServer(
        usageFails: Bool = false,
        usageHangs: Bool = false
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
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf 'received:%s\\n' "$line" >> "\(log.path)"
          id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p')
          case "$line" in
            *'"method":"initialize"'*)
              sleep 0.05
              printf '{"id":%s,"result":{"userAgent":"fake"}}\\n' "$id"
              ;;
            *rateLimits*)
              sleep 0.05
              printf '{"id":%s,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":38,"windowDurationMins":10080,"resetsAt":1785303228},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitsByLimitId":null}}\\n' "$id"
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
