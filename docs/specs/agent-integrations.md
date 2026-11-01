# Agent 连接与任务接入

Spec ID：`QV-PRODUCT-AGENT-INTEGRATIONS-001` · `Accepted / Verifying` · 2026-10-09。

## 授权与目标

用户要求修复设置停留在用量页的问题；连接页采用 VibeIsland 的 Agent 列表，新增 DSH 和 Kimi Code，并明确允许参考 VibeIsland 的多 Agent 接入。沿用本轮查看实际效果的开发运行授权，不包含发布、推送或版本身份变化。

随后要求兼容基于 DSH 的定制客户端（例如本机 Scoder、DeepViewer），只做兼容，统一显示 DSH。多目录修订随后按用户“启动”要求进入 14:26 开发运行包。

连接页以十行列表呈现 Codex、Claude Code、DSH、Kimi Code、Cursor、Gemini CLI、OpenCode、GitHub Copilot CLI、Devin Desktop、Devin CLI，统一名称、圆角矩形真实品牌图标、连接状态与开关；展开箭头位于固定宽度最左列，状态固定列宽，名称可展开该来源的实际设置。图标来源与尺寸见[来源图标记录](../design/quotaview-provider-icons.md#agent-连接列表2026-10-09)。移除连接页独立预览；套餐、额度、Tokens、成本统计仍属于用量页。继续现有 QuotaView 中性开关与中英文文案。

## 参考与适配

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
- DSH / Kimi 权限仅提醒，用户在原客户端确认；不展示可响应按钮。终止、失败和完成按来源实际发出的生命周期事件映射。Kimi `Stop` 是可被其他 Hook 阻止的预结束通知，不能据此宣称所有 Hook 决策之后的强一致完成。
- 本次不增加 DSH / Kimi 的套餐额度窗口、30 日历史统计、成本估算和完整回答同步，没有来源的数值不伪造为零。完整回答在原客户端查看。
- DSH/Kimi 新接入未经过真实会话端到端验收；事件契约之外的旧版客户端、跨设备配置、断线期间的历史重放和失联回收不作为已验证能力。

## 配置、隐私与资源不变量

- 各 Provider 独立私有 socket、认证令牌、支持目录和开关；会话标识以 Provider 为命名空间后哈希。DSH 额外纳入规范化数据目录的 SHA-256，父子身份、轮次和工具调用沿用同一命名空间；复制的 session ID 不会跨客户端覆盖。配置注入目录哈希，事件不传递原始目录，不增加定制客户端 Provider、名称或图标。
- 配置修改移入 utility 任务，按修订串行执行；旧任务不能发布新状态。停用停止监听并撤下其任务，不继续读取事件。
- 只增删本渠道标记块；保留用户及 VibeIsland 等其他工具的配置。修改前保存内容寻址备份，写前核对文件版本，原子替换单文件；保留原权限。多 profile 不构成文件系统事务，任一写入失败显示错误，重试会收敛全部 profile。
- 转发公开会话标题、模型、工具名、有限标识、生命周期及 DSH 实际 token 数；不转发提示词、工具参数/输出、完整回答、账户凭据和完整工作目录。数据只走本机私有 socket。
- 插件异步写入、有限队列 256、连接超时 750 ms，错误不阻塞 DSH；Kimi Helper 不输出审批决定，连接/写入/回执各至多 250 ms。无新增周期性轮询或 GPU 预览。队列溢出丢弃最旧事件，不承诺离线历史完整性。
- Runtime 最多记录 512 会话，子任务展示复用现有 128 上限。DSH 按来源 epoch/seq 去重。

### DSH 定制客户端与多目录

- 只读核对本机运行 Scoder 的 `resource-locator.ts` 和独立 DeepViewer 对应源码：二者均将 `DSH_HOME` 设置为各自 `userData/harness-home`，沿用 DSH profile 与原生事件接口。兼容入口由目录结构判断，不硬编码品牌白名单，不合并用户数据。
- 默认目录 `~/.dsh` 与非空 `$DSH_HOME` 并行支持。启动、启用、重新检查或修改自定义目录时，扫描当前用户 `Application Support/<应用目录>/{harness-home,harness,.dsh}/profiles/<profile>`；不递归搜用户目录或会话。只接入包含 `cordis.yml` 和有效 `package.json.dsh.profile`、属于当前用户的 profile，跳过备份/迁移/归档/快照路径并对符号链接规范化、去重。
- 连接列表保持单一 DSH 行。展开后显示配置目录数量、重新检查和添加目录；非标准位置可选择数据根目录、profiles、具体 profile 或包含 harness-home 的应用数据目录。自定义目录最多 32 项，可移除；仍符合自动发现条件的目录由自动发现管理。
- 插件落在各个 profile 的可写 `cordis.patch.yml`。本渠道私有安装清单最多记住 512 个配置路径，先记录写入意图，确保部分失败后仍可停用清理。停用/移除只清理本渠道标记块；不可访问的路径保留在清单，待再次检查时清理。不删除客户端原有插件、配置、会话或缓存。
- 新配置需重启对应客户端使其加载（支持 live patch 的客户端也可能自行加载）。没有进程扫描、周期轮询或自动重启客户端。原生事件 API 不兼容的旧版/深度改造版尚不承诺支持。

## 设置导航修复

静态壁纸采用 `scaledToFill`，单纯裁切不保证命中区域随视口缩小。装饰图片明确禁用命中，容器设置视口内的 contentShape，导航提高层级。只读采样发现部分主线程时间等待 Metal drawable，未证明全局死锁，未把该观察冒充此次点击问题的唯一根因。

## 验收记录

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
- 仅转发生命周期、会话/轮次/工具标识和工具名；不读取提示词、工具参数/输出、压缩内容、凭据或历史会话。无审批决定、自动批准、远程 API、额度或成本推算。两入口停用各自撤下卡片并停止监听。
- 非默认 `--config`、云任务、应用改名和不同进程封装未验证。当前本机未发现 Devin CLI 或桌面应用；隔离 Hook/IPC 测试不能替代真实客户端任务与用户视觉验收。

### 本批验证

7 项 Devin 专项最终通过：事件映射/隐私、来源分流、共享 JSONC 幂等与独立卸载、混合 Hook 子数组保留、并发安装、坏配置保护，以及 CLI 生产 helper → listener → 任务卡/桌面规范载荷 → IPC → 任务卡。后者不等同真实 Desktop 进程到 Hook 的端到端验证；本机未安装 Devin。最终 CLI 用例使用 Build 10 运行包内辅助程序。6 项既有 NativeAgent 检查通过，1 项官方 OpenCode opt-in 跳过；本地化 708 模板/728 条目录文案通过。

初次临时 Devin.app 夹具被系统校验拒绝并触发用户可见“已损坏”提示；已清理并移除该测试方式，以纯来源规则测试及桌面规范载荷 IPC 验证替代，没有删除真实客户端或关闭系统保护。Build 10 / 内部 143 已更新重启，256 输入/19 资源及加载路径验证通过，证据与限制见 [Handoff](../../HANDOFF.md)。未推送或发布。
