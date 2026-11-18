# 当前任务输出速率

Spec ID `QV-PRODUCT-TASK-OUTPUT-RATE-001` · Accepted / Verifying

2026-11-15 用户授权 0.9.4 本地首版、冒烟测试、启动开发版，视觉由用户验收。采用本轮用户指定的 Token Monitor 请求计时思路，复用 QV 日志读流和任务卡。首版范围为带请求级用量记录的 Codex 任务；用户随后认可显示效果，授权 Build 4 扩展至所有 Agent 数据源。

## 行为（Build 6 当前）

- 速率移至任务卡右下角、累计用量前：四档 SF Symbols 圆圈图标 + 整数 `tok/s`。低于 20 为 `tortoise.circle`，20 至不足 60 为 `hare.circle`，60 至不足 120 为 `car.circle`，120 及以上为 `airplane.circle`。
- 速率与累计统计共用系统 10 pt Medium、等宽数字及 `IslandBoardStyle.muted` 灰色；累计统计单位为 `tok`，未知为 `— tok`。标题恢复独占可用空间，不再容纳速率。
- 当前任务保留最近有效请求快照，直到新样本替换；不因 30 秒无更新、工具执行或等待确认而隐藏。新 turn 仍清零，避免展示上一轮数据；从未取得有效样本时隐藏速率。
- 成功完成后显示本轮有效请求 `Σoutput / Σduration` 的灰色加权均值；迟到用量仍可修订。失败/中断沿用隐藏规则。
- 右下角统计组保持固有宽度和较高布局优先级，详情行只占剩余空间，并在该视口裁切滚动文字；速率与累计用量之间使用与标题行相同的 1 × 9 pt 深灰竖线，线两侧各 3 pt；图标与速率间距 3 pt，详情与统计组仍间隔 8 pt。保留右侧操作按钮的 4 pt 光学避让，不改变卡片高度与内距。
- Build 3/4 的标题后 13 pt 字体、30 秒过期与等待隐藏属于前序行为，已被本节覆盖。

## 数据

`task_started` 建立初始请求边界，工具结果/用户消息为后续边界。首次模型输出固定请求起点，异步工具结果不能将已经开始的请求起点后移。有效 `token_usage_record` 必须通过既有 thread、turn 和累计计数验证，使用 `usage.output_tokens` 与日志时间戳计算。计时包括首输出等待。仅保留数值、时间、哈希标识，复用既有读取上限。旧格式或缺失计时记录仍显示既有 token 用量。

每个 response 的重复记录保留原采样时间和均值。均值以实际请求时长加权，模型请求之间的工具等待不进入分母。中途附着且日志边界不可恢复时，均值覆盖可验证的样本。

## 验证

- 四个原生 SF Symbols 可加载。
- 34 项隔离速率冒烟通过，覆盖档位、过期、重复响应、异步工具交叠、下一请求计时、新 turn、缺失时间与加权平均。
- 本机只读日志抽样 3 份，110 条有效速率样本。
- 增量 Debug arm64 构建、开发运行包身份与加载路径核对通过，PID 29886。
- 构建时修复尾读闭包对 `state.pending` 的重叠独占访问，改用局部 decoder 后回写。
- 实际排版、图标观感及完成态由用户验收。

证据 `.build/rate-094b1/` 与 `.build/rate-094b3-runtime/`。开发版本 0.9.4 Build 3 / 内部 192。


## 多 Agent 扩展（Build 4）

所有来源复用同一任务卡速率字段和颜色规则；不改变已接受的标题排版。以下为已实现来源，并非真实客户端全矩阵验收结论：

| Agent 入口 | 输出计数与计时来源 |
|---|---|
| Codex | 沿用请求级 `token_usage_record` 与 rollout 边界 |
| Claude Code | transcript `message.usage.output_tokens`；用户/工具结果时间戳建立请求边界，实时 Prompt Hook 可补初始边界；按消息/request ID 替换流式修订 |
| DSH | `step/start` 到 `assistant/message` 回调间隔与 `usage.outputTokens`；`request/header` 仅提供模型，不用它代替每次请求开始 |
| Gemini CLI | `BeforeModel` 到有 `candidatesTokenCount` 的 `AfterModel`；同次请求的流式累计计数替换旧样本 |
| OpenCode | 完成的 `message.updated` 中 `tokens.output` 与 `time.created/completed`，消息 ID 去重；终端 Flush 保留数值字段 |
| Kimi Code | 当前 session/agent 的 `wire.jsonl`，`llm.request.time` 到 `usage.record.time`，仅 `usageScope=turn` 和 `usage.output`；忽略重复 step.end 和 session 汇总 |
| Copilot CLI | 当前 session `events.jsonl` 的 `session.usage_record.data.usage.outputTokens/duration`，duration 为毫秒；缺少请求计时的旧记录不显示 |
| Devin Desktop / CLI | 既有本地 session 存储中 `metadata.metrics.output_tokens/total_time_ms`，记录 ID 去重；支持 SQLite 与 files 两种存储 |
| Cursor | [公开 Hook](https://cursor.com/docs/hooks) 的 afterAgentResponse 只有文字，无法提供此口径的输出 token；本轮保持隐藏，不用字数或账户汇总估算 |

`AgentOutputRateLedger` 以响应标识去重，并将同一响应的更大输出计数替换旧样本。平均值为有效请求 `Σoutput / Σduration`，包含请求首输出等待，排除请求间工具/审批空档；不声称是模型服务器的精确生成速率。独立速率更新不把未知总 token 伪造成 0。Devin 使用源记录的 duration，首次观测时刻只决定实时显示保鲜期，重复读取不刷新该时刻。

Kimi/Copilot 在 Prompt Hook 捕获本轮日志起点并每秒只读刷新；16 MiB、8192 行、单行 1 MiB 和 80 ms 解析预算，未写完尾行留待下次。Devin 复用其既有预算。完成后保留最长 10 秒读取以接纳迟到记录，新 turn 与禁用立即隔离/停止。Claude 沿用既有尾读和 Stop 前排空；插件来源由回调推送。已加载的 DSH/OpenCode 客户端须重载插件才会发送新字段。

### Build 4 验证与运行

- 36 项隔离冒烟：请求时长加权、流式替换、重复/非法计数、Kimi 毫秒时间戳/来源定位、历史隔离、部分尾行、Copilot 单次时长、Claude 请求边界、Gemini 输出字段、OpenCode Flush、Devin 两种存储去重。
- DSH/OpenCode 实际插件脚本通过本地隔离 socket 发出 4 条速率事件与 2 条完成事件；验证 DSH 两个 step 的时长和 OpenCode 重复消息标识。
- 2 项定向 XCTest 冒烟通过：原生 IPC 完成态、迟到用量、陈旧 turn、下一轮清零、未知总量，以及 Hook 元数据过滤。
- 本地化 718 模板、753 条目录 × 3 翻译通过；Debug arm64 增量构建、261 生产输入与运行包清单/实际加载路径一致，正式安装未改。
- 最终开发包 0.9.4 Build 4 / 内部 193，PID 42336。证据 `.build/agents-rate-094b4/`、`.build/agents-rate-094b4-final-runtime/`。仅冒烟，未开展完整回归或主动视觉验收；新增 Agent 的真实使用表现由用户验收。


## 快照与右下角布局（Build 5）

2026-11-15 用户反馈显示经常消失且标题速率过大，要求保留快照至新数据更新、移到右下角累计用量之前、单位改为 `tok`，并明确任务详情避让。按上方行为落实，仅改展示与布局。

2 项定向冒烟通过，验证一小时无新数据仍保留快照、等待状态保留、完成后加权平均、新轮清零和 `tok` 单位，以及既有原生 IPC 迟到用量路径。布局源码核对统计组固定宽度/优先级、详情视口裁切和右侧光学内缩；未进行截图或 UI 自动化验收。

本地化、Debug arm64 增量构建、261 生产输入与实际运行路径核验通过。开发包 0.9.4 Build 5 / 内部 194，PID 46339。证据 `.build/rate-footer-094b5/smoke.log`、`.build/rate-footer-094b5-runtime/`。实际视觉由用户验收，仅本地未提交/推送/发布。

## 紧凑统计分隔线（Build 6）

按用户截图反馈缩小统计间距，在速率与累计用量间添加上方标题行同款 1 × 9 pt 深灰竖线，线两侧各 3 pt。只在存在速率时出现，详情视口避让保持。纯布局修改仅做本地化、补丁、增量编译与运行核验，不新增测试或主动视觉验收。

开发包 0.9.4 Build 6 / 内部 195 已启动，PID 48229。证据 `.build/rate-divider-094b6-runtime/`；本地未提交/推送/发布，实际效果由用户检查。

## 用户验收与公告源码集成（Build 7）

2026-11-15 用户确认 Build 6 的展示效果，并授权更新公告、源码推送合并 main。公告三条覆盖输出速率、快照和紧凑统计，不承诺磁盘持久化：完成均值目前只在进程内的当前卡片持续显示，应用重启不保证恢复，新 turn/清理卡片清除。

7 项定向本地冒烟与本地化通过；开发包 0.9.4 Build 7 / 内部 196 已启动，PID 52317。精确源码与 PR/main CI 证据见 Handoff；不发布 Release/appcast。

2026-11-15 源码经 [PR #143](https://github.com/Duoasa/QuotaView/pull/143) 合入 main `4e248150b8a2eaef0d0c0da8881be9486631856d`。PR 与精确 main CI 均通过，各 807 测试、7 跳过、0 失败及原生问题关闭契约；合并树与当前运行输入一致。此交付补记保留本地，PR 描述同步最终结果。未发布 Release/appcast。

## Antigravity（0.9.4 Build 10）

按会话 UUID、调用序号和起始步骤配对 PreInvocation 与 PostInvocation。从相应客户端目录的 transcript_full.jsonl 匹配同一步骤的 PLANNER_RESPONSE。速率取输出 token 除以两次 Hook 的时间差，任务 Token 累加匹配记录中的输入与输出。读取日志末尾最多 2 MiB，短暂重试等待日志写入。缺少记录时沿用上次快照。完成后按各调用耗时加权显示。

Build 11 允许系统或工具步骤插在调用起点和回复之间，按会话、调用时间窗及起始步骤匹配唯一回复。Hook 缺少路径时只在三个已知客户端根目录中取唯一会话日志。读数最长等待约 10 秒，按本轮回复步骤去重。

Build 15 将 Antigravity 单次调用的缓存读取 Token 计入任务与用量页的总量，输出速率仍仅用输出 Token 和调用耗时计算。
