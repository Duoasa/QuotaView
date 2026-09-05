import AppKit
import Darwin
import Foundation
import Metal
import SwiftUI
import XCTest
@testable import QuotaView
@testable import QuotaViewActivityHookSupport
@testable import QuotaViewCore

private extension NSView {
    func firstDescendant<ViewType: NSView>(
        ofType type: ViewType.Type
    ) -> ViewType? {
        if let match = self as? ViewType {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}

final class AppBehaviorTests: XCTestCase {
    @MainActor
    func testNativeSettingsRowPinsVisibleSegmentedControlToTrailingInset() {
        let row = NativeSettingsRow(
            title: "Island Style",
            subtitle: "Switch between island styles."
        ) {
            NativeSettingsSegmentedPicker(
                "Island Style",
                selection: .constant(0)
            ) {
                Text("AI Orb").tag(0)
                Text("Progress Bar").tag(1)
            }
        }
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: 600,
            height: 80
        )
        hostingView.layoutSubtreeIfNeeded()

        guard let segmentedControl = hostingView.firstDescendant(
            ofType: NSSegmentedControl.self
        ) else {
            return XCTFail("Expected a native segmented control")
        }
        let controlFrame = hostingView.convert(
            segmentedControl.bounds,
            from: segmentedControl
        )
        XCTAssertEqual(
            controlFrame.maxX,
            hostingView.bounds.maxX - 18,
            accuracy: 1
        )
    }

    func testAppUpdateEnvironmentAcceptsOnlyTrustedConfiguration() {
        let environment = makeUpdateEnvironment()

        XCTAssertEqual(environment.availability, .available)
    }

    func testAppUpdateEnvironmentRejectsUnsafeLaunchContexts() {
        let unsafeEnvironments: [(AppUpdateEnvironment, AppUpdateAvailability)] = [
            (
                makeUpdateEnvironment(isDebugBuild: true),
                .debugBuild
            ),
            (
                makeUpdateEnvironment(isApplicationBundle: false),
                .notApplicationBundle
            ),
            (
                makeUpdateEnvironment(bundleIdentifier: "example.copy"),
                .unexpectedBundleIdentifier
            ),
            (
                makeUpdateEnvironment(signingTeamIdentifier: nil),
                .untrustedSignature
            ),
            (
                makeUpdateEnvironment(signingTeamIdentifier: "OTHERTEAM"),
                .untrustedSignature
            ),
            (
                makeUpdateEnvironment(feedURLString: "http://example.com"),
                .invalidConfiguration
            ),
            (
                makeUpdateEnvironment(publicEDKey: ""),
                .invalidConfiguration
            )
        ]

        for (environment, expectedAvailability) in unsafeEnvironments {
            XCTAssertEqual(
                environment.availability,
                expectedAvailability
            )
        }
    }

    @MainActor
    func testUnsupportedAppUpdateControllerRemainsInactive() {
        let controller = AppUpdateController(
            environment: makeUpdateEnvironment(isDebugBuild: true)
        )

        XCTAssertEqual(controller.availability, .debugBuild)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)

        controller.checkForUpdates()
        controller.setAutomaticallyChecksForUpdates(true)

        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
    }

    @MainActor
    func testTokenActivityHoverCancellationDoesNotPresentTooltip()
        async {
        let controller = TokenActivityHoverController()
        var presentedCellID: Int?
        let cancelledPresentation = expectation(
            description: "Cancelled hover does not present"
        )
        cancelledPresentation.isInverted = true

        controller.schedule(
            cellID: 4,
            delayNanoseconds: 20_000_000
        ) {
            presentedCellID = 4
            cancelledPresentation.fulfill()
        }
        controller.cancel()
        await fulfillment(
            of: [cancelledPresentation],
            timeout: 0.1
        )

        XCTAssertNil(presentedCellID)

        let presented = expectation(
            description: "Active hover presents"
        )
        controller.schedule(
            cellID: 9,
            delayNanoseconds: 20_000_000
        ) {
            presentedCellID = 9
            presented.fulfill()
        }
        await fulfillment(of: [presented], timeout: 1.0)

        XCTAssertEqual(presentedCellID, 9)
    }

    private func makeUpdateEnvironment(
        isDebugBuild: Bool = false,
        isApplicationBundle: Bool = true,
        bundleIdentifier: String? = "com.quotaview.menubar",
        signingTeamIdentifier: String? = "BUUH229D5Q",
        feedURLString: String? =
            "https://duoasa.github.io/QuotaView/appcast.xml",
        publicEDKey: String? =
            "cu6dSd9lxpFU+KdiqaiTanblnNMWQVaj2oTxs7jf/6A="
    ) -> AppUpdateEnvironment {
        AppUpdateEnvironment(
            isDebugBuild: isDebugBuild,
            isApplicationBundle: isApplicationBundle,
            bundleIdentifier: bundleIdentifier,
            expectedBundleIdentifier: "com.quotaview.menubar",
            signingTeamIdentifier: signingTeamIdentifier,
            expectedSigningTeamIdentifier: "BUUH229D5Q",
            feedURLString: feedURLString,
            publicEDKey: publicEDKey
        )
    }

    func testMenuPanelResizeKeepsItsMenuBarAnchorStable() {
        let visibleFrame = NSRect(
            x: 0,
            y: 0,
            width: 1_440,
            height: 875
        )
        let compact = MenuBarPanelGeometry.anchoredFrame(
            size: NSSize(width: 310, height: 500),
            centerX: 1_250,
            visibleFrame: visibleFrame,
            screenEdgeInset: 8,
            menuBarGap: 6
        )
        let expanded = MenuBarPanelGeometry.anchoredFrame(
            size: NSSize(width: 310, height: 620),
            centerX: 1_250,
            visibleFrame: visibleFrame,
            screenEdgeInset: 8,
            menuBarGap: 6
        )

        XCTAssertEqual(compact.maxY, expanded.maxY)
        XCTAssertEqual(compact.maxY, visibleFrame.maxY - 6)
        XCTAssertEqual(compact.minX, expanded.minX)
    }

    func testCodexActivityProductionInactivityTiming() {
        XCTAssertEqual(CodexActivityStore.compactDelay, 20)
        XCTAssertEqual(
            CodexActivityStore.confirmationReminderDelay,
            10
        )
        XCTAssertEqual(
            CodexActivityStore.settledEventReplayAgeThreshold,
            20
        )
        XCTAssertEqual(
            CodexActivityStore.compactDelay
                + CodexActivityStore.hiddenDelayAfterCompact,
            120
        )
    }

    @MainActor
    func testConfirmationReminderActivatesOnlyAfterSustainedWait()
        async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            confirmationReminderDelay: 0.01
        )
        store.receive(
            CodexActivityEvent(
                event: .permissionRequest,
                sessionHash: "session",
                turnHash: "turn",
                waitReason: .approval
            )
        )
        XCTAssertFalse(store.isConfirmationReminderActive)

        for _ in 0..<100
        where !store.isConfirmationReminderActive {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(store.isConfirmationReminderActive)

        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                turnHash: "turn"
            )
        )
        XCTAssertFalse(store.isConfirmationReminderActive)
        await store.stop()
    }

    @MainActor
    func testCodexActivityUpdatedTimingAppliesToPendingCompletion() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 1,
            hiddenDelayAfterCompact: 1
        )
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session", occurredAt: Date().addingTimeInterval(-0.01)))
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session"
            )
        )
        store.updateInactivityDelays(
            compactDelay: 0.01,
            hiddenDelayAfterCompact: 0.01
        )

        for _ in 0..<100 where store.presentation != .hidden {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .hidden)
        await store.stop()
    }

    @MainActor
    func testRippleGlowProductionContractAndRendererResource() throws {
        XCTAssertEqual(
            CodexActivityRippleGlowContract.uniformFloatCount,
            128
        )
        XCTAssertEqual(
            CodexActivityRippleGlowContract.sphereRadius,
            0.535,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityRippleGlowContract.contourDeformation,
            0
        )
        XCTAssertEqual(
            CodexActivityRippleGlowContract.approvedSpeedMultiplier,
            1.5
        )

        let view = ActivityRippleGlowMetalView(
            frame: NSRect(x: 0, y: 0, width: 64, height: 64),
            initialState: .thinking
        )
        XCTAssertTrue(view.isRendererAvailable)
    }

    @MainActor
    func testStateSmokeProductionContractAndMetalPipeline() {
        let profiles = CodexActivityVisualState.allCases.map {
            CodexActivityStateSmokeProfile.profile(for: $0)
        }
        XCTAssertEqual(profiles.count, 9)
        XCTAssertEqual(
            CodexActivityStateSmokeProfile
                .profile(for: .disconnectedCodex)
                .motionFrequency,
            0,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(
            CodexActivityStateSmokeProfile
                .profile(for: .working)
                .motionFrequency,
            CodexActivityStateSmokeProfile
                .profile(for: .standby)
                .motionFrequency
        )
        XCTAssertGreaterThan(
            CodexActivityStateSmokeProfile
                .profile(for: .error)
                .turbulence,
            CodexActivityStateSmokeProfile
                .profile(for: .working)
                .turbulence
        )
        XCTAssertGreaterThan(
            CodexActivityStateSmokeProfile
                .profile(for: .working)
                .diffusion,
            CodexActivityStateSmokeProfile
                .profile(for: .standby)
                .diffusion
        )
        XCTAssertLessThan(
            CodexActivityStateSmokeProfile
                .profile(for: .compactingContext)
                .diffusionSpeed,
            CodexActivityStateSmokeProfile
                .profile(for: .working)
                .diffusionSpeed
        )
        XCTAssertLessThan(
            CodexActivityStateSmokeProfile
                .profile(for: .compactingContext)
                .diffusion,
            CodexActivityStateSmokeProfile
                .profile(for: .working)
                .diffusion
        )
        XCTAssertGreaterThan(
            CodexActivityStateSmokeProfile
                .profile(for: .working)
                .diffusionSpeedVariation,
            0
        )
        XCTAssertGreaterThan(
            CodexActivityStateSmokeProfile
                .profile(for: .error)
                .diffusionSpeedVariation,
            CodexActivityStateSmokeProfile
                .profile(for: .standby)
                .diffusionSpeedVariation
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.minimumProgressFrontPosition,
            0,
            accuracy: 0.0001
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "clamp(u.frontPosition, 0.0, 0.95)"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float terminalDiffusion"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float broadPlumeNoise"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float finePlumeNoise"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float diffusionSpeedPhase"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "u.diffusionSpeedVariation"
            )
        )
        XCTAssertFalse(
            activityStateSmokeShaderSource.contains(
                "convergenceDirection"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "u.completionFillProgress"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "u.completionEffectHighlight"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "if (u.effectStyle > 0.5)"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "u.completionDarkening"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "u.completionSmokeOpacity"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "normalHorizontalOpacity"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "uv.x / opacityFront"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "u.opacityStopPositions"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "u.opacityStopOpacities"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "activityProgressDiamondDensity"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "activityProgressDropDensity"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "activityProgressSloshDensity"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float dropletCellSize = 2.35;"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "frontDensity * 0.88"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "effectTime * 0.68"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float twinkleRate = mix("
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float quantumNoiseOpacityBoost = 1.10;"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "+ twinkleWave * 0.62"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "+ pow(twinkleWave, 5.0) * 0.16"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "* quantumNoiseOpacityBoost"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float completionHighlightDensity = pow(density, 3.0);"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "completionHighlightDensity = pow(density, 1.5);"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "* completionHighlightDensity"
            )
        )
        XCTAssertFalse(
            activityStateSmokeShaderSource.contains(
                "time * (0.52 + turbulence * 0.46)"
            )
        )
        XCTAssertFalse(
            activityStateSmokeShaderSource.contains(
                "float rows = 5.5;"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains(
                "float body = fill * (0.50 + caustic * 0.38);"
            )
        )
        XCTAssertTrue(
            activityStateSmokeShaderSource.contains("u.effectStyle")
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.previewProgressFraction,
            0.60,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.horizontalOpacity(
                at: 0,
                frontPosition: 0.60,
                completionActive: false
            ),
            0.50,
            accuracy: 0.0001
        )
        let workingProfile = CodexActivityStateSmokeProfile.profile(
            for: .working
        )
        let compactingProfile = CodexActivityStateSmokeProfile.profile(
            for: .compactingContext
        )
        XCTAssertEqual(
            compactingProfile.opacityCurve,
            .normal
        )
        XCTAssertEqual(
            compactingProfile.opacityCurve.opacity(at: 0),
            CodexActivityStateSmokeContract.normalLeftmostOpacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            workingProfile.deepColor,
            SIMD4<Float>(0.14, 0.29, 0.34, 1)
        )
        XCTAssertEqual(
            workingProfile.midColor,
            SIMD4<Float>(0.20, 0.40, 0.46, 1)
        )
        XCTAssertEqual(
            workingProfile.highlightColor,
            SIMD4<Float>(0.28, 0.48, 0.54, 1)
        )
        XCTAssertEqual(
            compactingProfile.deepColor,
            SIMD4<Float>(0.16, 0.18, 0.20, 1)
        )
        XCTAssertEqual(
            compactingProfile.midColor,
            SIMD4<Float>(0.22, 0.24, 0.26, 1)
        )
        XCTAssertEqual(
            compactingProfile.highlightColor,
            SIMD4<Float>(0.28, 0.30, 0.32, 1)
        )
        let quantumNoiseCompactingProfile =
            CodexActivityStateSmokeProfile.profile(
                for: .compactingContext,
                effect: .dropField
            )
        XCTAssertEqual(
            quantumNoiseCompactingProfile.deepColor,
            SIMD4<Float>(0.50, 0.53, 0.57, 1)
        )
        XCTAssertEqual(
            quantumNoiseCompactingProfile.midColor,
            SIMD4<Float>(0.68, 0.72, 0.77, 1)
        )
        XCTAssertEqual(
            quantumNoiseCompactingProfile.highlightColor,
            SIMD4<Float>(0.88, 0.92, 0.98, 1)
        )
        XCTAssertEqual(
            quantumNoiseCompactingProfile.fieldSpeed,
            compactingProfile.fieldSpeed,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            quantumNoiseCompactingProfile.turbulence,
            compactingProfile.turbulence,
            accuracy: 0.0001
        )
        let visualStates: [CodexActivityVisualState] = [
            .disconnectedCodex,
            .standby,
            .thinking,
            .working,
            .compactingContext,
            .awaitingConfirmation,
            .completed,
            .error,
            .unavailable
        ]
        for state in visualStates {
            let stateSmokeReference =
                CodexActivityStateSmokeProfile.profile(for: state)
            for effect in
                AppPreferences.CodexActivityProgressEffect.allCases
            {
                if state == .compactingContext,
                   effect == .dropField
                {
                    continue
                }
                XCTAssertEqual(
                    CodexActivityStateSmokeProfile.profile(
                        for: state,
                        effect: effect
                    ),
                    stateSmokeReference,
                    "\(effect.rawValue) must use the State Smoke \(state) profile"
                )
            }
        }
        XCTAssertEqual(
            CodexActivityStateSmokeContract.horizontalOpacity(
                at: 0.30,
                frontPosition: 0.60,
                completionActive: false
            ),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.horizontalOpacity(
                at: 0.60,
                frontPosition: 0.60,
                completionActive: false
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.horizontalOpacity(
                at: 0.90,
                frontPosition: 0.60,
                completionActive: false
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.horizontalOpacity(
                at: 0.20,
                frontPosition: 0.40,
                completionActive: false
            ),
            CodexActivityStateSmokeContract.horizontalOpacity(
                at: 0.40,
                frontPosition: 0.80,
                completionActive: false
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.horizontalOpacity(
                at: 0.90,
                frontPosition: 0.60,
                completionActive: true
            ),
            1,
            accuracy: 0.0001
        )

        guard let device = MTLCreateSystemDefaultDevice() else {
            return XCTFail("Metal is unavailable")
        }
        do {
            _ = try device.makeLibrary(
                source: activityStateSmokeShaderSource,
                options: MTLCompileOptions()
            )
        } catch {
            XCTFail("State Smoke shader failed: \(error)")
        }

        let view = ActivityStateSmokeMetalView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 50)
        )
        XCTAssertTrue(view.isRendererAvailable)
    }

    func testCodexActivityConnectionRequiresRealPromptSubmission() {
        var evidence = CodexActivityConnectionEvidence(
            observedInstallationID: nil,
            connectedInstallationID: nil
        )

        evidence.record(
            event: .sessionStart,
            installationID: "installation"
        )
        XCTAssertEqual(
            evidence.observedInstallationID,
            "installation"
        )
        XCTAssertNil(evidence.connectedInstallationID)
        XCTAssertEqual(
            evidence.status(for: "installation"),
            .awaitingFirstEvent
        )

        evidence.record(
            event: .preToolUse,
            installationID: "installation"
        )
        XCTAssertNil(evidence.connectedInstallationID)

        evidence.record(
            event: .userPromptSubmit,
            installationID: "installation"
        )
        XCTAssertEqual(
            evidence.connectedInstallationID,
            "installation"
        )
        XCTAssertEqual(
            evidence.status(for: "installation"),
            .connected
        )
        XCTAssertEqual(
            evidence.status(for: "different-installation"),
            .awaitingTrust
        )
    }

    func testCodexActivityRestartRequirementRejectsSetupCLIEvents()
    {
        let requirement = CodexActivityRestartRequirement(
            baselineProcessIdentifier: 140
        )

        XCTAssertFalse(
            requirement.isSatisfied(currentProcessIdentifier: nil)
        )
        XCTAssertFalse(
            requirement.isSatisfied(currentProcessIdentifier: 140)
        )
        XCTAssertTrue(
            requirement.isSatisfied(currentProcessIdentifier: 141)
        )

        let noRunningCodexRequirement =
            CodexActivityRestartRequirement(
                baselineProcessIdentifier: 0
            )
        XCTAssertTrue(
            noRunningCodexRequirement.isSatisfied(
                currentProcessIdentifier: 141
            )
        )
    }

    func testCodexActivitySetupSeparatesTrustRestartAndFirstEvent()
    {
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .awaitingTrust,
                reviewConfirmed: false,
                requiresRestart: true
            ),
            .awaitingTrust
        )
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .awaitingTrust,
                reviewConfirmed: true,
                requiresRestart: true
            ),
            .installedNeedsRestart
        )
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .awaitingTrust,
                reviewConfirmed: true,
                requiresRestart: false
            ),
            .awaitingFirstEvent
        )
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .connected,
                reviewConfirmed: true,
                requiresRestart: false
            ),
            .connected
        )
    }

    func testCodexSecurityReviewLauncherPreparesPrivateCommand()
        throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewSecurityReviewTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let codexURL = rootURL.appendingPathComponent(
            "Codex CLI With Spaces"
        )
        try Data(
            """
            #!/bin/bash
            sleep 2.5
            if IFS= read -r -t 0 early_command; then
                exit 17
            fi
            printf '› '
            for step in 1 2 3 4 5; do
                printf 'Checking startup list %s\\n' "$step"
                sleep 0.2
            done
            if IFS= read -r -t 0 early_command; then
                exit 18
            fi
            IFS= read -r command
            test "$command" = "/hooks"
            printf '11 hooks need review before they can run.\\n'
            printf 'Press t to trust all; enter to review hooks; esc to close\\n'
            IFS= read -r -n 1 trust_key
            test "$trust_key" = "t" -o "$trust_key" = "T"
            printf 'Press enter to view hooks; esc to close\\n'
            sleep 2
            """.utf8
        ).write(to: codexURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: codexURL.path
        )

        let launcher = CodexSecurityReviewLauncher(
            codexExecutablePath: codexURL.path,
            launcherDirectoryURL: rootURL.appendingPathComponent(
                "Launchers",
                isDirectory: true
            )
        )
        let launcherURL = try launcher.prepareLauncher()
        let expectURL = launcherURL.deletingLastPathComponent()
            .appendingPathComponent("QuotaViewHookReview.exp")
        let launcherContents = try String(
            contentsOf: launcherURL,
            encoding: .utf8
        )
        let expectContents = try String(
            contentsOf: expectURL,
            encoding: .utf8
        )
        let launcherPermissions = try XCTUnwrap(
            try fileManager.attributesOfItem(
                atPath: launcherURL.path
            )[.posixPermissions] as? NSNumber
        )
        let expectPermissions = try XCTUnwrap(
            try fileManager.attributesOfItem(
                atPath: expectURL.path
            )[.posixPermissions] as? NSNumber
        )

        XCTAssertTrue(launcherContents.contains("/usr/bin/expect"))
        XCTAssertTrue(launcherContents.contains(codexURL.path))
        XCTAssertTrue(expectContents.contains(#"send -- "/hooks\r""#))
        XCTAssertTrue(expectContents.contains(#"-re {›}"#))
        XCTAssertTrue(
            expectContents.contains(
                #"set quiet_deadline [expr {[clock milliseconds] + 3000}]"#
            )
        )
        XCTAssertTrue(
            expectContents.contains(
                #"-re {Press t to trust all}"#
            )
        )
        XCTAssertFalse(expectContents.contains("after 1800"))
        XCTAssertEqual(launcherPermissions.intValue & 0o777, 0o700)
        XCTAssertEqual(expectPermissions.intValue & 0o777, 0o700)

        let process = Process()
        let standardInput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
        process.arguments = [
            expectURL.path,
            codexURL.path,
            launcher.reviewCompletionURL.path
        ]
        process.standardInput = standardInput
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        standardInput.fileHandleForWriting.write(Data("t".utf8))
        try standardInput.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            "The launcher must enter /hooks through Codex's own PTY."
        )
        XCTAssertEqual(
            try String(
                contentsOf: launcher.reviewCompletionURL,
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            "confirmed"
        )
        let completionPermissions = try XCTUnwrap(
            try fileManager.attributesOfItem(
                atPath: launcher.reviewCompletionURL.path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(
            completionPermissions.intValue & 0o777,
            0o600
        )
    }

    @MainActor
    func testCodexActivityCompletesThenCompactsAndHides() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.02,
            hiddenDelayAfterCompact: 0.20
        )
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session", occurredAt: Date().addingTimeInterval(-0.01)))
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session"
            )
        )
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .completed)

        for _ in 0..<100 where store.presentation != .compact {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .compact)

        for _ in 0..<100 where store.presentation != .hidden {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .hidden)
        await store.stop()
    }

    @MainActor
    func testNewCodexActivityCancelsPendingCompaction() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.02,
            hiddenDelayAfterCompact: 0.02
        )
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session", occurredAt: Date().addingTimeInterval(-0.01)))
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                occurredAt: Date()
            )
        )
        try? await Task.sleep(nanoseconds: 8_000_000)
        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn-2",
                occurredAt: Date()
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn-2",
                toolCategory: .fileEdit,
                occurredAt: Date()
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.snapshot?.operationKey, .editingFiles)
        await store.stop()
    }

    @MainActor
    func testLiveSettledToolEventStaysVisibleWhenStopIsMissing() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            settledEventReplayAgeThreshold: 0.02
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                occurredAt: Date()
            )
        )
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.operationKey, .reviewingToolResult)

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .thinking)
        await store.stop()
    }

    @MainActor
    func testNewActivityContinuesWithoutSettledVisibilityGap() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            settledEventReplayAgeThreshold: 0.02
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                occurredAt: Date()
            )
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.presentation, .expanded)
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                toolCategory: .fileEdit,
                occurredAt: Date()
            )
        )

        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.snapshot?.operationKey, .editingFiles)
        await store.stop()
    }

    @MainActor
    func testReplayedOldSettledEventDoesNotReopenIsland() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            settledEventReplayAgeThreshold: 0.20
        )
        store.receive(
            CodexActivityDelivery(
                source: .startupReplay,
                activity: CodexActivityEvent(
                    event: .postToolUse,
                    sessionHash: "session",
                    occurredAt: Date().addingTimeInterval(-1)
                )
            )
        )

        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertEqual(store.snapshot?.operationKey, .reviewingToolResult)
        await store.stop()
    }

    @MainActor
    func testDelayedLiveQueueEventIsNotMistakenForStartupReplay() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            settledEventReplayAgeThreshold: 0.20
        )
        store.receive(
            CodexActivityDelivery(
                source: .liveQueue,
                activity: CodexActivityEvent(
                    event: .postToolUse,
                    sessionHash: "session",
                    occurredAt: Date().addingTimeInterval(-1)
                )
            )
        )

        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertTrue(store.shouldPlayVisualEffects)
        await store.stop()
    }

    @MainActor
    func testIntermediateToolStepsNeverSynthesizeTurnCompletion() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 1,
            hiddenDelayAfterCompact: 1
        )
        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn"
            )
        )
        for completedStep in 0..<4 {
            store.receive(
                CodexActivityEvent(
                    event: .preToolUse,
                    sessionHash: "session",
                    turnHash: "turn",
                    toolCategory: .localTool,
                    planProgress: CodexActivityPlanProgress(
                        completedSteps: completedStep,
                        inProgressSteps: 1,
                        pendingSteps: 3 - completedStep
                    )
                )
            )
            store.receive(
                CodexActivityEvent(
                    event: .postToolUse,
                    sessionHash: "session",
                    turnHash: "turn",
                    toolCategory: .localTool
                )
            )

            try? await Task.sleep(nanoseconds: 10_000_000)
            XCTAssertEqual(store.lifecycle, .active)
            XCTAssertEqual(store.snapshot?.state, .thinking)
            XCTAssertEqual(
                store.snapshot?.operationKey,
                .reviewingToolResult
            )
            XCTAssertNotEqual(store.snapshot?.state, .completed)
            XCTAssertEqual(store.presentation, .expanded)
            XCTAssertTrue(store.shouldPlayVisualEffects)
        }

        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn"
            )
        )
        XCTAssertEqual(store.lifecycle, .completed)
        XCTAssertEqual(store.snapshot?.state, .completed)
        XCTAssertEqual(store.snapshot?.operationKey, .turnCompleted)
        await store.stop()
    }

    @MainActor
    func testDuplicateDeliveryIDIsReducedOnlyOnce() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        let prompt = CodexActivityDelivery(
            eventID: "event-1",
            source: .liveSocket,
            activity: CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session"
            )
        )
        store.receive(prompt)
        store.receive(
            CodexActivityDelivery(
                eventID: "event-1",
                source: .liveQueue,
                activity: CodexActivityEvent(
                    event: .stop,
                    sessionHash: "session"
                )
            )
        )

        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.snapshot?.state, .thinking)
        await store.stop()
    }

    @MainActor
    func testLateSettledEventCannotReopenCompletedTurn() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 1,
            hiddenDelayAfterCompact: 1
        )
        let now = Date()
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session", turnHash: "turn-1", occurredAt: now.addingTimeInterval(-0.01)))
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn-1",
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                turnHash: nil,
                occurredAt: now.addingTimeInterval(0.01)
            )
        )

        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .completed)
        XCTAssertEqual(store.snapshot?.operationKey, .turnCompleted)

        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn-2",
                occurredAt: now.addingTimeInterval(0.02)
            )
        )
        XCTAssertEqual(store.snapshot?.state, .thinking)
        XCTAssertEqual(store.snapshot?.operationKey, .analyzingRequest)
        await store.stop()
    }

    @MainActor
    func testLeadingActivityStartsNewTurnWithoutPromptAfterStop() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 1,
            hiddenDelayAfterCompact: 1
        )
        let now = Date()
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session", turnHash: "turn-1", occurredAt: now.addingTimeInterval(-0.01)))
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn-1",
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn-2",
                toolCategory: .shell,
                occurredAt: now.addingTimeInterval(0.01)
            )
        )

        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.snapshot?.operationKey, .executingShell)
        XCTAssertTrue(store.shouldPlayVisualEffects)
        await store.stop()
    }

    @MainActor
    func testLateLeadingActivityFromCompletedTurnCannotReopenIt() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 1,
            hiddenDelayAfterCompact: 1
        )
        let now = Date()
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session", turnHash: "turn-1", occurredAt: now.addingTimeInterval(-0.01)))
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn-1",
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn-1",
                toolCategory: .shell,
                occurredAt: now.addingTimeInterval(0.01)
            )
        )

        XCTAssertEqual(store.lifecycle, .completed)
        XCTAssertEqual(store.snapshot?.state, .completed)
        XCTAssertEqual(store.snapshot?.operationKey, .turnCompleted)

        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn-2",
                toolCategory: .shell,
                occurredAt: now.addingTimeInterval(0.02)
            )
        )
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.snapshot?.operationKey, .executingShell)
        await store.stop()
    }

    @MainActor
    func testSessionEndStillHidesImmediatelyAfterStop() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session"
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session"
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .sessionEnd,
                sessionHash: "session"
            )
        )

        XCTAssertEqual(store.lifecycle, .idle)
        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertFalse(store.shouldPlayVisualEffects)
        await store.stop()
    }

    @MainActor
    func testOlderActivityCannotOverwriteNewerState() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.01,
            hiddenDelayAfterCompact: 0.01
        )
        let now = Date()
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                toolCategory: .fileEdit,
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                occurredAt: now.addingTimeInterval(-1)
            )
        )

        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.presentation, .expanded)
        await store.stop()
    }

    @MainActor
    func testActivityOlderThanSessionEndCannotReopenIsland() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        let endedAt = Date()
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                occurredAt: endedAt.addingTimeInterval(-2)
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .sessionEnd,
                sessionHash: "session",
                occurredAt: endedAt
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                occurredAt: endedAt.addingTimeInterval(-1)
            )
        )

        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertEqual(store.snapshot?.occurredAt, endedAt)
        await store.stop()
    }

    func testCodexActivityHookInstallerPreservesExistingHooks() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewHookInstallerTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let hooksURL = rootURL.appendingPathComponent("hooks.json")
        let helperURL = rootURL.appendingPathComponent(
            "BundledQuotaViewActivityHook"
        )
        let installedHelperURL = rootURL
            .appendingPathComponent("Application Support")
            .appendingPathComponent("QuotaViewActivityHook")
        try fileManager.createDirectory(
            at: installedHelperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helperURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helperURL.path
        )

        let existingRoot: [String: Any] = [
            "description": "Existing hooks",
            "hooks": [
                "PostToolUse": [[
                    "matcher": "Bash",
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/bin/true"
                    ]]
                ]]
            ]
        ]
        try JSONSerialization.data(
            withJSONObject: existingRoot,
            options: [.prettyPrinted]
        ).write(to: hooksURL)

        let installer = CodexActivityHookInstaller(
            socketURL: rootURL.appendingPathComponent(
                "Activity Socket.sock"
            ),
            authenticationToken: "token'with-quote",
            hooksURL: hooksURL,
            helperURL: helperURL,
            installedHelperURL: installedHelperURL
        )
        let firstInstallation = try installer.install()
        let secondInstallation = try installer.install()
        XCTAssertTrue(firstInstallation.hookDefinitionChanged)
        XCTAssertFalse(secondInstallation.hookDefinitionChanged)
        XCTAssertTrue(try installer.isInstalled())
        XCTAssertEqual(
            try Data(contentsOf: installedHelperURL),
            try Data(contentsOf: helperURL)
        )

        var installedRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: hooksURL)
            ) as? [String: Any]
        )
        XCTAssertEqual(
            installedRoot["description"] as? String,
            "Existing hooks"
        )
        let installedHooks = try XCTUnwrap(
            installedRoot["hooks"] as? [String: Any]
        )
        for event in CodexActivityHookEvent.allCases {
            let groups = try XCTUnwrap(
                installedHooks[event.rawValue] as? [[String: Any]]
            )
            let commands = groups.flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? [])
                    .compactMap { $0["command"] as? String }
            }
            XCTAssertEqual(
                commands.filter {
                    $0.contains("QuotaViewActivityHook")
                }.count,
                1
            )
            XCTAssertTrue(
                commands.contains {
                    $0.contains(installedHelperURL.path)
                        && !$0.contains(helperURL.path)
                        && $0.contains("--installation-id")
                }
            )
        }
        let postToolGroups = try XCTUnwrap(
            installedHooks[
                CodexActivityHookEvent.postToolUse.rawValue
            ] as? [[String: Any]]
        )
        XCTAssertTrue(
            postToolGroups.flatMap {
                $0["hooks"] as? [[String: Any]] ?? []
            }.contains {
                $0["command"] as? String == "/usr/bin/true"
            }
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: hooksURL.appendingPathExtension(
                    "quotaview-backup"
                ).path
            )
        )

        try installer.uninstall()
        XCTAssertFalse(try installer.isInstalled())
        XCTAssertFalse(
            fileManager.fileExists(atPath: installedHelperURL.path)
        )
        installedRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: hooksURL)
            ) as? [String: Any]
        )
        let uninstalledHooks = try XCTUnwrap(
            installedRoot["hooks"] as? [String: Any]
        )
        XCTAssertTrue(
            uninstalledHooks.values.allSatisfy { value in
                guard let groups = value as? [[String: Any]] else {
                    return false
                }
                return groups.flatMap {
                    $0["hooks"] as? [[String: Any]] ?? []
                }.allSatisfy {
                    !(($0["command"] as? String) ?? "")
                        .contains("QuotaViewActivityHook")
                }
            }
        )
        XCTAssertTrue(
            (uninstalledHooks["PostToolUse"] as? [[String: Any]] ?? [])
                .flatMap {
                    $0["hooks"] as? [[String: Any]] ?? []
                }
                .contains {
                    $0["command"] as? String == "/usr/bin/true"
                }
        )
    }

    func testCodexEnvironmentInspectorEnablesHooksWhenNeeded()
        throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewCodexEnvironmentTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let executableURL = rootURL.appendingPathComponent("codex")
        let markerURL = rootURL.appendingPathComponent("hooks-enabled")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "codex-cli 0.test"
          exit 0
        fi
        if [ "$1" = "features" ] && [ "$2" = "list" ]; then
          if [ -f "\(markerURL.path)" ]; then
            echo "hooks stable true"
          else
            echo "hooks stable false"
          fi
          exit 0
        fi
        if [ "$1" = "features" ] && [ "$2" = "enable" ] && [ "$3" = "hooks" ]; then
          /usr/bin/touch "\(markerURL.path)"
          exit 0
        fi
        exit 1
        """
        try Data(script.utf8).write(to: executableURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executableURL.path
        )

        let inspector = CodexActivityEnvironmentInspector(
            executablePath: executableURL.path,
            timeout: 2
        )
        let result = try inspector.inspectAndEnableHooksIfNeeded()
        XCTAssertEqual(result.version, "codex-cli 0.test")
        XCTAssertTrue(result.hooksEnabled)
        XCTAssertTrue(result.didEnableHooks)
        XCTAssertTrue(
            fileManager.fileExists(atPath: markerURL.path)
        )
    }

    func testCodexActivityHookInstallerRejectsInvalidHooksShape()
        throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewInvalidHookTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let hooksURL = rootURL.appendingPathComponent("hooks.json")
        let helperURL = rootURL.appendingPathComponent(
            "QuotaViewActivityHook"
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helperURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helperURL.path
        )
        let original = Data(#"{"hooks":["invalid"]}"#.utf8)
        try original.write(to: hooksURL)

        let installer = CodexActivityHookInstaller(
            socketURL: rootURL.appendingPathComponent("activity.sock"),
            authenticationToken: "token",
            hooksURL: hooksURL,
            helperURL: helperURL
        )
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    func testCodexActivityFileBridgeAcceptsOnlyAuthenticatedEvents()
        throws
    {
        let fileManager = FileManager.default
        let queueURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewActivityQueueTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let bridge = CodexActivityFileBridge(
            queueURL: queueURL,
            authenticationToken: "expected-token",
            installationIdentifier: "expected-installation"
        )
        defer {
            bridge.stop()
            try? fileManager.removeItem(at: queueURL)
        }

        let received = expectation(
            description: "Authenticated file event received"
        )
        received.expectedFulfillmentCount = 1
        try bridge.start { delivery, completion in
            let event = delivery.activity
            XCTAssertEqual(delivery.source, .liveQueue)
            XCTAssertEqual(event.event, .preToolUse)
            XCTAssertEqual(event.sessionHash, "session-hash")
            XCTAssertEqual(event.toolCategory, .fileEdit)
            received.fulfill()
            completion(true)
        }

        let event = CodexActivityEvent(
            event: .preToolUse,
            sessionHash: "session-hash",
            toolCategory: .fileEdit,
            occurredAt: Date()
        )
        let invalidEnvelope = CodexActivityBridgeEnvelope(
            authenticationToken: "wrong-token",
            installationIdentifier: "expected-installation",
            activity: event
        )
        let staleInstallationEnvelope = CodexActivityBridgeEnvelope(
            authenticationToken: "expected-token",
            installationIdentifier: "old-installation",
            activity: event
        )
        let validEnvelope = CodexActivityBridgeEnvelope(
            authenticationToken: "expected-token",
            installationIdentifier: "expected-installation",
            eventID: "valid-event",
            activity: event
        )
        try JSONEncoder().encode(invalidEnvelope).write(
            to: queueURL.appendingPathComponent(
                "event-0-invalid.json"
            ),
            options: .atomic
        )
        try JSONEncoder().encode(staleInstallationEnvelope).write(
            to: queueURL.appendingPathComponent(
                "event-1-stale-installation.json"
            ),
            options: .atomic
        )
        try JSONEncoder().encode(validEnvelope).write(
            to: queueURL.appendingPathComponent(
                "event-2-valid.json"
            ),
            options: .atomic
        )

        wait(for: [received], timeout: 1)
    }

    func testCodexActivityFileBridgeKeepsUnacceptedStartupReplay()
        throws
    {
        let fileManager = FileManager.default
        let queueURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewActivityReplayTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: queueURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: queueURL) }

        let eventURL = queueURL.appendingPathComponent(
            "event-startup-replay.json"
        )
        let envelope = CodexActivityBridgeEnvelope(
            authenticationToken: "token",
            installationIdentifier: "installation",
            eventID: "startup-replay",
            activity: CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session"
            )
        )
        try JSONEncoder().encode(envelope).write(
            to: eventURL,
            options: .atomic
        )

        let rejected = expectation(description: "Replay rejected")
        let firstBridge = CodexActivityFileBridge(
            queueURL: queueURL,
            authenticationToken: "token",
            installationIdentifier: "installation"
        )
        try firstBridge.start { delivery, completion in
            XCTAssertEqual(delivery.source, .startupReplay)
            XCTAssertEqual(delivery.eventID, "startup-replay")
            completion(false)
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 1)
        firstBridge.stop()
        XCTAssertTrue(fileManager.fileExists(atPath: eventURL.path))

        let accepted = expectation(description: "Replay accepted")
        let secondBridge = CodexActivityFileBridge(
            queueURL: queueURL,
            authenticationToken: "token",
            installationIdentifier: "installation"
        )
        defer { secondBridge.stop() }
        try secondBridge.start { delivery, completion in
            XCTAssertEqual(delivery.source, .startupReplay)
            completion(true)
            accepted.fulfill()
        }
        wait(for: [accepted], timeout: 1)
        for _ in 0..<100
        where fileManager.fileExists(atPath: eventURL.path) {
            Thread.sleep(forTimeInterval: 0.005)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: eventURL.path))
    }

    func testCodexActivityUnixBridgeAcknowledgesAcceptedEvent()
        throws
    {
        let fileManager = FileManager.default
        let rootURL = URL(
            fileURLWithPath:
                "/tmp/qv-socket-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: rootURL) }
        let socketURL = rootURL.appendingPathComponent("activity.sock")
        let bridge = CodexActivityUnixBridge(
            socketURL: socketURL,
            authenticationToken: "token",
            installationIdentifier: "installation"
        )
        defer { bridge.stop() }

        let received = expectation(description: "Socket event accepted")
        try bridge.start { delivery, completion in
            XCTAssertEqual(delivery.source, .liveSocket)
            XCTAssertEqual(delivery.eventID, "socket-event")
            XCTAssertEqual(delivery.activity.event, .stop)
            completion(true)
            received.fulfill()
        }

        let envelope = CodexActivityBridgeEnvelope(
            authenticationToken: "token",
            installationIdentifier: "installation",
            eventID: "socket-event",
            activity: CodexActivityEvent(
                event: .stop,
                sessionHash: "session"
            )
        )
        let payload = try JSONEncoder().encode(envelope)
        let client = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(client, 0)
        defer { Darwin.close(client) }
        var receiveTimeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var address = sockaddr_un()
        let pathBytes = Array(socketURL.path.utf8CString)
        XCTAssertLessThanOrEqual(
            pathBytes.count,
            MemoryLayout.size(ofValue: address.sun_path)
        )
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) { socketAddress in
                Darwin.connect(
                    client,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        XCTAssertEqual(connectResult, 0)

        let didSend = payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return Darwin.send(client, baseAddress, buffer.count, 0)
                == buffer.count
        }
        XCTAssertTrue(didSend)

        var acknowledgementBuffer = [UInt8](repeating: 0, count: 1_024)
        let acknowledgementCount = Darwin.recv(
            client,
            &acknowledgementBuffer,
            acknowledgementBuffer.count,
            0
        )
        XCTAssertGreaterThan(acknowledgementCount, 0)
        let acknowledgementData = Data(
            acknowledgementBuffer.prefix(max(acknowledgementCount, 0))
        )
        let acknowledgement = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: acknowledgementData)
                as? [String: Any]
        )
        XCTAssertEqual(acknowledgement["eventID"] as? String, "socket-event")
        XCTAssertEqual(acknowledgement["accepted"] as? Bool, true)
        wait(for: [received], timeout: 1)
    }

    @MainActor
    func testNativePreferenceDefaults() {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.showStatusIcon)
        XCTAssertTrue(preferences.showRemainingQuota)
        XCTAssertFalse(preferences.showResetCountdown)
        XCTAssertTrue(preferences.showUsageSummary)
        XCTAssertTrue(preferences.showSparkQuota)
        XCTAssertTrue(preferences.showCreditBalance)
        XCTAssertTrue(preferences.showDailyTokens)
        XCTAssertTrue(preferences.showThirtyDayTokens)
        XCTAssertTrue(preferences.showLifetimeTokens)
        XCTAssertTrue(preferences.showTokenActivity)
        XCTAssertTrue(preferences.showEstimatedCost)
        XCTAssertEqual(preferences.tokenActivityRange, .month)
        XCTAssertTrue(preferences.showResetAction)
        XCTAssertTrue(preferences.codexActivityIslandEnabled)
        XCTAssertEqual(
            preferences.codexActivityScreenPlacement,
            .followHotspot
        )
        XCTAssertEqual(
            preferences.codexActivityProgressEffect,
            .dropField
        )
        XCTAssertEqual(preferences.codexActivityCompactDelay, 20)
        XCTAssertEqual(
            preferences.codexActivityHiddenDelayAfterCompact,
            100
        )
        XCTAssertTrue(preferences.followsSystemAppearance)
        XCTAssertTrue(preferences.followsSystemLanguage)
        XCTAssertEqual(preferences.customAppearance, .dark)
        XCTAssertEqual(preferences.customLanguage, .simplifiedChinese)
        XCTAssertEqual(preferences.glassMode, .clear)
        XCTAssertEqual(
            defaults.string(
                forKey: "preferences.appearance.glassPreset"
            ),
            "clear"
        )
        XCTAssertNil(defaults.string(
            forKey: "preferences.codexActivity.islandStyle"
        ))
        XCTAssertNil(defaults.string(
            forKey: "preferences.codexActivity.orbAnimation"
        ))
        XCTAssertNil(defaults.string(
            forKey: "preferences.codexActivity.expandedSize"
        ))
    }

    @MainActor
    func testSavedNativePreferencesAndLegacyGlassMigration() {
        let savedSuiteName = "QuotaViewTests.\(UUID().uuidString)"
        let savedDefaults = UserDefaults(suiteName: savedSuiteName)!
        defer {
            savedDefaults.removePersistentDomain(forName: savedSuiteName)
        }
        savedDefaults.set(
            false,
            forKey: "preferences.appearance.followsSystem"
        )
        savedDefaults.set(
            AppPreferences.AppearanceMode.light.rawValue,
            forKey: "preferences.appearance.custom"
        )
        savedDefaults.set(
            QuotaViewGlassMode.frosted.rawValue,
            forKey: "preferences.appearance.glassPreset"
        )
        savedDefaults.set(
            false,
            forKey: "preferences.language.followsSystem"
        )
        savedDefaults.set(
            false,
            forKey: "preferences.panel.showThirtyDayTokens"
        )
        savedDefaults.set(
            false,
            forKey: "preferences.panel.showTokenActivity"
        )
        savedDefaults.set(
            false,
            forKey: "preferences.panel.showEstimatedCost"
        )
        savedDefaults.set(
            false,
            forKey: "preferences.panel.showSparkQuota"
        )
        savedDefaults.set(
            "total",
            forKey: "preferences.panel.tokenActivityRange"
        )
        savedDefaults.set(
            AppPreferences.Language.english.rawValue,
            forKey: "preferences.language.custom"
        )
        savedDefaults.set(
            false,
            forKey: "preferences.codexActivity.islandEnabled"
        )
        savedDefaults.set(
            AppPreferences.CodexActivityIslandStyle
                .progressBar.rawValue,
            forKey: "preferences.codexActivity.islandStyle"
        )
        savedDefaults.set(
            AppPreferences.CodexActivityOrbAnimation.rippleGlow.rawValue,
            forKey: "preferences.codexActivity.orbAnimation"
        )
        savedDefaults.set(
            AppPreferences.CodexActivityProgressEffect
                .sloshFlow.rawValue,
            forKey: "preferences.codexActivity.progressEffect"
        )
        savedDefaults.set(
            AppPreferences.CodexActivityScreenPlacement.codexScreen.rawValue,
            forKey: "preferences.codexActivity.screenPlacement"
        )
        savedDefaults.set(
            "60",
            forKey: "preferences.codexActivity.expandedSize"
        )
        savedDefaults.set(
            58,
            forKey: "preferences.codexActivity.compactDelay"
        )
        savedDefaults.set(
            999,
            forKey:
                "preferences.codexActivity.hiddenDelayAfterCompact"
        )

        let savedPreferences = AppPreferences(defaults: savedDefaults)

        XCTAssertFalse(savedPreferences.followsSystemAppearance)
        XCTAssertEqual(savedPreferences.customAppearance, .light)
        XCTAssertEqual(savedPreferences.glassMode, .frosted)
        XCTAssertFalse(savedPreferences.followsSystemLanguage)
        XCTAssertEqual(savedPreferences.customLanguage, .english)
        XCTAssertFalse(savedPreferences.showThirtyDayTokens)
        XCTAssertFalse(savedPreferences.showTokenActivity)
        XCTAssertFalse(savedPreferences.showEstimatedCost)
        XCTAssertFalse(savedPreferences.showSparkQuota)
        XCTAssertEqual(savedPreferences.tokenActivityRange, .sixMonths)
        XCTAssertFalse(savedPreferences.codexActivityIslandEnabled)
        XCTAssertEqual(
            savedPreferences.codexActivityProgressEffect,
            .sloshFlow
        )
        savedPreferences.codexActivityProgressEffect = .diamondFront
        XCTAssertEqual(
            savedDefaults.string(
                forKey: "preferences.codexActivity.progressEffect"
            ),
            AppPreferences.CodexActivityProgressEffect
                .diamondFront.rawValue
        )
        XCTAssertEqual(
            savedPreferences.codexActivityScreenPlacement,
            .codexScreen
        )
        XCTAssertEqual(
            savedDefaults.string(
                forKey: "preferences.codexActivity.islandStyle"
            ),
            AppPreferences.CodexActivityIslandStyle
                .progressBar.rawValue
        )
        XCTAssertEqual(
            savedDefaults.string(
                forKey: "preferences.codexActivity.orbAnimation"
            ),
            AppPreferences.CodexActivityOrbAnimation.rippleGlow.rawValue
        )
        XCTAssertEqual(
            savedDefaults.string(
                forKey: "preferences.codexActivity.expandedSize"
            ),
            "60"
        )
        XCTAssertEqual(savedPreferences.codexActivityCompactDelay, 60)
        XCTAssertEqual(
            savedPreferences.codexActivityHiddenDelayAfterCompact,
            120
        )
        XCTAssertEqual(
            savedDefaults.string(
                forKey: "preferences.panel.tokenActivityRange"
            ),
            AppPreferences.TokenActivityRange.sixMonths.rawValue
        )

        let legacySuiteName = "QuotaViewTests.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        defer {
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        }
        legacyDefaults.set(
            "legacy-ultra-thin",
            forKey: "preferences.appearance.glassPreset"
        )
        let migratedPreferences = AppPreferences(defaults: legacyDefaults)

        XCTAssertEqual(migratedPreferences.glassMode, .clear)
        XCTAssertEqual(
            legacyDefaults.string(
                forKey: "preferences.appearance.glassPreset"
            ),
            "clear"
        )
    }

    @MainActor
    func testRemovedAIOrbPreferencesArePreservedButIgnored() {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            AppPreferences.CodexActivityIslandStyle.aiOrb.rawValue,
            forKey: "preferences.codexActivity.islandStyle"
        )
        defaults.set(
            AppPreferences.CodexActivityOrbAnimation.rippleGlow.rawValue,
            forKey: "preferences.codexActivity.orbAnimation"
        )
        defaults.set(
            "75",
            forKey: "preferences.codexActivity.expandedSize"
        )

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.codexActivityProgressEffect,
            .dropField
        )
        XCTAssertEqual(
            defaults.string(
                forKey: "preferences.codexActivity.islandStyle"
            ),
            AppPreferences.CodexActivityIslandStyle
                .aiOrb.rawValue
        )
        XCTAssertEqual(
            defaults.string(
                forKey: "preferences.codexActivity.orbAnimation"
            ),
            AppPreferences.CodexActivityOrbAnimation
                .rippleGlow.rawValue
        )
        XCTAssertEqual(
            defaults.string(
                forKey: "preferences.codexActivity.expandedSize"
            ),
            "75"
        )
        XCTAssertEqual(
            defaults.string(
                forKey: "preferences.codexActivity.progressEffect"
            ),
            AppPreferences.CodexActivityProgressEffect
                .dropField.rawValue
        )
    }

    @MainActor
    func testProgressEffectPreferenceUsesStableFourCaseContract() {
        XCTAssertEqual(
            AppPreferences.CodexActivityProgressEffect.allCases,
            [.stateSmoke, .diamondFront, .dropField, .sloshFlow]
        )
        XCTAssertEqual(
            AppPreferences.CodexActivityProgressEffect.allCases.map(
                \.shaderIndex
            ),
            [0, 1, 2, 3]
        )
        XCTAssertEqual(
            AppPreferences.CodexActivityProgressEffect.dropField.rawValue,
            "dropField"
        )
        XCTAssertEqual(
            AppPreferences.CodexActivityProgressEffect
                .dropField.displayName.simplifiedChinese,
            "量子噪点"
        )
        XCTAssertEqual(
            AppPreferences.CodexActivityProgressEffect
                .dropField.displayName.english,
            "Quantum Noise"
        )

        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            "unknown-effect",
            forKey: "preferences.codexActivity.progressEffect"
        )

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.codexActivityProgressEffect,
            .dropField
        )
        XCTAssertEqual(
            defaults.string(
                forKey: "preferences.codexActivity.progressEffect"
            ),
            AppPreferences.CodexActivityProgressEffect.dropField.rawValue
        )
    }

    @MainActor
    func testWidgetKeepsOptionalUsageDemandForDetailedMetrics() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            false,
            forKey: "preferences.panel.showDailyTokens"
        )
        defaults.set(
            false,
            forKey: "preferences.panel.showLifetimeTokens"
        )
        defaults.set(
            false,
            forKey: "preferences.panel.showTokenActivity"
        )
        defaults.set(
            false,
            forKey: "preferences.panel.showEstimatedCost"
        )
        let preferences = AppPreferences(defaults: defaults)
        let recorder = FetchRequestRecorder()
        let provider = AppStubProvider { request in
            await recorder.record(request)
            return Self.makeFetchResult(resetCredits: nil)
        }
        let store = CodexStatusStore(
            provider: provider,
            preferences: preferences,
            diagnostics: defaults,
            widgetSnapshotWriter: Self.disabledWidgetWriter()
        )

        await store.refresh()
        let request = await recorder.lastRequest

        XCTAssertNotNil(request)
        XCTAssertTrue(
            request?.capabilities.contains(.currentUsage) ?? false
        )
        XCTAssertTrue(
            request?.capabilities.contains(.historicalUsage) ?? false
        )
        XCTAssertTrue(
            request?.capabilities.contains(.rateWindows) ?? false
        )
        XCTAssertTrue(
            request?.capabilities.contains(.balances) ?? false
        )
        await store.stop()
    }

    @MainActor
    func testDemoResetUsesSimulationBoundary() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let provider = AppStubProvider { _ in
            Self.makeFetchResult(resetCredits: 2)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults,
            widgetSnapshotWriter: Self.disabledWidgetWriter()
        )

        await store.refresh()

        XCTAssertTrue(store.hasAvailableResetCredit)
        XCTAssertEqual(store.operationAvailability, .demoOnly)
        let didSimulate = await store.performDemoReset()
        XCTAssertTrue(didSimulate)
        await store.stop()
    }

    @MainActor
    func testMissingOptionalValuesRemainUnavailable() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let provider = AppStubProvider { _ in
            Self.makeFetchResult(resetCredits: nil)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults,
            widgetSnapshotWriter: Self.disabledWidgetWriter()
        )

        await store.refresh()

        XCTAssertNil(store.snapshot?.availableResetCredits)
        XCTAssertNil(store.snapshot?.creditBalance)
        XCTAssertNil(store.snapshot?.recentDailyTokens)
        XCTAssertNil(store.snapshot?.lifetimeTokens)
        XCTAssertNil(store.snapshot?.sparkQuota)
        XCTAssertFalse(store.hasAvailableResetCredit)
        await store.stop()
    }

    func testCodexActivityScreenLocatorUsesLargestVisibleWindow() {
        let displays = [
            CodexActivityScreenLocator.DisplayGeometry(
                id: 1,
                bounds: CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
            ),
            CodexActivityScreenLocator.DisplayGeometry(
                id: 2,
                bounds: CGRect(
                    x: 1_920,
                    y: 0,
                    width: 2_560,
                    height: 1_440
                )
            )
        ]

        let displayID = CodexActivityScreenLocator.bestDisplayID(
            windowBounds: [
                CGRect(x: 200, y: 100, width: 400, height: 300),
                CGRect(x: 2_100, y: 120, width: 1_600, height: 1_000)
            ],
            displays: displays
        )

        XCTAssertEqual(displayID, 2)
    }

    func testCodexActivityIslandUsesOnlyProgressBarGeometry() {
        let expanded = CodexActivityIslandGeometry.panelSize(
            presentation: .expanded,
            state: .working
        )
        XCTAssertEqual(expanded, NSSize(width: 462, height: 128))

        let compact = CodexActivityIslandGeometry.panelSize(
            presentation: .compact,
            state: .working
        )
        XCTAssertEqual(compact.height, 112, accuracy: 0.0001)
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry.textInset,
            20
        )
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry
                .expandedSurfaceHeight,
            68
        )
        XCTAssertEqual(
            CodexActivityIslandTextGeometry
                .expandedStatusAlignment(style: .progressBar),
            .trailing
        )
        let progressCompactState = CodexActivityRenderState(
            visualState: .thinking,
            approximateProgressFraction: 0.42,
            windowTitle: "0.4.0",
            statusTitle: "思考中",
            operation: "正在分析任务",
            accessibilityLabel: "测试"
        )
        let progressCompactSize = CodexActivityIslandGeometry.panelSize(
            presentation: .compact,
            renderState: progressCompactState
        )
        let maximumCompactTextWidth =
            CodexActivityIslandProgressBarGeometry
            .maximumLocalizedCompactStatusTextWidth
        let retainedWhitespace =
            progressCompactSize.width
            - CodexActivityIslandProgressBarGeometry.effectInset * 2
            - maximumCompactTextWidth
        let originalWhitespace =
            CodexActivityIslandPresentation.compactSurfaceSize.width
            - maximumCompactTextWidth
        XCTAssertEqual(progressCompactSize.height, 112, accuracy: 0.0001)
        XCTAssertLessThan(
            progressCompactSize.width,
            CodexActivityIslandPresentation.compactSurfaceSize.width
                + CodexActivityIslandProgressBarGeometry.effectInset * 2
        )
        XCTAssertEqual(
            retainedWhitespace / originalWhitespace,
            CodexActivityIslandProgressBarGeometry
                .compactWhitespaceRetention,
            accuracy: 0.0001
        )
        for statusTitle in
            CodexActivityIslandProgressBarGeometry
            .allLocalizedStatusTitles
        {
            XCTAssertEqual(
                CodexActivityIslandProgressBarGeometry
                    .compactPanelSize(statusTitle: statusTitle),
                progressCompactSize
            )
            XCTAssertLessThanOrEqual(
                CodexActivityIslandProgressBarGeometry
                    .compactStatusTextWidth(for: statusTitle),
                CodexActivityIslandProgressBarGeometry
                    .fixedCompactSurfaceWidth
            )
        }
    }

    func testCodexActivityTurnTokenUsageCopyAndGeometry() {
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry.tokenUsageFontSize,
            CodexActivityIslandProgressBarGeometry.detailFontSize
        )
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry
                .completionStatusFontSize,
            16
        )
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry
                .completionDetailFontSize,
            11
        )
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry
                .completionQuotaValueFontSize,
            28
        )
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry
                .compactQuotaRingDiameter,
            30
        )
        let compactSurfaceBounds = NSRect(
            origin: .zero,
            size: NSSize(
                width:
                    CodexActivityIslandProgressBarGeometry
                    .fixedCompactSurfaceWidth,
                height:
                    CodexActivityIslandPresentation
                    .compactSurfaceSize.height
            )
        )
        let compactRingFrame =
            CodexActivityIslandProgressBarGeometry
            .compactQuotaRingFrame(in: compactSurfaceBounds)
        XCTAssertEqual(
            compactRingFrame.midX,
            compactSurfaceBounds.maxX
                - compactSurfaceBounds.height / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            compactRingFrame.midY,
            compactSurfaceBounds.midY,
            accuracy: 0.0001
        )
        let expandedSurfaceWidth =
            CodexActivityIslandProgressBarGeometry
            .maximumExpandedPanelWidth
            - CodexActivityIslandProgressBarGeometry.effectInset * 2
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry.textInset * 2
                + CodexActivityIslandProgressBarGeometry
                    .completionLeftColumnWidth
                + CodexActivityIslandProgressBarGeometry
                    .completionColumnGap
                + CodexActivityIslandProgressBarGeometry
                    .completionRightColumnWidth,
            expandedSurfaceWidth,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityTokenUsageFormatter.string(for: 999),
            "999"
        )
        XCTAssertEqual(
            CodexActivityTokenUsageFormatter.string(for: 12_800),
            "12.8K"
        )
        XCTAssertEqual(
            CodexActivityTokenUsageFormatter.string(for: 1_000_000),
            "1M"
        )

        let chinese = CodexActivityCopy(language: .simplifiedChinese)
        XCTAssertEqual(
            chinese.tokenUsageTitle(totalTokens: 12_800),
            "本次 12.8K tokens"
        )
        XCTAssertEqual(
            chinese.completionTokenUsageDetail(totalTokens: 12_800),
            "本次消耗 12.8K tokens"
        )
        XCTAssertEqual(
            chinese.completionQuotaAccessibilitySuffix(
                remainingPercent: 52
            ),
            "，当前额度剩余 52%"
        )
        XCTAssertTrue(
            chinese.accessibilityLabel(
                windowTitle: "Codex",
                statusTitle: "工作中",
                operation: "正在分析任务数据",
                approximateProgressFraction: 0.5,
                tokenUsageTitle: "本次 12.8K tokens"
            ).contains("本次 12.8K tokens")
        )

        let english = CodexActivityCopy(language: .english)
        XCTAssertEqual(
            english.tokenUsageTitle(totalTokens: 12_800),
            "This turn 12.8K tokens"
        )
        XCTAssertEqual(
            english.completionTokenUsageDetail(totalTokens: 12_800),
            "12.8K tokens this turn"
        )
        XCTAssertEqual(
            CodexActivityQuotaRingContract.riskBand(
                for: nil
            ),
            .unavailable
        )
        XCTAssertEqual(
            CodexActivityQuotaRingContract.riskBand(
                for: 82
            ),
            .healthy
        )
        XCTAssertEqual(
            CodexActivityQuotaRingContract.riskBand(
                for: 49
            ),
            .warning
        )
        XCTAssertEqual(
            CodexActivityQuotaRingContract.riskBand(
                for: 19
            ),
            .critical
        )
        XCTAssertTrue(
            CodexActivityTurnTokenUsagePresentationContract
                .showsCompletionReceipt(
                    visualState: .completed,
                    operationKey: .turnCompleted,
                    totalTokens: 12_800
                )
        )
        XCTAssertFalse(
            CodexActivityTurnTokenUsagePresentationContract
                .showsCompletionReceipt(
                    visualState: .error,
                    operationKey: .turnFailed,
                    totalTokens: 12_800
                )
        )
        XCTAssertFalse(
            CodexActivityTurnTokenUsagePresentationContract
                .showsCompletionReceipt(
                    visualState: .completed,
                    operationKey: .goalCompleted,
                    totalTokens: 12_800
                )
        )
    }

    func testConfirmationReminderUsesStaticWarningEdgeEmphasis() {
        XCTAssertEqual(
            CodexActivityIslandConfirmationReminderContract
                .edgeEmphasis(
                    visualState: .awaitingConfirmation,
                    reminderActive: false,
                    completionEffectAvailable: true
                ),
            .none
        )
        XCTAssertEqual(
            CodexActivityIslandConfirmationReminderContract
                .edgeEmphasis(
                    visualState: .awaitingConfirmation,
                    reminderActive: true,
                    completionEffectAvailable: false
                ),
            .confirmationReminder
        )
        XCTAssertEqual(
            CodexActivityIslandConfirmationReminderContract
                .edgeEmphasis(
                    visualState: .completed,
                    reminderActive: false,
                    completionEffectAvailable: true
                ),
            .completion
        )
        XCTAssertTrue(
            CodexActivityIslandConfirmationReminderContract
                .warningColor.isEqual(
                    CodexActivityQuotaRingContract.color(for: 49)
                )
        )
    }

    func testCodexActivityIslandHoverTransparencyContract() {
        XCTAssertEqual(
            CodexActivityIslandHoverTransparencyContract.restingAlpha,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandHoverTransparencyContract.hoveredAlpha,
            0.20,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandHoverTransparencyContract
                .transitionDuration,
            0.14,
            accuracy: 0.0001
        )

        let hoverFrame =
            CodexActivityIslandHoverTransparencyContract
            .visibleSurfaceFrame(
                panelFrame: NSRect(
                    x: 100,
                    y: 200,
                    width: 462,
                    height: 128
                ),
                panelInset: 30
            )
        XCTAssertEqual(
            hoverFrame,
            NSRect(x: 130, y: 230, width: 402, height: 68)
        )
    }

    func testStateSmokeSimulationKeepsStateSpecificMotion() {
        var simulation = CodexActivityStateSmokeSimulation()
        let profile = CodexActivityStateSmokeProfile.profile(
            for: .working
        )
        var minimumPulse: Float = 1
        var maximumPulse: Float = 0

        for _ in 0..<180 {
            simulation.step(profile: profile)
            minimumPulse = min(minimumPulse, simulation.pulse)
            maximumPulse = max(maximumPulse, simulation.pulse)
        }

        XCTAssertLessThan(minimumPulse, 0.1)
        XCTAssertGreaterThan(maximumPulse, 0.9)
        XCTAssertGreaterThan(simulation.fieldTime, 0)
    }

    func testStateSmokePlanProgressUsesOnlyStatusCounts() {
        let progress = CodexActivityPlanProgress(
            completedSteps: 2,
            inProgressSteps: 1,
            pendingSteps: 2
        )
        XCTAssertEqual(progress.totalSteps, 5)
        XCTAssertEqual(
            progress.approximateFraction ?? -1,
            0.42,
            accuracy: 0.0001
        )

        let firstOfFour = CodexActivityPlanProgress(
            completedSteps: 0,
            inProgressSteps: 1,
            pendingSteps: 3
        )
        XCTAssertEqual(
            firstOfFour.approximateFraction ?? -1,
            0.025,
            accuracy: 0.0001
        )

        let allCompleted = CodexActivityPlanProgress(
            completedSteps: 3,
            inProgressSteps: 0,
            pendingSteps: 0
        )
        XCTAssertEqual(
            allCompleted.approximateFraction,
            CodexActivityPlanProgress.maximumActiveFraction
        )
        XCTAssertNil(
            CodexActivityPlanProgress(
                completedSteps: 0,
                inProgressSteps: 0,
                pendingSteps: 0
            ).approximateFraction
        )
        XCTAssertNotNil(
            CodexActivityReducer.snapshot(
                for: CodexActivityEvent(
                    schemaVersion: 1,
                    event: .preToolUse,
                    sessionHash: "legacy-session"
                )
            )
        )
    }

    func testActivityHookParsesDirectAndExecWrappedPlans() throws {
        let direct = try XCTUnwrap(
            CodexActivityPlanInputParser.parse(
                toolName: "update_plan",
                toolInput: [
                    "explanation": "private explanation",
                    "plan": [
                        ["step": "private first step", "status": "completed"],
                        ["step": "private second step", "status": "in_progress"],
                        ["step": "private third step", "status": "pending"]
                    ]
                ]
            )
        )
        XCTAssertEqual(direct.completedSteps, 1)
        XCTAssertEqual(direct.inProgressSteps, 1)
        XCTAssertEqual(direct.pendingSteps, 1)

        let wrappedSource = #"""
        const result = await tools.update_plan({
          explanation: "不要传出这段说明（含括号、逗号与 \"引号\"）",
          plan: [
            {step: "分析（现状）", status: "completed"},
            {step: "实现：解析 exec", status: "in_progress"},
            {step: "验证，且不泄露文本", status: "pending"},
          ],
        });
        """#
        let wrapped = try XCTUnwrap(
            CodexActivityPlanInputParser.parse(
                toolName: "exec",
                toolInput: wrappedSource
            )
        )
        XCTAssertEqual(wrapped, direct)
        XCTAssertFalse(String(reflecting: wrapped).contains("不要传出"))

        XCTAssertEqual(
            CodexActivityPlanInputParser.parse(
                toolName: "functions.exec",
                toolInput: ["input": wrappedSource]
            ),
            direct
        )
    }

    func testActivityHookUsesLastValidWrappedPlanAndRejectsGuessing() {
        let source = #"""
        const ignored = "tools.update_plan({plan:[{status:'completed'}]})";
        // tools.update_plan({plan:[{status:"completed"}]});
        await tools.update_plan({plan:[
          {step:"one", status:"completed"},
          {step:"two", status:"pending"}
        ]});
        await tools.update_plan({plan:[
          {step:"one", status:"completed"},
          {step:"two", status:"in_progress"},
          {step:"three", status:"pending"}
        ]});
        await tools.update_plan({plan: dynamicallyGeneratedPlan});
        """#
        XCTAssertEqual(
            CodexActivityPlanInputParser.parse(
                toolName: "functions__exec",
                toolInput: source
            ),
            CodexActivitySanitizedPlanProgress(
                completedSteps: 1,
                inProgressSteps: 1,
                pendingSteps: 1
            )
        )
        XCTAssertNil(
            CodexActivityPlanInputParser.parse(
                toolName: "exec",
                toolInput:
                    "tools.update_plan({plan: dynamicallyGeneratedPlan})"
            )
        )
        XCTAssertNil(
            CodexActivityPlanInputParser.parse(
                toolName: "exec_command",
                toolInput: source
            )
        )
    }

    @MainActor
    func testStateSmokeStoreCarriesPlanProgressUntilTurnStops() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn-1",
                toolCategory: .localTool,
                planProgress: CodexActivityPlanProgress(
                    completedSteps: 1,
                    inProgressSteps: 1,
                    pendingSteps: 2
                )
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            0.275
        )

        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                turnHash: "turn-1",
                toolCategory: .localTool
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            0.275
        )

        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn-2"
            )
        )
        XCTAssertNil(store.snapshot?.approximateProgressFraction)

        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn-2",
                toolCategory: .localTool,
                planProgress: CodexActivityPlanProgress(
                    completedSteps: 2,
                    inProgressSteps: 0,
                    pendingSteps: 0
                )
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            CodexActivityPlanProgress.maximumActiveFraction
        )

        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn-2"
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            1
        )
        await store.stop()
    }

    @MainActor
    func testCurrentTurnTokenUsageUsesCumulativeDeltaAndFreezesAtStop()
        async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn-1",
                source: .appServer
            )
        )
        store.receive(
            CodexActivityTokenUsageUpdate(
                sessionHash: "session",
                turnHash: "turn-1",
                cumulativeTotalTokens: 10_000,
                lastReportedTotalTokens: 4_000
            )
        )
        XCTAssertEqual(store.currentTurnTokenUsage, 4_000)

        store.receive(
            CodexActivityTokenUsageUpdate(
                sessionHash: "session",
                turnHash: "turn-1",
                cumulativeTotalTokens: 16_000,
                lastReportedTotalTokens: 6_000
            )
        )
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)

        // A rate-limit-only rebroadcast can repeat the last request usage.
        // The cumulative delta must not double count it.
        store.receive(
            CodexActivityTokenUsageUpdate(
                sessionHash: "session",
                turnHash: "turn-1",
                cumulativeTotalTokens: 16_000,
                lastReportedTotalTokens: 6_000
            )
        )
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)

        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn-1",
                source: .appServer,
                turnCompletionStatus: .completed
            )
        )
        XCTAssertEqual(store.lifecycle, .completed)
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        await store.stop()
    }

    @MainActor
    func testNewTurnTokenUsageStartsFromPreviousThreadTotal() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn-1",
                source: .appServer
            )
        )
        store.receive(
            CodexActivityTokenUsageUpdate(
                sessionHash: "session",
                turnHash: "turn-1",
                cumulativeTotalTokens: 16_000,
                lastReportedTotalTokens: 6_000
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn-1",
                source: .appServer,
                turnCompletionStatus: .completed
            )
        )

        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn-2",
                source: .appServer
            )
        )
        XCTAssertNil(store.currentTurnTokenUsage)
        store.receive(
            CodexActivityTokenUsageUpdate(
                sessionHash: "session",
                turnHash: "turn-2",
                cumulativeTotalTokens: 20_500,
                lastReportedTotalTokens: 4_500
            )
        )
        XCTAssertEqual(store.currentTurnTokenUsage, 4_500)
        await store.stop()
    }

    @MainActor
    func testLocalPlanWinsAppServerAndLegacyWithoutMovingBackward()
        async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn",
                planProgress: CodexActivityPlanProgress(
                    completedSteps: 2,
                    inProgressSteps: 1,
                    pendingSteps: 1
                ),
                source: .localRollout,
                planSource: .localRollout
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            0.525
        )

        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn",
                planProgress: CodexActivityPlanProgress(
                    completedSteps: 3,
                    inProgressSteps: 1,
                    pendingSteps: 0
                ),
                source: .hook,
                planSource: .legacyTool
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            0.525
        )

        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn",
                planProgress: CodexActivityPlanProgress(
                    completedSteps: 1,
                    inProgressSteps: 1,
                    pendingSteps: 2
                ),
                source: .appServer,
                planSource: .appServer
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            0.525
        )

        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                turnHash: "turn",
                planProgress: CodexActivityPlanProgress(
                    completedSteps: 0,
                    inProgressSteps: 0,
                    pendingSteps: 0
                ),
                source: .appServer,
                planSource: .appServer
            )
        )
        XCTAssertEqual(
            store.snapshot?.approximateProgressFraction,
            0.525
        )
        await store.stop()
    }

    @MainActor
    func testInterruptedAndFailedTurnsNeverShowCompletion() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session", turnHash: "turn", source: .appServer, occurredAt: Date().addingTimeInterval(-0.01)))
        store.receive(
            CodexActivityEvent(
                event: .interrupt,
                sessionHash: "session",
                turnHash: "turn",
                source: .appServer,
                turnCompletionStatus: .interrupted
            )
        )
        XCTAssertEqual(store.lifecycle, .idle)
        XCTAssertEqual(store.snapshot?.state, .standby)
        XCTAssertEqual(store.snapshot?.operationKey, .turnInterrupted)
        XCTAssertNil(store.snapshot?.approximateProgressFraction)

        store.receive(
            CodexActivityEvent(
                event: .userPromptSubmit,
                sessionHash: "session",
                turnHash: "turn-2"
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn-2",
                source: .appServer,
                turnCompletionStatus: .failed
            )
        )
        XCTAssertEqual(store.lifecycle, .idle)
        XCTAssertEqual(store.snapshot?.state, .error)
        XCTAssertEqual(store.snapshot?.operationKey, .turnFailed)
        XCTAssertNil(store.snapshot?.approximateProgressFraction)
        await store.stop()
    }

    @MainActor
    func testActiveGoalPreventsTurnCompletionFromFakingGoalCompletion()
        async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                turnHash: "turn",
                toolCategory: .goal,
                source: .appServer,
                goalStatus: .active
            )
        )
        XCTAssertNil(store.snapshot?.approximateProgressFraction)

        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                turnHash: "turn",
                source: .appServer,
                turnCompletionStatus: .completed
            )
        )
        XCTAssertEqual(store.lifecycle, .idle)
        XCTAssertEqual(store.snapshot?.state, .standby)
        XCTAssertEqual(store.snapshot?.operationKey, .followingGoal)
        XCTAssertNil(store.snapshot?.approximateProgressFraction)
        await store.stop()
    }

    func testStateSmokeProgressProjectionTracksApproximateProgress() {
        var projection = CodexActivityStateSmokeProgressProjection()
        XCTAssertEqual(
            projection.resolve(
                approximateProgressFraction: nil,
                elapsed: 1.0 / 60.0,
                reduceMotion: false
            ),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeProgressProjection
                .targetFrontPosition(for: 0.42) ?? -1,
            0.42,
            accuracy: 0.0001
        )

        var projected = projection.resolve(
            approximateProgressFraction: 0.60,
            elapsed: 1.0 / 60.0,
            reduceMotion: false
        )
        XCTAssertEqual(projected, 0.0340, accuracy: 0.0001)
        XCTAssertGreaterThan(projected, 0)
        XCTAssertLessThan(projected, 0.60)
        for _ in 0..<180 {
            projected = projection.resolve(
                approximateProgressFraction: 0.60,
                elapsed: 1.0 / 60.0,
                reduceMotion: false
            )
        }
        XCTAssertEqual(projected, 0.60, accuracy: 0.0001)
        XCTAssertEqual(
            projection.resolve(
                approximateProgressFraction: 1,
                elapsed: 0,
                reduceMotion: true
            ),
            CodexActivityStateSmokeContract
                .maximumProgressFrontPosition,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            projection.resolve(
                approximateProgressFraction: nil,
                elapsed: 1.0 / 60.0,
                reduceMotion: false
            ),
            0,
            accuracy: 0.0001
        )
        let compactRenderState = CodexActivityRenderState(
            visualState: .thinking,
            approximateProgressFraction: 0.42,
            windowTitle: "0.4.0",
            statusTitle: "思考中",
            operation: "正在分析任务",
            accessibilityLabel: "测试"
        )
        let compactPanelSize = CodexActivityIslandGeometry.panelSize(
            presentation: .expanded,
            renderState: compactRenderState
        )
        XCTAssertEqual(
            compactPanelSize.height,
            CodexActivityIslandProgressBarGeometry
                .expandedPanelHeight,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            compactPanelSize.width,
            CodexActivityIslandProgressBarGeometry
                .maximumExpandedPanelWidth,
            accuracy: 0.0001
        )

        let wideRenderState = CodexActivityRenderState(
            visualState: .compactingContext,
            approximateProgressFraction: 0.75,
            windowTitle: "Refine the compact Codex activity island",
            statusTitle: "Compacting Context",
            operation:
                "Condensing earlier messages to free context space",
            accessibilityLabel: "Test"
        )
        let widePanelSize = CodexActivityIslandGeometry.panelSize(
            presentation: .expanded,
            renderState: wideRenderState
        )
        XCTAssertEqual(widePanelSize, compactPanelSize)
        XCTAssertEqual(
            CodexActivityIslandProgressBarGeometry.columnGap,
            14,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandTextContrast.statusDotBorderWidth,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandTextContrast
                .progressTaskTitleColor.alphaComponent,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandTextContrast
                .progressTaskTitleColor.whiteComponent,
            0.88,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandTextContrast
                .progressOperationColor.alphaComponent,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandTextContrast
                .progressOperationColor.whiteComponent,
            0.76,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandTextContrast
                .operationShimmerShoulderAlpha,
            0.24,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandTextContrast
                .operationShimmerPeakAlpha,
            1,
            accuracy: 0.0001
        )
    }

    func testStateSmokeUnplannedProgressAdvancesFromZero() {
        var progress = CodexActivityStateSmokeUnplannedProgress()
        XCTAssertEqual(
            progress.resolve(
                state: .thinking,
                elapsed: 0,
                reduceMotion: false
            ) ?? -1,
            0,
            accuracy: 0.0001
        )

        for _ in 0..<120 {
            _ = progress.resolve(
                state: .thinking,
                elapsed: 1.0 / 60.0,
                reduceMotion: false
            )
        }
        XCTAssertGreaterThan(progress.fraction, 0.10)
        XCTAssertLessThan(
            progress.fraction,
            CodexActivityStateSmokeUnplannedProgress
                .maximumActiveFraction
        )
        XCTAssertEqual(
            CodexActivityStateSmokeUnplannedProgress
                .maximumActiveFraction,
            0.50,
            accuracy: 0.0001
        )

        _ = progress.resolve(
            state: .working,
            elapsed: 0,
            reduceMotion: false
        )
        XCTAssertGreaterThanOrEqual(
            progress.fraction,
            CodexActivityStateSmokeUnplannedProgress
                .workingMinimumFraction
        )
        let workingFraction = progress.fraction
        _ = progress.resolve(
            state: .thinking,
            elapsed: 0,
            reduceMotion: false
        )
        XCTAssertGreaterThanOrEqual(
            progress.fraction,
            workingFraction
        )

        _ = progress.resolve(
            state: .compactingContext,
            elapsed: 0,
            reduceMotion: false
        )
        XCTAssertGreaterThanOrEqual(
            progress.fraction,
            CodexActivityStateSmokeUnplannedProgress
                .compactionMinimumFraction
        )

        progress.reset()
        XCTAssertEqual(
            progress.resolve(
                state: .thinking,
                elapsed: 0,
                reduceMotion: true
            ) ?? -1,
            Double(
                CodexActivityStateSmokeUnplannedProgress
                    .reducedMotionThinkingFraction
            ),
            accuracy: 0.0001
        )
        XCTAssertNil(
            progress.resolve(
                state: .standby,
                elapsed: 1,
                reduceMotion: false
            )
        )

        var projection =
            CodexActivityStateSmokeProgressProjection()
        XCTAssertEqual(
            projection.resolve(
                approximateProgressFraction: 0.60,
                elapsed: 0,
                reduceMotion: true
            ),
            0.60,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            projection.resolve(
                approximateProgressFraction: 0.20,
                elapsed: 1.0 / 60.0,
                reduceMotion: false
            ),
            0.60,
            accuracy: 0.0001
        )
        projection.reset()
        XCTAssertNil(projection.displayedFrontPosition)
    }

    func testStateSmokeWaitsAtOnePercentBeforeUnplannedProgress() {
        var resolver = CodexActivityStateSmokeProgressResolver()

        for _ in 0..<15 {
            XCTAssertEqual(
                resolver.resolve(
                    state: .thinking,
                    plannedFraction: nil,
                    elapsed: 0.25,
                    reduceMotion: false
                ) ?? -1,
                CodexActivityStateSmokeProgressResolver
                    .planResolutionFraction,
                accuracy: 0.0001
            )
        }
        XCTAssertEqual(resolver.mode, .resolvingPlan)
        XCTAssertEqual(
            resolver.resolve(
                state: .thinking,
                plannedFraction: nil,
                elapsed: 0.24,
                reduceMotion: false
            ) ?? -1,
            0.01,
            accuracy: 0.0001
        )
        XCTAssertEqual(resolver.mode, .resolvingPlan)

        let firstUnplanned = resolver.resolve(
            state: .thinking,
            plannedFraction: nil,
            elapsed: 0.01,
            reduceMotion: false
        )
        XCTAssertEqual(firstUnplanned ?? -1, 0.01, accuracy: 0.0001)
        XCTAssertEqual(resolver.mode, .unplanned)

        let advancing = resolver.resolve(
            state: .thinking,
            plannedFraction: nil,
            elapsed: 0.25,
            reduceMotion: false
        )
        XCTAssertGreaterThan(advancing ?? 0, firstUnplanned ?? 0)
    }

    func testStateSmokePlanCanTakeOverEarlyOrLateWithoutResettingDisplay() {
        var resolver = CodexActivityStateSmokeProgressResolver()
        XCTAssertEqual(
            resolver.resolve(
                state: .thinking,
                plannedFraction: nil,
                elapsed: 0.25,
                reduceMotion: false
            ) ?? -1,
            0.01,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            resolver.resolve(
                state: .thinking,
                plannedFraction: 0.125,
                elapsed: 0.25,
                reduceMotion: false
            ) ?? -1,
            0.125,
            accuracy: 0.0001
        )
        XCTAssertEqual(resolver.mode, .planned)

        resolver.reset()
        for _ in 0..<17 {
            _ = resolver.resolve(
                state: .thinking,
                plannedFraction: nil,
                elapsed: 0.25,
                reduceMotion: false
            )
        }
        XCTAssertEqual(resolver.mode, .unplanned)
        XCTAssertEqual(
            resolver.resolve(
                state: .working,
                plannedFraction: 0.375,
                elapsed: 0.25,
                reduceMotion: false
            ) ?? -1,
            0.375,
            accuracy: 0.0001
        )
        XCTAssertEqual(resolver.mode, .planned)

        var projection = CodexActivityStateSmokeProgressProjection()
        XCTAssertEqual(
            projection.resolve(
                approximateProgressFraction: 0.40,
                elapsed: 0,
                reduceMotion: true
            ),
            0.40,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            projection.resolve(
                approximateProgressFraction: 0.25,
                elapsed: 0.25,
                reduceMotion: false
            ),
            0.40,
            accuracy: 0.0001
        )
    }

    func testStateSmokeStaticStatesKeepTheFieldStill() {
        for state in [
            CodexActivityVisualState.disconnectedCodex,
            .unavailable,
        ] {
            var simulation = CodexActivityStateSmokeSimulation()
            let profile = CodexActivityStateSmokeProfile.profile(
                for: state
            )
            for _ in 0..<120 {
                simulation.step(
                    profile: profile,
                    effectPlaybackEnabled: false
                )
            }
            XCTAssertEqual(
                simulation.fieldTime,
                0,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                simulation.effectTime,
                0,
                accuracy: 0.0001
            )
        }
    }

    func testQuantumNoiseClockStaysContinuousAcrossStateProfiles() {
        var simulation = CodexActivityStateSmokeSimulation()
        let working = CodexActivityStateSmokeProfile.profile(
            for: .working
        )
        let awaitingConfirmation =
            CodexActivityStateSmokeProfile.profile(
                for: .awaitingConfirmation
            )

        for _ in 0..<120 {
            simulation.step(
                profile: working,
                effectPlaybackEnabled: true
            )
        }
        let beforeStateChange = simulation.effectTime
        for _ in 0..<120 {
            simulation.step(
                profile: awaitingConfirmation,
                effectPlaybackEnabled: true
            )
        }

        XCTAssertEqual(beforeStateChange, 2, accuracy: 0.0001)
        XCTAssertEqual(simulation.effectTime, 4, accuracy: 0.0001)
        XCTAssertNotEqual(simulation.fieldTime, simulation.effectTime)

        simulation.step(
            profile: CodexActivityStateSmokeProfile.profile(
                for: .unavailable
            ),
            effectPlaybackEnabled: false
        )
        XCTAssertEqual(simulation.effectTime, 4, accuracy: 0.0001)

        simulation.resetEffectTime()
        XCTAssertEqual(simulation.effectTime, 0, accuracy: 0.0001)
    }

    func testStateSmokeCompletionTransitionFillsDarkensAndResets() {
        var transition =
            CodexActivityStateSmokeCompletionTransition()
        XCTAssertEqual(transition.snapshot, .inactive)

        transition.enter()
        let early = transition.advance(elapsed: 0.10)
        XCTAssertGreaterThan(early.fillProgress, 0)
        XCTAssertLessThan(early.fillProgress, 1)
        XCTAssertEqual(early.effectHighlight, 0, accuracy: 0.0001)
        XCTAssertEqual(early.darkening, 0, accuracy: 0.0001)
        XCTAssertEqual(early.smokeOpacity, 1, accuracy: 0.0001)

        var fading = early
        for _ in 0..<60 {
            fading = transition.advance(
                elapsed: CodexActivityStateSmokeContract.fixedStep
            )
        }
        XCTAssertEqual(fading.fillProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(
            fading.darkening,
            CodexActivityStateSmokeContract.completionFinalDarkening,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(fading.smokeOpacity, 0)
        XCTAssertLessThan(fading.smokeOpacity, 1)

        var completed = fading
        for _ in 0..<30 {
            completed = transition.advance(
                elapsed: CodexActivityStateSmokeContract.fixedStep
            )
        }
        XCTAssertEqual(completed.smokeOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(
            CodexActivityStateSmokeContract.completionGlowDelay,
            CFTimeInterval(
                CodexActivityStateSmokeContract
                    .completionSmokeFadeDelay
                + CodexActivityStateSmokeContract
                    .completionSmokeFadeDuration
            ),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract.completionGlowBreathDuration,
            1.8,
            accuracy: 0.0001
        )

        transition.reset()
        XCTAssertEqual(transition.snapshot, .inactive)
        XCTAssertFalse(transition.isActive)
    }

    func testProgressEffectsCompletionHighlightIsBriefAndSubdued() {
        var transition =
            CodexActivityStateSmokeCompletionTransition()
        transition.enter()

        _ = transition.advance(elapsed: 0.25)
        let filled = transition.advance(elapsed: 0.17)
        XCTAssertEqual(filled.fillProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(filled.effectHighlight, 0, accuracy: 0.0001)

        let highlighted = transition.advance(
            elapsed:
                CodexActivityStateSmokeContract
                    .completionEffectHighlightDuration / 2
        )
        XCTAssertEqual(highlighted.fillProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(highlighted.effectHighlight, 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(
            CodexActivityStateSmokeContract
                .completionEffectHighlightIntensity,
            0.14
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract
                .completionHighlightIntensity(for: .dropField),
            0.18,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract
                .completionHighlightIntensity(for: .diamondFront),
            0.14,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeContract
                .completionHighlightIntensity(for: .sloshFlow),
            0.14,
            accuracy: 0.0001
        )

        let settled = transition.advance(
            elapsed:
                CodexActivityStateSmokeContract
                    .completionEffectHighlightDuration / 2
        )
        XCTAssertEqual(settled.effectHighlight, 0, accuracy: 0.0001)
        XCTAssertEqual(
            CodexActivityStateSmokeCompletionSnapshot
                .reducedMotion.effectHighlight,
            0,
            accuracy: 0.0001
        )
    }

    func testStateSmokeCompletionGlowUsesInsetFourSidedSource() {
        let islandRect = NSRect(x: 10, y: 10, width: 424, height: 110)
        let sourceRect =
            CodexActivityIslandCompletionGlowGeometry.sourceRect(
                in: islandRect
            )

        XCTAssertGreaterThan(sourceRect.minX, islandRect.minX)
        XCTAssertLessThan(sourceRect.maxX, islandRect.maxX)
        XCTAssertGreaterThan(sourceRect.minY, islandRect.minY)
        XCTAssertLessThan(sourceRect.maxY, islandRect.maxY)
        XCTAssertEqual(
            sourceRect.midX,
            islandRect.midX,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            sourceRect.midY,
            islandRect.midY,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            sourceRect.minX - islandRect.minX,
            CodexActivityIslandCompletionGlowGeometry.sourceInset,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandCompletionGlowGeometry
                .sourceCornerRadius(
                    in: islandRect,
                    islandCornerRadius:
                        CodexActivityIslandProgressBarGeometry
                        .expandedCornerRadius
                ),
            CodexActivityIslandProgressBarGeometry
                .expandedCornerRadius
                - CodexActivityIslandCompletionGlowGeometry
                    .sourceInset,
            accuracy: 0.0001
        )
        XCTAssertGreaterThanOrEqual(
            CodexActivityIslandProgressBarGeometry.effectInset,
            CodexActivityIslandCompletionGlowGeometry
                .peakShadowRadius * 3
        )
        XCTAssertEqual(
            CodexActivityIslandCompletionGlowGeometry.outlineWidth,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandCompletionGlowGeometry.shadowOpacity,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityIslandCompletionPalette.gradientLocations,
            [0, 0.52, 1]
        )
        XCTAssertNotEqual(
            CodexActivityIslandCompletionPalette.violet,
            CodexActivityIslandCompletionPalette.cyan
        )
    }

    func testStateSmokeReduceMotionAndRequestedTextGeometryAreStable() {
        let snapshot =
            CodexActivityStateSmokeSimulation
            .reducedMotionSnapshot
        XCTAssertEqual(snapshot.fieldTime, 0.35, accuracy: 0.0001)
        XCTAssertEqual(
            CodexActivityStateSmokeCompletionSnapshot.reducedMotion
                .fillProgress,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeCompletionSnapshot.reducedMotion
                .darkening,
            CodexActivityStateSmokeContract.completionFinalDarkening,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CodexActivityStateSmokeCompletionSnapshot.reducedMotion
                .smokeOpacity,
            0,
            accuracy: 0.0001
        )

        let aiOrbExpandedStart = CodexActivityIslandTextGeometry.textStart(
            style: .aiOrb,
            compactStart: 54,
            expandedStart: 128,
            expansionProgress: 1
        )
        let smokeExpandedStart = CodexActivityIslandTextGeometry.textStart(
            style: .progressBar,
            compactStart: 54,
            expandedStart: 128,
            expansionProgress: 1
        )
        XCTAssertEqual(aiOrbExpandedStart, 128, accuracy: 0.0001)
        XCTAssertEqual(
            smokeExpandedStart,
            CodexActivityIslandProgressBarGeometry.textInset,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            activityIslandSurfaceCornerRadius(
                style: .progressBar,
                surfaceHeight:
                    CodexActivityIslandProgressBarGeometry
                    .expandedSurfaceHeight,
                expansionProgress: 1
            ),
            CodexActivityIslandProgressBarGeometry
                .expandedCornerRadius,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            activityIslandSurfaceCornerRadius(
                style: .progressBar,
                surfaceHeight:
                    CodexActivityIslandPresentation
                    .compactSurfaceSize.height,
                expansionProgress: 0
            ),
            CodexActivityIslandPresentation
                .compactSurfaceSize.height / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            activityIslandSurfaceCornerRadius(
                style: .aiOrb,
                surfaceHeight: 110,
                expansionProgress: 1
            ),
            34,
            accuracy: 0.0001
        )

        let smokeCompactFrame =
            CodexActivityIslandTextGeometry.compactTitleFrame(
                style: .progressBar,
                surfaceWidth: 250
            )
        XCTAssertEqual(smokeCompactFrame.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(smokeCompactFrame.width, 250, accuracy: 0.0001)
        XCTAssertEqual(smokeCompactFrame.midX, 125, accuracy: 0.0001)

        let aiOrbCompactFrame =
            CodexActivityIslandTextGeometry.compactTitleFrame(
                style: .aiOrb,
                surfaceWidth: 250
            )
        XCTAssertEqual(aiOrbCompactFrame.minX, 40, accuracy: 0.0001)
        XCTAssertEqual(aiOrbCompactFrame.width, 210, accuracy: 0.0001)
    }

    func testCodexActivityScreenLocatorUsesLargestIntersection() {
        let displays = [
            CodexActivityScreenLocator.DisplayGeometry(
                id: 1,
                bounds: CGRect(x: 0, y: 0, width: 1_000, height: 800)
            ),
            CodexActivityScreenLocator.DisplayGeometry(
                id: 2,
                bounds: CGRect(x: 1_000, y: 0, width: 1_000, height: 800)
            )
        ]

        let displayID = CodexActivityScreenLocator.bestDisplayID(
            windowBounds: [
                CGRect(x: 800, y: 100, width: 700, height: 500)
            ],
            displays: displays
        )

        XCTAssertEqual(displayID, 2)
        XCTAssertNil(
            CodexActivityScreenLocator.bestDisplayID(
                windowBounds: [],
                displays: displays
            )
        )
    }

    func testSparkQuotaProjectsFromDedicatedRateWindow() throws {
        let result = Self.makeFetchResult(
            resetCredits: nil,
            sparkUsedPercent: 37
        )
        let presentation = try XCTUnwrap(
            CurrentCodexPresentationProjector()
                .makePresentation(from: result)
        )
        let sparkQuota = try XCTUnwrap(presentation.sparkQuota)

        XCTAssertEqual(sparkQuota.usedPercent, 37)
        XCTAssertEqual(sparkQuota.remainingPercent, 63)
        XCTAssertEqual(sparkQuota.windowDurationMinutes, 10_080)
        XCTAssertEqual(
            sparkQuota.resetsAt,
            result.snapshot.capturedAt.addingTimeInterval(604_800)
        )
    }

    func testCoreQuotaWindowsProjectShortestDurationFirst() throws {
        let result = Self.makeFetchResult(
            resetCredits: nil,
            secondaryUsedPercent: 60
        )
        let presentation = try XCTUnwrap(
            CurrentCodexPresentationProjector()
                .makePresentation(from: result)
        )

        XCTAssertEqual(
            presentation.quotaWindows.map(\.id),
            [
                CodexDomainCatalog.secondaryRateWindowID,
                CodexDomainCatalog.primaryRateWindowID
            ]
        )
        XCTAssertEqual(
            presentation.quotaWindows.map(\.windowDurationMinutes),
            [300, 10_080]
        )
        XCTAssertEqual(
            presentation.quotaWindows.map(\.remainingPercent),
            [40, 75]
        )
        XCTAssertEqual(presentation.remainingPercent, 75)
        XCTAssertEqual(presentation.windowDurationMinutes, 10_080)
    }

    func testHistoricalUsageProjectsSortedTokenActivity() throws {
        let earlier = Date(timeIntervalSince1970: 1_784_160_000)
        let later = earlier.addingTimeInterval(86_400)
        let observations = [later, earlier].map { date in
            MetricObservation(
                definitionID: CodexDomainCatalog.dailyTokensID,
                entity: CodexDomainCatalog.providerEntity,
                value: .count(date == earlier ? 1_200 : 4_800),
                interval: DateInterval(
                    start: date,
                    duration: 86_400
                ),
                observedAt: date,
                receivedAt: later,
                source: .providerHistoricalBucket,
                precision: .exact
            )
        }
        let result = Self.makeFetchResult(
            resetCredits: nil,
            historicalObservations: observations
        )
        let presentation = try XCTUnwrap(
            CurrentCodexPresentationProjector()
                .makePresentation(from: result)
        )

        XCTAssertEqual(
            presentation.tokenActivity.map(\.date),
            [earlier, later]
        )
        XCTAssertEqual(
            presentation.tokenActivity.map(\.tokens),
            [1_200, 4_800]
        )
        XCTAssertEqual(presentation.recentDailyTokens, 4_800)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(
            presentation.recentDailyDate,
            formatter.string(from: later)
        )
    }

    @MainActor
    func testTokenActivityGridRestoresPlaceholdersAndCapsAtSixMonths()
    throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = try XCTUnwrap(
            DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 8,
                day: 10
            ).date
        )
        let sixMonthBoundary = try XCTUnwrap(
            calendar.date(byAdding: .month, value: -6, to: endDate)
        ).addingTimeInterval(86_400)
        let tooOld = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: sixMonthBoundary)
        )
        let earlierDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -39, to: endDate)
        )
        let recentDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -3, to: endDate)
        )
        let futureDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 1, to: endDate)
        )
        let activity = [
            DailyTokenActivity(date: tooOld, tokens: 20_000),
            DailyTokenActivity(date: sixMonthBoundary, tokens: 1_000),
            DailyTokenActivity(date: earlierDate, tokens: 9_000),
            DailyTokenActivity(date: recentDate, tokens: 2_000),
            DailyTokenActivity(date: endDate, tokens: 3_000),
            DailyTokenActivity(date: endDate, tokens: 2_000),
            DailyTokenActivity(date: futureDate, tokens: 30_000)
        ]

        for range in AppPreferences.TokenActivityRange.allCases {
            let model = TokenActivityGridModel(
                activity: activity,
                range: range,
                endingAt: endDate
            )
            let placeholderCount = model.cells
                .prefix { $0.isPlaceholder }
                .count

            XCTAssertEqual(
                model.cells.count,
                model.rowCount * TokenActivityGridMetrics.columnCount
            )
            XCTAssertEqual(
                placeholderCount,
                model.cells.count - model.dayCount
            )
            XCTAssertFalse(
                model.cells.dropFirst(placeholderCount).contains {
                    $0.isPlaceholder
                }
            )
        }

        let week = TokenActivityGridModel(
            activity: activity,
            range: .week,
            endingAt: endDate
        )
        XCTAssertEqual(week.dayCount, 7)
        XCTAssertEqual(week.rowCount, 1)
        XCTAssertEqual(week.cells.prefix { $0.isPlaceholder }.count, 9)
        XCTAssertEqual(week.cells.compactMap(\.date).last, endDate)
        XCTAssertEqual(week.maximumTokens, 5_000)
        XCTAssertEqual(TokenActivityGridMetrics.gridWidth, 237)
        XCTAssertEqual(
            TokenActivityGridMetrics.tooltipDelayNanoseconds,
            500_000_000
        )
        XCTAssertEqual(
            TokenActivityGridMetrics.sectionHeight(
                rowCount: week.rowCount
            ),
            59
        )

        let month = TokenActivityGridModel(
            activity: activity,
            range: .month,
            endingAt: endDate
        )
        XCTAssertEqual(month.dayCount, 31)
        XCTAssertEqual(month.rowCount, 2)
        XCTAssertEqual(month.cells.prefix { $0.isPlaceholder }.count, 1)
        XCTAssertEqual(
            TokenActivityGridMetrics.sectionHeight(
                rowCount: month.rowCount
            ),
            74
        )

        let sixMonths = TokenActivityGridModel(
            activity: activity,
            range: .sixMonths,
            endingAt: endDate
        )
        let expectedSixMonthDays = try XCTUnwrap(
            calendar.dateComponents(
                [.day],
                from: sixMonthBoundary,
                to: endDate
            ).day
        ) + 1
        XCTAssertEqual(sixMonths.dayCount, expectedSixMonthDays)
        XCTAssertEqual(
            sixMonths.rowCount,
            (expectedSixMonthDays + 15) / 16
        )
        XCTAssertEqual(
            sixMonths.cells.compactMap(\.date).first,
            sixMonthBoundary
        )
        XCTAssertEqual(sixMonths.cells.compactMap(\.date).last, endDate)
        XCTAssertFalse(sixMonths.cells.compactMap(\.date).contains(tooOld))
        XCTAssertFalse(sixMonths.cells.compactMap(\.date).contains(futureDate))
        XCTAssertEqual(sixMonths.maximumTokens, 9_000)

        let partialHistory = TokenActivityGridModel(
            activity: [
                DailyTokenActivity(date: earlierDate, tokens: 9_000),
                DailyTokenActivity(date: endDate, tokens: 3_000)
            ],
            range: .sixMonths,
            endingAt: endDate
        )
        XCTAssertEqual(partialHistory.dayCount, 40)
        XCTAssertEqual(partialHistory.rowCount, 3)
        XCTAssertEqual(
            partialHistory.cells.prefix { $0.isPlaceholder }.count,
            8
        )
        XCTAssertEqual(
            partialHistory.cells.compactMap(\.date).first,
            earlierDate
        )

        let empty = TokenActivityGridModel(
            activity: [],
            range: .sixMonths,
            endingAt: endDate
        )
        XCTAssertEqual(empty.dayCount, 31)
        XCTAssertEqual(empty.rowCount, 2)
        XCTAssertEqual(empty.cells.count, 32)
        XCTAssertEqual(empty.cells.prefix { $0.isPlaceholder }.count, 1)
        XCTAssertTrue(empty.cells.dropFirst().allSatisfy { $0.tokens == nil })
        XCTAssertEqual(empty.maximumTokens, 0)
        XCTAssertEqual(TokenActivityGridMetrics.gridHeight(rowCount: 0), 12)
        XCTAssertEqual(
            TokenActivityGridMetrics.sectionHeight(rowCount: 0),
            59
        )
    }

    @MainActor
    func testEstimatedCostChartUsesThirtyDaysAndCachedInputPrice()
    throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = try XCTUnwrap(
            DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 8,
                day: 11
            ).date
        )
        let yesterday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: endDate)
        )
        let outsideRange = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -30, to: endDate)
        )
        let model = EstimatedCostChartModel(
            activity: [
                DailyTokenActivity(
                    date: outsideRange,
                    tokens: 900_000_000
                ),
                DailyTokenActivity(date: yesterday, tokens: 25_000_000),
                DailyTokenActivity(date: endDate, tokens: 75_000_000)
            ],
            endingAt: endDate
        )

        XCTAssertEqual(model.days.count, 30)
        XCTAssertEqual(model.days.first?.date, calendar.date(
            byAdding: .day,
            value: -29,
            to: endDate
        ))
        XCTAssertEqual(model.days.last?.date, endDate)
        XCTAssertEqual(
            EstimatedCostChartMetrics.cachedInputUSDPerMillionTokens,
            0.50
        )
        XCTAssertEqual(model.todayCost ?? -1, 37.50, accuracy: 0.000_001)
        XCTAssertEqual(model.latestCost ?? -1, 37.50, accuracy: 0.000_001)
        XCTAssertEqual(
            model.periodCost ?? -1,
            50.00,
            accuracy: 0.000_001
        )
        XCTAssertEqual(model.maximumCost, 37.50, accuracy: 0.000_001)
        XCTAssertEqual(model.periodTokens, 100_000_000)
        XCTAssertEqual(EstimatedCostChartMetrics.sectionHeight, 176)

        let barWidth = CGFloat(EstimatedCostChartMetrics.dayCount)
            * EstimatedCostChartMetrics.barWidth
            + CGFloat(EstimatedCostChartMetrics.dayCount - 1)
            * EstimatedCostChartMetrics.barSpacing
        XCTAssertEqual(
            barWidth,
            EstimatedCostChartMetrics.contentWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            EstimatedCostChartMetrics.barSpacing,
            62.0 / 29.0,
            accuracy: 0.000_001
        )

        let noTodayBucket = EstimatedCostChartModel(
            activity: [
                DailyTokenActivity(date: yesterday, tokens: 25_000_000)
            ],
            endingAt: endDate
        )
        XCTAssertNil(noTodayBucket.todayCost)
        XCTAssertEqual(
            noTodayBucket.latestCost ?? -1,
            12.50,
            accuracy: 0.000_001
        )
    }

    @MainActor
    func testZeroResetCreditsDoNotExposeDemoAction() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let provider = AppStubProvider { _ in
            Self.makeFetchResult(resetCredits: 0)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults,
            widgetSnapshotWriter: Self.disabledWidgetWriter()
        )

        await store.refresh()

        XCTAssertEqual(store.snapshot?.availableResetCredits, 0)
        XCTAssertFalse(store.hasAvailableResetCredit)
        let didSimulate = await store.performDemoReset()
        XCTAssertFalse(didSimulate)
        await store.stop()
    }

    @MainActor
    func testLatestProviderFailureClearsPresentation() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let outcomes = AppOutcomeSequence()
        let provider = AppStubProvider { _ in
            if await outcomes.shouldFail() {
                throw ProviderError.unavailable
            }
            return Self.makeFetchResult(resetCredits: 1)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults,
            widgetSnapshotWriter: Self.disabledWidgetWriter()
        )

        await store.refresh()
        XCTAssertNotNil(store.snapshot)
        XCTAssertTrue(store.hasCurrentCodexStatus)

        await store.refresh()
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.hasCurrentCodexStatus)
        XCTAssertNotNil(store.errorMessage)
        guard case .unavailable = store.providerState else {
            await store.stop()
            return XCTFail("Latest provider failure must be unavailable")
        }
        await store.stop()
    }

    private static func makeFetchResult(
        resetCredits: Int?,
        secondaryUsedPercent: Int? = nil,
        sparkUsedPercent: Int? = nil,
        historicalObservations: [MetricObservation] = []
    ) -> ProviderFetchResult {
        let capturedAt = Date(timeIntervalSince1970: 1_785_000_000)
        let window = RateWindow(
            id: CodexDomainCatalog.primaryRateWindowID,
            titleKey: "codex.quota.primary",
            period: .duration(minutes: 10_080),
            startsAt: nil,
            resetsAt: capturedAt.addingTimeInterval(3_600),
            usedFraction: 0.25,
            remainingFraction: 0.75,
            sourcePrecision: .providerRounded,
            quotaRisk: .normal
        )
        var rateWindows = [window]
        if let secondaryUsedPercent {
            let usedFraction = Double(secondaryUsedPercent) / 100
            rateWindows.append(
                RateWindow(
                    id: CodexDomainCatalog.secondaryRateWindowID,
                    titleKey: "codex.quota.secondary",
                    period: .duration(minutes: 300),
                    startsAt: nil,
                    resetsAt: capturedAt.addingTimeInterval(18_000),
                    usedFraction: usedFraction,
                    remainingFraction: 1 - usedFraction,
                    sourcePrecision: .providerRounded,
                    quotaRisk: .normal
                )
            )
        }
        if let sparkUsedPercent {
            let usedFraction = Double(sparkUsedPercent) / 100
            rateWindows.append(
                RateWindow(
                    id: CodexDomainCatalog.sparkRateWindowID,
                    titleKey: "codex.quota.spark.weekly",
                    period: .duration(minutes: 10_080),
                    startsAt: nil,
                    resetsAt: capturedAt.addingTimeInterval(604_800),
                    usedFraction: usedFraction,
                    remainingFraction: 1 - usedFraction,
                    sourcePrecision: .providerRounded,
                    quotaRisk: .normal
                )
            )
        }
        var metrics: [MetricSample] = []
        if let resetCredits {
            metrics.append(
                MetricSample(
                    definitionID: CodexDomainCatalog.resetCreditsID,
                    entity: CodexDomainCatalog.providerEntity,
                    value: .count(Int64(resetCredits)),
                    availability: .available,
                    observedAt: capturedAt
                )
            )
        }
        let snapshot = ProviderSnapshot(
            schemaVersion: 1,
            providerID: CodexDomainCatalog.providerID,
            capturedAt: capturedAt,
            availability: .available,
            accountScope: nil,
            plan: PlanDescriptor(
                rawValue: "plus",
                displayName: "plus"
            ),
            rateWindows: rateWindows,
            balances: [],
            currentMetrics: metrics,
            models: [],
            agents: [],
            serviceHealth: .unknown
        )
        return ProviderFetchResult(
            snapshot: snapshot,
            historicalObservations: historicalObservations,
            diagnostics: SanitizedFetchDiagnostics(
                sourceLabel: "test",
                duration: 0,
                optionalIssues: []
            )
        )
    }

    @MainActor
    private static func disabledWidgetWriter()
        -> QuotaViewWidgetSnapshotWriter {
        QuotaViewWidgetSnapshotWriter(
            appGroupIdentifier: "com.quotaview.tests.disabled",
            containerURLProvider: { _ in nil },
            timelineReloader: { _ in }
        )
    }
}

private struct AppStubProvider:
    UsageProviderAdapter, Sendable {
    let descriptor = ProviderDescriptor(
        id: CodexDomainCatalog.providerID,
        displayName: "Codex",
        capabilities: .currentQuotaViewFeatures,
        sourceKinds: [.localAppServer],
        resourceProfile: ProviderResourceProfile(
            minimumRefreshInterval: 1,
            startsSubprocess: false,
            typicalTimeout: 1,
            permitsParallelEnrichment: true,
            lowPowerMinimumInterval: 1
        ),
        supportsStableAccountScope: false
    )

    private let handler: @Sendable (
        ProviderFetchRequest
    ) async throws -> ProviderFetchResult

    init(
        handler: @escaping @Sendable (
            ProviderFetchRequest
        ) async throws -> ProviderFetchResult
    ) {
        self.handler = handler
    }

    func availability() async -> ProviderAvailability {
        .available
    }

    func fetch(
        _ request: ProviderFetchRequest
    ) async throws -> ProviderFetchResult {
        try await handler(request)
    }

    func stop() async {}
}

private actor FetchRequestRecorder {
    private(set) var lastRequest: ProviderFetchRequest?

    func record(_ request: ProviderFetchRequest) {
        lastRequest = request
    }
}

private actor AppOutcomeSequence {
    private var callCount = 0

    func shouldFail() -> Bool {
        defer { callCount += 1 }
        return callCount > 0
    }
}
