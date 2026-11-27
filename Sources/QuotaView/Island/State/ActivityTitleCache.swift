import Foundation
import QuotaViewCore

/// Display names belong to the thread. An asynchronous fallback belongs to the
/// execution which requested it, including the generation of a legacy turn.
struct ActivityTitleCache {
    struct Lookup: Equatable {
        let identity: CodexActivityTaskIdentity
        fileprivate let id = UUID()
    }

    private var entries: [String: (value: String, source: IslandTaskTitleSource)] = [:]
    private var attempts: [String: (lookup: Lookup, date: Date)] = [:]

    func title(for session: String) -> String? { entries[session]?.value }
    func source(for session: String) -> IslandTaskTitleSource { entries[session]?.source ?? .fallback }

    mutating func remember(_ value: String?, session: String, source: IslandTaskTitleSource) {
        guard let value else { return }
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 512,
              source.rawValue >= self.source(for: session).rawValue else { return }
        entries[session] = (title, source)
    }

    mutating func beginLookup(for identity: CodexActivityTaskIdentity, now: Date = Date()) -> Lookup? {
        let session = identity.sessionHash
        guard source(for: session) == .fallback else { return nil }
        if let attempt = attempts[session], attempt.lookup.identity == identity,
           now.timeIntervalSince(attempt.date) < 10 { return nil }
        let lookup = Lookup(identity: identity)
        attempts[session] = (lookup, now)
        return lookup
    }

    @discardableResult
    mutating func finish(_ lookup: Lookup, title: String?, current: CodexActivityTaskIdentity?) -> Bool {
        let session = lookup.identity.sessionHash
        guard current == lookup.identity, attempts[session]?.lookup == lookup else { return false }
        remember(title, session: session, source: .fallback)
        return true
    }

    mutating func forget(_ session: String) {
        entries.removeValue(forKey: session)
        attempts.removeValue(forKey: session)
    }
}
