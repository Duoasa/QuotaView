import Foundation
import XCTest
@testable import CodexPulseCore

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

        let snapshot: CodexSnapshot
        do {
            snapshot = try await client.fetchSnapshot(
                now: Date(timeIntervalSince1970: 1_785_000_000)
            )
        } catch {
            let log = (try? String(contentsOf: fixture.log, encoding: .utf8)) ?? "<no log>"
            XCTFail("Client failed with \(error). Fake server log:\n\(log)")
            await client.stop()
            return
        }

        XCTAssertEqual(snapshot.availability, .ready)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.usedPercent, 38)
        XCTAssertEqual(snapshot.remainingPercent, 62)
        XCTAssertEqual(snapshot.creditBalance, "0")
        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertEqual(snapshot.lifetimeTokens, 9_876)

        await client.stop()
    }

    private func makeFakeAppServer() throws -> (executable: URL, log: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let executable = directory.appendingPathComponent("fake-codex")
        let log = directory.appendingPathComponent("fake-codex.log")
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
              printf '{"id":%s,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":38,"windowDurationMins":10080,"resetsAt":1785303228},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":2,"credits":[]}}}\\n' "$id"
              ;;
            *usage*)
              sleep 0.05
              printf '{"id":%s,"result":{"summary":{"lifetimeTokens":9876},"dailyUsageBuckets":[]}}\\n' "$id"
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
}
