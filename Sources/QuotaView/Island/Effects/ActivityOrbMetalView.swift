import AppKit
import MetalKit
import QuartzCore
import QuotaViewCore
import simd

private extension CodexActivityVisualState {

    var activityOrbStyle: ActivityOrbStyle {
        switch self {
        case .disconnectedCodex:
            ActivityOrbStyle(
                primary: activityRGBA(0.13, 0.17, 0.24),
                secondary: activityRGBA(0.28, 0.34, 0.44),
                accent: activityRGBA(0.48, 0.57, 0.70),
                speed: 0.032,
                speedFloor: 0.24,
                motionCycle: 17.0,
                tempo: 0.44,
                response: 1.15,
                energy: 0.46,
                turbulence: 0.08,
                pulse: 0.06,
                desaturation: 0.34,
                volume: 0.38,
                refraction: 0.42
            )
        case .standby:
            ActivityOrbStyle(
                primary: activityRGBA(0.12, 0.23, 0.42),
                secondary: activityRGBA(0.25, 0.35, 0.58),
                accent: activityRGBA(0.44, 0.56, 0.75),
                speed: 0.045,
                speedFloor: 0.28,
                motionCycle: 16.0,
                tempo: 0.58,
                response: 1.25,
                energy: 0.50,
                turbulence: 0.12,
                pulse: 0.05,
                desaturation: 0.18,
                volume: 0.44,
                refraction: 0.50
            )
        case .thinking:
            ActivityOrbStyle(
                primary: activityRGBA(0.20, 0.12, 0.68),
                secondary: activityRGBA(0.50, 0.23, 0.88),
                accent: activityRGBA(0.34, 0.57, 1.00),
                speed: 0.14,
                speedFloor: 0.22,
                motionCycle: 11.0,
                tempo: 0.82,
                response: 1.55,
                energy: 0.86,
                turbulence: 0.34,
                pulse: 0.18,
                desaturation: 0,
                volume: 0.76,
                refraction: 0.74
            )
        case .working:
            ActivityOrbStyle(
                primary: activityRGBA(0.04, 0.30, 0.78),
                secondary: activityRGBA(0.02, 0.65, 0.90),
                accent: activityRGBA(0.28, 0.94, 0.84),
                speed: 0.24,
                speedFloor: 0.18,
                motionCycle: 8.5,
                tempo: 1.05,
                response: 1.85,
                energy: 1.02,
                turbulence: 0.58,
                pulse: 0.22,
                desaturation: 0,
                volume: 0.94,
                refraction: 0.84
            )
        case .compactingContext:
            ActivityOrbStyle(
                primary: activityRGBA(0.50, 0.56, 0.66),
                secondary: activityRGBA(0.82, 0.86, 0.93),
                accent: activityRGBA(1.00, 1.00, 1.00),
                speed: 0.16,
                speedFloor: 0.20,
                motionCycle: 9.5,
                tempo: 0.90,
                response: 1.80,
                energy: 1.02,
                turbulence: 0.48,
                pulse: 0.30,
                desaturation: 0.12,
                volume: 0.94,
                refraction: 0.90,
                compression: 1
            )
        case .awaitingConfirmation:
            ActivityOrbStyle(
                primary: activityRGBA(0.55, 0.21, 0.02),
                secondary: activityRGBA(0.95, 0.46, 0.05),
                accent: activityRGBA(1.00, 0.78, 0.22),
                speed: 0.075,
                speedFloor: 0.18,
                motionCycle: 12.0,
                tempo: 0.72,
                response: 1.45,
                energy: 0.92,
                turbulence: 0.20,
                pulse: 0.46,
                desaturation: 0,
                volume: 0.68,
                refraction: 0.82
            )
        case .completed:
            ActivityOrbStyle(
                primary: activityRGBA(0.18, 0.12, 0.52),
                secondary: activityRGBA(0.26, 0.48, 0.88),
                accent: activityRGBA(0.43, 0.89, 1.00),
                speed: 0.055,
                speedFloor: 0.20,
                motionCycle: 13.0,
                tempo: 0.55,
                response: 1.20,
                energy: 0.82,
                turbulence: 0.12,
                pulse: 0.12,
                desaturation: 0,
                volume: 0.62,
                refraction: 0.68
            )
        case .error:
            ActivityOrbStyle(
                primary: activityRGBA(0.55, 0.01, 0.05),
                secondary: activityRGBA(0.92, 0.08, 0.14),
                accent: activityRGBA(1.00, 0.36, 0.22),
                speed: 0.13,
                speedFloor: 0.22,
                motionCycle: 8.0,
                tempo: 0.92,
                response: 2.10,
                energy: 0.96,
                turbulence: 0.62,
                pulse: 0.28,
                desaturation: 0,
                volume: 0.82,
                refraction: 0.62
            )
        case .unavailable:
            ActivityOrbStyle(
                primary: activityRGBA(0.23, 0.25, 0.30),
                secondary: activityRGBA(0.36, 0.38, 0.43),
                accent: activityRGBA(0.50, 0.53, 0.58),
                speed: 0.015,
                speedFloor: 0.15,
                motionCycle: 18.0,
                tempo: 0.28,
                response: 1.00,
                energy: 0.36,
                turbulence: 0.03,
                pulse: 0,
                desaturation: 0.88,
                volume: 0.24,
                refraction: 0.18
            )
        }
    }
}

private func activityRGBA(
    _ red: Float,
    _ green: Float,
    _ blue: Float,
    _ alpha: Float = 1
) -> SIMD4<Float> {
    SIMD4<Float>(red, green, blue, alpha)
}

private struct ActivityOrbStyle {
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
    var speed: Float
    var speedFloor: Float
    var motionCycle: Float
    var tempo: Float
    var response: Float
    var energy: Float
    var turbulence: Float
    var pulse: Float
    var desaturation: Float
    var volume: Float
    var refraction: Float
    var compression: Float = 0

    mutating func approach(
        _ target: ActivityOrbStyle,
        factor: Float
    ) {
        primary += (target.primary - primary) * factor
        secondary += (target.secondary - secondary) * factor
        accent += (target.accent - accent) * factor
        speed += (target.speed - speed) * factor
        speedFloor += (target.speedFloor - speedFloor) * factor
        motionCycle += (target.motionCycle - motionCycle) * factor
        tempo += (target.tempo - tempo) * factor
        response += (target.response - response) * factor
        energy += (target.energy - energy) * factor
        turbulence += (target.turbulence - turbulence) * factor
        pulse += (target.pulse - pulse) * factor
        desaturation += (target.desaturation - desaturation) * factor
        volume += (target.volume - volume) * factor
        refraction += (target.refraction - refraction) * factor
        compression += (target.compression - compression) * factor
    }
}

private func activityMotionSpeedMultiplier(
    elapsed: Float,
    speedFloor: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let position =
        max(elapsed, 0).truncatingRemainder(dividingBy: safeCycle)
        / safeCycle
    let envelope = 0.5 - 0.5 * cos(position * 2 * .pi)
    let floor = min(max(speedFloor, 0), 1)
    return floor + (1 - floor) * envelope
}

private func activityCompressionPulse(
    elapsed: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let position =
        max(elapsed, 0).truncatingRemainder(dividingBy: safeCycle)
        / safeCycle
    return 0.5 - 0.5 * cos(position * 2 * .pi)
}

private func activityCompressionBounce(
    elapsed: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let phase =
        max(elapsed, 0).truncatingRemainder(dividingBy: safeCycle)
        / safeCycle

    func raisedCosinePulse(center: Float, halfWidth: Float) -> Float {
        let distance = abs(phase - center)
        guard distance < halfWidth else { return 0 }
        return 0.5 + 0.5 * cos(.pi * distance / halfWidth)
    }

    let primary = raisedCosinePulse(center: 0.34, halfWidth: 0.20)
    let rebound =
        raisedCosinePulse(center: 0.64, halfWidth: 0.14) * 0.46
    return max(primary, rebound)
}

private struct ActivityOrbUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var motionPhase: Float
    var energy: Float
    var turbulence: Float
    var pulse: Float
    var desaturation: Float
    var volume: Float
    var refraction: Float
    var tempo: Float
    var motionEnergy: Float
    var compression: Float
    var compressionPulse: Float
    var compressionBounce: Float
    var reserved1: Float
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
}

private let activityOrbMotionSpeedScale: Float = 16.0
private let activityOrbRotationPhaseGain: Float = 1.45
private let activityOrbFluidPhaseGain: Float = 2.80
private let activityOrbSurfacePhaseGain: Float = 2.20
private let activityCompressionCycle: Float = 3.2
let activityOrbSphereRadius: Float = 0.535

private let activityOrbShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct ActivityOrbUniforms {
    float2 resolution;
    float time;
    float motionPhase;

    float energy;
    float turbulence;
    float pulse;
    float desaturation;

    float volume;
    float refraction;
    float tempo;
    float motionEnergy;

    float compression;
    float compressionPulse;
    float compressionBounce;
    float reserved1;

    float4 primary;
    float4 secondary;
    float4 accent;
};

vertex VertexOut activityOrbVertex(uint vertexID [[vertex_id]]) {
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

float activityHash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float activityValueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            activityHash21(i),
            activityHash21(i + float2(1.0, 0.0)),
            u.x
        ),
        mix(
            activityHash21(i + float2(0.0, 1.0)),
            activityHash21(i + 1.0),
            u.x
        ),
        u.y
    );
}

float activitySoftBand(float distance, float width) {
    float normalized = distance / max(width, 0.0001);
    return exp(-normalized * normalized);
}

float2 activityRotate2D(float2 value, float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return float2(
        value.x * cosine - value.y * sine,
        value.x * sine + value.y * cosine
    );
}

float3 activityRotateVolume(float3 value, float time) {
    value.xz = activityRotate2D(value.xz, time * 0.31 + 0.42);
    value.xy = activityRotate2D(value.xy, -time * 0.23 - 0.18);
    value.yz = activityRotate2D(value.yz, time * 0.17 + 0.28);
    return value;
}

float activityFluidField(
    float3 point,
    float time,
    float turbulence
) {
    float3 warped = point;
    warped.x += sin(point.y * 3.2 + time * 1.10) *
        (0.10 + turbulence * 0.10);
    warped.y += sin(point.z * 3.8 - time * 0.84) *
        (0.09 + turbulence * 0.12);
    warped.z += cos(point.x * 4.1 + time * 0.72) *
        (0.08 + turbulence * 0.11);

    float broad =
        sin(warped.x * 3.8 + time * 0.55) +
        sin(warped.y * 4.4 - time * 0.47) +
        sin(warped.z * 4.0 + time * 0.38);
    float detail =
        sin((warped.x + warped.y) * 7.2 - time * 0.92) +
        cos((warped.y - warped.z) * 6.1 + time * 0.68);

    return broad * 0.30 + detail * 0.13;
}

fragment float4 activityOrbFragment(
    VertexOut in [[stage_in]],
    constant ActivityOrbUniforms &u [[buffer(0)]]
) {
    float2 p = (in.uv - 0.5) * 2.0;
    p.x *= u.resolution.x / max(u.resolution.y, 1.0);

    float rotationTime =
        u.motionPhase * \(activityOrbRotationPhaseGain);
    float fluidTime =
        u.motionPhase * \(activityOrbFluidPhaseGain);
    float surfaceTime =
        u.motionPhase * \(activityOrbSurfacePhaseGain);
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float compressionAmount =
        u.compression *
        (
            0.20 +
            u.compressionPulse * 0.62 +
            u.compressionBounce * 0.28
        );
    float wholeSphereCompression =
        u.compression * u.compressionBounce;
    float directionalPressure =
        0.5 +
        0.5 * cos(angle * 2.0 + u.time * 0.42);
    float animatedTurbulence =
        u.turbulence * (0.84 + u.motionEnergy * 0.20);
    float breathing =
        sin(u.time * u.tempo) *
        (0.006 + u.pulse * 0.010);
    float sphereRadius =
        \(activityOrbSphereRadius) +
        breathing -
        compressionAmount *
        (0.034 + directionalPressure * 0.018) -
        wholeSphereCompression * 0.050;
    float sphereDistance = abs(radius - sphereRadius);

    if (radius > sphereRadius + 0.18) {
        return float4(0.0);
    }

    float3 primary = u.primary.rgb;
    float3 secondary = u.secondary.rgb;
    float3 accent = u.accent.rgb;

    float normalizedRadius = radius / max(sphereRadius, 0.001);
    float inside = 1.0 - step(1.0, normalizedRadius);
    float zExtent = sqrt(
        max(0.0, 1.0 - normalizedRadius * normalizedRadius)
    );
    float3 normal = normalize(float3(
        p / max(sphereRadius, 0.001),
        zExtent
    ));

    float fresnel = pow(
        saturate(1.0 - max(normal.z, 0.0)),
        2.25
    );
    float rim = smoothstep(0.10, 0.96, fresnel);
    float3 keyLight = normalize(float3(-0.48, 0.64, 0.82));
    float specular = pow(
        saturate(dot(normal, keyLight)),
        38.0
    );

    float3 volumeColor = float3(0.0);
    float volumeAlpha = 0.0;
    constexpr int sampleCount = 20;

    for (int index = 0; index < sampleCount; ++index) {
        float samplePosition =
            (float(index) + 0.5) / float(sampleCount);
        float sampleZ = mix(-zExtent, zExtent, samplePosition);
        float3 samplePoint = float3(
            p / max(sphereRadius, 0.001),
            sampleZ
        );
        float inwardScale =
            1.0 +
            compressionAmount *
            (
                0.18 +
                0.16 * (1.0 - abs(sampleZ))
            );
        samplePoint.xy *= inwardScale;
        samplePoint.z *= 1.0 + compressionAmount * 0.12;
        samplePoint = activityRotateVolume(
            samplePoint,
            rotationTime *
                (0.72 + animatedTurbulence * 0.42)
        );

        float field = activityFluidField(
            samplePoint * (1.16 + animatedTurbulence * 0.22),
            fluidTime,
            animatedTurbulence
        );
        float ribbon = exp(
            -abs(field) * (5.6 - u.volume * 1.8)
        );
        float filament = exp(
            -abs(
                field +
                sin(
                    samplePoint.x * 6.0 -
                    samplePoint.z * 4.0 +
                    fluidTime
                ) * 0.20
            ) * 12.0
        );
        float depthFade =
            0.46 +
            0.54 * sin(samplePosition * M_PI_F);
        float density =
            (ribbon * 0.62 + filament * 0.52) *
            depthFade *
            (0.018 + u.volume * 0.020) *
            (1.0 + compressionAmount * 0.46);

        float colorPhase = fract(
            samplePosition * 0.78 +
            field * 0.15 +
            angle / (2.0 * M_PI_F) -
            fluidTime * 0.035
        );
        float3 sampleColor =
            colorPhase < 0.5
            ? mix(primary, secondary, colorPhase * 2.0)
            : mix(
                secondary,
                accent,
                (colorPhase - 0.5) * 2.0
            );

        float remaining = 1.0 - volumeAlpha;
        volumeColor +=
            remaining *
            sampleColor *
            density *
            (1.65 + u.energy * 1.12);
        volumeAlpha += remaining * density;
    }

    volumeColor *= inside;
    volumeAlpha *= inside;

    float normalizedX = p.x / max(sphereRadius, 0.001);
    float normalizedY = p.y / max(sphereRadius, 0.001);
    float projectedWaveA =
        normalizedY -
        sin(
            normalizedX * (4.2 + animatedTurbulence * 1.8) +
            surfaceTime * 1.55 +
            zExtent * 2.1
        ) * (0.17 + animatedTurbulence * 0.08);
    float projectedWaveB =
        normalizedX +
        cos(
            normalizedY * (4.8 + animatedTurbulence * 1.2) -
            surfaceTime * 1.12 -
            zExtent * 1.7
        ) * (0.15 + animatedTurbulence * 0.07);
    float projectedRibbonA = activitySoftBand(
        projectedWaveA,
        0.065 + animatedTurbulence * 0.020
    );
    float projectedRibbonB = activitySoftBand(
        projectedWaveB,
        0.080 + animatedTurbulence * 0.018
    );
    float projectedRibbon =
        inside *
        (projectedRibbonA * 0.72 + projectedRibbonB * 0.44) *
        (0.38 + zExtent * 0.62);
    float inwardFront = mix(
        0.92,
        0.18,
        u.compressionPulse
    );
    float inwardBand =
        exp(
            -abs(normalizedRadius - inwardFront) *
            (16.0 + u.compressionPulse * 8.0)
        ) *
        inside *
        u.compression;
    float compressedCore =
        exp(-normalizedRadius * 5.2) *
        inside *
        u.compression *
        u.compressionPulse;
    projectedRibbon +=
        inwardBand *
        (0.36 + u.compressionPulse * 0.28);
    float projectedPhase =
        0.5 +
        0.5 * sin(
            angle * 2.4 -
            surfaceTime * 1.3 +
            zExtent * 3.4
        );
    float3 projectedColor = mix(
        mix(primary, secondary, projectedPhase),
        accent,
        saturate(
            projectedRibbonB * 0.44 +
            inwardBand * 0.72 +
            compressedCore * 0.26
        )
    );

    float chromaRed = activitySoftBand(
        abs(radius - sphereRadius - 0.006 * u.refraction),
        0.012 + u.refraction * 0.005
    );
    float chromaGreen = activitySoftBand(
        abs(radius - sphereRadius),
        0.011
    );
    float chromaBlue = activitySoftBand(
        abs(radius - sphereRadius + 0.008 * u.refraction),
        0.014 + u.refraction * 0.004
    );
    float3 chromaticRim = float3(
        chromaRed,
        chromaGreen,
        chromaBlue
    );
    chromaticRim *= mix(
        primary,
        accent,
        0.5 +
            0.5 * sin(angle * 2.0 - surfaceTime * 1.2)
    );

    float caustic =
        pow(
            max(
                0.0,
                0.5 +
                0.5 *
                cos(
                    angle * 1.4 -
                    surfaceTime * 1.8 -
                    0.7
                )
            ),
            18.0
        ) *
        activitySoftBand(sphereDistance, 0.026);
    float halo = exp(
        -sphereDistance * (12.0 - u.energy * 1.8)
    );

    float glassTint = inside * (
        0.035 +
        rim * 0.14 +
        specular * 0.24
    );
    float3 glassColor =
        mix(primary, accent, fresnel) * glassTint +
        float3(0.72, 0.86, 1.0) * specular * 0.54;

    float3 color =
        volumeColor * (1.18 + u.volume * 0.74) +
        projectedColor *
            projectedRibbon *
            (0.32 + u.volume * 0.64) +
        mix(primary, secondary, projectedPhase) *
            inside *
            zExtent *
            0.035 *
            u.volume +
        glassColor +
        chromaticRim * (0.34 + u.refraction * 0.50) +
        accent * caustic * (0.60 + u.energy * 0.72) +
        mix(secondary, accent, 0.76) *
            (
                inwardBand * 0.34 +
                compressedCore * 0.24
            ) +
        mix(primary, secondary, 0.5) *
            halo *
            0.075 *
            u.energy;

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    color = mix(color, float3(luma), saturate(u.desaturation));

    float alpha =
        volumeAlpha * (0.82 + u.volume * 0.42) +
        projectedRibbon * (0.18 + u.volume * 0.28) +
        inwardBand * 0.12 +
        compressedCore * 0.08 +
        rim * inside * (0.24 + u.refraction * 0.30) +
        specular * inside * 0.48 +
        max(max(chromaRed, chromaGreen), chromaBlue) * 0.64 +
        halo * 0.10 * u.energy;

    alpha *= 1.0 - smoothstep(
        sphereRadius + 0.12,
        sphereRadius + 0.18,
        radius
    );
    color *=
        0.94 +
        0.06 *
        sin(u.time * u.tempo * 0.78) *
        u.pulse;

    return float4(max(color, 0.0), saturate(alpha));
}
"""

private final class ActivityOrbRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()

    private var currentStyle: ActivityOrbStyle
    private var targetStyle: ActivityOrbStyle
    private var activeState: CodexActivityVisualState
    private var reduceMotion = false
    private var stateElapsed: Float = 0
    private var motionPhase: Float = 0

    init?(
        view: MTKView,
        initialState: CodexActivityVisualState
    ) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.wantsLayer = true
        view.layer?.isOpaque = false

        do {
            let library = try device.makeLibrary(
                source: activityOrbShaderSource,
                options: nil
            )
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(
                name: "activityOrbVertex"
            )
            descriptor.fragmentFunction = library.makeFunction(
                name: "activityOrbFragment"
            )
            descriptor.colorAttachments[0].pixelFormat =
                view.colorPixelFormat

            if let attachment = descriptor.colorAttachments[0] {
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor =
                    .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor =
                    .oneMinusSourceAlpha
            }

            pipelineState = try device.makeRenderPipelineState(
                descriptor: descriptor
            )
        } catch {
            return nil
        }

        self.commandQueue = commandQueue
        currentStyle = initialState.activityOrbStyle
        targetStyle = initialState.activityOrbStyle
        activeState = initialState
        super.init()
        view.delegate = self
    }

    func setState(_ state: CodexActivityVisualState) {
        if state != activeState {
            activeState = state
            stateElapsed = 0
        }
        targetStyle = state.activityOrbStyle
        if reduceMotion {
            currentStyle = targetStyle
        }
    }

    func setReduceMotion(_ enabled: Bool, in view: MTKView) {
        guard reduceMotion != enabled else { return }
        reduceMotion = enabled
        if enabled {
            currentStyle = targetStyle
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.needsDisplay = true
        } else {
            stateElapsed = 0
            lastFrameTime = CACurrentMediaTime()
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        }
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor =
                view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              )
        else {
            return
        }

        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastFrameTime, 1.0 / 15.0))
        lastFrameTime = now

        if reduceMotion {
            currentStyle = targetStyle
        } else {
            let transitionFactor = min(
                1,
                delta * max(0.4, targetStyle.response)
            )
            currentStyle.approach(
                targetStyle,
                factor: transitionFactor
            )
            stateElapsed += delta
            let speedMultiplier = activityMotionSpeedMultiplier(
                elapsed: stateElapsed,
                speedFloor: currentStyle.speedFloor,
                cycle: currentStyle.motionCycle
            )
            motionPhase +=
                delta *
                currentStyle.speed *
                speedMultiplier *
                activityOrbMotionSpeedScale
            if motionPhase > 4096 {
                motionPhase.formTruncatingRemainder(dividingBy: 4096)
            }
        }

        let motionEnergy = reduceMotion
            ? Float(0)
            : activityMotionSpeedMultiplier(
                elapsed: stateElapsed,
                speedFloor: 0,
                cycle: currentStyle.motionCycle
            )
        let compressionPulse = reduceMotion
            ? Float(0.72)
            : activityCompressionPulse(
                elapsed: stateElapsed,
                cycle: activityCompressionCycle
            )
        let compressionBounce = reduceMotion
            ? Float(0.68)
            : activityCompressionBounce(
                elapsed: stateElapsed,
                cycle: activityCompressionCycle
            )

        var uniforms = ActivityOrbUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            time: reduceMotion ? 0.35 : Float(now - startTime),
            motionPhase: motionPhase,
            energy: currentStyle.energy,
            turbulence: reduceMotion
                ? 0.04
                : currentStyle.turbulence,
            pulse: reduceMotion ? 0 : currentStyle.pulse,
            desaturation: currentStyle.desaturation,
            volume: currentStyle.volume,
            refraction: currentStyle.refraction,
            tempo: reduceMotion ? 0 : currentStyle.tempo,
            motionEnergy: motionEnergy,
            compression: currentStyle.compression,
            compressionPulse: compressionPulse,
            compressionBounce: compressionBounce,
            reserved1: 0,
            primary: currentStyle.primary,
            secondary: currentStyle.secondary,
            accent: currentStyle.accent
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<ActivityOrbUniforms>.stride,
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
    }
}

private final class ActivityMetalOrbView: MTKView {
    private var renderer: ActivityOrbRenderer?

    init(
        frame: NSRect,
        initialState: CodexActivityVisualState
    ) {
        super.init(
            frame: frame,
            device: MTLCreateSystemDefaultDevice()
        )
        renderer = ActivityOrbRenderer(
            view: self,
            initialState: initialState
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setState(_ state: CodexActivityVisualState) {
        renderer?.setState(state)
        if isPaused {
            needsDisplay = true
        }
    }

    func setReduceMotion(_ enabled: Bool) {
        renderer?.setReduceMotion(enabled, in: self)
    }

    func redrawIfPaused() {
        if isPaused {
            needsDisplay = true
        }
    }
}

final class ActivitySelectableOrbView: NSView {
    private var particleView: ActivityMetalOrbView?
    private var rippleGlowView: ActivityRippleGlowMetalView?
    private var activeView: NSView?
    var hasParticleRenderer: Bool { particleView != nil }
    var hasRippleGlowRenderer: Bool { rippleGlowView != nil }
    private var state: CodexActivityVisualState
    private var animation: AppPreferences.CodexActivityOrbAnimation
    private var reduceMotion = false
    private var playbackEnabled = true

    override var isOpaque: Bool { false }

    init(
        frame: NSRect,
        initialState: CodexActivityVisualState,
        animation: AppPreferences.CodexActivityOrbAnimation
    ) {
        state = initialState
        self.animation = animation
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAnimation(animation)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        activeView?.frame = bounds
        redrawIfPaused()
    }

    func setAnimation(
        _ newAnimation: AppPreferences.CodexActivityOrbAnimation
    ) {
        let requestedView: NSView
        switch newAnimation {
        case .particleOrb:
            requestedView = makeParticleViewIfNeeded()
        case .rippleGlow:
            if rippleGlowView == nil {
                let candidate = ActivityRippleGlowMetalView(
                    frame: bounds,
                    initialState: state
                )
                if candidate.isRendererAvailable {
                    rippleGlowView = candidate
                }
            }
            requestedView = rippleGlowView ?? makeParticleViewIfNeeded()
        }

        animation = newAnimation
        guard activeView !== requestedView else {
            setReduceMotion(reduceMotion)
            return
        }

        particleView?.setReduceMotion(true)
        rippleGlowView?.setReduceMotion(true)
        activeView?.removeFromSuperview()
        activeView = requestedView
        requestedView.frame = bounds
        addSubview(requestedView)
        updatePlaybackState()
    }

    private func makeParticleViewIfNeeded() -> ActivityMetalOrbView {
        if let particleView { return particleView }
        let view = ActivityMetalOrbView(frame: bounds, initialState: state)
        particleView = view
        return view
    }

    func setCardCompletionPhase(_ phase: IslandCardCompletionPhase?) {
        rippleGlowView?.cardCompletionPhase = phase
    }

    func setState(_ newState: CodexActivityVisualState) {
        state = newState
        particleView?.setState(newState)
        rippleGlowView?.setState(newState)
        redrawIfPaused()
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        updatePlaybackState()
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        playbackEnabled = enabled
        updatePlaybackState()
    }

    private func updatePlaybackState() {
        particleView?.setReduceMotion(
            reduceMotion
                || !playbackEnabled
                || activeView !== particleView
        )
        if let rippleGlowView {
            rippleGlowView.setReduceMotion(
                reduceMotion
                    || !playbackEnabled
                    || activeView !== rippleGlowView
            )
        }
    }

    func redrawIfPaused() {
        particleView?.redrawIfPaused()
        rippleGlowView?.redrawIfPaused()
    }
}

// Hosts the selectable orb in the live island.
@MainActor
final class IslandActivityOrbHost: NSView {
    // Only the tiny orb canvas is supersampled, never the island or text.
    static let renderScale: CGFloat = 2
    private let orb: ActivitySelectableOrbView
    private var configuredState: CodexActivityVisualState
    private var requestedPlayback = false
    private(set) var playbackActive = false
    var isRendering: Bool { orb.subviews.compactMap { $0 as? MTKView }.contains { !$0.isPaused } }
    var usesRippleGlow: Bool { orb.subviews.contains { $0 is ActivityRippleGlowMetalView } }
    var drawableSize: CGSize { orb.subviews.compactMap { $0 as? MTKView }.first?.drawableSize ?? .zero }
    var backingPixelSize: CGSize {
        guard let view = orb.subviews.compactMap({ $0 as? MTKView }).first else { return .zero }
        let size = view.convertToBacking(view.bounds).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
    init(state: CodexActivityVisualState) {
        configuredState = state
        orb = ActivitySelectableOrbView(frame: .zero, initialState: state, animation: .rippleGlow)
        super.init(frame: .zero)
        clipsToBounds = false
        orb.clipsToBounds = false
        orb.setPlaybackEnabled(false)
        addSubview(orb)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height) / CGFloat(CodexActivityRippleGlowContract.sphereRadius)
        let next = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        if orb.frame != next { orb.frame = next; orb.redrawIfPaused() }
        orb.layoutSubtreeIfNeeded()
        synchronizeResolution()
    }
    func configure(state: CodexActivityVisualState, playback: Bool, completionPhase: IslandCardCompletionPhase? = nil) {
        orb.setCardCompletionPhase(completionPhase)
        if configuredState != state {
            configuredState = state; orb.setState(state)
        }
        requestedPlayback = playback
        synchronizePlayback()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        synchronizePlayback()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
        synchronizeResolution()
    }
    private func synchronizeResolution() {
        guard let window else { return }
        for view in orb.subviews.compactMap({ $0 as? MTKView }) {
            view.autoResizeDrawable = false
            view.layer?.contentsScale = window.backingScaleFactor
            view.layer?.minificationFilter = .linear
            view.layer?.magnificationFilter = .linear
            let size = view.convertToBacking(view.bounds).size
            let pixels = CGSize(width: ceil(size.width) * Self.renderScale,
                                height: ceil(size.height) * Self.renderScale)
            if pixels.width > 0, pixels.height > 0, view.drawableSize != pixels {
                view.drawableSize = pixels
                orb.redrawIfPaused()
            }
        }
    }
    private func synchronizePlayback() {
        let active = requestedPlayback && window != nil
        guard playbackActive != active else { return }
        playbackActive = active
        orb.setPlaybackEnabled(playbackActive)
    }
    func stop() { requestedPlayback = false; synchronizePlayback() }
}
