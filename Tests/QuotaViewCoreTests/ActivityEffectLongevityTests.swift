import XCTest
import Metal
import QuotaViewCore
@testable import QuotaView

final class ActivityEffectLongevityTests: XCTestCase {
    private func compute(_ kernel: String, count: Int) throws -> [Float] {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw XCTSkip("Metal unavailable") }
        let library = try device.makeLibrary(source: activityStateSmokeShaderSource + kernel, options: nil)
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "longevity")))
        let buffer = try XCTUnwrap(device.makeBuffer(length: count * 4, options: .storageModeShared))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: Float.self, capacity: count), count: count))
    }

    func testNoiseDoesNotCollapseAfterHoursOfWorkingDisplacement() throws {
        let values = try compute("""
        kernel void longevity(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            uint sample = id % 4096;
            float hours = float(id / 4096);
            float2 cell = float2(float(sample % 64) - hours * 3600.0 * 16.0 / 2.35,
                                float(sample / 64));
            out[id] = activityStateSmokeHash(floor(cell) + 31.0);
        }
        """, count: 4096 * 25)
        for hour in 0..<25 {
            let bins = Set(values[(hour * 4096)..<((hour + 1) * 4096)].map { Int($0 * 256) })
            print("noise hour=\(hour) occupiedBins=\(bins.count)")
            XCTAssertGreaterThan(bins.count, 200, "hour \(hour): noise must not collapse into repeated rows")
        }
    }
    func testBoundedClocksRemainResponsiveAfterThirtyDays() {
        var clock = ActivityEffectClock()
        clock.advance(30 * 24 * 3600 + 255.99)
        XCTAssertEqual(clock.value, 255.99, accuracy: 0.000001)
        clock.advance(0.02)
        XCTAssertEqual(clock.value, 0.01, accuracy: 0.000001)
        clock.advance(.infinity)
        clock.advance(.nan)
        XCTAssertEqual(clock.value, 0.01, accuracy: 0.000001)

        var simulation = CodexActivityStateSmokeSimulation()
        let profile = CodexActivityStateSmokeProfile.profile(for: .working)
        for _ in 0..<30 * 24 * 60 { simulation.step(delta: 60, profile: profile) }
        let before = simulation.fieldTime
        simulation.step(profile: profile)
        XCTAssertTrue(simulation.fieldTime.isFinite)
        XCTAssertNotEqual(simulation.fieldTime, before)
        XCTAssertLessThan(simulation.fieldTime, 256)
        XCTAssertLessThan(simulation.effectTime, 256)
    }

    func testQuantumMotionStaysBoundedAndMovingForTwentyFourHours() {
        var motion = ActivityQuantumMotion()
        for _ in 0..<24 * 3600 * 4 {
            motion.advance(state: .working, elapsed: 0.25, reduceMotion: false)
        }
        XCTAssertLessThan(abs(Double(motion.displacement.x)), ActivityQuantumMotion.displacementPeriod)
        XCTAssertLessThan(motion.phase, 256)
        let before = motion.displacement.x
        motion.advance(state: .working, elapsed: 1 / 60, reduceMotion: false)
        XCTAssertEqual(motion.displacement.x - before, -16 / 60, accuracy: 0.002)
        let frozen = motion.displacement
        motion.advance(state: .compactingContext, elapsed: 0.25, reduceMotion: true)
        XCTAssertEqual(motion.displacement, frozen)
    }

    func testAllFourRenderedEffectsAreContinuousAtClockRollover() throws {
        // Production shading, including the overlap, at both sides of the epoch.
        // Eight samples: four styles, each just before and just after rollover.
        let plane = 256 * 68
        let values = try compute("""
        kernel void longevity(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            uint pixel = id % (256 * 68);
            uint frame = id / (256 * 68);
            ActivityStateSmokeUniforms u = {};
            u.resolution = float2(256, 68);
            u.frontPosition = 0.75;
            u.pulse = 0.5; u.energy = 1; u.turbulence = 0.7;
            u.diffusion = 0.8; u.diffusionSpeed = 0.7; u.diffusionSpeedVariation = 0.2;
            u.effectStyle = float(frame / 2);
            u.fieldTime = frame % 2 == 0 ? 255.9999 : 0.0001;
            u.quantumClock = float4(-100.5, 0, u.fieldTime, 0);
            u.quantumWeights = float4(0, 1, 0, 0);
            u.quantumEnabled = float4(1, 1, 0, 0);
            u.deepColor = float4(0.1, 0.2, 0.4, 1);
            u.midColor = float4(0.2, 0.4, 0.7, 1);
            u.highlightColor = float4(0.3, 0.8, 1, 1);
            u.completionSmokeOpacity = 1;
            u.opacityStopPositions = float4(0, 0.333333, 0.666667, 1);
            u.opacityStopOpacities = float4(0.5, 0.666667, 0.833333, 1);
            VertexOut v = {};
            v.uv = (float2(pixel % 256, pixel / 256) + 0.5) / u.resolution;
            out[id] = length(activityStateSmokeLoopedSample(v, u).rgb);
        }
        """, count: plane * 8)
        for effect in 0..<4 {
            var sum: Float = 0
            var maximum: Float = 0
            for pixel in 0..<plane {
                let a = values[effect * 2 * plane + pixel]
                let b = values[(effect * 2 + 1) * plane + pixel]
                XCTAssertTrue(a.isFinite && b.isFinite)
                let difference = abs(a - b)
                sum += difference
                maximum = max(maximum, difference)
            }
            XCTAssertLessThan(sum / Float(plane), 0.002, "style \(effect)")
            XCTAssertLessThan(maximum, 0.03, "style \(effect)")
        }
    }

    func testQuantumLatticeWrapPreservesParticleIdentity() throws {
        let values = try compute("""
        kernel void longevity(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            uint pixel = id % 4096;
            float offset = id < 4096 ? -4096.0 * 2.35 : 0.0;
            float2 cell; float seed;
            out[id] = activityQuantumGrain(float2(float(pixel % 64) + 0.37 + offset,
                                                 float(pixel / 64) + 0.29), cell, seed);
        }
        """, count: 8192)
        var error: Float = 0
        for i in 0..<4096 { error += abs(values[i] - values[i + 4096]) }
        XCTAssertLessThan(error / 4096, 0.002)
    }

}
