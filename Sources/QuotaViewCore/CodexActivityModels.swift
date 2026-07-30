import CryptoKit
import Foundation

public enum CodexActivityHookEvent: String, Codable, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case stop = "Stop"
}

public enum CodexActivityToolCategory: String, Codable, Sendable {
    case shell
    case fileEdit
    case mcp
    case subagent
    case localTool
    case unknown
}

public enum CodexActivitySessionStartSource: String, Codable, Sendable {
    case startup
    case resume
    case clear
    case compact
}

public struct CodexActivityEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let event: CodexActivityHookEvent
    public let sessionHash: String
    public let turnHash: String?
    public let workspaceName: String?
    public let toolCategory: CodexActivityToolCategory?
    public let sessionStartSource: CodexActivitySessionStartSource?
    public let occurredAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        event: CodexActivityHookEvent,
        sessionHash: String,
        turnHash: String? = nil,
        workspaceName: String? = nil,
        toolCategory: CodexActivityToolCategory? = nil,
        sessionStartSource: CodexActivitySessionStartSource? = nil,
        occurredAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.sessionHash = sessionHash
        self.turnHash = turnHash
        self.workspaceName = workspaceName
        self.toolCategory = toolCategory
        self.sessionStartSource = sessionStartSource
        self.occurredAt = occurredAt
    }
}

public struct CodexActivityBridgeEnvelope: Codable, Equatable, Sendable {
    public let authenticationToken: String
    public let installationIdentifier: String
    public let activity: CodexActivityEvent

    public init(
        authenticationToken: String,
        installationIdentifier: String,
        activity: CodexActivityEvent
    ) {
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
        self.activity = activity
    }
}

public enum CodexActivityVisualState: String, Codable, CaseIterable, Sendable {
    case disconnectedCodex
    case standby
    case thinking
    case working
    case compactingContext
    case awaitingConfirmation
    case completed
    case error
    case unavailable
}

public enum CodexActivityPresentation: String, Codable, Sendable {
    case hidden
    case expanded
    case compact
}

public struct CodexActivitySnapshot: Equatable, Sendable {
    public let sessionHash: String
    public let state: CodexActivityVisualState
    public let workspaceName: String?
    public let operationKey: CodexActivityOperationKey
    public let toolCategory: CodexActivityToolCategory?
    public let occurredAt: Date

    public init(
        sessionHash: String,
        state: CodexActivityVisualState,
        workspaceName: String?,
        operationKey: CodexActivityOperationKey,
        toolCategory: CodexActivityToolCategory?,
        occurredAt: Date
    ) {
        self.sessionHash = sessionHash
        self.state = state
        self.workspaceName = workspaceName
        self.operationKey = operationKey
        self.toolCategory = toolCategory
        self.occurredAt = occurredAt
    }
}

public enum CodexActivityOperationKey: String, Codable, Sendable {
    case connectingSession
    case sessionEnded
    case analyzingRequest
    case executingShell
    case editingFiles
    case callingExternalTool
    case coordinatingSubagent
    case usingLocalTool
    case usingTool
    case awaitingApproval
    case reviewingToolResult
    case compactingContext
    case continuingAfterCompaction
    case subagentStarted
    case subagentStopped
    case turnCompleted
    case bridgeUnavailable
    case malformedEvent
}

public enum CodexActivityReducer {
    public static func snapshot(
        for event: CodexActivityEvent
    ) -> CodexActivitySnapshot? {
        guard event.schemaVersion == CodexActivityEvent.currentSchemaVersion,
              !event.sessionHash.isEmpty
        else {
            return nil
        }

        let state: CodexActivityVisualState
        let operation: CodexActivityOperationKey

        switch event.event {
        case .sessionStart:
            if event.sessionStartSource == .compact {
                state = .thinking
                operation = .continuingAfterCompaction
            } else {
                state = .standby
                operation = .connectingSession
            }
        case .sessionEnd:
            state = .standby
            operation = .sessionEnded
        case .userPromptSubmit:
            state = .thinking
            operation = .analyzingRequest
        case .preToolUse:
            state = .working
            operation = operationForTool(event.toolCategory)
        case .permissionRequest:
            state = .awaitingConfirmation
            operation = .awaitingApproval
        case .postToolUse:
            state = .thinking
            operation = .reviewingToolResult
        case .preCompact:
            state = .compactingContext
            operation = .compactingContext
        case .postCompact:
            state = .thinking
            operation = .continuingAfterCompaction
        case .subagentStart:
            state = .working
            operation = .subagentStarted
        case .subagentStop:
            state = .thinking
            operation = .subagentStopped
        case .stop:
            state = .completed
            operation = .turnCompleted
        }

        return CodexActivitySnapshot(
            sessionHash: event.sessionHash,
            state: state,
            workspaceName: event.workspaceName,
            operationKey: operation,
            toolCategory: event.toolCategory,
            occurredAt: event.occurredAt
        )
    }

    public static func shouldHideImmediately(
        after event: CodexActivityEvent
    ) -> Bool {
        event.event == .sessionEnd
    }

    public static func shouldStartInactivityCycle(
        after event: CodexActivityEvent
    ) -> Bool {
        switch event.event {
        case .stop:
            true
        case .sessionStart:
            event.sessionStartSource != .compact
        default:
            false
        }
    }

    private static func operationForTool(
        _ category: CodexActivityToolCategory?
    ) -> CodexActivityOperationKey {
        switch category {
        case .shell:
            .executingShell
        case .fileEdit:
            .editingFiles
        case .mcp:
            .callingExternalTool
        case .subagent:
            .coordinatingSubagent
        case .localTool:
            .usingLocalTool
        case .unknown, nil:
            .usingTool
        }
    }
}

public enum CodexActivityPrivacy {
    public static func hashIdentifier(_ identifier: String) -> String {
        let digest = SHA256.hash(data: Data(identifier.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func workspaceName(from path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path)
            .standardizedFileURL
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(80))
    }

    public static func toolCategory(
        for canonicalName: String?
    ) -> CodexActivityToolCategory? {
        guard let canonicalName, !canonicalName.isEmpty else {
            return nil
        }

        if canonicalName == "Bash" || canonicalName == "exec_command" {
            return .shell
        }
        if ["apply_patch", "Edit", "Write"].contains(canonicalName) {
            return .fileEdit
        }
        if canonicalName == "Agent"
            || canonicalName == "spawn_agent"
            || canonicalName.contains("subagent")
        {
            return .subagent
        }
        if canonicalName.hasPrefix("mcp__") {
            return .mcp
        }
        return .localTool
    }
}

public struct CodexThreadMetadata: Decodable, Equatable, Sendable {
    public let id: String
    public let sessionId: String?
    public let cwd: String?
    public let name: String?

    public init(
        id: String,
        sessionId: String?,
        cwd: String?,
        name: String?
    ) {
        self.id = id
        self.sessionId = sessionId
        self.cwd = cwd
        self.name = name
    }

    public func matches(sessionHash: String) -> Bool {
        CodexActivityPrivacy.hashIdentifier(id) == sessionHash
            || sessionId.map(CodexActivityPrivacy.hashIdentifier)
                == sessionHash
    }

    public var privacySafeDisplayName: String? {
        if let name {
            let trimmed = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                return String(trimmed.prefix(120))
            }
        }
        return CodexActivityPrivacy.workspaceName(from: cwd)
    }
}
