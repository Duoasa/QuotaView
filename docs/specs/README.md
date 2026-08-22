# QuotaView SDD 规格注册表

> 文档编号：`QV-SDD-INDEX-001`
>
> 文档类型：Specification Registry
>
> 状态：`Accepted`
>
> 当前生产基线：`0.3.5 Build 5`
>
> 当前迭代：`0.3.6 Build 2` 灵动岛升级

本文件只负责定位当前工作和规格，不复制 Release 证据、实现细节或历史
Requirement 矩阵。

## 1. 当前状态

| 项目 | 当前值 |
|---|---|
| 公开稳定版 | `0.3.5 Build 5`；事实见 [版本历史](../../VERSION_HISTORY.md#当前最新版本) |
| 当前开发版本 | 产品 `0.3.6 Build 2`；Sparkle 内部序号 `7` |
| 当前产品规格 | `QV-PRODUCT-ACTIVITY-ISLAND-004` |
| 规格 / 交付状态 | `Accepted` / `Verifying` |
| 当前边界 | 只升级单任务灵动岛；多任务实验已排除；不扩大本地数据与权限边界 |
| 当前阶段 | 产品验收完成；已批准 `v0.3.6-build.2` 进入完整 Stable Release 与 appcast 门禁，发布进行中 |
| 当前设置 | 完成后缩小 5...60 秒；缩小后隐藏 5...120 秒；均为 5 秒档位 |
| 并行验证 | `QV-PRODUCT-APP-UPDATES-003` 为 `Accepted / Verifying`，等待真实 N → N+1 |

当前工作区、验证结果和下一步见 [HANDOFF.md](../../HANDOFF.md)。

## 2. 状态模型

- 规格：`Draft` → `Review` → `Accepted`；不用时进入 `Superseded` 或
  `Archived`。
- 交付：`Discovery` → `Prototype` 或 `Planned` → `Implementing` →
  `Verifying` → `Released`。
- 规格被接受不等于已实现；Prototype 被确认不等于已进入生产；构建通过
  不等于已发布。

状态出口和授权边界见 [SDD 开发流程](DEVELOPMENT_PROCESS.md)。

## 3. 活跃规格

| Spec ID | 文档 | 状态 | 用途 |
|---|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-004` | [0.3.6 灵动岛升级](../design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Verifying` | 单灵动岛动画选择、显示开关与缩小/隐藏时间设置；等待产品验收 |
| `QV-PRODUCT-APP-UPDATES-003` | [应用检查与更新](../design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 已发布更新器；后续获准版本完成真实 N → N+1 |

## 4. 已发布与历史参考

以下文档保留追溯价值，但不在默认会话中全文读取。

| Spec ID | 文档 | 定位 | 何时读取 |
|---|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-001` | [稳定单任务灵动岛](../design/quotaview-codex-activity-widget-product.md) | 当前稳定行为基线 | 修改灵动岛生产行为时 |
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001` | [多任务灵动岛 Preview](../design/quotaview-codex-activity-island-multitask.md) | `0.3.2 Preview 1` 独立历史参考，不属于稳定源码 | 本轮明确排除，不读取或迁入 |
| `QV-PRODUCT-TOKEN-ACTIVITY-001` | [Token 活动](../design/quotaview-token-activity.md) | 已发布功能规格 | 修改 Token 图表时 |
| `QV-PRODUCT-USAGE-OVERVIEW-002` | [用量概览](../design/quotaview-usage-overview-0.3.4.md) | 已发布功能规格 | 修改主额度、Spark、成本或用量时 |
| `QV-DESIGN-WIDGET-001` | [WidgetKit 方案](../design/quotaview-widgetkit-solution.md) | 已发布实现参考 | 修改 Widget Target、共享数据或布局时 |
| `QV-EXEC-CORE-002` | [核心架构演进](../design/quotaview-core-architecture-evolution.md) | 历史架构方案，含未实施阶段，不是当前路线图 | 修改核心边界并需要历史决策时 |
| `QV-EVIDENCE-CORE-0.2.0-001` | [0.2.0 重构报告](../design/quotaview-core-refactor-0.2.0-report.md) | 历史验证证据 | 调查相关回归时 |
| `QV-EVIDENCE-DESIGN-QA-001` | [Design QA](../../design-qa.md) | 视觉验收记录 | 视觉任务或核对历史结论时 |

公开产品说明、Handoff、版本历史、Prototype README 和外部参考都不是产品
规格。未跟踪草稿也不进入正式 SDD 调用链。

## 5. 默认阅读路由

1. [AGENTS.md](../../AGENTS.md)：长期约束；
2. [HANDOFF.md](../../HANDOFF.md)：当前工作与版本入口；
3. [VERSION_HISTORY.md → 当前最新版本](../../VERSION_HISTORY.md#当前最新版本)：
   已发生的发布事实；
4. 本注册表：定位当前唯一规格；
5. 当前任务对应的一份规格；
6. 仅在需要时读取相关历史证据或大型参考。

历史 Release Notes 只放在 `VERSION_HISTORY.md` 或 GitHub Release；当前工作
结论只放在 `HANDOFF.md`；Requirement 的定义和验收条件只放在所属规格。

## 6. 维护规则

- 新增或改变产品行为时注册唯一 Spec ID；Requirement ID 保存在所属规格，
  不在本索引复制矩阵。
- 当前迭代、规格状态或交付状态变化时同步本文件和 Handoff。
- 发布、撤回、Latest 或资产事实变化时同步 Version History 和 Handoff；
  README 与 GitHub Release 只维护各自面向用户的内容。
- 大型旧规格不因保留而自动获得当前决策权；其“后续阶段”只有被新的当前
  规格明确采纳后才可实施。
- 规格、代码与用户当前指令冲突时，先核对生产事实，再在同一任务修正。
