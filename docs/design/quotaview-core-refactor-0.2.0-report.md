# QuotaView 0.2.0 核心重构归档报告

> 文档编号：`QV-EVIDENCE-CORE-0.2.0-001`
>
> 状态：`Archived / Released`
>
> 日期：2026-07-28

本文只证明 0.2.0 当时的实施与验证，不驱动当前实现。当前边界见
[`QV-EXEC-CORE-002`](quotaview-core-architecture-evolution.md)，版本事实见
`VERSION_HISTORY.md`。

## 已交付

- 引入稳定 Provider/Entity/Metric ID、标准化 Snapshot 和 Codex Adapter；
- 分离数据可用性、额度风险与服务健康；缺失主窗口不再解释为零；
- `RefreshCoordinator` 使用 generation、配置/启用 revision 与账户作用域，
  支持 replace、coalesce、disable、stop 和旧结果拒绝；
- App Server 使用独立启动/请求 timeout、有界 stdout/stderr、取消处理；
  可选 usage 失败不污染主额度；
- UI 改为消费 `CurrentCodexPresentation`；Token 显示均关闭时停止 usage 请求；
- 写操作保持 `demoOnly`，刷新路径不能产生账户副作用；
- 建立 Foundation-only Widget Contract 预留；真正 Extension 于 0.2.1 发布。

0.2.0 未交付 SQLite History、第二 Provider、模型/Agent 明细、通知、Widget
Extension 或真实账户操作；这些旧计划不构成当前待办。

## 当时验证

- `swift test` 28 项通过，覆盖 Domain、刷新并发、超时/输出边界、设置 Demand、
  Demo 边界和 Widget schema；
- 无签名 Universal Release 构建通过，App 与 Core 均包含 `x86_64 arm64`；
- App 为 `0.2.0 (1)`，图标、Assets 与三款 Asta Sans 存在；
- App/ZIP 体积相对 0.1.5 Build 6 分别增加 8.16%/4.73%，低于当时 15% 门禁；
- 未发现真实 consume、截图、自动展开/点击或 UI QA 入口。

该验证不证明后续版本的性能、视觉、签名、公证或 Widget 共享容器；对应事实
必须从当前代码、最新规格与版本历史重新核对。
