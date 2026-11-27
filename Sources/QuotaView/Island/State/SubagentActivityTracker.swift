import QuotaViewCore

/// Stores verified parentage and the latest admitted observations. The task
/// registry owns execution identity and alone determines the turn eligible for replay.
struct SubagentActivityTracker {
    private var identities: [String: CodexActivitySubagentIdentity] = [:]
    private var latest: [String: CodexActivityEvent] = [:]
    private var starts: [String: CodexActivityEvent] = [:]
    private var unavailable: Set<String> = []

    var sessions: [String] { Array(identities.keys) }
    func identity(for session: String) -> CodexActivitySubagentIdentity? { identities[session] }
    func latestSource(for session: String) -> CodexActivityEventSource? { latest[session]?.source }

    mutating func register(_ identity: CodexActivitySubagentIdentity) -> Bool {
        if let previous = identities[identity.sessionHash], previous.parentSessionHash != identity.parentSessionHash {
            return false
        }
        identities[identity.sessionHash] = identity
        return true
    }

    @discardableResult
    mutating func removeIdentity(for session: String) -> CodexActivitySubagentIdentity? {
        identities.removeValue(forKey: session)
    }

    mutating func retainChildren(in kinds: [String: CodexActivitySessionKind]) {
        identities = identities.filter { kinds[$0.key] == .subagent }
    }

    mutating func observe(_ event: CodexActivityEvent, startsTurn: Bool) {
        latest[event.sessionHash] = event
        if startsTurn { starts[event.sessionHash] = event }
        unavailable.remove(event.sessionHash)
    }

    mutating func markUnavailable(_ source: CodexActivityEventSource) {
        for (session, event) in latest where (event.source ?? .hook) == source {
            unavailable.insert(session)
        }
    }

    mutating func clearActivity(for session: String) {
        latest.removeValue(forKey: session)
        starts.removeValue(forKey: session)
        unavailable.remove(session)
    }

    func replay(for current: CodexActivityTaskIdentity?) -> [CodexActivityEvent] {
        guard let current, identities[current.sessionHash] != nil, !unavailable.contains(current.sessionHash),
              let event = latest[current.sessionHash],
              event.turnHash == nil || event.turnHash == current.turnHash else { return [] }
        var events: [CodexActivityEvent] = []
        if let start = starts[current.sessionHash], start.turnHash == current.turnHash, start != event {
            events.append(start.classified(as: .subagent))
        }
        events.append(event.classified(as: .subagent))
        return events
    }
}
