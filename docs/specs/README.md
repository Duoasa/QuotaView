# QuotaView SDD 规格索引

> 文档编号：`QV-SDD-INDEX-001`
>
> 文档类型：SDD 规格注册表（Specification Registry）
>
> 规格状态：`Accepted`
>
> 生效日期：2026-08-05
>
> 当前生产基线：QuotaView `0.3.1 (Build 2)`
>
> 当前进行中工作：Codex 灵动岛多任务适配
>
> 当前交付阶段：`Verifying`（`0.3.2 Preview 1` 发布门禁）

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
起已进入 `main`；用户于 `2026-08-05` 授权将多任务能力迁入生产，当前生产
实现位于独立预览分支，仍不得把未完成的构建写成已发布。

以下本地对象默认排除在正式调用链外：未跟踪的旧
`Prototypes/CodexActivityMetalDemo/`、受 `AGENTS.md` 门禁约束的未跟踪
`docs/reference/`，以及未跟踪图片。它们不是当前规格或验收证据；除非用户
明确授权相应对象并完成注册，不得读取后直接影响生产实现。

## 2. 当前状态快照

| 维度 | 当前事实 |
|---|---|
| 公开生产版本 | `0.3.1 (Build 2)` |
| 生产版本状态 | 已发布；GitHub Latest；Developer ID 签名并完成 Apple 公证 |
| 当前开发代码版本 | `MARKETING_VERSION = 0.3.2`，`CURRENT_PROJECT_VERSION = 1`，渠道 `preview` |
| 当前迭代 | Codex 灵动岛多任务适配 |
| 当前规格 | `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001` |
| 规格状态 | `Accepted`：固定单岛、多任务列表和 Demo 视觉基线已确认 |
| 交付状态 | `Verifying`：核心实现、自动化和状态轮播已通过，正在完成预览版发布门禁 |
| Prototype 自动化 | 38 项测试通过，0 失败（2026-08-04）；不能替代生产测试 |
| 生产源码状态 | 已接入任务注册表、独立生命周期、自动优先级、可选 AX 标题跟随、固定任务列和紧凑态入口 |
| 生产自动化 | `swift test` 60 项通过、0 失败（2026-08-05）；Universal Xcode Release、静态门禁和 Developer ID 本地签名候选包通过，App、Widget、Hook、Core 均为 `x86_64 arm64` |
| 本地验收候选包 | `dist/QuotaView-v0.3.2-preview.1.zip`；Developer ID 签名、未公证；已安装运行，仅用于产品验收 |
| 发布目标 | `0.3.2 (Build 1) Preview 1`；发布已获授权，计划 tag `v0.3.2-preview.1`，尚未创建 |
| 稳定回滚基线 | `0.3.1 (Build 2)` / `v0.3.1-build.2` / `3119171f45163fe45d68a4f774a0488968f14fd7` |
| 当前验收 | Demo 基线已有产品所有者确认；`2026-08-05` 生产实机六状态轮播与 SessionEnd 清理已由产品所有者确认通过；语言、Widget 状态共享、辅助功能及完整交互矩阵继续验收 |

### 当前迭代边界

- Prototype 位于
  [`Prototypes/CodexActivityMultiTaskDemo`](../../Prototypes/CodexActivityMultiTaskDemo/README.md)，
  与生产 Target 隔离；
- 当前允许按已接受规格修改生产 `Sources/`、测试、版本配置和预发布构建脚本；
- 用户已明确授权创建 `v0.3.2-preview.1` 与 GitHub Pre-release；在签名、
  公证、资产验证和 Release 实际完成前，不得把计划资产写成发布事实；
- Demo 的冻结产品方向继续有效；调试可以修复实现偏差，但改变固定单岛、
  尺寸、任务列、隐私或交互方向必须先更新规格并取得产品所有者确认；
- 当前工作不得改变 `0.3.1 (Build 2)` 的发布事实。

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
| `Verifying` | 实现完成，正在执行自动化和产品验收 | 不得提前发布 |
| `Released` | 已完成 Release、tag、资产和回下载验证 | 作为生产事实维护 |

## 4. 规格注册表

| 文档编号 | 文档 | 类型 | 规格状态 | 交付状态 | 当前用途 |
|---|---|---|---|---|---|
| `QV-GOVERNANCE-001` | [AGENTS.md](../../AGENTS.md) | 治理规范 | `Accepted` | — | 长期产品、实现、验证与发布约束 |
| `QV-PRODUCT-ACTIVITY-ISLAND-001` | [单任务灵动岛产品规格](../design/quotaview-codex-activity-widget-product.md) | 已发布功能规格 | `Accepted` | `Released` | `0.3.1` 单任务生产行为基线 |
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001` | [多任务灵动岛规格](../design/quotaview-codex-activity-island-multitask.md) | 当前功能规格 | `Accepted` | `Verifying` | `0.3.2 Preview 1` 发布门禁 |
| `QV-DESIGN-WIDGET-001` | [WidgetKit 接入规格](../design/quotaview-widgetkit-solution.md) | 架构/功能规格 | `Accepted` | `Released` | Widget 数据、Target 与验证边界 |
| `QV-EXEC-CORE-002` | [核心架构演进规格](../design/quotaview-core-architecture-evolution.md) | 架构规格 | `Accepted` | `Released`（仅 Phase 0–2、4A–4B） | 当前核心架构不变量；Phase 3、5–7 尚未实施 |
| `QV-EVIDENCE-CORE-0.2.0-001` | [0.2.0 重构报告](../design/quotaview-core-refactor-0.2.0-report.md) | 验证证据 | `Archived` | `Released` | 历史实施与测试证据 |
| `QV-EVIDENCE-DESIGN-QA-001` | [主项目 Design QA](../../design-qa.md) | 验收证据 | — | — | 生产视觉验收历史，证据状态 `Active` |
| `QV-EVIDENCE-MULTITASK-DEMO-QA-001` | [多任务 Demo Design QA](../../Prototypes/CodexActivityMultiTaskDemo/design-qa.md) | Prototype 验收证据 | — | `Prototype` | Demo 视觉、交互与调试记录 |

以下文件不是产品规格：

- `README.md` / `README.zh-CN.md`：公开产品说明；
- `CONTRIBUTING.md`：外部协作和提交入口；
- `.github/pull_request_template.md`：SDD 变更、验证和发布影响的 PR 证据表；
- `HANDOFF.md`：当前实施与工作区状态；
- `VERSION_HISTORY.md`：已发生的发布历史；
- `docs/reference/`：按门禁读取的外部参考，不具有 QuotaView 决策权；
- `Prototypes/*/README.md`：Prototype 的运行与隔离说明，不替代对应规格。

## 5. 当前迭代追踪矩阵

当前多任务工作使用以下稳定 Requirement ID。详细定义与验收条件位于
[多任务灵动岛规格](../design/quotaview-codex-activity-island-multitask.md)。

| Requirement ID | 规格范围 | 当前证据 | 当前结论 |
|---|---|---|---|
| `MT-SCOPE-001` | 单一 `NSPanel`、单任务行为不回归 | `CodexActivityIsland.swift` + 生产测试 | 单/多任务共用单一生产面板；待实机验收 |
| `MT-DATA-001` | 按 `sessionHash` 隔离任务与生命周期 | `CodexActivityStore` + 交错/结束/计时测试 | 首版生产实现完成，自动化通过 |
| `MT-SELECT-001` | 用户焦点优先与自动降级仲裁 | `CodexActivityStore` + `CodexFocusedTaskTitleReader.swift` | 自动优先级与可选标题跟随已实现；待真实 Codex 验收 |
| `MT-UI-001` | `496 × 152 pt` 固定最大态与任务列 | `CodexActivityIsland.swift` + 连续窗口测试 | 首版生产实现完成；等待视觉验收 |
| `MT-UI-002` | `52 pt` 紧凑态与“共 N 项”展开 | 动态宽度、跑马灯和 Press 入口 | 首版生产实现完成；等待交互验收 |
| `MT-MOTION-001` | 任务列、玻璃选择态、Metal 与 Reduce Motion | 生产任务列、选择玻璃、跑马灯和静态降级 | 六状态生产实机轮播通过；Reduce Motion 与完整节奏矩阵继续验收 |
| `MT-PRIVACY-001` | 最小 AX 标题读取、禁止控制或完整扫描 | 有界顶部标题区读取器 + 设置说明 | 已实现只读降级；待权限授予/撤销实机验收 |
| `MT-A11Y-001` | VoiceOver、Increase Contrast、Reduce Motion | 生产 AX 标签、Press、Reduce Motion | 首版实现完成；等待产品矩阵验收 |
| `MT-VERIFY-001` | 自动化、Release 构建、视觉矩阵 | 60 项生产测试、Universal Release、静态门禁、本地签名候选包与六状态实机轮播通过 | 其余产品验收待完成 |

以上为 `Verifying` 阶段证据。产品所有者已接受以预览版公开当前能力与
不足；只有签名、公证、tag、GitHub Pre-release 和回下载验证全部完成后，
才能把当前结果写成 `Released`。

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

- `0.3.1 (Build 2)` 必须继续作为公开稳定版与回滚基线出现在
  `HANDOFF.md`、`VERSION_HISTORY.md` 和 README；开发配置可以按明确授权
  使用 `0.3.2 (Build 1) Preview 1`，但不得提前改变公开 Latest；
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
