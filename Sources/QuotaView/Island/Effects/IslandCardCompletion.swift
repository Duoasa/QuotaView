import MetalKit
import SwiftUI
import QuotaViewCore

enum IslandCardCompletionPhase: Equatable {
    case resting, filling, wave
    case revealed(riseStart: CFTimeInterval)

    var riseStart: CFTimeInterval? {
        if case .revealed(let start) = self { return start }
        return nil
    }

    func orbFold(at now: CFTimeInterval, reduceMotion: Bool) -> Float {
        if reduceMotion { return 1 }
        switch self {
        case .wave, .filling: return 0
        case .resting, .revealed: break
        }
        let start = riseStart ?? IslandConfirmationPulse.restingRiseStart
        let breath = IslandConfirmationPulse.duration
        let rise = IslandConfirmationPulse.riseDuration
        let t = max(0, now - start).truncatingRemainder(dividingBy: 2 * breath)
        if t < rise { return Float(Self.easing.value(at: t / rise)) }
        let afterHold = t - rise - breath
        if afterHold <= 0 { return 1 }
        if afterHold >= rise { return 0 }
        return Float(1 - Self.easing.value(at: afterHold / rise))
    }

    // Core Animation's easeInEaseOut control points, shared with the glow's visual timing.
    private static let easing = UnitCurve.bezier(startControlPoint: .init(x: 0.42, y: 0),
                                                 endControlPoint: .init(x: 0.58, y: 1))
}

struct IslandCardCompletionInput: Equatable {
    let id: Int
    let identity: CodexActivityTaskIdentity?
    let state: CodexActivityVisualState
    let visible: Bool

    func startsCompletion(after previous: Self) -> Bool {
        guard visible, previous.visible, id == previous.id, identity == previous.identity,
              state == .completed else { return false }
        switch previous.state {
        case .thinking, .working, .compactingContext, .awaitingConfirmation: return true
        default: return false
        }
    }
}

// Capture an isolated copy of the card once. Scrolling, hit testing and
// accessibility continue to use the original SwiftUI row beneath the wave.
struct IslandCardCompletionWave<Card: View>: NSViewRepresentable {
    let content: Card
    let reduceMotion: Bool
    let finished: () -> Void

    func makeNSView(context: Context) -> IslandCardWaveView {
        let view = IslandCardWaveView()
        view.prepare(card: NSHostingView(rootView: content.environment(\.self, context.environment)),
                     reduceMotion: reduceMotion, finished: finished)
        return view
    }

    func updateNSView(_ view: IslandCardWaveView, context: Context) {}
    static func dismantleNSView(_ view: IslandCardWaveView, coordinator: ()) { view.stop() }
}

final class IslandCardWaveView: MTKView {
    static let duration = 1.0
    private static let gpu = MTLCreateSystemDefaultDevice()
    private static let queue = gpu?.makeCommandQueue()
    private static let pipeline: MTLRenderPipelineState? = {
        guard let gpu, let library = try? gpu.makeLibrary(source: cardWaveShader, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cardWaveVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cardWaveFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? gpu.makeRenderPipelineState(descriptor: descriptor)
    }()

    private var card: NSView?
    private var texture: MTLTexture?
    private var endTimer: Task<Void, Never>?
    private var finished: (() -> Void)?
    private var startTime: CFTimeInterval = 0
    private var quiet: Float = 0

    init() {
        super.init(frame: .zero, device: Self.gpu)
        isPaused = true
        preferredFramesPerSecond = 60
        layer?.isOpaque = false
        layer?.cornerRadius = IslandVibeLayout.rowRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        setAccessibilityElement(false)
    }

    required init(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func prepare(card: NSView, reduceMotion: Bool, finished: @escaping () -> Void) {
        self.card = card
        self.finished = finished
        quiet = reduceMotion ? 1 : 0
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { needsLayout = true }
        else { stop() }
    }

    override func layout() {
        super.layout()
        guard let card, window != nil, !bounds.isEmpty else { return }
        self.card = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.finished != nil, self.window != nil else { return }
            self.play(card)
        }
    }

    private func play(_ card: NSView) {
        guard let device, Self.pipeline != nil else { finish(); return }
        card.frame = bounds
        addSubview(card)
        card.layoutSubtreeIfNeeded()
        defer { card.removeFromSuperview() }
        guard let bitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds) else { finish(); return }
        card.cacheDisplay(in: card.bounds, to: bitmap)
        guard let image = bitmap.cgImage, let snapshot = try? MTKTextureLoader(device: device)
            .newTexture(cgImage: image, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
        else { finish(); return }
        texture = snapshot
        startTime = CACurrentMediaTime()
        isPaused = false
        endTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(Self.duration)) } catch { return }
            self?.finish()
        }
    }

    private func finish() {
        let callback = finished
        stop()
        callback?()
    }

    func stop() {
        endTimer?.cancel()
        endTimer = nil
        finished = nil
        card = nil
        texture = nil
        isPaused = true
    }

    override func draw(_ rect: CGRect) {
        guard let texture, let pipeline = Self.pipeline, let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable, let buffer = Self.queue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let phase = Float((CACurrentMediaTime() - startTime) / Self.duration)
        var geometry = SIMD4(Float(bounds.width), Float(bounds.height), phase, Float(bounds.width * 0.055))
        var quiet = self.quiet
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&geometry, length: 16, index: 0)
        encoder.setFragmentBytes(&quiet, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

private let cardWaveShader = """
#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; float2 uv; };
vertex Vertex cardWaveVertex(uint i [[vertex_id]]) {
    float2 uv = float2((i << 1) & 2, i & 2);
    return {float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1), uv};
}

// Points and normalized time keep the same wave on Retina and standard displays.
fragment float4 cardWaveFragment(Vertex v [[stage_in]], texture2d<float> card [[texture(0)]],
                                constant float4 &geometry [[buffer(0)]],
                                constant float &reducedMotion [[buffer(1)]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float2 size = geometry.xy, p = v.uv * size;
    float t = saturate(geometry.z), band = geometry.w;
    float2 origin = float2(size.x * 0.5, size.y * 0.5), ray = p - origin;
    float d = length(ray);
    bool quiet = reducedMotion > 0.5;
    float travel = (1 - exp2(-8 * t)) / (1 - exp2(-8.0));
    float radius = quiet ? 28 : travel * (length(max(origin, size - origin)) + band);
    float x = (d - radius) / band;
    float strength = quiet ? sin(M_PI_F * t) : smoothstep(0.0, 0.035, t) * (1 - pow(t, 2.2));
    float envelope = strength * exp(-0.29 * x*x);
    float4 delta = x - float4(-1.5, -0.5, 0.5, 1.5);
    float4 weights = exp(-1.55 * delta * delta);
    weights /= max(dot(weights, float4(1)), 0.0001);
    float3 tint = (float3(140,92,255)*weights.x + float3(79,161,255)*weights.y
                 + float3(110,227,255)*weights.z + float3(183,243,255)*weights.w) / 255.0;
    float2 edge = min(p, size-p);
    float bevel = exp(-min(edge.x, edge.y)/3.0);
    float2 offset = ray/max(1.0,d) * (quiet ? 0.0 : 3.2 * strength * x * exp(-0.55*x*x)) * (1 + 0.35*bevel) / size;
    float4 base = card.sample(smp,v.uv);
    float3 bent = float3(card.sample(smp,v.uv-offset*1.08).r,
                         card.sample(smp,v.uv-offset).g,
                         card.sample(smp,v.uv-offset*0.92).b);
    float line = min(0.18, length(fwidth(base.rgb)));
    float3 lit = 1 - (1-bent)*(1-tint*min(0.9, (0.45+line+0.12*bevel)));
    // Paint only the wave band; the live card remains visible through its tail.
    float a = saturate(envelope);
    return float4(lit*a,a);
}
"""
