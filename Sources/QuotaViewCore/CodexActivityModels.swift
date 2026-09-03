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
    case interrupt = "Interrupt"
    case stop = "Stop"
}

public enum CodexActivityToolCategory: String, Codable, Sendable {
    case shell
    case fileEdit
    case mcp
    case subagent
    case goal
    case localTool
    case unknown
}

public enum CodexActivityEventSource: String, Codable, Sendable {
    case hook
    case appServer
    case localRollout
}

public enum CodexActivityPlanSource: String, Codable, Sendable {
    case legacyTool
    case appServer
    case localRollout
}

public enum CodexActivityTurnCompletionStatus: String, Codable, Sendable {
    case completed
    case interrupted
    case failed
}

public enum CodexActivityGoalStatus: String, Codable, Sendable {
    case active
    case paused
    case blocked
    case usageLimited
    case budgetLimited
    case complete
}

public enum CodexActivityWaitReason: String, Codable, Sendable {
    case approval
    case userInput
}

public enum CodexActivitySessionStartSource: String, Codable, Sendable {
    case startup
    case resume
    case clear
    case compact
}

public struct CodexActivityPlanProgress: Codable, Equatable, Sendable {
    public static let maximumStepCount = 100
    public static let maximumActiveFraction = 0.95
    public static let inProgressStepWeight = 0.10

    public let completedSteps: Int
    public let inProgressSteps: Int
    public let pendingSteps: Int

    public init(
        completedSteps: Int,
        inProgressSteps: Int,
        pendingSteps: Int
    ) {
        self.completedSteps = completedSteps
        self.inProgressSteps = inProgressSteps
        self.pendingSteps = pendingSteps
    }

    public var totalSteps: Int {
        completedSteps + inProgressSteps + pendingSteps
    }

    public var approximateFraction: Double? {
        guard completedSteps >= 0,
              inProgressSteps >= 0,
              pendingSteps >= 0,
              (1...Self.maximumStepCount).contains(totalSteps)
        else {
            return nil
        }

        let weightedCompleted = Double(completedSteps)
            + Double(inProgressSteps) * Self.inProgressStepWeight
        return min(
            weightedCompleted / Double(totalSteps),
            Self.maximumActiveFraction
        )
    }
}

public struct CodexActivityEvent: Codable, Equatable, Sendable {
    public static let minimumSupportedSchemaVersion = 1
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let event: CodexActivityHookEvent
    public let sessionHash: String
    public let turnHash: String?
    public let workspaceName: String?
    public let toolCategory: CodexActivityToolCategory?
    public let sessionStartSource: CodexActivitySessionStartSource?
    public let planProgress: CodexActivityPlanProgress?
    public let source: CodexActivityEventSource?
    public let planSource: CodexActivityPlanSource?
    public let turnCompletionStatus: CodexActivityTurnCompletionStatus?
    public let goalStatus: CodexActivityGoalStatus?
    public let waitReason: CodexActivityWaitReason?
    public let occurredAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        event: CodexActivityHookEvent,
        sessionHash: String,
        turnHash: String? = nil,
        workspaceName: String? = nil,
        toolCategory: CodexActivityToolCategory? = nil,
        sessionStartSource: CodexActivitySessionStartSource? = nil,
        planProgress: CodexActivityPlanProgress? = nil,
        source: CodexActivityEventSource? = nil,
        planSource: CodexActivityPlanSource? = nil,
        turnCompletionStatus: CodexActivityTurnCompletionStatus? = nil,
        goalStatus: CodexActivityGoalStatus? = nil,
        waitReason: CodexActivityWaitReason? = nil,
        occurredAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.sessionHash = sessionHash
        self.turnHash = turnHash
        self.workspaceName = workspaceName
        self.toolCategory = toolCategory
        self.sessionStartSource = sessionStartSource
        self.planProgress = planProgress
        self.source = source
        self.planSource = planSource
        self.turnCompletionStatus = turnCompletionStatus
        self.goalStatus = goalStatus
        self.waitReason = waitReason
        self.occurredAt = occurredAt
    }
}

public struct CodexActivityBridgeEnvelope: Codable, Equatable, Sendable {
    public let authenticationToken: String
    public let installationIdentifier: String
    public let eventID: String?
    public let activity: CodexActivityEvent

    public init(
        authenticationToken: String,
        installationIdentifier: String,
        eventID: String? = nil,
        activity: CodexActivityEvent
    ) {
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
        self.eventID = eventID
        self.activity = activity
    }
}

public enum CodexActivityDeliverySource: String, Codable, Sendable {
    case liveSocket
    case liveQueue
    case startupReplay
    case localRollout
}

public struct CodexActivityDelivery: Equatable, Sendable {
    public let eventID: String?
    public let source: CodexActivityDeliverySource
    public let activity: CodexActivityEvent

    public init(
        eventID: String? = nil,
        source: CodexActivityDeliverySource,
        activity: CodexActivityEvent
    ) {
        self.eventID = eventID
        self.source = source
        self.activity = activity
    }
}

public struct CodexActivityTokenUsageUpdate: Equatable, Sendable {
    public let sessionHash: String
    public let turnHash: String
    public let cumulativeTotalTokens: Int64
    public let lastReportedTotalTokens: Int64
    public let occurredAt: Date

    public init(
        sessionHash: String,
        turnHash: String,
        cumulativeTotalTokens: Int64,
        lastReportedTotalTokens: Int64,
        occurredAt: Date = Date()
    ) {
        self.sessionHash = sessionHash
        self.turnHash = turnHash
        self.cumulativeTotalTokens = cumulativeTotalTokens
        self.lastReportedTotalTokens = lastReportedTotalTokens
        self.occurredAt = occurredAt
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

public enum CodexActivityTurnLifecycle: String, Codable, Sendable {
    case idle
    case active
    case completed
    case unconfirmed
}

public struct CodexActivitySnapshot: Equatable, Sendable {
    public let sessionHash: String
    public let state: CodexActivityVisualState
    public let workspaceName: String?
    public let operationKey: CodexActivityOperationKey
    public let toolCategory: CodexActivityToolCategory?
    public let approximateProgressFraction: Double?
    public let occurredAt: Date

    public init(
        sessionHash: String,
        state: CodexActivityVisualState,
        workspaceName: String?,
        operationKey: CodexActivityOperationKey,
        toolCategory: CodexActivityToolCategory?,
        approximateProgressFraction: Double?,
        occurredAt: Date
    ) {
        self.sessionHash = sessionHash
        self.state = state
        self.workspaceName = workspaceName
        self.operationKey = operationKey
        self.toolCategory = toolCategory
        self.approximateProgressFraction = approximateProgressFraction
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
    case executingPlan
    case managingGoal
    case followingGoal
    case goalPaused
    case goalBlocked
    case goalLimited
    case goalCompleted
    case usingTool
    case awaitingApproval
    case awaitingUserInput
    case reviewingToolResult
    case compactingContext
    case continuingAfterCompaction
    case subagentStarted
    case subagentStopped
    case turnCompleted
    case turnInterrupted
    case turnFailed
    case bridgeUnavailable
    case malformedEvent
}

public enum CodexActivityReducer {
    public static func snapshot(
        for event: CodexActivityEvent,
        approximateProgressFraction: Double? = nil,
        activeGoalStatus: CodexActivityGoalStatus? = nil
    ) -> CodexActivitySnapshot? {
        guard event.schemaVersion
                >= CodexActivityEvent.minimumSupportedSchemaVersion,
              event.schemaVersion
                <= CodexActivityEvent.currentSchemaVersion,
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
            operation = event.planSource != nil
                ? .executingPlan
                : operationForTool(event.toolCategory)
        case .permissionRequest:
            state = .awaitingConfirmation
            operation = event.waitReason == .userInput
                ? .awaitingUserInput
                : .awaitingApproval
        case .postToolUse:
            switch event.goalStatus {
            case .active:
                state = .thinking
                operation = .followingGoal
            case .paused:
                state = .standby
                operation = .goalPaused
            case .blocked:
                state = .error
                operation = .goalBlocked
            case .usageLimited, .budgetLimited:
                state = .unavailable
                operation = .goalLimited
            case .complete:
                state = .completed
                operation = .goalCompleted
            case nil:
                state = .thinking
                operation = event.toolCategory == .goal
                    ? .managingGoal
                    : .reviewingToolResult
            }
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
        case .interrupt:
            state = .standby
            operation = .turnInterrupted
        case .stop:
            switch event.turnCompletionStatus {
            case .interrupted:
                state = .standby
                operation = .turnInterrupted
            case .failed:
                state = .error
                operation = .turnFailed
            case .completed, nil:
                switch activeGoalStatus {
                case .active:
                    state = .standby
                    operation = .followingGoal
                case .paused:
                    state = .standby
                    operation = .goalPaused
                case .blocked:
                    state = .error
                    operation = .goalBlocked
                case .usageLimited, .budgetLimited:
                    state = .unavailable
                    operation = .goalLimited
                case .complete, nil:
                    state = .completed
                    operation = .turnCompleted
                }
            }
        }

        let isCompletedTurn = event.event == .stop
            && event.turnCompletionStatus != .interrupted
            && event.turnCompletionStatus != .failed
            && (activeGoalStatus == nil || activeGoalStatus == .complete)

        return CodexActivitySnapshot(
            sessionHash: event.sessionHash,
            state: state,
            workspaceName: event.workspaceName,
            operationKey: operation,
            toolCategory: event.toolCategory,
            approximateProgressFraction:
                isCompletedTurn
                ? 1
                : approximateProgressFraction
                    ?? event.planProgress?.approximateFraction,
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
        case .stop, .interrupt:
            true
        case .postToolUse:
            event.goalStatus != nil && event.goalStatus != .active
        case .sessionStart:
            event.sessionStartSource != .compact
        default:
            false
        }
    }

    public static func isSettledContinuationEvent(
        after event: CodexActivityEvent
    ) -> Bool {
        switch event.event {
        case .postToolUse, .postCompact, .subagentStop:
            true
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
        case .goal:
            .managingGoal
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
        if ["create_goal", "get_goal", "update_goal"].contains(
            canonicalName
        ) || canonicalName.hasSuffix("__create_goal")
            || canonicalName.hasSuffix("__get_goal")
            || canonicalName.hasSuffix("__update_goal")
        {
            return .goal
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
