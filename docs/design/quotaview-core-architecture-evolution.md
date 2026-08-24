# QuotaView 核心架构摘要

> 文档编号：`QV-EXEC-CORE-002`
>
> 文档状态：`Archived`
>
> 已发布范围：0.2.0 核心重构；0.2.1 Widget Extension

本文件是已落地架构边界的按需摘要，不是路线图。旧版 Phase 3/5/6/7、
SQLite、第二 Provider、通知与真实账户操作计划均已归档；只有新的当前 Spec
明确采纳后才能重新进入开发。

## 产品不变量

- QuotaView 是轻量、原生、默认只读的本地用量与状态工具；
- 数据只来自官方本地 CLI/App Server/Provider，不读取浏览器 Cookie、网页、
  Keychain 凭据或用户 Prompt；
- 缺失数据不等于零；数据可用性、额度风险和服务健康互相独立；
- 禁用模块必须停止自身后台任务、子进程、写入和通知检查；
- 额度重置能力固定为 `demoOnly`，不得实现或调用真实 consume；
- UI 只消费稳定 Presentation DTO；架构修改不能借机改变已确认视觉、设置
  key、本地化和辅助功能语义。

## 当前分层

```text
Provider/RPC → Domain Snapshot → RefreshCoordinator → Presentation DTO → UI
                                      ├→ Widget Projector/Writer
                                      └→ optional usage projection
```

- **Domain**：Provider、Entity、Metric 使用稳定命名空间 ID；快照、当前值和
  官方历史桶保持缺失/可用语义；
- **Provider**：静态 Registry 拒绝重复 ID；Codex Adapter 隔离协议细节；
  不提供动态插件或用户脚本运行时；
- **刷新协调**：generation、配置 revision、启用 revision 和账户作用域共同
  拒绝旧结果；replace/coalesce/disable/stop 均可取消、超时并收敛；
- **进程/RPC**：启动和请求使用独立 timeout；stdout 单行上限 1 MiB，stderr
  有界；可选 usage 失败不得污染主额度；
- **Presentation/Demand**：UI 不直接解释原始 RPC；所有 usage 消费者关闭后
  才停止可选请求；
- **写操作**：刷新路径不持有账户操作 Executor；Demo 只返回
  `isSimulation = true` 的本地结果，非 Demo 授权由执行器拒绝；
- **Extension 边界**：Widget 只读取 Foundation-only 脱敏快照，具体契约见
  [`QV-DESIGN-WIDGET-001`](quotaview-widgetkit-solution.md)。

## 已实施 / 未授权

| 能力 | 当前边界 |
|---|---|
| Domain、Codex Provider、刷新协调、Presentation、Demand | 已发布 |
| 官方每日 Token 桶与面板图表 | 已发布；不建立 SQLite 长期历史 |
| Widget Contract / Extension | 已发布 |
| 多 Provider、模型/Agent 明细 | 未实现、未授权 |
| 通知调度和通知设置 | 未实现、未授权 |
| 真实手动/自动账户写操作 | 未实现、未授权；继续 Demo-only |

## 回归要求

- 测试缺失窗口、超界值、可选请求失败、并发旧结果、取消/超时、账户切换、
  Demand、Demo 写边界和 Widget 快照；
- 禁止新增未获规格批准的后台任务、权限、数据库、第三方运行时或真实写路径；
- 当前实现事实优先于本归档；0.2.0 原始验证见
  [`QV-EVIDENCE-CORE-0.2.0-001`](quotaview-core-refactor-0.2.0-report.md)。
