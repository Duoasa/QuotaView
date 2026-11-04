# DSH 岛内审批

Spec ID：`QV-DSH-APPROVAL-001` · `Accepted / Complete` · 2026-11-04。

用户已明确要求“按这个方案接入DSH审批，完成后重启开发版”。Build 17 实现工具审批与显式交接；Build 18 修复真实反馈暴露的展示权限问题；Build 19 增加插件标题/模型补读；当前 Build 20 / 内部 153 增加不依赖插件重载的 Runtime 标题补读。真实客户端操作与视觉由用户验收，不包含推送或发布。

## 结论

通过 DSH 的公开 Host 插件接口接入，无须修改 DSH 客户端源码或模拟点击。已补入 QuotaView 的决策回传、请求生命周期与详情适配。

首批支持工具权限的「仅本次允许」「拒绝」，另设「在 DSH 中处理」交接入口，复用岛内审批界面和私有 Unix socket。不提供工具审批协议没有定义的「本会话允许」「永久允许」。用户提问及借用提问界面的应用授权属于另一条接口，留待单独适配。

## 核对范围与证据

| 对象 | 本次核对 | 证据边界 |
|---|---|---|
| QuotaView | 基于 `0707199a51a8026f6c46c2f618881a7ecf3e714a` 的本地修改 | 开发 Build 17 增加交互；公开 Build 16 仍仅观察 |
| 本机 DSH CLI | DSH / user-approval `0.1.7-rc.2` | 实际加载安装包的 ApprovalService 与 Cordis，8 项隔离接口冒烟通过 |
| 本机 DeepSeek Harness.app | Desktop / 内置 DSH `0.2.1-rc.5` | 只读检查 app.asar；user-approval/lib/index.js 与上述 CLI 文件逐字节相同 |
| 本机旧 DSH Desktop.app | Desktop `0.9.0`，内置 DSH `0.1.5-rc.2` | 静态确认相同的审批事件及结果词汇，未动态验证 |
| 官方 master | `8bd073392eef6f54e921a093b95076248eb08cbb` | 官方文档与 Host/Client 源码；不能代替已安装版本 |

CLI 与新 Desktop 的审批服务文件 SHA-256 均为 `6a5ad1ba3c3dc3abbbae52e6c8c4463970ee0c1c8988cebb0d5cf2acd17ee90b`。该模块相同不代表完整依赖、profile、客户端 UI 或真实任务已验证。

隔离证据：`.build/dsh-approval-research-20261104/source-audit.json`、`seam-smoke.mjs`、`seam-smoke.log`。使用内存 Agent/session 与合成响应器，没有模型调用、命令执行、真实审批或客户端配置修改。

## 调研时的缺口（已在 Build 17 补齐）

- `Sources/QuotaView/NativeAgentDSHPlugin.swift` 监听审计事件 `approval/asked` / `approval/decided`，映射成权限提醒/结束；发送固定 `awaitDecision: false`，发送后关闭连接，没有注册可返回决定的 `approval/request`。
- `NativeAgentRuntime.swift` 只更新观察状态，不保存可答复请求，也没有处理 socket 断开撤销。
- `ClaudeCodeBridge.swift` 已有认证、等待及决定回传能力，可复用传输基础；Claude 的权限协议不能直接当成 DSH 协议。
- `IslandLiveStore.swift` 仍以 Codex/Claude 两路分派响应，`IslandApprovalProtocol.swift` 有 Claude 专用标记。DSH 必须独立判断来源、能力和连接代次，不能伪装为 Claude。

## DSH 官方接口

可响应入口是 `ctx.on('approval/request', ...)`；监听或修改审计事件不能完成授权。结果为 `allowed-once`、`rejected`、`cancelled`、`unavailable`，仅前者授予本次动作权限。`never` 策略在派发监听器前拒绝请求，插件不应改变此策略。[官方审批说明](https://github.com/deepseek-ai/deepseek-harness/blob/8bd073392eef6f54e921a093b95076248eb08cbb/docs/subsystems/approval.md)

请求携带实际 Agent、工具名、可选 callId、原因与取消信号，不携带工具参数，也没有暴露服务生成的审计 approval ID。适配器需为实际等待中的请求生成连接 ID，绑定数据目录命名空间、进程 epoch、会话、轮次与 callId；不能拿相同工具名或最新审批作为响应目标。[官方类型](https://github.com/deepseek-ai/deepseek-harness/blob/8bd073392eef6f54e921a093b95076248eb08cbb/packages/interaction/user-approval/src/types.ts)

原客户端经 Agent 范围内的 Remote Event 接手审批。Host 监听器按 waterfall 顺序执行，返回结果占用本次决定，调用 `next()` 才交给后续处理器。因此新增 Host 监听器不会自动实现两个界面同时可答、任一端先答都关闭另一端。[官方 Client 实现](https://github.com/deepseek-ai/deepseek-harness/blob/8bd073392eef6f54e921a093b95076248eb08cbb/packages/client/ui-approval/src/client/index.ts)

## 已接受的首批行为

1. 启用 DSH 交互审批后，只接手已识别且具备完整详情的活动请求。先确认私有连接与能力；离线、关闭、队列已满、类型不支持或详情不全时立即 `next()`。
2. 岛内展示工具、完整待批准动作与原因，只提供「仅本次允许」「拒绝」两个决定。「在 DSH 中处理」撤销岛内响应资格并调用 `next()`，不等于拒绝或任务取消。
3. 断线、QuotaView 退出、停用或插件卸载，释放本地等待并交接。DSH AbortSignal 触发则结束为取消，晚到点击失效，不再启动另一份审批。
4. 观察事件与交互请求去重；区分「已发送」和「DSH 已结算」。socket 写出成功不是远端接受证据，应以可靠关联的结算/回执更新状态。
5. 保留 DSH 数据目录隔离。对子 Agent、ACP 所有者及额外审批插件，确认路由和原有策略后再接入；不能无条件 prepend 绕过其他审查。普通 Host 插件在启动时注册；已安装官方 Client 通过随后建立的 Remote Event 注册审批监听。保持普通 waterfall 顺序，已先注册的审批处理器可以继续占用请求；不保证任意第三方策略组合一定转到岛内。

首批采用单一处理者与显式交接。若要求双端始终同时可操作，需要专门的协调层或 Client 插件，共享一次性决定与取消通道；不能直接 `Promise.race(next(), islandAnswer)`，否则输掉的一方可能仍可点击或持有未结束请求。

## 详情与数据范围

原观察通道不传工具参数。可操作审批增加「仅待审批期间、仅本地内存」的有限详情通道：按当前轮次 callId 关联 `tool/call`，验证实际 schema 后提取命令、目标路径/变更或必要结构化参数。不转发整个历史会话、工具输出或凭据，不写入归档及诊断日志。

未知工具、关联失败、超长或参数不完整时回到 DSH；不能截掉关键内容后仍展示允许按钮。此项窄范围例外已同步至 Agent 接入规格。首批只支持原生 `bash` 和 `str_replace_editor` 的 create/str_replace/insert；view、插件/MCP 等未知类型回退，不为此读取账户信息或开放 HTTP 服务。

## 提问及其他授权

`userQuestions` 是独立的结构化提问接口；新版还支持 `intent: approval` 应用授权和 `plan-review` 计划确认。这些返回原问题选项，授权持久化由调用方负责，不能映射为工具权限结果。建议在工具审批通过后再适配问题选项、自由输入、超时继续、重连与晚到回答。[官方提问服务](https://github.com/deepseek-ai/deepseek-harness/blob/8bd073392eef6f54e921a093b95076248eb08cbb/packages/interaction/user-questions/README.md)

## 实施范围与验收

| 改动 | 目的 |
|---|---|
| DSH 插件 | 独立等待决定，不阻塞观察队列；处理取消、交接、卸载与详情关联 |
| DSH Runtime / 协议映射 | 保存活动请求，映射允许/拒绝，处理断线和完成，不复用 Claude 的持久化权限 |
| 岛内响应路由 | 按 Provider 和连接代次判断能力，复用现有视图/队列，避免 Codex 断线撤销 DSH 请求 |
| 连接设置与文案 | 交互审批开关、交接及数据范围说明、六语言与辅助功能；保留现有目录发现及安装标记 |

已通过的 8 项接口冒烟：允许、拒绝、无人接手、非法结果、never 策略、取消后迟到允许、顺序接手/交接、模拟连接失败后 next 回退。最后一项使用合成异常，没有真实 socket 或 UI。

实施后的 33 项定向冒烟通过，0 失败：生产插件 → 真实 Unix socket → Runtime/岛内模型 → 实际安装的 DSH ApprovalService → 审计结算，覆盖允许、拒绝、显式交接、取消后迟到答复、关闭审批开关、插件卸载、QuotaView 停止；不同数据目录的相同 session/call ID 并发审批、前置策略优先、超大/未知详情回退、观察去重、Codex 断线隔离以及既有 Claude 路由。证据 `final-smoke.log`。补入有界队列等待后，3 项相关冒烟复验通过，证据 `bounded-wait-smoke.log`。日志均位于 `.build/dsh-approval-research-20261104/`。

测试使用内存 session、临时独立 profile 和 UserDefaults，无模型调用、工具执行或 UI 自动操作。安装器显式测试 homeOverride 不再发现用户真实目录；默认运行安装器仍沿用原多目录发现。上述结果不等同官方 Desktop/CLI 或定制客户端真实任务已验收；这些环境的实际加载、原生交接、外观与操作继续由用户验证。

## 运行契约与边界

### 最终展示权限修复（2026-11-04，Build 18）

用户重试后，截图显示完整工具参数已到岛内，DSH 无原生弹窗，但岛内仍只有「在 DSH 中处理」。前者符合单一处理者设计；后者是确定的展示层缺陷：`IslandLiveStore.display` 仍以 `provider.isObserverOnly` 将 DSH 所有请求的 canRespond 设为 false。此前冒烟从内部请求提交，遗漏最终 display 投影，不能证明按钮可用。

Build 18 / 内部 151 为具备 DSH 协议的实际审批保留原 canRespond；普通 DSH 观察提醒和已撤销请求仍不可响应，不改变原生回答同步能力。冒烟改为读取最终 `display.taskDetails` 的确认请求，检查 DSH 来源、可响应状态与三个选项，并用其请求 ID 完成官方审批服务闭环；停用后确认展示也失去响应权限。7 项相关冒烟通过，证据 `.build/dsh-approval-research-20261104/presentation-smoke.log`。Debug arm64 运行证据 `.build/dsh-091b18-runtime/`；真实按钮操作与视觉继续由用户验收。

### 真实客户端反馈复核（2026-11-04 12:12）

用户截图显示原生 bash 提权审批已出现，而岛内仅有只读提醒；真实客户端接入不能视为已验收。本机只读核对该会话的审批事件，toolName 为 bash，参数键属于支持范围；DSH 主进程及 Host 自 10:17 持续运行，早于 12:06 插件更新，profile 已被热加载重写。

补充实际安装的 `dsh-api-remotes` + `ApprovalService` + Cordis + 生产适配器、隔离 socket 的顺序冒烟：启动时先注册适配器，1 个岛内请求并返回 allowed-once，原生监听未接手；原生 Remote Event 已注册后热加载适配器，0 个岛内请求、1 个原生请求。证据 `remote-order-smoke.mjs` / `remote-order-smoke.log`。这重现了热加载时原生优先的机制，但不证明截图的唯一原因。保持既有策略顺序，不通过 prepend 绕过其他审批处理器。

用户已表示将完整退出并重启 DSH、以新会话重试后反馈。当前等待该实测，不主动批准或操作其真实请求；本次只有诊断与文档更新，开发包仍为 Build 17。

- DSH 总开关仍默认关闭；启用后的独立「在灵动岛处理权限请求」偏好默认打开，保留用户关闭值。切换审批开关立即释放待处理连接，不关闭任务观察。
- 自动配置仅对 desktop/web/tui profile 声明可交互；ACP、其他 profile 和 subagent 均回原路径。插件更新后需重启对应 DSH 客户端加载；不代用户退出正在进行的 DSH 会话。
- 请求绑定本次适配器 epoch、数据目录命名空间、session 对象、当前 turn、callId、审计 ID 与独立 request UUID。仅开放轮次、完整匹配与完整参数可获 `admitted`，传输 ACK 不授予响应资格。
- 每适配器及 Runtime 最多 32 个待处理请求，观察同步最多等待 1.5 秒，接入确认最多 1.5 秒；确认后等待用户最多 10 分钟，届时撤销岛内响应并交回 DSH。命令/文件参数完整 JSON 至多 64 KiB，原因和 cwd 各 4 KiB，不截断关键动作；当前轮次最多回查 2048 条事件，关联失败直接交接。
- 完整参数只存待审批内存，经本机认证 socket 传输，界面以有界高度滚动显示；不写任务历史、偏好或诊断。结算、交接、断开、终止或关闭时移除参数。发送结果不代表已获 DSH 接受，等待关联的 approval/decided 结算。
- 双端同时可答、永久/会话权限、用户提问、计划/应用授权不在首批范围。未知请求保留原客户端处理。
- Debug arm64 构建、App/Widget 身份与实际运行路径见 `.build/dsh-091b17-final-runtime/`；源码和运行包对应，正式安装与发布通道保留。
