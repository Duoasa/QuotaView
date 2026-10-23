# 当前主线：WebView2 + .NET

2026-10-23：后续唯一维护仓库为 `Duoasa/QuotaView`，Windows 工程位于 `Windows/`，原仓库 `cfc5490` 为迁移来源。首个正式版 **QuotaView 0.8.3-win · Windows** 已发布，包内版本及 tag 为 `0.8.3-win.10` / `v0.8.3-win.10`；首个签名条目加入 `Windows/updates/appcast.xml`。macOS Release 名称补充平台标注，原资产、Latest 与 Sparkle feed 不变。完整发布事实见[版本历史](../VERSION_HISTORY.md#当前最新版本)，CI 和运行状态见[主仓库 Handoff](../HANDOFF.md)。本轮复用通过 CI 的原包，公开回下载、签名、哈希与 324 个文件检查通过，不改动应用代码。

当前工程入口为根目录 `build.ps1`，实现位于 `webview2/`；`windows/` 保留共享业务模块与 React 界面。运行时不依赖 Electron、Node.js 或 .NET Framework。

本轮完成原生窗口、数据和 Hook 桥接，设置与 mac 对齐，仅保留 AI 球及量子噪点；增加悬停展开，用量卡片组合布局和不可交互的充值卡，修复设置窗口 DPI、按钮尺寸和小屏定位。

复查入口：`./build.ps1 -Action test`；交付入口：`./build.ps1 -Action publish`。见 [主线说明](webview2/README.md)。生成物和报告不提交 Git，旧 Electron 发行包不代表本次主线。

继续修改时应使用现有真实数据读取链路。不要引入模拟额度，不要恢复充值二级页面、多特效选择或玻璃模式。Codex 的 Desktop owner 双向连接与只读 Hook 必须区分；真实拒绝测试的未核实项保留在 WebView2 开发记录，不扩大既有验收结论。
