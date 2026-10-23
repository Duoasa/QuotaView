import { React } from "./react.js";
import {
  useApp,
  isFiniteNumber,
  formatNumber,
  formatCurrency,
  remainingQuota,
  formatCountdown,
  quotaWindows,
  taskLabel,
  creditValue,
  filterDays,
  dayKey,
  sumKnown,
  ProviderIcon,
  PROVIDER_LABELS,
  Notice,
} from "./common.js";
const h = React.createElement;

// Missing dates stay unknown. Account totals and local cost records are never added together.
export function calendarDays(records, count, now) {
  const byDate = new Map(
    (Array.isArray(records) ? records : []).map((day) => [day.date, day]),
  );
  return Array.from({ length: count }, (_, index) => {
    const date = new Date(now);
    date.setDate(date.getDate() - count + 1 + index);
    const key = dayKey(date);
    return byDate.get(key) || { date: key, total: null, cost: null };
  });
}

function QuotaCard({ item, stale }) {
  const { t, now, snapshot } = useApp();
  const value = remainingQuota(item),
    privacy = snapshot.settings.privacy;
  const reset = isFiniteNumber(item.resetAt)
    ? t(
        formatCountdown(item.resetAt, now, t) + "重置",
        "Resets in " + formatCountdown(item.resetAt, now, t),
      )
    : "—";
  return h(
    "article",
    { className: "data-card quota-card " + (stale ? "stale-data" : "") },
    h(
      "div",
      { className: "card-title-line" },
      h("span", null, taskLabel(item, t)),
      h(
        "span",
        {
          title: privacy
            ? ""
            : isFiniteNumber(item.resetAt)
              ? new Date(item.resetAt).toLocaleString()
              : "",
        },
        privacy ? "—" : reset,
      ),
    ),
    h(
      "div",
      { className: "quota-value" },
      h(
        "strong",
        null,
        privacy ? "•••" : value === null ? "—" : Math.round(value) + "%",
      ),
      h(
        "span",
        null,
        privacy
          ? ""
          : value === null
            ? t("额度未知", "Unavailable")
            : t(
                "已使用 " + Math.round(100 - value) + "%",
                "Used " + Math.round(100 - value) + "%",
              ),
      ),
    ),
    h(
      "div",
      {
        className: "quota-bar",
        role: "progressbar",
        "aria-label": t("剩余额度", "Remaining quota"),
        "aria-valuemin": 0,
        "aria-valuemax": 100,
        "aria-valuenow": privacy || value === null ? undefined : value,
      },
      h("span", {
        className: value <= 10 ? "danger" : value <= 30 ? "warning" : "",
        style: { width: (privacy || value === null ? 0 : value) + "%" },
      }),
    ),
  );
}

function CostCard({ days }) {
  const { t, locale, now, snapshot } = useApp();
  const visible = calendarDays(days, 30, now),
    available = filterDays(days, 30, now),
    latest = available.at(-1);
  const maximum = Math.max(
    1,
    ...visible.map((day) => (isFiniteNumber(day.cost) ? day.cost : 0)),
  );
  const money = (value) =>
    snapshot.settings.privacy ? "•••" : formatCurrency(value, locale);
  return h(
    "section",
    { className: "data-card cost-bento" },
    h(
      "div",
      { className: "cost-total" },
      h("span", null, t("成本估算", "Cost estimate")),
      h("strong", null, money(sumKnown(available, "cost"))),
      h("small", null, t("最近 30 天", "Last 30 days")),
    ),
    h(
      "div",
      {
        className: "cost-bars",
        "aria-label": t("每日估算成本", "Daily estimated cost"),
      },
      ...visible.map((day) =>
        h(
          "div",
          {
            key: day.date,
            className: "cost-bar-slot",
            title: snapshot.settings.privacy
              ? ""
              : day.date + " · " + formatCurrency(day.cost, locale),
          },
          h("i", {
            className: isFiniteNumber(day.cost) ? "" : "missing",
            style: {
              height: snapshot.settings.privacy
                ? "0%"
                : isFiniteNumber(day.cost)
                  ? Math.max(2, (day.cost / maximum) * 100) + "%"
                  : "2px",
            },
          }),
        ),
      ),
    ),
    h(
      "div",
      { className: "cost-latest", title: latest?.date },
      h("span", null, t("最近一天", "Latest day")),
      h("strong", null, money(latest?.cost)),
      h("small", null, t("估算值 · 非账单", "Estimate · not a bill")),
    ),
  );
}

function Activity({ days, lifetimeTokens }) {
  const { t, locale, now, snapshot } = useApp();
  const [mode, setMode] = React.useState("daily"),
    [selected, setSelected] = React.useState(null);
  const today = new Date(now);
  today.setUTCHours(0, 0, 0, 0);
  const start = new Date(today);
  start.setUTCDate(start.getUTCDate() - start.getUTCDay() - 364);
  const values = new Map(days.map((d) => [d.date, d.total]));
  const daily = Array.from({ length: 371 }, (_, i) => {
    const date = new Date(+start + i * 86400000);
    const key = date.toISOString().slice(0, 10);
    return { date: key, total: values.get(key) ?? null, future: date > today };
  });
  const windowTotal = daily.reduce(
    (s, d) => s + (d.future ? 0 : d.total || 0),
    0,
  );
  let running = isFiniteNumber(lifetimeTokens)
    ? Math.max(0, lifetimeTokens - windowTotal)
    : days
        .filter((d) => d.date < daily[0].date)
        .reduce((s, d) => s + (d.total || 0), 0);
  let hasData = running > 0;
  const weeks = Array.from({ length: 53 }, (_, i) => {
    const week = daily.slice(i * 7, i * 7 + 7),
      known = week.filter((d) => !d.future && isFiniteNumber(d.total));
    const total = known.reduce((s, d) => s + d.total, 0);
    if (known.length) hasData = true;
    running += total;
    return {
      date: week[0].date,
      total:
        mode === "weekly"
          ? known.length
            ? total
            : null
          : hasData
            ? running
            : null,
    };
  });
  const data = mode === "daily" ? daily : weeks;
  const maximum = Math.max(
    1,
    ...data.map((d) => (d.future ? 0 : d.total || 0)),
  );
  const months = [];
  for (let col = 0; col < 53; col++) {
    const date = daily[col * 7].date;
    if (!col || date.slice(0, 7) !== daily[(col - 1) * 7].date.slice(0, 7)) {
      if (months.length && col - months.at(-1).col < 3) months.pop();
      months.push({ col, date });
    }
  }
  const describe = (d) =>
    d.date + " · " + formatNumber(d.total, locale) + " tokens";
  return h(
    "section",
    { className: "data-card activity-bento" },
    h(
      "div",
      { className: "card-title-line" },
      h("span", null, t("Token 活动", "Token activity")),
      selected &&
        h("span", { className: "activity-selection" }, describe(selected)),
      h(
        "div",
        {
          className: "activity-mode",
          role: "group",
          "aria-label": t("活动范围", "Activity mode"),
        },
        ...["daily", "weekly", "cumulative"].map((v, i) =>
          h(
            "button",
            {
              key: v,
              "aria-pressed": mode === v,
              className: mode === v ? "selected" : "",
              onClick: () => {
                setMode(v);
                setSelected(null);
              },
            },
            t(["每天", "每周", "累计总量"][i], ["Daily", "Weekly", "Total"][i]),
          ),
        ),
      ),
    ),
    snapshot.settings.privacy
      ? h("p", { className: "muted" }, t("数据已隐藏", "Data hidden"))
      : h(
          "div",
          { className: "activity-scroll" },
          h(
            "div",
            { className: "activity-plot" },
            h(
              "div",
              { className: "activity-grid mode-" + mode },
              ...Array.from({ length: 371 }, (_, i) => {
                const col = Math.floor(i / 7),
                  row = i % 7,
                  d = mode === "daily" ? daily[i] : weeks[col];
                const filled =
                  d.total > 0 &&
                  row >= 7 - Math.max(1, Math.ceil((d.total / maximum) * 7));
                const level = !d.total ? 0 : d.total / maximum;
                const color =
                  mode !== "daily"
                    ? filled
                      ? "#0787eb"
                      : "#303030"
                    : !level
                      ? "#303030"
                      : level < 0.25
                        ? "#173e68"
                        : level < 0.5
                          ? "#235b99"
                          : level < 0.75
                            ? "#3889ed"
                            : "#80baff";
                return h("button", {
                  key: i,
                  className:
                    "activity-cell" +
                    (mode === "daily" && selected?.date === d.date
                      ? " selected"
                      : ""),
                  disabled: !!d.future,
                  style: {
                    background: color,
                    visibility: d.future ? "hidden" : "visible",
                  },
                  title: describe(d),
                  "aria-label": describe(d),
                  onClick: () => setSelected(d),
                });
              }),
            ),
            h(
              "div",
              { className: "activity-months" },
              ...months.map((m) =>
                h(
                  "span",
                  { key: m.date, style: { left: (m.col / 53) * 100 + "%" } },
                  new Date(m.date + "T12:00:00Z").toLocaleDateString(locale, {
                    month: "short",
                    timeZone: "UTC",
                  }),
                ),
              ),
            ),
          ),
        ),
  );
}

export function UsageDashboard() {
  const { snapshot, t, locale, now } = useApp();
  const [provider, setProvider] = React.useState("codex");
  const settings = snapshot.settings,
    quota = snapshot.quotas[provider],
    usage = snapshot.usage[provider];
  const windows = quotaWindows(quota);
  const cards = windows.length
    ? windows
    : [
        { name: t("5 小时额度", "5-hour quota"), windowMinutes: 300 },
        { name: t("每周额度", "Weekly quota"), windowMinutes: 10080 },
      ];
  const days = filterDays(usage?.days, 36500, now),
    month = filterDays(days, 30, now),
    latest = days.at(-1);
  const lifetime = isFiniteNumber(usage?.summary?.lifetimeTokens);
  const providers = [
    "codex",
    "claude",
    ...["dsh", "kimi"].filter(
      (key) => snapshot.quotas[key] || snapshot.usage[key],
    ),
  ];
  const metrics = [
    [t("最近一天 Tokens", "Latest day tokens"), latest?.total, latest?.date],
    [t("30 天 Tokens", "30-day tokens"), sumKnown(month, "total")],
    [
      t("累计 Tokens", "Total tokens"),
      lifetime ? usage.summary.lifetimeTokens : sumKnown(days, "total"),
      lifetime
        ? t("账户累计", "Account lifetime")
        : t("本地记录累计，可能不完整", "Local recorded total, may be partial"),
    ],
  ];
  return h(
    "div",
    { className: "usage-panel usage-dashboard" },
    h(
      "div",
      {
        className: "usage-provider-tabs",
        role: "tablist",
        "aria-label": t("数据来源", "Data provider"),
      },
      ...providers.map((key) =>
        h(
          "button",
          {
            key,
            role: "tab",
            "aria-selected": provider === key,
            className: provider === key ? "selected" : "",
            onClick: () => setProvider(key),
          },
          h(ProviderIcon, { provider: key, size: 16 }),
          PROVIDER_LABELS[key],
        ),
      ),
    ),
    quota?.error &&
      h(
        Notice,
        { tone: "warning" },
        t(
          "最新数据获取失败，显示上次快照。",
          "Latest fetch failed; showing the previous snapshot.",
        ),
      ),
    h(
      "div",
      { className: "usage-bento-top" },
      h(
        "div",
        { className: "usage-bento-metrics" },
        h(
          "div",
          { className: "quota-grid" },
          ...cards.map((item, index) =>
            h(QuotaCard, { key: index, item, stale: !!quota?.error }),
          ),
        ),
        h(
          "div",
          { className: "usage-summary-stats" },
          ...metrics.map(([label, value, title]) =>
            h(
              "article",
              {
                key: label,
                className: "data-card usage-summary-stat",
                title: settings.privacy ? "" : title,
              },
              h("span", null, label),
              h(
                "strong",
                null,
                settings.privacy ? "•••" : formatNumber(value, locale, true),
              ),
            ),
          ),
        ),
      ),
      h(
        "article",
        { className: "data-card account-bento" },
        h("span", { className: "muted" }, t("账户", "Account")),
        h("h3", null, settings.privacy ? "•••" : quota?.account?.plan || "—"),
        h(
          "p",
          {
            className: "account-email",
            title: settings.privacy ? "" : quota?.account?.email,
          },
          settings.privacy
            ? "•••"
            : quota?.account?.email || PROVIDER_LABELS[provider],
        ),
        h(
          "div",
          { className: "account-balance" },
          h("span", null, t("积分余额", "Credit balance")),
          h(
            "strong",
            null,
            settings.privacy
              ? "•••"
              : quota?.credits?.unlimited
                ? t("无限", "Unlimited")
                : formatCurrency(creditValue(quota?.credits?.balance), locale),
          ),
        ),
        h(
          "div",
          { className: "account-ticket-row" },
          h(
            "div",
            {
              className: "recharge-ticket",
              "aria-label": t("充值卡，仅展示", "Recharge card, display only"),
              "aria-disabled": true,
            },
            h("img", {
              src:
                "../assets/" +
                (provider === "claude"
                  ? "claude-recharge-card.svg"
                  : "recharge-card.svg"),
              alt: "",
            }),
            h(ProviderIcon, { provider, size: 17 }),
          ),
          h(
            "div",
            null,
            h("span", null, t("额度重置", "Quota resets")),
            h(
              "strong",
              null,
              settings.privacy
                ? "•••"
                : isFiniteNumber(quota?.credits?.resetCount)
                  ? t(
                      quota.credits.resetCount + "次",
                      String(quota.credits.resetCount),
                    )
                  : "—",
            ),
          ),
        ),
      ),
    ),
    settings.showCost &&
      h(CostCard, { days: usage?.localDays || usage?.days || [] }),
    settings.showActivity &&
      h(Activity, {
        days: usage?.days || [],
        lifetimeTokens: usage?.summary?.lifetimeTokens,
      }),
    !lifetime &&
      h(
        "p",
        { className: "chart-note" },
        t(
          "累计值来自可读取的本地记录，可能不完整。",
          "Totals cover readable local records and may be incomplete.",
        ),
      ),
  );
}
