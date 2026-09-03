# QuotaView 0.4.5 灵动岛本次任务 Token

> Spec ID：`QV-PRODUCT-ACTIVITY-ISLAND-TURN-TOKENS-013`
>
> 状态：`Accepted / Publishing`
>
> 目标版本：`0.4.5 Build 1`（Sparkle 内部 Build `17`）

## 1. 决策

在不改变现有灵动岛形态的前提下组合两种展示方案：任务运行期间在右侧状态
下方显示本次任务实时 Token；只有收到同一 turn 的真实成功终态后，才在现有
完成停留阶段切换为左右回执：左侧分层显示“已完成”和本次 Token，右侧显示
真实当前额度剩余。紧凑阶段左侧保留“已完成”，右侧使用额度风险色圆环显示
剩余百分比。灵动岛继续使用固定 `402 × 68 pt` 展开表面、量子噪点进度效果、
既有生命周期和悬停透明行为。

“本次任务”严格定义为 Codex 本地任务流中的一个 `turn_id`（Socket 回退中为
`turnId`），不是账号额度周期、模型上下文占用或线程生命周期累计。

## 2. Requirement

| ID | Requirement |
|---|---|
| `TURN-TOKENS-01` | 主通道只读 Codex 已有 rollout JSONL，并且只投影 `task_started`、`token_count`、`task_complete`、计划状态计数和工具类别；Socket/Hook 作为回退。线程与 turn 标识进入状态层前必须哈希，不保存提示词、回复、推理、命令、工具输入输出、diff 或会话原文 |
| `TURN-TOKENS-02` | 主通道以 `total_token_usage.total_tokens` 的线程累计增量计算本次 turn，`last_token_usage.total_tokens` 只在首次附着且缺少前序基线时用于一次性推导基线；Socket 回退使用对应 camelCase 字段，重复通知不得重复累计 |
| `TURN-TOKENS-03` | 新 `turnId` 必须重置本次计数；同一 turn 的计数只能单调增加，缺失或无有效正数时保持不可用，不显示伪造的 `0 tokens` |
| `TURN-TOKENS-04` | 运行态保留现有左右两栏并使用上下两排栅格；左上任务标题与右上状态共享一条视觉中线，左下运行详情与右下本次 Token 共享一条视觉中线；下排两侧统一使用 Asta Sans Regular `11.5 pt`，Token 继续以次要文字色显示“本次 12.8K tokens”等实时累计 |
| `TURN-TOKENS-05` | 只有 rollout 的真实 `task_complete`，或 Socket 回退的真实成功 `turn/completed` 时，展开态才切换为左右完成回执；左栏使用 Semibold `16 pt` 的“已完成”和 Regular `11 pt` 的“本次消耗 12.8K tokens”，`interrupted`、`failed`、Goal 完成和局部工具结束不得触发 |
| `TURN-TOKENS-06` | 完成态右栏读取 `CodexStatusStore` 最新有效主周期快照，只显示垂直居中、右对齐的大号剩余百分比，不显示周期标题；右侧保留 `20 pt` 安全边距，额度不可用时显示破折号，不得伪造 `0%`，也不显示没有数据源支持的“较上次”变化 |
| `TURN-TOKENS-07` | 紧凑完成态左侧显示“已完成”，右侧为 `30 pt` 圆形额度环；圆环与灵动岛胶囊右端半圆同心，中心只显示数值，剩余 `50%–100% / 20%–49% / <20%` 分别使用绿 / 黄 / 红风险色，不可用时使用中性环和破折号 |
| `TURN-TOKENS-08` | 完成量子噪点、四周辉光和描边统一为左紫—中蓝—右青色系；展开态和紧凑态均不显示任何沿边缘环绕的高光点或线性流光，只保留固定渐变描边与外部完成辉光。Reduce Motion 下停止外部辉光呼吸动画 |
| `TURN-TOKENS-09` | 中英文与 VoiceOver 必须包含同一 Token 和额度语义；展开与紧凑岛体尺寸、运行态布局、进度计算、完成真相、完成/隐藏计时和悬停点击穿透行为均不得改变 |

## 3. 数据口径

rollout 的 `total_token_usage`（以及 Socket 回退的 `tokenUsage.total`）是线程
生命周期累计值，不能直接显示为本次任务；`last_token_usage` 也不能在每次
通知上直接相加。QuotaView 在 `task_started` 记录最近一次线程累计值作为基线
并显示：

`本次任务 Token = max(0, 当前 total - turn 起点 total)`

若应用在 turn 进行中首次附着，启动恢复会保留该 turn 的第一条和最新一条
Token 数值：第一条用 `total - last` 推导基线，最新一条恢复当前累计；后续仍
只比较累计值，因此重复 `last` 不会重复计数。

任务定位优先以只读方式查询 `~/.codex/state_5.sqlite` 中最近活动线程的
`rollout_path`，并限制文件必须位于 `~/.codex/sessions`；数据库不可用时才在
该已知目录内按修改时间做有界回退。单行上限 `1 MiB`、启动尾读上限
`16 MiB`、候选线程上限 `24`，运行中只读取追加字节。解析器虽然必须解码一行
JSON，但只把允许的数值、枚举、工作区末级名称和哈希标识送入应用状态，不把
正文类字段保存在模型、缓存或诊断中。

## 4. 验证

1. 解码测试覆盖 rollout 与 Socket 数值字段、哈希标识、非法小数、负数、
   缺失字段、`last > total`，以及 message/reasoning 等正文记录被忽略。
2. Store 测试覆盖首次附着、同 turn 累计增量、重复通知、真实 Stop 后冻结和
   新 turn 基线重置。
3. 展示契约测试覆盖 `12.8K / 1M` 格式、中英文、两栏字号、额度环同心几何、
   风险色阈值、VoiceOver，以及 interrupted、failed 和 Goal 完成不出现成功
   回执。
4. 尾读测试覆盖只恢复活动 turn、忽略历史完成、处理追加完成事件和有界候选；
   再运行 `swift test`、Universal Release 无签名构建、架构/版本/资源检查、
   `git diff --check` 与启动冒烟。
5. 运行态双行层级、完成回执、长标题、中英文与悬停透明叠加效果由产品所有者
   在真实 Codex 任务中验收。

## 5. 当前验证

- `swift test` 130 项通过、0 失败；本地任务流解码、正文忽略、活动 turn
  恢复、增量尾读、真实完成、来源优先级、完成两栏字号、额度环同心几何与
  风险色阈值测试通过。
- Universal Release 无签名构建通过；App、Core、Widget 与 Activity Hook 均为
  `x86_64 arm64`，版本为 `0.4.5 Build 1` / internal `17`，资源与干净临时
  副本的 ad-hoc 签名校验通过。
- 新构建已从干净临时副本启动并保持运行，PID 为 `80828`；启动诊断确认本地
  rollout 主通道继续接收事件。开发 ZIP SHA-256 为
  `fc247a259f9f25f6f405bccbd5308ad1582667ff7bfa55ec34a77c635c99c297`。
- 宿主权限额度探针同时确认主数据可用：`Pro 5x` 协议值 `prolite`，已用
  `52%`、剩余 `48%`；该真实主周期快照现已接入完成态右栏和紧凑额度环。
- 产品所有者已检查运行态与完成态视觉，并批准包含实时 Token、左右布局、
  额度环和紫蓝青完成效果的 0.4.5 候选发布；Developer ID、公证、GitHub
  Release 与 Stable appcast 由发布规格继续执行。
