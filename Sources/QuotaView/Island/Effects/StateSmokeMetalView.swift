import AppKit
import MetalKit
import QuartzCore
import QuotaViewCore
import simd

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

let activityStateSmokeShaderSource: String = {
    #if SWIFT_PACKAGE
    let bundle = Bundle.main.resourceURL
        .flatMap { Bundle(url: $0.appendingPathComponent("QuotaView_QuotaView.bundle")) }
        ?? Bundle.module
    #else
    let bundle = Bundle.main
    #endif

    guard let url = bundle.url(forResource: "CodexActivityStateSmokeShader", withExtension: "txt"),
          let source = try? String(contentsOf: url, encoding: .utf8) else {
        return ""
    }
    return source
}()

private enum ActivityStateSmokeRendererError: Error {
    case unavailableMetal
    case missingCommandQueue
    case missingFunction
    case missingShader
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

        guard !activityStateSmokeShaderSource.isEmpty else {
            throw ActivityStateSmokeRendererError.missingShader
        }
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
    private var fullSurface = false

    init(view: MTKView, taskCard: Bool) throws {
        completionTransition.usesCardCompletion = taskCard
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

    func setFullSurfacePresentation(_ enabled: Bool, in view: MTKView) {
        guard fullSurface != enabled else { return }
        fullSurface = enabled
        view.preferredFramesPerSecond = enabled ? 30 : 60
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
            for: completionTransition.usesCardCompletion && newState == .completed ? previousState : newState,
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

    var displayedProgressPosition: Float? { progressProjection.displayedFrontPosition }
    var playbackClockReference: CFTimeInterval { lastFrameAt }
    func restoreProgressPosition(_ fraction: Double?) {
        // A newly mounted card resumes its task's position without replaying 0 -> p.
        _ = progressProjection.resolve(approximateProgressFraction: fraction, elapsed: 0, reduceMotion: true)
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
        let completingCard = completionTransition.usesCardCompletion && state == .completed
        quantumMotion.advance(state: completingCard ? .working : state, elapsed: elapsed, reduceMotion: reduceMotion)

        let resolvedApproximateProgress = fullSurface ? nil : progressResolver.resolve(
            state: state,
            plannedFraction: approximateProgressFraction,
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
        let frontPosition: Float = fullSurface ? 1 : progressProjection.resolve(
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
                completingCard ? 0 : completionSnapshot.effectHighlight
                * CodexActivityStateSmokeContract
                    .completionHighlightIntensity(for: effect),
            completionDarkening: completionSnapshot.darkening,
            completionSmokeOpacity: completionSnapshot.smokeOpacity,
            completionActive: state == .completed ? 1 : 0,
            quantumWeights: quantumMotion.profile.weights,
            quantumClock: SIMD4<Float>(quantumMotion.displacement.x,
                quantumMotion.displacement.y, quantumMotion.phase, quantumMotion.profile.failure),
            quantumEnabled: SIMD4<Float>(1, quantumMotion.profile.visibility,
                state == .completed && !completingCard ? 1 : 0, fullSurface ? 1 : 0),
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
            && !fullSurface
            && state.activitySupportsUnplannedProgress
            && approximateProgressFraction == nil
            && (progressResolver.mode == .inactive
                || progressResolver.mode == .resolvingPlan)
        let shouldAnimate =
            playbackEnabled
            && (!reduceMotion || resolvingPlanWithoutMotion)
            && !completionSettled
        // Running-state/profile changes preserve the interval until the next
        // frame. Only a real pause/resume boundary discards inactive wall time.
        if view.isPaused != !shouldAnimate {
            lastFrameAt = CACurrentMediaTime()
            view.enableSetNeedsDisplay = !shouldAnimate
            view.isPaused = !shouldAnimate
        }
        if playbackEnabled && view.isPaused {
            view.needsDisplay = true
        }
    }
}

final class ActivityStateSmokeMetalView: MTKView {
    private var smokeRenderer: ActivityStateSmokeRenderer?
    private(set) var fullSurfacePresentation = false

    var isRendererAvailable: Bool {
        smokeRenderer != nil
    }

    init(frame: NSRect, taskCard: Bool = false) {
        super.init(frame: frame, device: nil)
        smokeRenderer = try? ActivityStateSmokeRenderer(view: self, taskCard: taskCard)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        smokeRenderer?.setPlaybackEnabled(enabled, in: self)
    }

    func setFullSurfacePresentation(_ enabled: Bool) {
        fullSurfacePresentation = enabled
        smokeRenderer?.setFullSurfacePresentation(enabled, in: self)
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

    var displayedProgressPosition: Float? { smokeRenderer?.displayedProgressPosition }
    var playbackClockReference: CFTimeInterval? { smokeRenderer?.playbackClockReference }
    func restoreProgressPosition(_ fraction: Double?) { smokeRenderer?.restoreProgressPosition(fraction) }

    func redrawIfPaused() {
        if isPaused {
            needsDisplay = true
        }
    }
}

/// Settings-only renderer: bounded resolution and frame rate, no task lifecycle.
final class CodexActivityStateSmokePreviewHostView: NSView {
    private let smokeView = ActivityStateSmokeMetalView(frame: .zero)
    private var fallbackView: NSImageView?
    private var previewCornerRadius: CGFloat = 4
    private var requestedPlayback = false
    private var lastPlayback = false
    var isRendererAvailable: Bool { smokeView.isRendererAvailable }
    override var isOpaque: Bool { false }

    init(frame frameRect: NSRect, effect: AppPreferences.CodexActivityProgressEffect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(smokeView)
        smokeView.setPlaybackEnabled(false)
        smokeView.preferredFramesPerSecond = 24
        smokeView.autoResizeDrawable = false
        smokeView.setState(CodexActivityStateSmokeContract.previewState)
        smokeView.setEffect(effect)
        smokeView.setApproximateProgress(CodexActivityStateSmokeContract.previewProgressFraction)
        smokeView.restoreProgressPosition(CodexActivityStateSmokeContract.previewProgressFraction)
    }

    convenience init(effect: AppPreferences.CodexActivityProgressEffect) {
        self.init(frame: .zero, effect: effect)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: name, object: window)
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: name, object: NSApp)
            }
            var ancestor = superview
            while let view = ancestor {
                if let clip = view as? NSClipView {
                    clip.postsBoundsChangedNotifications = true
                    NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                        name: NSView.boundsDidChangeNotification, object: clip)
                }
                ancestor = view.superview
            }
        }
        synchronizePlayback()
    }
    override func viewDidHide() { super.viewDidHide(); synchronizePlayback() }
    override func viewDidUnhide() { super.viewDidUnhide(); synchronizePlayback() }
    @objc private func visibilityChanged(_ notification: Notification) { synchronizePlayback() }

    override func layout() {
        super.layout()
        if smokeView.frame != bounds { smokeView.frame = bounds }
        // One pixel per point is sufficient for these small decorative previews;
        // production task effects retain their independent rendering budget.
        let size = CGSize(width: max(1, ceil(bounds.width)), height: max(1, ceil(bounds.height)))
        if smokeView.drawableSize != size {
            smokeView.drawableSize = size
            smokeView.redrawIfPaused()
        }
        fallbackView?.frame = bounds
        synchronizePlayback()
    }

    private func synchronizePlayback() {
        let visible = requestedPlayback && window?.occlusionState.contains(.visible) == true
            && window?.isMiniaturized == false && !NSApp.isHidden && !isHiddenOrHasHiddenAncestor
            && !visibleRect.isEmpty && bounds.width > 0 && bounds.height > 0
        guard visible != lastPlayback else { return }
        lastPlayback = visible
        smokeView.setPlaybackEnabled(visible)
    }

    func update(effect: AppPreferences.CodexActivityProgressEffect, reduceMotion: Bool,
                cornerRadius: CGFloat = 4, playbackEnabled: Bool = true) {
        requestedPlayback = playbackEnabled
        if previewCornerRadius != cornerRadius {
            previewCornerRadius = max(0, cornerRadius)
        }
        layer?.cornerRadius = previewCornerRadius
        layer?.cornerCurve = .continuous
        // Clip the Metal surface itself as well as the fallback host so both
        // rendering paths retain the same inset corners.
        smokeView.layer?.cornerRadius = previewCornerRadius
        smokeView.layer?.cornerCurve = .continuous
        smokeView.layer?.masksToBounds = true
        smokeView.setEffect(effect)
        smokeView.setReduceMotion(reduceMotion)
        synchronizePlayback()
    }
    func setFallbackImage(_ image: NSImage?) {
        guard !isRendererAvailable else { return }
        if fallbackView == nil {
            let view = NSImageView(frame: bounds)
            view.imageScaling = .scaleAxesIndependently
            addSubview(view)
            fallbackView = view
        }
        fallbackView?.image = image
    }
    func stop() { requestedPlayback = false; synchronizePlayback() }
}
