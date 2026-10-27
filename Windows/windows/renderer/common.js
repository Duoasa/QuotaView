import { React } from "./react.js";
var PROVIDERS = ["codex", "claude", "dsh", "kimi"],
  PROVIDER_LABELS = {
    codex: "Codex",
    claude: "Claude Code",
    dsh: "DSH",
    kimi: "Kimi Code",
  },
  DEFAULT_SETTINGS = {
    language: "system",
    theme: "dark",
    material: "solid",
    effect: "quantum",
    islandWidth: 680,
    showCapsule: !0,
    privacy: !1,
    autoExpand: !0,
    alwaysOnTop: !0,
    startAtLogin: !1,
    display: "active",
    refreshSeconds: 60,
    notifications: !0,
    autoCheckUpdates: !1,
    reduceMotion: !1,
    showTokens: !0,
    showCost: !0,
    showActivity: !0,    collapseDelaySeconds: 15,
    lowQuotaNotifications: !0,
    completionNotifications: !0,
    tokenActivityRange: "month",
    showRemainingQuota: !0,
    showResetCountdown: !0,
    showUsageSummary: !0,
    showSparkQuota: !0,
    showCreditBalance: !0,
    showDailyTokens: !0,
    showThirtyDayTokens: !0,
    showLifetimeTokens: !0,    providers: { codex: !0, claude: !1, dsh: !1, kimi: !1 },
    codexActivityHooks: !1,
    codexHookScope: "all",
    codexPath: "",
    codexHome: "",
    claudeHome: "",
    dshRoots: [],
    proxy: { mode: "system", url: "" },
  };
function normalizeSnapshot(t) {
  let e = t && typeof t == "object" ? t : {};
  return {
    ui: e.ui || {},
    locale: e.locale,
    platform: e.platform,
    warning: e.warning,
    backgroundTasks: Array.isArray(e.backgroundTasks) ? e.backgroundTasks : [],
    tasks: Array.isArray(e.tasks) ? e.tasks.filter((a) => a && a.id) : [],
    quotas: e.quotas || {},
    usage: e.usage || {},
    providers: e.providers || {},
    displays: Array.isArray(e.displays) ? e.displays : [],
    version: e.version || null,
    update: e.update || null,
    settings: {
      ...DEFAULT_SETTINGS,
      ...e.settings,
      theme: "dark",
      material: "solid",
      providers: { ...DEFAULT_SETTINGS.providers, ...e.settings?.providers },
    },
  };
}
function isFiniteNumber(t) {
  return typeof t == "number" && Number.isFinite(t);
}
function formatNumber(t, e, a = !1) {
  return isFiniteNumber(t)
    ? new Intl.NumberFormat(e, {
        notation: a ? "compact" : "standard",
        maximumFractionDigits: a ? 1 : 0,
      }).format(t)
    : "\u2014";
}
function formatCurrency(t, e) {
  return isFiniteNumber(t)
    ? new Intl.NumberFormat(e, {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: t < 0.01 && t > 0 ? 4 : 2,
      }).format(t)
    : "\u2014";
}
function remainingQuota(t) {
  return isFiniteNumber(t?.usedPercent) &&
    t.usedPercent >= 0 &&
    t.usedPercent <= 100
    ? 100 - t.usedPercent
    : null;
}
function taskProgress(t) {
  return window.QVTaskState.presentationProgress(t);
}
function sumKnown(t, e) {
  let a = t.map((l) => l?.[e]);
  return a.length && a.every(isFiniteNumber)
    ? a.reduce((l, n) => l + n, 0)
    : null;
}
function formatDuration(t, e) {
  return !isFiniteNumber(t) || t < 0
    ? "\u2014"
    : t < 6e4
      ? e("\u5C11\u4E8E 1 \u5206\u949F", "<1m")
      : t < 36e5
        ? e(`${Math.floor(t / 6e4)} \u5206\u949F`, `${Math.floor(t / 6e4)}m`)
        : t < 864e5
          ? e(
              `${Math.floor(t / 36e5)} \u5C0F\u65F6 ${Math.floor((t % 36e5) / 6e4)} \u5206\u949F`,
              `${Math.floor(t / 36e5)}h ${Math.floor((t % 36e5) / 6e4)}m`,
            )
          : e(`${Math.floor(t / 864e5)} \u5929`, `${Math.floor(t / 864e5)}d`);
}
function formatCountdown(t, e, a) {
  return isFiniteNumber(t)
    ? t <= e
      ? a("\u5F85\u5237\u65B0", "Due for refresh")
      : formatDuration(t - e, a)
    : "\u2014";
}
function plainText(t) {
  if (typeof t == "string") return t;
  if (t == null) return "";
  try {
    return JSON.stringify(t, null, 2);
  } catch {
    return String(t);
  }
}
function safeLinkURL(t) {
  try {
    let e = new URL(t);
    return e.protocol === "https:" ? e.href : null;
  } catch {
    return null;
  }
}
function quotaWindows(t) {
  return Array.isArray(t?.windows) ? t.windows : [];
}
function statusLabel(t, e) {
  let a = {
    thinking: ["\u601D\u8003\u4E2D", "Thinking"],
    working: ["\u5DE5\u4F5C\u4E2D", "Working"],
    waiting: ["\u5F85\u786E\u8BA4", "Needs confirmation"],
    completed: ["\u5DF2\u5B8C\u6210", "Completed"],
    failed: ["\u6267\u884C\u5931\u8D25", "Failed"],
    interrupted: ["\u5DF2\u4E2D\u65AD", "Interrupted"],
    compacting: ["\u538B\u7F29\u4E0A\u4E0B\u6587", "Compacting context"],
    unknown: ["\u72B6\u6001\u672A\u77E5", "Unknown status"],
  };
  return e(...(a[t] || a.unknown));
}
function taskLabel(t, e) {
  if (!t) return e("\u989D\u5EA6", "Quota");
  let a = /spark/i.test([t.limitId, t.label, t.name].filter(Boolean).join(" "))
    ? "Spark \xB7 "
    : "";
  return t.windowMinutes === 300
    ? a + e("5 \u5C0F\u65F6", "5 hours")
    : t.windowMinutes === 10080
      ? a + e("\u5468\u989D\u5EA6", "Weekly")
      : t.windowMinutes === 1440
        ? a + e("\u6BCF\u65E5", "Daily")
        : isFiniteNumber(t.windowMinutes)
          ? a +
            (t.windowMinutes % 60 === 0
              ? e(
                  `${t.windowMinutes / 60} \u5C0F\u65F6`,
                  `${t.windowMinutes / 60} hours`,
                )
              : e(
                  `${t.windowMinutes} \u5206\u949F`,
                  `${t.windowMinutes} minutes`,
                ))
          : a +
            (t.label ||
              (t.slot === "primary"
                ? e("\u4E3B\u8981\u5468\u671F", "Primary period")
                : t.slot === "secondary"
                  ? e("\u6B21\u8981\u5468\u671F", "Secondary period")
                  : t.name) ||
              e("\u989D\u5EA6", "Quota"));
}
function creditValue(t) {
  return isFiniteNumber(t)
    ? t
    : typeof t == "string" &&
        /^\d+(?:\.\d+)?$/.test(t) &&
        Number.isFinite(Number(t))
      ? Number(t)
      : null;
}
function dayKey(t) {
  let e = new Date(t);
  return `${e.getFullYear()}-${String(e.getMonth() + 1).padStart(2, "0")}-${String(e.getDate()).padStart(2, "0")}`;
}
function filterDays(t, e, a = Date.now()) {
  let l = new Date(a);
  l.setDate(l.getDate() - e + 1);
  let n = dayKey(l.getTime()),
    i = dayKey(a);
  return (Array.isArray(t) ? [...t] : [])
    .filter((u) => u && typeof u.date == "string" && u.date >= n && u.date <= i)
    .sort((u, o) => u.date.localeCompare(o.date));
}
var AppContext = React.createContext(null),
  useApp = () => React.useContext(AppContext),
  co;
function observeVisibility(t) {
  return !t || typeof IntersectionObserver > "u"
    ? () => {}
    : (co ||
        (co = new IntersectionObserver(
          (e) => {
            for (let a of e)
              a.target.classList.toggle("effects-paused", !a.isIntersecting);
          },
          { threshold: 0.01 },
        )),
      co.observe(t),
      () => co.unobserve(t));
}
function Icon({ name: t, size: e = 16, className: a = "", ...l }) {
  let n = {
    settings: React.createElement(
      React.Fragment,
      null,
      React.createElement("circle", { cx: "12", cy: "12", r: "3" }),
      React.createElement("path", {
        d: "m9 3 .7-1h4.6l.7 3 2 1 3-.6 2.3 4-.9 2.6v2l.9 2.6-2.3 4-3-.6-2 1-.7 3H9.7l-.7-3-2-1-3 .6-2.3-4 .9-2.6v-2L1.7 9l2.3-4 3 .6 2-1Z",
        transform: "translate(1 0) scale(.9)",
      }),
    ),
    island: React.createElement(
      React.Fragment,
      null,
      React.createElement("rect", {
        x: "3",
        y: "5",
        width: "18",
        height: "14",
        rx: "5",
      }),
      React.createElement("path", {
        d: "m12 8 .7 2.3L15 11l-2.3.7L12 14l-.7-2.3L9 11l2.3-.7Z",
      }),
    ),
    chart: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M3 3v18h18M7 16v-4m5 4V7m5 9V4",
      }),
    ),
    connections: React.createElement(
      React.Fragment,
      null,
      React.createElement("circle", { cx: "12", cy: "4", r: "2.5" }),
      React.createElement("circle", { cx: "4", cy: "18", r: "2.5" }),
      React.createElement("circle", { cx: "20", cy: "18", r: "2.5" }),
      React.createElement("path", {
        d: "m10.6 6.2-5.2 9.6m8-9.6 5.2 9.6M7 18h10",
      }),
    ),
    globe: React.createElement(
      React.Fragment,
      null,
      React.createElement("circle", { cx: "12", cy: "12", r: "9" }),
      React.createElement("ellipse", {
        cx: "12",
        cy: "12",
        rx: "4",
        ry: "9",
      }),
      React.createElement("path", { d: "M3 12h18M5 7h14M5 17h14" }),
    ),
    bug: React.createElement(
      React.Fragment,
      null,
      React.createElement("rect", {
        x: "7",
        y: "7",
        width: "10",
        height: "13",
        rx: "5",
      }),
      React.createElement("path", {
        d: "m8 7-2-3m10 3 2-3M3 10h4m10 0h4M3 15h4m10 0h4M4 20l4-2m8 0 4 2M12 8v12",
      }),
    ),
    info: React.createElement(
      React.Fragment,
      null,
      React.createElement("circle", { cx: "12", cy: "12", r: "9" }),
      React.createElement("path", { d: "M12 11v6M12 7h.01" }),
    ),
    back: React.createElement("path", { d: "m14 6-6 6 6 6" }),
    up: React.createElement("path", { d: "m6 15 6-6 6 6" }),
    down: React.createElement("path", { d: "m6 9 6 6 6-6" }),
    right: React.createElement("path", { d: "m9 6 6 6-6 6" }),
    refresh: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M20 11a8 8 0 1 0-2 6M20 4v7h-7",
      }),
    ),
    pin: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "m8 3 8 0-1 6 4 4v2H5v-2l4-4ZM12 15v7",
      }),
    ),
    check: React.createElement("path", { d: "m5 12 4 4L19 6" }),
    close: React.createElement("path", { d: "m6 6 12 12M18 6 6 18" }),
    minus: React.createElement("path", { d: "M5 12h14" }),
    external: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M14 3h7v7m0-7L10 14M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5",
      }),
    ),
    shield: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "m12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6Z",
      }),
      React.createElement("path", { d: "m8 12 3 3 5-6" }),
    ),
    eye: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M2 12S6 5 12 5s10 7 10 7-4 7-10 7S2 12 2 12Z",
      }),
      React.createElement("circle", { cx: "12", cy: "12", r: "3" }),
    ),
    eyeOff: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M3 3 21 21M9 5a13 13 0 0 1 13 7s-1 2-4 4M6 6a22 22 0 0 0-4 6s4 7 10 7c2 0 3-.4 4-1M10 10a3 3 0 0 0 4 4",
      }),
    ),
    bell: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M5 17h14l-2-3V9a5 5 0 0 0-10 0v5ZM10 21h4",
      }),
    ),
    monitor: React.createElement(
      React.Fragment,
      null,
      React.createElement("rect", {
        x: "2",
        y: "3",
        width: "20",
        height: "14",
        rx: "2",
      }),
      React.createElement("path", { d: "M12 17v4M8 21h8" }),
    ),
    folder: React.createElement("path", { d: "M3 5h6l2 3h10v12H3Z" }),
    terminal: React.createElement(
      React.Fragment,
      null,
      React.createElement("rect", {
        x: "2",
        y: "4",
        width: "20",
        height: "16",
        rx: "3",
      }),
      React.createElement("path", { d: "m6 9 3 3-3 3m7 0h4" }),
    ),
    clock: React.createElement(
      React.Fragment,
      null,
      React.createElement("circle", { cx: "12", cy: "12", r: "9" }),
      React.createElement("path", { d: "M12 6v6l4 3" }),
    ),
    warning: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "m12 3 10 18H2ZM12 9v5M12 17h.01",
      }),
    ),
    copy: React.createElement(
      React.Fragment,
      null,
      React.createElement("rect", {
        x: "8",
        y: "8",
        width: "12",
        height: "13",
        rx: "2",
      }),
      React.createElement("path", { d: "M16 8V3H3v13h5" }),
    ),
    power: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", { d: "M12 2v10M7 5a8 8 0 1 0 10 0" }),
    ),
    moon: React.createElement("path", {
      d: "M20 15A9 9 0 0 1 9 4a9 9 0 1 0 11 11Z",
    }),
    sun: React.createElement(
      React.Fragment,
      null,
      React.createElement("circle", { cx: "12", cy: "12", r: "4" }),
      React.createElement("path", {
        d: "M12 1v2m0 18v2M1 12h2m18 0h2M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2",
      }),
    ),
    download: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M12 3v12m-5-5 5 5 5-5M3 16v5h18v-5",
      }),
    ),
    file: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "M5 2h9l5 5v15H5ZM14 2v6h5M8 12h8M8 16h8",
      }),
    ),
    sparkles: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", {
        d: "m12 3 2 6 6 3-6 2-2 7-2-7-7-2 7-3ZM20 2v4m-2-2h4",
      }),
    ),
    pause: React.createElement(
      React.Fragment,
      null,
      React.createElement("path", { d: "M8 5v14M16 5v14" }),
    ),
  };
  return React.createElement(
    "svg",
    {
      className: `icon ${a}`,
      width: e,
      height: e,
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      strokeWidth: "1.7",
      strokeLinecap: "round",
      strokeLinejoin: "round",
      "aria-hidden": "true",
      ...l,
    },
    n[t] || n.info,
  );
}
function ProviderIcon({ provider: t = "codex", size: e = 18 }) {
  return React.createElement("img", {
    className: `provider-icon provider-${t}`,
    src: `../assets/providers/${t === "kimi" ? "kimi.png" : `${["codex", "claude", "dsh"].includes(t) ? t : "codex"}.svg`}`,
    width: e,
    height: e,
    alt: "",
  });
}
function IconButton({ icon: t, label: e, active: a, className: l = "", ...n }) {
  return React.createElement(
    "button",
    {
      className: `icon-button ${a ? "active" : ""} ${l}`,
      type: "button",
      "aria-label": e,
      title: e,
      ...n,
    },
    React.createElement(Icon, { name: t }),
  );
}
function Toggle({ checked: t, onChange: e, label: a, disabled: l = !1 }) {
  return React.createElement(
    "button",
    {
      type: "button",
      role: "switch",
      "aria-checked": !!t,
      "aria-label": a,
      className: `toggle ${t ? "on" : ""}`,
      disabled: l,
      onClick: () => e(!t),
    },
    React.createElement("span", null),
  );
}
function SettingRow({
  title: t,
  description: e,
  icon: a,
  children: l,
  className: n = "",
}) {
  return React.createElement(
    "div",
    { className: `setting-row ${n}` },
    a &&
      React.createElement(
        "span",
        { className: "row-icon" },
        React.createElement(Icon, { name: a }),
      ),
    React.createElement(
      "div",
      { className: "setting-copy" },
      React.createElement("div", { className: "setting-label" }, t),
      e && React.createElement("p", null, e),
    ),
    React.createElement("div", { className: "setting-control" }, l),
  );
}
function SettingGroup({ title: t, children: e, note: a, className: l = "" }) {
  return React.createElement(
    "section",
    { className: `settings-group ${l}` },
    t && React.createElement("h2", null, t),
    React.createElement("div", { className: "group-box" }, e),
    a && React.createElement("p", { className: "group-note" }, a),
  );
}
function SegmentedControl({
  options: t,
  value: e,
  onChange: a,
  label: l,
  disabled: n,
}) {
  return React.createElement(
    "div",
    { className: "segmented", role: "group", "aria-label": l },
    t.map(([i, u]) =>
      React.createElement(
        "button",
        {
          type: "button",
          disabled: n,
          className: e === i ? "selected" : "",
          "aria-pressed": e === i,
          key: i,
          onClick: () => a(i),
        },
        u,
      ),
    ),
  );
}
function Select({ options: t, value: e, onChange: a, label: l, disabled: n }) {
  return React.createElement(
    "select",
    {
      "aria-label": l,
      value: e ?? "",
      disabled: n,
      onChange: (i) => a(i.target.value),
    },
    t.map(([i, u]) => React.createElement("option", { key: i, value: i }, u)),
  );
}
function Notice({
  children: t,
  tone: e = "info",
  icon: a = e === "warning" ? "warning" : "info",
}) {
  return React.createElement(
    "div",
    { className: `notice ${e}` },
    React.createElement(Icon, { name: a }),
    React.createElement("div", null, t),
  );
}
function EmptyState({ icon: t = "island", title: e, children: a, action: l }) {
  return React.createElement(
    "div",
    { className: "empty-state" },
    React.createElement(
      "span",
      { className: "empty-icon" },
      React.createElement(Icon, { name: t, size: 28 }),
    ),
    React.createElement("h3", null, e),
    React.createElement("p", null, a),
    l,
  );
}
function QuotaRing({ value: t, size: e = 14 }) {
  let a = typeof t == "number" && Number.isFinite(t);
  return React.createElement(
    "svg",
    {
      width: e,
      height: e,
      viewBox: "0 0 20 20",
      className: `quota-ring ${a ? (t <= 10 ? "danger" : t <= 30 ? "warning" : "healthy") : "unknown"}`,
      "aria-hidden": "true",
    },
    React.createElement("circle", {
      cx: "10",
      cy: "10",
      r: "7.5",
      className: "ring-track",
    }),
    a &&
      React.createElement("circle", {
        cx: "10",
        cy: "10",
        r: "7.5",
        pathLength: "100",
        strokeDasharray: `${Math.max(0, Math.min(100, t))} 100`,
        className: "ring-fill",
      }),
  );
}
function ConnectionDot({ provider: t, connected: e }) {
  return React.createElement(
    "span",
    { className: "provider-badge" },
    React.createElement(ProviderIcon, { provider: t, size: 14 }),
    PROVIDER_LABELS[t] || t,
    typeof e == "boolean" &&
      React.createElement("i", {
        className: `connection-dot ${e ? "connected" : ""}`,
      }),
  );
}
function Metric({
  label: t,
  value: e,
  onChange: a,
  placeholder: l,
  multiline: n = !1,
  disabled: i,
}) {
  let u = React.useId();
  return React.createElement(
    "label",
    { className: "field", htmlFor: u },
    React.createElement("span", null, t),
    n
      ? React.createElement("textarea", {
          id: u,
          value: e || "",
          onChange: (o) => a(o.target.value),
          placeholder: l,
          disabled: i,
        })
      : React.createElement("input", {
          id: u,
          value: e || "",
          onChange: (o) => a(o.target.value),
          placeholder: l,
          disabled: i,
          spellCheck: "false",
        }),
  );
}
function ExternalLink({ href: t, children: e, className: a = "" }) {
  let { invoke: l } = useApp(),
    n = safeLinkURL(t);
  return n
    ? React.createElement(
        "a",
        {
          className: a,
          href: n,
          onClick: (i) => {
            (i.preventDefault(), l("openExternal", n));
          },
        },
        e,
      )
    : React.createElement("span", null, e);
}
function ConfirmationDialog({
  title: t,
  children: e,
  confirmLabel: a,
  onConfirm: l,
  onClose: n,
  danger: i = !1,
  disabled: u = !1,
}) {
  let { t: o } = useApp(),
    c = React.useRef(null);
  return (
    React.useEffect(() => {
      let r = document.activeElement,
        g = c.current,
        m = (f) => {
          if (
            (f.key === "Escape" && (f.preventDefault(), n()), f.key !== "Tab")
          )
            return;
          let p = [
            ...g.querySelectorAll(
              "button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),a[href]",
            ),
          ];
          if (!p.length) {
            f.preventDefault();
            return;
          }
          let w = p[0],
            N = p.at(-1);
          f.shiftKey && document.activeElement === w
            ? (f.preventDefault(), N.focus())
            : !f.shiftKey &&
              document.activeElement === N &&
              (f.preventDefault(), w.focus());
        };
      return (
        g?.addEventListener("keydown", m),
        () => {
          (g?.removeEventListener("keydown", m), r?.focus?.());
        }
      );
    }, [n]),
    React.createElement(
      "div",
      {
        className: "modal-backdrop",
        onMouseDown: (r) => {
          r.target === r.currentTarget && n();
        },
      },
      React.createElement(
        "section",
        {
          ref: c,
          className: "dialog",
          role: "alertdialog",
          "aria-modal": "true",
          "aria-label": t,
        },
        React.createElement("h2", null, t),
        React.createElement("div", { className: "dialog-body" }, e),
        React.createElement(
          "div",
          { className: "dialog-actions" },
          React.createElement(
            "button",
            { autoFocus: !0, onClick: n },
            o("\u53D6\u6D88", "Cancel"),
          ),
          React.createElement(
            "button",
            {
              className: i ? "danger-button" : "primary-button",
              disabled: u,
              onClick: l,
            },
            a,
          ),
        ),
      ),
    )
  );
}
function Markdown({ text: t }) {
  let e = String(t || "").replace(
      /\r\n/g,
      `
`,
    ).split(`
`),
    a = [];
  function l(n, i) {
    return n
      .split(/(`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\(https:\/\/[^\s)]+\))/g)
      .map((o, c) => {
        if (o.startsWith("`") && o.endsWith("`"))
          return React.createElement(
            "code",
            { key: `${i}-${c}` },
            o.slice(1, -1),
          );
        if (o.startsWith("**") && o.endsWith("**"))
          return React.createElement(
            "strong",
            { key: `${i}-${c}` },
            o.slice(2, -2),
          );
        let r = /^\[([^\]]+)\]\((https:\/\/[^\s)]+)\)$/.exec(o);
        return r
          ? React.createElement(
              ExternalLink,
              { key: `${i}-${c}`, href: r[2] },
              r[1],
            )
          : o;
      });
  }
  for (let n = 0; n < e.length; n++) {
    let i = e[n];
    if (/^\s*```/.test(i)) {
      let u = [],
        o = n,
        c = i.replace(/^\s*```/, "").trim();
      for (; ++n < e.length && !/^\s*```/.test(e[n]);) u.push(e[n]);
      a.push(
        React.createElement(
          "div",
          { className: "code-block", key: o },
          c && React.createElement("div", { className: "code-language" }, c),
          React.createElement(
            "pre",
            null,
            React.createElement(
              "code",
              null,
              u.join(`
`),
            ),
          ),
        ),
      );
      continue;
    }
    if (
      i.includes("|") &&
      n + 1 < e.length &&
      /^\s*\|?\s*:?-{3,}:?\s*\|/.test(e[n + 1])
    ) {
      let u = n,
        o = (g) =>
          g
            .trim()
            .replace(/^\|/, "")
            .replace(/\|$/, "")
            .split("|")
            .map((m) => m.trim()),
        c = o(i),
        r = [];
      for (n += 2; n < e.length && e[n].includes("|") && e[n].trim();)
        (r.push(o(e[n])), n++);
      (n--,
        a.push(
          React.createElement(
            "div",
            { className: "markdown-table", key: u },
            React.createElement(
              "table",
              null,
              React.createElement(
                "thead",
                null,
                React.createElement(
                  "tr",
                  null,
                  c.map((g, m) =>
                    React.createElement("th", { key: m }, l(g, `${u}-h-${m}`)),
                  ),
                ),
              ),
              React.createElement(
                "tbody",
                null,
                r.map((g, m) =>
                  React.createElement(
                    "tr",
                    { key: m },
                    g.map((f, p) =>
                      React.createElement(
                        "td",
                        { key: p },
                        l(f, `${u}-${m}-${p}`),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
      continue;
    }
    if (/^#{1,6}\s/.test(i)) {
      let u = /^(#{1,6})\s+(.*)/.exec(i),
        o = `h${Math.min(6, u[1].length + 2)}`;
      a.push(React.createElement(o, { key: n }, l(u[2], n)));
      continue;
    }
    if (/^\s*[-*+]\s+/.test(i) || /^\s*\d+\.\s+/.test(i)) {
      let u = /^\s*\d+\./.test(i),
        o = [],
        c = n,
        r = u ? /^\s*\d+\.\s+/ : /^\s*[-*+]\s+/;
      do
        (o.push(
          React.createElement("li", { key: n }, l(e[n].replace(r, ""), n)),
        ),
          n++);
      while (n < e.length && r.test(e[n]));
      n--;
      let g = u ? "ol" : "ul";
      a.push(React.createElement(g, { key: c }, o));
      continue;
    }
    if (/^>\s?/.test(i)) {
      a.push(
        React.createElement(
          "blockquote",
          { key: n },
          l(i.replace(/^>\s?/, ""), n),
        ),
      );
      continue;
    }
    if (/^\s*([-*_])\1{2,}\s*$/.test(i)) {
      a.push(React.createElement("hr", { key: n }));
      continue;
    }
    i.trim() && a.push(React.createElement("p", { key: n }, l(i, n)));
  }
  return React.createElement("div", { className: "markdown" }, a);
}

export {
  normalizeSnapshot,
  isFiniteNumber,
  formatNumber,
  formatCurrency,
  remainingQuota,
  taskProgress,
  sumKnown,
  formatDuration,
  formatCountdown,
  plainText,
  safeLinkURL,
  quotaWindows,
  statusLabel,
  taskLabel,
  creditValue,
  dayKey,
  filterDays,
  observeVisibility,
  Icon,
  ProviderIcon,
  IconButton,
  Toggle,
  SettingRow,
  SettingGroup,
  SegmentedControl,
  Select,
  Notice,
  EmptyState,
  QuotaRing,
  ConnectionDot,
  Metric,
  ExternalLink,
  ConfirmationDialog,
  Markdown,
  PROVIDERS,
  PROVIDER_LABELS,
  DEFAULT_SETTINGS,
  AppContext,
  useApp,
};
