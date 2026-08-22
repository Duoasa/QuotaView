import AppKit
import MetalKit
import QuartzCore
import QuotaViewCore
import simd

enum CodexActivityRippleGlowContract {
    static let uniformFloatCount = 128
    static let sphereRadius: Float = 0.535
    static let contourDeformation: Float = 0
    static let approvedSpeedMultiplier: Float = 1.5
}

private enum RippleGlowUniformLayout {
    static let floatCount =
        CodexActivityRippleGlowContract.uniformFloatCount
    static let sizeX = 0
    static let sizeY = 1
    static let time = 2
    static let speed = 3
    static let radius = 4
    static let warp = 6
    static let ridgeAmount = 7
    static let sharpness = 8
    static let exposure = 14
    static let style = 15
    static let glassEnabled = 19
    static let contourDeformation = 21
    static let colorA = 32
    static let colorB = 36
    static let colorC = 40
    static let colorD = 44
    static let highlightColor = 48
    static let shellInner = 52
    static let shellMid = 56
    static let shellEdge = 60
}

private let rippleGlowUniformSeed: [Float] = [
    1, 1, 0, 0.8199999928474426, 0.7200000286102295, 0.36000001430511475, 3.200000047683716, 0.5,
    2.200000047683716, 0.11999999731779099, 0.2800000011920929, 0.30000001192092896, 0.5699999928474426, 0.18000000715255737, 2, 9,
    0.004999999888241291, 0, 0, 1, 0.49000000953674316, 0, 2, 0.41999998688697815,
    0.7699999809265137, 0.23000000417232513, 65, 0, 0, 1, 0.2199999988079071, 0.25,
    1, 0.8470588326454163, 0.41960784792900085, 1, 0.5098039507865906, 0.95686274766922, 1, 1,
    1, 0.48235294222831726, 0.8352941274642944, 1, 0.5568627715110779, 0.42352941632270813, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    0.6078431606292725, 0.95686274766922, 1, 1, 0.772549033164978, 0.6627451181411743, 1, 1,
    0.9176470637321472, 0.95686274766922, 1, 1, 0.8627451062202454, 0.9176470637321472, 1, 1,
    0.0117647061124444, 0.01568627543747425, 0.03529411926865578, 1, 0.5843137502670288, 0.42352941632270813, 1, 1,
    0.9686274528503418, 0.9843137264251709, 1, 1, 0.9372549057006836, 0.9647058844566345, 0.9921568632125854, 1,
    0.8784313797950745, 0.9333333373069763, 0.9764705896377563, 1, 0.8313725590705872, 0.9019607901573181, 0.9686274528503418, 1,
    0.7333333492279053, 0.8352941274642944, 0.9529411792755127, 1, 0.6509804129600525, 0.7803921699523926, 0.9411764740943909, 1,
    0.529411792755127, 0.6901960968971252, 0.9215686321258545, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
]

private struct RippleGlowRGBA {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float

    init(
        _ red: Float,
        _ green: Float,
        _ blue: Float,
        _ alpha: Float = 1
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

private struct RippleGlowConfiguration {
    let primary: RippleGlowRGBA
    let secondary: RippleGlowRGBA
    let accent: RippleGlowRGBA
    let upperHighlight: RippleGlowRGBA
    let highlight: RippleGlowRGBA
    let speed: Float
    let warp: Float
    let ridgeAmount: Float
    let sharpness: Float
    let exposure: Float

    func uniforms() -> [Float] {
        var result = rippleGlowUniformSeed
        result[RippleGlowUniformLayout.speed] =
            speed
            * CodexActivityRippleGlowContract.approvedSpeedMultiplier
        result[RippleGlowUniformLayout.radius] =
            CodexActivityRippleGlowContract.sphereRadius
        result[RippleGlowUniformLayout.warp] = warp
        result[RippleGlowUniformLayout.ridgeAmount] = ridgeAmount
        result[RippleGlowUniformLayout.sharpness] = sharpness
        result[RippleGlowUniformLayout.exposure] = exposure
        result[RippleGlowUniformLayout.style] = 9
        result[RippleGlowUniformLayout.glassEnabled] = 1
        result[RippleGlowUniformLayout.contourDeformation] =
            CodexActivityRippleGlowContract.contourDeformation
        result.setRippleGlowColor(primary, at: RippleGlowUniformLayout.colorA)
        result.setRippleGlowColor(
            secondary,
            at: RippleGlowUniformLayout.colorB
        )
        result.setRippleGlowColor(accent, at: RippleGlowUniformLayout.colorC)
        result.setRippleGlowColor(
            upperHighlight,
            at: RippleGlowUniformLayout.colorD
        )
        result.setRippleGlowColor(
            highlight,
            at: RippleGlowUniformLayout.highlightColor
        )
        result.setRippleGlowColor(
            highlight,
            at: RippleGlowUniformLayout.shellInner
        )
        result.setRippleGlowColor(accent, at: RippleGlowUniformLayout.shellMid)
        result.setRippleGlowColor(
            secondary,
            at: RippleGlowUniformLayout.shellEdge
        )
        return result
    }
}

private extension Array where Element == Float {
    mutating func setRippleGlowColor(
        _ color: RippleGlowRGBA,
        at offset: Int
    ) {
        self[offset] = color.red
        self[offset + 1] = color.green
        self[offset + 2] = color.blue
        self[offset + 3] = color.alpha
    }
}

private extension CodexActivityVisualState {
    var rippleGlowConfiguration: RippleGlowConfiguration {
        switch self {
        case .disconnectedCodex:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.13, 0.17, 0.24),
                secondary: RippleGlowRGBA(0.28, 0.34, 0.44),
                accent: RippleGlowRGBA(0.48, 0.57, 0.70),
                upperHighlight: RippleGlowRGBA(0.68, 0.74, 0.84),
                highlight: RippleGlowRGBA(0.86, 0.90, 0.96),
                speed: 0.24,
                warp: 1.6,
                ridgeAmount: 0.22,
                sharpness: 1.7,
                exposure: 1.45
            )
        case .standby:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.12, 0.23, 0.42),
                secondary: RippleGlowRGBA(0.25, 0.35, 0.58),
                accent: RippleGlowRGBA(0.44, 0.56, 0.75),
                upperHighlight: RippleGlowRGBA(0.66, 0.76, 0.94),
                highlight: RippleGlowRGBA(0.90, 0.94, 1.00),
                speed: 0.32,
                warp: 1.9,
                ridgeAmount: 0.28,
                sharpness: 1.8,
                exposure: 1.55
            )
        case .thinking:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.20, 0.12, 0.68),
                secondary: RippleGlowRGBA(0.50, 0.23, 0.88),
                accent: RippleGlowRGBA(0.34, 0.57, 1.00),
                upperHighlight: RippleGlowRGBA(0.79, 0.48, 1.00),
                highlight: RippleGlowRGBA(0.96, 0.91, 1.00),
                speed: 0.82,
                warp: 3.2,
                ridgeAmount: 0.50,
                sharpness: 2.2,
                exposure: 2.00
            )
        case .working:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.04, 0.30, 0.78),
                secondary: RippleGlowRGBA(0.02, 0.65, 0.90),
                accent: RippleGlowRGBA(0.28, 0.94, 0.84),
                upperHighlight: RippleGlowRGBA(0.64, 1.00, 0.96),
                highlight: RippleGlowRGBA(0.92, 1.00, 1.00),
                speed: 1.15,
                warp: 3.8,
                ridgeAmount: 0.68,
                sharpness: 2.5,
                exposure: 2.05
            )
        case .compactingContext:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.50, 0.56, 0.66),
                secondary: RippleGlowRGBA(0.82, 0.86, 0.93),
                accent: RippleGlowRGBA(0.98, 0.98, 1.00),
                upperHighlight: RippleGlowRGBA(0.68, 0.76, 0.90),
                highlight: RippleGlowRGBA(1.00, 1.00, 1.00),
                speed: 0.72,
                warp: 2.9,
                ridgeAmount: 0.62,
                sharpness: 2.6,
                exposure: 1.82
            )
        case .awaitingConfirmation:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.55, 0.21, 0.02),
                secondary: RippleGlowRGBA(0.95, 0.46, 0.05),
                accent: RippleGlowRGBA(1.00, 0.78, 0.22),
                upperHighlight: RippleGlowRGBA(1.00, 0.56, 0.12),
                highlight: RippleGlowRGBA(1.00, 0.94, 0.72),
                speed: 0.48,
                warp: 2.3,
                ridgeAmount: 0.38,
                sharpness: 2.0,
                exposure: 1.86
            )
        case .completed:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.02, 0.38, 0.22),
                secondary: RippleGlowRGBA(0.05, 0.70, 0.40),
                accent: RippleGlowRGBA(0.36, 0.95, 0.65),
                upperHighlight: RippleGlowRGBA(0.54, 1.00, 0.79),
                highlight: RippleGlowRGBA(0.90, 1.00, 0.95),
                speed: 0.36,
                warp: 1.8,
                ridgeAmount: 0.30,
                sharpness: 1.8,
                exposure: 1.70
            )
        case .error:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.55, 0.01, 0.05),
                secondary: RippleGlowRGBA(0.92, 0.08, 0.14),
                accent: RippleGlowRGBA(1.00, 0.36, 0.22),
                upperHighlight: RippleGlowRGBA(1.00, 0.58, 0.18),
                highlight: RippleGlowRGBA(1.00, 0.88, 0.82),
                speed: 0.96,
                warp: 3.9,
                ridgeAmount: 0.74,
                sharpness: 2.8,
                exposure: 1.98
            )
        case .unavailable:
            RippleGlowConfiguration(
                primary: RippleGlowRGBA(0.23, 0.25, 0.30),
                secondary: RippleGlowRGBA(0.36, 0.38, 0.43),
                accent: RippleGlowRGBA(0.50, 0.53, 0.58),
                upperHighlight: RippleGlowRGBA(0.62, 0.64, 0.68),
                highlight: RippleGlowRGBA(0.78, 0.80, 0.84),
                speed: 0.08,
                warp: 0.8,
                ridgeAmount: 0.08,
                sharpness: 1.4,
                exposure: 1.20
            )
        }
    }
}

private enum RippleGlowRendererError: Error {
    case missingShader
    case invalidShader
    case unavailableMetal
    case missingFunction
    case missingCommandQueue
}

private enum RippleGlowShaderResource {
    static func source() throws -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(
            forResource: "CodexActivityRippleGlowShader",
            withExtension: "txt"
        ) else {
            throw RippleGlowRendererError.missingShader
        }
        guard let source = String(
            data: try Data(contentsOf: url),
            encoding: .utf8
        ) else {
            throw RippleGlowRendererError.invalidShader
        }
        return source
    }
}

private enum RippleGlowPipeline {
    private static let cache = RippleGlowPipelineCache()

    static func make(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        try cache.pipeline(device: device, pixelFormat: pixelFormat)
    }
}

private final class RippleGlowPipelineCache {
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
        if let cached = pipelines[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let library = try device.makeLibrary(
            source: RippleGlowShaderResource.source(),
            options: MTLCompileOptions()
        )
        guard let vertex = library.makeFunction(name: "vs_main"),
              let fragment = library.makeFunction(name: "fs_main")
        else {
            throw RippleGlowRendererError.missingFunction
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "QuotaView Ripple Glow Orb"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        if let attachment = descriptor.colorAttachments[0] {
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
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

private final class RippleGlowRenderer: NSObject, MTKViewDelegate {
    private static let transitionDuration: CFTimeInterval = 0.42

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var activeState: CodexActivityVisualState
    private var transitionFrom: [Float]
    private var transitionTarget: [Float]
    private var transitionStartedAt = CACurrentMediaTime()
    private var lastFrameAt = CACurrentMediaTime()
    private var motionPhase: Float = 0
    private var reduceMotion = false

    init(
        view: MTKView,
        initialState: CodexActivityVisualState
    ) throws {
        guard rippleGlowUniformSeed.count
                == RippleGlowUniformLayout.floatCount
        else {
            throw RippleGlowRendererError.invalidShader
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RippleGlowRendererError.unavailableMetal
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

        pipeline = try RippleGlowPipeline.make(
            device: device,
            pixelFormat: view.colorPixelFormat
        )
        guard let queue = device.makeCommandQueue() else {
            throw RippleGlowRendererError.missingCommandQueue
        }
        commandQueue = queue
        activeState = initialState
        let initialUniforms = initialState.rippleGlowConfiguration.uniforms()
        transitionFrom = initialUniforms
        transitionTarget = initialUniforms
        super.init()
        view.delegate = self
    }

    func setState(_ state: CodexActivityVisualState, in view: MTKView) {
        guard activeState != state else { return }
        let now = CACurrentMediaTime()
        let uniforms = state.rippleGlowConfiguration.uniforms()
        if reduceMotion {
            transitionFrom = uniforms
            transitionTarget = uniforms
        } else {
            transitionFrom = interpolatedUniforms(at: now)
            transitionTarget = uniforms
        }
        transitionStartedAt = now
        activeState = state
        if view.isPaused {
            view.needsDisplay = true
        }
    }

    func setReduceMotion(_ enabled: Bool, in view: MTKView) {
        guard reduceMotion != enabled else { return }
        reduceMotion = enabled
        lastFrameAt = CACurrentMediaTime()
        if enabled {
            transitionFrom = transitionTarget
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.needsDisplay = true
        } else {
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        }
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0,
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
        let frameDelta = reduceMotion
            ? 0
            : min(max(now - lastFrameAt, 0), 0.1)
        lastFrameAt = now
        var uniforms = interpolatedUniforms(at: now)
        let speed = max(
            uniforms[RippleGlowUniformLayout.speed],
            0.001
        )
        motionPhase += Float(frameDelta) * speed
        uniforms[RippleGlowUniformLayout.sizeX] =
            Float(view.drawableSize.width)
        uniforms[RippleGlowUniformLayout.sizeY] =
            Float(view.drawableSize.height)
        uniforms[RippleGlowUniformLayout.time] = motionPhase / speed

        encoder.setRenderPipelineState(pipeline)
        uniforms.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            encoder.setFragmentBytes(
                address,
                length: bytes.count,
                index: 0
            )
        }
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func interpolatedUniforms(
        at time: CFTimeInterval
    ) -> [Float] {
        let rawProgress = min(
            max(
                (time - transitionStartedAt) / Self.transitionDuration,
                0
            ),
            1
        )
        let progress = Float(
            rawProgress * rawProgress * (3 - 2 * rawProgress)
        )
        guard progress < 1 else { return transitionTarget }
        return zip(transitionFrom, transitionTarget).map { start, end in
            start + (end - start) * progress
        }
    }
}

final class ActivityRippleGlowMetalView: MTKView {
    private var rippleRenderer: RippleGlowRenderer?

    var isRendererAvailable: Bool {
        rippleRenderer != nil
    }

    init(
        frame: NSRect,
        initialState: CodexActivityVisualState
    ) {
        super.init(frame: frame, device: nil)
        rippleRenderer = try? RippleGlowRenderer(
            view: self,
            initialState: initialState
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setState(_ state: CodexActivityVisualState) {
        rippleRenderer?.setState(state, in: self)
        if isPaused {
            needsDisplay = true
        }
    }

    func setReduceMotion(_ enabled: Bool) {
        rippleRenderer?.setReduceMotion(enabled, in: self)
    }

    func redrawIfPaused() {
        if isPaused {
            needsDisplay = true
        }
    }
}
