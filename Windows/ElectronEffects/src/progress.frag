#version 300 es
precision highp float;
precision highp int;
// Derived from QuotaView v0.7.7-build.1 (3866177cfa19db734d657ef505a4dc72c3338fba).
// MIT (c) 2026 Duoasa. Numeric shader formulas retained; host is Windows/OpenGL.
uniform float p[128];
in vec2 uv;
out vec4 fragColor;
struct ActivityStateSmokeUniforms {
    vec2 resolution;
    float frontPosition;
    float pulse;
    float fieldTime;
    float effectTime;
    float turbulence;
    float energy;
    float diffusion;
    float diffusionSpeed;
    float diffusionSpeedVariation;
    float grain;
    float effectStyle;
    float completionFillProgress;
    float completionEffectHighlight;
    float completionDarkening;
    float completionSmokeOpacity;
    float completionActive;
    vec4 quantumWeights;
    vec4 quantumClock;
    vec4 quantumEnabled;
    vec4 opacityStopPositions;
    vec4 opacityStopOpacities;
    vec4 background;
    vec4 deepColor;
    vec4 midColor;
    vec4 highlightColor;
};
ActivityStateSmokeUniforms loadUniforms() {
    ActivityStateSmokeUniforms u;
    u.resolution = vec2(p[0], p[1]);
    u.frontPosition = p[2];
    u.pulse = p[3];
    u.fieldTime = p[4];
    u.effectTime = p[5];
    u.turbulence = p[6];
    u.energy = p[7];
    u.diffusion = p[8];
    u.diffusionSpeed = p[9];
    u.diffusionSpeedVariation = p[10];
    u.grain = p[11];
    u.effectStyle = p[12];
    u.completionFillProgress = p[13];
    u.completionEffectHighlight = p[14];
    u.completionDarkening = p[15];
    u.completionSmokeOpacity = p[16];
    u.completionActive = p[17];
    u.quantumWeights = vec4(p[18], p[19], p[20], p[21]);
    u.quantumClock = vec4(p[22], p[23], p[24], p[25]);
    u.quantumEnabled = vec4(p[26], p[27], p[28], p[29]);
    u.opacityStopPositions = vec4(p[30], p[31], p[32], p[33]);
    u.opacityStopOpacities = vec4(p[34], p[35], p[36], p[37]);
    u.background = vec4(p[38], p[39], p[40], p[41]);
    u.deepColor = vec4(p[42], p[43], p[44], p[45]);
    u.midColor = vec4(p[46], p[47], p[48], p[49]);
    u.highlightColor = vec4(p[50], p[51], p[52], p[53]);
    return u;
}
float activityStateSmokeHash(vec2 p0) {
    // Integer avalanche avoids losing fractional randomness at large coordinates.
    // Quantization retains fractional seed offsets without large float products.
    uvec2 p = uvec2(ivec2(floor(p0 * 16.0)));
    uint h = p.x * 0x9e3779b9u ^ p.y * 0x85ebca6bu;
    h ^= h >> 16; h *= 0x7feb352du;
    h ^= h >> 15; h *= 0x846ca68bu;
    h ^= h >> 16;
    return float(h >> 8) * (1.0 / 16777216.0);
}

float activityStateSmokeValueNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 fraction = fract(p);
    vec2 weight = fraction * fraction * (3.0 - 2.0 * fraction);
    return mix(
        mix(
            activityStateSmokeHash(cell),
            activityStateSmokeHash(cell + vec2(1.0, 0.0)),
            weight.x
        ),
        mix(
            activityStateSmokeHash(cell + vec2(0.0, 1.0)),
            activityStateSmokeHash(cell + vec2(1.0, 1.0)),
            weight.x
        ),
        weight.y
    );
}

float activityStateSmokeFBM(vec2 p0) {
    float value = 0.0;
    float amplitude = 0.5;
    vec2 p = p0;
    for (int index = 0; index < 4; ++index) {
        value += amplitude * activityStateSmokeValueNoise(p);
        p = p * 2.03 + 11.7;
        amplitude *= 0.5;
    }
    return value;
}

float activityStateSmokeReverseSmoothstep(
    float edge0,
    float edge1,
    float value
) {
    float amount = clamp(
        (value - edge0) / (edge1 - edge0),
        0.0,
        1.0
    );
    return amount * amount * (3.0 - 2.0 * amount);
}

float activityStateSmokeOpacitySegment(
    float value,
    float fromPosition,
    float toPosition,
    float fromOpacity,
    float toOpacity
) {
    float distance = max(toPosition - fromPosition, 0.0001);
    float amount = clamp(
        (value - fromPosition) / distance,
        0.0,
        1.0
    );
    return mix(fromOpacity, toOpacity, amount);
}

float activityStateSmokeHorizontalOpacity(
    float relativeX,
    vec4 stopPositions,
    vec4 stopOpacities
) {
    if (relativeX <= stopPositions.y) {
        return activityStateSmokeOpacitySegment(
            relativeX,
            stopPositions.x,
            stopPositions.y,
            stopOpacities.x,
            stopOpacities.y
        );
    }
    if (relativeX <= stopPositions.z) {
        return activityStateSmokeOpacitySegment(
            relativeX,
            stopPositions.y,
            stopPositions.z,
            stopOpacities.y,
            stopOpacities.z
        );
    }
    return activityStateSmokeOpacitySegment(
        relativeX,
        stopPositions.z,
        stopPositions.w,
        stopOpacities.z,
        stopOpacities.w
    );
}

float activityProgressDiamondDensity(
    vec2 uv,
    float aspect,
    float front,
    float time,
    float pulse,
    float turbulence
) {
    float rows = 7.5;
    float columns = max(rows * aspect, 1.0);
    vec2 coordinate = vec2(uv.x * columns, uv.y * rows);
    float column = floor(coordinate.x);
    coordinate.y += (column - trunc(column / 2.0) * 2.0) * 0.5;
    vec2 cell = floor(coordinate);
    vec2 local = fract(coordinate) - 0.5;
    float distanceToDiamond = abs(local.x) + abs(local.y);
    float core = 1.0 - smoothstep(0.28, 0.47, distanceToDiamond);
    float bloom = exp(-max(distanceToDiamond - 0.25, 0.0) * 9.5);
    float seed = activityStateSmokeHash(cell + 17.0);
    float centerX = (cell.x + 0.5) / columns;
    float stagger = (seed - 0.5) * (0.028 + turbulence * 0.018);
    float shimmer =
        sin(time * 2.8 + seed * 6.2831853) * (0.004 + pulse * 0.005);
    float activated = 1.0 - smoothstep(
        front - 0.018,
        front + 0.032,
        centerX + stagger + shimmer
    );
    float edgeFocus = exp(-abs(centerX - front) * 15.0);
    return clamp(
        (core + bloom * (0.12 + edgeFocus * 0.20))
            * activated
            * (0.72 + edgeFocus * 0.28),
        0.0,
        1.0
    );
}

float activityProgressDropDensity(
    vec2 pixel,
    vec2 resolution,
    float front,
    float effectTime
) {
    float dropletCellSize = 2.35;
    vec2 drift = vec2(
        sin(effectTime * 0.63) * 0.46,
        effectTime * 0.68
    );
    vec2 coordinate = (pixel + drift) / dropletCellSize;
    vec2 cell = floor(coordinate);
    float shapeSeed = activityStateSmokeHash(cell + 31.0);
    vec2 jitter = vec2(
        activityStateSmokeHash(cell + 47.0),
        activityStateSmokeHash(cell + 83.0)
    ) - 0.5;
    vec2 local = fract(coordinate) - 0.5 - jitter * 0.22;
    float dotRadius = mix(0.17, 0.31, shapeSeed);
    float dotDistance = length(local);
    float microDrop = 1.0 - smoothstep(
        dotRadius,
        dotRadius + 0.10,
        dotDistance
    );
    float microBloom = exp(-max(dotDistance - dotRadius, 0.0) * 12.0);
    float centerX = clamp(
        ((cell.x + 0.5) * dropletCellSize - drift.x)
            / max(resolution.x, 1.0),
        0.0,
        1.0
    );
    float stagger =
        (activityStateSmokeHash(cell + 109.0) - 0.5)
        * 0.026;
    float frontDensity = 1.0 - smoothstep(
        front - 0.125,
        front + 0.002,
        centerX + stagger
    );
    float occupancySeed = activityStateSmokeHash(cell + 151.0);
    float occupancy = step(
        1.0 - frontDensity * 0.88,
        occupancySeed
    );
    float twinkleRate = mix(
        2.4,
        4.0,
        activityStateSmokeHash(cell + 197.0)
    );
    float twinkleWave = 0.5
        + 0.5
            * sin(
                effectTime * twinkleRate
                + shapeSeed * 6.2831853
            );
    float quantumNoiseOpacityBoost = 1.10;
    float sparkle = min(
        (0.22
            + twinkleWave * 0.62
            + pow(twinkleWave, 5.0) * 0.16)
            * quantumNoiseOpacityBoost,
        1.0
    );
    return clamp(
        (microDrop + microBloom * 0.08)
            * occupancy
            * sparkle,
        0.0,
        1.0
    );
}

vec3 activityQuantumOriginalColor(float density, ActivityStateSmokeUniforms u) {
    float breathing = 1.0 + (u.pulse - 0.5) * 0.18;

    vec3 color = u.background.rgb;
    color += u.deepColor.rgb * density * 0.72 * u.energy;
    color +=
        u.midColor.rgb
        * pow(density, 2.2)
        * 0.68
        * u.energy;
    color +=
        u.highlightColor.rgb
        * pow(density, 7.0)
        * 0.55
        * breathing
        * u.energy;
    if (u.effectStyle > 0.5) {
        float completionHighlightDensity = pow(density, 3.0);
        if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
            completionHighlightDensity = pow(density, 1.5);
        }
        color +=
            u.highlightColor.rgb
            * completionHighlightDensity
            * clamp(u.completionEffectHighlight, 0.0, 1.0)
            * u.energy;
    }
    return color;
}
// State-aware quantum starlight renderer. The particle field has no vertical envelope:
// only the production island's rounded clipping and horizontal progress apply.
float activityQuantumPulseCenter(float phase) {
    float cycle = fract(phase * 0.24);
    float eased = cycle * cycle * cycle * (cycle * (cycle * 6.0 - 15.0) + 10.0);
    return mix(-0.28, 1.28, eased);
}

float activityQuantumTransportPulse(vec2 pixel, vec2 resolution, float front, float phase) {
    float position = pixel.x / max(resolution.x * front, 1.0);
    float height = pixel.y / resolution.y;
    // A single irregular cluster passes through the field. Its centre accelerates
    // and decelerates; its curved, broken edge never becomes a straight light bar.
    float bend = 0.065 * sin(height * 7.0 + phase * 0.6)
        + 0.035 * sin(height * 19.0 - phase * 0.35);
    float width = 0.080 + 0.025 * sin(height * 11.0 + phase * 0.4);
    float cycle = fract(phase * 0.24);
    float gate = smoothstep(0.04, 0.16, cycle) * (1.0 - smoothstep(0.84, 0.96, cycle));
    return exp(-0.5 * pow((position - activityQuantumPulseCenter(phase) - bend) / width, 2.0)) * gate;
}

float activityQuantumFrontCoverage(vec2 pixel, vec2 resolution, float front, float completion) {
    if (front <= 0.0) { return 0.0; }
    float x = pixel.x / resolution.x;
    float y = pixel.y / resolution.y;
    // Estimated progress retains a visible dissolve even at 1%. A short front is
    // an uncertainty region, not a tiny precisely clipped bar. Keep dots crisp.
    float minimumFeather = min(48.0 / resolution.x, 0.18);
    float feather = clamp(front * 0.70, minimumFeather, 0.18);
    float retreat = feather * (0.10 + 0.05 * sin(y * 7.0) + 0.025 * sin(y * 19.0));
    float edge = max(front, minimumFeather) - retreat;
    float coverage = 1.0 - smoothstep(max(0.0, edge - feather), edge, x);
    // Approach zero continuously as progress first appears; standby stays empty.
    coverage *= smoothstep(0.0, 0.005, front);
    return mix(coverage, 1.0, smoothstep(0.75, 1.0, completion));
}

// Restore the early full-height prototype's independently phased neighbourhoods.
// Interpolate their influence so grouped light has no rectangular cell boundary.
float activityQuantumCompressionCoherence(vec2 pixel, float phase) {
    vec2 grid = pixel / 33.6; // Original neighbourhood: 7 grains at 4.8 px.
    vec2 cell = floor(grid);
    vec2 fraction = fract(grid);
    vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float value = 0.0;
    for (int row = 0; row < 2; ++row) {
        for (int column = 0; column < 2; ++column) {
            vec2 neighbour = cell + vec2(column, row);
            float seed = activityStateSmokeHash(neighbour + 263.0);
            float organize = 0.5 + 0.5 * sin(phase * 3.2 + seed * 6.283185);
            float weight = (column == 0 ? 1.0 - blend.x : blend.x)
                         * (row == 0 ? 1.0 - blend.y : blend.y);
            value += organize * weight;
        }
    }
    return value;
}

vec3 activityQuantumCompressionClusters(vec2 pixel, vec2 resolution, float front, float phase) {
    float organize = activityQuantumCompressionCoherence(pixel, phase);
    vec2 cell = floor(pixel / 2.35);
    vec2 jitter = vec2(activityStateSmokeHash(cell + 47.0),
                          activityStateSmokeHash(cell + 83.0)) - 0.5;
    // Original local reordering: jitter gently tightens and loosens with the group.
    // Keep the current original-grain scale and occupancy; do not adjoin stars.
    vec2 flow = jitter * (0.22 * 2.35 * 0.49) * organize;
    return vec3(flow, smoothstep(0.30, 0.88, organize));
}

// Completion retains its previous fill/settle field. This revision targets only
// context compression; the renderer passes completion through quantumEnabled.z.
vec3 activityQuantumCompletionClusters(vec2 pixel, vec2 resolution, float front, float phase) {
    // Staggered, short-lived star clusters form, loosen and re-form elsewhere.
    // Smooth envelopes hide reseeding; no tiles, aligned edges or solid glow layer.
    float width = max(resolution.x * front, 1.0);
    float count = clamp(ceil(width / 220.0), 1.0, 3.0);
    float highlight = 0.0;
    vec2 flow = vec2(0.0);
    for (int i = 0; i < 3; ++i) {
        if (float(i) >= count) { break; }
        float clock = phase / 4.8 - float(i) * 0.10;
        float generation = floor(clock);
        float age = fract(clock);
        vec2 key = vec2(generation, float(i) * 17.0);
        float rx = activityStateSmokeHash(key + 419.0);
        float ry = activityStateSmokeHash(key + 461.0);
        float life = smoothstep(0.0, 0.28, age) * (1.0 - smoothstep(0.65, 1.0, age));
        float gather = smoothstep(0.08, 0.48, age);
        float release = smoothstep(0.56, 1.0, age);
        float tightness = gather * (1.0 - release);
        // A shared curved spine gives neighbouring clusters a family resemblance.
        // Spacing and sequential gathering create order without rectangular cells.
        float slot = (float(i) + 0.40 + rx * 0.20) / count;
        float arc = slot * 4.2 + generation * 1.7;
        vec2 center = vec2(width * slot,
                              resolution.y * (0.50 + 0.38 * sin(arc)));
        center += vec2(sin(age * 5.0 + ry * 6.28) * 9.0,
                         sin(age * 4.0 + rx * 6.28) * 5.0);
        float radius = mix(66.0, 35.0, tightness);
        vec2 delta = pixel - center;
        float angle = atan(resolution.y * 0.38 * 4.2 * cos(arc), width)
                    + sin(age * 3.0 + ry * 6.28) * 0.22;
        vec2 local = vec2(delta.x * cos(angle) + delta.y * sin(angle),
                            -delta.x * sin(angle) + delta.y * cos(angle));
        local /= vec2(radius * (1.1 + rx * 0.35), radius * (0.75 + ry * 0.25));
        float theta = atan(local.y, local.x);
        float contour = 1.0 + 0.14 * sin(theta * 3.0 + age * 5.0 + ry * 6.28)
                            + 0.08 * sin(theta * 5.0 - age * 3.0);
        float distance = length(local) / contour;
        float cluster = exp(-distance * distance * 1.6) * life;
        highlight += cluster * (0.70 + tightness * 0.90)
            * (1.0 - float(i) * 0.10);
        // A small continuous advection accompanies gathering and release, retaining
        // the original grain scale instead of collapsing the entire particle field.
        flow += delta / max(length(delta), 1.0) * cluster * tightness * 3.2;
    }
    return vec3(flow, min(highlight, 1.5));
}

// Same grain geometry and interior occupancy as the original 0.4.6 drop field.
float activityQuantumGrain(vec2 point, out vec2 cell, out float seed) {
    vec2 coordinate = point / 2.35;
    cell = floor(coordinate);
    cell -= floor(cell / 4096.0) * 4096.0;
    seed = activityStateSmokeHash(cell + 31.0);
    vec2 jitter = vec2(activityStateSmokeHash(cell + 47.0),
                          activityStateSmokeHash(cell + 83.0)) - 0.5;
    vec2 local = fract(coordinate) - 0.5 - jitter * 0.22;
    float radius = mix(0.17, 0.31, seed);
    float distance = length(local);
    float microDrop = 1.0 - smoothstep(radius, radius + 0.10, distance);
    float microBloom = exp(-max(distance - radius, 0.0) * 12.0);
    float occupancy = step(1.0 - 0.88, activityStateSmokeHash(cell + 151.0));
    return (microDrop + microBloom * 0.08) * occupancy;
}

float activityQuantumMotionDensity(vec2 pixel, vec2 resolution, float front,
                                  ActivityStateSmokeUniforms u) {
    vec4 mode = u.quantumWeights;
    float phase = u.quantumClock.z;
    float failure = u.quantumClock.w;
    vec3 clusters = u.quantumEnabled.z > 0.5
        ? activityQuantumCompletionClusters(pixel, resolution, front, phase)
        : activityQuantumCompressionClusters(pixel, resolution, front, phase);
    vec2 point = pixel + u.quantumClock.xy + mode.z * clusters.xy;
    // State motion acts on the original fine-grain field, not on grain size/count.
    point.x += mode.x * sin(pixel.y * 0.044 + phase * 1.2) * 7.0
        + mode.z * sin(pixel.y * 0.037 + phase * 1.6) * 0.35;
    point.y += mode.x * sin(pixel.x * 0.023 + phase * 1.5) * 6.0
        + mode.z * sin(pixel.x * 0.028 - phase * 1.8) * 0.35;
    vec2 cell;
    float seed;
    float particle = activityQuantumGrain(point, cell, seed);
    float activation = u.quantumEnabled.w > 0.5 ? 1.0
        : activityQuantumFrontCoverage(pixel, resolution, front, u.completionFillProgress);
    float packet = activityQuantumTransportPulse(pixel, resolution, front, phase);
    float restingWeight = max(0.0, 1.0 - dot(mode, vec4(1.0)) - failure);
    float groupSeed = activityStateSmokeHash(floor(cell / 7.0) + 263.0);
    float twinkleRate = mix(2.4, 4.0, activityStateSmokeHash(cell + 197.0));
    float wave = 0.5 + 0.5 * sin(phase * twinkleRate + seed * 6.2831853);
    float sparkle = min((0.22 + wave * 0.62 + pow(wave, 5.0) * 0.16) * 1.10, 1.0);
    float threshold = activityStateSmokeHash(cell + 347.0) * 0.60;
    float dissolve = smoothstep(threshold, threshold + 0.40, activation);
    // Preserve the original ratio of dim/bright stars. State gestures modulate
    // that sparkle instead of imposing an always-bright floor on every point.
    float thinking = sparkle;
    float working = sparkle * (0.84 + 0.50 * packet);
    float compacting = sparkle * (u.quantumEnabled.z > 0.5
        ? 0.70 + 2.60 * clusters.z
        : 0.62 + 1.85 * pow(clusters.z, 2.0));
    float waiting = sparkle;
    float interrupted = sparkle * (0.90 + 0.16
        * (0.5 + 0.5 * sin(phase * 5.3 + groupSeed * 6.283185)));
    float intensity = restingWeight * 0.70 + mode.x * thinking + mode.y * working
        + mode.z * compacting + mode.w * waiting + failure * interrupted;
    return clamp(particle * intensity * dissolve * pow(activation, 0.55)
                 * u.quantumEnabled.y, 0.0, 1.0);
}

vec3 activityQuantumMotionColor(float density, ActivityStateSmokeUniforms u) {
    vec3 tint = mix(u.midColor.rgb, u.highlightColor.rgb, 0.26);
    tint /= max(max(tint.r, max(tint.g, tint.b)), 0.001);
    float minimum = min(tint.r, min(tint.g, tint.b));
    // Keep the compression state's neutral silver; only chromatic states gain saturation.
    float chromatic = smoothstep(0.12, 0.45, 1.0 - minimum);
    float neutral = minimum * 0.85 * chromatic;
    tint = max((tint - neutral) / max(1.0 - neutral, 0.001), vec3(0.0));
    float luminance = dot(tint, vec3(0.2126, 0.7152, 0.0722));
    float target = 0.54;
    tint = luminance < target
        ? mix(tint, vec3(1.0), (target - luminance) / max(1.0 - luminance, 0.001))
        : tint * target / max(luminance, 0.001);
    // Stronger color in each star, with more exposure in the dim/mid range.
    // Neutral silver stays neutral; zero-density gaps and the front dissolve stay black.
    tint = pow(tint, vec3(mix(1.0, 1.50, chromatic)));
    // Original microBloom is very faint. Do not let the brighter transfer curve
    // amplify it into a veil between the original fine, closely spaced stars.
    float light = pow(max(density, 0.0), 0.78) * smoothstep(0.03, 0.18, density);
    // Preserve the existing neutral-star luminance ceiling with uniform integer noise.
    float exposure = mix(1.51, 1.78, chromatic) * (1.0 + u.quantumClock.w * 0.12);
    vec3 enhanced = u.background.rgb + tint * light * exposure
        + tint * light * u.completionEffectHighlight;
    // Match the original VISIBLE warm gold, including density-dependent highlights
    // and energy. The same native opacity/compositing pipeline follows both paths.
    vec3 reference = activityQuantumOriginalColor(density, u);
    // Breathe AFTER the original transfer so dimming cannot shift gold toward red.
    float breath = 1.0; // Island waiting opacity is synchronized with the island glow.
    reference = u.background.rgb + (reference - u.background.rgb) * breath;
    return mix(enhanced, reference,
               clamp(u.quantumWeights.w, 0.0, 1.0));
}

float activityProgressSloshDensity(
    vec2 uv,
    float front,
    float time,
    float pulse,
    float turbulence
) {
    float verticalPhase = (uv.y - 0.5) * 6.2831853;
    float primaryWave =
        sin(verticalPhase * 1.10 - time * 1.40) * 0.026;
    float secondaryWave =
        sin(verticalPhase * 2.30 + time * 0.82 + 1.7) * 0.012;
    float localPulse = (pulse - 0.5) * 0.012;
    float boundary = front
        + (primaryWave + secondaryWave + localPulse)
            * (0.72 + turbulence * 0.28);
    float fill = 1.0 - smoothstep(
        boundary - 0.055,
        boundary + 0.018,
        uv.x
    );
    float frontDistance = abs(uv.x - boundary);
    float crest = exp(-frontDistance * 42.0);
    float firstEcho = exp(-abs(uv.x - (boundary - 0.082)) * 31.0);
    float secondEcho = exp(-abs(uv.x - (boundary - 0.164)) * 23.0);
    float fluidNoise = activityStateSmokeFBM(
        vec2(
            uv.x * 4.2 - time * 0.22,
            uv.y * 3.4 + time * 0.10
        )
    );
    float caustic = smoothstep(0.34, 0.68, fluidNoise);
    float body = fill * (0.50 + caustic * 0.38);
    return clamp(
        body
            + crest * (0.76 + pulse * 0.20)
            + firstEcho * fill * 0.34
            + secondEcho * fill * 0.18,
        0.0,
        1.0
    );
}

vec4 activityStateSmokeSample(vec2 sampleUV, ActivityStateSmokeUniforms u) {
    vec2 resolution = max(u.resolution, vec2(1.0));
    vec2 pixel = floor(sampleUV * resolution) + 0.5;
    vec2 uv = pixel / resolution;
    float aspect = resolution.x / resolution.y;
    vec2 p = vec2(uv.x * aspect, uv.y);

    // Optional satellite presentation: all pixels participate, without encoding
    // plan progress or pretending the task completed. Main islands keep w = 0.
    bool fullSurface = u.quantumEnabled.w > 0.5;
    float boundedFront = fullSurface ? 1.0 : clamp(u.frontPosition, 0.0, 0.95);
    float completionFront = fullSurface ? 1.35 : mix(
        boundedFront,
        1.12,
        clamp(u.completionFillProgress, 0.0, 1.0)
    );
    float front = aspect * completionFront;
    float frontDistance = p.x - front;
    vec2 samplePoint = vec2(
        p.x * 1.3 - u.fieldTime * 0.12,
        uv.y * 2.0 + u.fieldTime * 0.035
    );
    float warp = activityStateSmokeFBM(
        samplePoint * 1.7
    );
    float noise = activityStateSmokeFBM(
        samplePoint
            + vec2(warp * (0.95 + u.turbulence))
    );
    float density = activityStateSmokeReverseSmoothstep(
        0.62,
        0.05,
        (p.x - front) * 1.4
            + (0.5 - noise)
                * (1.15 + u.turbulence * 0.65)
    );
    float diffusionSpeedPhase =
        u.fieldTime * (1.25 + u.diffusion * 0.55);
    float diffusionClock =
        u.fieldTime * u.diffusionSpeed
        + sin(diffusionSpeedPhase)
            * u.diffusionSpeedVariation;
    float broadPlumeNoise = activityStateSmokeFBM(
        vec2(
            frontDistance * (0.62 + u.diffusion * 0.15)
                - diffusionClock * 0.28,
            uv.y * (1.15 + u.diffusion * 0.35)
                + diffusionClock * 0.07
        )
            + vec2(2.7, -1.9)
            + warp * 0.32
    );
    float finePlumeNoise = activityStateSmokeFBM(
        vec2(
            frontDistance * (1.35 + u.diffusion * 0.50)
                - diffusionClock * 0.62,
            uv.y * (3.10 + u.diffusion * 0.45)
                - diffusionClock * 0.18
        )
            + vec2(-1.4, 3.6)
            + noise * 0.28
    );
    float plumeFrontModulation =
        (broadPlumeNoise - 0.5) * 0.11 * u.diffusion;
    float plumeGate = smoothstep(
        -0.055,
        0.075,
        frontDistance + plumeFrontModulation
    );
    float spreadPulse =
        0.78
        + 0.22
            * sin(
                diffusionClock * 2.4
                + broadPlumeNoise * 6.2831853
            );
    float plumeEnvelope = exp(
        -max(frontDistance, 0.0)
            * (2.35 - u.diffusion * 0.75)
            / max(spreadPulse, 0.50)
    );
    float plumeWisps = smoothstep(
        0.38,
        0.72,
        broadPlumeNoise * 0.58
            + finePlumeNoise * 0.42
            + noise * 0.16
    );
    float terminalDiffusion =
        plumeGate
        * plumeEnvelope
        * plumeWisps
        * (0.14 + u.diffusion * 0.66);
    density = clamp(max(density, terminalDiffusion), 0.0, 1.0);
    if (u.effectStyle > 0.5 && u.effectStyle < 1.5) {
        density = activityProgressDiamondDensity(
            uv,
            aspect,
            completionFront,
            u.fieldTime,
            u.pulse,
            u.turbulence
        );
    } else if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
        density = activityQuantumMotionDensity(pixel, resolution, completionFront, u);
    } else if (u.effectStyle >= 2.5) {
        density = activityProgressSloshDensity(
            uv,
            completionFront,
            u.fieldTime,
            u.pulse,
            u.turbulence
        );
    }
    if (u.effectStyle > 0.5) {
        float effectProgressGate = mix(
            smoothstep(0.0005, 0.012, boundedFront),
            1.0,
            clamp(u.completionActive, 0.0, 1.0)
        );
        density *= effectProgressGate;
    }
    float breathing = 1.0 + (u.pulse - 0.5) * 0.18;

    vec3 color = u.background.rgb;
    color += u.deepColor.rgb * density * 0.72 * u.energy;
    color +=
        u.midColor.rgb
        * pow(density, 2.2)
        * 0.68
        * u.energy;
    color +=
        u.highlightColor.rgb
        * pow(density, 7.0)
        * 0.55
        * breathing
        * u.energy;
    if (u.effectStyle > 0.5) {
        float completionHighlightDensity = pow(density, 3.0);
        if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
            completionHighlightDensity = pow(density, 1.5);
        }
        color +=
            u.highlightColor.rgb
            * completionHighlightDensity
            * clamp(u.completionEffectHighlight, 0.0, 1.0)
            * u.energy;
    }
    if (u.effectStyle >= 1.5 && u.effectStyle < 2.5) {
        color = activityQuantumMotionColor(density, u);
    }
    color = mix(
        color,
        u.background.rgb * 0.62,
        clamp(u.completionDarkening, 0.0, 1.0)
    );
    color += (activityStateSmokeHash(pixel) - 0.5) * u.grain;
    float opacityFront = max(
        boundedFront,
        1.0 / resolution.x
    );
    float smokeRelativeX = clamp(
        uv.x / opacityFront,
        0.0,
        1.0
    );
    float normalHorizontalOpacity = activityStateSmokeHorizontalOpacity(
        smokeRelativeX,
        u.opacityStopPositions,
        u.opacityStopOpacities
    );
    float horizontalOpacity = fullSurface ? 1.0 : mix(
        normalHorizontalOpacity,
        1.0,
        clamp(u.completionActive, 0.0, 1.0)
    );
    float smokeOpacity =
        clamp(u.completionSmokeOpacity, 0.0, 1.0)
        * horizontalOpacity;
    return vec4(max(color, 0.0) * smokeOpacity, smokeOpacity);
}

vec4 activityStateSmokeLoopedSample(vec2 sampleUV, ActivityStateSmokeUniforms u) {
    bool quantum = u.effectStyle >= 1.5 && u.effectStyle < 2.5;
    float clock = quantum ? u.quantumClock.z : u.fieldTime;
    vec4 current = activityStateSmokeSample(sampleUV, u);
    // The incoming epoch reaches zero exactly at rollover. Do not simply wrap
    // arbitrary sin/noise frequencies: their periods differ, including twinkles.
    if (clock <= 248.0) { return current; }
    float blend = smoothstep(248.0, 256.0, clock);
    if (quantum) { u.quantumClock.z -= 256.0; }
    else { u.fieldTime -= 256.0; }
    return mix(current, activityStateSmokeSample(sampleUV, u), blend);
}


void main(){fragColor=activityStateSmokeLoopedSample(uv,loadUniforms());}
