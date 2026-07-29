import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences

    @Environment(\.colorScheme) private var colorScheme

    private let openSettingsAction: () -> Void
    private let contentLayoutDidChange: () -> Void
    private let confirmationPresentationDidChange: (Bool) -> Void

    @State private var route: Route = .overview
    @State private var isShowingFinalConfirmation = false

    private enum Route {
        case overview
        case resetDetails
    }

    private var copy: AppCopy { preferences.copy }

    init(
        store: CodexStatusStore,
        preferences: AppPreferences,
        openSettingsAction: @escaping () -> Void = {},
        contentLayoutDidChange: @escaping () -> Void = {},
        confirmationPresentationDidChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.preferences = preferences
        self.openSettingsAction = openSettingsAction
        self.contentLayoutDidChange = contentLayoutDidChange
        self.confirmationPresentationDidChange =
            confirmationPresentationDidChange
    }

    var body: some View {
        ZStack {
            Group {
                switch route {
                case .overview:
                    QuotaViewFigmaMenu(
                        store: store,
                        preferences: preferences,
                        copy: copy,
                        openResetAction: openResetDetails,
                        refreshAction: refresh,
                        openCodexAction: openCodex,
                        openSettingsAction: showSettings,
                        quitAction: quit
                    )
                case .resetDetails:
                    QuotaViewFigmaResetMenu(
                        store: store,
                        copy: copy,
                        returnAction: returnToOverview,
                        resetAction: presentFinalConfirmation,
                        refreshAction: refresh,
                        openCodexAction: openCodex,
                        openSettingsAction: showSettings
                    )
                }
            }

            if isShowingFinalConfirmation {
                finalConfirmationOverlay
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: route)
        .animation(
            .easeOut(duration: 0.14),
            value: isShowingFinalConfirmation
        )
        .onChange(of: route) {
            contentLayoutDidChange()
        }
        .onChange(of: isShowingFinalConfirmation) {
            confirmationPresentationDidChange(
                isShowingFinalConfirmation
            )
        }
        .onChange(of: resetEntryIsAvailable) {
            guard !resetEntryIsAvailable,
                  route == .resetDetails
            else {
                return
            }
            returnToOverview()
        }
        .onExitCommand {
            if isShowingFinalConfirmation {
                dismissFinalConfirmation()
            }
        }
    }

    private var finalConfirmationOverlay: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .fill(confirmationScrimColor)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
            )
            .onTapGesture {
                // Keep destructive confirmation explicit. The scrim absorbs
                // clicks so the underlying reset page cannot be operated.
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(
                    copy.text(
                        "确认重置额度？",
                        "Reset quota now?"
                    )
                )
                .font(AstaSans.semiBold(14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    copy.text(
                        "此操作将消耗 1 次额度重置机会，并立即重置一个符合条件的 "
                        + "Codex 使用周期。操作完成后无法撤销。当前版本仍为演示"
                        + "模式，不会调用真实重置接口，也不会消耗次数。",
                        "This action uses one reset credit to reset an "
                        + "eligible Codex usage cycle immediately. It cannot "
                        + "be undone. This version remains in demo mode and "
                        + "will not call the live reset endpoint or consume "
                        + "a credit."
                    )
                )
                .font(AstaSans.regular(11.5))
                .foregroundStyle(.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    Button(
                        role: .destructive,
                        action: completeDemoReset
                    ) {
                        Text(
                            copy.text(
                                "确认演示重置",
                                "Confirm Demo Reset"
                            )
                        )
                        .font(AstaSans.medium(11.5))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                    }
                    .quotaViewInteractiveButton()
                    .background(
                        Color.red.opacity(0.20),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
                    .keyboardShortcut(.defaultAction)

                    Button(
                        role: .cancel,
                        action: dismissFinalConfirmation
                    ) {
                        Text(copy.text("取消", "Cancel"))
                            .font(AstaSans.medium(11.5))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                    }
                    .quotaViewInteractiveButton()
                    .background(
                        confirmationCancelFill,
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 250)
            .background {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 26,
                        style: .continuous
                    )
                    .fill(.regularMaterial)

                    RoundedRectangle(
                        cornerRadius: 26,
                        style: .continuous
                    )
                    .fill(confirmationSurfaceTint)
                }
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
                .strokeBorder(
                    confirmationBorderColor,
                    lineWidth: 0.75
                )
            }
            .shadow(
                color: Color.black.opacity(0.32),
                radius: 12,
                x: 0,
                y: 6
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
    }

    private var confirmationScrimColor: Color {
        colorScheme == .light
            ? Color.black.opacity(0.32)
            : Color.black.opacity(0.52)
    }

    private var confirmationSurfaceTint: Color {
        colorScheme == .light
            ? Color.white.opacity(0.30)
            : Color.black.opacity(0.28)
    }

    private var confirmationBorderColor: Color {
        colorScheme == .light
            ? Color.black.opacity(0.18)
            : Color.white.opacity(0.26)
    }

    private var confirmationCancelFill: Color {
        colorScheme == .light
            ? Color.black.opacity(0.10)
            : Color.white.opacity(0.10)
    }

    private func openResetDetails() {
        guard resetEntryIsAvailable else { return }
        route = .resetDetails
    }

    private func returnToOverview() {
        isShowingFinalConfirmation = false
        route = .overview
    }

    private func completeDemoReset() {
        Task {
            guard await store.performDemoReset() else {
                return
            }
            isShowingFinalConfirmation = false
        }
    }

    private func dismissFinalConfirmation() {
        isShowingFinalConfirmation = false
    }

    private func presentFinalConfirmation() {
        guard resetEntryIsAvailable else {
            return
        }

        // Keep the nonactivating panel key while its content-owned modal is
        // visible so keyboard shortcuts and button focus remain reliable.
        confirmationPresentationDidChange(true)
        isShowingFinalConfirmation = true
    }

    private var resetEntryIsAvailable: Bool {
        preferences.showResetAction
            && store.hasAvailableResetCredit
    }

    private func showSettings() {
        openSettingsAction()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func refresh() {
        Task {
            await store.refresh()
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func openCodex() {
        let chatGPTURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard FileManager.default.fileExists(atPath: chatGPTURL.path) else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: chatGPTURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
