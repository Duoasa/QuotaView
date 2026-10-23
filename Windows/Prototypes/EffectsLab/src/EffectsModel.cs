using System;

namespace QuotaView.EffectsLab {
    internal enum EffectState { Thinking, Working, Compacting, Waiting, Completed, Error, Standby, Disconnected, Unavailable }

    // No log reader or task simulator: every input is an explicit console fixture.
    internal sealed class EffectsModel {
        internal static readonly string[] Names = { "思考", "执行", "压缩上下文", "待确认", "完成", "错误", "待机", "未连接", "不可用" };
        internal static readonly string[] Descriptions = {
            "紫色流体 · 噪点自然聚集", "青色流体 · 粒子持续输运", "银色流体 · 聚集与消散",
            "琥珀色流体 · 原地呼吸", "绿色球体 · 铺满、微亮、淡出、描边", "红色流体 · 低速故障脉动",
            "蓝灰色流体 · 低可见度静止噪点", "灰蓝色流体 · 低可见度静止噪点", "灰色流体 · 低可见度静止噪点"
        };
        internal EffectState State { get; private set; }
        internal bool Paused;
        internal bool ReduceMotion { get; private set; }
        internal double Speed = 1;
        internal double Progress { get; private set; }
        internal double Front { get; private set; }
        internal double OrbPhase { get; private set; }
        internal double QuantumPhase { get; private set; }
        internal double Displacement { get; private set; }
        internal double CompletionTime { get; private set; }
        internal double Elapsed { get; private set; }
        private double transitionTime;
        private float[] orb, orbFrom, orbTarget, color, colorTarget;
        // weights (4), velocity (x), rate, failure, visibility
        private float[] motion, motionTarget;
        internal const double LatticePeriod = 4096 * 2.35;

        internal EffectsModel() {
            State = EffectState.Working;
            Progress = Front = .60;
            orb = OrbProfile(State); orbFrom = (float[])orb.Clone(); orbTarget = (float[])orb.Clone();
            color = (float[])ReleaseProfiles.Quantum[(int)State].Clone(); colorTarget = (float[])color.Clone();
            motion = MotionProfile(State); motionTarget = (float[])motion.Clone();
            transitionTime = .42;
        }
        internal void SetState(EffectState state) {
            if (state == State) return;
            orbFrom = (float[])orb.Clone(); orbTarget = OrbProfile(state); transitionTime = 0;
            colorTarget = (float[])ReleaseProfiles.Quantum[(int)state].Clone();
            motionTarget = MotionProfile(state);
            State = state; CompletionTime = ReduceMotion && state == EffectState.Completed ? 1.4 : 0;
            if (ReduceMotion) SnapProfiles();
        }
        internal void SetProgress(double value) {
            if (double.IsNaN(value) || double.IsInfinity(value)) return;
            Progress = Math.Max(0, Math.Min(.95, value));
            if (ReduceMotion) Front = Progress;
        }
        internal void SetReducedMotion(bool value) {
            ReduceMotion = value;
            if (value) {
                SnapProfiles(); Front = Progress;
                if (State == EffectState.Completed) CompletionTime = Math.Max(1.4, CompletionTime);
            }
        }
        private void SnapProfiles() {
            orb = (float[])orbTarget.Clone(); color = (float[])colorTarget.Clone();
            motion = (float[])motionTarget.Clone(); transitionTime = .42;
        }
        internal void Restart() {
            OrbPhase = QuantumPhase = Displacement = Elapsed = 0;
            CompletionTime = ReduceMotion && State == EffectState.Completed ? 1.4 : 0;
            Front = Progress;
            SnapProfiles();
        }
        internal void ReplayCompletion() {
            SetState(EffectState.Completed); CompletionTime = ReduceMotion ? 1.4 : 0;
        }
        internal void Advance(double elapsed) {
            if (Paused || ReduceMotion || double.IsNaN(elapsed) || double.IsInfinity(elapsed)) return;
            double delta = Math.Min(.1, Math.Max(0, elapsed)) * Math.Max(.1, Math.Min(2, Speed));
            int steps = Math.Max(1, (int)Math.Ceiling(delta * 120));
            double dt = delta / steps;
            for (int step = 0; step < steps; step++) {
                Elapsed += dt;
                transitionTime += dt;
                float t = (float)Smooth(transitionTime / .42);
                for (int i = 0; i < orb.Length; i++) orb[i] = orbFrom[i] + (orbTarget[i] - orbFrom[i]) * t;
                OrbPhase += dt * orb[3]; // Integrate phase; a new speed never rephases the sphere.
                float a = (float)(1 - Math.Exp(-5 * dt));
                for (int i = 0; i < motion.Length; i++) motion[i] += (motionTarget[i] - motion[i]) * a;
                for (int i = 0; i < color.Length; i++) color[i] += (colorTarget[i] - color[i]) * a;
                Displacement = (Displacement + motion[4] * dt) % LatticePeriod;
                QuantumPhase = (QuantumPhase + motion[5] * dt) % 256;
                // Freeze the starting front during completion so its one-shot envelope is deterministic.
                if (State == EffectState.Completed) CompletionTime += dt;
                else Front += (Progress - Front) * (1 - Math.Exp(-3.5 * dt));
            }
        }
        internal float[] OrbUniforms(int width, int height) {
            float[] p = (float[])orb.Clone();
            p[0] = width; p[1] = height; p[2] = (float)(OrbPhase / Math.Max(.0001, p[3]));
            return p;
        }
        internal float[] QuantumUniforms(int width, int height) {
            float[] p = new float[54];
            p[0] = width; p[1] = height; p[2] = (float)Front;
            p[3] = .5f + (float)(.5 * Math.Sin(QuantumPhase * Math.PI * 2)) * color[10];
            p[4] = (float)QuantumPhase; p[5] = (float)QuantumPhase;
            p[6] = color[9]; p[7] = color[11]; p[8] = color[12]; p[9] = color[13]; p[10] = color[14];
            p[11] = .01f; p[12] = 2; p[16] = 1;
            if (State == EffectState.Completed) {
                p[17] = 1;
                p[13] = ReduceMotion ? 1 : (float)(1 - Math.Pow(1 - Clamp(CompletionTime / .42), 3));
                p[14] = ReduceMotion ? 0 : (float)(Math.Pow(Math.Sin(Math.PI * Clamp((CompletionTime - .42) / .30)), 2) * .18);
                p[15] = ReduceMotion ? .64f : (float)(Smooth((CompletionTime - .36) / .44) * .64);
                p[16] = ReduceMotion ? 0 : (float)(1 - Smooth((CompletionTime - .80) / .36));
            }
            Array.Copy(motion, 0, p, 18, 4);
            p[22] = (float)Displacement; p[24] = (float)QuantumPhase; p[25] = motion[6];
            p[26] = 1; p[27] = motion[7]; p[28] = State == EffectState.Completed ? 1 : 0;
            p[30] = 0; p[31] = 1f/3; p[32] = 2f/3; p[33] = 1;
            p[34] = .5f; p[35] = 2f/3; p[36] = 5f/6; p[37] = 1;
            p[38] = 19f/255; p[39] = 16f/255; p[40] = 25f/255; p[41] = 1;
            for (int j = 0; j < 3; j++) {
                for (int k = 0; k < 3; k++) p[42 + j * 4 + k] = color[j * 3 + k];
                p[45 + j * 4] = 1;
            }
            return p;
        }
        internal float CompletionGlow {
            get {
                if (State != EffectState.Completed) return 0;
                if (ReduceMotion) return .72f;
                double t = Math.Max(0, CompletionTime - 1.16);
                return (float)(Smooth(t / .24) * (.72 + .18 * Math.Sin(t * Math.PI * 2 / 1.8)));
            }
        }
        internal static double Clamp(double t) { return Math.Max(0, Math.Min(1, t)); }
        internal static double Smooth(double t) { t = Clamp(t); return t * t * (3 - 2 * t); }
        private static float[] OrbProfile(EffectState state) {
            float[] p = (float[])ReleaseProfiles.Seed.Clone(), c = ReleaseProfiles.Orb[(int)state];
            p[3] = c[15] * 1.5f; p[4] = .535f; p[6] = c[16]; p[7] = c[17]; p[8] = c[18]; p[14] = c[19]; p[15] = 9; p[19] = 1; p[21] = 0;
            for (int j = 0; j < 5; j++) SetRgb(p, 32 + 4*j, c, 3*j);
            SetRgb(p, 52, c, 12); SetRgb(p, 56, c, 6); SetRgb(p, 60, c, 3);
            return p;
        }
        private static void SetRgb(float[] to, int at, float[] from, int start) {
            for (int i=0; i<3; i++) to[at+i] = from[start+i]; to[at+3] = 1;
        }
        private static float[] MotionProfile(EffectState state) {
            switch (state) {
                case EffectState.Working: return new float[] {0,1,0,0,-16,1.5f,0,1};
                case EffectState.Thinking:
                case EffectState.Compacting: return new float[] {0,0,1,0,-.8f,1,0,1};
                case EffectState.Waiting: return new float[] {0,0,0,1,0,1,0,1};
                case EffectState.Error: return new float[] {0,0,0,0,0,.38f,1,1};
                case EffectState.Completed: return new float[] {0,.3f,.4f,0,-2,.45f,0,1};
                default: return new float[] {0,0,0,0,0,0,0,.3f};
            }
        }
    }
}
