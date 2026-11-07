import AppKit
import MetalKit
import OSLog
import SwiftUI

// Original implementation of texture-fragment dissolution, informed by Telegram's
// DustEffect architecture. No Telegram source, UIKit runtime tricks or screen capture.
@MainActor
enum IslandResetDust {
    static let duration: Double = 1.7
    static let refillStartTime: Double = 1.15
    static let padding = CGSize(width: 55, height: 80)
    static let cardSize = IslandResetTicketFlight.cardSize
    static let canvasSize = CGSize(width: cardSize.width + padding.width * 2,
                                   height: cardSize.height + padding.height * 2)
    static let particleCount = Int(ceil(cardSize.width)) * Int(ceil(cardSize.height))

    static func artwork() -> CGImage? {
        guard let face = NSImage(named: "IslandResetTicket"), let mark = NSImage(named: "IslandResetMark") else { return nil }
        return artwork(face: face, mark: mark)
    }
    static func artwork(face: NSImage, mark: NSImage) -> CGImage? {
        // lockFocus can produce 16-bit/64-bpp images on HDR displays, which
        // MTKTextureLoader rejects. Use an explicit, deterministic RGBA8 bitmap.
        let width = Int(ceil(cardSize.width * 2)), height = Int(ceil(cardSize.height * 2))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        context.scaleBy(x: CGFloat(width) / cardSize.width, y: CGFloat(height) / cardSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        face.draw(in: CGRect(origin: .zero, size: cardSize))
        let markSize = CGSize(width: 45.3649, height: 45.302)
        mark.draw(in: CGRect(x: (cardSize.width - markSize.width) / 2,
                             y: (cardSize.height - markSize.height) / 2,
                             width: markSize.width, height: markSize.height))
        return context.makeImage()
    }

    nonisolated static func pipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "resetDustVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "resetDustFragment")
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // Positions are evaluated analytically by the GPU; no per-particle CPU work,
    // persistent simulation buffers, SwiftUI frame timers or offscreen redraws.
    nonisolated static let shader = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms { float4 canvas; float4 card; };
    struct Fragment {
        float4 position [[position]];
        float2 uv;
        float2 local;
        float alpha;
        float rounded;
    };
    float dustRandom(uint n) {
        n ^= n >> 16; n *= 0x7feb352du; n ^= n >> 15;
        n *= 0x846ca68bu; n ^= n >> 16;
        return float(n >> 8) / 16777216.0;
    }
    vertex Fragment resetDustVertex(uint vertexIndex [[vertex_id]], uint particle [[instance_id]],
                                    constant Uniforms &u [[buffer(0)]]) {
        const float2 corners[6] = {float2(0,0),float2(1,0),float2(0,1),
                                   float2(1,0),float2(1,1),float2(0,1)};
        float2 corner = corners[vertexIndex];
        uint columns = uint(ceil(u.card.x));
        float2 grid = float2(particle % columns, particle / columns);
        float2 tile = u.card.xy / ceil(u.card.xy);
        float2 base = (grid + 0.5) * tile;
        uint seed = particle + uint(u.canvas.w) * 7919u;
        float r0 = dustRandom(seed), r1 = dustRandom(seed + 157u), r2 = dustRandom(seed + 571u);
        float edge = 0.5 + 0.25 * sin(base.y * 0.09) + 0.25 * sin(base.y * 0.21 + base.x * 0.07);
        float delay = 0.42 * (0.65 * base.x / u.card.x + 0.20 * edge + 0.15 * r0);
        float age = max(0.0, u.canvas.z - delay);
        float life = 0.80 + 0.40 * r2;
        float released = smoothstep(0.0, 0.12, age);
        float2 drift = float2((r0 - 0.42) * 48.0 * age,
                               -(28.0 + 28.0 * r1) * age - 10.0 * age * age);
        float2 curl = float2(sin(age * 7.0 + r1 * 6.283) - sin(r1 * 6.283),
                              cos(age * 6.0 + r0 * 6.283) - cos(r0 * 6.283));
        drift += curl * (6.0 * age);
        float shrink = mix(1.0, 0.24, smoothstep(0.08, life, age));
        float2 point = u.card.zw + base + drift + (corner - 0.5) * tile * shrink;
        Fragment out;
        out.position = float4(point.x / u.canvas.x * 2.0 - 1.0,
                              1.0 - point.y / u.canvas.y * 2.0, 0, 1);
        out.uv = (grid + corner) * tile / u.card.xy;
        out.local = corner * 2.0 - 1.0;
        out.alpha = 1.0 - smoothstep(life * 0.35, life, age);
        out.rounded = released;
        if (age >= life) { out.position = float4(-2,-2,0,1); }
        return out;
    }
    fragment half4 resetDustFragment(Fragment in [[stage_in]], texture2d<half> artwork [[texture(0)]]) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float circle = 1.0 - smoothstep(0.65, 1.05, length(in.local));
        float mask = mix(1.0, circle, in.rounded);
        return artwork.sample(s, in.uv) * half(in.alpha * mask);
    }
    """#
}

// Share immutable GPU resources across page hosts. Shader compilation and
// texture upload run off the main actor; only AppKit artwork capture stays here.
final class IslandResetDustResources: @unchecked Sendable {
    let device: MTLDevice
    let pipeline: MTLRenderPipelineState
    let queue: MTLCommandQueue
    let texture: MTLTexture
    init(device: MTLDevice, image: CGImage) throws {
        self.device = device
        pipeline = try IslandResetDust.pipeline(device: device)
        guard let queue = device.makeCommandQueue() else { throw ResourceError.unavailable }
        self.queue = queue
        texture = try MTKTextureLoader(device: device).newTexture(cgImage: image,
            options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
    }
    enum ResourceError: Error { case unavailable }
}

@MainActor
final class IslandResetDustResourceCache {
    static let shared = IslandResetDustResourceCache()
    private var preparation: Task<IslandResetDustResources, Error>?
    func load(artwork: @MainActor () -> CGImage? = IslandResetDust.artwork) async throws -> IslandResetDustResources {
        if let preparation { return try await preparation.value }
        guard let device = MTLCreateSystemDefaultDevice(), let image = artwork() else {
            throw IslandResetDustResources.ResourceError.unavailable
        }
        let task = Task.detached(priority: .userInitiated) {
            try IslandResetDustResources(device: device, image: image)
        }
        preparation = task
        return try await task.value
    }
}

// CADisplayLink retains its target. Keep the host weak so an interrupted page
// cannot leave an offscreen renderer alive through the run loop.
@MainActor
private final class IslandResetDustDisplayLinkTarget: NSObject {
    weak var host: IslandResetDustHost?
    init(host: IslandResetDustHost) { self.host = host }
    @objc func step(_ link: CADisplayLink) { host?.draw() }
}

struct IslandResetAnimatedTicket: View {
    @ObservedObject var controller: CodexResetController
    let playbackEnabled: Bool
    let isPresented: Bool
    var isEmpty = false
    private var displayedEmpty: Bool { controller.phase == .submitting ? false : isEmpty }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animating: Bool { controller.ticketDissolveInFlight || controller.ticketRefillInFlight }
    private var canAnimate: Bool { !reduceMotion && isPresented && playbackEnabled }
    private var destination: CGRect { CGRect(origin: CGPoint(x: IslandResetDust.padding.width,
        y: IslandResetDust.padding.height), size: IslandResetDust.cardSize) }
    var body: some View {
        IslandResetTicket(playbackEnabled: playbackEnabled && !animating,
                          size: IslandResetDust.cardSize, isEmpty: displayedEmpty)
            .opacity(controller.ticketHidden && !reduceMotion ? 0 : 1)
            .allowsHitTesting(!animating)
            .overlay {
                IslandResetDustView(serial: controller.ticketAnimationSerial,
                    active: controller.ticketDissolveInFlight,
                    prepare: isPresented, reduceMotion: reduceMotion || !isPresented || !playbackEnabled,
                    refillReady: { if canAnimate { controller.startTicketRefill(serial: $0) } },
                    completion: { controller.finishTicketDissolve(serial: $0, animateRefill: canAnimate) })
                    .frame(width: IslandResetDust.canvasSize.width, height: IslandResetDust.canvasSize.height)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay {
                IslandResetTicketFlightView(serial: controller.ticketAnimationSerial, toReset: true,
                    active: controller.ticketRefillInFlight && canAnimate,
                    source: destination.offsetBy(dx: 0, dy: IslandResetTicketRefill.entryOffset),
                    destination: destination, reduceMotion: reduceMotion, refillEntrance: true,
                    isEmpty: displayedEmpty, onCompletion: controller.finishTicketRefill)
                    .frame(width: IslandResetDust.canvasSize.width, height: IslandResetDust.canvasSize.height)
                    // Confine only the incoming card/shadow above the title;
                    // the independent particle canvas remains unrestricted.
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.white.frame(height: destination.maxY)
                            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: IslandResetTicketRefill.lowerFadeHeight)
                        }
                    }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .onChange(of: canAnimate) { _, enabled in
                if !enabled { controller.finishTicketRefill(serial: controller.ticketAnimationSerial) }
            }
    }
}

private struct IslandResetDustView: NSViewRepresentable {
    let serial: UInt64
    let active: Bool
    let prepare: Bool
    let reduceMotion: Bool
    let refillReady: (UInt64) -> Void
    let completion: (UInt64) -> Void
    func makeNSView(context: Context) -> IslandResetDustHost { IslandResetDustHost() }
    func updateNSView(_ view: IslandResetDustHost, context: Context) {
        view.configure(serial: serial, active: active, prepare: prepare,
                       reduceMotion: reduceMotion, refillReady: refillReady, completion: completion)
    }
    static func dismantleNSView(_ view: IslandResetDustHost, coordinator: ()) { view.stop() }
}

final class IslandResetDustHost: MTKView, MTKViewDelegate {
    private static let logger = Logger(subsystem: "com.quotaview.menubar", category: "reset-dust")
    override var isOpaque: Bool { false }
    private var pipeline: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private var texture: MTLTexture?
    private var attemptedSetup = false
    private let resourceCache: IslandResetDustResourceCache
    private var serial: UInt64?
    private var startedAt: CFTimeInterval?
    private var completion: ((UInt64) -> Void)?
    private var refillReady: ((UInt64) -> Void)?
    private var sentRefillReady = false
    private var occlusionObserver: NSObjectProtocol?
    private let inFlight = DispatchSemaphore(value: 3)
    private var displayRefresh: CADisplayLink?
    private lazy var displayTarget = IslandResetDustDisplayLinkTarget(host: self)
    var usesDisplayRefresh: Bool { displayRefresh != nil }

    init(resourceCache: IslandResetDustResourceCache? = nil) {
        self.resourceCache = resourceCache ?? .shared
        super.init(frame: .zero, device: nil)
        isPaused = true
        enableSetNeedsDisplay = false
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        wantsLayer = true
        layer?.isOpaque = false
        delegate = self
        isHidden = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func prepareResources() {
        guard !attemptedSetup else { return }
        attemptedSetup = true
        let cache = resourceCache
        Task { [weak self] in
            do {
                let resources = try await cache.load()
                guard let self else { return }
                self.device = resources.device
                self.pipeline = resources.pipeline
                self.commandQueue = resources.queue
                self.texture = resources.texture
                self.startIfVisible()
            } catch {
                Self.logger.error("Reset dust setup failed: \(String(describing: error), privacy: .public)")
                self?.stop()
            }
        }
    }
    func configure(serial: UInt64, active: Bool, prepare: Bool, reduceMotion: Bool,
                   refillReady: @escaping (UInt64) -> Void = { _ in },
                   completion: @escaping (UInt64) -> Void) {
        if prepare && !reduceMotion { prepareResources() }
        guard active else { stop(); return }
        if self.serial == serial {
            // Visibility/reduced-motion changes must use the current callbacks,
            // so stopping cannot request a refill with stale playback permission.
            self.completion = completion
            self.refillReady = refillReady
            if reduceMotion { stop() }
            return
        }
        stop()
        self.serial = serial
        self.completion = completion
        self.refillReady = refillReady
        guard !reduceMotion else { stop(); return }
        startIfVisible()
    }
    private func startIfVisible() {
        guard serial != nil, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        guard window?.occlusionState.contains(.visible) == true else { stop(); return }
        guard pipeline != nil, commandQueue != nil, texture != nil else { return }
        isHidden = false
        // Keep MTKView's timer paused; the view-bound link follows the display,
        // including screen changes, and stops completely between dissolves.
        guard displayRefresh == nil else { return }
        let link = displayLink(target: displayTarget, selector: #selector(IslandResetDustDisplayLinkTarget.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        displayRefresh = link
        link.add(to: .main, forMode: .common)
    }
    override func layout() {
        super.layout()
        if serial != nil && displayRefresh == nil { startIfVisible() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else { stop(); return }
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
            object: window, queue: .main) { [weak self, weak window] _ in
                guard window?.occlusionState.contains(.visible) == true else { self?.stop(); return }
            }
        startIfVisible()
    }
    func stop() {
        displayRefresh?.invalidate()
        displayRefresh = nil
        isPaused = true
        isHidden = true
        startedAt = nil
        let finished = serial
        let callback = completion
        serial = nil
        completion = nil
        refillReady = nil
        sentRefillReady = false
        if let finished { DispatchQueue.main.async { callback?(finished) } }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let activeSerial = serial, !isHidden, window?.occlusionState.contains(.visible) == true else { stop(); return }
        let now = CACurrentMediaTime()
        let elapsed = startedAt.map { now - $0 } ?? 0
        guard elapsed < IslandResetDust.duration else { stop(); return }
        guard let pipeline, let commandQueue, let texture else { stop(); return }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = commandQueue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass)
        else { inFlight.signal(); return }
        if startedAt == nil { startedAt = now }
        let uniforms = [SIMD4<Float>(Float(bounds.width), Float(bounds.height), Float(elapsed), Float((serial ?? 0) % 65536)),
                        SIMD4<Float>(Float(IslandResetDust.cardSize.width), Float(IslandResetDust.cardSize.height),
                                     Float(IslandResetDust.padding.width), Float(IslandResetDust.padding.height))]
        encoder.setRenderPipelineState(pipeline)
        uniforms.withUnsafeBytes { bytes in
            encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                               instanceCount: IslandResetDust.particleCount)
        encoder.endEncoding()
        command.present(drawable)
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.commit()
        // Anchor overlap to rendered particle time, not the confirmation click.
        // One callback per run; never publish SwiftUI state inside a draw pass.
        if !sentRefillReady, elapsed >= IslandResetDust.refillStartTime {
            sentRefillReady = true
            let callback = refillReady
            DispatchQueue.main.async { callback?(activeSerial) }
        }
    }
    deinit {
        displayRefresh?.invalidate()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }
}
