"use strict";
// Hook helpers are headless and must bypass Electron readiness and single-instance.
const codexHookIndex = process.argv.indexOf("--quotaview-codex-hook");
const hookIndex = process.argv.indexOf("--quotaview-hook");
if (codexHookIndex >= 0) {
  Promise.resolve(
    require("./core/codex-hook.cjs").main(
      process.argv.slice(codexHookIndex + 1),
    ),
  ).then(
    () => process.exit(0),
    () => process.exit(0),
  );
} else if (hookIndex >= 0) {
  Promise.resolve(
    require("./core/hook.cjs").main(process.argv.slice(hookIndex + 1)),
  ).then(
    () => process.exit(0),
    () => process.exit(0),
  );
} else {
  runApplication();
}
function runApplication() {
  const {
    app,
    BrowserWindow,
    ipcMain,
    Tray,
    Menu,
    nativeImage,
    screen,
    shell,
    dialog,
    Notification,
    nativeTheme,
    session,
    net,
  } = require("electron");
  const fs = require("node:fs"),
    path = require("node:path"),
    os = require("node:os"),
    crypto = require("node:crypto");
  const { SettingsStore } = require("./core/settings.cjs");
  const { DismissedTasks } = require("./core/task-history.cjs");
  const { selectRelease } = require("./core/updates.cjs");
  const { fileURLToPath } = require("node:url");
  const {
    ForegroundMonitor,
    safeExternal,
    placeIsland,
  } = require("./core/platform.cjs");
  const { CodexService } = require("./core/codex.cjs");
  const { IntegrationService } = require("./core/integrations.cjs");
  const SMOKE = process.argv.includes("--smoke-test");
  const smokeReport = process.argv
    .find((a) => a.startsWith("--smoke-report="))
    ?.slice(15);
  if (SMOKE)
    app.setPath(
      "userData",
      fs.mkdtempSync(path.join(os.tmpdir(), "quotaview-smoke-")),
    );
  app.setName("QuotaView Windows");
  if (!app.requestSingleInstanceLock()) {
    app.quit();
    return;
  }
  let store,
    dismissed,
    settings,
    codex,
    integrations,
    tray,
    island,
    capsule,
    preferences,
    refreshTimer,
    collapseTimer,
    hideTimer,
    pointerTimer,
    updateTimer,
    activeDisplayId;
  const windowLoads = new Map();
  const rendererErrors = [];
  let expanded = false,
    pinned = false,
    hovered = false,
    expansionReason = null,
    quitting = false,
    lastSnapshot = null,
    update = { available: false, checking: false };
  let oldTaskStates = new Map(),
    notifyQuota = new Map(),
    publishTimer = null,
    backendRevision = 0;
  const foreground = new ForegroundMonitor();
  const ROOT = path.join(__dirname, "..");
  const HTML = path.join(ROOT, "dist", "renderer", "index.html");
  const RELEASE_API =
    "https://api.github.com/repos/Duoasa/quotaview-windows/releases?per_page=30";
  const RELEASE_PAGE = "https://github.com/Duoasa/quotaview-windows/releases";
  function locale() {
    return settings?.language === "zh" ||
      (settings?.language === "system" && app.getLocale().startsWith("zh"))
      ? "zh"
      : "en";
  }
  function word(en, zh) {
    return locale() === "zh" ? zh : en;
  }
  function display() {
    const all = screen.getAllDisplays();
    if (settings.display === "primary") return screen.getPrimaryDisplay();
    if (settings.display === "active" && activeDisplayId)
      return (
        all.find((x) => x.id === activeDisplayId) || screen.getPrimaryDisplay()
      );
    if (settings.display === "cursor" || settings.display === "active")
      return screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
    return (
      all.find((x) => String(x.id) === settings.display) ||
      screen.getPrimaryDisplay()
    );
  }
  function secureWindow(win) {
    win.webContents.on("render-process-gone", (_event, details) =>
      rendererErrors.push("Renderer exited: " + details.reason),
    );
    win.webContents.on("console-message", (_event, details, _line, _source) => {
      if (details?.level === "error")
        rendererErrors.push(String(details.message).slice(0, 500));
    });
    win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
    // Renderer documents never navigate. All external links use the narrow IPC route.
    win.webContents.on("will-navigate", (event) => event.preventDefault());
    win.webContents.on("will-attach-webview", (event) =>
      event.preventDefault(),
    );
    win.on("closed", () => {
      if (win === preferences) preferences = null;
    });
  }
  function createWindow(view, width, height) {
    const win = new BrowserWindow({
      width,
      height,
      show: false,
      frame: false,
      transparent: view !== "settings",
      resizable: view === "settings",
      minWidth: view === "settings" ? 720 : undefined,
      minHeight: view === "settings" ? 520 : undefined,
      skipTaskbar: view !== "settings",
      alwaysOnTop: view !== "settings" && settings.alwaysOnTop,
      backgroundColor: view === "settings" ? "#17191f" : "#00000000",
      hasShadow: view === "settings",
      title: "QuotaView Windows",
      icon: path.join(ROOT, "dist", "assets", "icon.png"),
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
        webSecurity: true,
        allowRunningInsecureContent: false,
        devTools: !app.isPackaged,
      },
    });
    secureWindow(win);
    windowLoads.set(view, win.loadFile(HTML, { query: { view } }));
    win.once("ready-to-show", () => {
      if (!SMOKE) win.showInactive();
    });
    return win;
  }
  function material() {
    for (const win of [island, capsule])
      if (win && !win.isDestroyed()) {
        win.setAlwaysOnTop(settings.alwaysOnTop, "floating");
        if (
          process.platform === "win32" &&
          typeof win.setBackgroundMaterial === "function"
        ) {
          try {
            win.setBackgroundMaterial(
              settings.material === "glass" ? "acrylic" : "none",
            );
          } catch {}
        }
      }
    nativeTheme.themeSource = settings.theme;
  }
  function reposition(height) {
    if (!island || island.isDestroyed()) return;
    const d = display();
    island.setBounds(
      placeIsland(
        d,
        expanded ? settings.islandWidth : 270,
        expanded
          ? Math.min(height || Math.min(island.getBounds().height < 180 ? 570 : island.getBounds().height, 800), d.workArea.height - (settings.showCapsule ? 112 : 16))
          : 66,
      ),
    );
    if (capsule && !capsule.isDestroyed()) {
      const b = placeIsland(d, 360, 76);
      capsule.setBounds({
        ...b,
        y: b.y + (expanded ? island.getBounds().height : 66) + 8,
      });
    }
  }
  function setExpanded(value, reason) {
    clearTimeout(hideTimer);
    expanded = !!value;
    if (!expanded) pinned = false;
    expansionReason = reason || null;
    reposition(expanded ? 570 : 66);
    if (!expanded && settings.hiddenDelaySeconds > 0)
      hideTimer = setTimeout(() => {
        const live = snapshot().tasks.some(
          (t) =>
            !["completed", "failed", "interrupted", "unknown"].includes(
              t.status,
            ),
        );
        if (!expanded && !live) island?.hide();
      }, settings.hiddenDelaySeconds * 1000);
    publish();
  }
  function snapshot() {
    const a = codex?.getSnapshot?.() || {};
    const b = integrations?.getSnapshot?.() || {};
    const allTasks = [...(a.tasks || []), ...(b.tasks || [])].filter(
      (t) => settings.providers[t.provider] !== false,
    );
    const backgroundTasks = allTasks.filter((t) => t.sessionKind === "memory");
    const tasks = allTasks
      .filter((t) => t.sessionKind !== "memory" && !dismissed?.has(t))
      .sort((x, y) => (y.updatedAt || 0) - (x.updatedAt || 0))
      .slice(0, 512);
    const quota = b.quota || {};
    const usage = b.usage || {};
    return {
      tasks,
      backgroundTasks,
      quotas: {
        codex: a.quota || null,
        claude: quota.provider === "claude" ? quota : quota.claude || null,
      },
      usage: {
        codex: a.usage || null,
        claude: usage.provider === "claude" ? usage : usage.claude || null,
      },
      providers: {
        codex: { enabled: settings.providers.codex, ...(a.state || {}) },
        claude: {
          enabled: settings.providers.claude,
          ...(b.states?.claude || {}),
        },
        dsh: { enabled: settings.providers.dsh, ...(b.states?.dsh || {}) },
        kimi: { enabled: settings.providers.kimi, ...(b.states?.kimi || {}) },
      },
      settings,
      displays: screen
        .getAllDisplays()
        .map((d) => ({
          id: String(d.id),
          name: d.label || `Display ${d.id}`,
          primary: d.id === screen.getPrimaryDisplay().id,
          width: d.bounds.width,
          height: d.bounds.height,
          scaleFactor: d.scaleFactor,
        })),
      version: app.getVersion(),
      locale: locale(),
      update,
      ui: { expanded, expansionReason, pinned, hovered },
      platform: {
        os: process.platform,
        glassNative:
          process.platform === "win32" &&
          Number(os.release().split(".")[2]) >= 22621,
        activeWindowTracking: foreground.available,
      },
      warning: store.error,
    };
  }
  function publish() {
    if (publishTimer) return;
    publishTimer = setTimeout(() => {
      publishTimer = null;
      if (!settings) return;
      lastSnapshot = snapshot();
      for (const w of [island, capsule, preferences])
        if (w && !w.isDestroyed())
          w.webContents.send("qv:change", lastSnapshot);
    }, 60);
  }
  function notificationsAndExpansion() {
    const s = snapshot();
    for (const t of s.tasks) {
      const previous = oldTaskStates.get(t.id);
      const terminal = ["completed", "failed", "interrupted"].includes(
        t.status,
      );
      if (previous !== t.status && !terminal && t.status !== "unknown")
        island?.showInactive();
      if (
        previous &&
        previous !== t.status &&
        terminal && t.verified !== false &&
        settings.notifications &&
        settings.completionNotifications &&
        Notification.isSupported()
      ) {
        new Notification({
          title: word(
            `${t.provider}: ${t.status}`,
            `${t.provider}：${t.status === "completed" ? "已完成" : t.status === "failed" ? "失败" : "已中断"}`,
          ),
          body: settings.privacy
            ? word("A task has finished.", "一项任务已结束。")
            : String(t.title || word("Agent task", "Agent 任务")).slice(0, 200),
          silent: false,
        }).show();
      }
      if (previous !== t.status && settings.autoExpand) {
        if (
          (t.status === "waiting" && settings.autoExpandOnApproval) ||
          (previous && terminal && t.verified !== false && settings.autoExpandOnComplete) ||
          (!previous && !terminal && settings.autoExpandOnStart)
        ) {
          setExpanded(true, t.status);
          if (collapseTimer) clearTimeout(collapseTimer);
          const delay = terminal
            ? settings.compactDelaySeconds
            : settings.collapseDelaySeconds;
          if (t.status !== "waiting" && delay > 0)
            collapseTimer = setTimeout(() => { if (!pinned && !hovered && !snapshot().tasks.some(task => task.status === "waiting")) setExpanded(false); }, delay * 1000);
        }
      }
      oldTaskStates.set(t.id, t.status);
    }
    if (oldTaskStates.size > 1024) {
      const ids = new Set(s.tasks.map((t) => t.id));
      oldTaskStates = new Map([...oldTaskStates].filter(([k]) => ids.has(k)));
    }
    for (const [provider, q] of Object.entries(s.quotas)) {
      if (!settings.notifications || !settings.lowQuotaNotifications || !q)
        continue;
      for (const w of q.windows || []) {
        const key = `${provider}:${w.name}:${w.resetAt}`;
        if (
          Number.isFinite(w.usedPercent) &&
          w.usedPercent >= 80 &&
          !notifyQuota.has(key) &&
          Notification.isSupported()
        ) {
          notifyQuota.set(key, Date.now());
          new Notification({
            title: word("Quota running low", "额度即将用尽"),
            body: `${provider} · ${w.name}: ${Math.max(0, 100 - w.usedPercent).toFixed(0)}% ${word("remaining", "剩余")}`,
          }).show();
        }
      }
    }
    if (notifyQuota.size > 100)
      notifyQuota = new Map([...notifyQuota].slice(-50));
    publish();
  }
  function bindService(s) {
    s?.on?.("change", notificationsAndExpansion);
    s?.on?.("error", () => publish());
  }
  async function createServices(codexOnly = false) {
    const rev = ++backendRevision;
    await codex?.stop?.();
    if (!codexOnly) await integrations?.stop?.();
    if (rev !== backendRevision) return;
    codex = new CodexService({
      dataDir: app.getPath("userData"),
      hookExecutable: app.isPackaged ? require("./core/helper-runtime.cjs").materializeHelper(process.resourcesPath, app.getPath("userData")) : process.execPath,
      packaged: app.isPackaged,
      electronMainPath: app.isPackaged
        ? undefined
        : path.join(__dirname, "main.cjs"),
      activityHooks: settings.codexActivityHooks,
      hookScope: settings.codexHookScope,
      home: settings.codexHome || undefined,
      executable: settings.codexPath || undefined,
      pollInterval: 1500,
      version: app.getVersion(),
      enabled: settings.providers.codex,
    });
    if (!codexOnly)
      integrations = new IntegrationService({
        dataDir: app.getPath("userData"),
        settings,
        executable: app.isPackaged ? require("./core/helper-runtime.cjs").materializeHelper(process.resourcesPath, app.getPath("userData")) : process.execPath,
        hookPath: path.join(__dirname, "core", "hook.cjs"),
        packaged: app.isPackaged,
        electronMainPath: app.isPackaged
          ? undefined
          : path.join(__dirname, "main.cjs"),
        claudeHome: settings.claudeHome || undefined,
      });
    bindService(codex);
    if (!codexOnly) bindService(integrations);
    if (settings.providers.codex) await codex.start();
    if (!codexOnly) await integrations.start();
    publish();
  }
  async function refresh() {
    const results = await Promise.allSettled([
      settings.providers.codex ? codex?.refresh?.() : null,
      integrations?.refresh?.(),
    ]);
    publish();
    return {
      ok: results.every((r) => r.status === "fulfilled"),
      errors: results
        .filter((r) => r.status === "rejected")
        .map((r) => String(r.reason?.message || r.reason).slice(0, 300)),
    };
  }
  function configureTimers() {
    clearInterval(refreshTimer);
    refreshTimer = setInterval(
      () => refresh().catch(() => {}),
      settings.refreshSeconds * 1000,
    );
    clearInterval(pointerTimer);
    if (settings.display === "cursor" && !SMOKE) {
      let previousDisplay = display().id;
      pointerTimer = setInterval(() => {
        const nextDisplay = display().id;
        if (nextDisplay !== previousDisplay) { previousDisplay = nextDisplay; reposition(); }
      }, 1500);
    }
    clearInterval(updateTimer);
    if (settings.autoCheckUpdates) {
      updateTimer = setInterval(
        () => checkUpdates().catch(() => {}),
        24 * 60 * 60 * 1000,
      );
    }
    if (settings.display === "active" && !SMOKE) foreground.start();
    else foreground.stop();
  }
  async function applySettings(patch) {
    const before = settings;
    if (
      patch?.proxy?.mode === "manual" &&
      !patch.proxy.url &&
      !settings.proxy.url
    )
      throw Error("A proxy URL is required for manual proxy mode.");
    settings = store.update(patch);
    if (before.startAtLogin !== settings.startAtLogin)
      app.setLoginItemSettings({
        openAtLogin: settings.startAtLogin,
        path: process.env.PORTABLE_EXECUTABLE_FILE || process.execPath,
        args: app.isPackaged ? [] : [path.join(__dirname, "main.cjs")],
      });
    if (integrations) integrations.settings = settings;
    if (settings.proxy.mode === "manual" && !settings.proxy.url)
      throw Error("A proxy URL is required for manual proxy mode.");
    await session.defaultSession.setProxy(
      settings.proxy.mode === "manual"
        ? { mode: "fixed_servers", proxyRules: settings.proxy.url }
        : { mode: settings.proxy.mode === "direct" ? "direct" : "system" },
    );
    material();
    if (capsule) {
      if (settings.showCapsule && !SMOKE) capsule.showInactive();
      else capsule.hide();
    }
    configureTimers();
    reposition();
    if (["codexHome", "codexPath"].some((k) => before[k] !== settings[k]))
      await createServices(true);
    if (before.claudeHome !== settings.claudeHome)
      await integrations?.refresh?.();
    publish();
    return settings;
  }
  function openSettings() {
    if (preferences && !preferences.isDestroyed()) {
      preferences.show();
      preferences.focus();
      return;
    }
    preferences = createWindow("settings", 920, 690);
    preferences.on("close", (event) => {
      if (!quitting) {
        event.preventDefault();
        preferences.hide();
      }
    });
    preferences.once("ready-to-show", () => {
      if (!SMOKE) preferences.show();
    });
  }
  function buildTray() {
    let icon = nativeImage.createFromPath(
      path.join(ROOT, "dist", "assets", "tray.png"),
    );
    if (icon.isEmpty())
      icon = nativeImage.createFromPath(
        path.join(ROOT, "dist", "assets", "icon.png"),
      );
    tray = new Tray(icon.resize({ width: 20, height: 20 }));
    tray.setToolTip("QuotaView Windows");
    tray.setContextMenu(
      Menu.buildFromTemplate([
        {
          label: word("Show Island", "显示灵动岛"),
          click: () => {
            island.showInactive();
            setExpanded(true, "tray");
          },
        },
        { label: word("Refresh usage", "刷新用量"), click: () => refresh() },
        { label: word("Settings", "设置"), click: openSettings },
        { type: "separator" },
        {
          label: word("Check for updates", "检查更新"),
          click: () => checkUpdates().then(openSettings),
        },
        { label: word("Quit", "退出"), click: () => app.quit() },
      ]),
    );
    tray.on("click", () => {
      island.showInactive();
      setExpanded(!expanded, "tray");
    });
  }
  function trusted(event) {
    const w = BrowserWindow.fromWebContents(event.sender);
    if (
      !w || ![island, capsule, preferences].includes(w) ||
      event.senderFrame !== event.sender.mainFrame
    )
      throw Error("Untrusted IPC sender");
    const u = new URL(event.senderFrame.url);
    if (u.protocol !== "file:") throw Error("Untrusted IPC origin");
    const originPath = path.resolve(fileURLToPath(u));
    const expectedPath = path.resolve(HTML);
    if ((process.platform === "win32" ? originPath.toLowerCase() !== expectedPath.toLowerCase() : originPath !== expectedPath)) throw Error("Untrusted IPC document");
  }
  function handle(name, fn) {
    ipcMain.handle("qv:" + name, async (event, ...args) => {
      trusted(event);
      return fn(event, ...args);
    });
  }
  async function checkUpdates() {
    if (update.checking) return update;
    update = { ...update, checking: true, error: null };
    publish();
    try {
      const response = await net.fetch(RELEASE_API, {
        headers: {
          Accept: "application/vnd.github+json",
          "User-Agent": "QuotaView-Windows",
        },
        signal: AbortSignal.timeout(15000),
      });
      if (response.status === 404) {
        update = {
          checking: false,
          available: false,
          url: RELEASE_PAGE,
          message: word(
            "No Windows release has been published yet.",
            "尚未发布 Windows 版本。",
          ),
        };
      } else {
        if (!response.ok) throw Error(`GitHub HTTP ${response.status}`);
        const body = await response.json();
        update = selectRelease(body, app.getVersion());
      }
    } catch (e) {
      update = {
        ...update,
        checking: false,
        error: String(e.message).slice(0, 300),
      };
    }
    update = { ...update, checkedAt: Date.now() };
    publish();
    return update;
  }
  function registerIPC() {
    handle("snapshot", () => snapshot());
    handle("inspectCodexHooks", () => codex.inspectHooks());
    handle("dismissTask", (_, request) => {
      const task = snapshot().tasks.find((t) => t.id === request?.id);
      if (!task) throw Error("Task no longer exists");
      dismissed.dismiss(task);
      publish();
      return { ok: true };
    });
    handle("restoreTasks", () => {
      dismissed.restore();
      publish();
      return { ok: true };
    });
    handle("settings", (_, patch) => {
      if (patch?.providers)
        throw Error("Use Connections to enable or disable an integration.");
      return applySettings(patch);
    });
    handle("refresh", () => refresh());
    handle("configure", async (_, request) => {
      const { provider, enabled, options } = request || {};
      if (
        !["codex", "claude", "dsh", "kimi"].includes(provider) ||
        typeof enabled !== "boolean"
      )
        throw Error("Invalid connection request");
      if (provider === "codex") {
        if (options && typeof options.activityHooks === "boolean") {
          await codex.configure(options);
          settings = store.update({
            codexActivityHooks: options.activityHooks,
            codexHookScope: options.scope || settings.codexHookScope,
          });
        }
        settings = store.update({ providers: { codex: enabled } });
        if (enabled) await codex.start();
        else await codex.stop();
      } else {
        await integrations.configure(provider, enabled, {
          ...(provider === "claude"
            ? { home: settings.claudeHome || undefined }
            : {}),
          ...(provider === "dsh" ? { roots: settings.dshRoots } : {}),
          ...options,
        });
        settings = store.update({ providers: { [provider]: enabled } });
      }
      publish();
      return snapshot();
    });
    handle("respond", async (_, request) => {
      if (
        !request ||
        typeof request.id !== "string" ||
        request.id.length > 512 ||
        !(
          (typeof request.decision === "string" &&
            [
              "allow",
              "deny",
              "accept",
              "acceptAlways",
              "acceptForSession",
              "decline",
              "cancel",
            ].includes(request.decision)) ||
          (request.decision &&
            typeof request.decision === "object" &&
            !Array.isArray(request.decision))
        ) ||
        JSON.stringify(request).length > 262144
      )
        throw Error("Invalid approval response");
      const s = snapshot();
      const task = s.tasks.find((t) => t.approval?.id === request.id);
      if (!task?.approval?.canRespond)
        throw Error("This request must be answered in the original client.");
      const service = task.provider === "codex" ? codex : integrations;
      const result = await service.respond(request.id, request.decision);
      publish();
      return result;
    });
    handle("openSettings", () => openSettings());
    handle("resize", (_, r) => {
      if (typeof r?.expanded !== "boolean") throw Error("Invalid resize");
      if (typeof r.pinned === "boolean") { pinned = r.pinned; if (pinned) clearTimeout(collapseTimer); }
      if (typeof r.hovered === "boolean") hovered = r.hovered;
      if (expanded !== r.expanded) setExpanded(r.expanded);
      if (Number.isFinite(r.height)) reposition(
        Number.isFinite(r.height)
          ? Math.max(180, Math.min(r.height, 900))
          : undefined,
      );
      publish();
      return { expanded };
    });
    handle("external", (_, url) => shell.openExternal(safeExternal(url)));
    handle("path", async (_, p) => {
      if (typeof p !== "string" || p.length > 4096 || p.includes("\0"))
        throw Error("Invalid path");
      const stat = await fs.promises.stat(p);
      if (stat.isDirectory()) return shell.openPath(p);
      shell.showItemInFolder(p);
      return "";
    });
    handle("updates", () => checkUpdates());
    handle("quit", () => app.quit());
    handle("minimize", (event) =>
      BrowserWindow.fromWebContents(event.sender)?.minimize(),
    );
    handle("showWindow", (_, name) => {
      if (name === "close-settings") preferences?.hide();
      else if (name === "settings") openSettings();
      else if (name === "island") {
        island.showInactive();
        setExpanded(true, "requested");
      } else if (name === "capsule") capsule.showInactive();
    });
    handle("directory", async (event) => {
      const result = await dialog.showOpenDialog(
        BrowserWindow.fromWebContents(event.sender),
        {
          properties: ["openDirectory"],
          title: word("Select agent data directory", "选择 Agent 数据目录"),
        },
      );
      return result.canceled ? null : result.filePaths[0];
    });
    handle("diagnostics", async (event) => {
      const result = await dialog.showSaveDialog(
        BrowserWindow.fromWebContents(event.sender),
        {
          defaultPath: "quotaview-diagnostics.json",
          filters: [{ name: "JSON", extensions: ["json"] }],
        },
      );
      if (result.canceled) return null;
      const s = snapshot();
      const data = {
        version: s.version,
        platform: process.platform,
        osRelease: os.release(),
        arch: process.arch,
        providers: Object.fromEntries(
          Object.entries(s.providers).map(([k, v]) => [
            k,
            {
              enabled: v.enabled,
              connected: v.connected,
              lastEventAt: v.lastEventAt,
            },
          ]),
        ),
        taskCount: s.tasks.length,
        statusCounts: s.tasks.reduce(
          (r, t) => ((r[t.status] = (r[t.status] || 0) + 1), r),
          {},
        ),
        displayCount: s.displays.length,
        settings: {
          language: settings.language,
          theme: settings.theme,
          material: settings.material,
        },
        generatedAt: new Date().toISOString(),
        privacy:
          "No task content, credentials, account identifiers, local paths, raw session IDs, or request payloads are included.",
      };
      await fs.promises.writeFile(
        result.filePath,
        JSON.stringify(data, null, 2),
      );
      return result.filePath;
    });
  }
  foreground.on("unavailable", () => { activeDisplayId = undefined; reposition(); publish(); });
  foreground.on("rect", (rect) => {
    const bounds = { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    const dipBounds = process.platform === "win32" ? screen.screenToDipRect(null, bounds) : bounds;
    const d = screen.getDisplayMatching(dipBounds);
    if (activeDisplayId !== d.id) {
      activeDisplayId = d.id;
      reposition();
    }
  });
  app.on("second-instance", () => {
    if (island) {
      island.showInactive();
      setExpanded(true, "second-instance");
    }
  });
  app.on("window-all-closed", () => {});
  app.on("before-quit", () => {
    quitting = true;
    clearInterval(refreshTimer);
    clearInterval(pointerTimer);
    clearInterval(updateTimer);
    clearTimeout(collapseTimer);
    clearTimeout(hideTimer);
    foreground.stop();
    codex?.stop?.();
    integrations?.stop?.();
    tray?.destroy();
  });
  app
    .whenReady()
    .then(async () => {
      store = new SettingsStore(app.getPath("userData"));
      dismissed = new DismissedTasks(app.getPath("userData"));
      settings = store.load();
      await session.defaultSession.setProxy(
        settings.proxy.mode === "manual" && settings.proxy.url
          ? { mode: "fixed_servers", proxyRules: settings.proxy.url }
          : { mode: settings.proxy.mode === "direct" ? "direct" : "system" },
      );
      session.defaultSession.setPermissionRequestHandler(
        (_wc, _permission, callback) => callback(false),
      );
      session.defaultSession.setPermissionCheckHandler(() => false);
      session.defaultSession.webRequest.onBeforeRequest(
        { urls: ["http://*/*", "https://*/*"] },
        (details, callback) => {
          if (details.webContentsId) callback({ cancel: true });
          else callback({});
        },
      );
      island = createWindow("island", 270, 66);
      capsule = createWindow("capsule", 360, 76);
      if (!settings.showCapsule)
        capsule.once("ready-to-show", () => capsule.hide());
      registerIPC();
      material();
      reposition();
      screen.on("display-added", () => {
        reposition();
        publish();
      });
      screen.on("display-removed", () => {
        reposition();
        publish();
      });
      screen.on("display-metrics-changed", () => {
        reposition();
        publish();
      });
      if (SMOKE) {
        preferences = createWindow("settings", 920, 690);
        await Promise.race([
          Promise.all(windowLoads.values()),
          new Promise((_, reject) =>
            setTimeout(
              () => reject(Error("Renderer startup timed out")),
              20000,
            ).unref(),
          ),
        ]);
        const bridge = await island.webContents.executeJavaScript(
          "window.quotaView.snapshot().then(s => ({version:s.version,taskCount:s.tasks.length,hasSettings:!!s.settings}))",
        );
        if (!bridge.hasSettings || bridge.taskCount !== 0)
          throw Error("Smoke preload bridge failed");
        for (const win of [island, capsule, preferences]) {
          const mounted = await win.webContents.executeJavaScript(
            "new Promise(resolve=>{let n=0;const check=()=>{if(document.querySelector('.fatal-error'))resolve(false);else if(document.getElementById('root')?.childElementCount)resolve(true);else if(++n>=30)resolve(false);else setTimeout(check,100);};check();})",
          );
          if (!mounted) throw Error("Renderer root did not mount");
        }
        if (rendererErrors.length) throw Error(rendererErrors.join("; "));
        const evidence = {
          ok: true,
          version: app.getVersion(),
          platform: process.platform,
          arch: process.arch,
          packaged: app.isPackaged,
          rendererLoaded: true,
          views: [...windowLoads.keys()],
          preloadBridge: true,
          reactMounted: true,
          rendererErrors: [],
          contextIsolation:
            island.webContents.getLastWebPreferences().contextIsolation,
          nodeIntegration:
            island.webContents.getLastWebPreferences().nodeIntegration,
        };
        if (smokeReport)
          fs.writeFileSync(smokeReport, JSON.stringify(evidence, null, 2));
        console.log(JSON.stringify(evidence));
        app.exit(0);
        return;
      }
      buildTray();
      await createServices();
      configureTimers();
      if (settings.autoCheckUpdates) checkUpdates();
      publish();
    })
    .catch((error) => {
      console.error(error);
      if (SMOKE && smokeReport)
        fs.writeFileSync(
          smokeReport,
          JSON.stringify({ ok: false, error: String(error.message) }),
        );
      if (!SMOKE)
        dialog.showErrorBox("QuotaView Windows", String(error.message));
      app.exit(1);
    });
}
