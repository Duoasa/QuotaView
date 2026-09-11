import Foundation

/// Pure, bounded recovery gate. Historical context cannot select a task until
/// fresh evidence for the same session and turn confirms it.
public struct CodexLocalActivityRecovery {
    public struct Projection {
        public let context: [CodexLocalRolloutDecodedRecord]
        public let record: CodexLocalRolloutDecodedRecord
        public let confirmationTime: Date?
    }

    private struct Context {
        let identity: CodexActivityTaskIdentity
        var records: [CodexLocalRolloutDecodedRecord]
    }
    private var contexts: [String: Context] = [:]
    private var order: [String] = []
    private let capacity: Int

    public init(capacity: Int = 128) { self.capacity = max(1, capacity) }

    public mutating func project(_ record: CodexLocalRolloutDecodedRecord) -> Projection? {
        guard let (identity, occurredAt) = Self.identityAndDate(record) else { return nil }
        let session = identity.sessionHash
        if record.requiresLiveConfirmation {
            if contexts[session]?.identity != identity { remove(session) }
            if case .activity(let event) = record.update, event.event == .userPromptSubmit { remove(session) }
            var context = contexts[session] ?? Context(identity: identity, records: [])
            context.records.append(record)
            contexts[session] = context
            order.removeAll { $0 == session }
            order.append(session)
            while contexts.count > capacity, let oldest = order.first { remove(oldest) }
            return nil
        }

        let pending = contexts[session]
        remove(session)
        var shouldRecover = pending?.identity == identity
        if case .activity(let event) = record.update {
            if [.stop, .interrupt, .sessionEnd, .userPromptSubmit].contains(event.event) { shouldRecover = false }
        }
        return Projection(context: shouldRecover ? pending?.records ?? [] : [], record: record,
                          confirmationTime: shouldRecover ? occurredAt : nil)
    }

    private mutating func remove(_ session: String) {
        contexts.removeValue(forKey: session)
        order.removeAll { $0 == session }
    }

    private static func identityAndDate(_ record: CodexLocalRolloutDecodedRecord) -> (CodexActivityTaskIdentity, Date)? {
        switch record.update {
        case .activity(let event): return (.init(sessionHash: event.sessionHash, turnHash: event.turnHash), event.occurredAt)
        case .tokenUsage(let usage): return (.init(sessionHash: usage.sessionHash, turnHash: usage.turnHash), usage.occurredAt)
        case .tokenUsageReplay(let updates):
            guard let first = updates.first,
                  updates.allSatisfy({ $0.sessionHash == first.sessionHash && $0.turnHash == first.turnHash }) else { return nil }
            return (.init(sessionHash: first.sessionHash, turnHash: first.turnHash), first.occurredAt)
        }
    }
}
