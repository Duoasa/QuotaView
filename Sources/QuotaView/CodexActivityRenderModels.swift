import Foundation
import QuotaViewCore

struct CodexActivityRenderState: Equatable {
    let taskIdentity: CodexActivityTaskIdentity?
    let visualState: CodexActivityVisualState
    let approximateProgressFraction: Double?
    let windowTitle: String
    let statusTitle: String
    let operation: String
    let tokenUsageTitle: String?
    let completionReceiptStatus: String?
    let completionReceiptDetail: String?
    let completionQuotaRemainingPercent: Int?
    let isConfirmationReminderActive: Bool
    let accessibilityLabel: String

    init(
        taskIdentity: CodexActivityTaskIdentity? = nil,
        visualState: CodexActivityVisualState,
        approximateProgressFraction: Double?,
        windowTitle: String,
        statusTitle: String,
        operation: String,
        tokenUsageTitle: String? = nil,
        completionReceiptStatus: String? = nil,
        completionReceiptDetail: String? = nil,
        completionQuotaRemainingPercent: Int? = nil,
        isConfirmationReminderActive: Bool = false,
        accessibilityLabel: String
    ) {
        self.taskIdentity = taskIdentity
        self.visualState = visualState
        self.approximateProgressFraction = approximateProgressFraction
        self.windowTitle = windowTitle
        self.statusTitle = statusTitle
        self.operation = operation
        self.tokenUsageTitle = tokenUsageTitle
        self.completionReceiptStatus = completionReceiptStatus
        self.completionReceiptDetail = completionReceiptDetail
        self.completionQuotaRemainingPercent =
            completionQuotaRemainingPercent
        self.isConfirmationReminderActive =
            isConfirmationReminderActive
        self.accessibilityLabel = accessibilityLabel
    }
}
