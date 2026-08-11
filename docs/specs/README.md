# QuotaView SDD 规格索引

> 文档编号：`QV-SDD-INDEX-001`
>
> 文档类型：SDD 规格注册表（Specification Registry）
>
> 规格状态：`Accepted`
>
> 生效日期：2026-08-04
>
> 当前生产基线：QuotaView `0.3.5 (Build 5)`
>
> 当前进行中工作：`QV-PRODUCT-APP-UPDATES-003` 等待后续 Build 6 或更高
> 正式版本完成真实 N → N+1 更新验收
>
> 当前交付阶段：版本 `Released`（`v0.3.5-build.5`）；更新规格保持
> `Verifying`（真实 N → N+1 尚未执行）

## 1. 本文件的职责

本文件是 QuotaView 采用 Specification-Driven Development（SDD）后的
唯一规格索引。它负责回答：

1. 当前公开生产基线是什么；
2. 当前唯一进行中的产品工作是什么；
3. 每份 Markdown 属于规范、规格、证据、交接、历史还是外部参考；
4. 当前功能处于发现、Demo、生产实现、验证还是发布阶段；
5. 开始一项工作前必须读取哪份规格以及满足哪些门禁。

发布事实仍以项目根目录的
[VERSION_HISTORY.md](../../VERSION_HISTORY.md#当前最新版本) 为唯一历史索引；
当前工作区、完成事项和阻塞项仍由 [HANDOFF.md](../../HANDOFF.md) 维护。
本文件不得把计划、Prototype 或候选构建写成已经发布。

### 1.1 正式文档边界

正式 SDD 系统只接纳已经由 Git 跟踪、且在本注册表或阅读路由中具有明确
职责的 Markdown。当前 SDD 治理、规格和多任务 Demo 文档自提交 `f603c38`
起已进入 `main`；多任务生产实现已作为 `0.3.2 Preview 1` 发布，随后从
`0.3.3` 稳定生产映射中移除并保留为公开 Pre-release 与本地归档参照。

以下本地对象默认排除在正式调用链外：未跟踪的旧
`Prototypes/CodexActivityMetalDemo/`、受 `AGENTS.md` 门禁约束的未跟踪
`docs/reference/`，以及未跟踪图片。它们不是当前规格或验收证据；除非用户
明确授权相应对象并完成注册，不得读取后直接影响生产实现。

## 2. 当前状态快照

| 维度 | 当前事实 |
|---|---|
| 公开生产版本 | `0.3.5 (Build 5)`；GitHub Latest；已进入公开 Stable appcast |
| 当前生产代码版本 | `MARKETING_VERSION = 0.3.5`、`CURRENT_PROJECT_VERSION = 5` |
| 当前迭代 | 后续 `Build 6` 的真实 N → N+1 更新验收；新功能范围尚未定义 |
| 当前规格 | `QV-PRODUCT-APP-UPDATES-003` |
| 规格状态 | `Accepted` |
| 交付状态 | `0.3.5 Build 5` 版本为 `Released`；`QV-PRODUCT-APP-UPDATES-003` 为 `Verifying`，只剩真实 N → N+1 与完整视觉/辅助功能矩阵 |
| 生产源码状态 | 主额度内嵌重置、Spark、30 日 Tokens、成本估算、半年完整 16 列网格、“最近一天”语义和只在预期 Developer ID 正式 App 启动的 Sparkle 2.9.2 Stable 更新器；0.3.2 多任务生产实现不包含在稳定源码中 |
| 生产自动化 | `swift test` 64 项通过、0 失败；PR #22 GitHub CI 通过；Universal Release、Developer ID、Apple 公证/Staple、回下载与公开 Feed 通过；App、Widget、Hook、Core、Sparkle 与嵌套组件均为 `x86_64 arm64` |
| 正式 Release | `v0.3.5-build.5` / [QuotaView 0.3.5 Build 5 — Usage Overview and App Updates](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.5-build.5) / 发布提交 `58e676a8317d907107af3d1731ab11a0ded52684` |
| 正式资产 | `QuotaView-v0.3.5-build.5.zip`；`12,747,358 bytes`；SHA-256 `d8524ddf5739501bd797cdd082cc8738a7775d8b994fe99033068af8f821b2e1`；Apple Submission `88796026-3227-405a-9e1b-900af973c527` |
| 回下载与 Feed | GitHub 资产与本地公证包逐字节一致；签名、Staple、Gatekeeper、版本、架构和资源复核通过；[公开 appcast](https://duoasa.github.io/QuotaView/appcast.xml) 线上逐字节与 EdDSA 验证通过 |
| 独立预览版 | `0.3.2 (Build 1) Preview 1` / `v0.3.2-preview.1` / [GitHub Pre-release](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.2-preview.1)，继续保留供社区测试 |
| 本地预览备份 | 分支 `codex/archive-0.3.2-preview.1-multitask-island`；worktree `.worktrees/QuotaView-0.3.2-preview.1-backup`；提交 `f835bcd46a3d0197e9dc09e0b5a25a6d5d69521c` |
| 当前验收 | 产品所有者已批准 Build 5 正式发布并提供 `Resources/QuotaView-0.3.5-Overview.png` 产品截图；完整视觉/辅助功能交叉矩阵未记录为全量通过；真实 N → N+1 等待后续 Build |

### 当前迭代边界

- 当前唯一仍在验证的规格为
  [`QV-PRODUCT-APP-UPDATES-003`](../design/quotaview-app-updates-0.3.5.md)；
- 已由 `0.3.5 Build 5` 正式发布、但完整视觉矩阵仍需保持未勾选的用量范围由
  [`QV-PRODUCT-USAGE-OVERVIEW-002`](../design/quotaview-usage-overview-0.3.4.md)
  继续记录；
- Token 活动图表的唯一规格为
  [`QV-PRODUCT-TOKEN-ACTIVITY-001`](../design/quotaview-token-activity.md)；
- 0.3.5 的 tag、Latest、正式资产、回下载与公开 Feed 验证已完成，发布事实
  不可移动；
- `v0.3.2-preview.1`、公证资产和 GitHub Pre-release 已完成并视为不可移动
  发布事实；对应本地归档必须保留，后续优化使用新的迭代、Build、tag 和资产；
- 0.3.2 Preview 的多任务生产代码不得进入 0.3.5 稳定版；单任务灵动岛继续
  作为稳定行为；
- `0.3.5 Build 4` 起 Build Number 全局单调递增，Marketing Version 升级
  也不得重置；App、Widget、兼容 Info.plist、tag 和 ZIP 必须同步。

## 3. SDD 状态模型

规格状态与交付状态必须分开记录，禁止只写含糊的“进行中”或“已完成”。
这两组状态用于产品和架构规格；治理、交接、发布历史和验证证据不强行套用
交付状态，应使用明确的文档/证据状态，并在注册表中以破折号表示不适用。

### 规格状态

| 状态 | 含义 | 允许的工作 |
|---|---|---|
| `Draft` | 问题、范围或验收条件尚未稳定 | 调研、讨论、隔离实验 |
| `Review` | 规格已成形，等待产品或技术确认 | 评审、Prototype、修订 |
| `Accepted` | 范围、不变量和验收条件已确认 | 进入已授权的交付阶段 |
| `Superseded` | 已由新规格替代 | 仅用于历史追溯 |
| `Archived` | 历史记录或验证报告，不再驱动新实现 | 只读引用 |

### 交付状态

| 状态 | 含义 | 生产代码权限 |
|---|---|---|
| `Discovery` | 需求与可行性探索 | 不得修改生产行为 |
| `Prototype` | 隔离 Demo 验证 | 仅修改 Prototype；除非用户另行授权 |
| `Planned` | 规格已接受，生产实施尚未开始 | 不得声称已实现 |
| `Implementing` | 已明确授权迁入生产 | 可按规格修改生产代码 |
| `Verifying` | 实现完成，正在执行自动化、产品验收或跨版本验证 | 未完成 Requirement 不得宣称通过；具体版本 Release 状态单独记录 |
| `Released` | 已完成 Release、tag、资产和回下载验证 | 作为生产事实维护 |

## 4. 规格注册表

| 文档编号 | 文档 | 类型 | 规格状态 | 交付状态 | 当前用途 |
|---|---|---|---|---|---|
| `QV-GOVERNANCE-001` | [AGENTS.md](../../AGENTS.md) | 治理规范 | `Accepted` | — | 长期产品、实现、验证与发布约束 |
| `QV-PRODUCT-ACTIVITY-ISLAND-001` | [单任务灵动岛产品规格](../design/quotaview-codex-activity-widget-product.md) | 已发布功能规格 | `Accepted` | `Released` | `0.3.1` 单任务生产行为基线 |
| `QV-PRODUCT-TOKEN-ACTIVITY-001` | [Token 活动图表规格](../design/quotaview-token-activity.md) | 已发布功能规格 | `Accepted` | `Released` | `0.3.3 Build 3` 基线由 `0.3.5 Build 5` 继续继承 |
| `QV-PRODUCT-USAGE-OVERVIEW-002` | [0.3.4 用量概览扩展规格](../design/quotaview-usage-overview-0.3.4.md) | 已发布功能规格 | `Accepted` | `Released` | 已由 `0.3.5 Build 5` 正式发布；完整视觉矩阵仍不标记全量通过 |
| `QV-PRODUCT-APP-UPDATES-003` | [0.3.5 应用检查与更新规格](../design/quotaview-app-updates-0.3.5.md) | 当前功能规格 | `Accepted` | `Verifying` | Build 5 已发布并上线 Feed；等待后续正式 Build 完成 N → N+1 |
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001` | [多任务灵动岛规格](../design/quotaview-codex-activity-island-multitask.md) | 预览版功能规格 | `Accepted` | `Released` | `0.3.2 Preview 1` 独立预览行为基线；不映射到 0.3.3 稳定源码 |
| `QV-DESIGN-WIDGET-001` | [WidgetKit 接入规格](../design/quotaview-widgetkit-solution.md) | 架构/功能规格 | `Accepted` | `Released` | Widget 数据、Target 与验证边界 |
| `QV-EXEC-CORE-002` | [核心架构演进规格](../design/quotaview-core-architecture-evolution.md) | 架构规格 | `Accepted` | `Released`（Phase 0–2、4A–4B；Phase 3 部分） | Token 活动使用官方每日桶；SQLite History 与 Phase 5–7 尚未实施 |
| `QV-EVIDENCE-CORE-0.2.0-001` | [0.2.0 重构报告](../design/quotaview-core-refactor-0.2.0-report.md) | 验证证据 | `Archived` | `Released` | 历史实施与测试证据 |
| `QV-EVIDENCE-DESIGN-QA-001` | [主项目 Design QA](../../design-qa.md) | 验收证据 | — | — | 生产视觉验收历史，证据状态 `Active` |
| `QV-EVIDENCE-MULTITASK-DEMO-QA-001` | [多任务 Demo Design QA](../../Prototypes/CodexActivityMultiTaskDemo/design-qa.md) | Prototype 验收证据 | — | `Released` | 0.3.2 Preview 的历史 Demo 视觉、交互与调试记录 |

以下文件不是产品规格：

- `README.md` / `README.zh-CN.md`：公开产品说明；
- `CONTRIBUTING.md`：外部协作和提交入口；
- `.github/pull_request_template.md`：SDD 变更、验证和发布影响的 PR 证据表；
- `HANDOFF.md`：当前实施与工作区状态；
- `VERSION_HISTORY.md`：已发生的发布历史；
- `docs/reference/`：按门禁读取的外部参考，不具有 QuotaView 决策权；
- `Prototypes/*/README.md`：Prototype 的运行与隔离说明，不替代对应规格。

## 5. 当前迭代追踪矩阵

`0.3.5 Build 5` 与后续 N → N+1 验收使用以下 Requirement ID。详细定义与验收条件位于
[0.3.5 应用检查与更新规格](../design/quotaview-app-updates-0.3.5.md)。

| Requirement ID | 规格范围 | 当前证据 | 当前结论 |
|---|---|---|---|
| `APP-UPDATES-01` | 单一长生命周期控制器与两处设置入口 | `AppUpdateController`、AppDelegate 与设置注入 + 编译 | 已实现；App 启动完成后启动同一控制器 |
| `APP-UPDATES-02` | Debug、非 App 和非预期签名环境无网络更新 | 纯环境模型与控制器测试 | 门禁分支通过；Ad Hoc 包保持不可更新 |
| `APP-UPDATES-03` | 手动检查、独立原生设置行、默认关闭的 24 小时自动检查、显式安装 | `SettingsView`、Info.plist + 正式签名 App | Build 5 已发布左文右开关的独立卡片行；完整视觉矩阵仍等待验收 |
| `APP-UPDATES-04` | HTTPS、EdDSA、签名 Feed、解压前验证、无画像/JS | Info.plist、Keychain 公钥、公开 appcast | 私钥 AES-256 加密备份与恢复校验完成；线上 Feed 逐字节和 EdDSA 验证通过 |
| `APP-UPDATES-05` | Stable-only、macOS 14 与全局递增 Build | `generate-appcast.sh`、版本配置与公开 Feed | `0.3.5 (5)`、最低 14.0、Stable-only 正式资产门禁通过 |
| `APP-UPDATES-06` | Sparkle 嵌套组件内到外签名且 Universal | `build-app.sh`、Developer ID 正式包、`codesign`、`lipo` | App、Sparkle 与嵌套组件均为正式签名 `x86_64 arm64`，公证/Staple 通过 |
| `APP-UPDATES-07` | 两个正式签名公证版本完成 N → N+1 | 发布前端到端验证记录 | 未执行；不得标记 Released |
| `APP-UPDATES-08` | 产品所有者按精确版本显式批准后执行完整 Release 与 appcast；未批准默认排除 | `AGENTS.md`、Handoff、GitHub Release 与线上 Feed | `0.3.5 Build 5` 已完成获准、正式发布和 Feed 部署；后续版本默认不纳入，需重新明确批准 |

### 5.1 已发布的 0.3.4 用量范围

下列 Requirement 已实现并由 `0.3.5 Build 5` 发布；其中 Build 3 的视觉范围
仍等待产品所有者验收。

| Requirement ID | 规格范围 | 当前证据 | 当前结论 |
|---|---|---|---|
| `USAGE-OVERVIEW-01` | 主额度内嵌重置信息并移除独立面板开关 | `QuotaViewFigmaMenu`、`AppPreferences` + 代码审查 | 已实现；菜单栏倒计时开关保持独立 |
| `USAGE-OVERVIEW-02` | `codex_bengalfox` 独立 Spark 窗口与 fail-soft | `CodexProviderAdapter` + `CodexModelsTests` | 映射、缺失和越界降级通过 |
| `USAGE-OVERVIEW-03` | Spark 紧凑中性图表、隐藏条件与动态高度 | `QuotaViewFigmaMenu` + 产品所有者验收 | 产品所有者确认，并批准为 Build 1 基线 |
| `USAGE-OVERVIEW-04` | 最近三十日 Token 汇总 | `EstimatedCostChartModel` + 行为测试 | UTC 三十日边界、窗口外排除与汇总通过 |
| `USAGE-OVERVIEW-05` | `$0.50/M` 缓存输入成本估算与非账单语义 | `EstimatedCostChartModel`、`SettingsView` + 行为测试 | 公式、三十柱几何和缺失数据语义通过 |
| `USAGE-OVERVIEW-06` | 设置顺序、默认值、持久化与 usage Demand | `AppPreferences`、`CodexStatusStore` + 偏好测试 | 实现完成，五项 usage 消费者共同控制可选请求 |
| `USAGE-OVERVIEW-07` | 顶部固定动态面板、状态、语言与 AX | 面板高度模型 + 代码审查 | 自动化边界通过；完整交叉矩阵仍等待逐项验收 |
| `USAGE-OVERVIEW-08` | 验证与发布门禁 | 64 项测试、CI、Universal、版本、架构、资源、签名、公证、Release 与回下载 | 已由 `0.3.5 Build 5` 完成正式发布门禁 |
| `USAGE-OVERVIEW-09` | 版本与发布控制 | `AGENTS.md`、`HANDOFF.md`、版本配置 | `0.3.5 (5)` 已发布；后续 Build 从 6 全局递增 |
| `USAGE-OVERVIEW-10` | 半年历史上限、连续日期格与完整 16 列占位网格 | `TokenActivityGridModel` + 行为测试 | 实现与自动化通过；等待产品验收 |
| `USAGE-OVERVIEW-11` | 最近一天与真实 UTC 日桶语义一致 | `CurrentCodexPresentation`、成本模型 + 行为测试 | 实现与自动化通过；等待产品验收 |

### 5.2 已发布 Token 活动追踪矩阵

`0.3.3 Build 3` 的以下 Requirement 已归档为稳定发布证据：

| Requirement ID | 规格范围 | 当前证据 | 当前结论 |
|---|---|---|---|
| `TOKEN-ACTIVITY-01` | 官方每日桶与四个 UTC 范围 | `CurrentCodexPresentation` + 行为测试 | 实现完成，排序与日期边界通过 |
| `TOKEN-ACTIVITY-02` | 完整 16 列网格与右下对齐 | `TokenActivityGridModel` + 网格测试 | 实现完成，产品所有者确认观感 |
| `TOKEN-ACTIVITY-03` | 深浅五级不透明单色 | `TokenActivityCellPalette` + 代码审查 | 产品所有者确认 Build 3 阶梯；占位格保留透明度 |
| `TOKEN-ACTIVITY-04` | 0.5 秒紧凑 Tooltip 与 AX | `TokenActivityHoverController` + Hover 测试 | 延迟、取消和 K/M/B 行为完成 |
| `TOKEN-ACTIVITY-05` | 顶部固定的动态菜单尺寸 | `MenuBarPanelController` + 几何测试 | 收缩与扩展均由产品所有者确认不跳动 |
| `TOKEN-ACTIVITY-06` | 设置开关、默认月与 Usage Demand | `AppPreferences`、`SettingsView` + 偏好测试 | 实现完成 |
| `TOKEN-ACTIVITY-07` | 发布门禁 | 57 项测试、CI、Universal、签名、公证、Release 与回下载验证 | 完成；交付状态为 `Released` |

0.3.2 Preview 的多任务 Requirement 与发布证据继续由其独立规格维护；不得
用其 `Released` 状态推导多任务实现已进入 0.3.5 稳定版。

## 6. 阅读路由

每次新开发会话按顺序读取：

1. [AGENTS.md](../../AGENTS.md)；
2. [HANDOFF.md → 版本定位入口](../../HANDOFF.md#0-版本定位入口)；
3. [VERSION_HISTORY.md → 当前最新版本](../../VERSION_HISTORY.md#当前最新版本)；
4. 本 SDD 索引的“当前状态快照”；
5. 当前任务对应的唯一规格及其 Requirement ID；
6. 对应的验证证据；只有相关时才读取历史报告或外部参考。

开发与对话流程详见
[SDD 开发流程](./DEVELOPMENT_PROCESS.md)。

## 7. 一致性规则

- `0.3.5 (Build 5)` 必须作为公开稳定版、GitHub Latest、默认下载与公开
  Stable appcast 条目出现在 `HANDOFF.md`、`VERSION_HISTORY.md` 和 README；
  `0.3.3 Build 3` 保留为封存回滚基线；
- 已发布的 `0.3.2 Preview 1` 继续作为独立 Pre-release，不得进入稳定默认
  下载或 appcast；
- 当前迭代、规格状态和交付状态必须同时与 `HANDOFF.md` 一致；
- 当前开发分支和 HEAD 必须从 Git 实时读取，不得在 Handoff 中维护会随提交
  失效的哈希；
- Prototype 不得出现在 `VERSION_HISTORY.md` 的正式版本总览中；
- 历史实施计划中的“当前”“后续”只在其标明的版本时点成立；当前状态表和
  生产代码优先，未实施阶段不得因文档保留而被写成已交付；
- 修改规格状态、交付状态、范围、不变量或验收条件时，必须同步更新本索引；
- 完成发布时，必须按 `AGENTS.md` 同步 Handoff、版本历史、README、Release
  Notes 和资产验证事实；
- 规格与代码冲突时，不得静默选择一方：先核对用户当前指令和生产事实，
  再在同一任务内修正规格或实现。
