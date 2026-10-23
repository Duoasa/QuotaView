(() => {
  "use strict";
  let next = 0;
  const pending = new Map(),
    listeners = new Set();
  chrome.webview.addEventListener("message", (event) => {
    const m = event.data;
    if (m.kind === "window-state") {
      document.documentElement.classList.toggle(
        "window-maximized",
        m.maximized,
      );
      window.dispatchEvent(new CustomEvent("qv-window-state", { detail: m }));
    } else if (m.kind === "reply") {
      const p = pending.get(m.id);
      pending.delete(m.id);
      if (p) {
        clearTimeout(p.timer);
        m.error ? p.reject(Error(m.error)) : p.resolve(m.value);
      }
    } else if (m.kind === "event" && m.channel === "qv:change")
      for (const fn of listeners) fn(m.value);
  });
  const invoke = (name, ...args) =>
    new Promise((resolve, reject) => {
      const id = ++next;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(Error("Native request timed out"));
      }, 120000);
      pending.set(id, { resolve, reject, timer });
      chrome.webview.postMessage({
        kind: "invoke",
        id,
        channel: "qv:" + name,
        args,
      });
    });
  const api = {
    subscribe: (fn) => {
      if (typeof fn !== "function") return () => {};
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
  };
  for (const [key, name] of Object.entries({
    snapshot: "snapshot",
    inspectCodexHooks: "inspectCodexHooks",
    dismissTask: "dismissTask",
    restoreTasks: "restoreTasks",
    updateSettings: "settings",
    refresh: "refresh",
    respond: "respond",
    configure: "configure",
    openSettings: "openSettings",
    resize: "resize",
    region: "region",
    maximize: "maximize",
    openExternal: "external",
    openPath: "path",
    checkUpdates: "updates",
    downloadUpdate: "downloadUpdate",
    cancelUpdate: "cancelUpdate",
    installUpdate: "installUpdate",
    quit: "quit",
    minimize: "minimize",
    showWindow: "showWindow",
    chooseDirectory: "directory",
    exportDiagnostics: "diagnostics",
    testConnection: "refresh",
  }))
    api[key] = (...args) => invoke(name, ...args);
  Object.defineProperty(window, "quotaView", {
    value: Object.freeze(api),
    writable: false,
    configurable: false,
  });
  window.addEventListener("error", (e) =>
    chrome.webview.postMessage({
      kind: "error",
      message: String(e.message).slice(0, 1000),
    }),
  );
  const frameEdge = (e) => {
    if (
      !document.querySelector(".settings-window") ||
      document.documentElement.classList.contains("window-maximized")
    )
      return 0;
    const l = e.clientX < 5,
      r = e.clientX > innerWidth - 5,
      t = e.clientY < 5,
      b = e.clientY > innerHeight - 5;
    return t
      ? l
        ? 13
        : r
          ? 14
          : 12
      : b
        ? l
          ? 16
          : r
            ? 17
            : 15
        : l
          ? 10
          : r
            ? 11
            : 0;
  };
  document.addEventListener("pointermove", (e) => {
    const edge = frameEdge(e);
    document.documentElement.style.cursor =
      {
        10: "ew-resize",
        11: "ew-resize",
        12: "ns-resize",
        15: "ns-resize",
        13: "nwse-resize",
        17: "nwse-resize",
        14: "nesw-resize",
        16: "nesw-resize",
      }[edge] || "";
  });
  document.addEventListener("pointerdown", (e) => {
    const edge = frameEdge(e);
    if (e.button === 0 && edge) {
      e.preventDefault();
      chrome.webview.postMessage({ kind: "resize-frame", edge });
      return;
    }
    if (
      e.detail === 2 &&
      e.button === 0 &&
      e.target.closest(".window-titlebar") &&
      !e.target.closest("button,input,a,select")
    ) {
      api.maximize();
      return;
    }
    if (
      e.button === 0 &&
      e.target.closest(".window-titlebar") &&
      !e.target.closest("button,input,a,select")
    )
      chrome.webview.postMessage({ kind: "drag" });
  });
})();
