/* Port of Prototypes/EffectsLab/EffectsModel.cs. MIT (c) 2026 Duoasa. */
(function (root) {
  "use strict";
  const assets =
    typeof module === "object" && module.exports
      ? require("./assets.js")
      : root.QVEffectAssets;
  const smokeProfiles =
    assets.smoke ||
    (typeof module === "object" && module.exports
      ? require("./smoke-profiles.json")
      : assets.quantum);
  const names = [
    "thinking",
    "working",
    "compacting",
    "waiting",
    "completed",
    "error",
    "standby",
    "disconnected",
    "unavailable",
  ];
  const clamp = (x) => Math.max(0, Math.min(1, x));
  const smooth = (x) => {
    x = clamp(x);
    return x * x * (3 - 2 * x);
  };
  function displayState(task) {
    const shared =
      typeof module === "object" && module.exports
        ? require("../../windows/shared/task-state.js")
        : root.QVTaskState;
    return shared.displayState(task);
  }
  function normalize(state) {
    return names.includes(state)
      ? state
      : state === "failed"
        ? "error"
        : state === "interrupted"
          ? "disconnected"
          : "unavailable";
  }
  function orbProfile(state) {
    const p = assets.seed.slice(),
      c = assets.orb[names.indexOf(normalize(state))];
    p[3] = c[15] * 1.5;
    p[4] = 0.535;
    p[6] = c[16];
    p[7] = c[17];
    p[8] = c[18];
    p[14] = c[19];
    p[15] = 9;
    p[19] = 1;
    p[21] = 0;
    const rgb = (offset, start) => {
      for (let i = 0; i < 3; i++) p[offset + i] = c[start + i];
      p[offset + 3] = 1;
    };
    for (let j = 0; j < 5; j++) rgb(32 + 4 * j, 3 * j);
    rgb(52, 12);
    rgb(56, 6);
    rgb(60, 3);
    return p;
  }
  function motionProfile(state) {
    switch (normalize(state)) {
      case "working":
        return [0, 1, 0, 0, -16, 1.5, 0, 1];
      case "thinking":
      case "compacting":
        return [0, 0, 1, 0, -0.8, 1, 0, 1];
      case "waiting":
        return [0, 0, 0, 1, 0, 1, 0, 1];
      case "error":
        return [0, 0, 0, 0, 0, 0.38, 1, 1];
      case "completed":
        return [0, 0.3, 0.4, 0, -2, 0.45, 0, 1];
      default:
        return [0, 0, 0, 0, 0, 0, 0, 0.3];
    }
  }
  class Model {
    constructor(state = "unavailable", progress = null) {
      this.state = normalize(state);
      this.reduced = false;
      this.frozen = state === "interrupted";
      this.orb = orbProfile(this.state);
      this.from = this.orb.slice();
      this.target = this.orb.slice();
      this.color = assets.quantum[names.indexOf(this.state)].slice();
      this.colorTarget = this.color.slice();
      this.smokeColor = smokeProfiles[names.indexOf(this.state)].slice();
      this.smokeTarget = this.smokeColor.slice();
      this.fieldPhase = 0;
      this.motion = motionProfile(this.state);
      this.motionTarget = this.motion.slice();
      this.transition = 0.42;
      this.orbPhase = 0;
      this.phase = 0;
      this.displacement = 0;
      // Mounting an existing completed task must not replay a new completion event.
      this.completion = this.state === "completed" ? 1.4 : 0;
      this.progress = 0;
      this.front = 0;
      this.known = false;
      this.setProgress(progress);
      this.front = this.progress;
    }
    setState(raw) {
      const state = normalize(raw);
      this.frozen = raw === "interrupted";
      if (state === this.state) return;
      this.from = this.orb.slice();
      this.target = orbProfile(state);
      this.transition = 0;
      this.colorTarget = assets.quantum[names.indexOf(state)].slice();
      this.motionTarget = motionProfile(state);
      this.smokeTarget = smokeProfiles[names.indexOf(state)].slice();
      this.state = state;
      this.completion = this.reduced && state === "completed" ? 1.4 : 0;
      if (this.reduced || this.frozen) this.snap();
    }
    setProgress(value) {
      this.known = Number.isFinite(value);
      this.progress = this.known ? Math.max(0, Math.min(0.95, value)) : 0;
      if (this.reduced || !this.known) this.front = this.progress;
    }
    setReduced(value) {
      if (this.reduced === !!value) return;
      this.reduced = !!value;
      if (this.reduced) {
        this.snap();
        this.front = this.progress;
        if (this.state === "completed")
          this.completion = Math.max(1.4, this.completion);
      }
    }
    snap() {
      this.orb = this.target.slice();
      this.color = this.colorTarget.slice();
      this.smokeColor = this.smokeTarget.slice();
      this.motion = this.motionTarget.slice();
      this.transition = 0.42;
    }
    advance(elapsed) {
      if (this.reduced || this.frozen || !Number.isFinite(elapsed)) return;
      const delta = Math.min(0.1, Math.max(0, elapsed)),
        steps = Math.max(1, Math.ceil(delta * 120)),
        dt = delta / steps;
      for (let step = 0; step < steps; step++) {
        this.transition += dt;
        const t = smooth(this.transition / 0.42);
        for (let i = 0; i < 128; i++)
          this.orb[i] = this.from[i] + (this.target[i] - this.from[i]) * t;
        this.orbPhase += dt * this.orb[3];
        const a = 1 - Math.exp(-5 * dt);
        for (let i = 0; i < this.motion.length; i++)
          this.motion[i] += (this.motionTarget[i] - this.motion[i]) * a;
        for (let i = 0; i < this.color.length; i++)
          this.color[i] += (this.colorTarget[i] - this.color[i]) * a;
        for (let i = 0; i < this.smokeColor.length; i++)
          this.smokeColor[i] += (this.smokeTarget[i] - this.smokeColor[i]) * a;
        this.fieldPhase = (this.fieldPhase + dt * this.smokeColor[15]) % 256;
        this.displacement =
          (this.displacement + this.motion[4] * dt) % (4096 * 2.35);
        this.phase = (this.phase + this.motion[5] * dt) % 256;
        if (this.state === "completed") this.completion += dt;
        else
          this.front +=
            (this.progress - this.front) * (1 - Math.exp(-3.5 * dt));
      }
    }
    orbUniforms(width, height) {
      const p = new Float32Array(this.orb);
      p[0] = width;
      p[1] = height;
      p[2] = this.orbPhase / Math.max(0.0001, p[3]);
      return p;
    }
    quantumUniforms(width, height) {
      const p = new Float32Array(55),
        c = this.color;
      p[0] = width;
      p[1] = height;
      p[2] = this.front;
      p[3] = 0.5 + 0.5 * Math.sin(this.phase * Math.PI * 2) * c[10];
      p[4] = p[5] = this.phase;
      p[6] = c[9];
      p[7] = c[11];
      p[8] = c[12];
      p[9] = c[13];
      p[10] = c[14];
      p[11] = this.known ? 0.01 : 0;
      p[12] = 2;
      p[16] = 1;
      if (this.state === "completed") {
        p[17] = 1;
        p[13] = this.reduced
          ? 1
          : 1 - Math.pow(1 - clamp(this.completion / 0.42), 3);
        p[14] = this.reduced
          ? 0
          : Math.pow(
              Math.sin(Math.PI * clamp((this.completion - 0.42) / 0.3)),
              2,
            ) * 0.18;
        p[15] = this.reduced
          ? 0.64
          : smooth((this.completion - 0.36) / 0.44) * 0.64;
        p[16] = this.reduced ? 0 : 1 - smooth((this.completion - 0.8) / 0.36);
      }
      p.set(this.motion.slice(0, 4), 18);
      p[22] = this.displacement;
      p[24] = this.phase;
      p[25] = this.motion[6];
      p[26] = 1;
      p[27] = this.motion[7];
      p[28] = this.state === "completed" ? 1 : 0;
      // Full-width activity field is distinct from a measured progress boundary.
      p[54] =
        !this.known && this.state !== "completed"
          ? 1
          : 0;
      p.set([0, 1 / 3, 2 / 3, 1], 30);
      p.set([0.5, 2 / 3, 5 / 6, 1], 34);
      p.set([19 / 255, 16 / 255, 25 / 255, 1], 38);
      for (let j = 0; j < 3; j++) {
        for (let k = 0; k < 3; k++) p[42 + j * 4 + k] = c[j * 3 + k];
        p[45 + j * 4] = 1;
      }
      return p;
    }
    get glow() {
      if (this.state !== "completed") return 0;
      if (this.reduced) return 0.72;
      const t = Math.max(0, this.completion - 1.16);
      return (
        smooth(t / 0.24) * (0.72 + 0.18 * Math.sin((t * Math.PI * 2) / 1.8))
      );
    }
    progressUniforms(width, height, effect = "quantum") {
      const p = this.quantumUniforms(width, height);
      if (effect === "quantum") return p;
      const c = this.smokeColor;
      p[3] =
        0.5 + 0.5 * Math.sin(this.fieldPhase * 2 * Math.PI * c[16]) * c[10];
      p[4] = this.fieldPhase;
      p[5] = this.fieldPhase;
      p[6] = c[9];
      p[7] = c[11];
      p[8] = c[12];
      p[9] = c[13];
      p[10] = c[14];
      p[12] = effect === "wave" ? 3 : 0;
      if (!this.known && this.state !== "completed") p[16] = 0;
      for (let j = 0; j < 3; j++)
        for (let k = 0; k < 3; k++) p[42 + j * 4 + k] = c[j * 3 + k];
      return p;
    }
    get needsAnimation() {
      return (
        !this.reduced &&
        !this.frozen &&
        (this.transition < 0.42 ||
          [
            "thinking",
            "working",
            "compacting",
            "waiting",
            "completed",
            "error",
            "standby",
            "unavailable",
          ].includes(this.state))
      );
    }
  }
  const api = { Model, displayState, normalize };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.QVEffectModel = api;
})(globalThis);
