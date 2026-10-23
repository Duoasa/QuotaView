/* Shared WebGL2 atlas for all Island effects; no Node access or network requests. */
(function () {
  "use strict";
  const { Model, displayState } = window.QVEffectModel,
    assets = window.QVEffectAssets;
  const entries = new Set(),
    models = new Map(),
    media = matchMedia("(prefers-reduced-motion: reduce)");
  const settingsPreview =
    new URL(location.href).searchParams.get("view") === "settings";
  const frameInterval = 1000 / (settingsPreview ? 24 : 60);
  let surface,
    gl,
    programs,
    raf = 0,
    last = 0,
    serial = 0,
    frames = 0,
    failure = null,
    testReact,
    testCreateRoot;
  const errors = [];
  const observer = new IntersectionObserver((changes) => {
    for (const change of changes)
      for (const entry of entries)
        if (entry.canvas === change.target)
          entry.visible = change.isIntersecting;
    schedule();
  });
  const resize = new ResizeObserver(() => schedule());
  function report(error) {
    failure = String(error?.message || error);
    errors.push(failure);
    console.error("[QuotaView effects]", failure);
    for (const e of entries)
      e.canvas.parentElement?.classList.add("qv-effect-unavailable");
  }
  function compile(type, source) {
    const s = gl.createShader(type);
    gl.shaderSource(s, source);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(s);
      gl.deleteShader(s);
      throw Error(log);
    }
    return s;
  }
  function program(source) {
    const v = compile(gl.VERTEX_SHADER, assets.vertex),
      f = compile(gl.FRAGMENT_SHADER, source),
      p = gl.createProgram();
    gl.attachShader(p, v);
    gl.attachShader(p, f);
    gl.linkProgram(p);
    gl.deleteShader(v);
    gl.deleteShader(f);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS))
      throw Error(gl.getProgramInfoLog(p));
    return { p, uniform: gl.getUniformLocation(p, "p[0]") };
  }
  function init() {
    if (gl) return;
    surface = document.createElement("canvas");
    gl = surface.getContext("webgl2", {
      alpha: true,
      antialias: false,
      depth: false,
      stencil: false,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false,
      powerPreference: "default",
    });
    if (!gl) throw Error("WebGL2 is unavailable; GPU effects could not start.");
    programs = {
      orb: program(assets.orbShader),
      quantum: program(assets.quantumShader),
      border: program(assets.borderShader),
    };
    surface.addEventListener("webglcontextlost", (event) => {
      event.preventDefault();
      cancelAnimationFrame(raf);
      raf = 0;
      report(Error("WebGL context lost"));
    });
    surface.addEventListener("webglcontextrestored", () => {
      gl = null;
      programs = null;
      failure = null;
      for (const e of entries)
        e.canvas.parentElement?.classList.remove("qv-effect-unavailable");
      schedule();
    });
  }
  function progress(task) {
    return window.QVTaskState.progressValue(task);
  }
  function keyFor(task, fallback) {
    return task?.id
      ? String(task.id) + ":" + String(task.turnId ?? task.startedAt ?? "")
      : fallback;
  }
  function modelFor(key, state, value) {
    let item = models.get(key);
    if (!item) {
      item = { model: new Model(state, value), used: performance.now() };
      models.set(key, item);
    }
    item.used = performance.now();
    // Keep recent task clocks across collapse/expand and React remounts, with bounded history.
    if (models.size > 1024) {
      const held = new Set([...entries].map((e) => e.key));
      for (const [k] of models) {
        if (models.size <= 768) break;
        if (!held.has(k)) models.delete(k);
      }
    }
    return item.model;
  }
  function mount(canvas, kind, props) {
    const entry = {
      canvas,
      kind,
      visible: true,
      key: null,
      model: null,
      props: null,
      context: canvas.getContext("2d", { alpha: true }),
      fallback: "local-" + ++serial,
    };
    if (!entry.context) throw Error("Canvas compositor unavailable");
    entries.add(entry);
    observer.observe(canvas);
    resize.observe(canvas);
    const update = (value) => {
      const state = value.task
          ? displayState(value.task)
          : value.status || "unknown",
        key = keyFor(value.task, entry.fallback);
      entry.key = key;
      entry.model = modelFor(key, state, progress(value.task));
      entry.props = value;
      // An explicit application preference takes priority. Windows can report
      // reduced motion globally even when the user wants these live status effects.
      entry.model.setReduced(value.reduceMotion ?? media.matches);
      entry.model.setState(state);
      entry.model.setProgress(progress(value.task));
      if (state === "completed" && (!entry.visible || document.hidden))
        entry.model.completion = Math.max(1.4, entry.model.completion);
      schedule();
    };
    update(props);
    return {
      update,
      dispose() {
        entries.delete(entry);
        observer.unobserve(canvas);
        resize.unobserve(canvas);
        if (!entries.size) {
          cancelAnimationFrame(raf);
          raf = 0;
          last = 0;
        }
      },
    };
  }
  function schedule() {
    if (!raf && !document.hidden && !failure)
      raf = requestAnimationFrame((t) => {
        raf = 0;
        try {
          render(t);
        } catch (e) {
          report(e);
        }
      });
  }
  function draw(prog, values, tile) {
    gl.viewport(tile.x, surface.height - tile.y - tile.h, tile.w, tile.h);
    gl.useProgram(prog.p);
    gl.uniform1fv(prog.uniform, values);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
  function render(time, force = false) {
    if (document.hidden && !force) {
      last = 0;
      return;
    }
    if (!force && last && time - last < frameInterval - 0.5) {
      schedule();
      return;
    }
    const visible = [];
    for (const e of entries) {
      if (
        !e.canvas.isConnected ||
        (!force &&
          (!e.visible || e.canvas.closest(".window-hidden,.effects-paused")))
      )
        continue;
      const rect = e.canvas.getBoundingClientRect();
      if (
        rect.width < 1 ||
        rect.height < 1 ||
        rect.bottom <= 0 ||
        rect.top >= innerHeight ||
        rect.right <= 0 ||
        rect.left >= innerWidth
      )
        continue;
      visible.push({ e, rect });
    }
    if (!visible.length) {
      last = 0;
      return;
    }
    init();
    const dt = last ? Math.min(0.1, (time - last) / 1000) : 0;
    last = time;
    const advanced = new Set(),
      dpr = settingsPreview
        ? 1
        : Math.max(1, Math.min(devicePixelRatio || 1, 2));
    const max = Math.min(
      4096,
      gl.getParameter(gl.MAX_TEXTURE_SIZE),
      gl.getParameter(gl.MAX_RENDERBUFFER_SIZE),
    );
    let x = 0,
      y = 0,
      row = 0,
      width = 1;
    for (const item of visible) {
      const { e, rect } = item;
      e.model.setReduced(e.props.reduceMotion ?? media.matches);
      if (!advanced.has(e.model)) {
        e.model.advance(dt);
        advanced.add(e.model);
      }
      const factor = e.kind === "orb" ? 2 / 0.535 : 1;
      const w = Math.min(max, Math.ceil(rect.width * dpr * factor)),
        h = Math.min(max, Math.ceil(rect.height * dpr * factor));
      if (x + w > max) {
        x = 0;
        y += row;
        row = 0;
      }
      if (y + h > max) break;
      item.tile = { x, y, w, h };
      x += w;
      row = Math.max(row, h);
      width = Math.max(width, x);
    }
    const height = Math.max(1, y + row);
    if (surface.width !== width) surface.width = width;
    if (surface.height !== height) surface.height = height;
    gl.disable(gl.BLEND);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    for (const { e, rect, tile } of visible) {
      if (!tile) continue;
      if (e.kind === "orb")
        draw(programs.orb, e.model.orbUniforms(tile.w, tile.h), tile);
      else {
        draw(
          programs.quantum,
          e.model.quantumUniforms(rect.width, rect.height),
          tile,
        );
        if (e.model.glow > 0) {
          gl.enable(gl.BLEND);
          gl.blendFuncSeparate(
            gl.SRC_ALPHA,
            gl.ONE_MINUS_SRC_ALPHA,
            gl.ONE,
            gl.ONE_MINUS_SRC_ALPHA,
          );
          draw(
            programs.border,
            new Float32Array([tile.w, tile.h, e.model.glow, dpr]),
            tile,
          );
          gl.disable(gl.BLEND);
        }
      }
    }
    for (const { e, rect, tile } of visible) {
      if (!tile) continue;
      const w = Math.ceil(rect.width * dpr),
        h = Math.ceil(rect.height * dpr);
      if (e.canvas.width !== w) e.canvas.width = w;
      if (e.canvas.height !== h) e.canvas.height = h;
      e.context.clearRect(0, 0, w, h);
      e.context.imageSmoothingEnabled = true;
      e.context.imageSmoothingQuality = "high";
      const crop = e.kind === "orb" ? 0.535 : 1,
        dx = (tile.w * (1 - crop)) / 2,
        dy = (tile.h * (1 - crop)) / 2;
      e.context.drawImage(
        surface,
        tile.x + dx,
        tile.y + dy,
        tile.w * crop,
        tile.h * crop,
        0,
        0,
        w,
        h,
      );
    }
    frames++;
    if (frames % 120 === 1) {
      const error = gl.getError();
      if (error !== gl.NO_ERROR) throw Error("WebGL error " + error);
    }
    if ([...advanced].some((m) => m.needsAnimation)) schedule();
    else last = 0;
  }
  function useEffect(React, kind, props) {
    const ref = React.useRef(null),
      controller = React.useRef(null);
    React.useLayoutEffect(() => {
      controller.current = mount(ref.current, kind, props);
      return () => {
        controller.current.dispose();
        controller.current = null;
      };
    }, []);
    React.useLayoutEffect(() => {
      controller.current?.update(props);
    }, [props.status, props.reduceMotion, props.task, props.effect]);
    return ref;
  }
  function renderOrb(React, props) {
    const ref = useEffect(React, "orb", props);
    return React.createElement(
      "span",
      {
        "aria-hidden": "true",
        className: `status-orb qv-gpu-orb status-${props.status || "unknown"} ${props.small ? "small" : ""}`,
      },
      React.createElement("canvas", { ref, className: "qv-orb-canvas" }),
    );
  }
  function Quantum(props) {
    return ProgressEffect({ ...props, effect: "quantum" });
  }
  function ProgressEffect(props) {
    const ref = useEffect(props.react, "quantum", props);
    return props.react.createElement(
      "span",
      { className: "task-effect qv-gpu-quantum", "aria-hidden": "true" },
      props.react.createElement("canvas", {
        ref,
        className: "qv-quantum-canvas",
      }),
    );
  }
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  function registerTestReact(React, createRoot) {
    if (new URL(location.href).searchParams.get("effectsSmoke") === "1") {
      testReact = React;
      testCreateRoot = createRoot;
    }
  }
  async function selfTest() {
    if (new URL(location.href).searchParams.get("effectsSmoke") !== "1")
      throw Error("Effect fixtures are available only in isolated smoke mode.");
    if (!testReact || !testCreateRoot)
      throw Error("React integration fixture is unavailable");
    const holder = document.createElement("div");
    holder.style.cssText =
      "position:fixed;inset:0;z-index:9999;background:black;";
    document.body.append(holder);
    const before = entries.size,
      testRoot = testCreateRoot(holder);
    function TestOrb(props) {
      return renderOrb(testReact, props);
    }
    let selectedEffect = "quantum";
    const show = async (task, reduced = true) => {
      const props = { task, status: displayState(task), reduceMotion: reduced };
      testRoot.render(
        testReact.createElement(
          "div",
          null,
          testReact.createElement(TestOrb, props),
          testReact.createElement(
            "div",
            {
              className: "task-card effect-" + selectedEffect,
              style: { width: 200, height: 64, position: "relative" },
            },
            testReact.createElement(ProgressEffect, {
              ...props,
              react: testReact,
              effect: selectedEffect,
            }),
          ),
        ),
      );
      await wait(100);
      render(performance.now(), true);
      if (failure) throw Error(failure);
    };
    const energy = (c) => {
      const p = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
      let n = 0;
      for (let i = 0; i < p.length; i += 4) n += p[i] + p[i + 1] + p[i + 2];
      return n;
    };
    const check = (v, message) => {
      if (!v) throw Error(message);
    };
    try {
      const task = {
        id: "effects-smoke-only",
        status: "working",
        progress: { completed: 3, total: 5 },
        verified: true,
      };
      await show(task);
      const orb = holder.querySelector(".qv-orb-canvas"),
        quantum = holder.querySelector(".qv-quantum-canvas");
      check(orb && quantum, "React effect components did not mount");
      check(energy(orb) > 5000, "Orb pixels are empty");
      const orbEnergy = energy(orb),
        full = energy(quantum);
      await show({ ...task, progress: { completed: 0, total: 5 } });
      check(
        Math.abs(energy(quantum) - full) > 1000,
        "Quantum progress did not change GPU output",
      );
      await show({ ...task, compacting: true });
      check(
        Math.abs(energy(orb) - orbEnergy) > 1000,
        "Compacting state did not change the orb",
      );
      await show({ ...task, status: "completed" });
      const center = quantum
        .getContext("2d")
        .getImageData(quantum.width >> 1, quantum.height >> 1, 1, 1).data;
      check(
        center[0] + center[1] + center[2] < 6,
        "Reduced-motion completion did not fade the particle field",
      );
      await show(task, false);
      const framesBefore = frames;
      const orbBefore = orb.toDataURL(),
        quantumBefore = quantum.toDataURL();
      await wait(600);
      const motion = {
        frames: frames - framesBefore,
        orb: orbBefore !== orb.toDataURL(),
        quantum: quantumBefore !== quantum.toDataURL(),
        systemReducedMotion: media.matches,
        hidden: document.hidden,
      };
      check(
        motion.frames >= 3 && motion.orb && motion.quantum,
        "Live animation is not advancing: " + JSON.stringify(motion),
      );
      await show({ ...task, progress: null }, false);
      const indeterminateBefore = quantum.toDataURL();
      await wait(350);
      check(
        energy(quantum) > 1000 && quantum.toDataURL() !== indeterminateBefore,
        "Unknown progress lost its live activity field",
      );
      check(gl.getError() === gl.NO_ERROR, "WebGL pipeline error");
      check(
        document.querySelector(".qv-gpu-orb canvas"),
        "Actual React orb component was not mounted",
      );
      testRoot.unmount();
      check(
        entries.size === before,
        "Effect component teardown leaked registrations",
      );
      return {
        ok: true,
        renderer: "WebGL2",
        contexts: 1,
        orbPixels: true,
        quantumProgress: true,
        motion,
        indeterminateMotion: true,
        compacting: true,
        completed: true,
        reactOrbMounted: true,
        reactQuantumMounted: true,
        teardown: true,
        errors: errors.slice(),
      };
    } finally {
      testRoot.unmount();
      holder.remove();
      schedule();
    }
  }
  media.addEventListener("change", schedule);
  document.addEventListener("visibilitychange", () => {
    last = 0;
    if (document.hidden) {
      cancelAnimationFrame(raf);
      raf = 0;
    } else schedule();
  });
  new MutationObserver(schedule).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["class"],
    subtree: true,
  });
  window.addEventListener("resize", schedule);
  window.addEventListener("pagehide", () => {
    cancelAnimationFrame(raf);
    observer.disconnect();
    resize.disconnect();
    if (gl) {
      for (const p of Object.values(programs || {})) gl.deleteProgram(p.p);
    }
    entries.clear();
    models.clear();
  });
  window.QVEffects = {
    displayState,
    renderOrb,
    Quantum,
    ProgressEffect,
    selfTest,
    registerTestReact,
    diagnostics: () => ({
      frames,
      entries: entries.size,
      models: models.size,
      contexts: gl ? 1 : 0,
      error: failure,
      hidden: document.hidden,
      systemReducedMotion: media.matches,
      active: [...entries].map((e) => ({
        kind: e.kind,
        visible: e.visible,
        state: e.model?.state,
        reduced: e.model?.reduced,
        animating: e.model?.needsAnimation,
      })),
    }),
  };
})();
