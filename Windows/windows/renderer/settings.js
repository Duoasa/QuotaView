import { React } from "./react.js";
import {
  Icon,
  ProviderIcon,
  Toggle,
  SettingRow,
  SettingGroup,
  SegmentedControl,
  Select,
  Notice,
  Metric,
  ConfirmationDialog,
  PROVIDERS,
  PROVIDER_LABELS,
  useApp,
} from "./common.js";
import { QuotaCapsule, UsageView } from "./usage.js";
import { TaskCard } from "./tasks.js";
const h = React.createElement;
var settingPages = [
  ["general", "settings", "\u901A\u7528", "General", "#4e9ef8"],
  ["island", "island", "\u7075\u52A8\u5C9B", "Island", "#ba6bf2"],
  ["usage", "chart", "\u7528\u91CF\u663E\u793A", "Usage display", "#f06083"],
  ["connections", "connections", "\u8FDE\u63A5", "Connections", "#57cbe6"],
  ["proxy", "globe", "\u7F51\u7EDC\u4EE3\u7406", "Network proxy", "#53c4c4"],
  ["feedback", "bug", "Bug \u53CD\u9988", "Bug feedback", "#eea650"],
  ["about", "info", "\u5173\u4E8E", "About", "#8c87f9"],
];
function SettingToggle({
  name: t,
  title: e,
  description: a,
  icon: l,
  disabled: n,
}) {
  let { snapshot: i, setSetting: u, busy: o } = useApp();
  return React.createElement(
    SettingRow,
    { title: e, description: a, icon: l },
    React.createElement(Toggle, {
      label: e,
      checked: i.settings[t],
      disabled: n || o.updateSettings,
      onChange: (c) => u(t, c),
    }),
  );
}
function GeneralSettings() {
  const { snapshot, t, setSetting, invoke } = useApp();
  const [confirmQuit, setConfirmQuit] = React.useState(false);
  const settings = snapshot.settings;
  const displays = [
    ["primary", t("主显示器", "Primary display")],
    ...snapshot.displays.map((display, index) => [
      String(display.id),
      display.label ||
        display.name ||
        t("显示器 " + (index + 1), "Display " + (index + 1)),
    ]),
  ];
  if (
    settings.display !== "active" &&
    !displays.some(([id]) => id === settings.display)
  )
    displays.push([
      settings.display,
      t("所选显示器未连接", "Selected display is disconnected"),
    ]);
  return h(
    React.Fragment,
    null,
    h(
      SettingGroup,
      { title: t("语言", "Language") },
      h(
        SettingRow,
        { title: t("应用语言", "App language"), icon: "globe" },
        h(Select, {
          label: t("应用语言", "App language"),
          value: settings.language,
          onChange: (value) => setSetting("language", value),
          options: [
            ["system", t("跟随系统", "System")],
            ["zh", "简体中文"],
            ["en", "English"],
          ],
        }),
      ),
    ),
    h(
      SettingGroup,
      { title: t("灵动岛显示位置", "Island display") },
      h(
        SettingRow,
        {
          title: t("焦点屏幕跟随", "Follow focused display"),
          description: t(
            "跟随当前活动窗口所在的屏幕。",
            "Follow the display containing the active window.",
          ),
          icon: "monitor",
        },
        h(Toggle, {
          label: t("焦点屏幕跟随", "Follow focused display"),
          checked: settings.display === "active",
          onChange: (value) =>
            setSetting("display", value ? "active" : "primary"),
        }),
      ),
      settings.display !== "active" &&
        h(
          SettingRow,
          {
            title: t("固定屏幕", "Fixed display"),
            description: t(
              "断开时暂回主屏，重新连接后恢复。",
              "Falls back to the primary display until reconnected.",
            ),
          },
          h(Select, {
            label: t("固定屏幕", "Fixed display"),
            value: settings.display,
            onChange: (value) => setSetting("display", value),
            options: displays,
          }),
        ),
    ),
    h(
      "button",
      { className: "quit-row", onClick: () => setConfirmQuit(true) },
      h(Icon, { name: "power" }),
      t("退出 QuotaView", "Quit QuotaView"),
    ),
    confirmQuit &&
      h(
        ConfirmationDialog,
        {
          title: t("退出 QuotaView？", "Quit QuotaView?"),
          confirmLabel: t("退出", "Quit"),
          danger: true,
          onClose: () => setConfirmQuit(false),
          onConfirm: () => invoke("quit"),
        },
        t("Agent 任务会继续运行。", "Agent tasks will keep running."),
      ),
  );
}
function IslandPreview() {
  let { t, snapshot: e } = useApp(),
    a = e.tasks.find((l) => !l.parentId);
  return React.createElement(
    "div",
    { className: `island-preview material-${e.settings.material}` },
    React.createElement(
      "div",
      {
        className: "preview-shell",
      },
      React.createElement(
        "div",
        { className: "preview-toolbar" },
        React.createElement(QuotaCapsule, { compact: !0 }),
        React.createElement(
          "div",
          null,
          React.createElement(Icon, { name: "pin", size: 11 }),
          React.createElement(Icon, { name: "up", size: 11 }),
        ),
      ),
      a
        ? React.createElement(TaskCard, {
            task: a,
            focused: true,
            onSelect: () => {},
          })
        : React.createElement(
            "div",
            { className: "preview-empty-task" },
            React.createElement("span", {
              className: `preview-ambient effect-${e.settings.effect}`,
            }),
            React.createElement(
              "div",
              null,
              React.createElement(
                "strong",
                null,
                t(
                  "\u7B49\u5F85\u771F\u5B9E\u4EFB\u52A1",
                  "Waiting for a real task",
                ),
              ),
              React.createElement(
                "span",
                null,
                t(
                  "\u65E0\u6A21\u62DF\u4EFB\u52A1 \xB7 \u65E0\u865A\u6784\u989D\u5EA6",
                  "No simulated tasks or invented quota",
                ),
              ),
            ),
          ),
      React.createElement(
        "div",
        { className: "preview-footer" },
        React.createElement(
          "span",
          null,
          t(
            `${e.tasks.length} \u4E2A\u4F1A\u8BDD`,
            `${e.tasks.length} sessions`,
          ),
        ),
        React.createElement(
          "div",
          null,
          React.createElement(Icon, { name: "refresh", size: 11 }),
          React.createElement(Icon, { name: "settings", size: 11 }),
        ),
      ),
    ),
    e.settings.showCapsule &&
      React.createElement(
        "div",
        { className: "preview-capsule" },
        React.createElement(QuotaCapsule, null),
      ),
  );
}
function IslandSettings() {
  const { t, snapshot, setSetting } = useApp();
  const settings = snapshot.settings;
  return h(
    React.Fragment,
    null,
    h(IslandPreview),
    h(
      SettingGroup,
      { title: t("外观与布局", "Appearance and layout") },
      h(
        "div",
        { className: "slider-setting" },
        h(
          "div",
          null,
          h(
            "label",
            { htmlFor: "island-width" },
            t("展开宽度", "Expanded width"),
          ),
          h("span", null, settings.islandWidth + " px"),
        ),
        h("input", {
          id: "island-width",
          type: "range",
          min: 520,
          max: 800,
          step: 8,
          value: settings.islandWidth,
          onChange: (event) =>
            setSetting("islandWidth", Number(event.target.value)),
        }),
      ),
    ),
    h(
      SettingGroup,
      { title: t("显示内容", "Content") },
      h(SettingToggle, {
        name: "showCapsule",
        title: t("悬浮用量胶囊", "Floating usage capsule"),
        description: t(
          "显示剩余额度与重置倒计时，宽度随周期数量自适应。",
          "Show remaining quota and reset countdown; width adapts to available periods.",
        ),
        icon: "chart",
      }),
      h(SettingToggle, {
        name: "privacy",
        title: t("隐私模式", "Privacy mode"),
        description: t(
          "隐藏任务内容和账户数据。",
          "Hide task contents and account data.",
        ),
        icon: "eyeOff",
      }),
    ),
    h(
      SettingGroup,
      { title: t("自动展开", "Automatic opening") },
      h(SettingToggle, {
        name: "autoExpand",
        title: t("自动弹出", "Automatic popups"),
        description: t(
          "新任务、完成或待确认时弹出。",
          "Open for new tasks, completions and requests.",
        ),
        icon: "island",
      }),
      h(
        SettingRow,
        {
          title: t("停留时间", "Stay open for"),
          description: t(
            "待确认、悬停或固定时保持展开。",
            "Stay open for pending requests, hover or when pinned.",
          ),
        },
        h(Select, {
          label: t("停留时间", "Stay open for"),
          value: String(settings.collapseDelaySeconds),
          disabled: !settings.autoExpand,
          onChange: (value) =>
            setSetting("collapseDelaySeconds", Number(value)),
          options: [5, 8, 12, 15, 20, 30, 60].map((value) => [
            String(value),
            t(value + " 秒", value + " s"),
          ]),
        }),
      ),
    ),
  );
}
function UsageSettings() {
  const { t } = useApp();
  return h(
    SettingGroup,
    {
      title: t("可选模块", "Optional modules"),
      note: t(
        "额度、Token 统计与账户信息始终显示；关闭的模块不占位。",
        "Quota, token totals and account details are always shown; hidden modules leave no gap.",
      ),
    },
    h(SettingToggle, {
      name: "showCost",
      title: t("成本估算", "Cost estimate"),
      description: t(
        "最近 30 天的估算成本。",
        "Estimated costs for the last 30 days.",
      ),
      icon: "chart",
    }),
    h(SettingToggle, {
      name: "showActivity",
      title: t("Token 活动", "Token activity"),
      description: t(
        "每日、每周和累计用量。",
        "Daily, weekly and cumulative usage.",
      ),
      icon: "chart",
    }),
  );
}

function CodexSettings() {
  let { t, snapshot: e, invoke: a, busy: l } = useApp(),
    [n, i] = React.useState(null),
    [u, o] = React.useState(!1),
    [c, r] = React.useState(e.settings.codexHookScope || "all"),
    [g, m] = React.useState(!1);
  async function f() {
    let N = await a("inspectCodexHooks");
    N && (i(N), m(!1));
  }
  async function p() {
    (await a("configure", {
      provider: "codex",
      enabled: !0,
      options: { activityHooks: !0, scope: c, enableFeature: g },
    })) !== null && o(!1);
  }
  let w = e.providers.codex?.hooks;
  return React.createElement(
    "div",
    { className: "hook-settings" },
    React.createElement(
      "h4",
      null,
      t("\u53EF\u9009\u4EFB\u52A1\u4E8B\u4EF6 Hook", "Optional activity Hooks"),
    ),
    React.createElement(
      Notice,
      null,
      t(
        "\u81EA\u52A8\u8BFB\u53D6\u4F1A\u8BDD\u8BB0\u5F55\u65E0\u9700 Hook\u3002\u6B64\u589E\u5F3A\u529F\u80FD\u8865\u5145\u5B9E\u65F6\u4EFB\u52A1\u548C\u4E0A\u4E0B\u6587\u538B\u7F29\u4E8B\u4EF6\uFF0C\u4E0D\u6388\u4E88 Codex Desktop \u5BA1\u6279\u6743\u9650\u3002",
        "Automatic session reading works without Hooks. This enhancement adds live task and compaction events, not Codex Desktop approval authority.",
      ),
    ),
    React.createElement(
      SettingRow,
      {
        title: t(
          "\u4EFB\u52A1\u4E8B\u4EF6\u8FDE\u63A5",
          "Activity event connection",
        ),
        description:
          w?.error ||
          (w?.connected
            ? t("\u5DF2\u63A5\u6536 Hook \u4E8B\u4EF6", "Hook events received")
            : e.settings.codexActivityHooks
              ? t(
                  "\u5DF2\u914D\u7F6E\uFF0C\u7B49\u5F85\u4FE1\u4EFB\u6216\u65B0\u4F1A\u8BDD\u4E8B\u4EF6",
                  "Configured, awaiting trust or a new session event",
                )
              : t("\u5F53\u524D\u5173\u95ED", "Currently disabled")),
      },
      React.createElement(Toggle, {
        label: t(
          "\u542F\u7528 Codex \u4EFB\u52A1 Hook",
          "Enable Codex activity Hooks",
        ),
        checked: e.settings.codexActivityHooks,
        disabled: l.configure,
        onChange: (N) => {
          N
            ? (o(!0), f())
            : a("configure", {
                provider: "codex",
                enabled: e.settings.providers.codex,
                options: { activityHooks: !1 },
              });
        },
      }),
    ),
    React.createElement(
      "button",
      { onClick: f, disabled: l.inspectCodexHooks },
      t("\u68C0\u67E5 Hook \u652F\u6301", "Inspect Hook support"),
    ),
    n &&
      React.createElement(
        "p",
        { className: "source-note" },
        n.version,
        " \xB7 ",
        n.featureEnabled
          ? t(
              "\u5BA2\u6237\u7AEF Hook \u529F\u80FD\u5DF2\u5F00\u542F",
              "Client Hooks feature enabled",
            )
          : t(
              "\u5BA2\u6237\u7AEF Hook \u529F\u80FD\u672A\u5F00\u542F",
              "Client Hooks feature disabled",
            ),
      ),
    u &&
      React.createElement(
        ConfirmationDialog,
        {
          title: t(
            "\u914D\u7F6E Codex \u4EFB\u52A1 Hook\uFF1F",
            "Configure Codex activity Hooks?",
          ),
          confirmLabel: t("\u4FDD\u5B58\u5E76\u542F\u7528", "Save and enable"),
          onClose: () => o(!1),
          disabled: !n || (!n.featureEnabled && !g) || l.configure,
          onConfirm: p,
        },
        React.createElement(
          "p",
          null,
          t(
            "\u5C06\u5907\u4EFD\u5E76\u66F4\u65B0\u6240\u9009 Codex \u6570\u636E\u76EE\u5F55\u7684 hooks.json\uFF0C\u53EA\u7BA1\u7406 QuotaView \u81EA\u5DF1\u7684\u6761\u76EE\u3002\u65B0\u4F1A\u8BDD\u53EF\u80FD\u9700\u8981\u91CD\u542F\u5E76\u5728 Codex \u4E2D\u786E\u8BA4\u4FE1\u4EFB\u3002",
            "Back up and update hooks.json in the selected Codex directory, managing only QuotaView-owned entries. Restart the session and approve trust in Codex if needed.",
          ),
        ),
        React.createElement(Select, {
          label: t("Hook \u8303\u56F4", "Hook scope"),
          value: c,
          onChange: r,
          options: [
            [
              "all",
              t("\u5168\u90E8\u4EFB\u52A1\u4E8B\u4EF6", "All task events"),
            ],
            [
              "compaction",
              t(
                "\u4EC5\u4E0A\u4E0B\u6587\u538B\u7F29",
                "Context compaction only",
              ),
            ],
          ],
        }),
        n
          ? !n.featureEnabled &&
              React.createElement(
                "label",
                { className: "confirmation-checkbox" },
                React.createElement("input", {
                  type: "checkbox",
                  checked: g,
                  onChange: (N) => m(N.target.checked),
                }),
                React.createElement(
                  "span",
                  null,
                  t(
                    "\u540C\u65F6\u901A\u8FC7 Codex CLI \u5F00\u542F Hook \u529F\u80FD\u6807\u5FD7\u3002\u8FD9\u4F1A\u66F4\u65B0 Codex \u914D\u7F6E\uFF1B\u4E0D\u52FE\u9009\u5219\u4E0D\u66F4\u6539\u539F\u6709\u7981\u7528\u8BBE\u7F6E\u3002",
                    "Also enable the Hook feature through Codex CLI. This updates Codex configuration; leave unchecked to preserve the disabled setting.",
                  ),
                ),
              )
          : React.createElement(
              "p",
              null,
              t(
                "\u6B63\u5728\u68C0\u67E5\u529F\u80FD\u652F\u6301\uFF1B\u6210\u529F\u540E\u624D\u80FD\u542F\u7528\u3002",
                "Inspecting support. Enabling requires a successful check.",
              ),
            ),
      ),
  );
}
function IntegrationSettings({ provider: t }) {
  let { t: e, snapshot: a, invoke: l, setSetting: n, busy: i } = useApp(),
    u = a.settings,
    [o, c] = React.useState(
      t === "codex"
        ? u.codexHome
        : t === "claude"
          ? u.claudeHome
          : t === "dsh"
            ? (u.dshRoots || []).join(`
`)
            : "",
    ),
    [r, g] = React.useState(u.codexPath || ""),
    [m, f] = React.useState(!1),
    [p, w] = React.useState(""),
    N = a.providers[t] || {};
  async function D() {
    let h = await l("chooseDirectory"),
      x = typeof h == "string" ? h : h?.path;
    x && c(x);
  }
  async function v() {
    if ((N.enabled ?? u.providers[t]) && t !== "codex") {
      f(!0);
      return;
    }
    await d();
  }
  async function d() {
    w("");
    let h =
      t === "codex"
        ? { codexHome: o.trim(), codexPath: r.trim() }
        : t === "claude"
          ? { claudeHome: o.trim() }
          : {
              dshRoots: o
                .split(
                  `
`,
                )
                .map((T) => T.trim())
                .filter(Boolean),
            };
    if ((await l("updateSettings", h)) !== null) {
      if (
        (N.enabled ?? u.providers[t]) &&
        t !== "codex" &&
        (await l("configure", {
          provider: t,
          enabled: !0,
          options:
            t === "claude"
              ? { home: o.trim() || void 0 }
              : { roots: h.dshRoots },
        })) === null
      ) {
        w(
          e(
            "\u504F\u597D\u5DF2\u4FDD\u5B58\uFF0C\u4F46\u8FDE\u63A5\u8FC1\u79FB\u672A\u5B8C\u6210\u3002\u8BF7\u67E5\u770B\u9519\u8BEF\u5E76\u91CD\u65B0\u8FDE\u63A5\u3002",
            "Preferences were saved, but connection migration did not complete. Review the error and reconnect.",
          ),
        );
        return;
      }
      (f(!1),
        w(
          e(
            "\u8DEF\u5F84\u4E0E\u8FDE\u63A5\u914D\u7F6E\u5DF2\u66F4\u65B0\u3002",
            "Paths and connection configuration updated.",
          ),
        ));
    }
  }
  return React.createElement(
    "div",
    { className: "connection-details" },
    N.message && React.createElement("p", null, N.message),
    N.error && React.createElement(Notice, { tone: "warning" }, N.error),
    t === "codex" &&
      React.createElement(
        Notice,
        null,
        e(
          N.desktop?.connected ? "已连接 Codex 桌面。可在灵动岛批准、拒绝和回答问题，操作会提交给原会话。" : "等待 Codex 桌面连接。连接后可在灵动岛处理审批和问题；额度和任务记录仍可查看。",
          N.desktop?.connected ? "Codex Desktop connected. Approve, deny and answer questions in the island; responses go to the original conversation." : "Waiting for Codex Desktop. Approvals and questions become available when connected; quota and task records remain available.",
        ),
      ),
    t === "claude" &&
      React.createElement(
        Notice,
        null,
        e(
          "\u542F\u7528\u4F1A\u5B89\u88C5 QuotaView \u4E13\u5C5E Hook\uFF0C\u4FDD\u7559\u5E76\u5907\u4EFD\u73B0\u6709\u914D\u7F6E\u3002\u4EC5\u6765\u81EA\u6B64\u8FDE\u63A5\u7684 PermissionRequest \u53EF\u5728\u5C9B\u5185\u54CD\u5E94\u3002",
          "Enabling installs QuotaView-owned Hooks while preserving and backing up existing configuration. Only PermissionRequests from this connection can be answered here.",
        ),
      ),
    t === "dsh" &&
      React.createElement(
        Notice,
        null,
        e(
          "\u8BFB\u53D6\u672C\u673A DSH \u63D2\u4EF6\u4E8B\u4EF6\u3002\u542F\u7528\u65F6\u4F1A\u53D1\u73B0\u9ED8\u8BA4 DSH\u3001\u5E94\u7528\u6570\u636E\u4E2D\u7684\u914D\u7F6E\u4EE5\u53CA\u4E0B\u65B9\u989D\u5916\u76EE\u5F55\uFF0C\u5E76\u5907\u4EFD\u3001\u4FEE\u6539\u5176\u4E2D\u7684 DSH \u914D\u7F6E\u3002",
          "Reads local DSH plugin events. Enabling discovers default DSH and app-data profiles plus the extra roots below, then backs up and updates those DSH configurations.",
        ),
      ),
    t === "kimi" &&
      React.createElement(
        Notice,
        null,
        e(
          "\u4EC5\u663E\u793A\u5F53\u524D\u96C6\u6210\u80FD\u591F\u9A8C\u8BC1\u7684\u4E8B\u4EF6\uFF1B\u672A\u77E5\u72B6\u6001\u548C\u989D\u5EA6\u4FDD\u6301\u672A\u77E5\u3002",
          "Shows only events verified by this integration; unavailable state and quota remain unknown.",
        ),
      ),
    t !== "kimi" &&
      React.createElement(
        React.Fragment,
        null,
        React.createElement(Metric, {
          label:
            t === "dsh"
              ? e(
                  "\u989D\u5916\u9879\u76EE\u6839\u76EE\u5F55\uFF08\u6BCF\u884C\u4E00\u4E2A\uFF09",
                  "Extra project roots (one per line)",
                )
              : e(
                  "\u6570\u636E\u76EE\u5F55\uFF08\u7559\u7A7A\u4F7F\u7528\u9ED8\u8BA4\u4F4D\u7F6E\uFF09",
                  "Data directory (empty for default)",
                ),
          value: o,
          onChange: c,
          multiline: t === "dsh",
          placeholder:
            t === "codex"
              ? "%USERPROFILE%\\.codex"
              : t === "claude"
                ? "%USERPROFILE%\\.claude"
                : "C:\\Projects\\my-project",
        }),
        t === "codex" &&
          React.createElement(Metric, {
            label: e(
              "Codex \u53EF\u6267\u884C\u6587\u4EF6\uFF08\u7559\u7A7A\u81EA\u52A8\u67E5\u627E\uFF09",
              "Codex executable (empty to auto-detect)",
            ),
            value: r,
            onChange: g,
            placeholder: "codex.exe",
          }),
        React.createElement(
          "div",
          { className: "connection-buttons" },
          React.createElement(
            "button",
            { onClick: D },
            React.createElement(Icon, { name: "folder", size: 13 }),
            e("\u9009\u62E9\u76EE\u5F55\u2026", "Choose directory\u2026"),
          ),
          React.createElement(
            "button",
            {
              onClick: () => {
                (c(""), t === "codex" && g(""));
              },
            },
            e("\u6062\u590D\u9ED8\u8BA4", "Use default"),
          ),
          React.createElement(
            "button",
            {
              className: "primary-button",
              disabled: i.updateSettings || i.configure,
              onClick: v,
            },
            (N.enabled ?? u.providers[t]) && t !== "codex"
              ? e(
                  "\u4FDD\u5B58\u5E76\u91CD\u65B0\u8FDE\u63A5\u2026",
                  "Save and reconnect\u2026",
                )
              : e("\u4FDD\u5B58\u8DEF\u5F84", "Save paths"),
          ),
        ),
      ),
    t === "codex" && React.createElement(CodexSettings, null),
    N.lastEventAt &&
      React.createElement(
        "p",
        { className: "source-note" },
        e("\u6700\u8FD1\u4E8B\u4EF6\uFF1A", "Last event: "),
        new Date(N.lastEventAt).toLocaleString(),
      ),
    React.createElement(
      "div",
      { className: "connection-buttons" },
      React.createElement(
        "button",
        {
          onClick: () =>
            t === "dsh" && (N.enabled ?? u.providers[t]) ? f(!0) : l("refresh"),
          disabled: i.refresh || i.configure,
        },
        React.createElement(Icon, { name: "refresh", size: 13 }),
        t === "dsh" && (N.enabled ?? u.providers[t])
          ? e(
              "\u91CD\u65B0\u53D1\u73B0\u5E76\u5B89\u88C5\u2026",
              "Rediscover and install\u2026",
            )
          : e("\u91CD\u65B0\u68C0\u67E5", "Recheck"),
      ),
    ),
    p && React.createElement(Notice, null, p),
    m &&
      React.createElement(
        ConfirmationDialog,
        {
          title: e(
            "\u4FDD\u5B58\u5E76\u91CD\u65B0\u8FDE\u63A5\uFF1F",
            "Save and reconnect?",
          ),
          confirmLabel: e(
            "\u66F4\u65B0\u63A5\u5165\u914D\u7F6E",
            "Update integration",
          ),
          onClose: () => f(!1),
          onConfirm: d,
        },
        React.createElement(
          "p",
          null,
          e(
            "\u8FD9\u4F1A\u5907\u4EFD\u914D\u7F6E\u3001\u79FB\u9664\u65E7\u76EE\u5F55\u4E2D\u4EC5\u5C5E\u4E8E QuotaView \u7684\u6761\u76EE\uFF0C\u5E76\u5728\u4EE5\u4E0B\u65B0\u76EE\u5F55\u4E2D\u5B89\u88C5\u63A5\u5165\u3002\u5176\u4ED6 Hook \u548C\u8BBE\u7F6E\u5C06\u4FDD\u7559\u3002",
            "This backs up configuration, removes only QuotaView-owned entries from old locations and installs the integration in the locations below. Other Hooks and settings are preserved.",
          ),
        ),
        React.createElement(
          "pre",
          null,
          o.trim() ||
            e("\u9ED8\u8BA4\u6570\u636E\u76EE\u5F55", "Default data directory"),
        ),
        t === "dsh" &&
          React.createElement(
            "p",
            null,
            e(
              "\u8FD8\u4F1A\u68C0\u67E5\u9ED8\u8BA4 DSH \u76EE\u5F55\u3001DSH_HOME \u4E0E\u5E94\u7528\u6570\u636E\u4E0B\u53D1\u73B0\u7684 DSH \u914D\u7F6E\u3002",
              "Also checks default DSH, DSH_HOME and discovered app-data DSH profiles.",
            ),
          ),
        React.createElement(
          "p",
          null,
          e(
            "\u65B0\u4F1A\u8BDD\u53EF\u80FD\u9700\u8981\u91CD\u542F\u540E\u624D\u4F1A\u4EA7\u751F\u4E8B\u4EF6\u3002",
            "New sessions may need a restart before events arrive.",
          ),
        ),
      ),
  );
}
function ConnectionSettings() {
  let { t, snapshot: e, invoke: a, busy: l } = useApp(),
    [n, i] = React.useState("codex"),
    [u, o] = React.useState(null);
  async function c(r, g) {
    (await a("configure", {
      provider: r,
      enabled: g,
      options: {
        codexHome: e.settings.codexHome,
        claudeHome: e.settings.claudeHome,
        dshRoots: e.settings.dshRoots,
        executable: e.settings.codexPath,
      },
    }),
      o(null));
  }
  return React.createElement(
    React.Fragment,
    null,
    React.createElement(
      "div",
      { className: "group-box connection-list" },
      PROVIDERS.map((r) => {
        let g = e.providers[r] || {},
          m = g.enabled ?? e.settings.providers[r];
        return React.createElement(
          "section",
          { className: "provider-section", key: r },
          React.createElement(
            "div",
            { className: "provider-row" },
            React.createElement(
              "button",
              {
                className: "provider-heading",
                onClick: () => i(n === r ? null : r),
                "aria-expanded": n === r,
              },
              React.createElement(ProviderIcon, { provider: r, size: 24 }),
              React.createElement("strong", null, PROVIDER_LABELS[r]),
              React.createElement(Icon, {
                name: n === r ? "down" : "right",
                size: 12,
              }),
            ),
            React.createElement(
              "span",
              {
                className: `connection-state ${g.connected ? "connected" : ""} ${g.error ? "error" : ""}`,
              },
              React.createElement("i", null),
              m
                ? g.error
                  ? t("\u9700\u8981\u5904\u7406", "Needs attention")
                  : g.connected
                    ? t("\u5DF2\u8FDE\u63A5", "Connected")
                    : t("\u7B49\u5F85\u6570\u636E", "Awaiting data")
                : t("\u5DF2\u505C\u7528", "Disabled"),
            ),
            React.createElement(Toggle, {
              label: t(
                `\u542F\u7528 ${PROVIDER_LABELS[r]}`,
                `Enable ${PROVIDER_LABELS[r]}`,
              ),
              checked: m,
              disabled: l.configure,
              onChange: (f) => (f ? o(r) : c(r, !1)),
            }),
          ),
          n === r && React.createElement(IntegrationSettings, { provider: r }),
        );
      }),
    ),
    React.createElement(
      "p",
      { className: "group-note" },
      t(
        "\u8FDE\u63A5\u5706\u70B9\u53EA\u8868\u793A\u6700\u8FD1\u7684\u6570\u636E\u8BFB\u53D6\u662F\u5426\u6709\u6548\uFF0C\u4E0D\u4EE3\u8868\u767B\u5F55\u72B6\u6001\u6216\u4FDD\u8BC1\u8D26\u6237\u53EF\u7528\u3002\u505C\u7528\u4F1A\u505C\u6B62\u5BF9\u5E94\u540E\u53F0\u5DE5\u4F5C\u3002",
        "Connection dots indicate the latest successful data read, not login status or guaranteed account access. Disabling stops the related background work.",
      ),
    ),
    React.createElement(
      Notice,
      { icon: "shield" },
      t(
        "\u9ED8\u8BA4\u4EC5\u5904\u7406\u672C\u673A\u6570\u636E\uFF0C\u4E0D\u4E0A\u4F20\u4EFB\u52A1\u5185\u5BB9\u3002\u542F\u7528\u63A5\u5165\u4E0D\u4F1A\u66FF\u4F60\u767B\u5F55\u8D26\u6237\u3002",
        "Local data stays local by default. Enabling an integration does not sign you in to an account.",
      ),
    ),
    u &&
      React.createElement(
        ConfirmationDialog,
        {
          title: t(
            `\u542F\u7528 ${PROVIDER_LABELS[u]} \u63A5\u5165\uFF1F`,
            `Enable ${PROVIDER_LABELS[u]}?`,
          ),
          confirmLabel: t("\u542F\u7528\u8FDE\u63A5", "Enable integration"),
          onClose: () => o(null),
          onConfirm: () => c(u, !0),
        },
        React.createElement(
          "p",
          null,
          u === "codex"
            ? t(
                "QuotaView \u5C06\u8BFB\u53D6\u4F60\u9009\u62E9\u7684 Codex \u6570\u636E\u76EE\u5F55\u5E76\u8FDE\u63A5\u672C\u5730 App Server\u3002",
                "QuotaView will read the selected Codex data directory and connect to the local App Server.",
              )
            : t(
                "\u8FD9\u4F1A\u5728\u6240\u9009\u5BA2\u6237\u7AEF\u6216\u9879\u76EE\u4E2D\u5B89\u88C5 QuotaView \u4E13\u5C5E\u4E8B\u4EF6 Hook\uFF0C\u5E76\u5907\u4EFD\u5DF2\u6709\u914D\u7F6E\u3002\u65B0\u4F1A\u8BDD\u53EF\u80FD\u9700\u8981\u91CD\u542F\u624D\u80FD\u8FDE\u63A5\u3002",
                "This installs QuotaView-owned event Hooks in the selected client or project and backs up existing configuration. Restart the session if needed to connect.",
              ),
        ),
        React.createElement(
          "p",
          null,
          t(
            "\u53EA\u6709\u672C\u8FDE\u63A5\u6301\u6709\u7684\u771F\u5B9E\u6743\u9650\u8BF7\u6C42\u53EF\u4EE5\u5728 QuotaView \u5185\u54CD\u5E94\u3002",
            "Only real permission requests owned by this connection can be answered in QuotaView.",
          ),
        ),
      ),
  );
}
function ProxySettings() {
  let { snapshot: t, t: e, invoke: a, busy: l } = useApp(),
    [n, i] = React.useState(t.settings.proxy?.mode || "system"),
    [u, o] = React.useState(t.settings.proxy?.url || ""),
    [c, r] = React.useState("");
  async function g() {
    if ((r(""), n === "manual"))
      try {
        let f = new URL(u);
        if (
          !["http:", "https:", "socks5:"].includes(f.protocol) ||
          f.username ||
          f.password
        )
          throw new Error();
      } catch {
        r(
          e(
            "\u8BF7\u8F93\u5165 HTTP\u3001HTTPS \u6216 SOCKS5 \u4EE3\u7406\u5730\u5740\uFF0C\u4E0D\u8981\u5728\u5730\u5740\u4E2D\u5305\u542B\u7528\u6237\u540D\u6216\u5BC6\u7801\u3002",
            "Enter an HTTP, HTTPS or SOCKS5 proxy URL without a username or password.",
          ),
        );
        return;
      }
    await a("updateSettings", {
      proxy: { mode: n, url: n === "manual" ? u.trim() : "" },
    });
  }
  let m =
    n !== (t.settings.proxy?.mode || "system") ||
    (n === "manual" && u !== (t.settings.proxy?.url || ""));
  return React.createElement(
    React.Fragment,
    null,
    React.createElement(
      "div",
      { className: "proxy-preview" },
      React.createElement(
        "div",
        { className: "proxy-route" },
        React.createElement(
          "div",
          null,
          React.createElement(
            "span",
            null,
            React.createElement("img", {
              src: "../assets/app-icon.png",
              width: "34",
              height: "34",
              alt: "",
            }),
          ),
          React.createElement("strong", null, "QuotaView"),
        ),
        React.createElement("i", null),
        React.createElement(
          "div",
          null,
          React.createElement(
            "span",
            null,
            React.createElement(Icon, { name: "globe", size: 26 }),
          ),
          React.createElement(
            "strong",
            null,
            n === "direct"
              ? e("\u76F4\u8FDE", "Direct")
              : n === "system"
                ? e("\u7CFB\u7EDF\u4EE3\u7406", "System proxy")
                : e("\u624B\u52A8\u4EE3\u7406", "Manual proxy"),
          ),
        ),
        React.createElement("i", null),
        React.createElement(
          "div",
          null,
          React.createElement(
            "span",
            null,
            React.createElement(Icon, { name: "download", size: 26 }),
          ),
          React.createElement(
            "strong",
            null,
            e("\u66F4\u65B0\u670D\u52A1", "Update service"),
          ),
        ),
      ),
      React.createElement(
        "p",
        null,
        e(
          "用于更新检查和 QuotaView 的 Codex 额度连接；其他 Agent 进程保留自身网络设置。",
          "Applies to update checks and the QuotaView Codex quota connection. Other agent processes keep their own network settings.",
        ),
      ),
    ),
    React.createElement(
      SettingGroup,
      { title: e("\u4EE3\u7406\u914D\u7F6E", "Proxy configuration") },
      React.createElement(
        SettingRow,
        {
          title: e("\u8FDE\u63A5\u65B9\u5F0F", "Connection mode"),
          icon: "globe",
        },
        React.createElement(Select, {
          label: e("\u8FDE\u63A5\u65B9\u5F0F", "Connection mode"),
          value: n,
          onChange: i,
          options: [
            ["system", e("\u8DDF\u968F Windows", "Use Windows settings")],
            [
              "direct",
              e("\u4E0D\u4F7F\u7528\u4EE3\u7406", "Direct connection"),
            ],
            ["manual", e("\u624B\u52A8\u4EE3\u7406", "Manual proxy")],
          ],
        }),
      ),
      n === "manual" &&
        React.createElement(
          "div",
          { className: "proxy-field" },
          React.createElement(Metric, {
            label: e("\u4EE3\u7406\u5730\u5740", "Proxy URL"),
            value: u,
            onChange: o,
            placeholder: "http://127.0.0.1:7890",
          }),
        ),
    ),
    c && React.createElement(Notice, { tone: "warning" }, c),
    React.createElement(
      Notice,
      null,
      e(
        "Codex CLI \u548C\u5176\u4ED6 Agent \u4F7F\u7528\u5404\u81EA\u7684\u73AF\u5883\u53D8\u91CF\u6216\u5BA2\u6237\u7AEF\u4EE3\u7406\u8BBE\u7F6E\u3002\u6B64\u9009\u9879\u4E0D\u4F1A\u5077\u5077\u4FEE\u6539\u5B83\u4EEC\uFF0C\u4E5F\u4E0D\u8868\u793A\u4EE3\u7406\u5DF2\u7ECF\u901A\u8FC7\u8FDE\u901A\u6027\u6D4B\u8BD5\u3002",
        "Codex CLI and other agents use their own environment or client proxy settings. This option does not modify them and does not imply a successful connectivity test.",
      ),
    ),
    React.createElement(
      "button",
      {
        className: "primary-button",
        disabled: !m || l.updateSettings,
        onClick: g,
      },
      e("\u4FDD\u5B58\u4EE3\u7406\u8BBE\u7F6E", "Save proxy settings"),
    ),
  );
}
function FeedbackSettings() {
  let { t, invoke: e, busy: a } = useApp(),
    [l, n] = React.useState(!1),
    [i, u] = React.useState("");
  return React.createElement(
    React.Fragment,
    null,
    React.createElement(
      SettingGroup,
      {
        title: t("\u95EE\u9898\u4E0E\u5EFA\u8BAE", "Issues and suggestions"),
      },
      React.createElement(
        "button",
        {
          className: "link-row",
          onClick: () =>
            e(
              "openExternal",
              "https://github.com/Duoasa/QuotaView/issues",
            ),
        },
        React.createElement(
          "span",
          { className: "row-icon" },
          React.createElement(Icon, { name: "bug" }),
        ),
        React.createElement(
          "span",
          null,
          React.createElement("strong", null, "GitHub Issues"),
          React.createElement(
            "small",
            null,
            t(
              "\u62A5\u544A\u95EE\u9898\u3001\u5EFA\u8BAE\u529F\u80FD\uFF0C\u6216\u67E5\u770B\u5DF2\u6709\u53CD\u9988\u3002",
              "Report bugs, request features or review existing issues.",
            ),
          ),
        ),
        React.createElement(Icon, { name: "external", size: 14 }),
      ),
      React.createElement(
        "button",
        { className: "link-row", onClick: () => n(!0) },
        React.createElement(
          "span",
          { className: "row-icon" },
          React.createElement(Icon, { name: "connections" }),
        ),
        React.createElement(
          "span",
          null,
          React.createElement(
            "strong",
            null,
            t("QQ \u4EA4\u6D41\u7FA4", "QQ community"),
          ),
          React.createElement(
            "small",
            null,
            t("\u7FA4\u53F7\uFF1A1108649282", "Group: 1108649282"),
          ),
        ),
        React.createElement(Icon, { name: "right", size: 14 }),
      ),
    ),
    React.createElement(
      SettingGroup,
      { title: t("\u672C\u5730\u8BCA\u65AD", "Local diagnostics") },
      React.createElement(
        SettingRow,
        {
          title: t(
            "\u5BFC\u51FA\u8BCA\u65AD\u4FE1\u606F",
            "Export diagnostics",
          ),
          description: t(
            "\u53EA\u4FDD\u5B58\u5230\u4F60\u7684\u7535\u8111\u3002\u5206\u4EAB\u524D\u8BF7\u81EA\u884C\u68C0\u67E5\u662F\u5426\u5305\u542B\u654F\u611F\u8DEF\u5F84\u6216\u4EFB\u52A1\u4FE1\u606F\u3002",
            "Saved locally only. Review paths and task information before sharing.",
          ),
          icon: "file",
        },
        React.createElement(
          "button",
          {
            disabled: a.exportDiagnostics,
            onClick: async () => {
              let o = await e("exportDiagnostics");
              o &&
                u(
                  typeof o == "string"
                    ? o
                    : o.path || t("\u5DF2\u5BFC\u51FA", "Exported"),
                );
            },
          },
          t("\u5BFC\u51FA\u2026", "Export\u2026"),
        ),
      ),
    ),
    i &&
      React.createElement(
        Notice,
        null,
        t("\u8BCA\u65AD\u6587\u4EF6\uFF1A", "Diagnostic file: "),
        i,
      ),
    React.createElement(
      Notice,
      { icon: "shield" },
      t(
        "\u4E0D\u4F1A\u81EA\u52A8\u4E0A\u4F20\u8BCA\u65AD\u6587\u4EF6\u3001\u8D26\u6237\u6570\u636E\u6216\u4EFB\u52A1\u8BB0\u5F55\u3002\u82E5\u8981\u53CD\u9988\uFF0C\u8BF7\u81EA\u884C\u9009\u62E9\u8981\u5206\u4EAB\u7684\u5185\u5BB9\u3002",
        "Diagnostics, account data and task records are not uploaded automatically. Choose what to share when reporting an issue.",
      ),
    ),
    l &&
      React.createElement(
        "div",
        { className: "modal-backdrop", onClick: () => n(!1) },
        React.createElement(
          "section",
          {
            className: "dialog qr-dialog",
            role: "dialog",
            "aria-modal": "true",
            "aria-label": t("QQ \u7FA4\u4E8C\u7EF4\u7801", "QQ group QR code"),
            onClick: (o) => o.stopPropagation(),
          },
          React.createElement(
            "h2",
            null,
            t("QQ \u4EA4\u6D41\u7FA4", "QQ community"),
          ),
          React.createElement("img", {
            src: "../assets/feedback-qr.png",
            alt: t(
              "QuotaView QQ \u7FA4\u4E8C\u7EF4\u7801",
              "QuotaView QQ group QR code",
            ),
          }),
          React.createElement("p", null, "1108649282"),
          React.createElement(
            "button",
            { className: "primary-button", onClick: () => n(!1) },
            t("\u5173\u95ED", "Close"),
          ),
        ),
      ),
  );
}
function AboutSettings() {
  let { snapshot: t, t: e, invoke: a, busy: l } = useApp(),
    n = t.update || {},
    i =
      t.version && typeof t.version == "object"
        ? t.version.version || t.version.name
        : t.version;
  return React.createElement(
    React.Fragment,
    null,
    React.createElement(
      "div",
      { className: "about-hero" },
      React.createElement("img", {
        src: "../assets/app-icon.png",
        width: "80",
        height: "80",
        alt: "QuotaView",
      }),
      React.createElement(
        "div",
        null,
        React.createElement("h2", null, "QuotaView"),
        React.createElement(
          "p",
          null,
          e(
            "\u8BA9 AI \u5DE5\u4F5C\u6E05\u6670\u53EF\u89C1",
            "Clarity for your AI workflow",
          ),
        ),
        React.createElement(
          "span",
          null,
          i ||
            e(
              "\u7248\u672C\u4FE1\u606F\u4E0D\u53EF\u7528",
              "Version unavailable",
            ),
          " \xB7 Windows",
        ),
      ),
    ),
    React.createElement(
      SettingGroup,
      { title: e("\u8F6F\u4EF6\u66F4\u65B0", "Software updates") },
      n.installError && React.createElement(SettingRow, {
        title: e("上次更新未完成", "Last update did not complete"),
        description: n.installError,
      }),
      React.createElement(
        SettingRow,
        {
          title: e("\u68C0\u67E5\u66F4\u65B0", "Check for updates"),
          description: n.checking
            ? e("\u6B63\u5728\u68C0\u67E5\u2026", "Checking\u2026")
            : n.error
              ? n.error
              : n.available
                ? e(
                    `\u53EF\u7528\u7248\u672C\uFF1A${n.version || "\u2014"}`,
                    `Available: ${n.version || "\u2014"}`,
                  )
                : n.checkedAt
                  ? e(
                      "\u68C0\u67E5\u5B8C\u6210\u3002\u6CA1\u6709\u53EF\u7528\u7684 Windows \u66F4\u65B0\u3002",
                      "Check complete. No Windows update is available.",
                    )
                  : e(
                      "\u4E0D\u4F1A\u628A macOS \u7248\u672C\u5F53\u4F5C Windows \u66F4\u65B0\u5B89\u88C5\u3002",
                      "macOS releases are never installed as Windows updates.",
                    ),
          icon: "refresh",
        },
        React.createElement(
          "button",
          {
            disabled: l.checkUpdates || n.checking || ["downloading", "verifying", "ready", "installing", "restart"].includes(n.phase),
            onClick: () => a("checkUpdates"),
          },
          e("\u68C0\u67E5\u66F4\u65B0\u2026", "Check for updates\u2026"),
        ),
      ),
      React.createElement(SettingToggle, {
        name: "autoCheckUpdates",
        title: e(
          "\u81EA\u52A8\u68C0\u67E5\u66F4\u65B0",
          "Automatically check for updates",
        ),
        description: e(
          "自动检查 Windows 更新，由你决定下载和重启安装。",
          "Check for Windows updates automatically. You choose when to download and restart.",
        ),
        icon: "download",
      }),
      n.available &&
        n.channel === "windows" &&
        React.createElement(
          SettingRow,
          {
            title: n.phase === "downloading" ? e(`正在下载 ${n.progress || 0}%`, `Downloading ${n.progress || 0}%`)
              : n.phase === "verifying" ? e("正在校验更新包…", "Verifying update…")
              : n.phase === "ready" ? e("更新已准备就绪", "Update ready")
              : ["installing", "restart"].includes(n.phase) ? e("正在准备重启…", "Preparing to restart…")
              : e("下载 Windows 更新", "Download Windows update"),
            description: e("安装后自动重新打开，保留现有设置与数据。", "Reopens after installation, keeping your settings and data."),
            icon: "download",
          },
          React.createElement("button", {
            disabled: l.downloadUpdate || l.installUpdate || ["verifying", "installing", "restart"].includes(n.phase),
            onClick: () => a(n.phase === "downloading" ? "cancelUpdate" : n.phase === "ready" ? "installUpdate" : "downloadUpdate"),
          }, n.phase === "downloading" ? e("取消下载", "Cancel download")
            : n.phase === "ready" ? e("重启并安装", "Restart and install") : e("下载更新", "Download update")),
        ),
      n.available &&
        n.url &&
        React.createElement(
          SettingRow,
          {
            title: e(
              "\u67E5\u770B Windows \u66F4\u65B0",
              "View Windows update",
            ),
          },
          React.createElement(
            "button",
            { onClick: () => a("openExternal", n.url) },
            e("\u6253\u5F00\u53D1\u5E03\u9875\u9762", "Open release page"),
            React.createElement(Icon, { name: "external", size: 12 }),
          ),
        ),
    ),
    React.createElement(
      SettingGroup,
      { title: e("\u9879\u76EE", "Project") },
      React.createElement(
        "button",
        {
          className: "link-row",
          onClick: () =>
            a("openExternal", "https://github.com/Duoasa/QuotaView"),
        },
        React.createElement(
          "span",
          null,
          React.createElement(
            "strong",
            null,
            e(
              "\u6E90\u4EE3\u7801\u4E0E\u8BF4\u660E",
              "Source code and documentation",
            ),
          ),
          React.createElement(
            "small",
            null,
            "github.com/Duoasa/QuotaView",
          ),
        ),
        React.createElement(Icon, { name: "external", size: 14 }),
      ),
      React.createElement(
        "button",
        {
          className: "link-row",
          onClick: () =>
            a(
              "openExternal",
              "https://github.com/Duoasa/QuotaView/blob/main/LICENSE",
            ),
        },
        React.createElement(
          "span",
          null,
          React.createElement(
            "strong",
            null,
            e("\u5F00\u6E90\u8BB8\u53EF", "Open-source license"),
          ),
          React.createElement("small", null, "MIT \xB7 Duoasa"),
        ),
        React.createElement(Icon, { name: "external", size: 14 }),
      ),
      React.createElement(
        "button",
        {
          className: "link-row",
          onClick: () =>
            a("openExternal", "https://github.com/Duoasa/QuotaView"),
        },
        React.createElement(
          "span",
          null,
          React.createElement(
            "strong",
            null,
            e(
              "\u4E0A\u6E38 QuotaView \u9879\u76EE",
              "Upstream QuotaView project",
            ),
          ),
          React.createElement(
            "small",
            null,
            e(
              "\u539F\u59CB macOS \u5B9E\u73B0\u4E0E\u8BBE\u8BA1",
              "Original macOS implementation and design",
            ),
          ),
        ),
        React.createElement(Icon, { name: "external", size: 14 }),
      ),
    ),
    React.createElement(
      "div",
      { className: "platform-note" },
      React.createElement(Icon, { name: "monitor" }),
      React.createElement(
        "p",
        null,
        e(
          "Windows \u9002\u914D\u4E0D\u5305\u542B\u684C\u9762\u5C0F\u7EC4\u4EF6\u3002\u4EFB\u52A1\u5C9B\u3001\u989D\u5EA6\u3001\u7528\u91CF\u3001\u8FDE\u63A5\u4E0E\u8BBE\u7F6E\u5747\u5728\u672C\u673A\u8FD0\u884C\u3002\u89C6\u89C9\u4E0E\u4EA4\u4E92\u6548\u679C\u4EE5 Windows \u624B\u52A8\u9A8C\u6536\u4E3A\u51C6\u3002",
          "The Windows port excludes desktop widgets. The Island, quota, usage, integrations and settings run locally. Visual and interaction quality requires manual Windows acceptance.",
        ),
      ),
    ),
    React.createElement(
      "p",
      { className: "about-credits" },
      e(
        "Asta Sans \u5B57\u4F53\u6309 SIL Open Font License \u5206\u53D1\u3002\u670D\u52A1\u5546\u540D\u79F0\u4E0E\u6807\u5FD7\u5C5E\u4E8E\u5176\u5404\u81EA\u6240\u6709\u8005\u3002",
        "Asta Sans is distributed under the SIL Open Font License. Provider names and marks belong to their respective owners.",
      ),
    ),
  );
}
function SettingsView() {
  let { t, invoke: e, snapshot: a } = useApp(),
    [l, n] = React.useState("general"),
    i = React.useRef(null),
    u = React.useRef(null),
    o = settingPages.find((m) => m[0] === l),
    c = {
      general: t(
        "\u8BED\u8A00\u3001\u663E\u793A\u4F4D\u7F6E\u4E0E\u5E94\u7528\u63A7\u5236\u3002",
        "Language, placement and app controls.",
      ),
      island: t(
        "布局、隐私与自动展开。",
        "Layout, privacy and automatic opening.",
      ),
      usage: t(
        "\u9009\u62E9\u7528\u91CF\u9875\u663E\u793A\u7684\u53EF\u9009\u6A21\u5757\u3002",
        "Choose optional modules for your usage page.",
      ),
      connections: t(
        "\u7BA1\u7406\u56DB\u79CD Agent \u7684\u672C\u5730\u4EFB\u52A1\u63A5\u5165\u3002",
        "Manage local activity from four agent providers.",
      ),
      proxy: t(
        "\u4E3A QuotaView \u7684\u66F4\u65B0\u68C0\u67E5\u9009\u62E9\u7F51\u7EDC\u8FDE\u63A5\u3002",
        "Configure networking for QuotaView update checks.",
      ),
      feedback: t(
        "\u9047\u5230\u95EE\u9898\u65F6\uFF0C\u901A\u8FC7\u4EE5\u4E0B\u65B9\u5F0F\u8054\u7CFB\u6211\u4EEC\u3002",
        "Get help when something goes wrong.",
      ),
      about: t(
        "\u7248\u672C\u4FE1\u606F\u3001\u5F00\u6E90\u8BB8\u53EF\u4E0E\u8F6F\u4EF6\u66F4\u65B0\u3002",
        "Version information, licenses and software updates.",
      ),
    };
  function r(m) {
    (n(m), i.current?.scrollTo({ top: 0 }));
  }
  function g(m) {
    let f = settingPages.findIndex((w) => w[0] === l),
      p = m.key === "ArrowDown" ? 1 : m.key === "ArrowUp" ? -1 : 0;
    if (p) {
      m.preventDefault();
      let w =
        settingPages[(f + p + settingPages.length) % settingPages.length][0];
      (r(w), u.current?.querySelector(`[data-page="${w}"]`)?.focus());
    }
  }
  return React.createElement(
    "main",
    { className: "settings-window" },
    React.createElement(
      "div",
      { className: "window-titlebar" },
      React.createElement(
        "span",
        null,
        React.createElement("img", {
          src: "../assets/app-icon.png",
          width: "16",
          height: "16",
          alt: "",
        }),
        "QuotaView",
      ),
      React.createElement(
        "div",
        { className: "window-controls" },
        React.createElement(
          "button",
          {
            onClick: () => e("minimize"),
            "aria-label": t("\u6700\u5C0F\u5316", "Minimize"),
          },
          React.createElement(Icon, { name: "minus", size: 12 }),
        ),
        React.createElement(
          "button",
          {
            onClick: () => e("maximize"),
            "aria-label": t("最大化或还原", "Maximize or restore"),
          },
          h(
            "svg",
            {
              width: 10,
              height: 10,
              viewBox: "0 0 12 12",
              fill: "none",
              "aria-hidden": true,
            },
            h("rect", {
              x: 2,
              y: 2,
              width: 8,
              height: 8,
              stroke: "currentColor",
            }),
          ),
        ),
        React.createElement(
          "button",
          {
            className: "window-close",
            onClick: () => e("showWindow", "close-settings"),
            "aria-label": t("\u5173\u95ED\u8BBE\u7F6E", "Close settings"),
          },
          React.createElement(Icon, { name: "close", size: 12 }),
        ),
      ),
    ),
    React.createElement(
      "aside",
      { className: "settings-sidebar" },
      React.createElement("h1", null, t("\u8BBE\u7F6E", "Settings")),
      React.createElement(
        "nav",
        {
          ref: u,
          "aria-label": t("\u8BBE\u7F6E\u5206\u7C7B", "Settings categories"),
          onKeyDown: g,
        },
        settingPages.map(([m, f, p, w, N], D) =>
          React.createElement(
            React.Fragment,
            { key: m },
            [3, 5].includes(D) &&
              React.createElement("div", { className: "nav-separator" }),
            React.createElement(
              "button",
              {
                "data-page": m,
                className: l === m ? "selected" : "",
                onClick: () => r(m),
                "aria-current": l === m ? "page" : void 0,
              },
              React.createElement(
                "span",
                { className: "sidebar-icon", style: { background: N } },
                React.createElement(Icon, { name: f, size: 16 }),
              ),
              React.createElement("span", null, t(p, w)),
            ),
          ),
        ),
      ),
      React.createElement(
        "div",
        { className: "sidebar-foot" },
        React.createElement("span", { className: "local-dot" }),
        t(
          "\u672C\u5730\u4F18\u5148 \xB7 \u65E0\u9065\u6D4B",
          "Local first \xB7 No telemetry",
        ),
      ),
    ),
    React.createElement(
      "div",
      { className: "settings-detail", ref: i },
      React.createElement(
        "div",
        { className: "settings-content" },
        React.createElement(
          "header",
          { className: "settings-page-heading" },
          React.createElement(
            "h1",
            null,
            React.createElement(
              "span",
              { className: "sidebar-icon", style: { background: o[4] } },
              React.createElement(Icon, { name: o[1], size: 17 }),
            ),
            t(o[2], o[3]),
          ),
          React.createElement("p", null, c[l]),
        ),
        l === "general"
          ? React.createElement(GeneralSettings, null)
          : l === "island"
            ? React.createElement(IslandSettings, null)
            : l === "usage"
              ? React.createElement(UsageSettings, null)
              : l === "connections"
                ? React.createElement(ConnectionSettings, null)
                : l === "proxy"
                  ? React.createElement(ProxySettings, null)
                  : l === "feedback"
                    ? React.createElement(FeedbackSettings, null)
                    : React.createElement(AboutSettings, null),
        React.createElement(
          "footer",
          { className: "settings-save-note" },
          React.createElement(Icon, { name: "check", size: 12 }),
          t(
            "\u5F00\u5173\u81EA\u52A8\u4FDD\u5B58\uFF1B\u6587\u672C\u914D\u7F6E\u8BF7\u70B9\u51FB\u4FDD\u5B58",
            "Toggles save automatically; save text configurations explicitly",
          ),
        ),
      ),
    ),
  );
}

export {
  SettingToggle,
  GeneralSettings,
  IslandPreview,
  IslandSettings,
  UsageSettings,
  CodexSettings,
  IntegrationSettings,
  ConnectionSettings,
  ProxySettings,
  FeedbackSettings,
  AboutSettings,
  SettingsView,
  settingPages,
};
