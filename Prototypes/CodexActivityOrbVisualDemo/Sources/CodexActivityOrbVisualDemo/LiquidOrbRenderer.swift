import AppKit
import MetalKit
import QuartzCore
import SwiftUI

enum OrbUniformLayout {
    static let floatCount = 128
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

let orbUniformSeed: [Float] = [
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

enum OrbShaderResourceError: LocalizedError {
    case missingResource
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "找不到 OrbShader.metal 资源"
        case .invalidUTF8:
            "OrbShader.metal 不是有效的 UTF-8 文本"
        }
    }
}

enum LiquidOrbError: LocalizedError {
    case metalUnavailable
    case shaderFunctionMissing(String)
    case commandQueueUnavailable
    case textureUnavailable
    case commandBufferUnavailable
    case renderEncoderUnavailable
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            "当前 Mac 没有可用的 Metal 设备"
        case let .shaderFunctionMissing(name):
            "Metal 着色器缺少函数：\(name)"
        case .commandQueueUnavailable:
            "无法创建 Metal Command Queue"
        case .textureUnavailable:
            "无法创建离屏渲染纹理"
        case .commandBufferUnavailable:
            "无法创建 Metal Command Buffer"
        case .renderEncoderUnavailable:
            "无法创建 Metal Render Encoder"
        case let .renderFailed(message):
            "Metal 离屏绘制失败：\(message)"
        }
    }
}

enum OrbShaderResources {
    static func source() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "OrbShader",
            withExtension: "metal"
        ) else {
            throw OrbShaderResourceError.missingResource
        }
        guard let source = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw OrbShaderResourceError.invalidUTF8
        }
        return source
    }
}

private enum OrbMetalPipeline {
    static func make(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let options = MTLCompileOptions()
        let library = try device.makeLibrary(
            source: OrbShaderResources.source(),
            options: options
        )
        guard let vertex = library.makeFunction(name: "vs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("vs_main")
        }
        guard let fragment = library.makeFunction(name: "fs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("fs_main")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "QuotaView AI Orb Prototype"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

final class LiquidOrbRenderer: NSObject, MTKViewDelegate {
    private static let stateTransitionDuration: CFTimeInterval = 0.42

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var state: DemoActivityState
    private var transitionFrom: [Float]
    private var transitionTarget: [Float]
    private var transitionStartedAt = CACurrentMediaTime()
    private var lastFrameAt = CACurrentMediaTime()
    private var motionPhase: Float = 0
    private var paused = false

    init(
        view: MTKView,
        initialState: DemoActivityState
    ) throws {
        guard orbUniformSeed.count == OrbUniformLayout.floatCount else {
            preconditionFailure("AI 球 Uniform 数量与 Metal 契约不一致")
        }
        let initialUniforms = initialState.orbConfiguration.applying(
            to: orbUniformSeed
        )
        state = initialState
        transitionFrom = initialUniforms
        transitionTarget = initialUniforms
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw LiquidOrbError.metalUnavailable
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.wantsLayer = true
        view.layer?.isOpaque = false

        pipeline = try OrbMetalPipeline.make(
            device: device,
            pixelFormat: view.colorPixelFormat
        )
        guard let queue = device.makeCommandQueue() else {
            throw LiquidOrbError.commandQueueUnavailable
        }
        commandQueue = queue
        super.init()
    }

    func setState(_ newState: DemoActivityState, in view: MTKView) {
        guard state != newState else { return }
        let now = CACurrentMediaTime()
        let newUniforms = newState.orbConfiguration.applying(
            to: orbUniformSeed
        )
        if paused {
            transitionFrom = newUniforms
            transitionTarget = newUniforms
        } else {
            transitionFrom = interpolatedUniforms(at: now)
            transitionTarget = newUniforms
        }
        transitionStartedAt = now
        state = newState
        if view.isPaused {
            view.draw()
        }
    }

    func setPaused(_ shouldPause: Bool, in view: MTKView) {
        guard paused != shouldPause else { return }
        paused = shouldPause
        lastFrameAt = CACurrentMediaTime()
        view.isPaused = shouldPause
        if shouldPause {
            view.draw()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            view.drawableSize.width > 0,
            view.drawableSize.height > 0,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let now = CACurrentMediaTime()
        let frameDelta = paused
            ? 0
            : min(max(now - lastFrameAt, 0), 0.1)
        lastFrameAt = now
        var uniforms = interpolatedUniforms(at: now)
        let speed = max(uniforms[OrbUniformLayout.speed], 0.001)
        motionPhase += Float(frameDelta) * speed
        uniforms[OrbUniformLayout.sizeX] = Float(view.drawableSize.width)
        uniforms[OrbUniformLayout.sizeY] = Float(view.drawableSize.height)
        uniforms[OrbUniformLayout.time] = motionPhase / speed

        encoder.setRenderPipelineState(pipeline)
        uniforms.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            encoder.setFragmentBytes(
                address,
                length: bytes.count,
                index: 0
            )
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func interpolatedUniforms(at time: CFTimeInterval) -> [Float] {
        let rawProgress = min(
            max(
                (time - transitionStartedAt)
                    / Self.stateTransitionDuration,
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

final class LiquidOrbHostView: NSView {
    private let metalView = MTKView(frame: .zero, device: nil)
    private var renderer: LiquidOrbRenderer?
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    override var isOpaque: Bool { false }

    init(
        frame frameRect: NSRect,
        initialState: DemoActivityState
    ) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        do {
            let renderer = try LiquidOrbRenderer(
                view: metalView,
                initialState: initialState
            )
            self.renderer = renderer
            metalView.delegate = renderer
            addSubview(metalView)
        } catch {
            errorLabel.alignment = .center
            errorLabel.maximumNumberOfLines = 0
            errorLabel.textColor = .systemRed
            errorLabel.stringValue = error.localizedDescription
            addSubview(errorLabel)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        metalView.frame = bounds
        errorLabel.frame = bounds.insetBy(dx: 8, dy: 8)
    }

    func setPaused(_ paused: Bool) {
        renderer?.setPaused(paused, in: metalView)
    }

    func setState(_ state: DemoActivityState) {
        renderer?.setState(state, in: metalView)
    }
}

struct LiquidOrbSurface: NSViewRepresentable {
    let state: DemoActivityState
    let paused: Bool

    func makeNSView(context: Context) -> LiquidOrbHostView {
        LiquidOrbHostView(frame: .zero, initialState: state)
    }

    func updateNSView(_ view: LiquidOrbHostView, context: Context) {
        view.setState(state)
        view.setPaused(paused)
    }
}

struct LiquidOrbView: View {
    let state: DemoActivityState
    let paused: Bool

    var body: some View {
        LiquidOrbSurface(state: state, paused: paused)
            .accessibilityLabel("仅用于调试的 AI 球视觉 Demo")
    }
}

struct MetalOrbSmokeReport {
    let deviceName: String
    let uniformBytes: Int
    let renderSize: Int
    let renderedStateCount: Int
}

enum MetalOrbSmokeTest {
    static func run() throws -> MetalOrbSmokeReport {
        guard orbUniformSeed.count == OrbUniformLayout.floatCount else {
            throw LiquidOrbError.renderFailed("Uniform 数量不正确")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw LiquidOrbError.metalUnavailable
        }
        let pixelFormat = MTLPixelFormat.bgra8Unorm
        let pipeline = try OrbMetalPipeline.make(
            device: device,
            pixelFormat: pixelFormat
        )
        guard let queue = device.makeCommandQueue() else {
            throw LiquidOrbError.commandQueueUnavailable
        }

        let side = 128
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: side,
            height: side,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget]
        textureDescriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw LiquidOrbError.textureUnavailable
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )

        for (index, state) in DemoActivityState.allCases.enumerated() {
            guard let commandBuffer = queue.makeCommandBuffer() else {
                throw LiquidOrbError.commandBufferUnavailable
            }
            guard let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPass
            ) else {
                throw LiquidOrbError.renderEncoderUnavailable
            }

            var uniforms = state.orbConfiguration.applying(to: orbUniformSeed)
            uniforms[OrbUniformLayout.sizeX] = Float(side)
            uniforms[OrbUniformLayout.sizeY] = Float(side)
            uniforms[OrbUniformLayout.time] = 0.75 + Float(index) * 0.1
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
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            if let error = commandBuffer.error {
                throw LiquidOrbError.renderFailed(
                    "\(state.statusTitle)：\(error.localizedDescription)"
                )
            }
            guard commandBuffer.status == .completed else {
                throw LiquidOrbError.renderFailed(
                    "\(state.statusTitle) Command Buffer 状态为 \(commandBuffer.status.rawValue)"
                )
            }
        }
        return MetalOrbSmokeReport(
            deviceName: device.name,
            uniformBytes: orbUniformSeed.count * MemoryLayout<Float>.stride,
            renderSize: side,
            renderedStateCount: DemoActivityState.allCases.count
        )
    }
}
