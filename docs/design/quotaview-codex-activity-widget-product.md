# QuotaView Codex 灵动岛产品文档

> 文档编号：`QV-PRODUCT-ACTIVITY-ISLAND-001`
>
> 文档状态：0.3.1 实现基线；等待产品所有者视觉与交互验收
>
> 开发版本：QuotaView `0.3.1 (Build 2)`
>
> 当前公开基线：QuotaView `0.3.1 (Build 1)`
>
> 更新日期：2026-08-01
>
> 适用平台：macOS 14 及以上

## ACTIVITY-00. 产品定位

Codex 灵动岛是 QuotaView 0.3.1 新增的常驻应用能力。它使用位于当前
macOS 菜单栏下方中央的非激活浮层，展示当前 Codex 任务的状态、操作和
Metal 流体球动画。

该功能不属于 WidgetKit 小组件。WidgetKit 的刷新频率、动画生命周期和
GPU 渲染能力不适合承载持续的实时状态动画；QuotaView 原有额度小组件与
本功能保持独立。

实现采用以下链路：

```text
Codex 官方生命周期 Hooks
→ QuotaViewActivityHook 脱敏辅助程序
→ 当前用户私有的本地 Unix Socket
→ CodexActivityStore 状态机
→ 非激活 NSPanel + Metal 流体球

Codex App Server thread/list
→ 仅匹配当前会话并解析窗口标题
→ 最大态第一行
```

不使用 Codex Desktop 私有 IPC，不读取或修改 Codex 任务内容，也不接入
任何账户写操作。

## ACTIVITY-01. 状态集

内部视觉状态固定为以下 9 种：

| 稳定标识 | 中文文案 | English | 产品语义 |
|---|---|---|---|
| `disconnectedCodex` | 未连接 Codex | Codex Not Connected | 用户已点击连接 Codex，但首次安全确认、Codex 重启或首条真实消息尚未完成。该状态只由 QuotaView 本地设置流程使用，不由 Hook 事件生成。 |
| `standby` | 空闲 | Idle | Codex 会话已连接，但当前没有正在执行或等待批准的操作。 |
| `thinking` | 思考中 | Thinking | Codex 正在分析、规划、生成内容或检查工具结果。 |
| `working` | 工作中 | Working | Codex 正在执行命令、修改文件、调用工具或协调子任务。 |
| `compactingContext` | 正在压缩上下文 | Compacting Context | Codex 正在压缩既有上下文，任务仍处于活动状态。 |
| `awaitingConfirmation` | 待确认 | Awaiting Confirmation | 任务被一项必须由用户明确批准的操作阻塞。 |
| `completed` | 已完成 | Completed | 当前回合已经正常结束，等待进入自适应收起流程。 |
| `error` | 失败 | Failed | 已可靠确认当前任务执行失败。 |
| `unavailable` | 未载入 | Not Loaded | QuotaView 无法取得可信的任务活动状态。 |

`等待输入`、`无任务` 和 `已取消` 不作为独立稳定状态：

- 普通问答中的等待回复不能冒充需要授权的 `待确认`；
- 没有活动任务时使用 `空闲`；
- 取消后的稳定状态回到 `空闲`。

`error` 与 `unavailable` 保留为完整产品状态，但 0.3.1 不根据缺乏明确
失败语义的 Hook 猜测这两个状态。连接故障在设置中独立显示。
`disconnectedCodex` 只表达首次连接进度，不能冒充 Codex 的真实任务状态。

## ACTIVITY-02. 官方 Hook 映射

| Codex Hook | 条件 | 灵动岛状态 | 当前操作 |
|---|---|---|---|
| `SessionStart` | `startup` / `resume` / `clear` | `standby` | 正在连接 Codex 会话 |
| `SessionStart` | `compact` | `thinking` | 上下文整理完成，正在继续任务 |
| `UserPromptSubmit` | 全部 | `thinking` | 正在分析新的任务 |
| `PreToolUse` | Shell | `working` | 正在执行终端操作 |
| `PreToolUse` | 文件编辑 | `working` | 正在修改项目文件 |
| `PreToolUse` | MCP | `working` | 正在调用外部工具 |
| `PreToolUse` | 子任务 | `working` | 正在协调子任务 |
| `PreToolUse` | 其他本地工具 | `working` | 正在执行本地工具 |
| `PermissionRequest` | 全部 | `awaitingConfirmation` | 有一项操作需要你的批准 |
| `PostToolUse` | 全部 | `thinking` | 正在检查工具执行结果 |
| `PreCompact` | 全部 | `compactingContext` | 正在整理较早消息以释放上下文空间 |
| `PostCompact` | 全部 | `thinking` | 上下文整理完成，正在继续任务 |
| `SubagentStart` | 全部 | `working` | 子任务已启动 |
| `SubagentStop` | 全部 | `thinking` | 正在汇总子任务结果 |
| `Stop` | 全部 | `completed` | 当前任务已完成 |
| `SessionEnd` | 全部 | 隐藏 | 不显示 |

自动上下文压缩之后，Codex 还可能发出
`SessionStart(source: compact)`。该事件必须继续显示为 `thinking`，
不得回退成 `standby`。

事件按辅助程序写入的发生时间排序。比当前快照更旧的事件一律忽略，避免
并发 Hook 或较慢进程把界面回滚到过期状态。

## ACTIVITY-03. 最大态与紧凑态

### 最大态

最大态从左到右分为 Metal 球体与三行文字：

1. 状态色圆点 + 当前 Codex 窗口名称；
2. 官方状态文案；
3. 当前正在执行的操作。

窗口名称优先使用 App Server 返回的 `thread.name`，不可用时降级为
`Codex · 工作区名称`，再降级为 `Codex`。窗口名称、状态和操作均使用
单行尾部省略，不能挤压既定间距或真实字号。

第一行圆点与文字按真实字形边界垂直居中；三行使用等距排版。第三行在
活动状态下显示 Codex 风格的高光扫过效果。

最大态尺寸根据状态文案长度使用以下生产点值：

| 状态 | 面板尺寸 |
|---|---:|
| 空闲 | `304 × 112 pt` |
| 已完成 / 失败 | `374 × 132 pt` |
| 未连接 Codex / 未载入 | `390 × 132 pt` |
| 其他活动状态 | `444 × 152 pt` |

### 紧凑态

紧凑态面板为 `270 × 72 pt`，其中可见胶囊为 `250 × 52 pt`，四周包含
`10 pt` 圆角阴影预留。

胶囊内只显示：

- 左侧 Metal 球体；
- 右侧剩余区域水平、垂直居中的状态文案。

球体按胶囊上、下、左各 `12 pt` 边距计算，可见直径为 `28 pt`。状态
文字字号为 `14 pt`，与球体保持 `14 pt` 间距。

最大态和紧凑态共用同一个内容视图、Metal 渲染器和圆角阴影层，通过尺寸
插值完成切换。不得创建第二个窗口交叉淡入，也不得启用原生矩形
`NSPanel` 阴影。

## ACTIVITY-04. 自适应显示规则

0.3.1 使用已经确认的两阶段收起方案：

```text
新活动
→ 立即显示最大态
→ Stop 后保持最大态 20 秒
→ 仍无新活动时切换为紧凑态
→ Stop 后累计满 120 秒
→ 仍无新活动时完全隐藏
```

补充规则：

- 20 秒或后续 100 秒内收到任何更新事件，立即恢复最大态并取消旧计时；
- `awaitingConfirmation` 不是完成状态，必须保持最大态提醒用户；
- 活动中的 `thinking`、`working` 和 `compactingContext` 不因单纯经过
  20 秒而收起；
- `SessionEnd` 立即隐藏当前会话；
- QuotaView 启动时没有可靠活动事件则保持隐藏，不伪造空闲状态；
- 用户在设置中开启功能后立即显示最大态“未连接 Codex”，不等待安装、
  Hook 或首个事件完成；
- 首次连接流程未完成时保持“未连接 Codex”最大态；收到重启后的第一条
  真实 `UserPromptSubmit` 后自动切换到真实活动状态；
- 正常 `SessionStart` 若没有进一步活动，20 秒后进入紧凑态，并在累计
  120 秒后隐藏；
- `SessionStart(source: compact)` 属于任务延续，不启动空闲计时。

## ACTIVITY-05. 动效与颜色

球体继续使用已在独立 Demo 中确认的 Metal 流体实现。各状态使用独立的
主题色、速度、湍流、脉冲和折射参数，并以平滑的慢 → 快 → 慢节奏循环。

状态色方向：

- 未连接 Codex：低饱和中性蓝灰；
- 空闲：低饱和蓝灰；
- 思考中：蓝紫；
- 工作中：青蓝；
- 正在压缩上下文：冷白、银白、纯白；
- 等待批准：琥珀；
- 已完成：绿色；
- 失败：红色；
- 未载入：中性灰。

上下文压缩状态必须同时表现：

- 整颗球体向中心压缩并回弹；
- 内部流体向核心汇聚并提高密度；
- 主压缩后具有一次较轻的二次收紧；
- 不使用红色或紫色。

开启 macOS“减少动态效果”后，取消面板尺寸过渡、流体循环、压缩跳动和
文字扫光，保留状态色与可识别的静态球体。

## ACTIVITY-06. 本地连接与隐私边界

用户在 QuotaView 设置的“Codex 灵动岛”页面明确点击“连接 Codex”后，
应用执行一次自动安装编排：

- 检测 Codex 版本与 Hooks 功能，必要时执行官方
  `codex features enable hooks`；
- 将当前签名 Helper 更新到固定路径
  `~/Library/Application Support/QuotaView/Helpers/QuotaViewActivityHook`；
- 合并写入 `~/.codex/hooks.json`；
- 保留既有 Hook；
- 安装前创建 `hooks.json.quotaview-backup`；
- 重复安装先移除旧 QuotaView Handler，不产生重复项；
- 断开连接只移除命令中包含 `QuotaViewActivityHook` 的 Handler；
- 现有配置结构无效时停止安装，不覆盖原文件；
- 首次安装或 Hook 定义变化后，QuotaView 自动打开一个 Codex CLI
  安全确认窗口并进入官方 `/hooks` 页面；
- 用户等待 CLI 首次加载完成，等待 QuotaView 自动输入 `/hooks` 并进入
  Hooks 页面；启动器确认“Press t to trust all”已经显示后才开放键盘，
  此时用户按 `T` 完成一次信任，QuotaView 自动识别结果并关闭临时 CLI；
- 如果安装前已有 Codex Desktop 进程，设置页提供一次“重新启动 Codex”
  操作；如果没有运行中的 Desktop，则直接进入等待首个真实事件；
- 用户不需要自行启动 CLI、输入 `/hooks` 或返回设置页手动刷新状态。

固定 Helper 命令路径和持久化认证令牌在应用移动与常规更新后保持不变，
避免 Hook 定义仅因 App Bundle 路径变化而重新要求信任。QuotaView 不修改
Codex 私有信任数据库、不使用 UI 自动化代替 Trust，也不使用
`--dangerously-bypass-hook-trust`。

自动打开逻辑只负责启动 Codex CLI 和进入官方 Hook 审查页，不发送 `T`，
不代替用户确认信任。只有用户在已验证的“Trust all”页面实际按下 `T`，
并且 Codex 输出信任完成界面后，启动器才写入权限隔离的本地完成信号。
打开审查页时记录当前 Codex Desktop 进程；在该进程重新启动前，设置用
CLI 产生的 Hook 事件全部丢弃，不能把连接状态误判为“已连接”或驱动真实
任务动画。

启动器不得依赖固定秒数或输入提示符单一信号发送 `/hooks`。Codex 会在
初始化检查完成前提前绘制输入提示符，因此启动器必须继续等待终端输出
连续稳定 3 秒；如果审查页没有打开，可以在有界次数内重新等待稳定并
重试 `/hooks`。在官方“Trust all”提示出现前，用户键盘输入不得转发给
Codex，避免提前按下的 `T` 落入普通任务输入框。

Hook 辅助程序会收到 Codex 官方 Hook JSON，但只保留并转发：

- SHA-256 后的会话和回合标识；
- 工作区路径最后一级名称，最多 80 个字符；
- Hook 事件类型；
- Shell、文件编辑、MCP、子任务或本地工具等粗粒度类别；
- `SessionStart` 来源；
- 本地发生时间。

辅助程序不转发提示词、命令正文、工具参数、工具输出、模型内容或会话
记录路径。标准输入限定为 2 MiB，桥接消息限定为 64 KiB。

Unix Socket 位于当前用户的 QuotaView Application Support 目录，权限为
`0600`，每条消息还需通过随机令牌认证。接收端设置有界读取时间，异常或
超大消息不能阻塞 Codex。Codex 沙盒禁止 Socket 时，Helper 回退到权限为
`0700` 的当前用户 `/tmp` 队列，事件文件权限为 `0600`。传输失败同时写入
不含会话、工作区、事件或工具业务数据的诊断日志，只记录时间、错误代码
和回退结果。

每条桥接消息还必须携带由固定 Hook 基础命令派生的安装标识。旧 Codex
进程、旧 Helper 或旧 Hook 定义产生的事件即使持有相同认证令牌，也不能
推进重启、信任或“已连接”状态。

App Server 只用于把 Hook 会话标识匹配到 `thread.id` / `sessionId`，
并解析 `thread.name` 与工作区降级名称。QuotaView 不保存或展示
`thread.preview`、turn、item、提示词或模型回复。

## ACTIVITY-07. 设置与辅助功能

设置窗口新增“Codex 灵动岛”页面，默认只显示新手所需的信息：

- 未启用、正在准备、需要安全确认、等待第一条消息、已连接和需要处理；
- “连接 Codex”/“打开安全确认”/“重新启动 Codex”/“停用”主操作；
- 明确引导用户等待 CLI 完成首次加载、等待 QuotaView 自动输入 `/hooks`
  并进入 Hooks 页面，只在看到“Press t to trust all”后按 `T`；
- 重启 Codex 和发送第一条真实消息的后续单步引导；
- 自适应收起规则；
- Hook 信任与隐私说明。

Codex 版本、Hooks 功能、本地桥接和诊断日志收进默认折叠的“连接详情”，
不要求普通用户理解这些技术概念。

QuotaView 收到当前固定 Hook 定义产生的第一条真实
`UserPromptSubmit` 后才显示“已连接”。其他真实事件只能将状态推进到
“等待首个事件”。启用状态、事件证据和固定命令标识会持久化；后续启动
自动更新 Helper，并仅在 Hook 定义或功能开关变化时重新进入重启/信任流程。

灵动岛为非激活、忽略鼠标事件的状态展示层，不抢占键盘焦点。最大态与
紧凑态分别提供本地化 VoiceOver 状态值；完整辅助功能标签包含窗口名称、
状态和当前操作，不能只依赖颜色。

## ACTIVITY-08. 0.3.1 验证边界

自动化验证覆盖：

- 11 种官方 Hook 的状态映射；
- `SessionStart(source: compact)` 的特殊映射；
- 旧事件不能覆盖新状态；
- 完成 20 秒后紧凑、完成满 120 秒隐藏；
- 新事件取消旧的收起计时；
- 线程标题匹配与隐私降级；
- Codex 环境检测、必要时启用 Hooks；
- 开启后立即显示“未连接 Codex”，不等待 Hook 事件；
- 私有启动器通过真实 PTY 打开 Codex 并输入 `/hooks`，但不自动确认信任；
- 私有启动器等待输入提示符且终端输出连续稳定 3 秒后再发送 `/hooks`，
  审查页未出现时有界重试，覆盖慢速冷启动与长列表检查竞态；
- 官方“Trust all”页面出现前不转发用户按键；用户确认后验证 Codex 输出
  并产生本地完成信号；
- 设置状态严格区分等待信任、信任完成等待重启和等待首个真实事件；
- 设置用 CLI 的事件在 Codex Desktop 重启前不能建立连接证据；
- 固定路径 Helper 安装与更新；
- Hook 安装、重复安装、卸载、既有配置保留和无效配置拒绝；
- 只有真实 `UserPromptSubmit` 能建立“已连接”证据；
- Helper、App 与 Widget 的 Universal 架构；
- 0.3.1 (Build 1) 版本信息。

以下项目继续等待产品所有者运行应用后验收：

- 最大态 / 紧凑态的最终尺寸、居中和截断；
- 各状态颜色、速度、流体感和压缩效果；
- 最大态与紧凑态切换的流畅度；
- 深色 / 浅色桌面背景；
- 简体中文 / English；
- Reduce Motion / Increase Contrast / VoiceOver。

在产品所有者明确确认前，不得把视觉与交互结果记录为“已通过”。

## ACTIVITY-09. 参考依据

- [OpenAI Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [OpenAI Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [QuotaView WidgetKit 方案](./quotaview-widgetkit-solution.md)
- [CodexBar macOS 设计参考](../reference/codexbar-macos-design-reference.md)
