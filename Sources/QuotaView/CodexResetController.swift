import Foundation
import QuotaViewCore
import SwiftUI

@MainActor
final class CodexResetController: ObservableObject {
    enum Phase: Equatable {
        case idle, preparing, confirming(CodexResetPreparation), submitting
        case finished(CodexResetOutcome), failed(CodexResetError)
    }
    @Published private(set) var phase: Phase = .idle
    private let makeCoordinator: () -> CodexRateLimitResetCoordinator
    private let refresh: () async -> Void
    private let journalURL: URL
    private var coordinator: CodexRateLimitResetCoordinator?
    private var revision: UInt64 = 0
    var hasPendingAttempt: Bool { FileManager.default.fileExists(atPath: journalURL.path) }
    var busy: Bool { phase == .preparing || phase == .submitting }

    static var defaultJournalURL: URL {
        let folder = Bundle.main.bundleIdentifier == "com.quotaview.development073" ? "QuotaView-073-Development" : "QuotaView"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder).appendingPathComponent("pending-codex-reset.json")
    }

    init(journalURL: URL, makeCoordinator: @escaping () -> CodexRateLimitResetCoordinator,
         refresh: @escaping () async -> Void) {
        self.journalURL = journalURL
        self.makeCoordinator = makeCoordinator
        self.refresh = refresh
    }

    func prepare() async {
        guard !busy else { return }
        revision &+= 1
        let generation = revision
        phase = .preparing
        let service = makeCoordinator()
        coordinator = service
        do {
            let confirmation = try await service.prepare()
            guard generation == revision else { return }
            phase = .confirming(confirmation)
        } catch {
            guard generation == revision else { return }
            phase = .failed(error as? CodexResetError ?? .connectionFailed)
        }
    }

    func cancelConfirmation() {
        guard phase != .submitting else { return }
        revision &+= 1
        coordinator = nil
        phase = .idle
    }

    func confirm() async {
        guard case .confirming(let preparation) = phase, let coordinator else { return }
        phase = .submitting
        do { phase = .finished(try await coordinator.execute(preparation)) }
        catch { phase = .failed(error as? CodexResetError ?? .outcomeUnknown) }
        // Server truth drives all surfaces. Never synthesize 100% or decrement
        // credits locally, including after an ambiguous response.
        await refresh()
    }
}

struct IslandCodexResetControls: View {
    @ObservedObject var controller: CodexResetController
    let data: IslandResetPageData
    let copy: AppCopy
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 10) {
            if case .confirming(let preparation) = controller.phase {
                VStack(alignment: .leading, spacing: 12) {
                    Text(copy.text("确认额度重置", "Confirm quota reset"))
                        .font(AstaSans.semiBold(13)).foregroundStyle(.white)
                    Text(preparation.isRetry
                        ? copy.text("上次提交结果未确认。将核对并重试同一次操作，不会改用另一张重置卡。", "The previous result is unknown. Retry the same operation without selecting another reset credit.")
                        : copy.text("将使用 1 次重置机会，重置符合条件的 Codex 用量周期。当前可用 \(preparation.availableCount) 次，操作无法撤销。", "Use one reset credit for eligible Codex usage windows. \(preparation.availableCount) available. This cannot be undone."))
                        .font(AstaSans.regular(11)).foregroundStyle(Color(white: 0.84))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { controller.cancelConfirmation() } label: {
                            Text(copy.text("取消", "Cancel")).frame(maxWidth: .infinity).frame(height: 36)
                        }
                            .buttonStyle(IslandApprovalActionStyle(primary: false))
                        Button {
                            Task { await controller.confirm() }
                        } label: {
                            Text(preparation.isRetry ? copy.text("确认重试", "Confirm retry") : copy.text("确认使用 1 次", "Use one reset"))
                                .frame(maxWidth: .infinity).frame(height: 36)
                        }.buttonStyle(IslandApprovalActionStyle(primary: false, destructive: true, emphasized: true))
                    }.font(AstaSans.semiBold(12)).controlSize(.large)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .islandGlass(RoundedRectangle(cornerRadius: 14, style: .continuous),
                        tint: Color(white: 0.075).opacity(0.75), solidTint: Color(white: 0.075))
            } else {
                Button { Task { await controller.prepare() } } label: {
                    Text(actionTitle).font(AstaSans.semiBold(13))
                        .frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
                }.buttonStyle(IslandApprovalActionStyle(primary: false, destructive: true, emphasized: true, followsGlassAppearance: true))
                    .disabled(controller.busy || (!controller.hasPendingAttempt && (!data.canRequestReset || !isCurrent)))
                    .accessibilityHint(copy.text("先检查重置卡，再由你确认使用。", "Checks reset credits before asking you to confirm."))
            }
            Text(caption).font(AstaSans.regular(10.5)).lineSpacing(2)
                .modifier(IslandGlassForeground()).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionTitle: String {
        switch controller.phase {
        case .preparing: return copy.text("正在检查重置卡…", "Checking reset credits…")
        case .submitting: return copy.text("正在重置…", "Resetting…")
        default:
            if controller.hasPendingAttempt { return copy.text("核对上次重置", "Check previous reset") }
            return data.actionTitle(copy: copy)
        }
    }

    private var caption: String {
        switch controller.phase {
        case .finished(.reset), .finished(.alreadyRedeemed):
            return copy.text("重置已确认，额度以刷新结果为准。", "Reset confirmed. Quota follows the refreshed account data.")
        case .finished(.nothingToReset): return copy.text("当前没有符合条件的用量周期，未使用重置卡。", "No eligible usage window; no reset credit used.")
        case .finished(.noCredit): return copy.text("当前没有可用重置卡。", "No reset credits available.")
        case .failed(let error):
            switch error {
            case .signInRequired: return copy.text("请先在 Codex 登录 ChatGPT 账户。", "Sign in to a ChatGPT account in Codex first.")
            case .accountChanged: return copy.text("账户或重置卡已变化，请切回原账户后重试。", "The account or reset credit changed. Return to the original account and retry.")
            case .noCredit: return copy.text("当前没有可用重置卡。", "No reset credits available.")
            case .creditDetailsUnavailable: return copy.text("无法确认可用重置卡，请刷新或更新 Codex 后重试。", "Reset credit details are unavailable. Refresh or update Codex and retry.")
            case .confirmationExpired: return copy.text("确认已过期，请重新检查。", "Confirmation expired. Check again.")
            case .storageUnavailable: return copy.text("无法安全保存重置记录，已停止操作。", "Cannot safely save the reset record. Operation stopped.")
            case .unsupported: return copy.text("当前 Codex 不支持重置接口，请更新 Codex。", "Update Codex to use the reset interface.")
            case .outcomeUnknown: return copy.text("结果尚未确认，核对重试会复用同一次操作。", "Result unknown. Retry will reuse the same operation.")
            case .connectionFailed: return copy.text("连接失败，尚未提交重置，请稍后重试。", "Connection failed before submission. Try again later.")
            case .busy: return copy.text("正在处理上一次操作。", "The previous operation is still running.")
            }
        case .preparing: return copy.text("正在读取当前账户与可用重置卡。", "Reading the current account and reset credits.")
        case .submitting: return copy.text("正在等待 Codex 确认，请勿重复操作。", "Waiting for Codex confirmation. Please do not repeat the action.")
        default:
            if controller.hasPendingAttempt { return copy.text("存在待确认的重置结果，请先核对。", "A previous reset needs reconciliation.") }
            if !isCurrent { return copy.text("请先刷新额度数据。", "Refresh quota data first.") }
            return data.caption(copy: copy)
        }
    }
}
