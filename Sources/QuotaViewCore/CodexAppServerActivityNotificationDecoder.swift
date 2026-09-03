import Foundation

public enum CodexAppServerActivityNotificationDecoder {
    public static let maximumMessageBytes = 1_048_576

    public static func decodeTokenUsage(
        line: String,
        now: Date = Date()
    ) -> CodexActivityTokenUsageUpdate? {
        guard let data = line.data(using: .utf8) else { return nil }
        return decodeTokenUsage(data: data, now: now)
    }

    public static func decodeTokenUsage(
        data: Data,
        now: Date = Date()
    ) -> CodexActivityTokenUsageUpdate? {
        guard data.count <= maximumMessageBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              envelope["id"] == nil,
              envelope["method"] as? String
                == "thread/tokenUsage/updated",
              let params = envelope["params"] as? [String: Any],
              let threadID = params["threadId"] as? String,
              !threadID.isEmpty,
              let turnID = params["turnId"] as? String,
              !turnID.isEmpty,
              let tokenUsage = params["tokenUsage"]
                as? [String: Any],
              let total = tokenUsage["total"] as? [String: Any],
              let last = tokenUsage["last"] as? [String: Any],
              let cumulativeTotalTokens = nonnegativeInteger(
                  total["totalTokens"]
              ),
              let lastReportedTotalTokens = nonnegativeInteger(
                  last["totalTokens"]
              ),
              cumulativeTotalTokens >= lastReportedTotalTokens
        else {
            return nil
        }

        return CodexActivityTokenUsageUpdate(
            sessionHash: CodexActivityPrivacy.hashIdentifier(threadID),
            turnHash: CodexActivityPrivacy.hashIdentifier(turnID),
            cumulativeTotalTokens: cumulativeTotalTokens,
            lastReportedTotalTokens: lastReportedTotalTokens,
            occurredAt: eventDate(
                from: envelope["emittedAtMs"]
                    ?? params["emittedAtMs"],
                fallback: now
            )
        )
    }

    public static func decode(
        line: String,
        now: Date = Date()
    ) -> CodexActivityEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        return decode(data: data, now: now)
    }

    public static func decode(
        data: Data,
        now: Date = Date()
    ) -> CodexActivityEvent? {
        guard data.count <= maximumMessageBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              envelope["id"] == nil,
              let method = envelope["method"] as? String,
              let params = envelope["params"] as? [String: Any],
              let threadID = params["threadId"] as? String,
              !threadID.isEmpty
        else {
            return nil
        }

        let occurredAt = eventDate(
            from: envelope["emittedAtMs"] ?? params["emittedAtMs"],
            fallback: now
        )
        let sessionHash = CodexActivityPrivacy.hashIdentifier(threadID)

        switch method {
        case "turn/started":
            guard let turnID = turnID(from: params) else { return nil }
            return CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: sessionHash,
                turnHash: CodexActivityPrivacy.hashIdentifier(turnID),
                source: .appServer,
                occurredAt: occurredAt
            )

        case "turn/plan/updated":
            guard let turnID = params["turnId"] as? String,
                  !turnID.isEmpty,
                  let plan = params["plan"] as? [Any],
                  plan.count <= CodexActivityPlanProgress.maximumStepCount,
                  let progress = planProgress(from: plan)
            else {
                return nil
            }
            return CodexActivityEvent(
                event: .preToolUse,
                sessionHash: sessionHash,
                turnHash: CodexActivityPrivacy.hashIdentifier(turnID),
                toolCategory: .localTool,
                planProgress: progress,
                source: .appServer,
                planSource: .appServer,
                occurredAt: occurredAt
            )

        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let turnID = turn["id"] as? String,
                  !turnID.isEmpty,
                  let rawStatus = turn["status"] as? String,
                  let status = CodexActivityTurnCompletionStatus(
                      rawValue: rawStatus
                  )
            else {
                return nil
            }
            return CodexActivityEvent(
                event: status == .interrupted ? .interrupt : .stop,
                sessionHash: sessionHash,
                turnHash: CodexActivityPrivacy.hashIdentifier(turnID),
                source: .appServer,
                turnCompletionStatus: status,
                occurredAt: occurredAt
            )

        case "thread/status/changed":
            guard let status = params["status"] as? [String: Any],
                  status["type"] as? String == "active",
                  let flags = status["activeFlags"] as? [String]
            else {
                return nil
            }
            let waitReason: CodexActivityWaitReason
            if flags.contains("waitingOnApproval") {
                waitReason = .approval
            } else if flags.contains("waitingOnUserInput") {
                waitReason = .userInput
            } else {
                return nil
            }
            return CodexActivityEvent(
                event: .permissionRequest,
                sessionHash: sessionHash,
                source: .appServer,
                waitReason: waitReason,
                occurredAt: occurredAt
            )

        case "thread/goal/updated":
            guard let goal = params["goal"] as? [String: Any],
                  let rawStatus = goal["status"] as? String,
                  let goalStatus = CodexActivityGoalStatus(
                      rawValue: rawStatus
                  )
            else {
                return nil
            }
            let turnHash = (params["turnId"] as? String).flatMap {
                $0.isEmpty ? nil : CodexActivityPrivacy.hashIdentifier($0)
            }
            return CodexActivityEvent(
                event: .postToolUse,
                sessionHash: sessionHash,
                turnHash: turnHash,
                toolCategory: .goal,
                source: .appServer,
                goalStatus: goalStatus,
                occurredAt: occurredAt
            )

        default:
            return nil
        }
    }

    private static func turnID(
        from params: [String: Any]
    ) -> String? {
        if let turnID = params["turnId"] as? String,
           !turnID.isEmpty {
            return turnID
        }
        guard let turn = params["turn"] as? [String: Any],
              let turnID = turn["id"] as? String,
              !turnID.isEmpty
        else {
            return nil
        }
        return turnID
    }

    private static func planProgress(
        from plan: [Any]
    ) -> CodexActivityPlanProgress? {
        var completed = 0
        var inProgress = 0
        var pending = 0

        for rawStep in plan {
            guard let step = rawStep as? [String: Any],
                  let status = step["status"] as? String
            else {
                return nil
            }
            switch status {
            case "completed":
                completed += 1
            case "inProgress":
                inProgress += 1
            case "pending":
                pending += 1
            default:
                return nil
            }
        }

        return CodexActivityPlanProgress(
            completedSteps: completed,
            inProgressSteps: inProgress,
            pendingSteps: pending
        )
    }

    private static func eventDate(
        from rawValue: Any?,
        fallback: Date
    ) -> Date {
        guard let milliseconds = rawValue as? NSNumber else {
            return fallback
        }
        let value = milliseconds.doubleValue
        guard value.isFinite, value >= 0 else { return fallback }
        return Date(timeIntervalSince1970: value / 1_000)
    }

    private static func nonnegativeInteger(_ rawValue: Any?) -> Int64? {
        guard let number = rawValue as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value.isFinite,
              value >= 0,
              value <= Double(Int64.max),
              value.rounded(.towardZero) == value
        else {
            return nil
        }
        return number.int64Value
    }
}
