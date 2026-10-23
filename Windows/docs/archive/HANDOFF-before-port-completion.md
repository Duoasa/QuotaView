# Windows 开发交接

当前任务：按最新发行版做最小 Windows 灵动岛，让用户查看效果。最终范围为完整灵动岛，不做桌面小组件。

源码基准：v0.7.7-build.1，commit `3866177cfa19db734d657ef505a4dc72c3338fba`；不是远程 `main`。

当前源码：`src/LocalSessions.cs`（有界本地观察）、`src/IslandWindow.cs`（WPF 窗口）、`src/Program.cs`（启动）。发行版轮廓已转译，状态球为简化 WPF 实现。

已运行程序：`bin/QuotaView.Windows.exe`，启动参数 `--expanded`；初始 PID 10996。2026-10-08 构建成功，25 项冒烟检查通过，真实本地探针和程序运行回执均读取到 1 个活动用户会话及额度记录。运行状态只保存在 `.local/`，不保存原始会话。没有改动 Codex 安装或账户配置。

视觉状态：待用户验收；没有截图或自动 UI 验收，不能标注视觉通过。

当前限制：只读日志观察，审批在 Codex 中操作；额度为可能滞后的本地记录。完整桌面 IPC、审批回传、原版特效、Markdown、完整设置、多屏键盘验证、现代 .NET 工程与发行流程尚未实现。参见 README 与 `docs/WINDOWS-MINIMUM.md`。

后续先根据用户体验修正窗口和交互，再继续完整适配。当前工作区原为空目录，未初始化 Git、未推送或发布。

## 独立特效开发台

用户随后要求先在单独 Windows 开发台实现 AI 球与量子噪点。新增 `Prototypes/EffectsLab/`，WinForms 控件 + 原生 OpenGL GPU 表面，未改动现有 WPF 程序。固定使用同一发行版 Ripple Glow 默认球（style 9）和 StateSmoke 的 dropField 量子噪点分支；原版来源保留在 reference/。

运行 `Prototypes/EffectsLab/bin/QuotaView.EffectsLab.exe`，构建 `Prototypes/EffectsLab/build.ps1 -Test`。支持九种状态、0–95% 模拟进度、显式完成重播、暂停、速度、减少动态效果，以及 24 DIP 球体的组合预览。启动 GPU 自检只读取像素并保存文字结果，不做截图或视觉验收。

用户后续明确反馈“效果很好，可以使用”，因此上述两个特效的当前开发台效果已获用户认可；这不等于 WPF 集成或跨显卡验证通过。

首次运行发现 GPU 自检没有清空前一个样本的边角，误报完成淡出失败；已修正清理，并在 NVIDIA RTX 3080 / OpenGL 4.6 上确认两个 shader 的输出、时间/进度响应和减少动态效果下完成收尾通过，GL 错误为 0。42 项模型检查覆盖状态连续性、打断、帧率、进度和完成规则。OpenGL 向 WPF 透明窗口的集成、跨显卡与多 DPI 对照尚未验证。开发台构建前需关闭本程序；运行记录见开发台 `.local/`。

## dot 适配包审阅

2026-10-21 用户提供 `F:/Codex Project/新建文件夹/`，要求分析整理。该目录是 0.8.3-win.1 Electron 运行分包，并非完整源码工程。已校验所有分包、片段、合并包以及 helper 哈希，并独立解包到 `Imports/dot-0.8.3-win.1/`；未改动原始下载文件或合并业务代码。

本机已用包内隔离 `--smoke-test` 模式完成 Windows x64 启动检查，退出码 0，island/capsule/settings 与 preload bridge 通过；未启用真实客户端或 Hooks。结果见 `Imports/dot-0.8.3-win.1/windows-smoke.json`。完整分析与接手顺序见 `docs/DOT-ADAPTATION-REVIEW.md`。

主要发现：缺完整前端源码、锁文件、测试和打包工程；两种核心特效仍是 CSS 近似，未接入已认可的 shader；压缩状态字段未被前端消费；Claude 旧状态和跨轮文本存在边界问题；ASAR 带有约 37 MB 的 Node 构建归档。建议先补齐 dot 完整源码、复现 Windows 构建与客户端验证，再决定 Electron 主线并移植特效。此次没有公开发布、推送或修改账户配置。

## Electron 核心特效接入

用户随后明确要求直接接入此前已认可的 AI 球与量子噪点。已新增 `ElectronEffects/`，复用开发台原 shader 和状态参数，迁移连续动画模型到 JavaScript，以单窗口单 WebGL2 图集接入 dot 真实 React 球体及任务卡组件；同时接通压缩状态。输出 `bin/QuotaView.ElectronEffects/QuotaView Windows.exe`，版本 `0.8.3-win.1.effects.1`。

新配置默认 quantum；已有设置保留，可在设置中切换量子噪点。构建命令 `ElectronEffects/build.ps1 -Test`。已通过 8 组模型测试及 Windows 隔离启动、React 挂载、GPU 进度与压缩配色、完成淡出和卸载清理检查，见 `ElectronEffects/gpu-smoke.json`。接入后视觉仍由用户评估。

当前用唯一匹配的 ASAR 产物适配脚本完成接入，新增模型和渲染代码保持独立可编辑；不是等待完整源码才可用。后续拿到 React 工程后，把相同组件并入源码并替换产物适配步骤。dot 原包及 C# 开发台均保留。具体使用与实现说明见 `ElectronEffects/README.md`。
