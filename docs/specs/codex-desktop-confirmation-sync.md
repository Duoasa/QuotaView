# Codex Desktop 确认详情与双向同步

Spec ID：`QV-CODEX-DESKTOP-CONFIRMATION-SYNC-001` · `Accepted / Verifying` · 整理：2026-10-08。
本规格维护当前 owner 应答及能力边界；当前交付见 [Handoff](../../HANDOFF.md)。

## Build 31 岛内文本回答

普通启动的 Codex Desktop 26.1120.50957 在原生异步问题卡上提供独立的文本框和发送按钮。开启辅助功能后，QuotaView 从正在等待的本地单题中匹配原窗口、问题全文和有序选项，再把同一张岛内卡变为可编辑。会话标题须在当前 Codex 数据目录的会话库中唯一对应目标线程。多题组合、身份不明确或原卡未打开时，仍可前往 Codex 处理。命令审批、旧桌面通道和同一共享服务的回答沿用各自协议。

选项和自填都以文本进入原问题卡。只有用户点确认才写入，已存在的不同原生草稿会阻止覆盖。重新匹配原卡、当前轮次、调用、输入值和按钮可用状态后，发送一次。题目结算归属于原问题回执。普通聊天输入框、剪贴板和全局按键不参与。

**用户实测通过（2026-11-25）。** QuotaView 0.9.7 Build 31（内部 268）配合默认启动的 Codex Desktop 26.1120.50957，用户在灵动岛的水果选择题中选了「樱桃」并确认。核对原会话记录，原轮次收到一条对应原始 `questionItemId` 的回答，内容为「樱桃」。此前生产输入模块发送「文本甲」的验证另见 `.build/codex-question-input-097b31/`。本次人工验收覆盖岛内点选，自定义输入框复用同一文本提交通道。

将此路径作为默认启动下单道异步选择题的兼容基线。它依靠 macOS 辅助功能操作 Codex 自己的问题卡，无需 Codex 对第三方开放回答接口或以共享模式重启。后续 Codex 改动原生控件时，可用同样的单题复测，以原轮次收到匹配题目标识和答案的一条回执为通过条件。

## Build 16 默认启动的本地聊天

11 月 24 日再次检查 26.1117.41037（29803）。使用默认数据目录已发布的控制 socket 完成 WebSocket `/rpc` 与原生 initialize 握手，随后 `thread/loaded/list` 返回 0 条，且没有下一页。此时共享服务没有承载当前桌面聊天，即使 socket 可连，也无法向该聊天取得回答能力。

对应版本的异步提问处理器发出带 questions 的 agentMessage，立即完成该 item 并返回 accepted。命令审批 Hook 没有等待这道题的答案。设置内按原会话显示作答位置，保留与旧 Desktop 或确实持有原会话的共享服务匹配时的提交路径。

## 0.9.7 Build 15 / 本地会话只读实测

11 月 24 日 08:52 用户实测，岛内为只读，橙色是在 Codex 原生界面选择。桌面 26.1117.41037（29803）的本地 host 在 08:50 通过 stdio 完成握手，WebSocket 属于 durable host。桌面为本地 host 添加配置覆盖项，而原生 daemon 启动分支要求覆盖列表为空。Build 15 对该精确构建停止提供无效的共享重启，保留命令 Hook、旧版桌面回答，以及对确实匹配同一服务的题目的处理。这个版本的普通本地会话仍需在 Codex 内作答。

## 目标与可观察结果

- 自动弹出开启时，新真实确认直接进入该任务详情，显示原问题、选项、命令、文件变更、权限或受支持工具表单。重复快照不反复抢焦点，已有另一请求草稿、手动用量/重置页和固定页面保持。关闭自动弹出后仍可手动进入。
- 普通审批使用原始数字/字符串 RPC ID 和所属 owner 回传；同步问题返回原始问题 ID/答案集合。异步问题保留原生 `questionItemId`，通过 Codex 原生回答消息回传，不把异步提问伪装成审批或阻塞执行。
- 选择选项或自行输入只修改该请求的草稿，显示选中反馈；完整有效的答案在点击“确认”后单次发送，ACK 仅为“已发送”。只有原任务的后续权威状态移除对应请求，或出现被原生接受的精确问题回答，才解除该请求。用户在 Codex 处理后同样同步；并行请求各自保留。
- 未知协议、未证明的来源、远程任务、外部授权和不支持的表单继续在 Codex 处理；缺失详情不编造可操作内容。

## PermissionRequest 命令审批（0.9.7 Build 12）

对具有完整命令的实时 Bash 审批，使用 Codex 文档定义的 PermissionRequest 返回允许一次或拒绝。已连接旧桌面通道时让 Codex 继续原有审批流程。对当前用户、会话和轮次匹配的已显示任务，开发版通过带认证的本地连接接收命令、工作目录和原因。操作只作用于这次 Hook 调用。挂起的审批和原始命令只保存在内存中。隐私模式、停用、会话不匹配、未知参数、连接结束或未在 55 秒内选择时，交回 Codex 正常审批。异步选择题继续沿用独立的回答机制。

仅 PermissionRequest 注册的超时改为 65 秒，其余事件保持 2 秒。原生信任状态为已修改时，用户通过「任务事件连接 → 授权连接」确认。隔离测试覆盖允许、拒绝、未决定、旧版桌面优先与过期轮次。2026-11-23 用户确认确认类审批正常；此结论不覆盖异步选择题。

## Hook 授权联动共享回答（0.9.7 Build 14）

用户在设置中启用或授权 Hook 后，检查所选目录、当前 Hook 定义和 Codex 返回的信任状态。已授权的旧安装从同页「选择题回答 → 连接回答」进入。仅由用户的连接操作建立一次启动意图。重复状态检查、已完成的启动和普通活动事件不会发起新启动。旧 Desktop 回答连接可用时继续使用原通道。

Codex 正运行时，设置提示用户保存退出，并提供取消。退出后再次检查 Hook，使用桌面应用自带的 CLI 在相同数据目录启动或复用本机 daemon，核对版本响应，然后用 macOS 打开 Codex。共享模式与所选数据目录只传给这次启动。设置分别呈现等待退出、准备中、已打开等待服务、服务连接和失败可重试。每个问题要由原服务核对当前轮次和题目才能提交。停用 Hook、切换目录、取消或退出 QuotaView 会撤回待执行的启动。后续普通打开 Codex 时，可通过设置再次连接回答。

## 新版共享服务回答通道（0.9.7 Build 13）

2026-11-23 用户明确要求接入新版 Codex 回答通道。新版桌面以 `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1` 启动时，QuotaView 与桌面连接同一个原生 App Server daemon，通过 Unix WebSocket `/rpc` 查询已加载的用户会话。仅活动轮次、原始 source item、问题序号、题面和选项全部匹配的未回答整组，才能将现有本地只读请求原位升级为可回答；保留请求 UUID、草稿、焦点和回执状态。部分已回答组仍在 Codex 处理。

确认时再次读取原服务状态，按原生 `questionItemId` 生成 `<send_user_message_question_reply>` 消息，调用 `turn/steer` 并携带 `expectedTurnId`。不调用 `turn/start`，不从独立新服务推断原会话能力。每组记录一次派发；失联、超时、ACK 轮次不符均为结果未知，不换通道补发。ACK 只证明已发送，精确接受回执才能结算问题。原生问题框是否自动消失仍待用户验收，未增加 UI 自动关闭操作。

传输校验当前用户、私有目录、socket 和对端 UID，支持原生 daemon 发布的单层绝对符号链接，连接前后复核链接及 socket inode。分页读最多 20×100 项、2 MiB；本机构建返回 `-32601` 时使用最大 8 MiB 的原生 `thread/read`，只匹配最后一个活动轮次，最多 2,000 项。超出预算或状态不完整保持原生处理。推理与无关工具内容不投影到问题模型。

旧 Desktop 回答连接存在时优先使用旧路由；命令审批继续遵循上节 PermissionRequest。停用、隐私模式、切换目录、断线或终态撤销共享回答能力。共享模式必须由桌面本身使用，QuotaView 不自动启动另一套服务来回答独占 host 的题目。

Build 13 验证时使用以下独立启动方式，Build 14 已内置上节设置入口。本机已安装 Codex 26.1117.41037（29803）默认仍是独占 host。保存工作并完全退出 Codex 后，运行 [共享模式启动脚本](../../scripts/start-codex-shared-answers.command)：它用已安装的 Codex CLI 启动/复用原生 daemon，再以该环境变量打开桌面；不关闭现有会话、不修改全局环境或应用文件。普通方式重新启动 Codex 会恢复其默认模式；需共享回答时使用此脚本。进入原会话或创建新测试问题后由用户验收。此启动方式属于已核验版本的兼容接入，后续 Codex 更新需重核。

验证：隔离模拟服务覆盖精确身份、过期轮次、重复点击、断线未知结果、部分回答、旧通道优先和安全 socket。另使用本机原生 CLI + 本地模拟模型服务，由生产 Swift 客户端提交真实原生异步问题，确认原轮次接受回执、错误轮次拒绝；没有调用真实模型或写入用户会话。复现入口见 [夹具说明](../../Tests/Fixtures/codex-shared-answers/README.md)，证据 `.build/shared-answers-097b13/`。真实桌面共享模式与岛内交互尚待用户测试。

## 前序诊断：新版桌面选择题兼容缺口（2026-11-23 用户反馈）

用户确认 Build 12 的确认类审批正常，但 17:37:05 截图中的异步选择题只能查看，不能选择或提交。“批准 / 拒绝”是该题的答案文字，不会将问题转换为 shell 命令审批。当前 `CodexActivityRuntime.responseCapability` 对非 PermissionRequest 请求仍要求 `desktopHandle`，`CodexDesktopIPCClient.submit` 的异步问题继续调用旧 `thread-follower-steer-turn`；只读视图因此隐藏选择控件和确认按钮。

本次复核 Codex 26.1117.41037（29803）：旧 socket 连接返回 errno 61，共享 app-server daemon 端点不存在。安装包中的新 `app-server-host` / bootstrap 模块具有内部 `turn/steer` 和 MessagePort 连接，但本次未确认可供 QuotaView 接入的替代回答端点。内部方法存在不证明外部应用可用，不从本地题面或独立 app-server 构造原会话的提交权限。

上述为 Build 12 的诊断结论，随后用户授权的 Build 13 实现见上节；实际桌面切换与交互验收仍未完成。诊断证据：`.build/codex-choice-097b12/diagnosis.json`。

## 仅收到审批通知时的断线提示（0.9.7 Build 11）

2026-11-23 实机对照：旧版 26.1111.71025 桌面安装包中含有 follower 的命令审批、提交回答和会话状态广播方法，已按归档内的 SHA-256 核对相应模块。当前 26.1117.41037 桌面应用归档中未找到这三个方法名。新版仍保留旧 socket 的路径计算代码，但当前桌面端通过 `MessageChannelMain` 向独立的 `app-server-host` 进程打开连接，11 月 23 日运行日志也记录了该进程。

在本机，11 月 20 日 22:13:19 的旧 socket 文件仍属当前用户。11 月 21 日 12:18 的日志仍有旧 IPC 广播，12:23 再次启动后可见独立 host 的连接记录。11 月 23 日用相同用户直接连接该文件，macOS 返回 `ECONNREFUSED`（61），进程打开文件列表中也没有该端点。故障发生在协议握手之前。此对照仅确认这两个构建与本机运行路径，尚未验证新版是否提供第三方可用的替代审批入口。

11 月 23 日 16:20:45 的网络访问测试中，活动 Hook 的 PermissionRequest 已确认送达，当前桌面端 26.1117.41037 的默认 follower socket 连接返回 ECONNREFUSED。任务的本地调用记录含网络授权请求；这三项证据没有提供可提交的 owner 请求句柄。该实例与启动后重放已答题的情形分别处理。

Codex 通用占位请求在桌面通道离线时说明断线，并引导在原对话处理。通道重连后按当前详情更新；等待权威快照时保留只读状态。新增展示回归验证断线、重连、再次断线时同一请求的身份和操作能力。

## 已回答的旧题与正在等待的新题（0.9.7 Build 8）

本地会话记录提供题面与回答回执。岛内的可编辑选项、自定义输入和提交按钮，要求当前桌面连接确认会话、轮次和题目。断线期间显示问题与选项文字；有会话链接时，「在 Codex 处理」直接打开原对话。恢复连接后，以当前桌面返回的待答问题集合更新表单。

最后一次完整桌面快照只覆盖当时的状态。连接中断后，同轮的后续新问题可以作为只读提醒出现。早于快照的回放和已收到准确回答回执的题目继续过滤。联合冒烟覆盖只读新题、恢复可答、原生回执、重启与同题面新调用。

## 启动时恢复异步问题（0.9.7 Build 5）

回放按会话、轮次、原调用、题目序号与题面核对已接受的回答。若启动记录中已有一组问题的全部回执，直接恢复已回答状态。跨启动只保存匹配问题的散列和时间，桌面与本地记录指向同一道题时共用该标记。只读表单沿用 30 秒自动收起，未回答的问题仍可处理。

## 问题交互与手动收起

- 可覆盖的提问页显示“跳过”和“确认”。自行输入沿用原生问题能力：异步问题始终支持，同步问题仅 `isOther=true` 或没有选项时支持；选项、自填互斥，切回自行输入保留已填草稿。空白或不完整答案禁用确认，未知或多选模式保持原生处理。
- 同步跳过按原生 `thread-follower-submit-user-input` 回传 `{answers:{}}`，仍等待 owner 权威移除。异步跳过只略过 Island 的本轮问题提示，同身份刷新不重新显示，不发空答案、不标记回答或清理独立等待。当前 follower 协议没有 Codex renderer 的异步跳过 RPC，因此不承诺同时关闭 Codex 窗口中的该提示。
- 待确认默认保持展开，手动收起可用，草稿保留；同请求普通刷新不会重新展开。新的请求身份或新的待确认会话仍按自动弹出偏好呼出；手动用量、重置、固定页与其他草稿遵循原焦点规则。
- 匿名待确认与具体请求分开：同轮次完整 owner 的 `threadRuntimeStatus.activeFlags=[]` 和空原始 pending 集合才证明旧匿名等待已结束，并同步 Core 状态与 Island。未知方法仍属于 pending，部分状态、未知 flags、旧 owner/epoch 不用于清理；异步未回答问题和并行具体请求各自保留。迟到匿名等待先保留，再由后续完整 owner 状态校正，不按跨通路时间戳猜测。
- Local-only 活动也可发起只读 Desktop owner discovery。经所选目录、用户来源和元数据一致性校验的 raw thread identity 仅留在内存，并与实际当前 owner/turn 证明分开；本地观察不直接获得提交能力。目录切换重放当前代次意图，停用清理，终态准入后撤销跟随。

## 协议与来源边界

旧 Desktop 通道使用所选 Codex 数据目录的 `ipc/ipc.sock`。UInt32 小端帧长 + UTF-8 JSON；已适配 initialize v0、owner/follower v1、state-changed v11 和 v13。这是版本相关的 Desktop 私有接口，未来更新需重新核对能力。新版共享通道使用该目录的 `app-server-control/app-server-control.sock` 与 `/rpc`，边界见 Build 13 小节。

- 普通审批/同步问题使用原 owner 的 command/file/permissions/elicitation/user-input 方法及原 typed RPC ID；可用决定/扩展范围由真实协议与请求约束。
- 异步问题保留 `JSON.stringify(["request_user_input_async", agentMessage.id, questionIndex])` 身份，经 `thread-follower-steer-turn` 回传原问题与答案。发送前重核 owner、轮次及未回答状态，不暴露任意 steering API。
- 旧 IPC 没有跨进程原子 turn CAS；ACK 轮次不符或写入后超时记为结果未知，不盲目重试。独立 app-server、Local 内容及 UI 模拟不生成回答能力；共享通道只接受同一原生服务的实时证明。PermissionRequest Hook 仅具有其自身命令请求的单次响应能力。

## 原生问题框关闭仍未完成

ACK、精确问题结算、Island 本地退场和 Codex 原生框消失分别验证。当前 follower steering 没有执行 renderer 的 selectedQuestion 清理；同步 resolved、第二次发送、Skip 或整组 Dismiss 都不能作为异步关闭兜底。

原生 renderer 选择可能是跨 source 的完整有序问题组；只答一题不能安全关闭整组。精确问题证明仅包含当前轮次原生 questionItemId/问题哈希，不发布答案，不解除其他 RPC 或匿名等待。

[原生关闭合同](../design/codex-native-question-closure-contract-2026-10-03.md)保留 opt-in、进程/构建/owner/epoch/host/轮次/完整组/草稿与事务保护要求；当前 AX 映射和 lease/CAS 未建立。合同夹具不代表真实关闭可用。

## 模块职责与不变量

| 模块 | 职责 |
|---|---|
| `CodexDesktopIPCClient` | 校验私有 socket/同 UID 对端、发现实际 owner、跟随状态、连续 revision patch、opaque 能力句柄、单次提交与资源预算 |
| `CodexSharedAppServerActivityClient` | 校验共享原生端点、当前已加载用户轮次、原生题目和接受回执；发放 opaque 回答能力，以 expectedTurnId 单次 steer |
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

## 连接恢复与上下文回收（2026-11-01 / 0.9.1 Build 9）

成功初始化后迅速断线也使用 250 ms 起、最高 5 秒退避。Shared 握手连接/写入/读取共用绝对期限并传播取消，前后验证 socket/目录属主权限及对端 UID。请求计时任务随完成取消。Island 仅保留有界审批字段，上下文每项 32 KiB、总计 2 MiB、最多 200 项，换轮/清理时回收；超限/缺失的文件变更上下文不产生批准能力。owner/epoch/轮次、未知结果不重放和 Desktop 能力来源规则保持。

107 项相关隔离测试与开发包构建/重启通过；具体范围、证据和未改条目见[复核与修复记录](../design/quotaview-bug-fixes-2026-11-01.md)。本批仅本地；真实客户端及视觉由用户验收。

## Build 29 · Codex Desktop v13 网络审批

本机 Codex Desktop 26.1111.71025 的会话状态广播为 v13。普通帧与超限帧的归属检查使用同一组已核验的版本。命令及网络审批仍走 v1 的决策请求。只读来源、过期请求及未知版本沿用原有降级。

本机已验证接收连续的权威 v13 快照更新；隔离冒烟覆盖 v13 的网络审批选项、向原请求发送一次决定、收到后续变化并清除已处理的请求。用户在 Build 30 的真实网络访问审批中确认审批按钮正常。
