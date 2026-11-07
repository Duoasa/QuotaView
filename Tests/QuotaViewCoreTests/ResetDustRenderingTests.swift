import MetalKit
import SwiftUI
import QuotaViewCore
import XCTest
@testable import QuotaView

@MainActor
final class ResetDustRenderingTests: XCTestCase {
    func testRefillRisesWithoutRotationAndHandsOffWithoutOpacityOrGeometryJump() {
        let destination = CGRect(origin: CGPoint(x: 55, y: 80), size: IslandResetTicketFlight.cardSize)
        let source = destination.offsetBy(dx: 0, dy: IslandResetTicketRefill.entryOffset)
        let samples = (0...100).map { IslandResetTicketRefill.sample(at: Double($0) / 100, source: source, destination: destination) }
        XCTAssertTrue(samples.allSatisfy { CATransform3DIsIdentity($0.transform) })
        XCTAssertTrue(samples.allSatisfy { $0.position.x == destination.midX })
        XCTAssertLessThan(samples[58].position.y, destination.midY - 3)
        XCTAssertGreaterThan(samples[80].position.y, destination.midY)
        XCTAssertLessThanOrEqual(IslandResetTicketRefill.duration, 0.5)
        XCTAssertGreaterThan(samples[0].position.y, destination.midY)
        let final = samples[100]
        XCTAssertEqual(final.position.x, destination.midX, accuracy: 0.001)
        XCTAssertEqual(final.position.y, destination.midY, accuracy: 0.001)
        XCTAssertEqual(final.transform.m11, 1, accuracy: 0.001)
        XCTAssertEqual(final.transform.m12, 0, accuracy: 0.001)
        let alphas = (0...100).map { IslandResetTicketRefill.opacity(at: Double($0) / 100) }
        XCTAssertEqual(alphas.first, 0); XCTAssertEqual(alphas.last, 1)
        for index in 1...100 { XCTAssertGreaterThanOrEqual(alphas[index], alphas[index - 1]) }
        XCTAssertLessThan(hypot(samples[100].position.x - samples[99].position.x,
                                samples[100].position.y - samples[99].position.y), 0.02)
    }

    func testEmptyArtworkAndOpacityRemainConsistentDuringRefillAndPageFlights() throws {
        XCTAssertTrue(IslandResetTicketArtwork.mark(.codex, isEmpty: true) === IslandResetTicketArtwork.emptyMark)
        XCTAssertTrue(IslandResetTicketArtwork.mark(.claudeCode, isEmpty: true) === IslandResetTicketArtwork.emptyMark)
        let host = IslandResetTicketFlightHost(frame: CGRect(x: 0, y: 0, width: 312, height: 280))
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { host.stop(); window.contentView = nil; window.close() }
        window.contentView = host
        host.isEmpty = true
        host.refillEntrance = true
        let destination = CGRect(origin: CGPoint(x: 55, y: 80), size: IslandResetTicketFlight.cardSize)
        host.configure(serial: 1, toReset: true, active: true,
            source: destination.offsetBy(dx: 0, dy: IslandResetTicketRefill.entryOffset), destination: destination, reduceMotion: false)
        XCTAssertEqual(host.cardOpacity, 1)
        let mask = try XCTUnwrap(host.layer?.mask as? CAGradientLayer)
        XCTAssertEqual(mask.frame, host.bounds)
        XCTAssertEqual(mask.locations?[1].doubleValue ?? -1, Double(destination.maxY / host.bounds.height), accuracy: 0.0001)
        XCTAssertEqual(mask.locations?[2].doubleValue ?? -1,
            Double((destination.maxY + IslandResetTicketRefill.lowerFadeHeight) / host.bounds.height), accuracy: 0.0001)
        let animation = try XCTUnwrap(host.flightAnimation)
        let opacity = try XCTUnwrap(animation.animations?.compactMap { $0 as? CAKeyframeAnimation }.first { $0.keyPath == "opacity" })
        let values = try XCTUnwrap(opacity.values as? [NSNumber])
        XCTAssertEqual(values.first?.doubleValue, 0)
        XCTAssertEqual(values.last?.doubleValue ?? -1, 1, accuracy: 0.0001)
        host.frame.size.height += 40
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(mask.frame, host.bounds)
        XCTAssertEqual(mask.locations?[1].doubleValue ?? -1, Double(destination.maxY / host.bounds.height), accuracy: 0.0001)
        host.stop(); host.refillEntrance = false
        XCTAssertNil(host.layer?.mask, "Page flights must not inherit the refill clip")
        host.configure(serial: 2, toReset: false, active: true, source: destination, destination: destination, reduceMotion: false)
        XCTAssertEqual(host.cardOpacity, 1)
        host.stop(); host.provider = .claudeCode
        XCTAssertEqual(host.cardOpacity, 1)
        let images = (host.layer?.sublayers ?? []).flatMap { $0.sublayers ?? [] }.compactMap { $0.contents as AnyObject? }
        XCTAssertTrue(images.contains { $0 === IslandResetTicketArtwork.emptyFaceCGImage as AnyObject? })
        XCTAssertTrue(images.contains { $0 === IslandResetTicketArtwork.emptyMarkCGImage as AnyObject? })
        host.isEmpty = false
        XCTAssertEqual(host.cardOpacity, 1)
    }

    func testBothProvidersUseKnownZeroForEmptyCardsAndPreserveUnknownData() {
        for count: Int? in [nil, 0, 2] {
            let snapshot = CurrentCodexPresentation(availability: .ready, planType: "",
                usedPercent: 20, remainingPercent: 80, windowDurationMinutes: 10080,
                resetsAt: nil, quotaWindows: [], sparkQuota: nil, creditBalance: nil,
                hasCredits: false, unlimitedCredits: false, availableResetCredits: count,
                lifetimeTokens: nil, recentDailyTokens: nil, recentDailyDate: nil,
                tokenActivity: [], lastUpdatedAt: Date())
            let data = IslandResetPageData(snapshot: snapshot)
            XCTAssertEqual(data.creditAvailability == .empty, count == 0)
            for provider in [IslandAgentProvider.codex, .claudeCode] {
                let board = IslandBoardState()
                let usage = IslandUsageBento(snapshot: snapshot, usageState: .current, english: true,
                    contentWidth: 680, options: .init(), privacy: false, playbackEnabled: false,
                    hidesTicket: false, onReset: {}, utilities: IslandUtilityActions(state: board),
                    onHeightChange: { _ in }, claudeUsage: .init(presentation: snapshot,
                        fiveHour: nil, sevenDay: nil, quotaState: .available, planName: nil,
                        extraUsageEnabled: nil, extraUsagePercent: nil), provider: .constant(provider))
                XCTAssertEqual(usage.resetCardIsEmpty, count == 0)
                XCTAssertEqual(usage.displayedResetCredits, count)
            }
        }
    }

    func testEmptyFaceIsOpaqueDarkCachedBitmapWithRoundedCorners() throws {
        let face = try XCTUnwrap(IslandResetTicketArtwork.emptyFaceCGImage)
        let mark = try XCTUnwrap(IslandResetTicketArtwork.emptyMarkCGImage)
        XCTAssertTrue(face === IslandResetTicketArtwork.emptyFaceCGImage)
        XCTAssertTrue(mark === IslandResetTicketArtwork.emptyMarkCGImage)
        XCTAssertEqual(face.bitsPerComponent, 8)
        XCTAssertEqual(face.width, 403)
        XCTAssertEqual(face.height, 240)
        XCTAssertFalse(IslandResetTicketArtwork.emptyFace.representations.contains { $0 is NSCustomImageRep })
        XCTAssertFalse(IslandResetTicketArtwork.emptyMark.representations.contains { $0 is NSCustomImageRep })
        let data = try XCTUnwrap(face.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let center = (face.height / 2) * face.bytesPerRow + (face.width / 2) * 4
        XCTAssertEqual(bytes[center + 3], 255, "Card interior must not reveal the desktop")
        XCTAssertLessThan(bytes[center], 100)
        XCTAssertGreaterThan(bytes[center], 50)
        XCTAssertEqual(bytes[3], 0, "Only the rounded outside corner remains transparent")
    }

    func testVectorArtworkUsesRGBA8AndLoadsAsMetalTexture() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let face = NSImage(size: CGSize(width: 201.29, height: 120), flipped: false) { rect in
            NSColor(white: 0.9, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
            return true
        }
        let mark = NSImage(size: CGSize(width: 45, height: 45), flipped: false) { rect in
            NSColor.gray.setFill(); NSBezierPath(ovalIn: rect).fill(); return true
        }
        let image = try XCTUnwrap(IslandResetDust.artwork(face: face, mark: mark))
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.bitsPerPixel, 32)
        XCTAssertEqual(image.width, 403)
        XCTAssertEqual(image.height, 240)
        let texture = try MTKTextureLoader(device: device).newTexture(cgImage: image,
            options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
        XCTAssertEqual(texture.width, image.width)
        XCTAssertEqual(texture.height, image.height)
    }

    func testFullSizeDustSpreadsOutsideCardAndSoftensCanvasEdges() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let pipeline = try IslandResetDust.pipeline(device: device)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: 1, height: 1, mipmapped: false)
        sourceDescriptor.storageMode = .shared
        let source = try XCTUnwrap(device.makeTexture(descriptor: sourceDescriptor))
        let white: [UInt8] = [255, 255, 255, 255]
        white.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: 4) }
        let size = IslandResetDust.renderCanvasSize, card = IslandResetDust.cardSize, padding = IslandResetDust.padding
        let width = Int(ceil(size.width)), height = Int(ceil(size.height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget]
        let output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var minX = width, maxX = 0, minY = height, edgeAlpha = 0
        for time: Float in [0.35, 0.65, 1.0, 1.3] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
            let uniforms = [SIMD4<Float>(Float(width), Float(height), time, 1),
                SIMD4<Float>(Float(card.width), Float(card.height), Float(padding.width), Float(padding.height)), .zero]
            encoder.setRenderPipelineState(pipeline)
            uniforms.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setFragmentTexture(source, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                instanceCount: IslandResetDust.particleCount)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            XCTAssertNil(command.error)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
            for y in 0..<height { for x in 0..<width {
                let alpha = Int(pixels[(y * width + x) * 4 + 3])
                if alpha > 16 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y) }
                if x < 2 || x >= width - 2 || y < 2 || y >= height - 2 { edgeAlpha = max(edgeAlpha, alpha) }
            } }
        }
        XCTAssertLessThan(minX, Int(padding.width) - 12)
        XCTAssertGreaterThan(maxX, Int(padding.width + card.width) + 12)
        XCTAssertLessThan(minY, Int(padding.height) - 40)
        XCTAssertLessThan(edgeAlpha, 10, "No bright hard line at the particle canvas boundary")
        print("Reset dust spread: left=\(Int(padding.width) - minX), right=\(maxX - Int(padding.width + card.width)), up=\(Int(padding.height) - minY), edgeAlpha=\(edgeAlpha)")
    }

    func testGPUKeepsSourceColorThenDispersesAndClears() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let pipeline = try IslandResetDust.pipeline(device: device)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: 2, height: 2, mipmapped: false)
        sourceDescriptor.storageMode = .shared
        let source = try XCTUnwrap(device.makeTexture(descriptor: sourceDescriptor))
        let pixels: [UInt8] = [255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255]
        pixels.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: 8) }
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 128, height: 128, mipmapped: false)
        outputDescriptor.storageMode = .shared
        outputDescriptor.usage = [.renderTarget]
        let output = try XCTUnwrap(device.makeTexture(descriptor: outputDescriptor))
        func frame(_ time: Float, topFade: SIMD4<Float> = .zero) throws -> [UInt8] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
            let uniforms = [SIMD4<Float>(128, 128, time, 1), SIMD4<Float>(32, 32, 48, 64), topFade]
            encoder.setRenderPipelineState(pipeline)
            uniforms.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setFragmentTexture(source, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: IslandResetDust.particleCount(for: CGSize(width: 32, height: 32)))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            var result = [UInt8](repeating: 0, count: 128 * 128 * 4)
            result.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 128 * 4,
                from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0) }
            return result
        }
        let faded = try frame(0, topFade: SIMD4<Float>(64, 32, 0, 0))
        XCTAssertLessThan(faded[(64 * 128 + 64) * 4 + 3], 10)
        XCTAssertTrue((120...145).contains(Int(faded[(80 * 128 + 64) * 4 + 3])))
        XCTAssertGreaterThan(faded[(95 * 128 + 64) * 4 + 3], 240)
        let initial = try frame(0), middle = try frame(0.65), end = try frame(Float(IslandResetDust.duration))
        func alpha(_ bytes: [UInt8]) -> Int { stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) } }
        XCTAssertEqual(alpha(initial), 32 * 32 * 255)
        XCTAssertGreaterThan(alpha(middle), 0)
        XCTAssertLessThan(alpha(middle), alpha(initial))
        let overlap = try frame(Float(IslandResetDust.refillStartTime))
        XCTAssertGreaterThan(alpha(overlap), 0, "Refill begins while particles are still visible")
        XCTAssertLessThan(alpha(overlap), alpha(middle))
        XCTAssertEqual(alpha(end), 0)
        let center = (80 * 128 + 64) * 4
        XCTAssertEqual(Array(initial[center..<center + 4]), [0, 0, 255, 255])
        let above = (0..<64).reduce(0) { sum, row in
            sum + (0..<128).reduce(0) { $0 + Int(middle[(row * 128 + $1) * 4 + 3]) }
        }
        XCTAssertGreaterThan(above, 0, "Particles must move above the original card bounds")
    }

    func testResourceCacheCoalescesConcurrentPreparationAndReusesGPUObjects() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let cache = IslandResetDustResourceCache()
        var captures = 0
        let first = Task { try await cache.load { captures += 1; return image } }
        let second = Task { try await cache.load { captures += 1; return image } }
        let a = try await first.value, b = try await second.value
        let c = try await cache.load { captures += 1; return image }
        XCTAssertTrue(a === b && b === c)
        XCTAssertEqual(captures, 1, "Host recreation must not recapture artwork or compile/upload again")
    }

    func testDisplayRefreshRunsOnlyWhileActiveAndStopsOnReducedMotion() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let cache = IslandResetDustResourceCache()
        _ = try await cache.load { image }
        // Offscreen fixture reports eligibility without showing/operating UI.
        let window = DustEligibleFixtureWindow(contentRect: CGRect(x: 0, y: 0, width: 312, height: 280),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let host = IslandResetDustHost(resourceCache: cache)
        window.contentView = host
        host.frame = CGRect(x: 0, y: 0, width: 312, height: 280)
        let completed = expectation(description: "Reduced motion ends active refresh")
        host.configure(serial: 9, active: true, prepare: true, reduceMotion: false) { _ in completed.fulfill() }
        for _ in 0..<30 {
            if host.usesDisplayRefresh { break }
            await Task.yield()
        }
        XCTAssertTrue(host.usesDisplayRefresh)
        XCTAssertTrue(host.isPaused, "MTKView timer must stay off while CADisplayLink drives rendering")
        host.configure(serial: 9, active: true, prepare: true, reduceMotion: true) { _ in completed.fulfill() }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertFalse(host.usesDisplayRefresh)
        XCTAssertTrue(host.isHidden)
    }

    func testIdleHostHasNoContinuousDrawingAndReducedMotionCompletes() async {
        let host = IslandResetDustHost()
        XCTAssertTrue(host.isPaused)
        XCTAssertFalse(host.usesDisplayRefresh)
        XCTAssertTrue(host.isHidden)
        let done = expectation(description: "Reduced motion completes without a GPU loop")
        host.configure(serial: 1, active: true, prepare: false, reduceMotion: true) { serial in
            XCTAssertEqual(serial, 1)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)
        XCTAssertTrue(host.isPaused)
        XCTAssertFalse(host.usesDisplayRefresh)
        XCTAssertTrue(host.isHidden)
    }

    func testRedConfirmationReusesApprovalPulseAndRestoresItsPalette() {
        let glow = ActivityIslandCompletionGlowView(frame: .zero)
        glow.confirmationColor = .systemRed
        glow.update(edgeEmphasis: .confirmationReminder, reduceMotion: false, playbackVisible: true)
        glow.updateIslandConfirmationPulse(animated: true)
        XCTAssertEqual(glow.displayedGlowColors.count, 2)
        XCTAssertTrue(glow.displayedGlowColors.allSatisfy { $0 == NSColor.systemRed.cgColor })
        XCTAssertEqual(glow.islandPulse?.duration, IslandConfirmationPulse.duration)
        glow.update(edgeEmphasis: .confirmationReminder, reduceMotion: true, playbackVisible: true)
        glow.updateIslandConfirmationPulse(animated: false)
        XCTAssertNil(glow.islandPulse)
        glow.confirmationColor = nil
        XCTAssertTrue(glow.displayedGlowColors.allSatisfy { $0 == CodexActivityIslandConfirmationReminderContract.approvalColor.cgColor })
        glow.update(edgeEmphasis: .none, reduceMotion: false, playbackVisible: false)
        XCTAssertTrue(glow.isHidden)
    }
}

@MainActor
private final class DustEligibleFixtureWindow: NSWindow {
    override var occlusionState: NSWindow.OcclusionState { .visible }
}
