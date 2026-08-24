# QuotaView 多任务 Codex 灵动岛 Preview 归档

> 文档编号：`QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001`
>
> 规格状态：`Archived`
>
> 交付状态：`Released`（`0.3.2 Preview 1`）

本文件只保存公开 Preview 的历史边界，不是当前路线图。稳定生产版使用
[`QV-PRODUCT-ACTIVITY-ISLAND-004`](quotaview-codex-activity-island-0.3.6.md)，
不得从本归档静默迁入多任务代码。

## Preview 范围

- 在一个固定灵动岛内按 `sessionHash` 维护多个任务；最大态为 `496 × 152 pt`，
  右侧最多显示三行任务轨道，紧凑态显示多任务摘要；
- 使用稳定优先级仲裁主任务，并允许连续滑动任务窗口；
- 可选“跟随当前 Codex 任务”只做有界、只读的辅助功能标题匹配；无法高
  置信度命中时安全降级，不控制 Codex、不读取正文；
- 保留 Metal 状态反馈、玻璃外壳、最大/紧凑/隐藏生命周期、Reduce Motion
  和 VoiceOver 操作；
- 隐私链路仍只接收脱敏 Hook 元数据，不读取 Prompt、命令、输出或会话内容。

## 已知不足

- Hook 传递和本机调度可能造成事件响应延迟；
- 标题未解析、重复、快速变化或 Codex UI 改版时，当前任务跟随可能滞后或
  失效；
- 任务切换、长标题跑马灯和收展节奏仍需优化。

这些不足是 Preview 未晋升稳定版的原因。旧文档中的实施 Phase、未来设置
和“生产尚未开始”跟踪表已经失效，均不保留为待办。

## 归档与发布事实

- tag：`v0.3.2-preview.1`；
- 归档分支：`codex/archive-0.3.2-preview.1-multitask-island`；
- 本地 Prototype：`Prototypes/CodexActivityMultiTaskDemo`；
- 资产、提交、签名、公证和 Release URL 见
  [`VERSION_HISTORY.md`](../../VERSION_HISTORY.md#032-build-1-preview-1)。

后续若重新开发多任务，必须建立新的当前 Spec，重新确认状态仲裁、当前任务
跟随、辅助功能权限、布局与隐私边界；本归档不构成实现或发布授权。
