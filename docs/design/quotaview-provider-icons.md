# 用量与任务来源图标

## 标签图标尺寸与原色（2026-10-30，0.8.7 Build 8）

用户反馈 Build 7 图标过大且颜色受暗色玻璃影响。圆底缩至 16 pt、标志缩至 11 pt；胶囊高仍为 24 pt，左内距按半径差变为 4 pt，保持同心。取消未选中图标的 0.72 透明度；玻璃只施加在独立背景层，圆底和品牌标志以完整不透明度绘于其上。选中状态仍由胶囊背景和文字表达，图标原色、字号、点击和辅助功能语义保持。重置卡继续沿用发行版原始灰色渐变素材。本节覆盖 Build 7 的尺寸与合成方式，运行证据 `.build/provider-capsules-087b8-runtime/`；视觉由用户验收。

本轮源码已由 [PR #117](https://github.com/Duoasa/QuotaView/pull/117) 合入 main `6c3f55f`，PR/main CI 均通过；当前 Build 8 的 239 项生产输入与最终源码及合并提交一致。集成证据 `.build/source-integration-087b7/`，完整交付见 Handoff；发布渠道未变，视觉验收仍独立保留。

## 用量标签圆形底托与重置卡恢复（2026-10-30，0.8.7 Build 7）

用户要求标签胶囊的 Agent 图标使用圆底，与左端半圆同心。Codex 使用白色圆底和黑色官方标志，Claude 使用官方陶土色 `#D97757` 圆底和白色原始标志。圆底直径 18 pt，符号 14 pt，胶囊高度沿用实际 24 pt；左内距由 `(24 - 18) / 2 = 3 pt` 推导，圆心均位于左侧 12 pt。保留图文间距 6、右内距 12、名称、选中状态、原点击范围和辅助功能；任务卡与连接设置继续使用原官方应用图标。

用户同时要求重置卡恢复发行版样式。`IslandResetMark.svg` 已逐字节恢复为 `v0.8.6-build.21` 的原始灰色渐变素材，白色卡面与转场原样保留；此项覆盖 Build 2 错误套用白色标志及 Build 6 临时黑色尝试。用量标签仍使用官方 Blossom 路径，通过模板渲染为黑色，不与重置卡共用颜色。Build 6 曾更新本地包，未单独提交或发布。

本批运行证据 `.build/provider-capsules-087b7-runtime/`，素材与稳定 tag 一致性及几何关系已核对；实际效果由用户检查。用户已授权将本轮 0.8.7 改动推送 GitHub 并合入 main，当前结果见 Handoff，未获发布或 appcast 准入。

## 官方图标与 Claude 橙底版本（2026-10-30，0.8.7 Build 2）

用户要求使用官方素材，截图仅表示 Claude 橙底白标的样式方向。此节覆盖下方 Claude 任务卡/连接页的奶油白底方案及 Codex 用量/重置细线路径；历史验收仅代表当时版本。

- Claude：从官方 Claude 3.6556.2（`com.anthropic.claudefordesktop`，签名 Team `Q6L2SF6YDW`）的 `Contents/Resources/electron.icns` 提取 `ic10` 原始 PNG 字节，保存为 `ClaudeApplicationIcon`。保留橙底、白标、圆角及透明画布，不重新配色或描绘。SHA-256：`a77ce76c9c0261ebd4fb5f51f12467d412783eaf589fc34cbf5a1a1aa12e5789`。
- 任务主卡、审批头卡、子任务、连接设置及普通来源图标入口统一使用橙底图标。任务仍占 16/14 pt 槽位，原图含约 10% 边距；连接设置沿用 27.5 pt 画布适配 22 pt 槽位。用量来源标签使用同一原图，字号、间距和交互不变。Claude 重置卡保留官网原始无框标志与原配色，避免把完整应用底框染成白块。
- ChatGPT/Codex：现有任务/连接应用 PNG 与官方应用 `icon-chatgpt.png` 字节一致，继续保留。用量 `CodexProviderMark` 与重置 `IslandResetMark` 改用官方桌面应用 26.1027.30824（`com.openai.codex`，签名 Team `2DC432GLL2`）`app.asar` 中 `webview/assets/app-primary-95a0e6d83f1e.js` 的 Blossom 组件（`egr`，导出 `lf`，由 `BlossomFidget` 使用）。原始 path 与 `149 149 418 418` viewBox 保持一致，`currentColor` 在现有深色表面解析为白色，不人工加描边。SVG SHA-256：`8e45c6a7a5065832678adda1878edc3f06d41b53b48e32183cd5ef6e184835b0`。

素材属于 Anthropic / OpenAI，仅标识对应服务；[OpenAI 品牌规范](https://openai.com/brand/)。资源随包加载，无运行时下载。来源及原始组件证据 `.build/provider-icons-087b2/provenance.json`；原路径一致性、既有官方 PNG 字节一致性和四项 AppKit 资源解码冒烟通过。Debug arm64 增量构建及开发包核验通过（239 输入、14 资源）；运行证据 `.build/provider-icons-087b2-runtime/`。视觉与小尺寸辨识度等待用户验收，未执行截图或 UI 自动验收；仅本地修改。

<a id="task-provider-icons"></a>

## 任务卡品牌标识统一（2026-10-28，0.8.6 Build 2）

主任务卡（含审批头卡）、可归档任务的品牌展示态与子任务行共用 `IslandTaskProviderIcon`。Codex 保留原应用图标；Claude 使用官网原始陶土色标志与奶油色底，DSH 使用现有官方鲸鱼标志与白底，Kimi 使用官网原始黑底应用图标，均为连续圆角矩形。复用本页记录的本地品牌素材，不重新绘制 Logo，不在任务卡使用系统终端或字母圆圈占位。

主卡保留 16 pt 图标槽位，子任务行保留 14 pt；其他品牌的可见底托为槽位的 80%，匹配 Codex 原图两侧各约 10% 的透明边距。底托圆角采用连接页的 5/22 比例，Claude / DSH 标志占底托 16/22，Kimi 填满底托。归档按钮仍为独立 24 pt 命中区，归档态图形、点击与按压反馈保持；普通标识保留产品名辅助功能标签，按钮内装饰图标不重复朗读。

用量标签、重置卡与连接设置沿用各自现有样式。2026-10-28 用户确认“图标没问题了”；该图标样式已验收。增量编译与实际运行包证据见 Handoff。

- 用量来源标签使用无底框标志：14 × 14 pt，图文间距 6 pt，两个标签间距 6 pt。高度、字号与水平内距共用顶部用量按钮的 `IslandChromeMetrics`（28 pt / 12 pt Medium / 8 pt）。选中背景与点击区域均为 Capsule；标签左缘对齐用量卡片，名称保持完整。图标不重复参与 VoiceOver 朗读。
- Codex 用量标签改用 `ProviderIcons.xcassets/CodexProviderMark.imageset` 的白色矢量标志。轮廓直接复用项目 `IslandResetMark.svg` 的主路径，保持原 viewBox，不含应用白色底框、渐变或浮雕；任务卡原有 `CodexProviderIcon.png` 保持。
- Claude Code 使用 `Resources/ProviderIcons.xcassets/ClaudeProviderIcon.imageset/ClaudeProviderIcon.svg`。任务卡、子任务、用量标签和重置卡共用 `IslandProviderIcon` 的缓存资源入口。

## Claude 素材来源

来源：[Claude 官方网站](https://claude.com/)，2026-10-09 获取。提取页面 `ClaudeWordmark` SVG 中 `fill="#D97757"` 的独立标志路径，保留原始路径与颜色，使用其 `0 0 125 125` 标志画布；没有使用系统星号或近似重画。

重置卡保留原有陶土色卡面与奶油白图标配色，仅将原始标志轮廓静态着色后缓存；SwiftUI 卡片和 AppKit 转场共用该图像。

该标志属于 Anthropic，用于标识第三方服务。应用本地打包矢量素材，运行时不从网络加载。Xcode 与 SwiftPM 均声明资源，编译后的资产可由 AppKit 加载；保留矢量表示适配不同缩放。

当前源码已完成定向 Swift 类型检查与资源编译/加载检查；已按用户“启动替换”授权于 2026-10-09 08:53 进入开发运行包；实际视觉由用户验收。来源快照与检查证据在 `.build/usage-provider-icons-20261009/`。

2026-10-09 胶囊修订已通过定向类型检查、矢量资源编译及 AppKit 加载检查；此次修订已按用户“运行”授权于 09:03 进入开发运行包，替换前旧包完整备份；运行证据见 `.build/provider-capsule-runtime-20261009/`。证据：`.build/usage-provider-capsules-20261009/`。

2026-10-09 连接页分组标题增加 22 pt 圆角图标（圆角 5 pt，文字间距 8 pt）。Codex 复用包内应用图标；Claude 原始标志加 4 pt 内距及奶油色底。只应用于分组标题，用量标签继续无框；本次修订已按用户“运行”授权于 2026-10-09 09:25 进入开发包，构建与运行证据见 Handoff，视觉待用户验收。

## Agent 连接列表（2026-10-09）

用户要求四个 Agent 使用圆角矩形真实图标，并将箭头移至最左侧。列表使用独立 `AgentSettingsIcon`，不改变用量页已有的无底框图标约定。

- 所有图标外框 22 × 22 pt，连续圆角 5 pt。Codex 原始 PNG 以 27.5 pt 画布居中裁切，补偿约 10% 透明边距；Claude 官网原始矢量标志为 16 pt、奶油色底；DSH 原始黑色鲸鱼标志为 16 pt、白底；Kimi 原始图标填满 22 pt 外框。没有使用系统终端或系统字母图标替代连接列表内的品牌。
- 箭头槽位 12 × 22 pt，位于图标左侧；图标与名称间距均为 10 pt。状态固定列宽：中文 76 pt、English 116 pt；开关位置不随状态文字长度变化。
- DSH 来源：本机官方 `@deepseek-ai/dsh-web-frontend` 包 `dist/favicon.svg`（DSH 0.1.7-rc.2）。保留原始 50 × 50 viewBox、路径与黑色填充；[官方项目](https://github.com/deepseek-ai/deepseek-harness)。新资产 `DSHProviderMark`，SHA-256 `9e983b4f649c25c6ca0623a50be1a6e705fd8f49f756638b980fa13b40575ab6`。
- Kimi 来源：[Kimi Code 官网](https://www.kimi.com/code/en) 声明的原始应用图标 [pwa-192.png](https://www.kimi.com/pwa-192.png)。保存原始 192 × 192 PNG，保留黑底、白色 K 与蓝色标记；不是系统 K 字符。新资产 `KimiCodeProviderIcon`，SHA-256 `6c14f9c3062e953b3ed57ae3e19db931c1c1bba38d4d8d55550544f31d55e469`。
- 上述品牌属于各自权利人，仅用于服务身份识别。来源快照、资源与修改前副本位于 `.build/agent-row-icons-20261009/`。本次编译、实际运行包及验收状态见 Handoff。

## 临时三来源任务卡预览（历史记录，Build 4 已清理）

用户要求在开发版展示 Claude、DSH、Kimi 模拟卡检查图标。仅 Debug 构建、`com.quotaview.development073` 和显式启动参数 `--debug-provider-cards` 同时满足时，在真实任务前加入三张带 DEBUG 标记的卡片；标题、说明、Tooltip 与辅助功能均表明模拟用途。仅本次进程内展示，不写入任务存储，不修改账号、额度、Hook 或来源连接设置，不携带真实任务身份/审批协议；选择不会回调真实任务操作，归档仅在内存中隐藏对应预览卡。

用户已确认图标并要求清理。0.8.6 Build 4 已移除模拟生成、参数读取、临时选择/归档分支和 Tooltip 修饰器，生产源码扫描无临时注入残留，新运行进程未带预览参数。此前预览仅存于旧进程，未写入真实任务存储。编译、运行与清理证据见 Handoff。

## 四来源官方图标（2026-11-01，0.8.7 Build 30）

用户要求新增 Agent 使用官方 icon。四个 SVG 原样保存，保留 viewBox、路径与原色，不重画或用 SF Symbols 替代；设置页复用 22 pt 白色圆角底与 16 pt 标志，任务卡按既有比例缩放。图标前景完整不透明，独立于玻璃材质。

- `CursorProviderMark`：[官方来源](https://cursor.com/brand)；原始文件 `cursor-brand-assets.zip/General Logos/Cube/SVG/CUBE_2D_LIGHT.svg`；SHA-256 `c483c02f78eb2619778fdd959e72a9adfac4844854472cd2653d4cbfd60e4d71`。
- `GeminiCLIProviderMark`：[官方来源](https://geminicli.com/brand-kit/)；原始文件 `https://geminicli.com/brandassets/gemini-cli-icon_full-color.svg`；SHA-256 `d2b511e4d9a97bb849526646cf1e7705ffa028a52eb53d847c6c3de1e9a40a73`。
- `OpenCodeProviderMark`：[官方来源](https://opencode.ai/brand)；原始文件 `https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/console/app/src/asset/brand/opencode-logo-light.svg`；SHA-256 `b47a4fecc77599382e238868e74064bbe92307b0e253a32f0b1a026517a2d2a6`。
- `CopilotCLIProviderMark`：[官方来源](https://github.com/primer/octicons/blob/main/icons/copilot-24.svg)；原始文件 `https://raw.githubusercontent.com/primer/octicons/main/icons/copilot-24.svg`；SHA-256 `eeafb3c2f333e04ccf7d031ae215f7adafaed4c6352556b0bf79496e048bcdd7`。

Cursor 为官方 light-background 2D cube；Gemini CLI 为官方全彩 CLI icon；OpenCode 为官方浅色背景标志；Copilot 为 GitHub Primer 的 copilot-24 矢量（MIT，许可证随 `ProviderIconNotices.txt` 打包）。各品牌商标仍属权利人，仅用于标识服务。资源由资产目录离线打包；本批视觉待用户验收。
