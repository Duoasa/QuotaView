#version 330 compatibility
// Derived from QuotaView v0.7.7-build.1 (3866177cfa19db734d657ef505a4dc72c3338fba).
// MIT (c) 2026 Duoasa. Numeric shader formulas retained; host is Windows/OpenGL.
uniform float p[128];
in vec2 uv;
out vec4 fragColor;
struct Uniforms {
    vec2 size;
    float time;
    float speed;
    float radius;
    float zoom;
    float warp;
    float ridgeAmt;
    float sharp;
    float shade;
    float sheen;
    float gloss;
    float shellMidAlpha;
    float shellEdgeAlpha;
    float exposure;
    float style;
    float edgeSoftness;
    float edgeGlow;
    float paletteCount;
    float glassEnabled;
    float glassOpacity;
    float contourDeform;
    float bandDensity;
    float chromaticShift;
    float metalScale;
    float metalStretch;
    float metalAngle;
    float metalOffset;
    float metalPhase;
    float metalEvolution;
    float metalRoughness;
    float metalDepth;
    vec4 colorA;
    vec4 colorB;
    vec4 colorC;
    vec4 colorD;
    vec4 highlightColor;
    vec4 shellInner;
    vec4 shellMid;
    vec4 shellEdge;
    vec4 sheenColor;
    vec4 specColor;
    vec4 canvasColor;
    vec4 glowColor;
    vec4 paletteStop0_;
    vec4 paletteStop1_;
    vec4 paletteStop2_;
    vec4 paletteStop3_;
    vec4 paletteStop4_;
    vec4 paletteStop5_;
    vec4 paletteStop6_;
    vec4 paletteStop7_;
    vec4 paletteStop8_;
    vec4 paletteStop9_;
    vec4 paletteStop10_;
    vec4 paletteStop11_;
};
const float GL_FU = 0.8817204;
const float GL_BSIG_CLEAR = 0.018;
const float GL_BSIG_GLASS = 0.0399;
const float GL_KA = 6.0;
const float GL_KG = 4.1209;
const float GL_KWA = 0.5;
const float GL_KR = 0.32;
const float GL_GH = 1.7320508;
const float GL_CLEAR_EA = 0.995;
const float GL_CLEAR_EB = 1.04;
Uniforms loadUniforms() {
    Uniforms u;
    u.size = vec2(p[0], p[1]);
    u.time = p[2];
    u.speed = p[3];
    u.radius = p[4];
    u.zoom = p[5];
    u.warp = p[6];
    u.ridgeAmt = p[7];
    u.sharp = p[8];
    u.shade = p[9];
    u.sheen = p[10];
    u.gloss = p[11];
    u.shellMidAlpha = p[12];
    u.shellEdgeAlpha = p[13];
    u.exposure = p[14];
    u.style = p[15];
    u.edgeSoftness = p[16];
    u.edgeGlow = p[17];
    u.paletteCount = p[18];
    u.glassEnabled = p[19];
    u.glassOpacity = p[20];
    u.contourDeform = p[21];
    u.bandDensity = p[22];
    u.chromaticShift = p[23];
    u.metalScale = p[24];
    u.metalStretch = p[25];
    u.metalAngle = p[26];
    u.metalOffset = p[27];
    u.metalPhase = p[28];
    u.metalEvolution = p[29];
    u.metalRoughness = p[30];
    u.metalDepth = p[31];
    u.colorA = vec4(p[32], p[33], p[34], p[35]);
    u.colorB = vec4(p[36], p[37], p[38], p[39]);
    u.colorC = vec4(p[40], p[41], p[42], p[43]);
    u.colorD = vec4(p[44], p[45], p[46], p[47]);
    u.highlightColor = vec4(p[48], p[49], p[50], p[51]);
    u.shellInner = vec4(p[52], p[53], p[54], p[55]);
    u.shellMid = vec4(p[56], p[57], p[58], p[59]);
    u.shellEdge = vec4(p[60], p[61], p[62], p[63]);
    u.sheenColor = vec4(p[64], p[65], p[66], p[67]);
    u.specColor = vec4(p[68], p[69], p[70], p[71]);
    u.canvasColor = vec4(p[72], p[73], p[74], p[75]);
    u.glowColor = vec4(p[76], p[77], p[78], p[79]);
    u.paletteStop0_ = vec4(p[80], p[81], p[82], p[83]);
    u.paletteStop1_ = vec4(p[84], p[85], p[86], p[87]);
    u.paletteStop2_ = vec4(p[88], p[89], p[90], p[91]);
    u.paletteStop3_ = vec4(p[92], p[93], p[94], p[95]);
    u.paletteStop4_ = vec4(p[96], p[97], p[98], p[99]);
    u.paletteStop5_ = vec4(p[100], p[101], p[102], p[103]);
    u.paletteStop6_ = vec4(p[104], p[105], p[106], p[107]);
    u.paletteStop7_ = vec4(p[108], p[109], p[110], p[111]);
    u.paletteStop8_ = vec4(p[112], p[113], p[114], p[115]);
    u.paletteStop9_ = vec4(p[116], p[117], p[118], p[119]);
    u.paletteStop10_ = vec4(p[120], p[121], p[122], p[123]);
    u.paletteStop11_ = vec4(p[124], p[125], p[126], p[127]);
    return u;
}
float mfEdgeD(
    float soft
) {
    return soft - 0.005;
}

vec3 mfEdgeGlow(
    vec3 col,
    vec2 uv,
    vec2 ctr,
    float rad,
    float soft_1,
    float glow,
    vec3 glowRGB
) {
    if (glow <= 0.0) {
        return col;
    }
    float r_3 = length(uv - ctr);
    float outside = smoothstep(rad - max(soft_1, 0.0005), rad + max(soft_1, 0.0005), r_3);
    return col + (glowRGB * ((glow * exp(-(max(r_3 - rad, 0.0)) * 11.0)) * outside));
}

vec3 glsFinishPresetFluid(
    vec3 colorIn,
    vec2 p_4,
    Uniforms u
) {
    vec3 color = vec3(0);
    color = colorIn;
    vec3 _e3 = color;
    vec4 _e6 = u.highlightColor;
    float _e10 = u.shade;
    color = mix(_e3, _e6.xyz, (_e10 * 0.22) * smoothstep(0.15, 1.15, dot(p_4, vec2(-0.32, 0.78))));
    vec3 _e22 = color;
    float _e25 = u.shade;
    color = _e22 * (1.0 - ((_e25 * 0.34) * smoothstep(-0.1, 1.2, dot(p_4, vec2(0.45, -0.62)))));
    vec3 _e39 = color;
    float _e42 = u.shade;
    color = _e39 * (1.0 - ((_e42 * 0.22) * smoothstep(0.72, 1.08, length(p_4))));
    vec3 _e53 = color;
    return clamp(_e53, vec3(0.0), vec3(1.0));
}

vec2 glsSiriBand(
    vec2 q,
    float drift,
    float phaseOffset,
    float amplitude,
    float mainY,
    float envelope,
    float softness
) {
    float y = (amplitude * envelope) * sin(((q.x * 1.0) + drift) + phaseOffset);
    float distanceToLine = abs(q.y - y);
    float line = 0.018 / (sqrt((distanceToLine * distanceToLine) + (softness * softness)) + 0.026);
    float bandDistance = max(0.0, max(q.y - max(mainY, y), min(mainY, y) - q.y));
    float band = 0.018 / (bandDistance + 0.075);
    return vec2(line, band);
}

vec3 glsSiriFluid(
    vec2 p_5,
    float t_2,
    Uniforms u
) {
    vec3 color_1 = vec3(0);
    float _e4 = u.zoom;
    float scale_1 = 0.74 + (_e4 * 0.34);
    vec2 q_5 = p_5 / vec2(scale_1);
    float xNorm = q_5.x;
    float envelopeBase = cos(1.5707964 * min(abs(0.9 * xNorm), 1.0));
    float envelope_1 = envelopeBase * envelopeBase;
    float low = 0.5 + (0.5 * cos(t_2 * 0.37));
    float mid = 0.5 + (0.5 * sin((t_2 * 0.51) + 1.2));
    float high = 0.5 + (0.5 * cos((t_2 * 0.73) + 2.1));
    float drift_1 = t_2 * 2.4;
    float _e50 = u.ridgeAmt;
    float mainAmplitude = (0.25 + (_e50 * 0.075)) + (low * 0.018);
    float bandAmplitude = (mainAmplitude + (mid * 0.025)) + (high * 0.018);
    float mainY_1 = (mainAmplitude * envelope_1) * sin((q_5.x * 1.1) + drift_1);
    float _e73 = u.warp;
    float separation = (1.85 + (_e73 * 0.2)) + (mid * 0.28);
    float _e83 = u.ridgeAmt;
    float softness_2 = (0.035 + ((1.0 - _e83) * 0.018)) + (mid * 0.006);
    vec2 _e94 = glsSiriBand(q_5, drift_1, -(separation), bandAmplitude, mainY_1, envelope_1, softness_2);
    vec2 _e98 = glsSiriBand(q_5, drift_1, -(separation) * 0.34, bandAmplitude, mainY_1, envelope_1, softness_2);
    vec2 _e101 = glsSiriBand(q_5, drift_1, separation * 0.34, bandAmplitude, mainY_1, envelope_1, softness_2);
    vec2 _e102 = glsSiriBand(q_5, drift_1, separation, bandAmplitude, mainY_1, envelope_1, softness_2);
    float w0_ = _e94.x + _e94.y;
    float w1_ = _e98.x + _e98.y;
    float w2_ = _e101.x + _e101.y;
    float w3_ = _e102.x + _e102.y;
    float total = ((w0_ + w1_) + w2_) + w3_;
    float dominant0_ = w0_ * w0_;
    float dominant1_ = w1_ * w1_;
    float dominant2_ = w2_ * w2_;
    float dominant3_ = w3_ * w3_;
    float dominantTotal = ((dominant0_ + dominant1_) + dominant2_) + dominant3_;
    vec4 _e127 = u.colorA;
    vec4 _e132 = u.colorC;
    vec4 _e138 = u.colorB;
    vec4 _e144 = u.colorD;
    vec3 spectral = ((((_e127.xyz * dominant0_) + (_e132.xyz * dominant1_)) + (_e138.xyz * dominant2_)) + (_e144.xyz * dominant3_)) / vec3(max(dominantTotal, 0.0001));
    float energy = (1.0 - exp(-(total) * 0.58)) * envelope_1;
    float mainDistance = abs(q_5.y - mainY_1);
    float whiteCore = exp((-(mainDistance) * mainDistance) / 0.0028) * envelope_1;
    vec4 _e170 = u.colorD;
    vec4 _e174 = u.colorB;
    vec3 atmosphere = mix(_e170.xyz, _e174.xyz, smoothstep(-0.7, 0.7, q_5.y)) * 0.018;
    color_1 = atmosphere + ((spectral * energy) * 1.14);
    vec3 _e188 = color_1;
    vec4 _e191 = u.highlightColor;
    color_1 = _e188 + ((_e191.xyz * whiteCore) * (0.18 + (0.1 * low)));
    vec3 _e200 = color_1;
    vec3 _e203 = color_1;
    color_1 = _e200 / (vec3(1.0) + (_e203 * 0.18));
    vec3 _e208 = color_1;
    vec3 _e209 = glsFinishPresetFluid(_e208, p_5, u);
    return _e209;
}

vec3 glsPresetFluid(vec2 p, int style, float t, Uniforms u) { return glsSiriFluid(p, t, u); }

vec3 glsFluid(vec2 p, int style, float t, Uniforms u) { return glsSiriFluid(p, t, u); }

vec3 glsOver(
    vec3 dst,
    vec3 src,
    float a_3
) {
    float k_5 = clamp(a_3, 0.0, 1.0);
    return (src * k_5) + (dst * (1.0 - k_5));
}

float glsRefractionProfile(
    float t_15
) {
    float depth_1 = clamp(t_15, 0.0, 1.0);
    float circular = sqrt(max(1.0 - ((1.0 - depth_1) * (1.0 - depth_1)), 0.0));
    return 1.0 - circular;
}

float glsHighlightLobe(
    vec2 normal,
    vec2 direction,
    float cut,
    float power
) {
    float angular = clamp((dot(normal, direction) - cut) / max(1.0 - cut, 0.001), 0.0, 1.0);
    return pow(angular, power);
}

int naga_f2i32(float value) { return int(value); }

float glsContourScale(vec2 uv, float time, float amount, Uniforms u) { return 1.0; }

vec2 glsContourNormal(vec2 uv, float radius, float time, float amount, Uniforms u) { return length(uv) < 0.0001 ? vec2(0.0) : normalize(uv); }

float consoleRippleEdgeHalfWidth(float contourRadius, Uniforms u) {
    float pixelWidth = 2.0 / max(min(u.size.x, u.size.y) * contourRadius, 1.0);
    return max(0.01 + mfEdgeD(u.edgeSoftness), 1.5 * pixelWidth);
}

vec4 orbGlassLiquidAnim(
    vec2 uv01_,
    Uniforms u
) {
    int md_1 = -1;
    bool local = false;
    vec3 fcol_1 = vec3(0.0);
    vec3 col_1 = vec3(0);
    vec2 _e8 = u.size;
    vec2 fc = vec2(uv01_.x, 1.0 - uv01_.y) * _e8;
    vec2 _e14 = u.size;
    float _e19 = u.size.x;
    float _e23 = u.size.y;
    vec2 uv_3 = ((2.0 * fc) - _e14) / vec2(max(min(_e19, _e23), 1.0));
    float _e31 = u.radius;
    float rad_2 = max(_e31, 0.05);
    float _e36 = u.time;
    float _e39 = u.speed;
    float t_19 = _e36 * _e39;
    float _e43 = u.contourDeform;
    float _e44 = glsContourScale(uv_3, t_19, _e43, u);
    float contourRad = rad_2 * _e44;
    float _e49 = u.edgeSoftness;
    float _e50 = mfEdgeD(_e49);
    float edgeHalfWidth = consoleRippleEdgeHalfWidth(contourRad, u);
    if (length(uv_3) > (contourRad * (1.0 + edgeHalfWidth))) {
        float _e61 = u.edgeSoftness;
        float _e64 = u.edgeGlow;
        vec4 _e67 = u.glowColor;
        vec3 _e69 = mfEdgeGlow(vec3(0.0), uv_3, vec2(0.0), contourRad, _e61, _e64, _e67.xyz);
        return vec4(clamp(_e69, vec3(0.0), vec3(1.0)), 1.0);
    }
    vec2 p_17 = uv_3 / vec2(contourRad);
    float pd = length(p_17);
    vec2 fu_1 = p_17 / vec2(GL_FU);
    float _e85 = u.style;
    int s_2 = naga_f2i32(_e85 + 0.5);
    if (s_2 == 1) {
        md_1 = 1;
    } else {
        if (!(s_2 == 3)) {
            local = s_2 == 8;
        } else {
            local = true;
        }
        bool _e102 = local;
        if (_e102) {
            md_1 = 7;
        } else {
            if (s_2 == 5) {
                md_1 = 6;
            } else {
                if (s_2 == 7) {
                    md_1 = 0;
                }
            }
        }
    }
    float clearFa = 1.0 - smoothstep(GL_CLEAR_EA, GL_CLEAR_EB, pd);
    float _e117 = u.contourDeform;
    vec2 _e118 = glsContourNormal(uv_3, rad_2, t_19, _e117, u);
    float edgeDepth = max(1.0 - pd, 0.0);
    float _e125 = u.shellMidAlpha;
    float refractionWidth = 0.015 + (0.95 * clamp(_e125, 0.0, 1.0));
    float refractionT = edgeDepth / max(refractionWidth, 0.001);
    float _e136 = glsRefractionProfile(refractionT);
    float refractionProfile = pow(_e136, 0.68);
    float _e141 = u.glassOpacity;
    float refractionAmount = (1.6 * clamp(_e141, 0.0, 1.0)) * refractionProfile;
    vec2 refractedP = p_17 - (_e118 * refractionAmount);
    if (clearFa > 0.0) {
        if (s_2 >= 9) {
            float _e159 = u.glassEnabled;
            if (_e159 > 0.5) {
                float _e164 = u.gloss;
                float _e172 = u.glassOpacity;
                float channelSplit = ((0.14 * clamp(_e164, 0.0, 2.0)) * clamp(_e172, 0.0, 1.0)) * refractionProfile;
                vec3 _e180 = glsPresetFluid(refractedP - (_e118 * channelSplit), s_2, t_19, u);
                vec3 _e181 = glsPresetFluid(refractedP, s_2, t_19, u);
                vec3 _e184 = glsPresetFluid(refractedP + (_e118 * channelSplit), s_2, t_19, u);
                fcol_1 = vec3(_e180.x, _e181.y, _e184.z);
            } else {
                vec3 _e189 = glsPresetFluid(p_17, s_2, t_19, u);
                fcol_1 = _e189;
            }
        } else {
            int _e190 = md_1;
            vec3 _e191 = glsFluid(fu_1, _e190, t_19, u);
            fcol_1 = _e191;
        }
    }
    vec3 _e192 = fcol_1;
    float lum = dot(_e192, vec3(0.213, 0.715, 0.072));
    vec3 _e199 = fcol_1;
    vec3 clearSat = clamp(vec3(lum) + ((_e199 - vec3(lum)) * 1.22), vec3(0.0), vec3(1.0));
    vec4 _e212 = u.canvasColor;
    vec3 _e216 = glsOver(_e212.xyz, clearSat, 0.99 * clearFa);
    col_1 = _e216;
    float _e220 = u.glassEnabled;
    if (_e220 > 0.5) {
        float _e225 = u.shellEdgeAlpha;
        float surfaceWidth = 0.026 + (0.055 * clamp(_e225, 0.0, 1.0));
        float surfaceBand = (1.0 - smoothstep(0.0, surfaceWidth, edgeDepth)) * clearFa;
        float opticalRim = pow(surfaceBand, 1.8);
        vec3 _e240 = col_1;
        vec4 _e243 = u.shellInner;
        float _e247 = u.glassOpacity;
        vec3 _e251 = glsOver(_e240, _e243.xyz, (opticalRim * _e247) * 0.45);
        col_1 = _e251;
        vec2 coolDirection = normalize(vec2(0.84, 0.54));
        vec2 warmDirection = normalize(vec2(-0.62, -0.78));
        float _e262 = glsHighlightLobe(_e118, coolDirection, -0.32, 1.8);
        float _e265 = glsHighlightLobe(_e118, warmDirection, -0.28, 2.0);
        float _e268 = u.gloss;
        float _e275 = u.shellEdgeAlpha;
        float dispersion = (opticalRim * clamp(_e268, 0.0, 2.0)) * (0.8 + (0.8 * _e275));
        vec3 _e281 = col_1;
        vec4 _e284 = u.shellMid;
        vec3 _e287 = glsOver(_e281, _e284.xyz, dispersion * _e262);
        col_1 = _e287;
        vec3 _e288 = col_1;
        vec4 _e291 = u.shellEdge;
        vec3 _e294 = glsOver(_e288, _e291.xyz, dispersion * _e265);
        col_1 = _e294;
        float _e297 = u.shellEdgeAlpha;
        float edgeShadow = (opticalRim * (0.015 + (0.15 * _e297))) * (0.15 + (0.85 * max(dot(_e118, vec2(0.45, -0.89)), 0.0)));
        vec3 _e314 = col_1;
        col_1 = _e314 * (1.0 - edgeShadow);
        vec2 keyDirection = normalize(vec2(-0.68, 0.73));
        vec2 fillDirection = normalize(vec2(0.74, -0.67));
        float _e328 = glsHighlightLobe(_e118, keyDirection, 0.2, 2.8);
        float _e332 = u.sheen;
        float key = ((opticalRim * _e328) * clamp(_e332, 0.0, 2.0)) * 1.4;
        float _e341 = glsHighlightLobe(_e118, fillDirection, 0.4, 3.6);
        float _e345 = u.sheen;
        float fill = ((opticalRim * _e341) * clamp(_e345, 0.0, 2.0)) * 1.0;
        vec3 _e352 = col_1;
        vec4 _e355 = u.sheenColor;
        vec3 _e357 = glsOver(_e352, _e355.xyz, key);
        col_1 = _e357;
        vec3 _e358 = col_1;
        vec4 _e361 = u.specColor;
        vec3 _e363 = glsOver(_e358, _e361.xyz, fill);
        col_1 = _e363;
    }
    float _e366 = u.edgeSoftness;
    float _e367 = mfEdgeD(_e366);
    float _e372 = u.edgeSoftness;
    float _e373 = mfEdgeD(_e372);
    float ballA = 1.0 - smoothstep(1.0 - edgeHalfWidth, 1.0 + edgeHalfWidth, pd);
    vec3 _e379 = col_1;
    float _e382 = u.exposure;
    col_1 = clamp(_e379 * max(_e382, 0.0), vec3(0.0), vec3(1.0)); // Straight RGB: final alpha applies coverage once.
    vec3 _e392 = col_1;
    float _e397 = u.edgeSoftness;
    float _e400 = u.edgeGlow;
    vec4 _e403 = u.glowColor;
    vec3 _e405 = mfEdgeGlow(_e392, uv_3, vec2(0.0), contourRad, _e397, _e400, _e403.xyz);
    return vec4(clamp(_e405, vec3(0.0), vec3(1.0)), 1.0);
}
void main() {
    Uniforms u = loadUniforms();
    vec4 sampleColor = orbGlassLiquidAnim(uv, u);
    // The native host crops the unchanged sphere silhouette; reproduce that
    // coverage on a transparent GPU surface, without an opaque square canvas.
    vec2 point = (uv * 2.0 - 1.0) * u.size / min(u.size.x, u.size.y);
    float edge = consoleRippleEdgeHalfWidth(u.radius, u);
    float coverage = 1.0 - smoothstep(1.0-edge, 1.0+edge, length(point)/u.radius);
    fragColor = vec4(sampleColor.rgb, coverage);
}
