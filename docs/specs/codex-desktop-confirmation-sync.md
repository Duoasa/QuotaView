# Codex Desktop 确认详情与双向同步

Spec ID：`QV-CODEX-DESKTOP-CONFIRMATION-SYNC-001` · `Accepted / Verifying` · 整理：2026-10-08。
本规格维护当前 owner 应答及能力边界；当前交付见 [Handoff](../../HANDOFF.md)。

## 目标与可观察结果

- 自动弹出开启时，新真实确认直接进入该任务详情，显示原问题、选项、命令、文件变更、权限或受支持工具表单。重复快照不反复抢焦点，已有另一请求草稿、手动用量/重置页和固定页面保持。关闭自动弹出后仍可手动进入。
- 普通审批使用原始数字/字符串 RPC ID 和所属 owner 回传；同步问题返回原始问题 ID/答案集合。异步问题保留原生 `questionItemId`，通过 Codex 原生回答消息回传，不把异步提问伪装成审批或阻塞执行。
- 选择选项或自行输入只修改该请求的草稿，显示选中反馈；完整有效的答案在点击“确认”后单次发送，ACK 仅为“已发送”。只有原任务的后续权威状态移除对应请求，或出现被原生接受的精确问题回答，才解除该请求。用户在 Codex 处理后同样同步；并行请求各自保留。
- 未知协议、未证明的来源、远程任务、外部授权和不支持的表单继续在 Codex 处理；缺失详情不编造可操作内容。

## 问题交互与手动收起

- 可覆盖的提问页显示“跳过”和“确认”。自行输入沿用原生问题能力：异步问题始终支持，同步问题仅 `isOther=true` 或没有选项时支持；选项、自填互斥，切回自行输入保留已填草稿。空白或不完整答案禁用确认，未知或多选模式保持原生处理。
- 同步跳过按原生 `thread-follower-submit-user-input` 回传 `{answers:{}}`，仍等待 owner 权威移除。异步跳过只略过 Island 的本轮问题提示，同身份刷新不重新显示，不发空答案、不标记回答或清理独立等待。当前 follower 协议没有 Codex renderer 的异步跳过 RPC，因此不承诺同时关闭 Codex 窗口中的该提示。
- 待确认默认保持展开，手动收起可用，草稿保留；同请求普通刷新不会重新展开。新的请求身份或新的待确认会话仍按自动弹出偏好呼出；手动用量、重置、固定页与其他草稿遵循原焦点规则。
- 匿名待确认与具体请求分开：同轮次完整 owner 的 `threadRuntimeStatus.activeFlags=[]` 和空原始 pending 集合才证明旧匿名等待已结束，并同步 Core 状态与 Island。未知方法仍属于 pending，部分状态、未知 flags、旧 owner/epoch 不用于清理；异步未回答问题和并行具体请求各自保留。迟到匿名等待先保留，再由后续完整 owner 状态校正，不按跨通路时间戳猜测。
- Local-only 活动也可发起只读 Desktop owner discovery。经所选目录、用户来源和元数据一致性校验的 raw thread identity 仅留在内存，并与实际当前 owner/turn 证明分开；本地观察不直接获得提交能力。目录切换重放当前代次意图，停用清理，终态准入后撤销跟随。

## 协议与来源边界

所选 Codex 数据目录的 `ipc/ipc.sock` 为当前端点。UInt32 小端帧长 + UTF-8 JSON；已适配 initialize v0、owner/follower v1、state-changed v11。这是版本相关的 Desktop 私有接口，未来更新需重新核对能力。

- 普通审批/同步问题使用原 owner 的 command/file/permissions/elicitation/user-input 方法及原 typed RPC ID；可用决定/扩展范围由真实协议与请求约束。
- 异步问题保留 `JSON.stringify(["request_user_input_async", agentMessage.id, questionIndex])` 身份，经 `thread-follower-steer-turn` 回传原问题与答案。发送前重核 owner、轮次及未回答状态，不暴露任意 steering API。
- IPC 没有跨进程原子 turn CAS；ACK 轮次不符或写入后超时记为结果未知，不盲目重试。独立 app-server、Hook、Local 内容及 UI 模拟不生成响应能力。

## 原生问题框关闭仍未完成

ACK、精确问题结算、Island 本地退场和 Codex 原生框消失分别验证。当前 follower steering 没有执行 renderer 的 selectedQuestion 清理；同步 resolved、第二次发送、Skip 或整组 Dismiss 都不能作为异步关闭兜底。

原生 renderer 选择可能是跨 source 的完整有序问题组；只答一题不能安全关闭整组。精确问题证明仅包含当前轮次原生 questionItemId/问题哈希，不发布答案，不解除其他 RPC 或匿名等待。

[原生关闭合同](../design/codex-native-question-closure-contract-2026-10-03.md)保留 opt-in、进程/构建/owner/epoch/host/轮次/完整组/草稿与事务保护要求；当前 AX 映射和 lease/CAS 未建立。合同夹具不代表真实关闭可用。

## 模块职责与不变量

| 模块 | 职责 |
|---|---|
| `CodexDesktopIPCClient` | 校验私有 socket/同 UID 对端、发现实际 owner、跟随状态、连续 revision patch、opaque 能力句柄、单次提交与资源预算 |
| `CodexDesktopRequestProjector` | 从完整状态提取公开请求和原生问题，保留精确 typed ID、当前 turn 和部分历史权威边界；私有推理不投影 |
| `CodexActivityStore / TaskRegistry` | 所选目录、用户来源、当前 turn 和连接代次准入；分类 await 恢复前再次校验；公共内容不能绕过 |
| `IslandLiveStore.RequestLifecycle` | 来源详情升级、请求队列、草稿身份、等待证据、独立同步/异步解除；Shared 与 Desktop 的连接撤销互不误伤 |
| `IslandBoardState` | 真实新请求的自动详情导航；用户选择和 UUID 草稿 Binding 保持 |
| `IslandQuestionInteractionEntry / IslandApprovalView` | View 与入口冒烟共用选择、自填、确认、跳过路径；只有显式确认将完整有效草稿交给响应路由 |
| `CodexActivityRuntime` | 连接/目录生命周期，准入任务的 follow 意图，响应路由与 scope 撤销；切目录先撤销旧回调和按钮能力 |

能力只能由当前 owner 的权威状态生成，不能从 JSON、Local rollout、独立 app-server、Hook 或 UI 模拟生成。未知 source 必须经过 Store 已有用户来源证据，或借用当前目录代次内仍验证有效且保留的 Local 用户身份；明确 internal、无效、已撤销、旧目录身份不能借用。身份仅决定来源准入，不生成响应能力；辅助任务不进入可操作 UI。同 item 的多个 RPC 仍由真实 ID/方法区分，数字与字符串 ID 不混淆，重连后旧句柄、旧 await/ACK/catch 不能覆盖新状态。

Shared 与 Desktop 等待证据分别保留，精确同步完成才能解除 Core 快照和提醒；来源替代、资源撤销、ACK 和不相关工具结束都不算回答。完整 Desktop question 集合替代同轮只读 Local async 观察，部分状态不清；不按文本猜配，不制造已回答 tombstone。

## 失败、资源与恢复

Owner 尚未就绪或首次 discovery 超时，follow 意图在连接内以 250 ms 至 5 s 的有界退避恢复；read loop 不阻塞等待自身 RPC。stop、换目录、unfollow、旧 epoch 取消恢复任务；提交动作从不自动重试。

生产 `Configuration.live` 的完整帧物化预算为 72 MiB、单会话投影 64 MiB、总保留状态 128 MiB（通用初始化器默认值仍为 9/8/32 MiB，不应当作生产配置）；请求/问题数量、树深度、节点数有界。原生 follow 发送完整会话，本次实测一个快照约 14.55 MiB，旧实现在读 header 时全局暂停，连带正常任务退回只读。当前没有已证实的 compact、paging 或 request-only follow 选项；`compact-thread` 会实际改变用户任务，不能作为传输优化。

超过物化预算但不超过原生 256 MiB wire 上限的帧采用流式 drain，不保存正文，最多保留 64 KiB 元数据；只允许一个 64 KiB 读取块在途，由消费者 ACK 提供背压。解析遵循 JSON 结构/转义，重复解码路由键拒绝；完整声明帧到齐后才使用位于正文之后的版本/目标等字段。只有已发现 owner、目标、conversation/host/当前 epoch 均明确时隔离对应 scope，取消恢复并撤销句柄而不解除等待；foreign、其他 audience 或未跟随的数据不能撤销健康能力。正常帧的 JSON 树超限同样通过完整信封确定 scope。单会话 64 MiB 与总状态 128 MiB 预算同时生效。

不完整 header/body 使用 5 秒无读取进展超时；实际读到数据即重置，客户端处理耗时不作为对端停滞；超时绑定 frame generation 和 epoch；超出 wire 上限、无法唯一归属或超时才全局暂停，显式重新检查/唤醒可以重建。异步失效回调返回后再次校验 epoch，旧回调不能关闭 stop/start 后的新连接。原始状态仅内存短暂保留，不写日志/磁盘；诊断只记录固定结果、数量和哈希身份。超限不是协议版本错误，也不代表已回答；超大会话本身仍在 Codex 处理，不承诺无限历史支持。

连接断开或 patch base revision 不连续时，旧句柄失效，等待新的权威快照。已写入后的 timeout/断连保留结果未知；提交身份账本跨临时状态缺口保留直到真实解除或轮次变化，防止再次发送。

## 状态流生命周期修复（2026-10-10，本地开发）

IPC ledger 每次重建分配单调递增的本地 `streamGeneration`，经快照传至 Store 和 Island。原生 revision 只在同一代次内比较；较新代次可以从较低 revision 建立基准，较旧代次即使 revision 更大也拒绝。同一代次的重复或回退快照仍拒绝。Runtime 在准入前向 IPC actor 核对快照是否仍属于当前 ledger；异步分类恢复继续受 receipt 身份保护。

Unfollow 撤销正在进行的 owner discovery 尝试，旧响应不能覆盖新尝试。旧 ledger 句柄继续由 nonce 校验拒绝；不清除提交去重身份来重发未知结果。诊断增加 streamGeneration / revision，不记录请求正文。

新增 `DesktopResubscriptionSmokeTests` 以真实适配器生成的隔离句柄覆盖异步问题和 command approval：旧 revision 100 后重新订阅 revision 1 可以操作，旧代次 999、同代次 0 及重复快照不能误结算新请求；旧句柄不能提交。两轮 95 项不同针对性测试通过，Debug arm64 开发包已启动；实际用户交互待验收。原截图缺少序号日志，不能断定这就是当次唯一原因。原生问题框关闭边界不变。

## 验证边界

既有阶段的握手、隔离 socket/草稿/身份冒烟与交付日志保留；计数、旧 PID、PR 过程不再作为本页“当前状态”。完整原记录见[清理前快照](../archive/maintenance-20261008/README.md)，当前运行事实见 [Handoff](../../HANDOFF.md)。
本次只据现有 `CodexDesktopIPCClient.Configuration.live` 与帧读取代码校正文档预算/超时语义，未修改通信实现或代答真实请求。真实交互和原生关闭继续保留验收边界。
