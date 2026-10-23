import { React } from "./react.js";
import {
  isFiniteNumber,
  formatNumber,
  taskProgress,
  formatDuration,
  plainText,
  statusLabel,
  observeVisibility,
  Icon,
  ProviderIcon,
  IconButton,
  Select,
  Notice,
  EmptyState,
  ConnectionDot,
  ConfirmationDialog,
  Markdown,
  PROVIDER_LABELS,
  useApp,
} from "./common.js";
import { QuotaCapsule, UsageView } from "./usage.js";
const { needsAttention, attentionKey } = window.QVTaskState;
function StatusOrb({ status: t = "unknown", small: e = !1, task: a }) {
  let { snapshot: l } = useApp();
  return window.QVEffects.renderOrb(React, {
    status: t,
    small: e,
    task: a,
    reduceMotion: !!l.settings.reduceMotion,
  });
}
function TaskCard({
  task: t,
  selected: e,
  focused = false,
  onSelect: a,
  nested: l = !1,
}) {
  let { snapshot: n, t: i, locale: u, now: o, invoke } = useApp(),
    c = React.useRef(null);
  React.useEffect(() => observeVisibility(c.current), []);
  let r = n.settings.privacy,
    g = taskProgress(t),
    m = t.startedAt
      ? formatDuration((t.completedAt || o) - t.startedAt, i)
      : null,
    f = window.QVEffects.displayState(t),
    p = r
      ? `${PROVIDER_LABELS[t.provider] || "Agent"} ${i("\u4EFB\u52A1", "task")}`
      : t.title || i("\u672A\u547D\u540D\u4EFB\u52A1", "Untitled task"),
    w = r
      ? i("\u5185\u5BB9\u5DF2\u9690\u85CF", "Content hidden")
      : needsAttention(t)
        ? t.approval?.kind === "question"
          ? i("等待你的回答", "Waiting for your answer")
          : i("等待你的确认", "Waiting for your confirmation")
        : t.tool
          ? plainText(
              (typeof t.tool == "object" && (t.tool.name || t.tool.command)) ||
                t.tool,
            )
          : t.publicText
            ? plainText(t.publicText).replace(/\s+/g, " ").slice(0, 150)
            : f === "completed"
              ? i(
                  "\u70B9\u51FB\u67E5\u770B\u516C\u5F00\u7ED3\u679C",
                  "View the public result",
                )
              : f === "unknown"
                ? i(
                    "\u7B49\u5F85\u65B0\u7684\u72B6\u6001\u4E8B\u4EF6",
                    "Waiting for a new status event",
                  )
                : i(
                    "\u7B49\u5F85\u516C\u5F00\u8FDB\u5C55",
                    "Waiting for public progress",
                  );
  return React.createElement(
    "div",
    {
      ref: c,
      role: "button",
      tabIndex: 0,
      onKeyDown: (event) => {
        if (
          event.target === event.currentTarget &&
          ["Enter", " "].includes(event.key)
        ) {
          event.preventDefault();
          a?.();
        }
      },
      type: "button",
      className: `task-card status-${f} effect-quantum ${e ? "selected" : ""} ${l ? "nested" : ""} ${g.known ? "known-progress" : "unknown-progress"}`,
      onClick: a,
      "aria-expanded": e,
      "data-focused": focused,
      "data-task-id": t.id,
      style: { "--progress": `${g.percent ?? 0}%` },
    },
    focused &&
      React.createElement(window.QVEffects.ProgressEffect, {
        react: React,
        task: t,
        effect: "quantum",
        reduceMotion: !!n.settings.reduceMotion,
      }),
    React.createElement(
      "span",
      { className: "task-card-content" },
      React.createElement(
        "span",
        { className: "task-main" },
        !focused && React.createElement(StatusOrb, { status: f, task: t }),
        React.createElement(
          "span",
          { className: "task-copy" },
          React.createElement("span", { className: "task-title" }, p),
          React.createElement(
            "span",
            { className: "task-activity" },
            React.createElement(
              "span",
              { className: "task-status" },
              t.verified === !1 && t.status === "completed"
                ? i(
                    "\u5B8C\u6210\u72B6\u6001\u672A\u9A8C\u8BC1",
                    "Completion unverified",
                  )
                : statusLabel(f, i),
            ),
            React.createElement("span", { className: "activity-text" }, w),
          ),
        ),
      ),
      React.createElement(
        "span",
        { className: "task-meta" },
        React.createElement(
          "span",
          { className: "task-model" },
          !r && t.model ? t.model : PROVIDER_LABELS[t.provider] || "Agent",
          m &&
            React.createElement(
              React.Fragment,
              null,
              React.createElement("i", null),
              " ",
              m,
            ),
          React.createElement(
            "button",
            {
              className: "task-archive",
              title: i("从灵动岛归档", "Archive from island"),
              "aria-label": i("归档任务", "Archive task"),
              onClick: (event) => {
                event.stopPropagation();
                invoke("dismissTask", { id: t.id });
              },
            },
            React.createElement(ProviderIcon, { provider: t.provider }),
            React.createElement(
              "svg",
              {
                className: "archive-glyph",
                viewBox: "0 0 16 16",
                fill: "none",
                "aria-hidden": true,
              },
              React.createElement("path", {
                d: "M2 3h12v3H2z M3 6v7h10V6 M6 9h4",
                stroke: "currentColor",
                strokeWidth: 1.2,
              }),
            ),
          ),
        ),
        React.createElement(
          "span",
          { className: "task-numbers" },
          r
            ? "\u2022\u2022\u2022"
            : isFiniteNumber(t.tokens?.total)
              ? `${formatNumber(t.tokens.total, u, !0)} tokens`
              : g.known
                ? `${Math.round(g.percent)}%`
                : "\u2014",
        ),
      ),
    ),
  );
}
function ApprovalCard({ task: t }) {
  let { t: e, invoke: a, snapshot: l } = useApp(),
    n = t.approval,
    [i, u] = React.useState(!1),
    [o, c] = React.useState(!1),
    [r, g] = React.useState(""),
    [m, f] = React.useState({}),
    [p, w] = React.useState({}),
    [N, D] = React.useState(null);
  if (
    (React.useEffect(() => {
      (u(!1), c(!1), g(""), f({}), w({}), D(null));
    }, [n?.id]),
    !n)
  )
    return null;
  let v = Array.isArray(n.questions) ? n.questions : [],
    d =
      n.canRespond === !0 &&
      ["command", "permission", "question"].includes(n.kind) &&
      !!n.id,
    h = Array.isArray(n.decisions) ? n.decisions : ["accept", "decline"],
    x = {
      accept: e("\u5141\u8BB8\u8FD9\u4E00\u6B21", "Allow once"),
      allow: e("\u5141\u8BB8\u8FD9\u4E00\u6B21", "Allow once"),
      decline: e("\u62D2\u7EDD", "Deny"),
      deny: e("\u62D2\u7EDD", "Deny"),
      cancel: e("\u53D6\u6D88\u8BF7\u6C42", "Cancel request"),
      acceptForSession: e(
        "\u672C\u4F1A\u8BDD\u5141\u8BB8",
        "Allow for session",
      ),
      acceptAlways: e(
        "\u59CB\u7EC8\u5141\u8BB8\u6B64\u8303\u56F4",
        "Always allow this scope",
      ),
    };
  async function T(A) {
    (u(!0), g(""), D(null));
    try {
      (await a("respond", { id: n.id, decision: A }, { throwError: !0 }),
        c(!0));
    } catch (O) {
      const errors = {
        codex_stale_request: e("此请求已更新或已处理，请查看当前卡片。", "This request changed or was already handled. Check the current card."),
        codex_request_already_submitted: e("已提交，正在等待 Codex 确认。", "Already submitted; waiting for Codex."),
        codex_request_already_submitting: e("正在提交，请稍候。", "Submission is in progress."),
        codex_submission_outcome_unknown: e("已发送，但结果尚未确认。请在 Codex 查看，勿重复提交。", "Sent, but the result is unconfirmed. Check Codex before trying again."),
        codex_desktop_timeout: e("Codex 同步超时，请稍后重试。", "Codex synchronization timed out. Try again shortly."),
        codex_desktop_disconnected: e("Codex 连接已断开，请等待重新连接。", "Codex disconnected. Waiting to reconnect."),
      };
      g(errors[O.message] || O.message);
    } finally {
      u(!1);
    }
  }
  function M(A, O, V) {
    f((rt) => ({
      ...rt,
      [A]: V
        ? Array.isArray(rt[A]) && rt[A].includes(O)
          ? rt[A].filter((ue) => ue !== O)
          : [...(Array.isArray(rt[A]) ? rt[A] : []), O]
        : O,
    }));
  }
  function E(A) {
    let O = A.id || A.question,
      V = m[O];
    return Array.isArray(V)
      ? V.flatMap((rt) =>
          rt === "__other__" ? (p[O]?.trim() ? [p[O].trim()] : []) : [rt],
        )
      : V === "__other__"
        ? p[O]?.trim() || ""
        : V || "";
  }
  let C =
    v.length > 0 &&
    v.every((A) => {
      let O = E(A),
        V = A.id || A.question;
      return (
        (Array.isArray(O) ? O.length > 0 : !!O) &&
        (!(Array.isArray(m[V])
          ? m[V].includes("__other__")
          : m[V] === "__other__") ||
          !!p[V]?.trim())
      );
    });
  function nt() {
    let A = {};
    for (let O of v) {
      let V = O.id || O.question,
        rt = E(O);
      A[V] = Array.isArray(rt) ? { answers: rt } : rt;
    }
    T({ answers: A });
  }
  return React.createElement(
    "div",
    { className: "approval-panel" },
    React.createElement(
      "div",
      { className: "detail-heading approval-heading" },
      React.createElement(Icon, { name: "shield" }),
      React.createElement(
        "h3",
        null,
        l.settings.privacy
          ? e(
              "\u9700\u8981\u4F60\u7684\u786E\u8BA4",
              "Your confirmation is needed",
            )
          : n.title ||
              e(
                "\u9700\u8981\u4F60\u7684\u786E\u8BA4",
                "Your confirmation is needed",
              ),
      ),
    ),
    l.settings.privacy
      ? React.createElement(
          Notice,
          null,
          e(
            "\u9690\u79C1\u6A21\u5F0F\u9690\u85CF\u4E86\u5BA1\u6279\u5185\u5BB9\u3002\u5173\u95ED\u9690\u79C1\u6A21\u5F0F\u5E76\u5BA1\u9605\u5177\u4F53\u64CD\u4F5C\u540E\u624D\u80FD\u6279\u51C6\u3002",
            "Privacy mode hides approval details. Turn it off and review the exact action before approving.",
          ),
        )
      : React.createElement(
          React.Fragment,
          null,
          n.reason &&
            n.reason !== "desktop_transport_unverified" &&
            React.createElement(
              "p",
              { className: "approval-reason" },
              plainText(n.reason),
            ),
          n.command &&
            React.createElement(
              "div",
              { className: "command-card" },
              React.createElement(
                "span",
                { className: "eyebrow" },
                React.createElement(Icon, { name: "terminal", size: 12 }),
                e("\u547D\u4EE4", "Command"),
              ),
              React.createElement("pre", null, plainText(n.command)),
            ),
          (n.cwd || t.cwd) &&
            React.createElement(
              "div",
              { className: "approval-field" },
              React.createElement(
                "span",
                null,
                e("\u5DE5\u4F5C\u76EE\u5F55", "Working directory"),
              ),
              React.createElement("code", null, n.cwd || t.cwd),
            ),
          n.scope &&
            React.createElement(
              "div",
              { className: "approval-field" },
              React.createElement(
                "span",
                null,
                e(
                  "\u8BF7\u6C42\u7684\u6743\u9650\u8303\u56F4",
                  "Requested scope",
                ),
              ),
              React.createElement("pre", null, plainText(n.scope)),
            ),
          v.map((A, O) => {
            let V = A.id || A.question || String(O),
              rt = Array.isArray(m[V]) ? m[V] : [m[V]];
            return React.createElement(
              "div",
              { className: "question-card", key: V },
              React.createElement(
                "h4",
                null,
                typeof A == "string"
                  ? A
                  : A.question || A.title || e("\u95EE\u9898", "Question"),
              ),
              A.multiSelect &&
                React.createElement(
                  "p",
                  { className: "chart-note" },
                  e(
                    "\u53EF\u9009\u62E9\u591A\u4E2A\u9009\u9879",
                    "Select all that apply",
                  ),
                ),
              (A.options || []).map((ue, yo) => {
                let yi = typeof ue == "string" ? ue : ue.label;
                return React.createElement(
                  "button",
                  {
                    type: "button",
                    role: A.multiSelect ? "checkbox" : "radio",
                    "aria-checked": rt.includes(yi),
                    className: `question-option ${rt.includes(yi) ? "selected" : ""}`,
                    disabled: !d || i || o,
                    key: yo,
                    onClick: () => M(V, yi, A.multiSelect),
                  },
                  React.createElement("span", {
                    className: "radio-outline",
                  }),
                  React.createElement(
                    "span",
                    null,
                    yi,
                    ue.description &&
                      React.createElement("small", null, ue.description),
                  ),
                );
              }),
              A.isOther !== false && React.createElement(
                "button",
                {
                  type: "button",
                  role: A.multiSelect ? "checkbox" : "radio",
                  "aria-checked": rt.includes("__other__"),
                  className: `question-option ${rt.includes("__other__") ? "selected" : ""}`,
                  disabled: !d || i || o,
                  onClick: () => M(V, "__other__", A.multiSelect),
                },
                React.createElement("span", {
                  className: "radio-outline",
                }),
                React.createElement(
                  "span",
                  null,
                  e("\u5176\u4ED6\u56DE\u7B54", "Other answer"),
                ),
              ),
              rt.includes("__other__") &&
                React.createElement("textarea", {
                  className: "question-free-text",
                  "aria-label": e(
                    "\u586B\u5199\u5176\u4ED6\u56DE\u7B54",
                    "Enter another answer",
                  ),
                  value: p[V] || "",
                  disabled: !d || i || o,
                  onChange: (ue) =>
                    w((yo) => ({ ...yo, [V]: ue.target.value })),
                }),
            );
          }),
        ),
    r && React.createElement(Notice, { tone: "warning" }, r),
    (o || n.submitted)
      ? React.createElement(
          Notice,
          { icon: "check" },
          e(
            "\u51B3\u5B9A\u5DF2\u63D0\u4EA4\uFF0C\u7B49\u5F85\u5BA2\u6237\u7AEF\u72B6\u6001\u66F4\u65B0\u3002",
            "Decision submitted. Waiting for the client state to update.",
          ),
        )
      : d
        ? React.createElement(
            React.Fragment,
            null,
            React.createElement(
              "p",
              { className: "approval-scope-note" },
              n.kind === "question"
                ? e(
                    "\u56DE\u7B54\u4F1A\u53D1\u9001\u7ED9\u6B64\u8BF7\u6C42\u7684\u539F\u59CB\u5BA2\u6237\u7AEF\u3002",
                    "Answers will be sent to the client that owns this request.",
                  )
                : e(
                    "\u5355\u6B21\u5141\u8BB8\u4EC5\u7528\u4E8E\u6B64\u8BF7\u6C42\u3002\u4F1A\u8BDD\u6216\u6301\u7EED\u6388\u6743\u9700\u8981\u518D\u6B21\u786E\u8BA4\u5177\u4F53\u8303\u56F4\u3002",
                    "Allow once applies only to this request. Session or persistent grants require a separate scope confirmation.",
                  ),
            ),
            React.createElement(
              "div",
              { className: "approval-actions" },
              n.kind === "question"
                ? React.createElement(
                    "button",
                    {
                      className: "primary-button",
                      disabled: i || l.settings.privacy || !C,
                      onClick: nt,
                    },
                    i
                      ? e("\u6B63\u5728\u63D0\u4EA4\u2026", "Submitting\u2026")
                      : e("\u63D0\u4EA4\u56DE\u7B54", "Send answers"),
                  )
                : h
                    .filter((A) => x[A])
                    .map((A) =>
                      React.createElement(
                        "button",
                        {
                          key: A,
                          className: ["accept", "allow"].includes(A)
                            ? "primary-button"
                            : "",
                          disabled:
                            i ||
                            (l.settings.privacy &&
                              !["decline", "deny", "cancel"].includes(A)),
                          onClick: () =>
                            ["acceptForSession", "acceptAlways"].includes(A)
                              ? D(A)
                              : T(A),
                        },
                        x[A],
                      ),
                    ),
            ),
          )
        : React.createElement(
            Notice,
            { tone: "warning" },
            e(
              "\u6B64\u8BF7\u6C42\u4E3A\u53EA\u8BFB\u540C\u6B65\u3002\u8BF7\u8FD4\u56DE\u539F\u5BA2\u6237\u7AEF\u5904\u7406\uFF1BQuotaView \u4E0D\u4F1A\u5047\u88C5\u5DF2\u6279\u51C6\u3002",
              "This is a read-only request. Respond in the originating client; QuotaView cannot approve it.",
            ),
          ),
    N &&
      React.createElement(
        ConfirmationDialog,
        {
          title: x[N],
          confirmLabel: e(
            "\u786E\u8BA4\u6B64\u6388\u6743\u8303\u56F4",
            "Confirm this scope",
          ),
          onClose: () => D(null),
          onConfirm: () => T(N),
        },
        React.createElement(
          "p",
          null,
          N === "acceptAlways"
            ? e(
                "\u8FD9\u4F1A\u4FDD\u5B58\u6301\u7EED\u6743\u9650\uFF0C\u672A\u6765\u7B26\u5408\u6B64\u8303\u56F4\u7684\u8BF7\u6C42\u53EF\u80FD\u4E0D\u518D\u8BE2\u95EE\u3002",
                "This saves persistent permission. Future requests within this scope may not ask again.",
              )
            : e(
                "\u6B64\u4F1A\u8BDD\u5185\u7B26\u5408\u6B64\u8303\u56F4\u7684\u8BF7\u6C42\u53EF\u80FD\u4E0D\u518D\u8BE2\u95EE\u3002",
                "Requests within this scope may no longer ask during this session.",
              ),
        ),
        React.createElement(
          "pre",
          null,
          plainText(n.scope || n.command || n.title),
        ),
      ),
  );
}
function TaskDetail({ task: t, childrenTasks: e, depth: a = 0 }) {
  let { snapshot: l, t: n, invoke: i, locale: u } = useApp(),
    o = taskProgress(t),
    c = l.settings.privacy,
    [r, g] = React.useState(null);
  const childAttention = e?.find(needsAttention)?.id;
  React.useEffect(() => {
    if (childAttention) g(childAttention);
  }, [childAttention]);
  return React.createElement(
    "div",
    { className: `task-detail status-${window.QVEffects.displayState(t)}` },
    React.createElement(
      "div",
      { className: "task-detail-toolbar" },
      React.createElement(ConnectionDot, { provider: t.provider }),
      React.createElement(
        "span",
        null,
        t.verified === !1 && t.status === "completed"
          ? n(
              "\u5B8C\u6210\u72B6\u6001\u672A\u9A8C\u8BC1",
              "Completion unverified",
            )
          : statusLabel(window.QVEffects.displayState(t), n),
      ),
    ),
    t.verified === !1 &&
      t.status === "completed" &&
      React.createElement(
        Notice,
        { tone: "warning" },
        n(
          "\u6765\u6E90\u6CA1\u6709\u9A8C\u8BC1\u6B64\u5B8C\u6210\u72B6\u6001\uFF0C\u8FDB\u5EA6\u4E0D\u4F1A\u663E\u793A\u4E3A 100%\u3002",
          "This completion is not verified by the source. Progress will not show 100%.",
        ),
      ),
    t.approval
      ? React.createElement(ApprovalCard, { task: t })
      : c
        ? React.createElement(
            EmptyState,
            {
              icon: "eyeOff",
              title: n(
                "\u4EFB\u52A1\u5185\u5BB9\u5DF2\u9690\u85CF",
                "Task details are hidden",
              ),
            },
            n(
              "\u5173\u95ED\u9690\u79C1\u6A21\u5F0F\u4EE5\u67E5\u770B\u516C\u5F00\u8FDB\u5C55\u548C\u5B8C\u6210\u7ED3\u679C\u3002",
              "Turn off privacy mode to view public progress and results.",
            ),
          )
        : React.createElement(
            React.Fragment,
            null,
            React.createElement(
              "div",
              { className: "detail-heading" },
              React.createElement(Icon, {
                name:
                  t.status === "completed"
                    ? "check"
                    : t.status === "failed"
                      ? "warning"
                      : "file",
              }),
              React.createElement(
                "h3",
                null,
                t.status === "completed"
                  ? n("\u5B8C\u6210\u7ED3\u679C", "Result")
                  : t.status === "failed"
                    ? n("\u6267\u884C\u5931\u8D25", "Execution failed")
                    : n(
                        "\u516C\u5F00\u4EFB\u52A1\u8FDB\u5C55",
                        "Public progress",
                      ),
              ),
            ),
            (t.status === "completed" && t.result) || t.publicText
              ? React.createElement(Markdown, {
                  text: plainText(
                    (t.status === "completed" && t.result) || t.publicText,
                  ),
                })
              : React.createElement(
                  "p",
                  { className: "detail-empty" },
                  t.status === "completed"
                    ? n(
                        "\u5DF2\u6536\u5230\u5B8C\u6210\u4E8B\u4EF6\uFF0C\u4F46\u6CA1\u6709\u53EF\u7528\u7684\u516C\u5F00\u7ED3\u679C\u3002",
                        "A completion event was received, but no public result is available.",
                      )
                    : n(
                        "\u5C1A\u672A\u6536\u5230\u53EF\u663E\u793A\u7684\u516C\u5F00\u8FDB\u5C55\u3002\u4EFB\u52A1\u72B6\u6001\u4E0D\u4F1A\u6839\u636E\u9759\u9ED8\u63A8\u65AD\u4E3A\u5B8C\u6210\u3002",
                        "No public progress is available yet. Silence is never treated as completion.",
                      ),
                ),
            t.tool &&
              React.createElement(
                "div",
                { className: "command-card" },
                React.createElement(
                  "span",
                  { className: "eyebrow" },
                  n(
                    "\u6700\u8FD1\u7684\u5DE5\u5177\u6D3B\u52A8",
                    "Latest tool activity",
                  ),
                ),
                React.createElement("pre", null, plainText(t.tool)),
              ),
            Array.isArray(t.progress?.steps) &&
              t.progress.steps.length > 0 &&
              React.createElement(
                "div",
                { className: "plan-section" },
                React.createElement(
                  "div",
                  { className: "card-title-line" },
                  React.createElement(
                    "h4",
                    null,
                    n("\u7ED3\u6784\u5316\u8BA1\u5212", "Structured plan"),
                  ),
                  React.createElement(
                    "span",
                    null,
                    formatNumber(t.progress.completed, u),
                    " / ",
                    formatNumber(t.progress.total, u),
                  ),
                ),
                t.progress.steps.map((m, f) =>
                  React.createElement(
                    "div",
                    { key: f, className: `plan-step ${m.status || ""}` },
                    React.createElement(
                      "span",
                      null,
                      ["completed", "done"].includes(m.status)
                        ? React.createElement(Icon, {
                            name: "check",
                            size: 12,
                          })
                        : ["in_progress", "working"].includes(m.status)
                          ? React.createElement("i", {
                              className: "working-dot",
                            })
                          : React.createElement("span", {
                              className: "plan-circle",
                            }),
                    ),
                    React.createElement(
                      "span",
                      null,
                      m.text ||
                        m.step ||
                        n("\u672A\u547D\u540D\u6B65\u9AA4", "Untitled step"),
                    ),
                  ),
                ),
                o.known &&
                  React.createElement(
                    "div",
                    {
                      className: "plan-progress",
                      role: "progressbar",
                      "aria-label": n(
                        "\u8BA1\u5212\u8FDB\u5EA6",
                        "Plan progress",
                      ),
                      "aria-valuemin": 0,
                      "aria-valuemax": 100,
                      "aria-valuenow": Math.round(o.percent),
                    },
                    React.createElement("i", {
                      style: { width: `${o.percent}%` },
                    }),
                  ),
                React.createElement(
                  "p",
                  { className: "chart-note" },
                  n(
                    "\u8FDB\u5EA6\u6765\u81EA\u771F\u5B9E\u8BA1\u5212\uFF1B\u53EA\u6709\u5DF2\u9A8C\u8BC1\u7684\u5B8C\u6210\u4E8B\u4EF6\u624D\u80FD\u663E\u793A 100%\u3002",
                    "Progress comes from the plan. Only a verified completion event can reach 100%.",
                  ),
                ),
              ),
          ),
    !c &&
      t.cwd &&
      React.createElement(
        "button",
        {
          className: "path-button",
          title: t.cwd,
          onClick: () => i("openPath", t.cwd),
        },
        React.createElement(Icon, { name: "folder", size: 13 }),
        React.createElement("span", null, t.cwd),
        React.createElement(Icon, { name: "external", size: 11 }),
      ),
    e?.length > 0 &&
      React.createElement(
        "div",
        { className: "subagent-section" },
        React.createElement(
          "h4",
          null,
          n("\u5B50\u4EFB\u52A1", "Subagents"),
          React.createElement("span", null, e.length),
        ),
        e.map((m) =>
          React.createElement(
            "div",
            { className: "subagent-stack", key: m.id },
            React.createElement(
              "button",
              {
                className: `subagent-row status-${window.QVEffects.displayState(m)}`,
                onClick: () => g(r === m.id ? null : m.id),
                "aria-expanded": r === m.id,
              },
              React.createElement(StatusOrb, {
                status: window.QVEffects.displayState(m),
                small: !0,
                task: m,
              }),
              React.createElement(
                "span",
                null,
                React.createElement(
                  "strong",
                  null,
                  c
                    ? n("\u5B50\u4EFB\u52A1", "Subagent")
                    : m.title ||
                        n(
                          "\u672A\u547D\u540D\u5B50\u4EFB\u52A1",
                          "Untitled subagent",
                        ),
                ),
                React.createElement(
                  "small",
                  null,
                  statusLabel(window.QVEffects.displayState(m), n),
                  !c && m.model ? ` \xB7 ${m.model}` : "",
                ),
              ),
              React.createElement(
                "span",
                { className: "subagent-count" },
                c
                  ? "\u2022\u2022\u2022"
                  : isFiniteNumber(m.tokens?.total)
                    ? `${formatNumber(m.tokens.total, u, !0)}`
                    : taskProgress(m).known
                      ? `${Math.round(taskProgress(m).percent)}%`
                      : "\u2014",
              ),
              React.createElement(Icon, {
                name: r === m.id ? "up" : "down",
                size: 10,
              }),
            ),
            r === m.id &&
              React.createElement(TaskDetail, {
                task: m,
                depth: a + 1,
                childrenTasks:
                  a < 3
                    ? l.tasks.filter(
                        (f) => f.parentId === m.id && f.id !== t.id,
                      )
                    : [],
              }),
          ),
        ),
      ),
    ["completed", "failed", "interrupted"].includes(t.status) &&
      !t.approval &&
      React.createElement(
        "button",
        {
          className: "dismiss-task",
          onClick: () => i("dismissTask", { id: t.id }),
        },
        React.createElement(Icon, { name: "close", size: 11 }),
        n(
          "\u4ECE\u7075\u52A8\u5C9B\u79FB\u9664\uFF08\u4FDD\u7559\u539F\u59CB\u4F1A\u8BDD\uFF09",
          "Dismiss from Island (keep original session)",
        ),
      ),
  );
}
function IslandView() {
  let { snapshot: t, t: e, invoke: a, busy: l } = useApp(),
    [n, i] = React.useState(!!t.ui?.expanded),
    [u, o] = React.useState("tasks"),
    [c, r] = React.useState(null),
    [focusedTaskId, setFocusedTaskId] = React.useState(null),
    f = React.useRef(null),
    [p, w] = React.useState(!!t.ui?.pinned),
    N = React.useRef(null),
    hoverOpen = React.useRef(null),
    pointerInside = React.useRef(false),
    seenAttention = React.useRef(new Set()),
    suppressHover = React.useRef(false),
    interactionState = React.useRef(null),
    D = React.useRef(""),
    v = React.useRef(t.ui?.expanded),
    d = t.tasks,
    h = d
      .filter((O) => !O.parentId || !d.some((V) => V.id === O.parentId))
      .sort((O, V) => +needsAttention(V) - +needsAttention(O)),
    x = h.filter((O) =>
      ["thinking", "working", "compacting"].includes(
        window.QVEffects.displayState(O),
      ),
    ),
    T = d.filter(needsAttention),
    M = h[0],
    focusedId = h.find((task) => task.id === focusedTaskId)?.id ?? M?.id;
  interactionState.current = { pinned: p, pending: T.length };
  (React.useEffect(() => {
    t.ui?.expanded !== void 0 &&
      t.ui.expanded !== v.current &&
      ((v.current = t.ui.expanded), i(t.ui.expanded));
  }, [t.ui?.expanded]),
    React.useEffect(() => {
      typeof t.ui?.pinned == "boolean" && w(t.ui.pinned);
    }, [t.ui?.pinned]));
  React.useEffect(() => {
    const pending = d.filter(needsAttention);
    const fresh = pending.find(
      (task) => !seenAttention.current.has(attentionKey(task)),
    );
    seenAttention.current = new Set(pending.map(attentionKey));
    if (!fresh || !t.settings.autoExpand) return;
    // Keep an already open request stable while the user reads or answers it.
    if (n && u === "tasks" && pending.some((task) => task.id === c)) return;
    let target = fresh;
    const visited = new Set();
    while (target.parentId && !visited.has(target.id)) {
      visited.add(target.id);
      const parent = d.find((task) => task.id === target.parentId);
      if (!parent) break;
      target = parent;
    }
    clearTimeout(N.current);
    clearTimeout(hoverOpen.current);
    suppressHover.current = false;
    setFocusedTaskId(target.id);
    r(target.id);
    o("tasks");
    i(true);
  }, [d, t.settings.autoExpand]);
  let E = (O) => {
      setFocusedTaskId(O);
      r((V) => (V === O ? null : O));
    },
    C = (O) => {
      clearTimeout(hoverOpen.current);
      clearTimeout(N.current);
      if (!O) {
        suppressHover.current = pointerInside.current;
        w(false);
      }
      (i(O), O || (o("tasks"), r(null)));
    };
  (React.useLayoutEffect(() => {
    if (!f.current) return;
    let O = () => {
        let rt = n
            ? Math.ceil(
                f.current.querySelector(".island-shell")?.scrollHeight || 172,
              ) + 8
            : 46,
          ue = `${n}:${rt}`;
        D.current !== ue &&
          ((D.current = ue), a("resize", { expanded: n, height: rt }));
      },
      V = new ResizeObserver(O);
    return (V.observe(f.current), O(), () => V.disconnect());
  }, [n, u, c, t.settings.islandWidth, t.tasks, t.quotas, t.usage]),
    React.useEffect(
      () => () => {
        clearTimeout(N.current);
        clearTimeout(hoverOpen.current);
      },
      [],
    ));
  function nt() {
    clearTimeout(N.current);
    n &&
      (N.current = setTimeout(() => {
        if (
          !pointerInside.current &&
          !interactionState.current.pinned &&
          !interactionState.current.pending &&
          !f.current?.querySelector("input:focus,textarea:focus,select:focus")
        )
          C(false);
      }, 450));
  }
  let A = T.length
    ? e(`${T.length} \u5F85\u786E\u8BA4`, `${T.length} need confirmation`)
    : x.length
      ? e(`${x.length} \u6B63\u5728\u8FDB\u884C`, `${x.length} active`)
      : h.length
        ? e(
            "\u6682\u65E0\u8FD0\u884C\u4E2D\u7684\u4EFB\u52A1",
            "No active tasks",
          )
        : e("\u7B49\u5F85\u4EFB\u52A1", "Waiting for tasks");
  return React.createElement(
    "main",
    {
      className: `island-window ${n ? "expanded" : "collapsed"}`,
      style: {
        "--island-width": t.settings.islandWidth + "px",
        "--body-max-height":
          Math.max(160, Math.min(650, window.screen.availHeight - 190)) + "px",
      },
      onMouseEnter: () => {
        pointerInside.current = true;
        (clearTimeout(N.current), a("resize", { expanded: n, hovered: !0 }));
        if (!n && !suppressHover.current) {
          clearTimeout(hoverOpen.current);
          hoverOpen.current = setTimeout(() => {
            if (pointerInside.current && !suppressHover.current) C(true);
          }, 150);
        }
      },
      onMouseLeave: () => {
        pointerInside.current = false;
        suppressHover.current = false;
        clearTimeout(hoverOpen.current);
        (a("resize", { expanded: n, hovered: !1 }), nt());
      },
      onKeyDown: (O) => {
        O.key === "Escape" &&
          (u !== "tasks" ? o("tasks") : c ? r(null) : C(!1));
      },
    },
    React.createElement(
      "div",
      { ref: f, className: "island-measure" },
      React.createElement(
        "section",
        {
          className: `island-shell ${T.length ? "has-approval" : ""}`,
        },
        n
          ? React.createElement(
              React.Fragment,
              null,
              React.createElement(
                "header",
                { className: "island-header" },
                u === "tasks"
                  ? React.createElement(QuotaCapsule, {
                      compact: !0,
                      onClick: () => o("usage"),
                    })
                  : React.createElement(
                      "button",
                      {
                        className: "back-button",
                        onClick: () => o("tasks"),
                      },
                      React.createElement(Icon, { name: "back", size: 11 }),
                      e("\u8FD4\u56DE\u4EFB\u52A1", "Back to tasks"),
                    ),
                React.createElement(
                  "div",
                  { className: "island-header-right" },
                  React.createElement(
                    "span",
                    {
                      className: `header-status ${T.length ? "warning" : ""}`,
                    },
                    u === "usage"
                      ? e("\u7528\u91CF\u7EDF\u8BA1", "Usage statistics")
                      : T.length
                        ? e(
                            `${T.length} \u5F85\u786E\u8BA4`,
                            `${T.length} pending`,
                          )
                        : "",
                  ),
                  React.createElement(IconButton, {
                    icon: "pin",
                    label: p
                      ? e("\u53D6\u6D88\u56FA\u5B9A", "Unpin")
                      : e("\u56FA\u5B9A\u5C55\u5F00", "Pin open"),
                    active: p,
                    onClick: () => {
                      (w(!p), a("resize", { expanded: n, pinned: !p }));
                    },
                  }),
                  React.createElement(IconButton, {
                    icon: "up",
                    label: e("\u6536\u8D77", "Collapse"),
                    onClick: () => C(!1),
                  }),
                ),
              ),
              React.createElement(
                "div",
                { className: `island-body page-${u}` },
                u === "tasks"
                  ? h.length
                    ? React.createElement(
                        "div",
                        { className: "task-list" },
                        h.map((O) =>
                          React.createElement(
                            "div",
                            { key: O.id, className: "task-stack" },
                            React.createElement(TaskCard, {
                              task: O,
                              selected: c === O.id,
                              focused: focusedId === O.id,
                              onSelect: () => E(O.id),
                            }),
                            c === O.id &&
                              React.createElement(TaskDetail, {
                                task: O,
                                childrenTasks: d.filter(
                                  (V) => V.parentId === O.id,
                                ),
                              }),
                          ),
                        ),
                      )
                    : React.createElement(
                        EmptyState,
                        {
                          title: e(
                            "\u4E13\u6CE8\u5F53\u4E0B\uFF0C\u4F59\u91CF\u5C3D\u5728\u638C\u63E1",
                            "Focus on the work. Know your limits.",
                          ),
                          action: React.createElement(
                            "button",
                            {
                              className: "primary-button",
                              onClick: () => a("openSettings"),
                            },
                            e("\u8FDE\u63A5 Agent", "Connect an agent"),
                          ),
                        },
                        e(
                          "\u8FDE\u63A5 Codex\u3001Claude Code\u3001DSH \u6216 Kimi Code\u3002\u771F\u5B9E\u4EFB\u52A1\u51FA\u73B0\u540E\uFF0C\u8FDB\u5C55\u4F1A\u663E\u793A\u5728\u8FD9\u91CC\u3002",
                          "Connect Codex, Claude Code, DSH or Kimi Code. Real task activity will appear here.",
                        ),
                      )
                  : React.createElement(UsageView, {}),
              ),
              React.createElement(
                "footer",
                { className: "island-footer" },
                React.createElement(
                  "span",
                  { className: "session-count" },
                  u === "tasks"
                    ? e(
                        `${h.length} \u4E2A\u4F1A\u8BDD`,
                        `${h.length} sessions`,
                      )
                    : Object.values(t.quotas || {}).some((q) => q?.updatedAt)
                      ? e("更新于 ", "Updated ") +
                        new Date(
                          Math.max(
                            ...Object.values(t.quotas || {}).map(
                              (q) => q?.updatedAt || 0,
                            ),
                          ),
                        ).toLocaleTimeString(undefined, {
                          hour: "2-digit",
                          minute: "2-digit",
                        })
                      : e("\u672C\u5730\u6570\u636E", "Local data"),
                ),
                React.createElement(
                  "div",
                  { className: "island-footer-right" },
                  t.backgroundTasks?.some((O) =>
                    ["thinking", "working", "compacting"].includes(O.status),
                  ) &&
                    React.createElement(
                      "span",
                      {
                        className: "background-status",
                        title: e(
                          "\u540E\u53F0\u8BB0\u5FC6\u6574\u7406\uFF0C\u4E0D\u8BA1\u5165\u7528\u6237\u4EFB\u52A1\u7EDF\u8BA1",
                          "Background memory work, excluded from user task statistics",
                        ),
                      },
                      React.createElement(StatusOrb, {
                        status: "thinking",
                        small: !0,
                      }),
                      e("\u540E\u53F0", "Background"),
                    ),
                  React.createElement(
                    "span",
                    { className: "footer-summary" },
                    u === "tasks" ? A : "",
                  ),
                  React.createElement(IconButton, {
                    icon: "refresh",
                    className: l.refresh ? "spinning" : "",
                    disabled: l.refresh,
                    label: e("\u5237\u65B0", "Refresh"),
                    onClick: () => a("refresh"),
                  }),
                  React.createElement(IconButton, {
                    icon: "settings",
                    label: e("\u8BBE\u7F6E", "Settings"),
                    onClick: () => a("openSettings"),
                  }),
                ),
              ),
            )
          : React.createElement(
              "button",
              {
                className: "collapsed-content",
                onClick: () => C(!0),
                "aria-label": e(
                  "\u5C55\u5F00 QuotaView \u7075\u52A8\u5C9B",
                  "Expand QuotaView Island",
                ),
                "aria-expanded": "false",
              },
              React.createElement(StatusOrb, {
                status: T.length
                  ? "waiting"
                  : window.QVEffects.displayState(x[0] || M),
                small: !0,
              }),
              React.createElement(
                "span",
                { className: "compact-title" },
                T.length
                  ? e(
                      `${T.length} \u9879\u5F85\u786E\u8BA4`,
                      `${T.length} pending`,
                    )
                  : x.length
                    ? e(
                        `${x.length} \u4E2A\u4EFB\u52A1\u8FDB\u884C\u4E2D`,
                        `${x.length} active tasks`,
                      )
                    : "QuotaView",
              ),
              React.createElement(
                "span",
                { className: `compact-status ${T.length ? "warning" : ""}` },
                T.length
                  ? React.createElement(Icon, { name: "shield", size: 13 })
                  : React.createElement(ProviderIcon, {
                      provider: x[0]?.provider || M?.provider || "codex",
                      size: 14,
                    }),
              ),
            ),
      ),
    ),
  );
}

export { StatusOrb, TaskCard, ApprovalCard, TaskDetail, IslandView };
