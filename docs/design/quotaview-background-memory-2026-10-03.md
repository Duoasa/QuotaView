# 记忆整理的来源、生命周期与底栏展示

Spec ID：`QV-PRODUCT-ACTIVITY-ISLAND-BACKGROUND-MEMORY-001`
状态：`Accepted / Verifying` · 2026-10-04

用户已授权统一调整来源解析、事件接收和展示，并要求记忆整理不进入会话列表，改为底栏 AI 球；完成本地验证后推送 GitHub，CI 通过后合并 main。

## 识别和通路

- 持久会话来源使用同一 thread 的 `threadSource` / `thread_source` 精确等于 `memory_consolidation`，或原始 `source` 为 `internal` / `subagent` / `subAgent` 的同名枚举值，分类为 `memoryConsolidation`。下面的精确执行元数据仅对当前轮次分类；名称、目录、模型缺失和 `unknown` 不能证明身份。
- 2026-10-03 用户反馈 `memories_v2` 仍进入列表。当前 Codex 的这类临时线程不写 state_5.sqlite 或 rollout，也没有 Desktop owner；只有 Hook 到达。外部日志结构 `TurnInputRequest.start.turn_trigger` 提供明确的 `memory_consolidation`，这是轮次证据而不是永久会话来源。补充通路只匹配精确线程与 Submission.id/Hook turnHash，已核对两个真实 Hook 会话的轮次关联，不从名称推断身份。
- 日志适配器只读所选目录的 logs_2.sqlite，限定原生 target/module/file、24 小时、128 条正文、2 MiB 总量、64 KiB 单条与 50 ms 查询预算。2026-10-04 改为目录/generation 共用读取服务、已观察轮次优先和薄索引游标推进，返回覆盖/失败集合；部分读取保留其他线程已验证证据，成功覆盖的新非记忆 start 仅撤销该线程旧证明。Rust Debug 结构内的引号正文不参与字段解析；旧轮次、冲突、损坏结构不获得新的分类。精确身份早于事件到达时由 Store 保留 pending，准入同一轮次才消费；不伪造生命周期或授予 Desktop 应答能力。完整契约见[信息通信规格](../specs/codex-island-information-contract.md)。
- 专用轮次分类与来源分类分开保留。当前日志记忆轮次可迁入后台通路；后续不同轮次撤销这份临时标签并恢复真实来源。明确 thread source 的记忆/内部身份不被临时标签撤销覆盖；前端列表与后台球使用相同结算结果。
- 分类与运行状态独立。旧泛内部身份可被更精确的记忆标识补全；同批矛盾来源保持内部类，新明确非记忆内部来源撤销旧记忆标签。稀疏数据不能把已知记忆重新变成用户会话。
- App Server 保留来源与轮次元数据，记忆生命周期走独立活动通路；公开正文、Token 与问答能力不进入用户通路。Desktop 仅观察记忆的轮次和运行状态，不产生问答句柄或应答能力。
- Local discovery 保留确定的记忆任务，来源更新即发布分类，不等待日志追加，不伪造任务开始。Hook 继承同一 hash 的可靠来源或只读 SQLite 分类；command Hook 没有专用来源字段，不虚构字段。
- 以对应 thread ID / 线程哈希绑定来源。App Server 的会话树共享 session ID 不能用于把父子任务一起分类。临时内部任务可能不落盘或不被接口公开，缺失专用来源时维持未知。

## 生命周期和展示

- Store 保存独立、有界的记忆快照；开始、工作、完成、失败、中断及结束依据真实事件。来源失效为“状态待更新”，重连的权威当前轮次可恢复状态；不以超时伪造完成。
- 权威分类迟到时，撤回原普通卡片、选择、请求附着及用户统计，保留原轮次和终态证据。没有提交、归档 Codex 或回答任务的副作用。
- 会话数量、运行/完成统计、任务列表、用户待确认提示与自动展开仅使用用户会话。后台记忆开始或结束不会抢占当前页或自动展开。
- 主任务页底栏会话计数右侧放置 18 pt 现有 AI 球，与刘海收起状态共用 `IslandSmallActivityOrb`，保持栏高和刷新/设置位置。收起状态的30pt仅为排布槽位，底栏不继承；原22pt底栏球直径比18pt大22.2%，已于2026-10-04统一。悬停与辅助功能说明“记忆整理”及真实状态；多个任务聚合为一球，优先显示仍运行或状态待更新的任务，否则显示最近终态。中英文由 AppCopy 提供。
- 复用 AI 球现有状态和动态效果。收起、隐藏、锁屏和减少动态沿用播放门禁；不添加逐帧 SwiftUI 更新、第二个生命周期计时器或演示数据。

## 验证与交付

2026-10-04 用户再次报告 memories 普通卡。已确认运行 Core 指纹及全部旧交付输入一致，排除旧运行包；本次真实 start 54385 bytes，严格旧解析在采样时也能匹配，因此不能把这一实例简单归因于格式变化或预算溢出。梳理发现早到身份被 Store 丢弃而 Local 只发差量、全局记录窗口/失败全空、warm 来源缓存和轮次读取节流等结构性缺口。新服务真实只读探针连续三次精确匹配目标轮次，22/34/36 ms；部分覆盖表示历史游标未扫完，不能清除已验证目标。实现及最终交付证据见 Handoff 最新节。前次 198 项通过是当时夹具范围的结果，不覆盖本次发现的乱序和多通道缺口。

本轮最终 239 项相关冒烟零失败，Debug arm64 构建、156 项生产输入和签名/实际加载核对通过；开发运行包已替换，PID 91302。证据 `.build/073-information-contract-smoke.log`、`.build/073-information-contract-build.log`、`.build/073-information-contract-delivery.json`。来源与执行容量独立管理，子 agent 不冒充记忆或普通用户任务；本轮增量未提交推送，实际显示与交互待用户验收。

2026-10-03 临时记忆补充：最终 198 项相关冒烟零失败，含 13 项新读取/解析反例和 4 项前端作用域迁移；覆盖伪造正文、旧轮次、超限、重复记录预算、停止/淘汰撤销及正常任务恢复。真实只读探针验证目标原生记录 5409 bytes、线程和轮次关联一致，查询 32 ms；首次冷读达到预算时维持未知，由既有刷新重试。证据 `.build/073-interaction-fixes-smoke.log`、`.build/073-ephemeral-memory-smoke.log`、`.build/073-ephemeral-memory-budget-smoke.log`。最终 Debug arm64 构建、155 项生产输入和签名/实际加载路径通过，开发包 PID 17729；证据 `.build/073-interaction-fixes-build.log`、`.build/073-interaction-fixes-delivery.json`。本轮源码尚未提交，视觉待用户验收；以下为此前持久来源交付。

154 项相关冒烟零失败，包含 37 项新增记忆专项检查；覆盖来源格式/反例、迟到分类与无追加日志更新、用户请求隔离、完成/失败/中断、断线/恢复、列表计数与自动展开，并复验原用户待确认、提问草稿及 Desktop 跟随撤销边界。类别缓存不代替仍有效的来源、轮次或应答资格。证据 `.build/073-background-memory-smoke.log`，现有展示基准 P95 4.43 ms，仅代表有界状态投影检查。

Debug arm64 构建通过，证据 `.build/073-background-memory-build.log`。构建包位于 `.build/Development073BackgroundMemory/Build/Products/Debug/QuotaView.app`；核对身份 `com.quotaview.development073`、0.7.3、内部 49、显示 Build 1。源码集成及 GitHub CI 结果以该分支对应 PR 为准；视觉、真实交互由用户验收。

PR #72 已合并 main `ea5cbcddf6f0123b3de9324e80e3642714eb2343`，PR 与 main CI 成功。用户后续授权替换运行包：刷新构建、154 项生产输入和签名验证通过，既有开发包已替换并启动（PID 17592），加载路径核对通过，旧包及 manifest 已备份。运行证据 `.build/073-background-memory-runtime-build.log`、`.build/073-background-memory-delivery.json`；视觉待用户验收。

本次属于 0.7.3 开发调整，配置身份不变。运行开发包与本轮源码/构建分开记录；不涉及公开 Release、appcast、稳定安装或真实额度重置。
