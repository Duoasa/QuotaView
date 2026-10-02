# Codex Desktop 确认详情与双向同步

Spec ID：`QV-CODEX-DESKTOP-CONFIRMATION-SYNC-001` · `Accepted / Verifying` · 2026-10-02

用户明确要求参考 Vibe Island 的真实通信，实现灵动岛直接显示、操作和同步 Codex 确认。此前“在 Codex 处理”的观察模式只适用于没有原任务响应能力的来源，本轮增加 Desktop owner 响应能力。既有确认页、页面尺寸、悬停和设置保持，额度重置仍仅演示。

## 目标与可观察结果

- 自动弹出开启时，新真实确认直接进入该任务详情，显示原问题、选项、命令、文件变更、权限或受支持工具表单。重复快照不反复抢焦点，已有另一请求草稿、手动用量/重置页和固定页面保持。关闭自动弹出后仍可手动进入。
- 普通审批使用原始数字/字符串 RPC ID 和所属 owner 回传；同步问题返回原始问题 ID/答案集合。异步问题保留原生 `questionItemId`，通过 Codex 原生回答消息回传，不把异步提问伪装成审批或阻塞执行。
- 选择选项或自行输入只修改该请求的草稿，显示选中反馈；完整有效的答案在点击“确认”后单次发送，ACK 仅为“已发送”。只有原任务的后续权威状态移除对应请求，或出现被原生接受的精确问题回答，才解除该请求。用户在 Codex 处理后同样同步；并行请求各自保留。
- 未知协议、未证明的来源、远程任务、外部授权和不支持的表单继续在 Codex 处理；缺失详情不编造可操作内容。

## 原生关闭最小合同与停止边界 · 2026-10-03

本轮继续调查，仍没有经过身份绑定的 async 提交并关闭接口。生产 API/AX 路由保持；[接口证据与最小合同](../design/codex-native-question-closure-contract-2026-10-03.md)明确 renderer 选择是完整有序问题组，可能跨 source，pure Dismiss 不能按单题接受触发。Skip 的同名 dismiss data 属性不能证明无发送。

AX 设计仅在明确 opt-in/已授权、同进程/构建/owner/epoch/host/会话/轮次/entity、完整组/草稿/元素证明和事务性保护齐备时允许一次 pureDismiss 意图。当前 AX 映射和 lease/CAS 均未建立，缺条件拒绝并交由人处理；双次读取不能消除 TOCTOU。隔离夹具仅验证合同，不调用 AX、启用权限或发送真实回答。后续依赖真实权限与人工验收的操作前停止；不能把代码、CI或缺少 Vibe 源码推导为已关闭或永久不能开发。

PR #70 main 合并提交 `9e67f2bde7a8a31d981e5e21e6a1cf1bfdb4ad8c` 的 postmerge push CI run 37073125800 同 SHA 成功：508 项，6 项跳过、0 失败。

## 提问提示结算与原生关闭边界 · 2026-10-03

本轮补齐已观察异步问题的当前轮次原生回答证明：Local rollout 仅输出 questionItemId 与原问题哈希，精确结算只读问题，多个问题全部回答后再移除对应组；不发布答案、不提升响应能力、不解除同步 RPC 或匿名等待。活动组证明与最近 256 项已结束证明有界保留，普通用户内容、早于请求的回答、旧轮次和相似文字不能建立未来解决标记。详见 [模块梳理](../design/quotaview-question-lifecycle-review-2026-10-03.md)。

送达 ACK、精确问题结算、Codex 原生框消失必须分开验证。当前异步 follower steering 没有执行 renderer 本地 selectedQuestion 清理；本轮前两个阶段已覆盖，原生框关闭仍未实现或验证。同步 resolved 事件不可用于异步问题，原生 Skip/第二次发送也不能作为关闭兜底。Vibe 官方社区 Issue #241 与静态脚本/AX 证据仍未证明同类异步场景；不自动申请系统权限或操作真实用户确认。

203 项相关隔离冒烟（0 失败）、P95 4.598 ms、Debug arm64 构建、资源/固定身份与 deep strict ad-hoc 签名通过；181 项输入核对一致，开发交付时 PID 75451。证据 `.build/073-question-presentation-*`；视觉和实际点击待用户验收。本轮源码集成与旧 PR #69 分开记录。 本轮安全修复源码提交 `f828264e8af7dfab06fcc1da5cf953174541348f` 已推送至 [PR #70](https://github.com/Duoasa/QuotaView/pull/70)。用户已授权对应提交 CI 通过后合并 main；CI 与最终 main 集成状态以该 PR 为准。203 项本地验证与已运行开发包单独记录，原生异步提问框关闭仍未完成。

## 问题交互与手动收起 · 2026-10-02 追加

- 可覆盖的提问页显示“跳过”和“确认”。自行输入沿用原生问题能力：异步问题始终支持，同步问题仅 `isOther=true` 或没有选项时支持；选项、自填互斥，切回自行输入保留已填草稿。空白或不完整答案禁用确认，未知或多选模式保持原生处理。
- 同步跳过按原生 `thread-follower-submit-user-input` 回传 `{answers:{}}`，仍等待 owner 权威移除。异步跳过只略过 Island 的本轮问题提示，同身份刷新不重新显示，不发空答案、不标记回答或清理独立等待。当前 follower 协议没有 Codex renderer 的异步跳过 RPC，因此不承诺同时关闭 Codex 窗口中的该提示。
- 待确认默认保持展开，手动收起可用，草稿保留；同请求普通刷新不会重新展开。新的请求身份或新的待确认会话仍按自动弹出偏好呼出；手动用量、重置、固定页与其他草稿遵循原焦点规则。
- 匿名待确认与具体请求分开：同轮次完整 owner 的 `threadRuntimeStatus.activeFlags=[]` 和空原始 pending 集合才证明旧匿名等待已结束，并同步 Core 状态与 Island。未知方法仍属于 pending，部分状态、未知 flags、旧 owner/epoch 不用于清理；异步未回答问题和并行具体请求各自保留。迟到匿名等待先保留，再由后续完整 owner 状态校正，不按跨通路时间戳猜测。
- Local-only 活动也可发起只读 Desktop owner discovery。经所选目录、用户来源和元数据一致性校验的 raw thread identity 仅留在内存，并与实际当前 owner/turn 证明分开；本地观察不直接获得提交能力。目录切换重放当前代次意图，停用清理，终态准入后撤销跟随。

## 通信证据与边界

参考本机原版 `/Applications/Vibe Island.app` 1.0.51 与 Codex Desktop 26.928.40906（build 12694，bundle `com.openai.codex`）的实际协议和原生 owner handler；CLI 0.159.2 是独立版本身份。Vibe 静态证据包含私有 IPC 批准/提问、页面探测和背景/AX 辅路，尚不能证明其每个异步分支选路、帧预算或 socket 隔离方式。QuotaView 使用已核验的原任务 owner/follower 通路。不是第三方同名开源克隆，也不是独立新启动 app-server 的审批 owner。Vibe 的 [更新记录](https://vibeisland.app/changelog/)可用于产品能力背景；官方 [App Server 文档](https://learn.chatgpt.com/docs/app-server)说明标准 JSON-RPC，不能代替本轮 Desktop 私有协议。

当前本地端点为所选 Codex 数据目录的 `ipc/ipc.sock`。帧是 UInt32 小端长度与 UTF-8 JSON；initialize version 0，owner discovery / following / follower actions version 1，本地 state-changed version 11。真实只读 initialize 握手成功，未向用户任务提交动作。协议是版本相关的非公开接口，不能宣称未来 Codex 更新无需适配。

普通回传使用原生 command/file/permissions/elicitation/user-input follower 方法。当前原生 command/file 请求没有 `availableDecisions`：仅已证明 owner 句柄采用真实四种枚举；规则变体只能来自原请求 proposed exec/network amendment，未来显式列表优先并严格约束。MCP 的 nullable turn 仅在展示层绑定已证明的当前 turn，原 RPC ID 不变。

异步提问来自 `agentMessage.questions`，原生身份是 `JSON.stringify(["request_user_input_async", agentMessage.id, questionIndex])`。回答使用 `<send_user_message_question_reply>` 中的原身份、原问题及用户答案，通过 `thread-follower-steer-turn` 发送。发送前刷新 owner 快照，验证当前轮次和未回答身份；不暴露通用任意 steering API。IPC 没有跨进程原子 turn CAS，采用 Codex 原生界面同样的用户操作语义；ACK turn 不符或发送后超时记为结果未知，不盲目重试。

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

完整帧物化预算 9 MiB、单会话投影 8 MiB、总保留状态 32 MiB；请求/问题数量、树深度、节点数有界。原生 follow 发送完整会话，本次实测一个快照约 14.55 MiB，旧实现在读 header 时全局暂停，连带正常任务退回只读。当前没有已证实的 compact、paging 或 request-only follow 选项；`compact-thread` 会实际改变用户任务，不能作为传输优化。

超过物化预算但不超过原生 256 MiB wire 上限的帧采用流式 drain，不保存正文，最多保留 64 KiB 元数据；只允许一个 64 KiB 读取块在途，由消费者 ACK 提供背压。解析遵循 JSON 结构/转义，重复解码路由键拒绝；完整声明帧到齐后才使用位于正文之后的版本/目标等字段。只有已发现 owner、目标、conversation/host/当前 epoch 均明确时隔离对应 scope，取消恢复并撤销句柄而不解除等待；foreign、其他 audience 或未跟随的数据不能撤销健康能力。正常帧的 JSON 树超限同样通过完整信封确定 scope。单会话 8 MiB 与总状态 32 MiB 预算保持。

不完整 header/body 有 5 秒帧 deadline，绑定 frame generation 和 epoch；超出 wire 上限、无法唯一归属或超时才全局暂停，显式重新检查/唤醒可以重建。异步失效回调返回后再次校验 epoch，旧回调不能关闭 stop/start 后的新连接。原始状态仅内存短暂保留，不写日志/磁盘；诊断只记录固定结果、数量和哈希身份。超限不是协议版本错误，也不代表已回答；超大会话本身仍在 Codex 处理，不承诺无限历史支持。

连接断开或 patch base revision 不连续时，旧句柄失效，等待新的权威快照。已写入后的 timeout/断连保留结果未知；提交身份账本跨临时状态缺口保留直到真实解除或轮次变化，防止再次发送。

## 验证与交付

2026-10-02 本轮最新：188 项限定隔离冒烟通过，覆盖生产 View/Board 草稿入口与真实 Unix socket 短帧、超大 burst 后健康原生问题提交、foreign/audience/重复路由/帧超时、旧 epoch 异步回调重入、canonical/live 当前轮次与来源准入。P95 展示基准 4.332 ms。最终 Debug arm64 构建与 deep strict ad-hoc 签名通过，固定身份开发包 PID 94157，178 项输入指纹一致；真实只读打包 Core 多 follow 证明超大会话隔离后正常会话仍权威/有 owner 输入能力。实际 app 保持 connected。命名测试任务当时已完成，没有处理真实 pending、发送真实答案或 UI 自动化，真实点击仍待用户验收。证据 `.build/073-question-capability-smoke.log`、`.build/073-question-capability-build.log`、`.build/073-question-capability-delivery.json`、`.build/073-question-capability-stock-readonly.json`、`.build/073-question-capability-stock-multifollow-readonly.json`。本轮修复提交 `3317b3c92d27b518b9d275214c28170af0dc8a9e` 已推送至 [PR #69](https://github.com/Duoasa/QuotaView/pull/69)，指向 main。用户明确授权检查 GitHub CI 后合并；GitHub 完整 Swift CI 与实际合并状态以该 PR 为准。本轮 188 项本地验证与已运行开发包输入独立记录；历史 PR #68 不包含本轮新修订。

以下为历史验证：

2026-10-02 问题交互与等待纠正追加：134 项相关隔离冒烟、最终 Debug arm64 构建、固定身份/资源、deep strict ad-hoc 签名及启动核对通过，开发包 PID 240。证据 `.build/073-question-interaction-final-smoke.log`、`.build/073-question-interaction-final-build.log`、`.build/073-question-interaction-delivery.json`。覆盖选择不发送、自行输入/文字保持、确认单次发送、同步跳过和异步本地跳过、手动收起/新请求呼出、local-only Desktop 跟随与撤销、无 typed 删除的 Core/Island 匿名等待清理，以及未知/部分/并行/owner/epoch/旧轮次边界。新增整链夹具统一模拟时钟后 14 项专项及最终全部复验通过，首次失败保留；生产代码在成功构建后未变。尚未提交推送，本轮真实交互仍待用户验收，不操作真实确认或 UI 自动化。

首次 Desktop 交付历史：

98 项必要隔离冒烟通过：Core IPC 21、公开投影 15、Island 生命周期 13、Store 准入 10、导航 4、既有准入 11、既有请求恢复 21、自动弹出偏好 3。证据 `.build/073-desktop-confirmation-smoke.log`。全新 Derived Data 的 Debug arm64 开发 Target 构建通过，证据 `.build/073-desktop-confirmation-build.log`；固定身份、资源与 deep strict ad-hoc 签名核对通过，开发包已启动 PID 90147，证据 `.build/073-desktop-confirmation-delivery.json`。真实只读 initialize 握手记录 `.build/073-desktop-confirmation-handshake.json`。测试使用临时 fixture，不替用户批准或回答真实待确认。视觉和真实交互由用户验收，不采用 UI 自动化。

开发身份保持 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。本轮源码、已运行开发包和公开 main/Release/appcast 分别记录，不把历史 PR #67 合并误作本功能已推送。

源码提交 `5461059bedb918dc74f344feac2fe7b852020153` 已推送 [PR #68](https://github.com/Duoasa/QuotaView/pull/68)，用户已授权 CI 通过后合并 main。GitHub 完整 Swift CI 与最终合并状态以该 PR 为准；本地不重复完整回归。
