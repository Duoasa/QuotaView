import Foundation

/// Cached canonical references are invalidated by reference/identity changes,
/// not by streamed text. A snapshot always rebuilds them from the bounded tree.
struct CodexDesktopProjectionIndex: Sendable {
    var canonicalIDs: Set<String> = []
    var tailKey: String?
    var tailIsAuthoritative = false
    private(set) var visitedEntries = 0
    init(state: DesktopIPCJSON) {
        guard state["turnHistory"]?["kind"]?.string == "canonical",
              let history = state["turnHistory"]?["history"]?.object,
              let islands = history["islands"]?.array, let tail = islands.last?.object,
              tail["newerBoundary"]?["status"]?.string == "exhausted",
              let entries = tail["entries"]?.array, let entities = history["entitiesByKey"]?.object else { return }
        for entry in entries {
            visitedEntries += 1
            guard let key = entry["value"]?.string, !key.isEmpty,
                  let id = entities[key]?["turnId"]?.string, !id.isEmpty else { return }
            tailKey = key
        }
        for island in islands {
            for entry in island["entries"]?.array ?? [] {
                visitedEntries += 1
                if let key = entry["value"]?.string, let id = entities[key]?["turnId"]?.string, !id.isEmpty {
                    canonicalIDs.insert(id)
                }
            }
        }
        tailIsAuthoritative = true
    }
    static func invalidated(by paths: [[DesktopIPCJSON]]) -> Bool {
        paths.contains { path in
            guard path.first?.string == "turnHistory" else { return path.isEmpty }
            guard path.count >= 4, path[1].string == "history", path[2].string == "entitiesByKey" else { return true }
            return path.count <= 4 || path[4].string == "turnId"
        }
    }
}

struct CodexDesktopProjectionCache: Sendable {
    private var index: CodexDesktopProjectionIndex?
    private var projection: CodexDesktopInteractionProjection?
    private(set) var indexVisitedEntries = 0
    private(set) var projectionBuildCount = 0
    mutating func project(conversationID: String, state: DesktopIPCJSON,
                          patches: [DesktopIPCJSON]?) throws -> CodexDesktopInteractionProjection {
        let paths = patches?.compactMap { $0["path"]?.array }
        // Missing/malformed paths never reuse a cache; applying still owns the
        // atomic protocol validation before reaching this point.
        let validPaths = paths != nil && paths?.count == patches?.count
        if index == nil || !validPaths || CodexDesktopProjectionIndex.invalidated(by: paths ?? []) {
            let fresh = CodexDesktopProjectionIndex(state: state)
            indexVisitedEntries += fresh.visitedEntries; index = fresh
        }
        if validPaths, let prior = projection,
           (paths ?? []).allSatisfy({ Self.isPresentationOnly($0, state: state) }) {
            // Only metadata represented in this projection is refreshed here.
            let refreshed = CodexDesktopInteractionProjection(currentTurnID: prior.currentTurnID, status: prior.status,
                title: state["title"]?.string ?? "", sourceKind: prior.sourceKind, startedAt: prior.startedAt,
                requests: prior.requests, authoritativePendingIdentities: prior.authoritativePendingIdentities,
                pendingRequestsAreAuthoritative: prior.pendingRequestsAreAuthoritative,
                asyncQuestions: prior.asyncQuestions, authoritativeAsyncQuestionIDs: prior.authoritativeAsyncQuestionIDs,
                threadWaitStatus: CodexDesktopRequestProjector.threadWaitStatus(state.object ?? [:]),
                asyncQuestionsAreAuthoritative: prior.asyncQuestionsAreAuthoritative)
            projection = refreshed; return refreshed
        }
        let result = try CodexDesktopRequestProjector.project(conversationID: conversationID, state: state, index: index!)
        projectionBuildCount += 1; projection = result; return result
    }
    func previouslyObservedAsyncAnswers(state: DesktopIPCJSON, turnID: String,
        questions: [CodexDesktopProjectedAsyncQuestion]) -> [String: String] {
        guard let index else { return [:] }
        return CodexDesktopRequestProjector.previouslyObservedAsyncAnswers(state: state, index: index,
            turnID: turnID, questions: questions)
    }
    private static func isPresentationOnly(_ path: [DesktopIPCJSON], state: DesktopIPCJSON) -> Bool {
        guard let root = path.first?.string else { return false }
        if ["title", "cwd", "model", "reasoningEffort", "effort", "threadRuntimeStatus", "tokenUsage"].contains(root) { return true }
        // Text/phase changes on an agent message do not change its questions.
        // User/steering message text may contain exact accepted replies.
        guard let field = path.last?.string, ["text", "phase"].contains(field), path.count >= 4,
              path[path.count - 3].string == "items" else { return false }
        var value = state
        for part in path.dropLast() {
            if let key = part.string, let next = value[key] { value = next }
            else if let number = part.integer, number >= 0, let array = value.array, number < array.count { value = array[Int(number)] }
            else { return false }
        }
        return value["type"]?.string == "agentMessage"
    }
}
