"use strict";
// Isolated Chromium profile, synthetic fixtures, no user accounts or agent data.
const fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path"),
  { spawn } = require("node:child_process"),
  { pathToFileURL } = require("node:url");
const browser =
  process.env.QV_CHROME ||
  (process.platform === "darwin"
    ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    : path.join(
        process.env.ProgramFiles || "C:\\Program Files",
        "Google/Chrome/Application/chrome.exe",
      ));
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "qv-renderer-"));
const child = spawn(
  browser,
  [
    "--headless=new",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-debugging-port=0",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
    "--user-data-dir=" + profile,
    "about:blank",
  ],
  { stdio: ["ignore", "ignore", "pipe"] },
);
const delay = (ms) => new Promise((r) => setTimeout(r, ms));
const timeout = setTimeout(() => {
  console.error("Renderer smoke timed out");
  child.kill();
  process.exitCode = 1;
}, 60000);
async function main() {
  const endpoint = await new Promise((resolve, reject) => {
    let log = "";
    child.on("error", reject);
    child.on("exit", (code) => reject(Error("Browser exited " + code)));
    child.stderr.on("data", (d) => {
      log += d;
      const m = log.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) resolve(new URL(m[1]));
    });
  });
  const pages = await fetch("http://" + endpoint.host + "/json/list").then(
    (r) => r.json(),
  );
  const ws = new WebSocket(
    pages.find((p) => p.type === "page").webSocketDebuggerUrl,
  );
  await new Promise((r, j) => {
    ws.onopen = r;
    ws.onerror = j;
  });
  let seq = 0;
  const pending = new Map(),
    errors = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id) {
      const p = pending.get(m.id);
      pending.delete(m.id);
      if (m.error) p.reject(Error(JSON.stringify(m.error)));
      else p.resolve(m.result);
    } else if (m.method === "Runtime.exceptionThrown")
      errors.push(
        m.params.exceptionDetails.exception?.description ||
          m.params.exceptionDetails.text,
      );
    else if (
      m.method === "Runtime.consoleAPICalled" &&
      m.params.type === "error"
    )
      errors.push(m.params.args.map((x) => x.value || x.description).join(" "));
  };
  const call = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++seq;
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });
  const evaluate = async (expression) => {
    const r = await call("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (r.exceptionDetails)
      throw Error(
        r.exceptionDetails.exception?.description || r.exceptionDetails.text,
      );
    return r.result.value;
  };
  await call("Runtime.enable");
  await call("Page.enable");
  const fixture = {
    version: "0.8.3-win.1.effects.2",
    locale: "en",
    ui: { expanded: true },
    platform: {},
    tasks: [
      {
        id: "fixture",
        provider: "codex",
        title: "Isolated renderer fixture",
        status: "working",
        verified: true,
        progress: { fraction: 0.55, completed: 1, total: 2 },
        updatedAt: Date.now(),
      },
    ],
    quotas: {},
    usage: {},
    providers: { codex: { enabled: true, connected: true } },
    settings: {
      language: "en",
      theme: "dark",
      effect: "smoke",
      reduceMotion: true,
      providers: { codex: true },
    },
    displays: [],
  };
  await call("Page.addScriptToEvaluateOnNewDocument", {
    source: `window.__fixture=${JSON.stringify(fixture)};window.quotaView=new Proxy({snapshot:async()=>window.__fixture,subscribe:fn=>{window.__notify=fn;return()=>{};},updateSettings:async patch=>{window.__fixture.settings={...window.__fixture.settings,...patch};window.__notify?.(window.__fixture);return window.__fixture.settings;}},{get:(t,k)=>t[k]||(()=>Promise.resolve({}))});`,
  });
  const url = pathToFileURL(
    path.resolve(__dirname, "../dist/renderer/index.html"),
  ).href;
  const reports = [];
  for (const view of ["island", "capsule", "settings"]) {
    await call("Page.navigate", {
      url: url + "?view=" + view + "&effectsSmoke=1",
    });
    let mounted = false;
    for (let i = 0; i < 60; i++) {
      await delay(100);
      mounted = await evaluate(`!!document.querySelector('#root .app')`);
      if (mounted) break;
    }
    if (!mounted)
      throw Error(
        view +
          " did not mount: " +
          errors.join("; ") +
          " " +
          (await evaluate(`document.body.innerText`)),
      );
    if (view === "island") {
      const progress = await evaluate(
        `document.querySelector('.task-card')?.style.getPropertyValue('--progress')`,
      );
      if (progress !== "55.00000000000001%" && progress !== "55%")
        throw Error("Canonical progress missing: " + progress);
      reports.push(await evaluate("window.QVEffects.selfTest()"));
    }
    if (view === "settings") {
      const pages = await evaluate(
        `Array.from(document.querySelectorAll('[data-page]')).map(n=>n.dataset.page)`,
      );
      for (const page of pages) {
        await evaluate(
          `document.querySelector('[data-page="${page}"]').click()`,
        );
        await delay(80);
        if (await evaluate(`!!document.querySelector('.fatal-error')`))
          throw Error("Settings page failed: " + page);
      }
      if (pages.some((p) => /reset|widget/i.test(p)))
        throw Error("Removed feature still has navigation");
      await evaluate(`document.querySelector('[data-page="island"]').click()`);
      await delay(100);
      if (
        (await evaluate(
          `document.querySelectorAll('.effect-sample canvas').length`,
        )) !== 3
      )
        throw Error("Live effect previews missing");
      await evaluate(`document.querySelectorAll('.effect-choice')[2].click()`);
      await delay(100);
      if ((await evaluate(`window.__fixture.settings.effect`)) !== "wave")
        throw Error("Effect selection did not persist");
      await evaluate(
        `window.quotaView.updateSettings({theme:'light',reduceMotion:true})`,
      );
      await delay(100);
      if (
        !(await evaluate(
          `!!document.querySelector('.theme-light.reduce-motion')`,
        ))
      )
        throw Error("Theme/motion setting did not apply");
      const live = await evaluate(`window.QVEffects.diagnostics().entries`);
      await evaluate(`document.querySelector('[data-page="about"]').click()`);
      await delay(100);
      if ((await evaluate(`window.QVEffects.diagnostics().entries`)) >= live)
        throw Error("Hidden settings preview leaked registrations");
      reports.push({
        settingsPages: pages,
        liveEffectPreviews: 3,
        settingsUpdates: true,
        previewTeardown: true,
      });
    }
    if (await evaluate(`!!document.querySelector('.fatal-error')`))
      throw Error(view + " error boundary");
  }
  if (errors.length) throw Error(errors.join("\n"));
  console.log(
    JSON.stringify(
      { ok: true, views: ["island", "capsule", "settings"], reports },
      null,
      2,
    ),
  );
  ws.close();
}
main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(async () => {
    clearTimeout(timeout);
    child.kill();
    await delay(500);
    fs.rmSync(profile, {
      recursive: true,
      force: true,
      maxRetries: 15,
      retryDelay: 200,
    });
  });
