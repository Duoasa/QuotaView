# QuotaView 0.4.4 Codex 多步计划兼容

> Spec ID：`QV-PRODUCT-ACTIVITY-ISLAND-CODEX-PLAN-010`
>
> 状态：`Accepted / Superseded`
>
> 目标版本：`0.4.4 Build 1`（Sparkle 内部 Build `16`）

## 1. 目标

在不解析提示词、终端文本或转录文件的前提下，让灵动岛兼容新版 Codex 的
原生计划、Goal、等待和中断状态。已有 Activity Hook 与
`tools.update_plan(...)` 精确计数继续作为旧宿主回退。

本轮只建立 `0.4.4` 开发候选、完成必要自动化检查、Universal 构建和启动
冒烟测试；不提交、不推送、不发布。视觉、主要交互和辅助功能矩阵由产品
所有者运行应用后验收。

## 2. 已验证协议与环境边界

- App Server 的 `turn/plan/updated` 提供 `pending`、`inProgress`、
  `completed` 三类步骤状态，可直接汇总数量；步骤正文和 explanation 不进入
  QuotaView 数据模型。
- `turn/completed` 必须区分 `completed`、`interrupted` 与 `failed`；只有真实
  completed 才进入绿色完成态和 100%。
- `thread/status/changed` 的 `waitingOnApproval` 与 `waitingOnUserInput` 都是
  明确等待状态。
- Goal 是跨轮次的单一目标，不是结构化步骤清单。Goal-only 任务不得据此
  伪造步骤总数或“1/4”。
- Codex Desktop 默认使用宿主私有 stdio，QuotaView 不能旁路订阅。0.4.4
  增加显式 opt-in 的共享 App Server 模式：Desktop 与 QuotaView 在下次启动
  后通过同一个 Unix WebSocket 传输连接；未启用或共享传输不可达时继续使用
  Activity Hook。不得通过读取 transcript、抓取终端文本或轮询正文绕过该
  边界。
- 共享客户端只使用 `thread/loaded/list`、`thread/resume` 和实时通知；订阅
  时排除历史 turns，进程内只保留线程与 turn 标识的 SHA-256 哈希。QuotaView
  不拥有共享服务的生命周期，退出时不得终止仍被 Codex 使用的服务。
- Codex CLI `0.152.1` 默认未启用 `tools.update_plan.enabled`。真实隔离探针
  在打开该线程级开关后，四步任务产生 9 次 `turn/plan/updated`；未打开时
  同一类任务只产生 turn、item 与 Hook 生命周期事件。Plan 模式产生
  `item/plan/delta` 和最终 plan item，但不产生带步骤状态的
  `turn/plan/updated`。

## 3. Requirement

| ID | Requirement |
|---|---|
| `CODEX-PLAN-01` | 新增隐私安全的 App Server 通知解码器，只接受已知通知与状态；事件、线程和 turn 标识只保留 SHA-256 哈希 |
| `CODEX-PLAN-02` | 原生计划只保留 completed / in-progress / pending 数量，最多 100 步；不保存 step、explanation、Goal objective 或其他正文 |
| `CODEX-PLAN-03` | 原生计划优先于同一 turn 的 legacy `update_plan`；同一来源内的可见进度不得倒退，运行中继续封顶 95% |
| `CODEX-PLAN-04` | Goal-only 状态可以显示“跟进目标”等操作语义，但 `approximateProgressFraction` 必须保持空值，不伪造步骤计数 |
| `CODEX-PLAN-05` | `Interrupt`、原生 interrupted 和 failed 是真实终止事件；中断不显示完成高光或 100%，失败进入错误态 |
| `CODEX-PLAN-06` | `waitingOnApproval` 与 `waitingOnUserInput` 分别映射为等待确认和等待输入，均不得继续显示正在执行 |
| `CODEX-PLAN-07` | Activity Hook schema 升级到 v3，安装器登记 `Interrupt`；队列中的 schema v1/v2 继续可解码 |
| `CODEX-PLAN-08` | App Server `thread/list` 覆盖 Desktop、CLI、VS Code、子 Agent 等公开 source kind；旧服务器拒绝新参数时回退旧请求 |
| `CODEX-PLAN-09` | 不改变灵动岛容器、既有四种进度效果、完成反馈、延时收起和固定排版几何 |
| `CODEX-PLAN-10` | 版本设置为 0.4.4 Build 1 / internal 16；完成 `swift test`、Universal 无发布签名构建和进程启动冒烟，主要测试与视觉审核等待产品所有者 |
| `CODEX-PLAN-11` | 共享 App Server 必须显式 opt-in；使用 Unix WebSocket 订阅当前已加载任务，断线可重连，不读取任务正文，且 QuotaView 退出时不终止共享服务 |

## 4. 状态与优先级

```text
App Server native plan ─┐
                        ├─ 同一 turn 选择可信来源 ─ 近似进度（<= 95%）
Activity Hook legacy ───┘

turn completed     -> completed / 100%
turn interrupted   -> standby / 保留未完成语义 / 启动收起
turn failed        -> error / 不显示完成反馈
Goal-only          -> active operation / 无步骤进度
```

同一 turn 内 native 计划一旦出现，后续 legacy 计划不能覆盖它。不同 turn 必须
清空旧计划。原生空计划表示清除该 turn 的计划；损坏、未知或超限的数据直接
拒绝，不进行猜测。

## 5. 验证与退出标准

1. 单元测试覆盖原生四步计划、来源优先级、单调性、Goal-only、等待、
   completed / interrupted / failed、隐私和旧 schema 兼容。
2. Activity Hook 测试覆盖 `Interrupt` 登记及 schema v3 输出。
3. `swift test` 通过，Universal app 同时包含 `arm64` 与 `x86_64`。
4. 核对 `CFBundleShortVersionString = 0.4.4`、`CFBundleVersion = 16`、
   产品显示 Build = 1，并完成一次非发布启动冒烟。
5. 不截图、不自动展开、不替代产品所有者视觉验收；最终状态记录为“等待用户
   验收”。
6. 只有运行中的 QuotaView 进程从与 Codex 任务相同的 App Server 传输收到
   `turn/plan/updated`，才可把原生数据桥标记为通过；伪造通知、测试 fixture、
   独立 App Server 或 Hook 回退均不能替代这项端到端验证。

## 6. 当前验证（2026-09-03）

- `swift test`：117 项通过，0 失败；新增覆盖 opt-in/socket 解析、客户端帧
  掩码，以及分片文本、ping/pong 与合并 WebSocket 帧。
- Universal Release 本地开发构建通过；App、Widget 和 Activity Hook 均为
  `x86_64 arm64`。
- 构建身份为 `0.4.4 Build 1` / internal `16`，`AppIcon.icns`、
  `Assets.car` 和嵌入组件检查通过。
- 使用 ad-hoc 签名完成启动冒烟，0.4.4 主进程保持运行；开发包 SHA-256 为
  `573b29f81fb74707b163a62ce87aaf01a975d4da7cbc8d1114f69f1651ac176c`。
  未执行 Developer ID 签名、公证、发布、commit 或 push。
- 真实 Codex `0.152.1` 隔离探针在打开 `tools.update_plan.enabled` 后完成四步
  串行任务并产生 9 次原生计划更新；捕获的一条真实通知由 0.4.4 解码器正确
  汇总为 4 步。临时任务、通知和探针文件已删除。
- 共享 App Server 服务端双客户端探针已验证 `thread/loaded/list`、
  `thread/resume` 和完整四步状态序列。运行中的 0.4.4 QuotaView 随后连接同一
  Unix WebSocket，真实 Codex 客户端在该服务上串行完成四步任务；QuotaView
  诊断记录收到 5 次 `activity_source=appServer` 原生计划通知，并在任务正常
  结束后收到同一 session/turn 的真实 `Stop`。Activity Hook 在该任务中被
  禁用，因此本次结果不是 legacy 回退。
- 原生共享数据桥的进程级端到端退出标准已经满足。当前 Codex Desktop 尚未
  在本任务中重启，因此 Desktop 发起任务的最终用户验证，以及主要功能、
  视觉、交互和辅助功能验收仍等待产品所有者；不得把本轮冒烟记录为视觉通过。
- 开发环境已设置 `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1`，下次启动 Codex
  Desktop 时才会切换到共享服务。未设置该显式开关的用户继续走原有稳定路径。
- 0.4.4 未发布；其原生计划适配与共享桥成果已由
  `QV-PRODUCT-CODEX-SOCKET-AUTOCONNECT-011` 继承，并提升为 0.4.5 的默认
  attach-only 自动发现方案。
