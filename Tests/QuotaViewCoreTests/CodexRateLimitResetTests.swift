import Foundation
import XCTest
@testable import QuotaViewCore
@testable import QuotaView

final class CodexRateLimitResetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func journal() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qv-reset-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("attempt.json")
    }
    private func assertError(_ expected: CodexResetError, _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? CodexResetError, expected) }
    }

    func testPreparationNeverConsumesOrWritesAnAttempt() async throws {
        let fake = FakeResetTransport(), url = try journal()
        let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        let ready = try await service.prepare(now: now)
        XCTAssertEqual(ready.availableCount, 2)
        XCTAssertFalse(ready.isRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let calls = await fake.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testConfirmedResetPinsCreditAndRejectsRepeatedConfirmation() async throws {
        let fake = FakeResetTransport(), url = try journal()
        let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        let ready = try await service.prepare(now: now)
        let result = try await service.execute(ready, now: now)
        XCTAssertEqual(result, .reset)
        let calls = await fake.calls
        XCTAssertEqual(calls.map(\.credit), ["credit-A"])
        XCTAssertEqual(calls.map(\.key), [ready.id.uuidString])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        await assertError(.confirmationExpired) { _ = try await service.execute(ready, now: now) }
    }

    func testUnknownOutcomeSurvivesRestartAndReusesKeyWithNoCredits() async throws {
        let fake = FakeResetTransport(), url = try journal()
        await fake.configure(failure: .timeoutAfterConsumption)
        let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        let ready = try await service.prepare(now: now)
        await assertError(.outcomeUnknown) { _ = try await service.execute(ready, now: now) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let persisted = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persisted.contains("example.test"), "Persist only the account hash, never its email")
        await fake.configure(count: 0, details: false)
        let restored = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        let retry = try await restored.prepare(now: now)
        XCTAssertTrue(retry.isRetry)
        XCTAssertEqual(retry.id, ready.id)
        let result = try await restored.execute(retry, now: now)
        XCTAssertEqual(result, .alreadyRedeemed)
        let calls = await fake.calls
        XCTAssertEqual(calls.map(\.key), [ready.id.uuidString, ready.id.uuidString])
        XCTAssertEqual(Set(calls.map(\.credit)), ["credit-A"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testConcurrentConfirmationCannotConsumeTwice() async throws {
        let fake = FakeResetTransport(), url = try journal()
        await fake.configure(delay: true)
        let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        let ready = try await service.prepare(now: now)
        let first = Task { try await service.execute(ready, now: now) }
        while await fake.calls.isEmpty { await Task.yield() }
        await assertError(.busy) { _ = try await service.execute(ready, now: now) }
        _ = try await first.value
        let calls = await fake.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testAccountChangeAndCreditChangeBlockBeforeConsumption() async throws {
        for changeAccount in [true, false] {
            let fake = FakeResetTransport(), url = try journal()
            let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
            let ready = try await service.prepare(now: now)
            if changeAccount { await fake.configure(email: "other@example.test") }
            else { await fake.configure(credit: "credit-B") }
            await assertError(changeAccount ? .accountChanged : .creditDetailsUnavailable) {
                _ = try await service.execute(ready, now: now)
            }
            let calls = await fake.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testExpiredConfirmationCannotConsume() async throws {
        let fake = FakeResetTransport(), url = try journal()
        let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        let ready = try await service.prepare(now: now)
        await assertError(.confirmationExpired) { _ = try await service.execute(ready, now: now.addingTimeInterval(61)) }
        let calls = await fake.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testMissingExpiredAndUnsupportedCreditDetailsFailClosed() async throws {
        for variant in 0...3 {
            let fake = FakeResetTransport(), url = try journal()
            switch variant {
            case 0: await fake.configure(details: false)
            case 1: await fake.configure(expiresAt: 1)
            case 2: await fake.configure(status: "consumed")
            default: await fake.configure(resetType: "unknown")
            }
            let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
            await assertError(.creditDetailsUnavailable) { _ = try await service.prepare(now: now) }
            let calls = await fake.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testJournalFailureStopsBeforeConsumption() async throws {
        let fake = FakeResetTransport(), url = try journal()
        try Data("corrupt".utf8).write(to: url)
        let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        await assertError(.storageUnavailable) { _ = try await service.prepare(now: now) }
        try FileManager.default.removeItem(at: url)
        let ready = try await service.prepare(now: now)
        // Make the atomic destination unwritable by replacing it with a directory.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        await assertError(.storageUnavailable) { _ = try await service.execute(ready, now: now) }
        let calls = await fake.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testKnownServerOutcomesAndUnsupportedMethod() async throws {
        for outcome in [CodexResetOutcome.noCredit, .nothingToReset] {
            let fake = FakeResetTransport(), url = try journal()
            await fake.configure(outcome: outcome)
            let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
            let ready = try await service.prepare(now: now)
            let actual = try await service.execute(ready, now: now)
            XCTAssertEqual(actual, outcome)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        let fake = FakeResetTransport(), url = try journal()
        await fake.configure(failure: .unsupported)
        let service = CodexRateLimitResetCoordinator(client: fake, journalURL: url)
        let ready = try await service.prepare(now: now)
        await assertError(.unsupported) { _ = try await service.execute(ready, now: now) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testControllerRequiresConfirmationAndCancelNeverConsumes() async throws {
        let fake = FakeResetTransport(), url = try journal()
        var refreshes = 0
        let controller = CodexResetController(journalURL: url,
            makeCoordinator: { CodexRateLimitResetCoordinator(client: fake, journalURL: url) },
            refresh: { refreshes += 1 })
        await controller.confirm()
        await controller.prepare()
        controller.cancelConfirmation()
        await controller.confirm()
        XCTAssertEqual(controller.phase, .idle)
        var calls = await fake.calls
        XCTAssertTrue(calls.isEmpty)
        await controller.prepare()
        await controller.confirm()
        XCTAssertEqual(controller.phase, .finished(.reset))
        XCTAssertEqual(refreshes, 1)
        calls = await fake.calls
        XCTAssertEqual(calls.count, 1)
    }
}

private actor FakeResetTransport: CodexResetTransport {
    enum Failure { case timeoutAfterConsumption, unsupported }
    struct Call { let credit: String; let key: String }
    private(set) var calls: [Call] = []
    private var email = "account@example.test", credit = "credit-A", status = "available", resetType = "codexRateLimits"
    private var count = 2, expiresAt = 2_000_000_000
    private var details = true, delay = false
    private var failure: Failure?
    private var outcome: CodexResetOutcome = .reset
    private var redeemed = Set<String>()

    func configure(count: Int? = nil, details: Bool? = nil, email: String? = nil, credit: String? = nil,
                   expiresAt: Int? = nil, status: String? = nil, resetType: String? = nil,
                   failure: Failure? = nil, outcome: CodexResetOutcome? = nil, delay: Bool? = nil) {
        if let count { self.count = count }; if let details { self.details = details }
        if let email { self.email = email }; if let credit { self.credit = credit }
        if let expiresAt { self.expiresAt = expiresAt }; if let status { self.status = status }
        if let resetType { self.resetType = resetType }; if let delay { self.delay = delay }
        if let failure { self.failure = failure }; if let outcome { self.outcome = outcome }
    }
    func readResetAccount() throws -> CodexResetAccountResponse {
        try decode(["account": ["type": "chatgpt", "email": email]])
    }
    func readResetLimits() throws -> AccountRateLimitsResponse {
        let credits: Any = details ? [["id": credit, "resetType": resetType, "status": status,
            "grantedAt": 1, "expiresAt": expiresAt]] : NSNull()
        return try decode(["rateLimits": ["primary": ["usedPercent": 30]],
            "rateLimitResetCredits": ["availableCount": count, "credits": credits]])
    }
    func consumeResetCredit(creditID: String, idempotencyKey: String) async throws -> CodexResetOutcome {
        calls.append(Call(credit: creditID, key: idempotencyKey))
        if delay { try await Task.sleep(nanoseconds: 50_000_000) }
        if failure == .unsupported { throw CodexAppServerClient.ClientError.server(code: -32601, message: "unknown method") }
        if redeemed.contains(idempotencyKey) { return .alreadyRedeemed }
        if outcome == .reset { redeemed.insert(idempotencyKey) }
        if failure == .timeoutAfterConsumption {
            failure = nil
            throw CodexAppServerClient.ClientError.requestTimedOut("account/rateLimitResetCredit/consume")
        }
        return outcome
    }
    func stopResetConnection() {}
    private func decode<T: Decodable>(_ value: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
