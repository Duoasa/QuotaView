import { trackWindowRegion } from "./window-region.js";
import { React, createRoot } from "./react.js";
import { normalizeSnapshot, Icon, AppContext } from "./common.js";
import { QuotaCapsule } from "./usage.js";
import { IslandView } from "./tasks.js";
import { SettingsView } from "./settings.js";
var viewName =
    new URLSearchParams(window.location.search).get("view") || "island",
  ErrorBoundary = class extends React.Component {
    constructor(e) {
      (super(e), (this.state = { error: null }));
    }
    static getDerivedStateFromError(e) {
      return { error: e };
    }
    render() {
      return this.state.error
        ? React.createElement(
            "main",
            { className: "fatal-error" },
            React.createElement("img", {
              src: "../assets/app-icon.png",
              width: "40",
              height: "40",
              alt: "QuotaView",
            }),
            React.createElement("h1", null, "QuotaView"),
            React.createElement(
              "p",
              null,
              "\u754C\u9762\u6682\u65F6\u65E0\u6CD5\u52A0\u8F7D\u3002\u8BF7\u91CD\u65B0\u542F\u52A8\u5E94\u7528\u3002",
              React.createElement("br", null),
              "The interface could not load. Please restart the app.",
            ),
            React.createElement(
              "details",
              null,
              React.createElement("summary", null, "\u8BE6\u60C5 / Details"),
              React.createElement("pre", null, this.state.error.message),
            ),
          )
        : this.props.children;
    }
  };
function App() {
  const fixtureMode = React.useRef(false);
  let [t, e] = React.useState(() => normalizeSnapshot(null)),
    [a, l] = React.useState({}),
    [n, i] = React.useState(""),
    [u, o] = React.useState(Date.now()),
    [c, r] = React.useState(matchMedia("(prefers-color-scheme: dark)").matches),
    [g, m] = React.useState(document.hidden),
    f =
      t.settings.language === "zh"
        ? "zh-CN"
        : t.settings.language === "en"
          ? "en-US"
          : t.locale === "zh" ||
              (!t.locale && navigator.language.startsWith("zh"))
            ? "zh-CN"
            : "en-US",
    p = React.useCallback((d, h) => (f.startsWith("zh") ? d : h), [f]),
    w = React.useCallback(
      async (d, h, x = {}) => {
        if (fixtureMode.current && d === "updateSettings") {
          e(current => normalizeSnapshot({...current,settings:{...current.settings,...h}}));
          return {ok:true};
        }
        try {
          if (typeof window.quotaView?.[d] != "function")
            throw new Error(
              p(
                "\u6B64\u529F\u80FD\u7684\u672C\u673A\u8FDE\u63A5\u4E0D\u53EF\u7528\u3002\u8BF7\u91CD\u65B0\u542F\u52A8\u5E94\u7528\u3002",
                "The local bridge for this feature is unavailable. Please restart the app.",
              ),
            );
          l((M) => ({ ...M, [d]: !0 }));
          let T = await window.quotaView[d](h);
          if (
            T?.ok === !1 ||
            T?.success === !1 ||
            (T?.error && !["snapshot", "checkUpdates"].includes(d))
          )
            throw new Error(
              typeof T.error == "string"
                ? T.error
                : p(
                    "\u64CD\u4F5C\u672A\u5B8C\u6210\u3002",
                    "The action did not complete.",
                  ),
            );
          return (
            d === "updateSettings" &&
              T?.settings &&
              e((M) => normalizeSnapshot({ ...M, ...T })),
            T
          );
        } catch (T) {
          if ((i(T.message || String(T)), x.throwError)) throw T;
          return null;
        } finally {
          l((T) => ({ ...T, [d]: !1 }));
        }
      },
      [p],
    ),
    N = React.useCallback((d, h) => w("updateSettings", { [d]: h }), [w]);
  React.useEffect(() => trackWindowRegion(viewName), []);
  React.useEffect(() => {
    if (new URLSearchParams(location.search).get("effectsSmoke") !== "1") return;
    window.QVUITest = { setSnapshot(value) { fixtureMode.current = true; e(normalizeSnapshot(value)); } };
    return () => { delete window.QVUITest; };
  }, []);
  (React.useEffect(() => {
    let d = !0,
      h;
    if (!window.quotaView) {
      i(
        p(
          "\u672A\u8FDE\u63A5\u5230 QuotaView \u672C\u673A\u670D\u52A1\u3002\u754C\u9762\u4E0D\u4F1A\u751F\u6210\u6A21\u62DF\u6570\u636E\u3002",
          "Not connected to the QuotaView local service. No simulated data will be generated.",
        ),
      );
      return;
    }
    return (
      window.quotaView
        .snapshot()
        .then((x) => {
          d && !fixtureMode.current && e(normalizeSnapshot(x));
        })
        .catch((x) => i(String(x.message || x))),
      (h = window.quotaView.subscribe((x) => {
        d && !fixtureMode.current && e(normalizeSnapshot(x));
      })),
      () => {
        ((d = !1), typeof h == "function" && h());
      }
    );
  }, []),
    React.useEffect(() => {
      let d = () => m(document.hidden);
      return (
        document.addEventListener("visibilitychange", d),
        () => document.removeEventListener("visibilitychange", d)
      );
    }, []),
    React.useEffect(() => {
      if (g) return;
      o(Date.now());
      let d = setInterval(() => o(Date.now()), 3e4);
      return () => clearInterval(d);
    }, [g]),
    React.useEffect(() => {
      let d = matchMedia("(prefers-color-scheme: dark)"),
        h = (x) => r(x.matches);
      return (
        d.addEventListener("change", h),
        () => d.removeEventListener("change", h)
      );
    }, []),
    React.useEffect(() => {
      ((document.documentElement.lang = f),
        (document.title =
          viewName === "settings"
            ? `${p("\u8BBE\u7F6E", "Settings")} \xB7 QuotaView`
            : "QuotaView"));
    }, [f, p]));
  let D = React.useMemo(
      () => ({
        snapshot: t,
        t: p,
        locale: f,
        now: u,
        invoke: w,
        setSetting: N,
        busy: a,
      }),
      [t, p, f, u, w, N, a],
    ),
    v =
      t.settings.theme === "system" ? (c ? "dark" : "light") : t.settings.theme;
  return React.createElement(
    AppContext.Provider,
    { value: D },
    React.createElement(
      "div",
      {
        className: `app view-${viewName} theme-${v} material-${t.settings.material} ${(viewName === "capsule" ? t.platform?.capsuleBackdrop : t.platform?.nativeBackdrop) ? "native-backdrop" : "fallback-backdrop"} ${t.platform?.settingsBackdrop ? "settings-backdrop" : ""} ${t.settings.reduceMotion ? "reduce-motion" : ""} ${g ? "window-hidden" : ""} ${t.settings.privacy ? "privacy-on" : ""}`,
      },
      viewName === "settings"
        ? React.createElement(SettingsView, null)
        : viewName === "capsule"
          ? React.createElement(
              "div",
              { className: "standalone-capsule" },
              React.createElement(QuotaCapsule, {
                onClick: () => w("showWindow", "island"),
              }),
            )
          : React.createElement(IslandView, null),
      t.warning &&
        React.createElement(
          "div",
          { className: "platform-warning" },
          React.createElement(Icon, { name: "warning", size: 12 }),
          t.warning,
        ),
      n &&
        React.createElement(
          "div",
          { className: "error-toast", role: "alert" },
          React.createElement(Icon, { name: "warning" }),
          React.createElement("span", null, n),
          React.createElement(
            "button",
            {
              onClick: () => i(""),
              "aria-label": p("\u5173\u95ED\u63D0\u793A", "Dismiss message"),
            },
            React.createElement(Icon, { name: "close", size: 12 }),
          ),
        ),
    ),
  );
}
createRoot(document.getElementById("root")).render(
  React.createElement(ErrorBoundary, null, React.createElement(App, null)),
);
window.QVEffects.registerTestReact(React, createRoot);
