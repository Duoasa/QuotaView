import XCTest
import Metal
import QuotaViewCore
@testable import QuotaView

final class ActivityQuantumMotionTests: XCTestCase {
    func testInterruptedTransitionRetainsPhaseAndDisplacement() {
        var motion = ActivityQuantumMotion()
        for _ in 0..<240 { motion.advance(state: .working, elapsed: 1 / 60, reduceMotion: false) }
        let before = motion.displacement
        let phase = motion.phase
        motion.advance(state: .awaitingConfirmation, elapsed: 1 / 60, reduceMotion: false)
        XCTAssertGreaterThan(motion.phase, phase)
        XCTAssertLessThan(abs(motion.displacement.x - before.x), 1.0)
        XCTAssertGreaterThan(motion.profile.weights.y, 0.8)
        motion.advance(state: .compactingContext, elapsed: 1 / 60, reduceMotion: false)
        XCTAssertGreaterThan(motion.profile.weights.z, 0)
        XCTAssertGreaterThan(motion.profile.weights.y, 0)
    }

    func testReduceMotionKeepsPhaseAndOfflineSettles() {
        var motion = ActivityQuantumMotion()
        motion.advance(state: .thinking, elapsed: 0.2, reduceMotion: false)
        let phase = motion.phase
        let position = motion.displacement
        for state in CodexActivityVisualState.allCases {
            motion.advance(state: state, elapsed: 0.25, reduceMotion: true)
            XCTAssertEqual(motion.phase, phase)
            XCTAssertEqual(motion.displacement, position)
        }
        for _ in 0..<600 { motion.advance(state: .disconnectedCodex, elapsed: 1 / 60, reduceMotion: false) }
        let resting = motion.displacement
        motion.advance(state: .disconnectedCodex, elapsed: 0.25, reduceMotion: false)
        XCTAssertEqual(motion.displacement.x, resting.x, accuracy: 0.0001)
    }

    func testFrameRateIndependentMotion() {
        var sixty = ActivityQuantumMotion()
        var thirty = ActivityQuantumMotion()
        for state in [CodexActivityVisualState.thinking, .working, .compactingContext, .awaitingConfirmation, .error] {
            for _ in 0..<60 { sixty.advance(state: state, elapsed: 1 / 60, reduceMotion: false) }
            for _ in 0..<30 { thirty.advance(state: state, elapsed: 1 / 30, reduceMotion: false) }
        }
        XCTAssertEqual(sixty.phase, thirty.phase, accuracy: 0.0001)
        XCTAssertEqual(sixty.displacement.x, thirty.displacement.x, accuracy: 0.0001)
    }

    func testProductionQuantumMetalCompiles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let library = try device.makeLibrary(source: activityStateSmokeShaderSource, options: nil)
        XCTAssertNotNil(library.makeFunction(name: "activityStateSmokeFragment"))
    }

    func testRenderedParticlesStayVisibleAcrossStatePalettes() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        let states: [CodexActivityVisualState] = [.thinking, .working, .compactingContext, .awaitingConfirmation, .error]
        func vector(_ v: SIMD4<Float>) -> String { "float4(\(v.x), \(v.y), \(v.z), \(v.w))" }
        let assignments = states.enumerated().map { index, state in
            let color = CodexActivityStateSmokeProfile.profile(for: state, effect: .dropField)
            let motion = ActivityQuantumMotionProfile.profile(state)
            return """
            if (gid.z == \(index)) {
                u.deepColor = \(vector(color.deepColor));
                u.midColor = \(vector(color.midColor));
                u.highlightColor = \(vector(color.highlightColor));
                u.energy = \(color.energy);
                u.pulse = \(color.pulse);
                u.quantumWeights = \(vector(motion.weights));
                u.quantumClock = float4(0, 0, 0.6, \(motion.failure));
            }
            """
        }.joined(separator: "\n")
        let source = activityStateSmokeShaderSource + """

        kernel void quantumPixelCheck(device float4 *pixels [[buffer(0)]], uint3 gid [[thread_position_in_grid]]) {
            ActivityStateSmokeUniforms u = {};
            u.resolution = float2(804, 136);
            u.quantumEnabled = float4(1, 1, 0, 0);
            \(assignments)
            float density = activityQuantumMotionDensity(float2(gid.xy), u.resolution, 0.75, u);
            // Match the display's bounded RGB output when judging brightness and saturation.
            float3 color = clamp(activityQuantumMotionColor(density, u), 0.0, 1.0);
            pixels[(gid.z * 136 + gid.y) * 804 + gid.x] = float4(color, density);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let function = try XCTUnwrap(library.makeFunction(name: "quantumPixelCheck"))
        let pipeline = try device.makeComputePipelineState(function: function)
        let plane = 804 * 136
        let buffer = try XCTUnwrap(device.makeBuffer(length: plane * states.count * MemoryLayout<SIMD4<Float>>.stride,
                                                      options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 804, height: 136, depth: states.count),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let pixels = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: plane * states.count)
        var means: [Float] = []
        for (index, state) in states.enumerated() {
            var samples: [Float] = []
            let original = CodexActivityStateSmokeProfile.profile(for: state, effect: .dropField)
            var originalColorError: Float = 0
            for offset in 0..<plane {
                let p = pixels[index * plane + offset]
                XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite)
                if p.w <= 0.03 && state != .awaitingConfirmation {
                    XCTAssertEqual(p.x + p.y + p.z, 0, "fine-grain gaps must not become a luminous veil")
                }
                if state == .awaitingConfirmation {
                    // Independent reference to the production transfer: compare the
                    // rendered RGB across dim points and peaks, not a guessed gold hue.
                    let d = p.w
                    let breathing = 1 + (original.pulse - 0.5) * 0.18
                    let expected = original.deepColor * (d * 0.72 * original.energy)
                        + original.midColor * (pow(d, 2.2) * 0.68 * original.energy)
                        + original.highlightColor * (pow(d, 7) * 0.55 * breathing * original.energy)
                    for channel in 0..<3 {
                        originalColorError = max(originalColorError,
                            abs(p[channel] - min(max(expected[channel], 0), 1)))
                    }
                }
                if p.w > 0.60 {
                    samples.append(p.x * 0.2126 + p.y * 0.7152 + p.z * 0.0722)
                    let brightest = max(p.x, max(p.y, p.z))
                    let darkest = min(p.x, min(p.y, p.z))
                    let saturation = (brightest - darkest) / brightest
                    if state == .compactingContext {
                        XCTAssertLessThan(saturation, 0.15, "compression retains neutral silver")
                    } else {
                        XCTAssertGreaterThan(saturation, 0.40,
                                             "\(state): retain distinct state color")
                    }
                }
            }
            XCTAssertGreaterThan(samples.count, 500, "\(state): visible grain area")
            let mean = samples.reduce(0, +) / Float(max(samples.count, 1))
            if state == .awaitingConfirmation {
                XCTAssertLessThan(originalColorError, 0.00001, "confirmation follows the actual original color transfer")
            } else {
                XCTAssertGreaterThan(mean, 0.45, "\(state): avoid crushed brightness")
                XCTAssertLessThan(mean, 0.74, "\(state): retain bright but bounded star cores")
                means.append(mean)
            }
            print("Quantum rendered particle luminance \(state.rawValue): \(mean)")
        }
        XCTAssertLessThan(try XCTUnwrap(means.max()) / XCTUnwrap(means.min()), 1.3)
    }

    func testTransportHasOneCurvedPulseWithNonlinearSpeed() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        let source = activityStateSmokeShaderSource + """

        kernel void quantumPulseCheck(device float2 *pixels [[buffer(0)]], uint3 gid [[thread_position_in_grid]]) {
            float cycle = gid.z < 9 ? (float(gid.z) + 1.0) * 0.1
                : (gid.z == 9 ? 0.99999 : 1.00001);
            float phase = cycle / 0.24;
            float pulse = activityQuantumTransportPulse(
                float2(float(gid.x) * 0.95, float(gid.y) * 68.0), float2(256, 136), 0.95, phase);
            pixels[(gid.z * 3 + gid.y) * 256 + gid.x] = float2(pulse, activityQuantumPulseCenter(phase));
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "quantumPulseCheck")))
        let count = 256 * 3 * 11
        let buffer = try XCTUnwrap(device.makeBuffer(length: count * MemoryLayout<SIMD2<Float>>.stride,
                                                      options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 256, height: 3, depth: 11),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let pixels = buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        var centers: [Float] = []
        for frame in 0..<11 {
            centers.append(pixels[frame * 768].y)
            var rowPeaks: [Int] = []
            for row in 0..<3 {
                let values = (0..<256).map { pixels[(frame * 3 + row) * 256 + $0].x }
                let peaks = (1..<255).filter { values[$0] > 0.2 && values[$0] > values[$0 - 1] && values[$0] >= values[$0 + 1] }
                XCTAssertLessThanOrEqual(peaks.count, 1, "only one pulse can cross a row")
                if centers[frame] > 0.15 && centers[frame] < 0.85 { XCTAssertEqual(peaks.count, 1) }
                rowPeaks.append(try XCTUnwrap(values.indices.max(by: { values[$0] < values[$1] })))
                if frame >= 9 { XCTAssertLessThan(try XCTUnwrap(values.max()), 0.00001, "no wrap flash") }
            }
            if frame == 4 {
                XCTAssertGreaterThan(try XCTUnwrap(rowPeaks.max()) - XCTUnwrap(rowPeaks.min()), 10,
                                     "pulse must have an irregular curved edge")
            }
        }
        for frame in 1..<9 { XCTAssertGreaterThan(centers[frame], centers[frame - 1]) }
        let fastStep = centers[4] - centers[3]
        XCTAssertGreaterThan(fastStep, (centers[1] - centers[0]) * 2)
        XCTAssertGreaterThan(fastStep, (centers[8] - centers[7]) * 2)
    }

    func testCompressionNeighbourhoodsTradeHighlightsContinuously() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        let source = activityStateSmokeShaderSource + """

        kernel void quantumClusterCheck(device float *samples [[buffer(0)]], uint3 gid [[thread_position_in_grid]]) {
            const float phases[] = {0.2, 0.9, 1.6, 0.2001};
            samples[(gid.z * 68 + gid.y) * 90 + gid.x] = activityQuantumCompressionClusters(
                float2(gid.xy) * 2.0 + 0.5, float2(180, 136), 1.0, phases[gid.z]).z;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "quantumClusterCheck")))
        let plane = 90 * 68
        let count = plane * 4
        let buffer = try XCTUnwrap(device.makeBuffer(length: count * MemoryLayout<Float>.stride,
                                                      options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 90, height: 68, depth: 4),
                                threadsPerThreadgroup: MTLSize(width: 10, height: 4, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let samples = buffer.contents().bindMemory(to: Float.self, capacity: count)
        for frame in 0..<3 {
            var bright = 0
            var dim = 0
            var changed: Float = 0
            for pixel in 0..<plane {
                let value = samples[frame * plane + pixel]
                XCTAssertTrue(value.isFinite)
                if value > 0.8 { bright += 1 }
                if value < 0.2 { dim += 1 }
                changed += abs(value - samples[((frame + 1) % 3) * plane + pixel])
                if pixel % 90 != 89 {
                    XCTAssertLessThan(abs(value - samples[frame * plane + pixel + 1]), 0.25,
                                      "neighbourhood boundaries remain smooth")
                }
            }
            XCTAssertGreaterThan(bright, plane / 20, "distinct gathered highlights")
            XCTAssertGreaterThan(dim, plane / 20, "dim spaces separate the highlights")
            XCTAssertGreaterThan(changed / Float(plane), 0.2, "different neighbourhoods gather next")
        }
        for pixel in 0..<plane {
            XCTAssertEqual(samples[pixel], samples[3 * plane + pixel], accuracy: 0.001,
                           "continuous time does not reseed or jump")
        }
    }

    func testGrainGeometryMatchesOriginalRendererPixelForPixel() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        // Compare the actual original renderer to candidate grain under the original
        // time-zero sparkle. Keep the progress front outside the measured interior.
        let source = activityStateSmokeShaderSource + """

        kernel void quantumOriginalGrainCheck(device float *errors [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
            float2 pixel = float2(gid) + 0.5;
            float2 cell;
            float seed;
            float grain = activityQuantumGrain(pixel, cell, seed);
            float wave = 0.5 + 0.5 * sin(seed * 6.2831853);
            float originalSparkle = min((0.22 + wave * 0.62 + pow(wave, 5.0) * 0.16) * 1.10, 1.0);
            float original = activityProgressDropDensity(pixel, float2(804, 136), 1.12, 0.0);
            errors[gid.y * 640 + gid.x] = abs(original - clamp(grain * originalSparkle, 0.0, 1.0));
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "quantumOriginalGrainCheck")))
        let count = 640 * 136
        let buffer = try XCTUnwrap(device.makeBuffer(length: count * MemoryLayout<Float>.stride,
                                                      options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 640, height: 136, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let errors = buffer.contents().bindMemory(to: Float.self, capacity: count)
        var maxError: Float = 0
        for index in 0..<count {
            XCTAssertTrue(errors[index].isFinite)
            maxError = max(maxError, errors[index])
        }
        XCTAssertLessThan(maxError, 0.00001, "retain original grain size, jitter and occupancy")
    }

    func testEstimatedFrontHasBroadFadeAndExplicitCompletion() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        let source = activityStateSmokeShaderSource + """

        kernel void quantumFrontCheck(device float *pixels [[buffer(0)]], uint3 gid [[thread_position_in_grid]]) {
            const float fronts[6] = {0.0, 0.01, 0.25, 0.5, 0.95, 1.12};
            float width = gid.y < 3 ? 804.0 : 416.0;
            float height = gid.y < 3 ? 136.0 : 104.0;
            float2 pixel = float2(float(gid.x) / 256.0 * width, float(gid.y % 3) / 2.0 * height);
            pixels[(gid.z * 6 + gid.y) * 256 + gid.x] = activityQuantumFrontCoverage(
                pixel, float2(width, height), fronts[gid.z], gid.z == 5 ? 1.0 : 0.0);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "quantumFrontCheck")))
        let count = 256 * 6 * 6
        let buffer = try XCTUnwrap(device.makeBuffer(length: count * MemoryLayout<Float>.stride,
                                                      options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 256, height: 6, depth: 6),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let pixels = buffer.contents().bindMemory(to: Float.self, capacity: count)
        let fronts: [Float] = [0, 0.01, 0.25, 0.5, 0.95, 1.12]
        for frame in 0..<6 {
            for row in 0..<6 {
                let values = (0..<256).map { pixels[(frame * 6 + row) * 256 + $0] }
                XCTAssertTrue(values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
                if frame == 0 { XCTAssertTrue(values.allSatisfy { $0 == 0 }) }
                if frame == 5 { XCTAssertTrue(values.allSatisfy { $0 == 1 }) }
                if (1...4).contains(frame) {
                    XCTAssertGreaterThan(values[0], 0.99, "short progress retains its visible core")
                    for x in 1..<256 {
                        XCTAssertLessThanOrEqual(values[x], values[x - 1], "no bright ruler at the front")
                        let width: Float = row < 3 ? 804 : 416
                        if Float(x) / 256 >= max(fronts[frame], 48 / width) {
                            XCTAssertEqual(values[x], 0, "uncertainty tail remains bounded")
                        }
                    }
                }
                if frame == 1 {
                    let width: Float = row < 3 ? 804 : 416
                    let dissolveWidth = Float(values.filter { $0 > 0.1 && $0 < 0.9 }.count) * width / 256
                    XCTAssertGreaterThan(dissolveWidth, 20, "1% needs a visible dissolve, not a tiny hard cap")
                    XCTAssertGreaterThan(values[Int(ceil(fronts[frame] * 256))], 0.1,
                                         "the logical percentage must not be a precise cutoff")
                }
                if (2...4).contains(frame) {
                    XCTAssertGreaterThan(values.filter { $0 > 0.1 && $0 < 0.9 }.count, 18,
                                         "estimated progress needs a broad soft boundary")
                }
            }
        }
    }

    func testEveryActiveStateDissolvesBeyondOnePercentAtBothSizes() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        let source = activityStateSmokeShaderSource + """

        kernel void earlyFrontCheck(device float *pixels [[buffer(0)]], uint3 gid [[thread_position_in_grid]]) {
            ActivityStateSmokeUniforms u = {};
            uint state = gid.z % 5;
            bool compact = (gid.z / 5) % 2 == 1;
            u.quantumEnabled = float4(1, 1, 0, 0);
            if (state == 0) u.quantumWeights.x = 1;
            if (state == 1) u.quantumWeights.y = 1;
            if (state == 2) u.quantumWeights.z = 1;
            if (state == 3) u.quantumWeights.w = 1;
            u.quantumClock = float4(0, 0, 0.3 + float(gid.z / 10) * 1.1, state == 4 ? 1 : 0);
            float2 size = compact ? float2(416, 104) : float2(804, 136);
            float2 pixel = float2(gid.x, float(gid.y) / 68.0 * size.y);
            pixels[(gid.z * 68 + gid.y) * 64 + gid.x] = activityQuantumMotionDensity(pixel, size, 0.01, u);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "earlyFrontCheck")))
        let plane = 64 * 68
        let count = plane * 30
        let buffer = try XCTUnwrap(device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 64, height: 68, depth: 30),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 4, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let pixels = buffer.contents().bindMemory(to: Float.self, capacity: count)
        for frame in 0..<30 {
            var tailStars = 0
            var inner: Float = 0
            var outer: Float = 0
            for y in 0..<68 { for x in 0..<64 {
                let value = pixels[frame * plane + y * 64 + x]
                if (10..<32).contains(x), value > 0.02 { tailStars += 1 }
                if x < 12 { inner += value }
                if (24..<36).contains(x) { outer += value }
                if x >= 48 { XCTAssertEqual(value, 0, "short front remains bounded") }
            } }
            XCTAssertGreaterThan(tailStars, 60, "frame \(frame): visible starlight extends through the uncertain tail")
            XCTAssertGreaterThan(inner, outer * 2, "frame \(frame): tail thins instead of ending as a solid cap")
        }
    }

    func testFullHeightCoverageAndSeparatedStarsAcrossStatesAndTransitions() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        let states: [CodexActivityVisualState] = [.thinking, .working, .compactingContext, .awaitingConfirmation, .error, .completed]
        var samples: [(SIMD4<Float>, Float, Float)] = []
        for state in states {
            let profile = ActivityQuantumMotionProfile.profile(state)
            for phase in [Float(0.3), 1.4, 2.6] {
                samples.append((profile.weights, profile.failure, phase))
            }
        }
        // Check intermediate morphs as well as settled states. The old vertical
        // envelope failed these edge-strip checks even before fully compacted.
        for amount in [Float(0.25), 0.5, 0.75] {
            samples.append((SIMD4<Float>(1 - amount, 0, amount, 0), 0, 1.4))
            samples.append((SIMD4<Float>(0, amount, 1 - amount, 0), 0, 1.4))
        }
        let assignments = samples.enumerated().map { index, sample in
            let (w, failure, phase) = sample
            return """
            if (gid.z == \(index)) {
                u.quantumWeights = float4(\(w.x), \(w.y), \(w.z), \(w.w));
                u.quantumClock = float4(0, 0, \(phase), \(failure));
            }
            """
        }.joined(separator: "\n")
        let source = activityStateSmokeShaderSource + """

        kernel void quantumCoverageCheck(device float *pixels [[buffer(0)]], uint3 gid [[thread_position_in_grid]]) {
            ActivityStateSmokeUniforms u = {};
            u.quantumEnabled = float4(1, 1, 0, 0);
            \(assignments)
            pixels[(gid.z * 136 + gid.y) * 804 + gid.x] =
                activityQuantumMotionDensity(float2(gid.xy), float2(804, 136), 0.95, u);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let function = try XCTUnwrap(library.makeFunction(name: "quantumCoverageCheck"))
        let pipeline = try device.makeComputePipelineState(function: function)
        let plane = 804 * 136
        let buffer = try XCTUnwrap(device.makeBuffer(length: plane * samples.count * MemoryLayout<Float>.stride,
                                                      options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 804, height: 136, depth: samples.count),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let pixels = buffer.contents().bindMemory(to: Float.self, capacity: plane * samples.count)
        for frame in samples.indices {
            func strip(_ rows: Range<Int>) -> (mean: Float, visible: Float, gaps: Float) {
                var sum: Float = 0
                var visible: Float = 0
                var gaps: Float = 0
                for y in rows {
                    for x in 48..<700 {
                        let value = pixels[frame * plane + y * 804 + x]
                        sum += value
                        if value > 0.14 { visible += 1 }
                        if value < 0.01 { gaps += 1 }
                    }
                }
                let count = Float(rows.count * 652)
                return (sum / count, visible / count, gaps / count)
            }
            let top = strip(0..<8)
            let middle = strip(60..<76)
            let bottom = strip(128..<136)
            for edge in [top, bottom] {
                XCTAssertGreaterThan(edge.visible, 0.04, "frame \(frame): stars must reach both edges")
                XCTAssertGreaterThan(edge.mean / max(middle.mean, 0.0001), 0.60,
                                     "frame \(frame): no central horizontal band")
            }
            XCTAssertGreaterThan(strip(0..<136).gaps, 0.58,
                                 "frame \(frame): stars need dark gaps, not a glowing fill")
            for y in 0..<136 {
                XCTAssertEqual(pixels[frame * plane + y * 804 + 795], 0,
                               "frame \(frame): preserve the horizontal progress boundary")
            }
        }
    }
}
