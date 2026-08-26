# QuotaView SDD 注册表

> 文档编号：`QV-SDD-INDEX-001`
>
> 状态：`Accepted`
>
> 生产基线：`0.3.7 Build 1`
>
> 当前开发：无；生产 Sparkle 内部更新序号 `11`

本文件只负责规格发现和状态定位，不复制 Requirement、实现或发布证据。

## 当前规格

| Spec ID | 文档 | 状态 | 当前结论 |
|---|---|---|---|
| `QV-PRODUCT-QUOTA-WINDOWS-003` | [多周期额度展示](../design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 已随 0.3.7 Build 1 发布并进入 Stable appcast |
| `QV-PRODUCT-ACTIVITY-ISLAND-004` | [稳定单任务灵动岛](../design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；多任务实验不在稳定范围 |
| `QV-PRODUCT-APP-UPDATES-003` | [应用检查与更新](../design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | Stable Feed 已发布；真实 N → N+1 安装操作待记录 |

当前版本与下一步见 [Handoff](../../HANDOFF.md)，不可变发布事实见
[Version History](../../VERSION_HISTORY.md#当前最新版本)。

## 按需规格与历史参考

| Spec ID | 文档 | 读取条件 |
|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001` | [0.3.2 多任务 Preview](../design/quotaview-codex-activity-island-multitask.md) | 仅研究公开 Preview；不能静默迁入稳定版 |
| `QV-PRODUCT-TOKEN-ACTIVITY-001` | [Token 活动](../design/quotaview-token-activity.md) | 修改范围、网格、Tooltip 或面板收展时 |
| `QV-PRODUCT-USAGE-OVERVIEW-002` | [用量概览](../design/quotaview-usage-overview-0.3.4.md) | 修改主额度、Spark、30 日用量或成本时 |
| `QV-DESIGN-WIDGET-001` | [WidgetKit 契约](../design/quotaview-widgetkit-solution.md) | 修改 Widget Target、共享快照、App Group 或布局时 |
| `QV-EXEC-CORE-002` | [核心架构摘要](../design/quotaview-core-architecture-evolution.md) | 修改 Provider、刷新、投影或写操作边界时 |
| `QV-EVIDENCE-CORE-0.2.0-001` | [0.2.0 重构报告](../design/quotaview-core-refactor-0.2.0-report.md) | 调查 0.2.0 架构回归时 |
| `QV-EVIDENCE-DESIGN-QA-001` | [Design QA](../../design-qa.md) | 核对历史视觉验收结论时 |

## 阅读与维护规则

1. 默认只读 `AGENTS.md`、`HANDOFF.md`、版本历史当前节、本注册表和任务对应
   的一份规格；历史参考按需读取。
2. 状态采用：规格 `Draft / Review / Accepted / Superseded / Archived`；
   交付 `Discovery / Prototype / Planned / Implementing / Verifying / Released`。
3. 新功能、用户可见行为或架构边界变化注册唯一 Spec ID；小型修复可复用
   现有 Requirement，文档修复可标记 `Spec impact: None`。
4. 当前迭代或规格状态变化同步 Handoff；发布、撤回、Latest 或资产变化同步
   Version History 与 Handoff。
5. 历史规格中的计划不构成当前授权。Prototype 验收不等于生产验收，构建
   通过不等于发布。

状态出口和授权边界见 [SDD 开发流程](DEVELOPMENT_PROCESS.md)。
