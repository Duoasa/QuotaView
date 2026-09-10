# QuotaView SDD 注册表

> 文档编号：`QV-SDD-INDEX-001`
>
> 状态：`Accepted`
>
> 生产基线：`0.4.7 Build 2`（内部 `21`）
>
> 当前迭代：0.4.7 Build 2 已合并 main、正式发布，README 与 Stable appcast 已同步

本文件只负责规格发现和状态定位，不复制 Requirement、实现或发布证据。

## 当前规格

| Spec ID | 文档 | 状态 | 当前结论 |
|---|---|---|---|
| `QV-PRODUCT-PROXY-017` | [0.4.7 自定义代理](../design/quotaview-proxy-settings-0.4.7.md) | `Accepted / Released` | 已晋升正式 0.4.7 Build 2；190 项本地测试、main CI、Universal、公证、回下载与签名 Feed 验证通过；用户代理反馈可用，完整验收待继续 |
| `QV-PROTOTYPE-QUANTUM-MOTION-016` | [量子噪点动效与控制台](../design/quotaview-quantum-motion-console.md) | `Accepted / Released` | 用户已验收当前效果；177 项本地及 CI 测试、Universal、签名、公证、回下载与线上 appcast 验证完成；0.4.6 Build 2 已发布 |
| `QV-FIX-CODEX-TOKEN-COMPATIBILITY-015` | [0.4.6 Token 兼容修复](../design/quotaview-codex-token-compatibility-0.4.6.md) | `Accepted / Released` | [链路审计](../design/quotaview-activity-logic-audit-0.4.6.md)的 9 个场景已修复；[重构验证](../design/quotaview-activity-refactor-verification-0.4.6.md)本地及 CI 166 项测试通过，用户已确认真实五步视觉；正式签名、公证、Latest 与 appcast 已验证 |
| `QV-RELEASE-0.4.5-001` | [0.4.5 Build 1 发布](../design/quotaview-0.4.5-release.md) | `Accepted / Released` | 130 项测试、Universal Developer ID、公证/Staple、GitHub Latest、回下载验证与 Stable appcast 在线 EdDSA 均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-CONFIRMATION-REMINDER-014` | [0.4.5 灵动岛等待确认提醒](../design/quotaview-activity-island-confirmation-reminder-0.4.5.md) | `Accepted / Released` | 等待确认满 10 秒显示静态黄色描边和四周光晕；已随 0.4.5 发布 |
| `QV-PRODUCT-ACTIVITY-ISLAND-TURN-TOKENS-013` | [0.4.5 灵动岛本次任务 Token](../design/quotaview-activity-island-turn-token-usage-0.4.5.md) | `Accepted / Released` | rollout 主通道显示实时 turn Token 与成功完成回执；已随 0.4.5 发布 |
| `QV-PRODUCT-ACTIVITY-ISLAND-HOVER-TRANSPARENCY-012` | [0.4.5 灵动岛悬停透明](../design/quotaview-activity-island-hover-transparency-0.4.5.md) | `Accepted / Released` | 悬停时整个灵动岛进入 80% 透明态并保持点击穿透；已随 0.4.5 发布 |
| `QV-PRODUCT-CODEX-SOCKET-AUTOCONNECT-011` | [0.4.5 Codex 本地任务流自动连接](../design/quotaview-codex-socket-autoconnect-0.4.5.md) | `Accepted / Released` | 只读本地任务流主通道、共享 Socket/Hook 回退及量子噪点单一灵动岛已随 0.4.5 发布 |
| `QV-RELEASE-0.4.3-001` | [0.4.3 Build 1 发布](../design/quotaview-0.4.3-release.md) | `Accepted / Released` | 104 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线 EdDSA 均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-QUANTUM-NOISE-009` | [量子噪点效果修正](../design/quotaview-quantum-noise-effect-correction.md) | `Accepted / Released` | 连续相位、压缩上下文可见性、闪灭、文字层级与完成反馈已随 0.4.3 发布；完整视觉矩阵仍待验收 |
| `QV-RELEASE-0.4.2-001` | [0.4.2 Build 1 发布](../design/quotaview-0.4.2-release.md) | `Accepted / Released` | 103 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线 EdDSA 均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008` | [0.4.2 任务连续性修正](../design/quotaview-activity-island-lifecycle-continuity-0.4.2.md) | `Accepted / Released` | 实时事件不再因局部步骤结束而误隐藏或提前完成；完成态只接受真实 `Stop`，已随 0.4.2 发布 |
| `QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007` | [0.4.2 进度条效果库](../design/quotaview-progress-effects-0.4.2.md) | `Accepted / Released` | 四种真实预览、状态配色适配、平滑进度与三个新增效果的完成高亮已随 0.4.2 发布 |
| `QV-RELEASE-0.4.1-001` | [0.4.1 发布](../design/quotaview-0.4.1-release.md) | `Accepted / Released` | 93 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线签名核验均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006` | [进度条灵动岛](../design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Released` | `exec` 计划计数、4 秒 1%识别窗口、单步骤回退、完成高光分层与结束事件收敛已随 0.4.1 Build 1 发布 |
| `QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005` | [灵动岛展开尺寸](../design/quotaview-codex-activity-island-size-0.4.0.md) | `Superseded / Released` | 0.4.1 的 AI 球尺寸能力保留为发布历史；0.4.5 已移除 AI 球及其展开尺寸选择器 |
| `QV-PRODUCT-QUOTA-WINDOWS-003` | [多周期额度展示](../design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 已随 0.3.7 Build 1 发布并进入 Stable appcast |
| `QV-PRODUCT-ACTIVITY-ISLAND-004` | [稳定单任务灵动岛](../design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；多任务实验不在稳定范围 |
| `QV-PRODUCT-APP-UPDATES-003` | [应用检查与更新](../design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.4.6 已进入 Stable Feed；真实 N → N+1 安装操作待记录 |

## 已替代的当前迭代规格

| Spec ID | 文档 | 状态 | 结论 |
|---|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-CODEX-PLAN-010` | [0.4.4 Codex 多步计划兼容](../design/quotaview-codex-plan-compatibility-0.4.4.md) | `Accepted / Superseded` | 0.4.4 未发布；原生计划与共享桥成果已进入 0.4.5 自动发现候选 |
| `QV-RELEASE-0.4.0-001` | [0.4.0 大版本开发](../design/quotaview-0.4.0-development.md) | `Superseded / Released` | 0.4.0 保留为开发身份记录，不发布；成果已由 0.4.1 Build 1 正式发布 |

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
