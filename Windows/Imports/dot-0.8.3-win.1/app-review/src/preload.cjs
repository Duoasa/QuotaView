"use strict";
const { contextBridge, ipcRenderer } = require("electron");
const call = (name, ...args) => ipcRenderer.invoke("qv:" + name, ...args);
contextBridge.exposeInMainWorld(
  "quotaView",
  Object.freeze({
    snapshot: () => call("snapshot"),
    subscribe: (callback) => {
      if (typeof callback !== "function") return () => {};
      const listener = (_event, value) => callback(value);
      ipcRenderer.on("qv:change", listener);
      return () => ipcRenderer.removeListener("qv:change", listener);
    },
    inspectCodexHooks: () => call("inspectCodexHooks"),
    dismissTask: (request) => call("dismissTask", request),
    restoreTasks: () => call("restoreTasks"),
    updateSettings: (patch) => call("settings", patch),
    refresh: () => call("refresh"),
    respond: (request) => call("respond", request),
    configure: (request) => call("configure", request),
    openSettings: () => call("openSettings"),
    resize: (request) => call("resize", request),
    openExternal: (url) => call("external", url),
    openPath: (p) => call("path", p),
    checkUpdates: () => call("updates"),
    quit: () => call("quit"),
    minimize: () => call("minimize"),
    showWindow: (name) => call("showWindow", name),
    chooseDirectory: () => call("directory"),
    exportDiagnostics: () => call("diagnostics"),
    testConnection: () => call("refresh"),
  }),
);
