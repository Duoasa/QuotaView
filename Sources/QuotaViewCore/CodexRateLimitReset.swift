import CryptoKit
import Foundation

public struct CodexResetAccountResponse: Decodable, Sendable {
    public struct Account: Decodable, Sendable {
        public let type: String
        public let email: String?
    }
    public let account: Account?
    var scope: String? {
        guard let account, account.type == "chatgpt",
              let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return nil }
        return SHA256.hash(data: Data(email.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum CodexResetOutcome: String, Decodable, Sendable {
    case reset, alreadyRedeemed, nothingToReset, noCredit
}

public protocol CodexResetTransport: Sendable {
    func readResetAccount() async throws -> CodexResetAccountResponse
    func readResetLimits() async throws -> AccountRateLimitsResponse
    func consumeResetCredit(creditID: String, idempotencyKey: String) async throws -> CodexResetOutcome
    func stopResetConnection() async
}

public enum CodexResetError: Error, Equatable, Sendable {
    case disabledByPreference, busy, signInRequired, accountChanged, noCredit, creditDetailsUnavailable
    case confirmationExpired, storageUnavailable, unsupported, connectionFailed, outcomeUnknown
}

public struct CodexResetPreparation: Equatable, Sendable {
    public let id: UUID
    public let availableCount: Int
    public let isRetry: Bool
    let accountScope: String
    let creditID: String
    let preparedAt: Date
}

/// A reset is never scheduled or retried automatically. A persisted attempt pins
/// both the opaque credit and idempotency key until its outcome is known.
public actor CodexRateLimitResetCoordinator {
    private struct Attempt: Codable {
        let id: UUID
        let accountScope: String
        let creditID: String
    }
    private let client: any CodexResetTransport
    private let journalURL: URL
    private let isConsumptionAllowed: @MainActor @Sendable () -> Bool
    private var prepared: CodexResetPreparation?
    private var busy = false

    public init(client: any CodexResetTransport, journalURL: URL,
                isConsumptionAllowed: @escaping @MainActor @Sendable () -> Bool = { true }) {
        self.client = client
        self.journalURL = journalURL
        self.isConsumptionAllowed = isConsumptionAllowed
    }

    public func prepare(now: Date = Date()) async throws -> CodexResetPreparation {
        guard !busy else { throw CodexResetError.busy }
        busy = true
        prepared = nil
        defer { busy = false }
        do {
            guard await isConsumptionAllowed() else { throw CodexResetError.disabledByPreference }
            guard let scope = try await client.readResetAccount().scope else { throw CodexResetError.signInRequired }
            let limits = try await client.readResetLimits()
            guard try await client.readResetAccount().scope == scope else { throw CodexResetError.accountChanged }
            let pending = try loadAttempt()
            if let pending, pending.accountScope != scope { throw CodexResetError.accountChanged }
            let count = limits.rateLimitResetCredits?.availableCount ?? 0
            let creditID: String
            if let pending {
                // The original credit may already be redeemed. Let the server
                // reconcile that exact key, even when the current count is zero.
                creditID = pending.creditID
            } else {
                guard let summary = limits.rateLimitResetCredits else { throw CodexResetError.creditDetailsUnavailable }
                guard summary.availableCount > 0 else { throw CodexResetError.noCredit }
                guard let credit = eligibleCredits(summary, now: now).first else { throw CodexResetError.creditDetailsUnavailable }
                creditID = credit.id
            }
            let value = CodexResetPreparation(id: pending?.id ?? UUID(), availableCount: max(0, count),
                isRetry: pending != nil, accountScope: scope, creditID: creditID, preparedAt: now)
            prepared = value
            await client.stopResetConnection()
            return value
        } catch let error as CodexResetError { await client.stopResetConnection(); throw error }
        catch { await client.stopResetConnection(); throw Self.readError(error) }
    }

    /// Only a matching, freshly presented confirmation can enter this method.
    public func execute(_ confirmation: CodexResetPreparation, now: Date = Date()) async throws -> CodexResetOutcome {
        guard !busy else { throw CodexResetError.busy }
        guard prepared == confirmation,
              now.timeIntervalSince(confirmation.preparedAt) >= 0,
              now.timeIntervalSince(confirmation.preparedAt) <= 60 else { throw CodexResetError.confirmationExpired }
        busy = true
        prepared = nil
        defer { busy = false }
        do {
            guard await isConsumptionAllowed() else { throw CodexResetError.disabledByPreference }
            guard try await client.readResetAccount().scope == confirmation.accountScope else { throw CodexResetError.accountChanged }
            if !confirmation.isRetry {
                let limits = try await client.readResetLimits()
                guard let summary = limits.rateLimitResetCredits else { throw CodexResetError.creditDetailsUnavailable }
                guard summary.availableCount > 0 else { throw CodexResetError.noCredit }
                guard eligibleCredits(summary, now: now).contains(where: { $0.id == confirmation.creditID }) else {
                    throw CodexResetError.creditDetailsUnavailable
                }
                guard try await client.readResetAccount().scope == confirmation.accountScope else { throw CodexResetError.accountChanged }
            }
            guard await isConsumptionAllowed() else { throw CodexResetError.disabledByPreference }
            let pending = try loadAttempt()
            guard pending?.id == (confirmation.isRetry ? confirmation.id : nil) else { throw CodexResetError.outcomeUnknown }
            try Task.checkCancellation()
            try saveAttempt(Attempt(id: confirmation.id, accountScope: confirmation.accountScope, creditID: confirmation.creditID))
        } catch let error as CodexResetError { await client.stopResetConnection(); throw error }
        catch { await client.stopResetConnection(); throw Self.readError(error) }

        do {
            let outcome = try await client.consumeResetCredit(creditID: confirmation.creditID, idempotencyKey: confirmation.id.uuidString)
            try FileManager.default.removeItem(at: journalURL)
            await client.stopResetConnection()
            return outcome
        } catch let error as CodexAppServerClient.ClientError {
            await client.stopResetConnection()
            if case .server(code: -32601, message: _) = error {
                // Method-not-found proves this server could not redeem anything.
                try? FileManager.default.removeItem(at: journalURL)
                throw CodexResetError.unsupported
            }
            throw CodexResetError.outcomeUnknown
        } catch {
            await client.stopResetConnection()
            // Includes malformed replies, transport failures and an unsuccessful
            // journal cleanup. Never substitute a new key after an ambiguous call.
            throw CodexResetError.outcomeUnknown
        }
    }

    private func eligibleCredits(_ summary: RateLimitResetCreditsSummary, now: Date) -> [RateLimitResetCredit] {
        (summary.credits ?? []).filter {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.status == "available" && $0.resetType == "codexRateLimits"
                && ($0.expiresAt.map { Double($0) > now.timeIntervalSince1970 } ?? true)
        }.sorted { ($0.expiresAt ?? Int.max) < ($1.expiresAt ?? Int.max) }
    }

    private func loadAttempt() throws -> Attempt? {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return nil }
        do { return try JSONDecoder().decode(Attempt.self, from: Data(contentsOf: journalURL)) }
        catch { throw CodexResetError.storageUnavailable }
    }

    private func saveAttempt(_ attempt: Attempt) throws {
        do {
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(attempt).write(to: journalURL, options: .atomic)
        } catch { throw CodexResetError.storageUnavailable }
    }

    private static func readError(_ error: Error) -> CodexResetError {
        if let error = error as? CodexAppServerClient.ClientError,
           case .server(code: -32601, message: _) = error { return .unsupported }
        return .connectionFailed
    }
}
