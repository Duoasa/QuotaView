# Agent 连接与任务接入

Spec ID：`QV-PRODUCT-AGENT-INTEGRATIONS-001` · `Accepted / Verifying` · 2026-10-09。

## Build 32 跨 Agent 问答与确认

同一待答请求只选一条提交通路。客户端已有可用的回答接口时，使用产生请求的实例。原生操作兜底需要匹配到已打开的原题和对应控件。只收到提醒、确认范围不明、会话已结束或目标已变化时，由用户在原客户端处理。

| 来源 | 岛内行为和边界 |
|---|---|
| Codex、Claude Code | 使用已有通路。Codex 默认启动的单题通过已打开的原卡提交，命令审批走 PermissionRequest Hook。 |
| DSH Desktop、Web、TUI | 在启用交互的配置中，普通单题通过原 Agent 的 `user-questions/request` 回传选项或自填。按原 waterfall 顺序注册。选择「在 DSH 中处理」、断线或停用均交给后续回答器。多题、多选、计划审阅、附带详情和未知字段交回原客户端。工具审批沿用原通路。 |
| Antigravity Desktop | 原生命令审批继续使用已有识别器。普通问答只接受展开、可折叠、包含单选组与原生自填控件的单题。绑定会话、轮次、原卡和控件，复核选项或文字与 Submit 后提交一次。保留已有自填草稿。跳过、调查表、翻页题和发送新聊天消息的建议卡不进入此通路。 |
| OpenCode 插件 | 继续通过发起请求的客户端回传。缺少原有 POST 方法时，使用原客户端的 `question.reply` 或 `permission.reply`。发送后含糊的结果留给原会话核实。 |
| Devin Desktop、Devin CLI | 默认为观察。两处设置可分别启用 `exec` 权限请求回传。完整参数和目录在岛内供审阅，单次决定通过等待中的原 Hook 返回。隐私、停用、旧轮次、断线、其他工具留给 Devin。普通问答仍在 Devin。 |
| Kimi Code、Gemini CLI、Copilot CLI、Devin CLI | 本机 Apple Terminal 或 iTerm2 下的受支持前台进程可绑定回原标签。绑定来自 Hook 自身的进程链，跳转时重查进程启动时间、TTY、终端宿主和标签。同一进程同时绑定多个会话时隐藏跳转，SSH、tmux、未知宿主或无法对应的进程由用户切回原终端。Kimi、Gemini、Copilot 的通知不产生岛内回答按钮；Copilot 的前置权限钩子会先于自身规则执行，未用它截断正常审批。 |
| Cursor | 沿用已验证的会话跳转。当前接入的 Hook 没有可供回传的原问题，普通问答留在 Cursor。 |

Kimi 的 PermissionRequest、Gemini 的 ToolPermission 都是通知；Copilot 的 permissionRequest 先于常规权限规则。参见 [Kimi Hook 事件表](https://moonshotai.github.io/kimi-code/en/customization/hooks)、[Gemini Hook 参考](https://geminicli.com/docs/hooks/reference/)和 [Copilot permissionRequest](https://docs.github.com/en/copilot/reference/hooks-reference#permissionrequest-decision-control)。

开发证据在 `.build/agent-interactions-097b32/`。DSH 隔离测试加载本机官方问答服务。OpenCode 测试用官方 SDK 1.19.5 和隔离传输验证实际请求路径、请求体及工作目录。Antigravity 的控件识别依据 2.34.0 渲染代码，提交生命周期经模拟控件验证。各客户端实际界面由用户验收。

## Build 16 一步接入

用户在列表或详情打开接入开关后，QuotaView 配置该 Agent 支持的渠道。二级页提供「检查连接」，并分别显示任务、额度、审批和问答的状态。用户已关闭的可选额度、Claude 状态栏和交互选项保持关闭；后续启动复用已有的接入配置和安装器。原生首次授权、缺少登录或组织 ID 时，显示下一步所需操作。

七种可选额度按来源启用，Devin Desktop 和 CLI 共用一个账户设置。手动保存的凭据优先。Cursor 可读取当前本机登录，Copilot CLI 可使用其登录，Gemini CLI 尊重自定义数据目录。显式连接允许首次系统授权，定时查找其他客户端的登录禁止弹出授权；Cursor 和 Copilot 在读取结束时复核登录，切换账户则弃用结果。原有 Codex、Claude Code 和 Antigravity 额度通道继续使用。真实账户覆盖按来源分别验收。

OpenCode 1.x 新会话使用当前实例的插件客户端处理审批和问答。只有原生未结请求才接收决定，单次允许、拒绝、单选以及多题按原始顺序作答；多选等不支持的表单在原客户端处理。岛内设置、隐私、连接、会话、轮次和请求身份共同限制提交。客户端内直接回答、关闭或结束轮次撤销对应能力。SDK 回传失败会呈现结果未确认，不能自动重发。

## Agent 接入设置

0.9.7 Build 20 起，11 个 Agent 共用单行列表。Build 21 在名称左侧恢复原有的 26 × 26 pt 品牌图标。右侧依次为状态图标、简短状态和接入开关。点品牌图标、名称或状态进入该 Agent 的二级页，可查看具体原因和检查连接。最右侧开关直接启用或停用该 Agent。

任务或额度已连通且无已知异常时显示绿色勾号「已激活」。连接失败、需要登录或授权时优先显示黄色警告「需检查」。已启用但尚未连通显示红色时钟「等待连接」，停用显示红色减号「已停用」。关闭后仍有清理错误的 Agent 显示警告。Build 22 起，列表恢复常规行最小高度 52 pt，上下内边距 8 pt，分隔线两侧各留 10 pt。二级页标题栏在名称左侧复用列表中的 26 × 26 pt 品牌图标。

Build 25 的排序以整行为拖动区域，左侧手柄提示可拖动。系统拖动预览包含品牌图标、名称、状态和开关。越过相邻行中线时，其他行以弹簧动画让出一个等高空位。松手后保存当前预览顺序，移出列表或取消会撤回预览。系统开启「减少动态效果」时，空位直接切换。顺序保存在本机的设置偏好中，新增支持的 Agent 依默认顺序追加。VoiceOver 可在手柄上逐位调整顺序。

辅助功能权限位于列表顶部。设置窗口顶部在标题左侧提供后退和前进按钮，共用胶囊背景和中央分隔线。历史记录覆盖侧栏页面及 Agent 二级页面；回退后访问新页面会清除原有前进记录。

常规双行设置（Build 40）的尺寸来自本机 macOS「系统设置 → 通知 → 应用程序通知」。辅助功能树中各行高 52 pt，相邻行起点相距 53 pt。实机窗口内的图标可见区域为 26 × 26 pt，距行左缘 11 pt，文字列距行左缘约 48 pt。分隔线高 1 pt，两侧各留 10 pt。

## 桌面会话导航

「Agent 接入」顶部、Codex 之前显示 QuotaView 的辅助功能权限开关。说明点名官方 DSH 和 Antigravity 的「前往对话」。开关显示 macOS 当前授权状态，点击进入系统设置管理授权，返回 QuotaView 时刷新。

0.9.7 Build 27 起，展开 DSH 或 Antigravity 任务详情时立即检查跳转条件，随后每五秒复核。授权生效或目标行加载后可显示入口，失去条件时收起；收起详情或切换任务即结束该任务的复核。点击时仍按原始会话 ID 验证目标。

| 来源 | 任务与原对话的对应关系 |
|---|---|
| Claude Code 桌面版 | 在普通及第三方模式的本机会话目录内交叉核对桌面 ID、Hook 的 CLI UUID、未归档状态和文件名。匹配字段支持 `cliSessionId` 与 `lastAssistantCliSessionId`。只有唯一匹配才打开。 |
| Claude Code 终端 | Terminal 按控制终端定位标签页；iTerm2 有分屏 UUID 时同时核对 UUID 和控制终端。显示及点击时验证 Claude 进程、启动时间、前台进程组和终端归属。只安装 CLI 即可。 |
| 官方 DSH | 标准桌面 profile 加载 QuotaView 的界面插件，通过官方侧栏扩展位置为现有会话行标记原始 ID。通过 macOS 辅助功能定位并点击该行，仅操作 `com.deepseek.dsh`。 |
| Antigravity App | 通过 Hook 的桌面来源或唯一的桌面日志目录确认来源。只在官方应用内定位同源、同端口、路径为 `/c/<UUID>` 的侧栏链接。 |
| Cursor | 查询本机索引中与 Hook UUID 对应的 `composerData` 键。官方编辑器内的 QuotaView 扩展按原始 ID 打开本机 Composer。 |
| Devin Desktop | 接受来自桌面进程的 Devin Local Hook 和本地会话存储标识。扩展通过 Devin Local 的连接器及原始会话 ID 打开对应编辑器。 |

Build 19 起，Terminal 与 iTerm2 首次未决定时显示「请求授权」。点击后由 QuotaView 对该终端请求 Apple Events 权限，无需已有 Claude Code 会话。若终端未运行，按钮明确标注「启动并请求授权」。已授权或已拒绝的条目可进入系统设置管理。

Build 10 在「Agent 接入」顶部按已安装终端显示自动化权限。浏览详情只检查权限，用户首次点击才请求 macOS 授权。关闭标签页、进程结束、换用另一会话或拒绝授权后撤销入口，展开的终端详情每五秒复核。嵌套桌面会话必须单独匹配自己的 CLI UUID。tmux、screen、SSH 和只能唤起整款应用的终端不生成终端目标。原有审批与回答入口沿用。

Build 33 修复原生任务事件的处理顺序。普通任务在读取客户端来源和会话元数据后生成跳转目标，DSH 的审批和完成事件使用同一个官方会话 ID。

Cursor 和 Devin Desktop 启用连接时，通过本机官方编辑器的扩展安装命令注册渠道专属的本地 VSIX。点击后，编辑器扩展读取本次有时限的请求，打开指定会话并回传结果。关闭连接时移除该渠道的导航扩展。DSH 和 Antigravity 按已有辅助功能权限工作。折叠工作区、归档会话或侧栏未挂载相应行时，入口可能隐藏。

已检查 Claude 3.6556.2、DeepSeek Harness 0.2.2-rc.1、Antigravity 2.33.0、Cursor 3.30.14 和 Devin 3.14.30825。Cursor、Devin 的官方 CLI 已在隔离扩展目录完成真实安装测试。原客户端实际选中会话的效果由用户验收。

## Antigravity（0.9.4 Build 18）

Antigravity 用量页使用全宽汇总卡（0.9.4 Build 23）。上排并列显示 Gemini 和 Claude/GPT 周额度，额外窗口每行两组续排；下排依次显示最近一天、30 天、累计 Token 和订阅套餐。套餐取账户快照中的简短档位名，缺失时显示「—」。

从 0.9.7 Build 7 开始，已安装 agy 时，定时和手动刷新都优先直接运行官方 CLI 的 /usage，在后台读取各模型组的有效剩余比例及重置时间。Agent 接入 → Antigravity 显示安装状态；点击「安装 agy」使用 Google 官方安装程序装到当前用户目录。安装成功后若已启用接入，立即刷新。

未安装 agy 或其未返回有效读数时，通过 macOS 辅助功能读取官方桌面端 Settings → Models 的套餐、模型组、剩余百分比和页面给出的重置倒计时。每五分钟或手动刷新时调用页面的额度刷新按钮。桌面端在后台时可临时打开额度页并恢复原页面；前台正在使用普通会话时，定时器跳过页面切换。最小化后如系统隐藏控件，手动刷新可暂时恢复窗口，读取后再次最小化。

桌面直读只需运行已登录的 Antigravity，并为 QuotaView 授予辅助功能权限。Build 8 起直接读取已安装的 agy 或 Gemini.app 内的 agy，失败后尝试桌面。所有来源均失败时显示「实时额度暂不可用」。CodexBar 的离线记录及标为 usageKnown=false 的项目不计入百分比。历史 Token 从本机会话日志独立统计。

### Antigravity 原生审批

0.9.7 Build 28 起，Antigravity 的 PreToolUse（含 ask_permission）只报告工具活动，立即交由客户端按原策略判定。开启岛内审批并授权 macOS 辅助功能后，QuotaView 在有活跃桌面任务时检查官方窗口。会话页地址须匹配原 UUID，页面须提供可识别的 Runtime permission 卡、授权范围以及可用的批准和拒绝按钮。灵动岛显示原卡上的问题、可编辑目标当前值、警告和选中范围；持久授权还须取得包含规则目标的原生选项说明。用户点击时重新读取会话、卡片、目标、范围和按钮，匹配后仅对该按钮发送一次系统辅助功能点击。客户端先处理、切换任务或关闭开关时撤下岛内入口。

Build 29 同时识别 2.34.0 桌面会话中的命令审批表单。用户 15:10 的网络测试截图显示可编辑命令、编号的授权选项、Skip 和 Submit。该表单与普通提问共用外框，因此识别时核对权限目标编辑框、原生单选组、当前选中的授权文字和两枚按钮。岛内批准提交客户端已选的范围，拒绝使用该权限表单的 Skip，客户端将其处理为本次拒绝。支持仅本次及带明确规则的会话或全局授权。选中 No、已有拒绝草稿或无法读出范围时，留在原客户端处理。

未挂载的卡片、来源不明的子会话、单独的 Dashboard 或 CLI 确认由原客户端处理。无需开启远程控制。[官方 Hook 说明](https://antigravity.google/docs/hooks)

## DSH 的 DeepSeek 余额（0.9.7 Build 26）

启用 DSH 的后台额度后，依次查找 QuotaView 手动保存的 API Key、进程环境中的 `DEEPSEEK_API_KEY` / `DEEPSEEK_KEY`、DSH 凭据存储中的 `refs.DEEPSEEK_API_KEY`。本机凭据按 DSH 的 v1 YAML 格式解析，默认文件为 `~/.dsh/.credentials.yaml`，设置了 `DSH_HOME` 时使用该目录。只向 DeepSeek 官方余额接口发起只读请求，按响应显示金额与币种。DSH 密钥在查询期间发生变化时丢弃该次结果。设置中的读取开关与手动配置仍可单独管理。

## 原生额度读取（0.9.7 Build 9）

Agent 详情可启用「后台读取额度」，在灵动岛的用量页查看。每五分钟刷新，支持手动刷新。关闭来源、停用接入或进入隐私模式时撤销展示。离线、未授权与无有效额度时显示不可用。DeepSeek 显示金额及币种，OpenCode Go 只使用订阅窗口。Devin Desktop 与 CLI 共用同一组织、一个额度来源。

QuotaView 使用系统 URLSession 向各服务查询，独立解析账户余额、额度窗口与重置时间。接口与计量规则参考 [CodexBar v0.85.0](https://github.com/steipete/CodexBar/tree/5dd48cab770a326691b25a124d37ffee12c5f7ac/Sources/CodexBarCore)。Build 8 曾链接 CodexBarCore 并分发独立读取程序，Build 9 将查询移入主程序。用户只需启用对应来源并授权账户。

Kimi Code 支持 API Key 及中国区 CLI 的有效登录；OpenCode Go 使用手动 Key 或本机启用的 Go 凭据。DeepSeek、GitHub Copilot、Cursor 与 Devin 使用对应服务的凭据，手动保存的凭据由本机钥匙串管理。Gemini CLI 使用已有的 Google 个人登录；令牌过期时，提供 OAuth 客户端配置可后台续期，否则等 CLI 更新登录后再读。断开网络、服务拒绝授权或缺少额度时显示不可用。

原生请求使用独立的临时网络会话，禁止携带凭据跟随重定向。停用后取消进行中的读取，并丢弃旧请求的结果。七个来源的接口路径与响应解析已通过定向夹具验证，真实账户覆盖待补。

Antigravity 支持系统及用户 Applications 目录下 Gemini.app 自带的 agy。查询子进程关闭自动更新，禁用浏览器启动，校验 CLI 版本后调用 /usage。Codex 与 Claude Code 沿用既有的原生额度通道。

## Build 15 任务与本地统计

卡片按会话 UUID 读取客户端摘要库的标题，标题为空时使用同一行的预览名。任务详情接收本轮公开的模型回复和工具名称，完成后显示最终回答。日志与标题索引可延迟写入，读取会短暂重试；新一轮任务会取消旧一轮的回填。私有思考、系统消息及工具参数不进入详情。

灵动岛「用量统计」在连接开启后提供 Antigravity 来源，按本地会话历史显示最近一天、30 天和累计 Token 及活动图。输入、缓存读取和输出按会话 UUID 与步骤计数，镜像日志和分块只计一次。缺少读数时显示等待；隐私模式隐藏来源与内容。本地历史未提供的账户额度、重置及价格不展示。

PreToolUse 按官方契约返回 `{"decision":"allow"}`，交由后续 Hook 及客户端原有审批策略处理。PostToolUse 继续返回空对象。

连接开关管理官方全局配置 `~/.gemini/config/hooks.json` 中的渠道专属组，关闭时移除该组。SessionStart、PreInvocation、PostInvocation、PreToolUse、PostToolUse、Stop 经现有本地 helper 转发任务状态和模型。后台任务尚未完全空闲时忽略 Stop。完全空闲时按终止原因区分完成、失败和中断。Hook 使用中性回执。配置格式见 [Antigravity Hooks](https://antigravity.google/docs/hooks)。

## 授权与目标

用户要求修复设置停留在用量页的问题；连接页采用 VibeIsland 的 Agent 列表，新增 DSH 和 Kimi Code，并明确允许参考 VibeIsland 的多 Agent 接入。沿用本轮查看实际效果的开发运行授权，不包含发布、推送或版本身份变化。

随后要求兼容基于 DSH 的定制客户端（例如本机 Scoder、DeepViewer），只做兼容，统一显示 DSH。多目录修订随后按用户“启动”要求进入 14:26 开发运行包。

连接页以十行列表呈现 Codex、Claude Code、DSH、Kimi Code、Cursor、Gemini CLI、OpenCode、GitHub Copilot CLI、Devin Desktop、Devin CLI，统一名称、圆角矩形真实品牌图标、连接状态与开关；展开箭头位于固定宽度最左列，状态固定列宽，名称可展开该来源的实际设置。图标来源与尺寸见[来源图标记录](../design/quotaview-provider-icons.md#agent-连接列表2026-10-09)。移除连接页独立预览；套餐、额度、Tokens、成本统计仍属于用量页。继续现有 QuotaView 中性开关与中英文文案。

## 参考与适配

2026-11-04：用户接受方案并要求实施，[DSH 岛内审批](dsh-interactive-approvals.md)已进入本地开发 0.9.1 Build 17。支持本次允许、拒绝与交回 DSH；公开 Build 16 保持仅提醒。实际客户端交互待用户验收。

- [VibeIsland 项目](https://github.com/vibeislandapp/vibe-island)以公开说明、社区内容为主；[更新记录](https://vibeisland.app/changelog/)记录 DSH 原生插件及 Kimi Hooks 接入。只读核对本机已安装适配器的事件接口与配置形式，未复制应用代码、图标或品牌资产。
- DSH：按本机 `@deepseek-ai/dsh 0.1.7-rc.2` 的公开 TypeScript 接口实现原创 `session/event` 插件，注册至现有 profile 的 `cordis.patch.yml`。不使用 Claude 兼容 Hooks 推断 DSH 原生事件。
- Kimi：按 [Kimi Code 官方 Hooks](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html) 实现 `~/.kimi-code/config.toml` 的 `[[hooks]]`；本机客户端为 2.1.1。兼容 `tool_call_id` 与 `tool_use_id` 字段，不将官方客户端内的审批接口替换为自动决定。
- CodexBar 参考预检：Provider 独立生命周期、迟到结果隔离及明确缺失值的做法适用。任务事件接口由各 Agent 决定，UI 采用用户指定的 VibeIsland 列表，不迁移参考项目的轮询和套餐布局。

## 行为与边界

| 来源 | 当前实现 |
|---|---|
| Codex | 保留原生任务流及补充 Hook；新增总开关，停用停止任务观察并撤下卡片，恢复后重新连接 |
| Claude Code | 保留现有 Hook、可交互审批及独立用量采集；展开后提供原有设置 |
| DSH | 插件发送开始、工具、权限提醒、压缩、完成/失败/中断、公开会话标题和模型；累计事件中实际提供的 Token；明确的 `origin=subagent` 父子关系进入已有子任务展示 |
| Kimi Code | Hook 发送开始、工具、权限提醒、压缩、完成/失败/中断、标题和模型；若提供明确非 `main` 的 `agent_id`，隔离到子任务，避免子任务完成覆盖主任务 |

- DSH / Kimi 首次默认关闭。启用写入本渠道配置后显示“等待会话”，只有接收到有效事件才显示“已连接”。配置失败显示原因与重试，即使开关已关闭也不隐藏清理失败。
- 配置状态与实时在线心跳不同：“已连接”表示本次运行已收到有效事件，不能据此推断客户端仍在线。
- DSH 在 desktop/web/tui profile、根会话和完整参数匹配时支持 `bash` 与 `str_replace_editor` 修改类工具的岛内审批；仅本次允许、拒绝或交回原客户端。审批开关默认打开，DSH 总开关仍默认关闭。未知类型、详情缺失、断线或停用回原路径，完整契约见 [DSH 审批](dsh-interactive-approvals.md)。Kimi 权限仍仅提醒，用户在原客户端确认，不展示可响应按钮。终止、失败和完成按来源实际发出的生命周期事件映射。Kimi `Stop` 是可被其他 Hook 阻止的预结束通知，不能据此宣称所有 Hook 决策之后的强一致完成。
- 不增加 DSH / Kimi 的套餐额度窗口、30 日历史统计和成本估算，没有来源的数值不伪造为零。DSH 从 Build 21 起按下方规则同步当前轮次最终正文；Kimi 的完整回答仍在原客户端查看。
- DSH/Kimi 新接入未经过真实会话端到端验收；事件契约之外的旧版客户端、跨设备配置、断线期间的历史重放和失联回收不作为已验证能力。

## 配置、隐私与资源不变量

- 各 Provider 独立私有 socket、认证令牌、支持目录和开关；会话标识以 Provider 为命名空间后哈希。DSH 额外纳入规范化数据目录的 SHA-256，父子身份、轮次和工具调用沿用同一命名空间；复制的 session ID 不会跨客户端覆盖。配置注入目录哈希，事件不传递原始目录，不增加定制客户端 Provider、名称或图标。
- 配置修改移入 utility 任务，按修订串行执行；旧任务不能发布新状态。停用停止监听并撤下其任务，不继续读取事件。
- 只增删本渠道标记块；保留用户及 VibeIsland 等其他工具的配置。修改前保存内容寻址备份，写前核对文件版本，原子替换单文件；保留原权限。多 profile 不构成文件系统事务，任一写入失败显示错误，重试会收敛全部 profile。
- 转发公开会话标题、模型、工具名、有限标识、生命周期及 DSH 实际 token 数；观察通道不转发提示词、思考过程、工具参数/输出、账户凭据和完整工作目录。用户明确授权 DSH 最终正文同步，范围见下节；另有 DSH 主动审批有限例外：仅传当前匹配动作的完整参数、cwd 与原因，经本机认证 socket 进入待审批内存，结束或交接后清除，不写历史与日志；参数上限与回退见专属规格。
- 观察插件异步写入、有限队列 256、连接超时 750 ms，错误不阻塞 DSH；DSH 交互请求使用独立连接与有界等待，不占用观察队列。Kimi Helper 不输出审批决定，连接/写入/回执各至多 250 ms。无新增周期性轮询或 GPU 预览。队列溢出丢弃最旧事件，不承诺离线历史完整性。
- Runtime 最多记录 512 会话，子任务展示复用现有 128 上限。DSH 按来源 epoch/seq 去重。

### DSH 最终回答（2026-11-04，Build 21）

用户明确选择「是，也接入最终回答」，已在 0.9.1 Build 21 / 内部 154 实施。根会话收到成功的 turn/end 时，插件最多回查当前轮次 8192 个事件，取最后一条 assistant/message 的 text 内容；遇到工具调用或 interrupted 标记不使用较早的说明文字替代。reasoning、工具输出、用户消息、失败/中断轮次不作为完成答案。正文与 Stop 使用同一事件，沿用 namespace、epoch/sequence、session 和 turn 验证及去重，不额外生成完成状态。

正文最多 64 KiB UTF-8，字符边界截断并明确标记；含正文的消息包上限 512 KiB，其他观察包仍为 16 KiB。Runtime 仅在匹配轮次的成功完成事件接纳正文，复用既有 Markdown 完成结果与超长提示；下一轮清除旧答案。正文仅保留在本地任务展示内存，不新增归档、磁盘正文缓存或诊断记录。缺少正文保持占位，不从提示词或摘要拼造。新插件加载后新完成的轮次生效，不补回此前完成的历史回答；更新插件需完整重启 DSH。

3 项定向冒烟通过，覆盖生产插件/真实 socket/Runtime/最终展示的正文、长文本截断、思考排除、失败轮次不返回答案及跨轮清理，并复验原审批与观察隐私路径；证据 `.build/dsh-approval-research-20261104/final-answer-smoke.log`。额外对用户反馈会话的最新成功轮次只读离线回放，232 字节正文逐字匹配原 text 内容、标题存在、思考未转发；日志只保存布尔值和字节数，见 `final-answer-replay.log`。这不等同真实客户端与视觉验收。Debug arm64 开发包运行证据 `.build/dsh-091b21-runtime/`，未推送或发布。

### DSH 定制客户端与多目录

2026-11-04 Build 20：用户继续反馈 Build 19 标题缺失。只读核对实际会话索引已有正确标题，DSH Host 仍是 12:15 启动，早于 12:23 的插件补读更新，已有模块缓存并不能因文件替换自动获得新逻辑。新增 QuotaView Runtime 补读：只对已由事件接纳的会话，从已配置数据目录的匹配 namespace 定位 `storages/session_projcache/sessions/<sessionID>.json`，只解码 version 7/title ver 1 的公开标题。不根据提示词猜标题，不扫描全部会话，不读取完整回答；缺失或不兼容时保留真实未知状态。

读取后台执行，文件上限 2 MiB，拒绝目录穿越和符号链接，每会话至少间隔 5 秒、最多 32 个同时读取，不增加轮询。结果需匹配当前运行代次、session、turn、epoch，且期间没有更新的标题才能应用。启用、缺少标题/新轮次或完成事件触发；停用取消并拒绝迟到结果。隔离测试沿用安装器的真实目录命名空间，验证不含标题的插件事件能使最终任务标题补齐，并继续完成审批；2 项相关冒烟通过，证据 `.build/dsh-approval-research-20261104/title-cache-final.log`。真实客户端显示待用户验收；最终回答仍未接入，用户选择待回复。

2026-11-04 Build 19：修复已存在的 DSH 会话在重连后显示「DSH 任务」或缺少模型的问题。此前只监听新产生的 session/title 与 request/header；用户实测会话标题在插件接入前已写入序号 19。现在首次收到每个 session 对象的事件时，从公开 requestHeader 折叠及最多 8192 条既有事件补取最近标题/模型，只将这两项元数据发往岛内。每个适配器/会话对象仅补读一次，后续沿用实时事件；不转发正文、工具参数或输出，不补造历史 Token。超出回查范围且没有标题时保持占位。隔离恢复会话与隐私过滤冒烟见 `.build/dsh-approval-research-20261104/metadata-smoke.log`。此包包含 Build 18 的审批最终展示权限修复，真实体验待用户验收。

- 只读核对本机运行 Scoder 的 `resource-locator.ts` 和独立 DeepViewer 对应源码：二者均将 `DSH_HOME` 设置为各自 `userData/harness-home`，沿用 DSH profile 与原生事件接口。兼容入口由目录结构判断，不硬编码品牌白名单，不合并用户数据。
- 默认目录 `~/.dsh` 与非空 `$DSH_HOME` 并行支持。启动、启用、重新检查或修改自定义目录时，扫描当前用户 `Application Support/<应用目录>/{harness-home,harness,.dsh}/profiles/<profile>`；不递归搜用户目录或会话。只接入包含 `cordis.yml` 和有效 `package.json.dsh.profile`、属于当前用户的 profile，跳过备份/迁移/归档/快照路径并对符号链接规范化、去重。
- 连接列表保持单一 DSH 行。展开后显示配置目录数量、重新检查和添加目录；非标准位置可选择数据根目录、profiles、具体 profile 或包含 harness-home 的应用数据目录。自定义目录最多 32 项，可移除；仍符合自动发现条件的目录由自动发现管理。
- 插件落在各个 profile 的可写 `cordis.patch.yml`。本渠道私有安装清单最多记住 512 个配置路径，先记录写入意图，确保部分失败后仍可停用清理。停用/移除只清理本渠道标记块；不可访问的路径保留在清单，待再次检查时清理。不删除客户端原有插件、配置、会话或缓存。
- 新配置需重启对应客户端使其加载（支持 live patch 的客户端也可能自行加载）。没有进程扫描、周期轮询或自动重启客户端。原生事件 API 不兼容的旧版/深度改造版尚不承诺支持。

## 设置导航修复

静态壁纸采用 `scaledToFill`，单纯裁切不保证命中区域随视口缩小。装饰图片明确禁用命中，容器设置视口内的 contentShape，导航提高层级。只读采样发现部分主线程时间等待 Metal drawable，未证明全局死锁，未把该观察冒充此次点击问题的唯一根因。

## 验收记录

- 2026-11-24，0.9.7 Build 27。用户为开发版开启辅助功能后，实测 Antigravity 可从灵动岛前往原会话。DSH 先前的会话跳转失败，新建会话后跳转成功。

- Swift Debug arm64 编译及 DSH JavaScript 语法检查；运行包身份、源码指纹、实际加载路径的结果见 [Handoff](../../HANDOFF.md)。
- 未新增/运行测试或 UI 自动化；未消耗真实审批/额度操作。
- 多目录修订：四个相关 Swift 文件定向 Swift 5 类型检查与 Node 插件语法检查通过，`git diff --check` 通过；证据 `.build/dsh-custom-clients-20261009/`。随后按用户“启动”授权完成 Debug arm64 增量编译并替换运行；14:26 / PID 53217，234 项输入、完整运行包及实际加载路径匹配。已核对 9 个根目录的 13 个 profile 注册标记、命名空间、原有其他配置、权限和备份；证据 `.build/dsh-custom-runtime-20261009/`。未重启兼容客户端或启动真实任务，真实会话并行与启停仍待验收。
- 用户验收：页面切换、列表布局、开关启停、重启 DSH/Kimi 后真实任务与权限提醒。未记录“视觉通过”或“真实会话联动通过”。

## 0.7.9 发布前回归

DSH 插件显式消费确认回执，避免连续事件逐条等待 750 ms 连接超时；新增两客户端命名空间、24 事件生命周期/隐私和停播夹具。正式包 Helper 的 11 个 Kimi 事件、只读权限提醒与不安全 route 拒绝已在隔离目录核对。真实客户端交互仍待用户验收；发布结果见[0.7.9 发布规格](release-0.7.9.md)。


## 四来源扩展（2026-11-01，0.8.7 Build 30）

用户在四个建议来源后要求「接入，使用官方 icon」，授权本地实现与开发运行更新。
复用既有 Provider 独立生命周期、配置串行化、迟到结果隔离、私有本地 socket，
沿用已接受的 CodexBar 参考边界；不迁入套餐抓取、OAuth 或新的界面框架。

| 来源 | 官方接口与配置 | 本次支持 |
|---|---|---|
| Cursor | [Hooks](https://cursor.com/docs/hooks)，`~/.cursor/hooks.json` | 提交、工具结果、压缩、完成/失败/中断及模型。跳过会改变权限处理的 preToolUse，不把工具拒绝当成正在等待审批；不宣称权限提醒支持 |
| Gemini CLI | [Hooks reference](https://geminicli.com/docs/hooks/reference/)，`~/.gemini/settings.json` | 提交、工具、模型、ToolPermission 提醒、压缩与 AfterAgent 完成 |
| OpenCode | [Plugins](https://opencode.ai/docs/plugins/)，全局 `~/.config/opencode/plugins/quotaview-<channel>-openCode.js` | 依据当前稳定版 v1.19.5 的插件 API，工作/空闲、工具、权限、模型/标题、完成/失败/中断；明确 parentID 的子会话隔离，失败后的 idle 不覆盖失败 |
| GitHub Copilot CLI | [Hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference)，`~/.copilot/hooks/quotaview-<channel>-copilotCLI.json` | 提交、工具、实际 permission_prompt 提醒、压缩、agentStop 完成与不可恢复错误；忽略子 Agent 的完成通知 |

- 新来源默认关闭，启用后在设置中安装该渠道的 Hook/插件。有效事件才进入「已连接」，没有真实在线心跳含义。启用后重启对应客户端。
- 配置采用精确命令归属识别和原子写入，保留其他 hooks 和设置，重复启用不重复注册；解析失败、外国内容占据独立文件或编辑冲突时停止写入并提示重试。备份存于 QuotaView 私有支持目录，避免被插件扫描器载入。
- 停用撤下该来源卡片、停止 listener 并删除本渠道配置；保留辅助程序和路由供缓存旧 Hook 的会话无害退出。不同来源同名 session 不合并。
- 三个命令 Hook 仅保留会话/轮次、模型、工具名与必要的 ID；不传提示词、工具参数/结果、会话文件、工作目录或账户凭据。OpenCode 插件沿用同样约束，最多 512 会话与 256 待发事件。
- 新来源均只观察，权限确认仍在原客户端；没有返回 allow/deny。Gemini/Copilot 权限通知未提供请求 ID，无法可靠匹配并行工具结果，因此不借其他工具的完成猜测已批准；提醒可手动隐藏，轮次终止会清除。Cursor 的 beforeSubmitPrompt 仅返回 continue，不改变工具权限策略。
- 不添加缺失的额度、Token、进度百分比或助手回答。Gemini/Copilot 未提供轮次 ID 时沿用会话内的开始/终止事件，不能宣称跨进程乱序终态有完整原生轮次保护。项目/组织配置可覆盖全局 Hook，云端或远程主机任务不属于本地 listener 支持范围。OpenCode 2.x 预览 API 不在本次兼容承诺内。
- 图标采用官方文件原始路径与颜色、离线打包，来源及哈希见[品牌资源](../design/quotaview-provider-icons.md#四来源官方图标2026-11-01087-build-30)。保持现有 22 pt 圆角图标、状态列和开关布局。

4 项隔离冒烟通过，覆盖各来源启用/停用/保留外部配置、非法配置保护、事件过滤、OpenCode 实际 socket 队列及子任务/失败隔离。既有 DSH 插件冒烟通过；实际运行包辅助程序 4 路 IPC 与失效路由中性输出检查通过。2026-11-01T14:35:29.154127+08:00 已更新运行 Build 30 / 内部 132，PID 67850，253 输入、18 资源与实际加载路径核对一致；证据 `.build/agent-expansion-087b30-complete-runtime/`、`.build/agent-expansion-087b30/`。未运行真实 Agent/账户任务，不将这些夹具等同四个客户端端到端验证。真实任务与视觉由用户验收，本次未推送或发布。


## 可用链路验证与结束事件（2026-11-01，0.8.7 Build 31）

- 新要求：从配置安装直到真实任务卡模型的事件链路必须可用，隔离解析/转换测试不能替代官方客户端验证。
- OpenCode 1.19.5 官方二进制在隔离目录实测：原插件已接收 idle，但客户端立即退出截断异步 socket 队列，造成任务停在 thinking。终态改用 `QuotaViewActivityHook --agent-hook --configuration <private-route> --event Flush`，同步提交在途及待发消息；每帧需 accepted ACK，最多 257 帧、调用总上限 1.5 秒。关闭/断线仍无害返回；不执行 shell 或代理审批。既有 source_epoch/source_sequence 去重避免重发导致重复任务。
- 运行组件新增可注入的安装器，生产默认路径不变，隔离冒烟使用临时目录和独立 UserDefaults；不添加生产 UI 模拟入口。
- 原 4 项接入冒烟及新增的 3 项链路冒烟最终通过。官方 OpenCode 正式客户端加载未经插桩的生产插件，使用本地确定性模型响应：connected=true，thinking → completed；另以真实 Node 进程立即退出覆盖丢失终态的回归。Cursor/Gemini/Copilot 使用实际安装命令、辅助程序、socket 与卡片模型，验证完成、相同 session ID 隔离和停用撤下。
- 证据 `.build/agent-usable-087b31/official-production/island-evidence.json`、`fixed-smoke.log`、`final-runtime-smoke.log`（前两项通过，新立即退出用例首次 PATH 夹具错误）、`exit-smoke.log`（修正测试进程继承环境后通过）。官方客户端二进制来源及哈希在 `official-client-identity.json`。
- 能力边界：OpenCode 已确认真实客户端任务状态链路，但本地模型响应不是云端账号、订阅额度、完整工具与审批场景验收。其余三家未安装，尚无真实客户端任务结论；不能标记「四家全部实测可用」。本轮不操作真实额度、不做视觉/交互自动验收。
- Build 31 / 内部 133 已进入 DevelopmentRuntime，253 生产输入、18 资源、运行身份与实际加载路径一致；记录见 Handoff。仍只保留本地修改。

可重复的官方客户端冒烟：先将官方 `opencode` 二进制置于 `.build/agent-usable-087b31/client/opencode`，再运行：

```sh
QV_OPENCODE_SMOKE_SCRIPT="$PWD/Tests/Fixtures/agent-integrations/run_opencode_smoke.py" \
QV_OPENCODE_SMOKE_ROOT=/private/tmp/quotaview-opencode-smoke \
swift test --filter NativeAgentRuntimeSmokeTests
```

模型 HTTP 服务只绑定 127.0.0.1，配置与缓存位于指定的隔离目录，不读取本机 Agent 的认证配置。没有环境变量时，官方客户端专项显示 Skip，其余本地链路冒烟正常执行。

## 安装与传输边界修复（2026-11-01 / 0.9.1 Build 9）

Kimi 采用 TOML 专用字符串转义，检查 hooks 赋值/普通表冲突并保留合法数组表；歧义转义键拒绝改写。Native 安装以最终权限创建独占临时文件，写后同步并原子替换；安装锁总等待最多 2 秒且可取消。Native ACK 必须匹配 eventID。

107 项相关隔离测试与开发包构建/重启通过；具体范围、证据和未改条目见[复核与修复记录](../design/quotaview-bug-fixes-2026-11-01.md)。本批仅本地；真实客户端及视觉由用户验收。

## Devin 双入口（2026-11-01，0.9.1 Build 10）

用户要求接入 CLI 和桌面版，随后明确拆成 **Devin Desktop** 与 **Devin CLI**。复用 NativeAgent 模块，连接页增加两个默认关闭的独立开关、状态和任务命名空间；不合并成一行。两者使用 [Devin 官网图标](https://devin.ai/favicon.svg)，沿用 22 pt 图标容器和现有列表样式。

### 接口与范围

- [Devin Local 自定义文档](https://docs.devin.ai/desktop/devin-local/customizations)说明 Desktop 的 Devin Local 与 CLI 共用 harness/config/hooks。桌面入口只观察本机 Devin Local；云端会话、旧 Cascade、受限工作区不在接入范围内。详情提示需信任工作区。
- 使用[官方 Hook 契约](https://docs.devin.ai/cli/extensibility/hooks/overview)及[生命周期](https://docs.devin.ai/cli/extensibility/hooks/lifecycle-hooks)：SessionStart/End、UserPromptSubmit、Pre/PostToolUse、PermissionRequest、Stop、PostCompaction。`prompt_id` 转为轮次身份，旧轮次结束不能覆盖新任务；PostToolUse 的 `success=false` 转为工具失败，不能推断整轮失败。Stop 是可被其他 Hook 阻止的预结束通知，与 Kimi 一样不承诺 Hook 决策后的强一致终态。
- 共用 `~/.config/devin/config.json` 的 hooks 字段。两入口各自写入准确归属的命令，停用仅删除本渠道、本入口命令；同用户/配置目录共用文件锁，避免双入口并发覆盖。支持 JSONC，编辑只涉及自有 Hook 节点和必要逗号，保留外部 Hook、未知字段和用户注释；重复键、非法配置或不可读文件拒绝修改。备份和原权限规则沿用现有安装器。
- Hook 只在触发时有界读取最多 32 层父进程路径：Devin.app / Devin Desktop.app 的主程序或 Frameworks helper 归入 Desktop，其余完整链归入 CLI；CLI 之后遇到交互 shell 时仍归 CLI，覆盖 Desktop 集成终端场景。链读取失败且无法确定来源时不发送事件，不猜测成已连接。修改应用名称、其他桌面封装或未来进程结构需真实客户端核验。
- 两个 Hook 都会被客户端调用，但只向匹配入口发送，防止重复卡。来源路径不进入 IPC。Devin 默认继承 Claude 配置；带 `DEVIN_PROJECT_DIR` 且不含 Claude `transcript_path` 的继承载荷在 Claude helper 中中性退出，避免多出 Claude 任务；正常 Claude 载荷保留。
- Build 10 初版仅转发生命周期、会话/轮次/工具标识和工具名；Build 12 增加下方当前会话模型/用量补读。无审批决定、自动批准、远程 API、额度或成本推算。两入口停用各自撤下卡片并停止监听与补读。
- 非默认 `--config`、云任务、应用改名和不同进程封装未验证。当前本机未发现 Devin CLI 或桌面应用；隔离 Hook/IPC 测试不能替代真实客户端任务与用户视觉验收。

### 本批验证

7 项 Devin 专项最终通过：事件映射/隐私、来源分流、共享 JSONC 幂等与独立卸载、混合 Hook 子数组保留、并发安装、坏配置保护，以及 CLI 生产 helper → listener → 任务卡/桌面规范载荷 → IPC → 任务卡。后者不等同真实 Desktop 进程到 Hook 的端到端验证；本机未安装 Devin。最终 CLI 用例使用 Build 10 运行包内辅助程序。6 项既有 NativeAgent 检查通过，1 项官方 OpenCode opt-in 跳过；本地化 708 模板/728 条目录文案通过。

初次临时 Devin.app 夹具被系统校验拒绝并触发用户可见“已损坏”提示；已清理并移除该测试方式，以纯来源规则测试及桌面规范载荷 IPC 验证替代，没有删除真实客户端或关闭系统保护。Build 10 / 内部 143 已更新重启，256 输入/19 资源及加载路径验证通过，证据与限制见 [Handoff](../../HANDOFF.md)。未推送或发布。

## Devin 当前任务模型与用量（2026-11-02，0.9.1 Build 12）

朋友实测最新版 Devin Desktop、选择 `swe-2-max` 时，卡片仍显示模型未知、无 Token。根因是初版只处理状态 Hook；没有读取会话模型及用量。当前修复适用于 Desktop/CLI 两个本机入口。

- 从当前会话的 `sessions.model` / `meta.json.model` 获取所选模型，不读取配置默认模型，不硬编码 `swe-2-max`。这表示会话模型选择，不宣称是服务端计费路由后的实际模型。
- 存储位置来自 Hook 继承的 `DEVIN_SESSIONS_DIR`，否则使用 `XDG_DATA_HOME/devin` 或 `~/.local/share/devin`，末尾为 `cli`。默认 SQLite `sessions.db`；兼容 `DEVIN_SESSION_STORE=files` 及已存在的 `sessions/<id>/meta.json`、`log.jsonl`。这些格式依据官方 CLI **3000.11.234** 实际建库与其官方文件迁移结果核对。
- `UserPromptSubmit` 在开始生成前捕获 SQLite 最大 node ID 或 JSONL 字节位置；后续只统计位置之后的 assistant 请求。使用持久化 `metadata.metrics.input_tokens + output_tokens`，不把 `num_tokens` / 上下文容量 / 金额当成消耗，也不额外叠加缓存分项。相同 `request_id`（缺失时 message/node ID）取最大值去重；这是本轮本地记录的输入与输出统计，不等同 `/session-stats` 的服务端计费维度。
- 活跃任务每秒在后台补读；Stop 后最多补读 10 秒，接收延迟落盘的末次消耗。新轮次清除旧 Token 显示和边界，旧轮次事件/异步读取结果不能覆盖新任务。重复开始事件不重设边界。停用取消补读并撤下卡片，不重建已隐藏任务。
- 无提交起点的中途接入只补模型，Token 保持未知；从更新后提交的新一轮开始统计。无指标、锁冲突、不支持的格式或超过读取上限不伪造为零；只有明确的数值零显示零。SQLite 只读、锁等待 20ms、VM 预算 80ms、每轮最多 8192 条，单值最多 1 MiB；文件存储每轮最多 16 MiB、每行最多 1 MiB、元数据最多 64 KiB，忽略尚未写完的末行。
- 隐私边界：SQLite 只投影模型/用量/去重 ID；文件存储有界解析当前会话文件，只保留这些字段。提示词、回答、工具参数/输出及凭据不保存、不转发。辅助程序仅额外经带认证的本机 IPC 传递由环境推导的存储目录、格式及位置，供后台读取；不接收 Hook 载荷中的任意文件路径，不进入公开任务内容。会话 ID 限定安全字符，数据库和日志须为普通文件。

验证：13 项 Devin 隔离冒烟通过，包含真实 CLI Hook 辅助程序 → listener → 卡片模型/用量、Desktop 规范载荷 → IPC → 卡片、重复请求/事件、新轮次、延迟末次写入、停用、只读与锁等待、JSONL 截断，以及缺失/坏数据边界。首次测试发现卡片跨轮保留旧 Token，已修正 Devin 专属轮次重置后全数通过。开发运行包内辅助程序另复验 1 项双入口模型/用量链路通过。另 1 项运行中 WAL 检查通过，数据库与 journal 字节未被观察器修改。官方 CLI 生成/迁移的隔离夹具，两种存储均由生产读取器成功解码；夹具请求值为合成值，并非真实在线推理。证据 `.build/devin-usage-smoke-final.log`、`.build/devin-usage-runtime-smoke.log`、`.build/devin-usage-wal-smoke.log`、`.build/devin-research/check-store.log`。

官方数据库关闭且 WAL 辅助文件缺失时，系统 SQLite 的只读连接可能返回不可读；运行中的写连接/WAL 存在时已验证可读。生产代码不为绕过此状态开启可写连接或忽略活跃 WAL，暂时不可读时保留最后有效显示；格式核对使用保持隔离连接的合成库模拟运行状态。

Debug arm64 开发包已更新重启为 Build 12 / 内部 145，257 输入与实际加载核对通过；详见 Handoff。未安装或登录真实 Devin Desktop，本机检查不代表朋友环境已修复，仍待其复测。此前已交付的 Build 11 DMG 不包含本批修复。源码经 [PR #130](https://github.com/Duoasa/QuotaView/pull/130) 合入 main `0a20049`，PR/main CI 均通过，各 781 测试、7 跳过、0 失败及 44 契约；本批未打包或发布。

Build 11 接受桌面执行器的 NO_TOOL_CALL 与 TERMINAL_STEP_TYPE 等正常终止枚举，仅明确的取消事件显示中断。连接页及任务卡采用原彩图标及原始透明画布。
