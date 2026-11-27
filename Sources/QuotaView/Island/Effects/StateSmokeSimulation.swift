import Foundation
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
    var usesCardCompletion = false
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
        let fillDuration = CodexActivityStateSmokeContract.completionFillDuration
        let fadeDelay = usesCardCompletion ? fillDuration * 0.65 : CodexActivityStateSmokeContract.completionSmokeFadeDelay
        let fadeDuration = usesCardCompletion ? fillDuration - fadeDelay : CodexActivityStateSmokeContract.completionSmokeFadeDuration
        let fadeLinear = min(
            max(
                (elapsed - fadeDelay) / fadeDuration,
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

// Shader evaluation crossfades the final eight units into the next epoch.
// Keep this period in sync with the loop in CodexActivityStateSmokeShader.txt.
struct ActivityEffectClock {
    static let period: Double = 256
    private(set) var value: Double = 0

    mutating func advance(_ delta: Double) {
        guard delta.isFinite, delta >= 0 else { return }
        value = (value + delta.truncatingRemainder(dividingBy: Self.period))
            .truncatingRemainder(dividingBy: Self.period)
    }
}

struct CodexActivityStateSmokeSimulation {
    private var fieldClock = ActivityEffectClock()
    private var effectClock = ActivityEffectClock()
    var fieldTime: Float { Float(fieldClock.value) }
    var effectTime: Float { Float(effectClock.value) }
    private(set) var pulse: Float = 0.5

    private var motionPhase: Double = 0
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
        guard delta.isFinite else { return }
        let safeDelta = Double(max(delta, 0))
        motionPhase = (motionPhase + safeDelta * Double(profile.motionFrequency) * .pi * 2 * 1.9)
            .truncatingRemainder(dividingBy: .pi * 2)
        fieldClock.advance(safeDelta * Double(profile.fieldSpeed))
        if effectPlaybackEnabled {
            effectClock.advance(safeDelta * Double(CodexActivityStateSmokeContract.quantumNoiseEffectClockRate))
        }
        pulse = Float(0.5 + 0.5 * sin(motionPhase + 0.35))
    }

    mutating func resetEffectTime() {
        effectClock = ActivityEffectClock()
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

extension CodexActivityVisualState {
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
    // Exact lattice period, not an arbitrary pixel modulus. The shader wraps
    // particle identity at 4096 cells, including neighbourhood seeds.
    static let displacementPeriod: Double = 4096 * 2.35
    private var position = SIMD2<Double>.zero
    private var clock = ActivityEffectClock()
    var displacement: SIMD2<Float> { SIMD2<Float>(Float(position.x), Float(position.y)) }
    var phase: Float { Float(clock.value) }

    mutating func advance(state: CodexActivityVisualState, elapsed: Float,
                          reduceMotion: Bool) {
        guard elapsed.isFinite else { return }
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
            position += SIMD2<Double>(Double(profile.velocity.x), Double(profile.velocity.y)) * Double(dt)
            for axis in 0..<2 {
                position[axis].formTruncatingRemainder(dividingBy: Self.displacementPeriod)
            }
            clock.advance(Double(profile.rate) * Double(dt))
        }
    }
}
