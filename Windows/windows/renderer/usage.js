import { React } from "./react.js";
import {
  isFiniteNumber,
  formatNumber,
  formatCurrency,
  remainingQuota,
  sumKnown,
  formatCountdown,
  quotaWindows,
  taskLabel,
  creditValue,
  dayKey,
  filterDays,
  Icon,
  ProviderIcon,
  Notice,
  EmptyState,
  QuotaRing,
  PROVIDER_LABELS,
  useApp,
} from "./common.js";
function QuotaCapsule({ compact: t = !1, onClick: e }) {
  let { snapshot: a, t: l, now: n } = useApp(),
    { settings: i } = a,
    u =
      Object.keys(a.quotas).find((g) => g === "codex" && a.quotas[g]) ||
      Object.keys(a.quotas).find((g) => a.quotas[g]),
    o = a.quotas[u],
    c = quotaWindows(o)
      .filter((g) => !/spark/i.test(g.limitId || g.name || ""))
      .slice(0, t ? 1 : 2),
    r = i.privacy
      ? React.createElement(
          React.Fragment,
          null,
          React.createElement(Icon, { name: "eyeOff", size: 13 }),
          React.createElement(
            "span",
            null,
            l("\u9690\u79C1\u6A21\u5F0F", "Privacy mode"),
          ),
        )
      : c.length
        ? c.map((g, m) => {
            let f = remainingQuota(g);
            return React.createElement(
              React.Fragment,
              { key: g.name || m },
              m > 0 &&
                React.createElement("i", {
                  className: "capsule-divider",
                }),
              React.createElement(
                "span",
                { className: "capsule-window" },
                React.createElement(QuotaRing, { value: f }),
                !t &&
                  React.createElement(
                    "span",
                    { className: "capsule-window-name" },
                    taskLabel(g, l),
                  ),
                i.showRemainingQuota &&
                  React.createElement(
                    "strong",
                    null,
                    f === null ? "\u2014" : `${Math.round(f)}%`,
                  ),
                React.createElement(
                  React.Fragment,
                  null,
                  i.showResetCountdown &&
                    React.createElement(
                      "span",
                      { className: "capsule-reset" },
                      formatCountdown(g.resetAt, n, l),
                      !t && isFiniteNumber(g.resetAt) && g.resetAt > n
                        ? l("\u91CD\u7F6E", " reset")
                        : "",
                    ),
                ),
              ),
            );
          })
        : React.createElement(
            React.Fragment,
            null,
            React.createElement(QuotaRing, { value: null }),
            React.createElement(
              "span",
              null,
              l("\u989D\u5EA6\u672A\u77E5", "Quota unavailable"),
            ),
          );
  return e
    ? React.createElement(
        "button",
        {
          type: "button",
          className: `quota-capsule ${t ? "compact" : ""} ${o?.error ? "stale" : ""}`,
          title:
            o?.error ||
            l("\u67E5\u770B\u7528\u91CF\u7EDF\u8BA1", "View usage statistics"),
          onClick: e,
        },
        r,
      )
    : React.createElement(
        "div",
        { className: `quota-capsule ${t ? "compact" : ""}` },
        r,
      );
}

export { QuotaCapsule };
export { UsageDashboard as UsageView } from "./usage-dashboard.js";
