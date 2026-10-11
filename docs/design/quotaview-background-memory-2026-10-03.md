# 记忆整理的来源、生命周期与底栏展示

Spec ID：`QV-PRODUCT-ACTIVITY-ISLAND-BACKGROUND-MEMORY-001` · `Accepted / Verifying`。
整理：2026-10-08；当前运行包及验证见 [Handoff](../../HANDOFF.md)。

## 目标与边界

- 原生记忆整理不进入用户会话列表/计数、不抢选中或弹出，使用既有独立底栏 AI 球。
- 来源以原生 `memory_consolidation` 或精确当前 turn 的同名 start trigger 为据；不能凭 memories 标题、目录、模型缺失或工具参数判定。
- 线程来源与本次执行目的分别保存。Hook session 可能是宿主身份，不能直接当作原生 thread；只有唯一准确 turn 证据才能绑定，冲突时拒绝迁移。
- 元数据只补身份，不生成开始/完成事件；真实生命周期与当前目录 generation/轮次一起准入。迟到身份只撤回同 turn 的 Hook 别名卡，不清除父会话新轮次。
- 完成、失败、中断和断线保留真实状态。来源/执行缓存有界，旧事件、迟到元数据不复活已结束或逐出的任务。
- 底栏球固定 18 pt、压缩上下文效果和“记忆整理 / Memory consolidation”文字；Tooltip 呈现真实状态。隐藏、暂停和减少动态遵循原渲染门禁。

共享读取预算、Registry、迟到身份、恢复和子任务边界统一在[信息契约](../specs/codex-island-information-contract.md#同步预算与恢复)维护；视觉参数统一在[界面规则](QUOTAVIEW_UI_RULES.md)。

## 证据与未完成项

2026-10-05 曾以两个真实临时线程的原生 start 证明定位 Hook session 与原生 thread 不一致；随后补齐共享宿主、冲突 turn、迟到身份、父新轮次和终态先到反例。该阶段 124 项隔离冒烟与交付核验通过，不能作为后续版本重复测试结论。

完整哈希映射、首次失败、构建/运行流水与旧 PID 见[清理前原文](../archive/maintenance-20261008/README.md)。真实记忆任务、并行父子任务及长期运行继续由用户验收；本轮清理未启动虚拟任务或改变运行数据。
