# 当前主线：WebView2 + .NET

## Windows 0.8.3-win.13 发布准备（2026-10-31）

自动检查更新默认开启，已有明确关闭偏好保留；设置精简与 Issue #114 修复已由 PR #118 合入 main。win.12 仅为未公开候选，本次正式发布使用 win.13。已修复冒烟测试在设置广播后未恢复用量场景的时序依赖。最终发布、签名 appcast 与运行证据将在发布完成后回填；当前公开稳定版仍见版本历史。


## 当前本地开发版 0.8.3-win.12（2026-10-31）

按用户要求继续让控件表达用途：删除通用/灵动岛静态行说明、连接与代理常驻解释、反馈隐私重复段落及侧栏标语；连接详情默认折叠，Desktop 状态改为紧凑状态行。隐私改为“隐藏任务与账户信息”，停留时间改为“自动收起延迟”；代理预览标明“更新与额度”。移除关于页指向同一仓库的重复上游入口。保留操作确认、动态错误、更新进度和许可证信息；诊断分享提示仅在导出后出现，中英文一致。

沿用 win.11 的 Issue #114 修复，本轮仅修改设置展示及版本号。前端与原生开发编译通过；运行入口更新为 `webview2/build/development-runtime-win12/QuotaView.Native.exe`，旧开发目录和 Downloads 正式包保留。用户负责视觉验收，未主动进行 UI 自动化或追加业务回归。源码未提交/推送，正式 Release 和 appcast 不变。

## 本地开发版 0.8.3-win.11（2026-10-31）

修复 [Issue #114](https://github.com/Duoasa/QuotaView/issues/114)：同一轮结束通知与完成自动展开共用一次性事件；启动历史、重复终态、重连及暂时消失不会重新提醒。Codex 同一会话的多份 rollout 合并成一张当前卡片，Desktop 与 rollout 统一轮次身份；终态在快照失效和断线时保留，较早轮次不能覆盖较新轮次。缓存只保留展示状态，不保留可操作审批；新轮次正常恢复通知。兼容旧版本已归档的原始轮次 ID。

设置页移除页面副标题、重复功能说明、预览空态技术说明、自动保存页脚及开发验收文案；保留隐私范围、权限与配置更改说明、诊断分享提示、错误与更新状态，中英文同步。

24 项定向 Node 检查通过（包括 8 项新增终态/通知用例），8 项原生适配检查通过，增量构建成功。隔离夹具覆盖 200 次终态切换及断线/旧快照/重复日志路径；未取得反馈者原始会话，不能宣称其具体触发链已在实机重现或验收。UI 观感与长期真实会话由用户验收。

开发运行目录为 `webview2/build/development-runtime/QuotaView.Native.exe`，版本 `0.8.3-win.11`，启动 PID 8408；继续使用现有用户数据，Downloads 中原正式程序文件保留。分支 `codex/windows-terminal-notifications`，源码未提交/推送，未发布或修改 appcast。诊断证据 `webview2/build/issue-114-delivery.json` 与 `issue-114-adapter.json`；公开稳定版仍为[版本历史](../VERSION_HISTORY.md#当前最新版本)中的 0.8.3-win。

2026-10-23：后续唯一维护仓库为 `Duoasa/QuotaView`，Windows 工程位于 `Windows/`，原仓库 `cfc5490` 为迁移来源。首个正式版 **QuotaView 0.8.3-win · Windows** 已发布，包内版本及 tag 为 `0.8.3-win.10` / `v0.8.3-win.10`；首个签名条目加入 `Windows/updates/appcast.xml`。macOS Release 名称补充平台标注，原资产、Latest 与 Sparkle feed 不变。完整发布事实见[版本历史](../VERSION_HISTORY.md#当前最新版本)，CI 和运行状态见[主仓库 Handoff](../HANDOFF.md)。本轮复用通过 CI 的原包，公开回下载、签名、哈希与 324 个文件检查通过，不改动应用代码。

当前工程入口为根目录 `build.ps1`，实现位于 `webview2/`；`windows/` 保留共享业务模块与 React 界面。运行时不依赖 Electron、Node.js 或 .NET Framework。

本轮完成原生窗口、数据和 Hook 桥接，设置与 mac 对齐，仅保留 AI 球及量子噪点；增加悬停展开，用量卡片组合布局和不可交互的充值卡，修复设置窗口 DPI、按钮尺寸和小屏定位。

复查入口：`./build.ps1 -Action test`；交付入口：`./build.ps1 -Action publish`。见 [主线说明](webview2/README.md)。生成物和报告不提交 Git，旧 Electron 发行包不代表本次主线。

继续修改时应使用现有真实数据读取链路。不要引入模拟额度，不要恢复充值二级页面、多特效选择或玻璃模式。Codex 的 Desktop owner 双向连接与只读 Hook 必须区分；真实拒绝测试的未核实项保留在 WebView2 开发记录，不扩大既有验收结论。
