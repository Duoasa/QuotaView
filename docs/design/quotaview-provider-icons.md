# 用量与任务来源图标

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
