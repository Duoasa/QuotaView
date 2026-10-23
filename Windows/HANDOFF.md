# 当前主线：WebView2 + .NET

2026-10-23：后续唯一维护仓库为 `Duoasa/QuotaView`，Windows 工程位于 `Windows/`，原仓库 `cfc5490` 为迁移来源。当前开发版本 `0.8.3-win.10`，Windows appcast 位于 `Windows/updates/appcast.xml`，尚未准入任何正式更新包。macOS 发布与 Sparkle feed 不变。更新代码、原生构建与 30 项专项检查完成；签名包校验、CI 和运行状态在主仓库 Handoff 同步。

当前工程入口为根目录 `build.ps1`，实现位于 `webview2/`；`windows/` 保留共享业务模块与 React 界面。运行时不依赖 Electron、Node.js 或 .NET Framework。

本轮完成原生窗口、数据和 Hook 桥接，设置与 mac 对齐，仅保留 AI 球及量子噪点；增加悬停展开，用量卡片组合布局和不可交互的充值卡，修复设置窗口 DPI、按钮尺寸和小屏定位。

复查入口：`./build.ps1 -Action test`；交付入口：`./build.ps1 -Action publish`。见 [主线说明](webview2/README.md)。生成物和报告不提交 Git，旧 Electron 发行包不代表本次主线。

继续修改时应使用现有真实数据读取链路。不要引入模拟额度，不要恢复充值二级页面、多特效选择或玻璃模式。Codex 的 Desktop owner 双向连接与只读 Hook 必须区分；真实拒绝测试的未核实项保留在 WebView2 开发记录，不扩大既有验收结论。
