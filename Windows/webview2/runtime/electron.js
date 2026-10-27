// Compatibility surface for the existing application controller. Every native
// operation is implemented by the .NET host; this does not load Electron.
import { EventEmitter } from "events";
import { call, later, receive, bootstrap } from "./bridge.js";
import { url } from "./misc.js";
const windows = new Map(),
  handlers = new Map();
let serial = 0;
const paths = { userData: bootstrap.dataDir };
export const app = new EventEmitter();
Object.assign(app, {
  isPackaged: true,
  setName: () => {},
  getPath: (n) => paths[n] || bootstrap.home,
  setPath: (n, p) => {
    paths[n] = p;
  },
  getLocale: () => bootstrap.locale,
  getVersion: () => bootstrap.version,
  requestSingleInstanceLock: () => true,
  whenReady: () => Promise.resolve(),
  setLoginItemSettings: (o) => call("app.autostart", o),
  quit: () => {
    app.emit("before-quit");
    call("app.exit", 0);
  },
  exit: (code) => call("app.exit", code),
});
receive("app", (e) => app.emit(e.type));
export const windowsUpdater = new EventEmitter();
Object.assign(windowsUpdater, {
  check: () => later("update.check"),
  status: () => later("update.status"),
  download: () => later("update.download"),
  cancel: () => later("update.cancel"),
  install: () => later("update.install"),
});
receive("updater", (e) => windowsUpdater.emit("state", e.value));
export class BrowserWindow extends EventEmitter {
  constructor(options) {
    super();
    this.id = ++serial;
    this.options = options;
    this.bounds = { x: 0, y: 0, width: options.width, height: options.height };
    this.destroyed = false;
    this.background = options.backgroundColor;
    this.webContents = new EventEmitter();
    Object.assign(this.webContents, {
      id: this.id,
      mainFrame: { url: "" },
      send: (channel, value) => call("window.send", this.id, channel, value),
      executeJavaScript: (script) => later("window.eval", this.id, script),
      getLastWebPreferences: () => ({
        contextIsolation: true,
        nodeIntegration: false,
      }),
      setWindowOpenHandler: () => {},
    });
    windows.set(this.id, this);
    call("window.create", this.id, options);
    receive("window-" + this.id, (e) => {
      if (e.type === "state") this.maximized = e.maximized;
      if (e.type === "closed") {
        this.destroyed = true;
        windows.delete(this.id);
      }
      if (e.type === "bounds") this.bounds = e.value;
      else this.emit(e.type, { preventDefault() {} });
    });
  }
  static fromWebContents(wc) {
    return windows.get(wc?.id);
  }
  async loadFile(file, options) {
    this.webContents.mainFrame.url =
      url.pathToFileURL(file).href +
      "?" +
      new URLSearchParams(options?.query || {});
    await later("window.load", this.id, file, options?.query || {});
    this.emit("ready-to-show");
  }
  capture(folder) {
    return later("window.capture", this.id, folder);
  }
  setBounds(b, animate = false) {
    this.bounds = b;
    call("window.bounds", this.id, b, animate);
  }
  getBounds() {
    return this.bounds;
  }
  setAlwaysOnTop(v) {
    call("window.top", this.id, v);
  }
  setBackgroundMaterial(v) {
    call("window.material", this.id, v);
  }
  setBackgroundColor(v) {
    this.background = v;
    call("window.background", this.id, v);
  }
  getBackgroundColor() {
    return this.background;
  }
  setShape(v) {
    call("window.region", this.id, v);
  }
  isDestroyed() {
    return this.destroyed;
  }
  showInactive() {
    call("window.show", this.id, false);
  }
  show() {
    call("window.show", this.id, true);
  }
  hide() {
    call("window.hide", this.id);
  }
  focus() {
    call("window.focus", this.id);
  }
  minimize() {
    call("window.state", this.id, "minimize");
  }
  maximize() {
    this.maximized = true;
    call("window.state", this.id, "maximize");
  }
  unmaximize() {
    this.maximized = false;
    call("window.state", this.id, "normal");
  }
  isMaximized() {
    return !!this.maximized;
  }
}
export const ipcMain = { handle: (name, fn) => handlers.set(name, fn) };
receive("ipc", async (e) => {
  const w = windows.get(e.window);
  try {
    if (!w) throw Error("Unknown window");
    const fn = handlers.get(e.channel);
    if (!fn) throw Error("Unknown method");
    const value = await fn(
      { sender: w.webContents, senderFrame: w.webContents.mainFrame },
      ...e.args,
    );
    call("window.reply", e.window, e.request, { value: value ?? null });
  } catch (error) {
    call("window.reply", e.window, e.request, {
      error: String(error.message || error),
    });
  }
});
export const screen = new EventEmitter();
Object.assign(screen, {
  getAllDisplays: () => call("screen.all"),
  getPrimaryDisplay: () =>
    screen.getAllDisplays().find((x) => x.primary) ||
    screen.getAllDisplays()[0],
  getCursorScreenPoint: () => call("screen.cursor"),
  getDisplayNearestPoint: (p) => call("screen.nearest", p),
  getDisplayMatching: (b) => call("screen.match", b),
  screenToDipRect: (_, b) => call("screen.dip", b),
});
receive("screen", (e) => screen.emit("display-metrics-changed", e));
export const nativeTheme = new EventEmitter();
let theme = "system";
Object.defineProperties(nativeTheme, {
  themeSource: {
    get: () => theme,
    set: (v) => {
      theme = v;
      call("theme.set", v);
    },
  },
  shouldUseDarkColors: {
    get: () =>
      theme === "dark" || (theme === "system" && call("theme.get").dark),
  },
  shouldUseHighContrastColors: { get: () => call("theme.get").highContrast },
  prefersReducedTransparency: { get: () => !call("theme.get").transparency },
});
receive("theme", () => nativeTheme.emit("updated"));
export const shell = {
  openExternal: (u) => later("shell.external", u),
  openPath: (p) => later("shell.path", p, false),
  showItemInFolder: (p) => later("shell.path", p, true),
};
export const dialog = {
  showOpenDialog: (w, o) => later("dialog.open", w.id, o),
  showSaveDialog: (w, o) => later("dialog.save", w.id, o),
  showErrorBox: (title, message) => call("dialog.error", title, message),
};
export const nativeImage = {
  createFromPath: (p) => ({
    path: p,
    isEmpty: () => false,
    resize() {
      return this;
    },
  }),
};
const menuFunctions = new Map();
export const Menu = {
  buildFromTemplate: (rows) =>
    rows.map((r) => {
      const id = "menu-" + ++serial;
      if (r.click) menuFunctions.set(id, r.click);
      return { id, label: r.label, type: r.type };
    }),
};
receive("menu", (e) => menuFunctions.get(e.value)?.());
export class Tray extends EventEmitter {
  constructor(image) {
    super();
    call("tray.create", image.path);
    receive("tray", (e) => this.emit(e.type));
  }
  setToolTip(s) {
    call("tray.tooltip", s);
  }
  setContextMenu(m) {
    call("tray.menu", m);
  }
  destroy() {
    call("tray.destroy");
  }
}
export class Notification {
  constructor(options) {
    this.options = options;
  }
  static isSupported() {
    return true;
  }
  show() {
    call("notification", this.options);
  }
}
export const session = {
  defaultSession: {
    setProxy: async (o) => call("proxy.settings", o),
    resolveProxy: (u) => later("proxy.resolve", u),
    setPermissionRequestHandler: () => {},
    setPermissionCheckHandler: () => {},
    webRequest: { onBeforeRequest: () => {} },
  },
};
export const net = {
  fetch: async (u, o) => {
    const r = await later("http.fetch", u, { headers: o?.headers || {} });
    return {
      status: r.status,
      ok: r.status >= 200 && r.status < 300,
      json: async () => JSON.parse(r.body),
    };
  },
};
