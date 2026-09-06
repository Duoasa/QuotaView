import AppKit
import MetalKit
import QuartzCore
import QuotaViewCore
import simd

enum CodexActivityStateSmokeContract {
    static let fixedStep: Float = 1.0 / 60.0
    static let progressFrontTrackingRate: Float = 3.5
    static let grain: Float = 0.01
    static let normalLeftmostOpacity: Float = 0.50
    static let normalTerminalOpacity: Float = 1
    static let minimumProgressFrontPosition: Float = 0
    static let maximumProgressFrontPosition: Float = 0.95
    static let completionFullFrontPosition: Float = 1.12
    static let completionFillDuration: Float = 0.42
    static let completionEffectHighlightDelay: Float = 0.42
    static let completionEffectHighlightDuration: Float = 0.30
    static let completionEffectHighlightIntensity: Float = 0.14
    static let quantumNoiseCompletionEffectHighlightIntensity: Float = 0.18
    static let quantumNoiseEffectClockRate: Float = 1.0
    static let completionDarkenDelay: Float = 0.36
    static let completionDarkenDuration: Float = 0.44
    static let completionFinalDarkening: Float = 0.64
    static let completionSmokeFadeDelay: Float = 0.80
    static let completionSmokeFadeDuration: Float = 0.36
    static let completionGlowDelay: CFTimeInterval = 1.16
    static let completionGlowFadeDuration: CFTimeInterval = 0.24
    static let completionGlowBreathDuration: CFTimeInterval = 1.80
    static let previewState: CodexActivityVisualState = .working
    static let previewProgressFraction: Double = 0.60

    static func completionHighlightIntensity(
        for effect: AppPreferences.CodexActivityProgressEffect
    ) -> Float {
        effect == .dropField
            ? quantumNoiseCompletionEffectHighlightIntensity
            : completionEffectHighlightIntensity
    }

    static func horizontalOpacity(
        at normalizedX: Float,
        frontPosition: Float,
        opacityCurve: CodexActivityStateSmokeOpacityCurve = .normal,
        completionActive: Bool
    ) -> Float {
        guard !completionActive else { return 1 }
        let x = min(max(normalizedX, 0), 1)
        let front = min(
            max(frontPosition, Float.leastNonzeroMagnitude),
            maximumProgressFrontPosition
        )
        let relativeX = min(max(x / front, 0), 1)
        return opacityCurve.opacity(at: relativeX)
    }
}

struct CodexActivityStateSmokeOpacityCurve: Equatable {
    let stopPositions: SIMD4<Float>
    let stopOpacities: SIMD4<Float>

    static let normal = CodexActivityStateSmokeOpacityCurve(
        stopPositions: SIMD4<Float>(0, 1.0 / 3.0, 2.0 / 3.0, 1),
        stopOpacities: SIMD4<Float>(0.50, 2.0 / 3.0, 5.0 / 6.0, 1)
    )

    func opacity(at relativeX: Float) -> Float {
        let x = min(max(relativeX, 0), 1)
        if x <= stopPositions.y {
            return interpolate(
                x,
                fromPosition: stopPositions.x,
                toPosition: stopPositions.y,
                fromOpacity: stopOpacities.x,
                toOpacity: stopOpacities.y
            )
        }
        if x <= stopPositions.z {
            return interpolate(
                x,
                fromPosition: stopPositions.y,
                toPosition: stopPositions.z,
                fromOpacity: stopOpacities.y,
                toOpacity: stopOpacities.z
            )
        }
        return interpolate(
            x,
            fromPosition: stopPositions.z,
            toPosition: stopPositions.w,
            fromOpacity: stopOpacities.z,
            toOpacity: stopOpacities.w
        )
    }

    func interpolated(
        to target: CodexActivityStateSmokeOpacityCurve,
        amount: Float
    ) -> CodexActivityStateSmokeOpacityCurve {
        let t = min(max(amount, 0), 1)
        return CodexActivityStateSmokeOpacityCurve(
            stopPositions:
                stopPositions + (target.stopPositions - stopPositions) * t,
            stopOpacities:
                stopOpacities + (target.stopOpacities - stopOpacities) * t
        )
    }

    private func interpolate(
        _ value: Float,
        fromPosition: Float,
        toPosition: Float,
        fromOpacity: Float,
        toOpacity: Float
    ) -> Float {
        let distance = max(toPosition - fromPosition, 0.0001)
        let amount = min(max((value - fromPosition) / distance, 0), 1)
        return fromOpacity + (toOpacity - fromOpacity) * amount
    }
}

private func activityStateSmokeRGBA(
    _ red: Float,
    _ green: Float,
    _ blue: Float,
    _ alpha: Float = 1
) -> SIMD4<Float> {
    SIMD4<Float>(red, green, blue, alpha)
}

private let activityStateSmokeBackground = activityStateSmokeRGBA(
    19.0 / 255.0,
    16.0 / 255.0,
    25.0 / 255.0
)

struct CodexActivityStateSmokeProfile: Equatable {
    let background: SIMD4<Float>
    let deepColor: SIMD4<Float>
    let midColor: SIMD4<Float>
    let highlightColor: SIMD4<Float>
    let fieldSpeed: Float
    let motionFrequency: Float
    let turbulence: Float
    let pulse: Float
    let energy: Float
    let diffusion: Float
    let diffusionSpeed: Float
    let diffusionSpeedVariation: Float
    let opacityCurve: CodexActivityStateSmokeOpacityCurve

    init(
        background: SIMD4<Float>,
        deepColor: SIMD4<Float>,
        midColor: SIMD4<Float>,
        highlightColor: SIMD4<Float>,
        fieldSpeed: Float,
        motionFrequency: Float,
        turbulence: Float,
        pulse: Float,
        energy: Float,
        diffusion: Float,
        diffusionSpeed: Float,
        diffusionSpeedVariation: Float,
        opacityCurve: CodexActivityStateSmokeOpacityCurve = .normal
    ) {
        self.background = background
        self.deepColor = deepColor
        self.midColor = midColor
        self.highlightColor = highlightColor
        self.fieldSpeed = fieldSpeed
        self.motionFrequency = motionFrequency
        self.turbulence = turbulence
        self.pulse = pulse
        self.energy = energy
        self.diffusion = diffusion
        self.diffusionSpeed = diffusionSpeed
        self.diffusionSpeedVariation = diffusionSpeedVariation
        self.opacityCurve = opacityCurve
    }

    static func profile(
        for state: CodexActivityVisualState
    ) -> CodexActivityStateSmokeProfile {
        switch state {
        case .disconnectedCodex:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.13, 0.17, 0.24),
                midColor: activityStateSmokeRGBA(0.28, 0.34, 0.44),
                highlightColor: activityStateSmokeRGBA(0.48, 0.57, 0.70),
                fieldSpeed: 0,
                motionFrequency: 0,
                turbulence: 0.08,
                pulse: 0,
                energy: 0.42,
                diffusion: 0.12,
                diffusionSpeed: 0,
                diffusionSpeedVariation: 0
            )
        case .standby:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.12, 0.23, 0.42),
                midColor: activityStateSmokeRGBA(0.25, 0.35, 0.58),
                highlightColor: activityStateSmokeRGBA(0.44, 0.56, 0.75),
                fieldSpeed: 0.25,
                motionFrequency: 0.32,
                turbulence: 0.12,
                pulse: 0.08,
                energy: 0.50,
                diffusion: 0.38,
                diffusionSpeed: 1.25,
                diffusionSpeedVariation: 0.16
            )
        case .thinking:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.20, 0.12, 0.68),
                midColor: activityStateSmokeRGBA(0.50, 0.23, 0.88),
                highlightColor: activityStateSmokeRGBA(0.34, 0.57, 1.00),
                fieldSpeed: 0.75,
                motionFrequency: 0.82,
                turbulence: 0.34,
                pulse: 0.18,
                energy: 0.86,
                diffusion: 0.82,
                diffusionSpeed: 1.55,
                diffusionSpeedVariation: 0.30
            )
        case .working:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.14, 0.29, 0.34),
                midColor: activityStateSmokeRGBA(0.20, 0.40, 0.46),
                highlightColor: activityStateSmokeRGBA(0.28, 0.48, 0.54),
                fieldSpeed: 1.00,
                motionFrequency: 1.10,
                turbulence: 0.58,
                pulse: 0.22,
                energy: 1.00,
                diffusion: 1.00,
                diffusionSpeed: 1.85,
                diffusionSpeedVariation: 0.36
            )
        case .compactingContext:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.16, 0.18, 0.20),
                midColor: activityStateSmokeRGBA(0.22, 0.24, 0.26),
                highlightColor: activityStateSmokeRGBA(0.28, 0.30, 0.32),
                fieldSpeed: 0.46,
                motionFrequency: 0.62,
                turbulence: 0.26,
                pulse: 0.14,
                energy: 0.82,
                diffusion: 0.08,
                diffusionSpeed: 0.45,
                diffusionSpeedVariation: 0.04
            )
        case .awaitingConfirmation:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.55, 0.21, 0.02),
                midColor: activityStateSmokeRGBA(0.95, 0.46, 0.05),
                highlightColor: activityStateSmokeRGBA(1.00, 0.78, 0.22),
                fieldSpeed: 0.48,
                motionFrequency: 0.52,
                turbulence: 0.20,
                pulse: 0.46,
                energy: 0.90,
                diffusion: 0.55,
                diffusionSpeed: 1.45,
                diffusionSpeedVariation: 0.24
            )
        case .completed:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.18, 0.12, 0.52),
                midColor: activityStateSmokeRGBA(0.26, 0.48, 0.88),
                highlightColor: activityStateSmokeRGBA(0.43, 0.89, 1.00),
                fieldSpeed: 0.18,
                motionFrequency: 0.24,
                turbulence: 0.12,
                pulse: 0.12,
                energy: 0.70,
                diffusion: 0.30,
                diffusionSpeed: 0.75,
                diffusionSpeedVariation: 0
            )
        case .error:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.55, 0.01, 0.05),
                midColor: activityStateSmokeRGBA(0.92, 0.08, 0.14),
                highlightColor: activityStateSmokeRGBA(1.00, 0.36, 0.22),
                fieldSpeed: 1.10,
                motionFrequency: 1.65,
                turbulence: 0.62,
                pulse: 0.28,
                energy: 0.98,
                diffusion: 0.92,
                diffusionSpeed: 1.95,
                diffusionSpeedVariation: 0.40
            )
        case .unavailable:
            CodexActivityStateSmokeProfile(
                background: activityStateSmokeBackground,
                deepColor: activityStateSmokeRGBA(0.23, 0.25, 0.30),
                midColor: activityStateSmokeRGBA(0.36, 0.38, 0.43),
                highlightColor: activityStateSmokeRGBA(0.50, 0.53, 0.58),
                fieldSpeed: 0,
                motionFrequency: 0,
                turbulence: 0.03,
                pulse: 0,
                energy: 0.32,
                diffusion: 0.08,
                diffusionSpeed: 0,
                diffusionSpeedVariation: 0
            )
        }
    }

    static func profile(
        for state: CodexActivityVisualState,
        effect: AppPreferences.CodexActivityProgressEffect
    ) -> CodexActivityStateSmokeProfile {
        let standardProfile = profile(for: state)
        guard state == .compactingContext,
              effect == .dropField
        else {
            return standardProfile
        }

        return CodexActivityStateSmokeProfile(
            background: standardProfile.background,
            deepColor: activityStateSmokeRGBA(0.50, 0.53, 0.57),
            midColor: activityStateSmokeRGBA(0.68, 0.72, 0.77),
            highlightColor: activityStateSmokeRGBA(0.88, 0.92, 0.98),
            fieldSpeed: standardProfile.fieldSpeed,
            motionFrequency: standardProfile.motionFrequency,
            turbulence: standardProfile.turbulence,
            pulse: standardProfile.pulse,
            energy: standardProfile.energy,
            diffusion: standardProfile.diffusion,
            diffusionSpeed: standardProfile.diffusionSpeed,
            diffusionSpeedVariation:
                standardProfile.diffusionSpeedVariation,
            opacityCurve: standardProfile.opacityCurve
        )
    }

    func interpolated(
        to target: CodexActivityStateSmokeProfile,
        amount: Float
    ) -> CodexActivityStateSmokeProfile {
        let t = min(max(amount, 0), 1)
        return CodexActivityStateSmokeProfile(
            background: background + (target.background - background) * t,
            deepColor: deepColor + (target.deepColor - deepColor) * t,
            midColor: midColor + (target.midColor - midColor) * t,
            highlightColor:
                highlightColor
                + (target.highlightColor - highlightColor) * t,
            fieldSpeed: fieldSpeed + (target.fieldSpeed - fieldSpeed) * t,
            motionFrequency:
                motionFrequency
                + (target.motionFrequency - motionFrequency) * t,
            turbulence:
                turbulence + (target.turbulence - turbulence) * t,
            pulse: pulse + (target.pulse - pulse) * t,
            energy: energy + (target.energy - energy) * t,
            diffusion: diffusion + (target.diffusion - diffusion) * t,
            diffusionSpeed:
                diffusionSpeed
                + (target.diffusionSpeed - diffusionSpeed) * t,
            diffusionSpeedVariation:
                diffusionSpeedVariation
                + (target.diffusionSpeedVariation
                    - diffusionSpeedVariation) * t,
            opacityCurve: opacityCurve.interpolated(
                to: target.opacityCurve,
                amount: t
            )
        )
    }
}

struct CodexActivityStateSmokeSnapshot: Equatable {
    let fieldTime: Float
    let effectTime: Float
    let pulse: Float
}

struct CodexActivityStateSmokeCompletionSnapshot: Equatable {
    let fillProgress: Float
    let effectHighlight: Float
    let darkening: Float
    let smokeOpacity: Float

    static let inactive = CodexActivityStateSmokeCompletionSnapshot(
        fillProgress: 0,
        effectHighlight: 0,
        darkening: 0,
        smokeOpacity: 1
    )

    static let reducedMotion = CodexActivityStateSmokeCompletionSnapshot(
        fillProgress: 1,
        effectHighlight: 0,
        darkening:
            CodexActivityStateSmokeContract.completionFinalDarkening,
        smokeOpacity: 0
    )
}

struct CodexActivityStateSmokeCompletionTransition {
    private(set) var elapsed: Float = 0
    private(set) var isActive = false

    var snapshot: CodexActivityStateSmokeCompletionSnapshot {
        guard isActive else { return .inactive }

        let fillLinear = min(
            max(
                elapsed
                    / CodexActivityStateSmokeContract
                        .completionFillDuration,
                0
            ),
            1
        )
        let fillProgress = 1 - pow(1 - fillLinear, 3)
        let highlightLinear = min(
            max(
                (elapsed
                    - CodexActivityStateSmokeContract
                        .completionEffectHighlightDelay)
                    / CodexActivityStateSmokeContract
                        .completionEffectHighlightDuration,
                0
            ),
            1
        )
        let highlightWave = sin(highlightLinear * .pi)
        let effectHighlight = highlightWave * highlightWave
        let darkenLinear = min(
            max(
                (elapsed
                    - CodexActivityStateSmokeContract
                        .completionDarkenDelay)
                    / CodexActivityStateSmokeContract
                        .completionDarkenDuration,
                0
            ),
            1
        )
        let darkenProgress =
            darkenLinear * darkenLinear * (3 - 2 * darkenLinear)
        let fadeLinear = min(
            max(
                (elapsed
                    - CodexActivityStateSmokeContract
                        .completionSmokeFadeDelay)
                    / CodexActivityStateSmokeContract
                        .completionSmokeFadeDuration,
                0
            ),
            1
        )
        let fadeProgress =
            fadeLinear * fadeLinear * (3 - 2 * fadeLinear)
        return CodexActivityStateSmokeCompletionSnapshot(
            fillProgress: fillProgress,
            effectHighlight: effectHighlight,
            darkening:
                darkenProgress
                * CodexActivityStateSmokeContract
                    .completionFinalDarkening,
            smokeOpacity: 1 - fadeProgress
        )
    }

    mutating func enter() {
        elapsed = 0
        isActive = true
    }

    mutating func advance(
        elapsed delta: Float
    ) -> CodexActivityStateSmokeCompletionSnapshot {
        guard isActive else { return .inactive }
        elapsed += min(max(delta, 0), 0.25)
        return snapshot
    }

    mutating func finish() {
        guard isActive else { return }
        elapsed = max(
            CodexActivityStateSmokeContract.completionFillDuration,
            CodexActivityStateSmokeContract.completionSmokeFadeDelay
                + CodexActivityStateSmokeContract
                    .completionSmokeFadeDuration
        )
    }

    mutating func reset() {
        elapsed = 0
        isActive = false
    }
}

struct CodexActivityStateSmokeSimulation {
    private(set) var fieldTime: Float = 0
    private(set) var effectTime: Float = 0
    private(set) var pulse: Float = 0.5

    private var motionPhase: Float = 0
    private var accumulator: Float = 0

    static let reducedMotionSnapshot = CodexActivityStateSmokeSnapshot(
        fieldTime: 0.35,
        effectTime: 0.35,
        pulse: 0.5
    )

    var snapshot: CodexActivityStateSmokeSnapshot {
        CodexActivityStateSmokeSnapshot(
            fieldTime: fieldTime,
            effectTime: effectTime,
            pulse: pulse
        )
    }

    mutating func advance(
        elapsed: Float,
        profile: CodexActivityStateSmokeProfile,
        effectPlaybackEnabled: Bool = true
    ) -> CodexActivityStateSmokeSnapshot {
        accumulator += min(max(elapsed, 0), 0.25)
        var steps = 0
        while accumulator >= CodexActivityStateSmokeContract.fixedStep,
              steps < 15
        {
            step(
                delta: CodexActivityStateSmokeContract.fixedStep,
                profile: profile,
                effectPlaybackEnabled: effectPlaybackEnabled
            )
            accumulator -= CodexActivityStateSmokeContract.fixedStep
            steps += 1
        }
        return snapshot
    }

    mutating func step(
        delta: Float = CodexActivityStateSmokeContract.fixedStep,
        profile: CodexActivityStateSmokeProfile,
        effectPlaybackEnabled: Bool = true
    ) {
        let safeDelta = max(delta, 0)
        motionPhase +=
            safeDelta * profile.motionFrequency * Float.pi * 2
        fieldTime += safeDelta * profile.fieldSpeed
        if effectPlaybackEnabled {
            effectTime +=
                safeDelta
                * CodexActivityStateSmokeContract
                    .quantumNoiseEffectClockRate
        }

        pulse =
            0.5
            + 0.5 * sin(motionPhase * 1.9 + 0.35)

        if motionPhase > Float.pi * 2_048 {
            motionPhase.formTruncatingRemainder(
                dividingBy: Float.pi * 2
            )
        }
        if fieldTime > 4_096 {
            fieldTime.formTruncatingRemainder(dividingBy: 4_096)
        }
    }

    mutating func resetEffectTime() {
        effectTime = 0
    }
}

struct CodexActivityStateSmokeProgressProjection {
    private(set) var displayedFrontPosition: Float?
    private var taskIdentity: CodexActivityTaskIdentity?

    @discardableResult
    mutating func bindTask(_ identity: CodexActivityTaskIdentity?) -> Bool {
        guard taskIdentity != identity else { return false }
        taskIdentity = identity
        reset()
        return true
    }

    mutating func reset() {
        displayedFrontPosition = nil
    }

    static func targetFrontPosition(
        for approximateProgressFraction: Double?
    ) -> Float? {
        guard let approximateProgressFraction,
              approximateProgressFraction.isFinite
        else { return nil }
        return min(
            max(
                Float(approximateProgressFraction),
                CodexActivityStateSmokeContract
                    .minimumProgressFrontPosition
            ),
            CodexActivityStateSmokeContract
                .maximumProgressFrontPosition
        )
    }

    mutating func resolve(
        approximateProgressFraction: Double?,
        elapsed: Float,
        reduceMotion: Bool
    ) -> Float {
        guard let target = Self.targetFrontPosition(
            for: approximateProgressFraction
        ) else {
            displayedFrontPosition = 0
            return 0
        }

        if reduceMotion {
            displayedFrontPosition = target
            return target
        }

        let current = displayedFrontPosition ?? 0
        let monotonicTarget = max(target, current)
        let transition = 1 - exp(
            -CodexActivityStateSmokeContract.progressFrontTrackingRate
                * min(max(elapsed, 0), 0.25)
        )
        let resolved =
            current + (monotonicTarget - current) * transition
        displayedFrontPosition = resolved
        return resolved
    }
}

struct CodexActivityStateSmokeUnplannedProgress {
    static let maximumActiveFraction: Float = 0.50
    static let reducedMotionThinkingFraction: Float = 0.12
    static let workingMinimumFraction: Float = 0.28
    static let confirmationMinimumFraction: Float = 0.40
    static let compactionMinimumFraction: Float = 0.46
    static let timeConstant: Float = 8

    private(set) var fraction: Float = 0

    mutating func reset() {
        fraction = 0
    }

    mutating func resolve(
        state: CodexActivityVisualState,
        elapsed: Float,
        reduceMotion: Bool
    ) -> Double? {
        guard state.activitySupportsUnplannedProgress else {
            return nil
        }

        let minimum = Self.minimumFraction(
            for: state,
            reduceMotion: reduceMotion
        )
        fraction = max(fraction, minimum)
        if !reduceMotion {
            let safeElapsed = min(max(elapsed, 0), 0.25)
            let transition = 1 - exp(-safeElapsed / Self.timeConstant)
            fraction +=
                (Self.maximumActiveFraction - fraction) * transition
        }
        fraction = min(fraction, Self.maximumActiveFraction)
        return Double(fraction)
    }

    private static func minimumFraction(
        for state: CodexActivityVisualState,
        reduceMotion: Bool
    ) -> Float {
        switch state {
        case .thinking:
            reduceMotion ? reducedMotionThinkingFraction : 0
        case .working:
            workingMinimumFraction
        case .awaitingConfirmation:
            confirmationMinimumFraction
        case .compactingContext:
            compactionMinimumFraction
        default:
            0
        }
    }
}

struct CodexActivityStateSmokeProgressResolver {
    enum Mode: Equatable {
        case inactive
        case resolvingPlan
        case unplanned
        case planned
    }

    static let planResolutionDuration: Float = 4.0
    static let planResolutionFraction: Double = 0.01

    private(set) var mode: Mode = .inactive
    private(set) var planResolutionElapsed: Float = 0
    private var unplannedProgress =
        CodexActivityStateSmokeUnplannedProgress()

    mutating func reset() {
        mode = .inactive
        planResolutionElapsed = 0
        unplannedProgress.reset()
    }

    mutating func resolve(
        state: CodexActivityVisualState,
        plannedFraction: Double?,
        elapsed: Float,
        reduceMotion: Bool
    ) -> Double? {
        if state == .completed {
            return plannedFraction ?? 1
        }
        guard state.activitySupportsUnplannedProgress else {
            mode = .inactive
            planResolutionElapsed = 0
            return nil
        }
        if let plannedFraction,
           plannedFraction.isFinite
        {
            mode = .planned
            return min(max(plannedFraction, 0), 1)
        }

        let safeElapsed = min(max(elapsed, 0), 0.25)
        switch mode {
        case .inactive:
            mode = .resolvingPlan
            planResolutionElapsed = safeElapsed
            return Self.planResolutionFraction
        case .resolvingPlan:
            planResolutionElapsed += safeElapsed
            guard planResolutionElapsed
                    >= Self.planResolutionDuration
            else {
                return Self.planResolutionFraction
            }
            mode = .unplanned
            let fraction = unplannedProgress.resolve(
                state: state,
                elapsed: 0,
                reduceMotion: reduceMotion
            )
            return max(fraction ?? 0, Self.planResolutionFraction)
        case .unplanned:
            let fraction = unplannedProgress.resolve(
                state: state,
                elapsed: safeElapsed,
                reduceMotion: reduceMotion
            )
            return max(fraction ?? 0, Self.planResolutionFraction)
        case .planned:
            // A new prompt normally resets through completed -> active. If a
            // transport temporarily omits a carried plan, keep the display
            // stable while giving a late plan another discovery window.
            mode = .resolvingPlan
            planResolutionElapsed = safeElapsed
            unplannedProgress.reset()
            return Self.planResolutionFraction
        }
    }
}

private extension CodexActivityVisualState {
    var activityAnimatesQuantumNoise: Bool {
        switch self {
        case .thinking,
             .working,
             .compactingContext,
             .awaitingConfirmation,
             .completed,
             .error:
            true
        case .disconnectedCodex,
             .standby,
             .unavailable:
            false
        }
    }

    var activitySupportsUnplannedProgress: Bool {
        switch self {
        case .thinking,
             .working,
             .compactingContext,
             .awaitingConfirmation:
            true
        case .disconnectedCodex,
             .standby,
             .completed,
             .error,
             .unavailable:
            false
        }
    }

    func activityStartsFreshProgress(
        after previousState: CodexActivityVisualState
    ) -> Bool {
        guard activitySupportsUnplannedProgress else { return false }
        return !previousState.activitySupportsUnplannedProgress
    }

    var activityClearsProgress: Bool {
        switch self {
        case .disconnectedCodex,
             .standby,
             .error,
             .unavailable:
            true
        case .thinking,
             .working,
             .compactingContext,
             .awaitingConfirmation,
             .completed:
            false
        }
    }
}

// State-driven quantum motion. Velocity is integrated, never multiplied by wall time
// after a state change. The same particle seeds therefore survive interruptions.
struct ActivityQuantumMotionProfile {
    var weights: SIMD4<Float> // exploration, transport, compression, waiting
    var velocity: SIMD2<Float>
    var rate: Float
    var failure: Float
    var visibility: Float

    static func profile(_ state: CodexActivityVisualState) -> Self {
        switch state {
        case .thinking:
            // Share the natural gathering motion; state colors remain independent.
            return profile(.compactingContext)
        case .working:
            return .init(weights: [0, 1, 0, 0], velocity: [-16, 0], rate: 1.5,
                         failure: 0, visibility: 1)
        case .compactingContext:
            return .init(weights: [0, 0, 1, 0], velocity: [-0.8, 0], rate: 1.0,
                         failure: 0, visibility: 1)
        case .awaitingConfirmation:
            return .init(weights: [0, 0, 0, 1], velocity: .zero, rate: 1,
                         failure: 0, visibility: 1)
        case .error:
            return .init(weights: .zero, velocity: .zero, rate: 0.38,
                         failure: 1, visibility: 1)
        case .completed:
            return .init(weights: [0, 0.3, 0.4, 0], velocity: [-2, 0], rate: 0.45,
                         failure: 0, visibility: 1)
        case .standby, .disconnectedCodex, .unavailable:
            return .init(weights: .zero, velocity: .zero, rate: 0,
                         failure: 0, visibility: 0.3)
        }
    }

    func interpolated(to target: Self, amount: Float) -> Self {
        let t = min(max(amount, 0), 1)
        return .init(weights: weights + (target.weights - weights) * t,
                     velocity: velocity + (target.velocity - velocity) * t,
                     rate: rate + (target.rate - rate) * t,
                     failure: failure + (target.failure - failure) * t,
                     visibility: visibility + (target.visibility - visibility) * t)
    }
}

struct ActivityQuantumMotion {
    private(set) var profile = ActivityQuantumMotionProfile.profile(.working)
    private(set) var displacement = SIMD2<Float>.zero
    private(set) var phase: Float = 0

    mutating func advance(state: CodexActivityVisualState, elapsed: Float,
                          reduceMotion: Bool) {
        let target = ActivityQuantumMotionProfile.profile(state)
        if reduceMotion {
            profile = target
            return
        }
        // Fixed substeps make interrupted transitions independent of frame rate.
        let delta = min(max(elapsed, 0), 0.25)
        let steps = max(1, Int(ceil(delta / (1.0 / 120.0))))
        let dt = delta / Float(steps)
        for _ in 0..<steps {
            profile = profile.interpolated(to: target, amount: 1 - exp(-5 * dt))
            displacement += profile.velocity * dt
            phase += profile.rate * dt
        }
    }
}

private struct ActivityStateSmokeUniforms {
    var resolution: SIMD2<Float>
    var frontPosition: Float
    var pulse: Float
    var fieldTime: Float
    var effectTime: Float
    var turbulence: Float
    var energy: Float
    var diffusion: Float
    var diffusionSpeed: Float
    var diffusionSpeedVariation: Float
    var grain: Float
    var effectStyle: Float
    var completionFillProgress: Float
    var completionEffectHighlight: Float
    var completionDarkening: Float
    var completionSmokeOpacity: Float
    var completionActive: Float
    var quantumWeights: SIMD4<Float>
    var quantumClock: SIMD4<Float>
    var quantumEnabled: SIMD4<Float>
    var opacityStopPositions: SIMD4<Float>
    var opacityStopOpacities: SIMD4<Float>
    var background: SIMD4<Float>
    var deepColor: SIMD4<Float>
    var midColor: SIMD4<Float>
    var highlightColor: SIMD4<Float>
}

let activityStateSmokeShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct ActivityStateSmokeUniforms {
    float2 resolution;
    float frontPosition;
    float pulse;
    float fieldTime;
    float effectTime;
    float turbulence;
    float energy;
    float diffusion;
    float diffusionSpeed;
    float diffusionSpeedVariation;
    float grain;
    float effectStyle;
    float completionFillProgress;
    float completionEffectHighlight;
    float completionDarkening;
    float completionSmokeOpacity;
    float completionActive;
    float4 quantumWeights;
    float4 quantumClock;
    float4 quantumEnabled;
    float4 opacityStopPositions;
    float4 opacityStopOpacities;
    float4 background;
    float4 deepColor;
    float4 midColor;
    float4 highlightColor;
};

vertex VertexOut activityStateSmokeVertex(
    uint vertexID [[vertex_id]]
) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

float activityStateSmokeHash(float2 p0) {
    float2 p = fract(p0 * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float activityStateSmokeValueNoise(float2 p) {
    float2 cell = floor(p);
    float2 fraction = fract(p);
    float2 weight = fraction * fraction * (3.0 - 2.0 * fraction);
    return mix(
        mix(
            activityStateSmokeHash(cell),
            activityStateSmokeHash(cell + float2(1.0, 0.0)),
            weight.x
        ),
        mix(
            activityStateSmokeHash(cell + float2(0.0, 1.0)),
            activityStateSmokeHash(cell + float2(1.0, 1.0)),
            weight.x
        ),
        weight.y
    );
}

float activityStateSmokeFBM(float2 p0) {
    float value = 0.0;
    float amplitude = 0.5;
    float2 p = p0;
    for (int index = 0; index < 4; ++index) {
        value += amplitude * activityStateSmokeValueNoise(p);
        p = p * 2.03 + 11.7;
        amplitude *= 0.5;
    }
    return value;
}

float activityStateSmokeReverseSmoothstep(
    float edge0,
    float edge1,
    float value
) {
    float amount = clamp(
        (value - edge0) / (edge1 - edge0),
        0.0,
        1.0
    );
    return amount * amount * (3.0 - 2.0 * amount);
}

float activityStateSmokeOpacitySegment(
    float value,
    float fromPosition,
    float toPosition,
    float fromOpacity,
    float toOpacity
) {
    float distance = max(toPosition - fromPosition, 0.0001);
    float amount = clamp(
        (value - fromPosition) / distance,
        0.0,
        1.0
    );
    return mix(fromOpacity, toOpacity, amount);
}

float activityStateSmokeHorizontalOpacity(
    float relativeX,
    float4 stopPositions,
    float4 stopOpacities
) {
    if (relativeX <= stopPositions.y) {
        return activityStateSmokeOpacitySegment(
            relativeX,
            stopPositions.x,
            stopPositions.y,
            stopOpacities.x,
            stopOpacities.y
        );
    }
    if (relativeX <= stopPositions.z) {
        return activityStateSmokeOpacitySegment(
            relativeX,
            stopPositions.y,
            stopPositions.z,
            stopOpacities.y,
            stopOpacities.z
        );
    }
    return activityStateSmokeOpacitySegment(
        relativeX,
        stopPositions.z,
        stopPositions.w,
        stopOpacities.z,
        stopOpacities.w
    );
}

float activityProgressDiamondDensity(
    float2 uv,
    float aspect,
    float front,
    float time,
    float pulse,
    float turbulence
) {
    float rows = 7.5;
    float columns = max(rows * aspect, 1.0);
    float2 coordinate = float2(uv.x * columns, uv.y * rows);
    float column = floor(coordinate.x);
    coordinate.y += fmod(column, 2.0) * 0.5;
    float2 cell = floor(coordinate);
    float2 local = fract(coordinate) - 0.5;
    float distanceToDiamond = abs(local.x) + abs(local.y);
    float core = 1.0 - smoothstep(0.28, 0.47, distanceToDiamond);
    float bloom = exp(-max(distanceToDiamond - 0.25, 0.0) * 9.5);
    float seed = activityStateSmokeHash(cell + 17.0);
    float centerX = (cell.x + 0.5) / columns;
    float stagger = (seed - 0.5) * (0.028 + turbulence * 0.018);
    float shimmer =
        sin(time * 2.8 + seed * 6.2831853) * (0.004 + pulse * 0.005);
    float activated = 1.0 - smoothstep(
        front - 0.018,
        front + 0.032,
        centerX + stagger + shimmer
    );
    float edgeFocus = exp(-abs(centerX - front) * 15.0);
    return clamp(
        (core + bloom * (0.12 + edgeFocus * 0.20))
            * activated
            * (0.72 + edgeFocus * 0.28),
        0.0,
        1.0
    );
}

float activityProgressDropDensity(
    float2 pixel,
    float2 resolution,
    float front,
    float effectTime
) {
    float dropletCellSize = 2.35;
    float2 drift = float2(
        sin(effectTime * 0.63) * 0.46,
        effectTime * 0.68
    );
    float2 coordinate = (pixel + drift) / dropletCellSize;
    float2 cell = floor(coordinate);
    float shapeSeed = activityStateSmokeHash(cell + 31.0);
    float2 jitter = float2(
        activityStateSmokeHash(cell + 47.0),
        activityStateSmokeHash(cell + 83.0)
    ) - 0.5;
    float2 local = fract(coordinate) - 0.5 - jitter * 0.22;
    float dotRadius = mix(0.17, 0.31, shapeSeed);
    float dotDistance = length(local);
    float microDrop = 1.0 - smoothstep(
        dotRadius,
        dotRadius + 0.10,
        dotDistance
    );
    float microBloom = exp(-max(dotDistance - dotRadius, 0.0) * 12.0);
    float centerX = clamp(
        ((cell.x + 0.5) * dropletCellSize - drift.x)
            / max(resolution.x, 1.0),
        0.0,
        1.0
    );
    float stagger =
        (activityStateSmokeHash(cell + 109.0) - 0.5)
        * 0.026;
    float frontDensity = 1.0 - smoothstep(
        front - 0.125,
        front + 0.002,
        centerX + stagger
    );
    float occupancySeed = activityStateSmokeHash(cell + 151.0);
    float occupancy = step(
        1.0 - frontDensity * 0.88,
        occupancySeed
    );
    float twinkleRate = mix(
        2.4,
        4.0,
        activityStateSmokeHash(cell + 197.0)
    );
    float twinkleWave = 0.5
        + 0.5
            * sin(
                effectTime * twinkleRate
                + shapeSeed * 6.2831853
            );
    float quantumNoiseOpacityBoost = 1.10;
    float sparkle = min(
        (0.22
            + twinkleWave * 0.62
            + pow(twinkleWave, 5.0) * 0.16)
            * quantumNoiseOpacityBoost,
        1.0
    );
    return clamp(
        (microDrop + microBloom * 0.08)
            * occupancy
            * sparkle,
        0.0,
        1.0
    );
}

float3 activityQuantumOriginalColor(float density, ActivityStateSmokeUniforms u) {
    float breathing = 1.0 + (u.pulse - 0.5) * 0.18;

    float3 color = u.background.rgb;
    color += u.deepColor.rgb * density * 0.72 * u.energy;
    color +=
        u.midColor.rgb
        * pow(density, 2.2)
        * 0.68
        * u.energy;
    color +=
        u.highlightColor.rgb
        * pow(density, 7.0)
        * 0.55
        * breathing
        * u.energy;
    if (u.effectStyle > 0.5) {
        float completionHighlightDensity = pow(density, 3.0);
        if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
            completionHighlightDensity = pow(density, 1.5);
        }
        color +=
            u.highlightColor.rgb
            * completionHighlightDensity
            * clamp(u.completionEffectHighlight, 0.0, 1.0)
            * u.energy;
    }
    return color;
}
// State-aware quantum starlight renderer. The particle field has no vertical envelope:
// only the production island's rounded clipping and horizontal progress apply.
float activityQuantumPulseCenter(float phase) {
    float cycle = fract(phase * 0.24);
    float eased = cycle * cycle * cycle * (cycle * (cycle * 6.0 - 15.0) + 10.0);
    return mix(-0.28, 1.28, eased);
}

float activityQuantumTransportPulse(float2 pixel, float2 resolution, float front, float phase) {
    float position = pixel.x / max(resolution.x * front, 1.0);
    float height = pixel.y / resolution.y;
    // A single irregular cluster passes through the field. Its centre accelerates
    // and decelerates; its curved, broken edge never becomes a straight light bar.
    float bend = 0.065 * sin(height * 7.0 + phase * 0.6)
        + 0.035 * sin(height * 19.0 - phase * 0.35);
    float width = 0.080 + 0.025 * sin(height * 11.0 + phase * 0.4);
    float cycle = fract(phase * 0.24);
    float gate = smoothstep(0.04, 0.16, cycle) * (1.0 - smoothstep(0.84, 0.96, cycle));
    return exp(-0.5 * pow((position - activityQuantumPulseCenter(phase) - bend) / width, 2.0)) * gate;
}

float activityQuantumFrontCoverage(float2 pixel, float2 resolution, float front, float completion) {
    if (front <= 0.0) { return 0.0; }
    float x = pixel.x / resolution.x;
    float y = pixel.y / resolution.y;
    // Estimated progress retains a visible dissolve even at 1%. A short front is
    // an uncertainty region, not a tiny precisely clipped bar. Keep dots crisp.
    float minimumFeather = min(48.0 / resolution.x, 0.18);
    float feather = clamp(front * 0.70, minimumFeather, 0.18);
    float retreat = feather * (0.10 + 0.05 * sin(y * 7.0) + 0.025 * sin(y * 19.0));
    float edge = max(front, minimumFeather) - retreat;
    float coverage = 1.0 - smoothstep(max(0.0, edge - feather), edge, x);
    // Approach zero continuously as progress first appears; standby stays empty.
    coverage *= smoothstep(0.0, 0.005, front);
    return mix(coverage, 1.0, smoothstep(0.75, 1.0, completion));
}

// Restore the early full-height prototype's independently phased neighbourhoods.
// Interpolate their influence so grouped light has no rectangular cell boundary.
float activityQuantumCompressionCoherence(float2 pixel, float phase) {
    float2 grid = pixel / 33.6; // Original neighbourhood: 7 grains at 4.8 px.
    float2 cell = floor(grid);
    float2 fraction = fract(grid);
    float2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float value = 0.0;
    for (int row = 0; row < 2; ++row) {
        for (int column = 0; column < 2; ++column) {
            float2 neighbour = cell + float2(column, row);
            float seed = activityStateSmokeHash(neighbour + 263.0);
            float organize = 0.5 + 0.5 * sin(phase * 3.2 + seed * 6.283185);
            float weight = (column == 0 ? 1.0 - blend.x : blend.x)
                         * (row == 0 ? 1.0 - blend.y : blend.y);
            value += organize * weight;
        }
    }
    return value;
}

float3 activityQuantumCompressionClusters(float2 pixel, float2 resolution, float front, float phase) {
    float organize = activityQuantumCompressionCoherence(pixel, phase);
    float2 cell = floor(pixel / 2.35);
    float2 jitter = float2(activityStateSmokeHash(cell + 47.0),
                          activityStateSmokeHash(cell + 83.0)) - 0.5;
    // Original local reordering: jitter gently tightens and loosens with the group.
    // Keep the current original-grain scale and occupancy; do not adjoin stars.
    float2 flow = jitter * (0.22 * 2.35 * 0.49) * organize;
    return float3(flow, smoothstep(0.30, 0.88, organize));
}

// Completion retains its previous fill/settle field. This revision targets only
// context compression; the renderer passes completion through quantumEnabled.z.
float3 activityQuantumCompletionClusters(float2 pixel, float2 resolution, float front, float phase) {
    // Staggered, short-lived star clusters form, loosen and re-form elsewhere.
    // Smooth envelopes hide reseeding; no tiles, aligned edges or solid glow layer.
    float width = max(resolution.x * front, 1.0);
    float count = clamp(ceil(width / 220.0), 1.0, 3.0);
    float highlight = 0.0;
    float2 flow = float2(0.0);
    for (int i = 0; i < 3; ++i) {
        if (float(i) >= count) { break; }
        float clock = phase / 4.8 - float(i) * 0.10;
        float generation = floor(clock);
        float age = fract(clock);
        float2 key = float2(generation, float(i) * 17.0);
        float rx = activityStateSmokeHash(key + 419.0);
        float ry = activityStateSmokeHash(key + 461.0);
        float life = smoothstep(0.0, 0.28, age) * (1.0 - smoothstep(0.65, 1.0, age));
        float gather = smoothstep(0.08, 0.48, age);
        float release = smoothstep(0.56, 1.0, age);
        float tightness = gather * (1.0 - release);
        // A shared curved spine gives neighbouring clusters a family resemblance.
        // Spacing and sequential gathering create order without rectangular cells.
        float slot = (float(i) + 0.40 + rx * 0.20) / count;
        float arc = slot * 4.2 + generation * 1.7;
        float2 center = float2(width * slot,
                              resolution.y * (0.50 + 0.38 * sin(arc)));
        center += float2(sin(age * 5.0 + ry * 6.28) * 9.0,
                         sin(age * 4.0 + rx * 6.28) * 5.0);
        float radius = mix(66.0, 35.0, tightness);
        float2 delta = pixel - center;
        float angle = atan2(resolution.y * 0.38 * 4.2 * cos(arc), width)
                    + sin(age * 3.0 + ry * 6.28) * 0.22;
        float2 local = float2(delta.x * cos(angle) + delta.y * sin(angle),
                            -delta.x * sin(angle) + delta.y * cos(angle));
        local /= float2(radius * (1.1 + rx * 0.35), radius * (0.75 + ry * 0.25));
        float theta = atan2(local.y, local.x);
        float contour = 1.0 + 0.14 * sin(theta * 3.0 + age * 5.0 + ry * 6.28)
                            + 0.08 * sin(theta * 5.0 - age * 3.0);
        float distance = length(local) / contour;
        float cluster = exp(-distance * distance * 1.6) * life;
        highlight += cluster * (0.70 + tightness * 0.90)
            * (1.0 - float(i) * 0.10);
        // A small continuous advection accompanies gathering and release, retaining
        // the original grain scale instead of collapsing the entire particle field.
        flow += delta / max(length(delta), 1.0) * cluster * tightness * 3.2;
    }
    return float3(flow, min(highlight, 1.5));
}

// Same grain geometry and interior occupancy as the original 0.4.6 drop field.
float activityQuantumGrain(float2 point, thread float2 &cell, thread float &seed) {
    float2 coordinate = point / 2.35;
    cell = floor(coordinate);
    seed = activityStateSmokeHash(cell + 31.0);
    float2 jitter = float2(activityStateSmokeHash(cell + 47.0),
                          activityStateSmokeHash(cell + 83.0)) - 0.5;
    float2 local = fract(coordinate) - 0.5 - jitter * 0.22;
    float radius = mix(0.17, 0.31, seed);
    float distance = length(local);
    float microDrop = 1.0 - smoothstep(radius, radius + 0.10, distance);
    float microBloom = exp(-max(distance - radius, 0.0) * 12.0);
    float occupancy = step(1.0 - 0.88, activityStateSmokeHash(cell + 151.0));
    return (microDrop + microBloom * 0.08) * occupancy;
}

float activityQuantumMotionDensity(float2 pixel, float2 resolution, float front,
                                  ActivityStateSmokeUniforms u) {
    float4 mode = u.quantumWeights;
    float phase = u.quantumClock.z;
    float failure = u.quantumClock.w;
    float3 clusters = u.quantumEnabled.z > 0.5
        ? activityQuantumCompletionClusters(pixel, resolution, front, phase)
        : activityQuantumCompressionClusters(pixel, resolution, front, phase);
    float2 point = pixel + u.quantumClock.xy + mode.z * clusters.xy;
    // State motion acts on the original fine-grain field, not on grain size/count.
    point.x += mode.x * sin(pixel.y * 0.044 + phase * 1.2) * 7.0
        + mode.z * sin(pixel.y * 0.037 + phase * 1.6) * 0.35;
    point.y += mode.x * sin(pixel.x * 0.023 + phase * 1.5) * 6.0
        + mode.z * sin(pixel.x * 0.028 - phase * 1.8) * 0.35;
    float2 cell;
    float seed;
    float particle = activityQuantumGrain(point, cell, seed);
    float activation = activityQuantumFrontCoverage(pixel, resolution, front, u.completionFillProgress);
    float packet = activityQuantumTransportPulse(pixel, resolution, front, phase);
    float restingWeight = max(0.0, 1.0 - dot(mode, float4(1.0)) - failure);
    float groupSeed = activityStateSmokeHash(floor(cell / 7.0) + 263.0);
    float twinkleRate = mix(2.4, 4.0, activityStateSmokeHash(cell + 197.0));
    float wave = 0.5 + 0.5 * sin(phase * twinkleRate + seed * 6.2831853);
    float sparkle = min((0.22 + wave * 0.62 + pow(wave, 5.0) * 0.16) * 1.10, 1.0);
    float threshold = activityStateSmokeHash(cell + 347.0) * 0.60;
    float dissolve = smoothstep(threshold, threshold + 0.40, activation);
    // Preserve the original ratio of dim/bright stars. State gestures modulate
    // that sparkle instead of imposing an always-bright floor on every point.
    float thinking = sparkle;
    float working = sparkle * (0.84 + 0.50 * packet);
    float compacting = sparkle * (u.quantumEnabled.z > 0.5
        ? 0.70 + 2.60 * clusters.z
        : 0.62 + 1.85 * pow(clusters.z, 2.0));
    float waiting = sparkle;
    float interrupted = sparkle * (0.90 + 0.16
        * (0.5 + 0.5 * sin(phase * 5.3 + groupSeed * 6.283185)));
    float intensity = restingWeight * 0.70 + mode.x * thinking + mode.y * working
        + mode.z * compacting + mode.w * waiting + failure * interrupted;
    return clamp(particle * intensity * dissolve * pow(activation, 0.55)
                 * u.quantumEnabled.y, 0.0, 1.0);
}

float3 activityQuantumMotionColor(float density, ActivityStateSmokeUniforms u) {
    float3 tint = mix(u.midColor.rgb, u.highlightColor.rgb, 0.26);
    tint /= max(max(tint.r, max(tint.g, tint.b)), 0.001);
    float minimum = min(tint.r, min(tint.g, tint.b));
    // Keep the compression state's neutral silver; only chromatic states gain saturation.
    float chromatic = smoothstep(0.12, 0.45, 1.0 - minimum);
    float neutral = minimum * 0.85 * chromatic;
    tint = max((tint - neutral) / max(1.0 - neutral, 0.001), float3(0.0));
    float luminance = dot(tint, float3(0.2126, 0.7152, 0.0722));
    float target = 0.54;
    tint = luminance < target
        ? mix(tint, float3(1.0), (target - luminance) / max(1.0 - luminance, 0.001))
        : tint * target / max(luminance, 0.001);
    // Stronger color in each star, with more exposure in the dim/mid range.
    // Neutral silver stays neutral; zero-density gaps and the front dissolve stay black.
    tint = pow(tint, float3(mix(1.0, 1.50, chromatic)));
    // Original microBloom is very faint. Do not let the brighter transfer curve
    // amplify it into a veil between the original fine, closely spaced stars.
    float light = pow(max(density, 0.0), 0.78) * smoothstep(0.03, 0.18, density);
    float exposure = mix(1.55, 1.78, chromatic) * (1.0 + u.quantumClock.w * 0.12);
    float3 enhanced = u.background.rgb + tint * light * exposure
        + tint * light * u.completionEffectHighlight;
    // Match the original VISIBLE warm gold, including density-dependent highlights
    // and energy. The same native opacity/compositing pipeline follows both paths.
    float3 reference = activityQuantumOriginalColor(density, u);
    // Breathe AFTER the original transfer so dimming cannot shift gold toward red.
    float breath = 0.65 + 0.35 * (0.5 + 0.5 * sin(u.quantumClock.z * 2.618));
    reference = u.background.rgb + (reference - u.background.rgb) * breath;
    return mix(enhanced, reference,
               clamp(u.quantumWeights.w, 0.0, 1.0));
}

float activityProgressSloshDensity(
    float2 uv,
    float front,
    float time,
    float pulse,
    float turbulence
) {
    float verticalPhase = (uv.y - 0.5) * 6.2831853;
    float primaryWave =
        sin(verticalPhase * 1.10 - time * 1.40) * 0.026;
    float secondaryWave =
        sin(verticalPhase * 2.30 + time * 0.82 + 1.7) * 0.012;
    float localPulse = (pulse - 0.5) * 0.012;
    float boundary = front
        + (primaryWave + secondaryWave + localPulse)
            * (0.72 + turbulence * 0.28);
    float fill = 1.0 - smoothstep(
        boundary - 0.055,
        boundary + 0.018,
        uv.x
    );
    float frontDistance = abs(uv.x - boundary);
    float crest = exp(-frontDistance * 42.0);
    float firstEcho = exp(-abs(uv.x - (boundary - 0.082)) * 31.0);
    float secondEcho = exp(-abs(uv.x - (boundary - 0.164)) * 23.0);
    float fluidNoise = activityStateSmokeFBM(
        float2(
            uv.x * 4.2 - time * 0.22,
            uv.y * 3.4 + time * 0.10
        )
    );
    float caustic = smoothstep(0.34, 0.68, fluidNoise);
    float body = fill * (0.50 + caustic * 0.38);
    return clamp(
        body
            + crest * (0.76 + pulse * 0.20)
            + firstEcho * fill * 0.34
            + secondEcho * fill * 0.18,
        0.0,
        1.0
    );
}

fragment float4 activityStateSmokeFragment(
    VertexOut in [[stage_in]],
    constant ActivityStateSmokeUniforms &u [[buffer(0)]]
) {
    float2 resolution = max(u.resolution, float2(1.0));
    float2 pixel = floor(in.uv * resolution) + 0.5;
    float2 uv = pixel / resolution;
    float aspect = resolution.x / resolution.y;
    float2 p = float2(uv.x * aspect, uv.y);

    float boundedFront = clamp(u.frontPosition, 0.0, 0.95);
    float completionFront = mix(
        boundedFront,
        1.12,
        clamp(u.completionFillProgress, 0.0, 1.0)
    );
    float front = aspect * completionFront;
    float frontDistance = p.x - front;
    float2 samplePoint = float2(
        p.x * 1.3 - u.fieldTime * 0.12,
        uv.y * 2.0 + u.fieldTime * 0.035
    );
    float warp = activityStateSmokeFBM(
        samplePoint * 1.7
    );
    float noise = activityStateSmokeFBM(
        samplePoint
            + float2(warp * (0.95 + u.turbulence))
    );
    float density = activityStateSmokeReverseSmoothstep(
        0.62,
        0.05,
        (p.x - front) * 1.4
            + (0.5 - noise)
                * (1.15 + u.turbulence * 0.65)
    );
    float diffusionSpeedPhase =
        u.fieldTime * (1.25 + u.diffusion * 0.55);
    float diffusionClock =
        u.fieldTime * u.diffusionSpeed
        + sin(diffusionSpeedPhase)
            * u.diffusionSpeedVariation;
    float broadPlumeNoise = activityStateSmokeFBM(
        float2(
            frontDistance * (0.62 + u.diffusion * 0.15)
                - diffusionClock * 0.28,
            uv.y * (1.15 + u.diffusion * 0.35)
                + diffusionClock * 0.07
        )
            + float2(2.7, -1.9)
            + warp * 0.32
    );
    float finePlumeNoise = activityStateSmokeFBM(
        float2(
            frontDistance * (1.35 + u.diffusion * 0.50)
                - diffusionClock * 0.62,
            uv.y * (3.10 + u.diffusion * 0.45)
                - diffusionClock * 0.18
        )
            + float2(-1.4, 3.6)
            + noise * 0.28
    );
    float plumeFrontModulation =
        (broadPlumeNoise - 0.5) * 0.11 * u.diffusion;
    float plumeGate = smoothstep(
        -0.055,
        0.075,
        frontDistance + plumeFrontModulation
    );
    float spreadPulse =
        0.78
        + 0.22
            * sin(
                diffusionClock * 2.4
                + broadPlumeNoise * 6.2831853
            );
    float plumeEnvelope = exp(
        -max(frontDistance, 0.0)
            * (2.35 - u.diffusion * 0.75)
            / max(spreadPulse, 0.50)
    );
    float plumeWisps = smoothstep(
        0.38,
        0.72,
        broadPlumeNoise * 0.58
            + finePlumeNoise * 0.42
            + noise * 0.16
    );
    float terminalDiffusion =
        plumeGate
        * plumeEnvelope
        * plumeWisps
        * (0.14 + u.diffusion * 0.66);
    density = clamp(max(density, terminalDiffusion), 0.0, 1.0);
    if (u.effectStyle > 0.5 && u.effectStyle < 1.5) {
        density = activityProgressDiamondDensity(
            uv,
            aspect,
            completionFront,
            u.fieldTime,
            u.pulse,
            u.turbulence
        );
    } else if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
        density = activityQuantumMotionDensity(pixel, resolution, completionFront, u);
    } else if (u.effectStyle >= 2.5) {
        density = activityProgressSloshDensity(
            uv,
            completionFront,
            u.fieldTime,
            u.pulse,
            u.turbulence
        );
    }
    if (u.effectStyle > 0.5) {
        float effectProgressGate = mix(
            smoothstep(0.0005, 0.012, boundedFront),
            1.0,
            clamp(u.completionActive, 0.0, 1.0)
        );
        density *= effectProgressGate;
    }
    float breathing = 1.0 + (u.pulse - 0.5) * 0.18;

    float3 color = u.background.rgb;
    color += u.deepColor.rgb * density * 0.72 * u.energy;
    color +=
        u.midColor.rgb
        * pow(density, 2.2)
        * 0.68
        * u.energy;
    color +=
        u.highlightColor.rgb
        * pow(density, 7.0)
        * 0.55
        * breathing
        * u.energy;
    if (u.effectStyle > 0.5) {
        float completionHighlightDensity = pow(density, 3.0);
        if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
            completionHighlightDensity = pow(density, 1.5);
        }
        color +=
            u.highlightColor.rgb
            * completionHighlightDensity
            * clamp(u.completionEffectHighlight, 0.0, 1.0)
            * u.energy;
    }
    if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
        color = activityQuantumMotionColor(density, u);
    }
    color = mix(
        color,
        u.background.rgb * 0.62,
        clamp(u.completionDarkening, 0.0, 1.0)
    );
    color += (activityStateSmokeHash(pixel) - 0.5) * u.grain;
    float opacityFront = max(
        boundedFront,
        1.0 / resolution.x
    );
    float smokeRelativeX = clamp(
        uv.x / opacityFront,
        0.0,
        1.0
    );
    float normalHorizontalOpacity = activityStateSmokeHorizontalOpacity(
        smokeRelativeX,
        u.opacityStopPositions,
        u.opacityStopOpacities
    );
    float horizontalOpacity = mix(
        normalHorizontalOpacity,
        1.0,
        clamp(u.completionActive, 0.0, 1.0)
    );
    float smokeOpacity =
        clamp(u.completionSmokeOpacity, 0.0, 1.0)
        * horizontalOpacity;
    return float4(max(color, 0.0) * smokeOpacity, smokeOpacity);
}
"""

private enum ActivityStateSmokeRendererError: Error {
    case unavailableMetal
    case missingCommandQueue
    case missingFunction
}

private enum ActivityStateSmokePipeline {
    private static let cache = ActivityStateSmokePipelineCache()

    static func make(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        try cache.pipeline(device: device, pixelFormat: pixelFormat)
    }
}

private final class ActivityStateSmokePipelineCache {
    private struct Key: Hashable {
        let registryID: UInt64
        let pixelFormat: UInt
    }

    private let lock = NSLock()
    private var pipelines: [Key: MTLRenderPipelineState] = [:]

    func pipeline(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let key = Key(
            registryID: device.registryID,
            pixelFormat: pixelFormat.rawValue
        )

        lock.lock()
        if let pipeline = pipelines[key] {
            lock.unlock()
            return pipeline
        }
        lock.unlock()

        let library = try device.makeLibrary(
            source: activityStateSmokeShaderSource,
            options: MTLCompileOptions()
        )
        guard let vertex = library.makeFunction(
            name: "activityStateSmokeVertex"
        ), let fragment = library.makeFunction(
            name: "activityStateSmokeFragment"
        ) else {
            throw ActivityStateSmokeRendererError.missingFunction
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "QuotaView State Smoke"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        let pipeline = try device.makeRenderPipelineState(
            descriptor: descriptor
        )

        lock.lock()
        let result = pipelines[key] ?? pipeline
        pipelines[key] = result
        lock.unlock()
        return result
    }
}

private final class ActivityStateSmokeRenderer:
    NSObject,
    MTKViewDelegate
{
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var simulation = CodexActivityStateSmokeSimulation()
    private var quantumMotion = ActivityQuantumMotion()
    private var completionTransition =
        CodexActivityStateSmokeCompletionTransition()
    private var currentProfile =
        CodexActivityStateSmokeProfile.profile(
            for: CodexActivityStateSmokeContract.previewState
        )
    private var targetProfile =
        CodexActivityStateSmokeProfile.profile(
            for: CodexActivityStateSmokeContract.previewState
        )
    private var state = CodexActivityStateSmokeContract.previewState
    private var effect =
        AppPreferences.CodexActivityProgressEffect.stateSmoke
    private var approximateProgressFraction: Double?
    private var progressProjection =
        CodexActivityStateSmokeProgressProjection()
    private var progressResolver =
        CodexActivityStateSmokeProgressResolver()
    private var lastFrameAt = CACurrentMediaTime()
    private var reduceMotion = false
    private var playbackEnabled = true

    init(view: MTKView) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ActivityStateSmokeRendererError.unavailableMetal
        }
        guard let queue = device.makeCommandQueue() else {
            throw ActivityStateSmokeRendererError.missingCommandQueue
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.wantsLayer = true
        view.layer?.isOpaque = false

        commandQueue = queue
        pipeline = try ActivityStateSmokePipeline.make(
            device: device,
            pixelFormat: view.colorPixelFormat
        )
        super.init()
        view.delegate = self
    }

    func setPlaybackEnabled(_ enabled: Bool, in view: MTKView) {
        guard playbackEnabled != enabled else { return }
        playbackEnabled = enabled
        applyPlaybackState(in: view)
    }

    func setReduceMotion(_ enabled: Bool, in view: MTKView) {
        guard reduceMotion != enabled else { return }
        reduceMotion = enabled
        if enabled {
            currentProfile = targetProfile
            if state == .completed {
                completionTransition.finish()
            }
        }
        applyPlaybackState(in: view)
    }

    func setState(
        _ newState: CodexActivityVisualState,
        taskIdentity newIdentity: CodexActivityTaskIdentity? = nil,
        in view: MTKView
    ) {
        let changedTask = progressProjection.bindTask(newIdentity)
        guard state != newState || changedTask else { return }
        let previousState = state
        let startsFreshProgress = changedTask || newState.activityStartsFreshProgress(
            after: previousState
        )
        state = newState
        if startsFreshProgress || newState.activityClearsProgress {
            progressProjection.reset()
            progressResolver.reset()
        }
        if startsFreshProgress {
            simulation.resetEffectTime()
        }
        if newState == .completed {
            completionTransition.enter()
            if reduceMotion {
                completionTransition.finish()
            }
        } else {
            completionTransition.reset()
        }
        targetProfile = CodexActivityStateSmokeProfile.profile(
            for: newState,
            effect: effect
        )
        if reduceMotion {
            currentProfile = targetProfile
        }
        applyPlaybackState(in: view)
    }

    func setEffect(
        _ newEffect: AppPreferences.CodexActivityProgressEffect,
        in view: MTKView
    ) {
        guard effect != newEffect else { return }
        effect = newEffect
        targetProfile = CodexActivityStateSmokeProfile.profile(
            for: state,
            effect: effect
        )
        if reduceMotion {
            currentProfile = targetProfile
        }
        if playbackEnabled && view.isPaused {
            view.needsDisplay = true
        }
    }

    func setApproximateProgress(
        _ fraction: Double?,
        in view: MTKView
    ) {
        let normalized = fraction.flatMap { value -> Double? in
            guard value.isFinite else { return nil }
            return min(max(value, 0), 1)
        }
        guard approximateProgressFraction != normalized else { return }
        approximateProgressFraction = normalized
        if playbackEnabled && view.isPaused {
            view.needsDisplay = true
        }
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}

    func draw(in view: MTKView) {
        guard playbackEnabled,
              view.drawableSize.width > 0,
              view.drawableSize.height > 0,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: descriptor
              )
        else {
            return
        }

        let now = CACurrentMediaTime()
        let elapsed = Float(min(max(now - lastFrameAt, 0), 0.25))
        let snapshot: CodexActivityStateSmokeSnapshot
        let completionSnapshot:
            CodexActivityStateSmokeCompletionSnapshot
        if reduceMotion {
            currentProfile = targetProfile
            snapshot =
                CodexActivityStateSmokeSimulation
                .reducedMotionSnapshot
            completionSnapshot =
                state == .completed
                ? .reducedMotion
                : .inactive
        } else {
            let profileTransitionRate: Float =
                state == .completed ? 9.0 : 4.2
            let transition = 1 - exp(-profileTransitionRate * elapsed)
            currentProfile = currentProfile.interpolated(
                to: targetProfile,
                amount: transition
            )
            snapshot = simulation.advance(
                elapsed: elapsed,
                profile: currentProfile,
                effectPlaybackEnabled:
                    state.activityAnimatesQuantumNoise
            )
            completionSnapshot = completionTransition.advance(
                elapsed: elapsed
            )
        }
        lastFrameAt = now
        quantumMotion.advance(state: state, elapsed: elapsed, reduceMotion: reduceMotion)

        let resolvedApproximateProgress = progressResolver.resolve(
            state: state,
            plannedFraction: approximateProgressFraction,
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
        let frontPosition = progressProjection.resolve(
            approximateProgressFraction: resolvedApproximateProgress,
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )

        if reduceMotion,
           progressResolver.mode != .resolvingPlan,
           !view.isPaused
        {
            applyPlaybackState(in: view)
        }

        var uniforms = ActivityStateSmokeUniforms(
            resolution: SIMD2<Float>(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            frontPosition: frontPosition,
            pulse:
                0.5
                + (snapshot.pulse - 0.5) * currentProfile.pulse,
            fieldTime: snapshot.fieldTime,
            effectTime: snapshot.effectTime,
            turbulence: currentProfile.turbulence,
            energy: currentProfile.energy,
            diffusion: currentProfile.diffusion,
            diffusionSpeed: currentProfile.diffusionSpeed,
            diffusionSpeedVariation:
                currentProfile.diffusionSpeedVariation,
            grain: CodexActivityStateSmokeContract.grain,
            effectStyle: effect.shaderIndex,
            completionFillProgress:
                completionSnapshot.fillProgress,
            completionEffectHighlight:
                completionSnapshot.effectHighlight
                * CodexActivityStateSmokeContract
                    .completionHighlightIntensity(for: effect),
            completionDarkening: completionSnapshot.darkening,
            completionSmokeOpacity: completionSnapshot.smokeOpacity,
            completionActive: state == .completed ? 1 : 0,
            quantumWeights: quantumMotion.profile.weights,
            quantumClock: SIMD4<Float>(quantumMotion.displacement.x,
                quantumMotion.displacement.y, quantumMotion.phase, quantumMotion.profile.failure),
            quantumEnabled: SIMD4<Float>(1, quantumMotion.profile.visibility,
                state == .completed ? 1 : 0, 0),
            opacityStopPositions: currentProfile.opacityCurve.stopPositions,
            opacityStopOpacities: currentProfile.opacityCurve.stopOpacities,
            background: currentProfile.background,
            deepColor: currentProfile.deepColor,
            midColor: currentProfile.midColor,
            highlightColor: currentProfile.highlightColor
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<ActivityStateSmokeUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if state == .completed,
           completionSnapshot.smokeOpacity <= 0.001,
           !reduceMotion
        {
            view.enableSetNeedsDisplay = true
            view.isPaused = true
        }
    }

    private func applyPlaybackState(in view: MTKView) {
        let completionSettled =
            state == .completed
            && completionTransition.snapshot.smokeOpacity <= 0.001
        let resolvingPlanWithoutMotion =
            reduceMotion
            && state.activitySupportsUnplannedProgress
            && approximateProgressFraction == nil
            && (progressResolver.mode == .inactive
                || progressResolver.mode == .resolvingPlan)
        let shouldAnimate =
            playbackEnabled
            && (!reduceMotion || resolvingPlanWithoutMotion)
            && !completionSettled
        lastFrameAt = CACurrentMediaTime()
        view.enableSetNeedsDisplay = !shouldAnimate
        view.isPaused = !shouldAnimate
        if playbackEnabled {
            view.needsDisplay = true
        }
    }
}

final class ActivityStateSmokeMetalView: MTKView {
    private var smokeRenderer: ActivityStateSmokeRenderer?

    var isRendererAvailable: Bool {
        smokeRenderer != nil
    }

    init(frame: NSRect) {
        super.init(frame: frame, device: nil)
        smokeRenderer = try? ActivityStateSmokeRenderer(view: self)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        smokeRenderer?.setPlaybackEnabled(enabled, in: self)
    }

    func setReduceMotion(_ enabled: Bool) {
        smokeRenderer?.setReduceMotion(enabled, in: self)
    }

    func setState(_ state: CodexActivityVisualState, taskIdentity: CodexActivityTaskIdentity? = nil) {
        smokeRenderer?.setState(state, taskIdentity: taskIdentity, in: self)
    }

    func setEffect(
        _ effect: AppPreferences.CodexActivityProgressEffect
    ) {
        smokeRenderer?.setEffect(effect, in: self)
    }

    func setApproximateProgress(_ fraction: Double?) {
        smokeRenderer?.setApproximateProgress(fraction, in: self)
    }

    func redrawIfPaused() {
        if isPaused {
            needsDisplay = true
        }
    }
}

final class CodexActivityStateSmokePreviewHostView: NSView {
    private let smokeView = ActivityStateSmokeMetalView(frame: .zero)

    override var isOpaque: Bool { false }

    init(
        frame frameRect: NSRect,
        effect: AppPreferences.CodexActivityProgressEffect
    ) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(smokeView)
        smokeView.preferredFramesPerSecond = 30
        smokeView.setState(CodexActivityStateSmokeContract.previewState)
        smokeView.setEffect(effect)
        smokeView.setApproximateProgress(
            CodexActivityStateSmokeContract.previewProgressFraction
        )
    }

    convenience init(
        effect: AppPreferences.CodexActivityProgressEffect
    ) {
        self.init(frame: .zero, effect: effect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        smokeView.setPlaybackEnabled(window != nil)
    }

    override func layout() {
        super.layout()
        smokeView.frame = bounds
        smokeView.layer?.cornerRadius = min(
            bounds.width,
            bounds.height
        ) * 0.18
        smokeView.layer?.cornerCurve = .continuous
        smokeView.layer?.masksToBounds = true
        smokeView.redrawIfPaused()
    }

    func update(
        effect: AppPreferences.CodexActivityProgressEffect,
        reduceMotion: Bool
    ) {
        smokeView.setEffect(effect)
        smokeView.setReduceMotion(reduceMotion)
        smokeView.setApproximateProgress(
            CodexActivityStateSmokeContract.previewProgressFraction
        )
        smokeView.setPlaybackEnabled(window != nil)
    }
}
