# QuotaView 稳定单任务 Codex 灵动岛规格

> 文档编号：`QV-PRODUCT-ACTIVITY-ISLAND-004`
>
> 规格状态：`Accepted`
>
> 交付状态：`Verifying`
>
> 当前开发：`0.3.7 Build 1`（Sparkle 内部序号 `11`）
>
> 已发布基线：`0.3.6 Build 2`（Sparkle 内部序号 `7`）

本文件合并了 0.3.1 的稳定单任务基础契约与 0.3.6 的个性化升级，是当前
生产灵动岛的唯一规格。`0.3.2 Preview 1` 多任务实验不属于本规格。

## 目标与边界

- 通过非激活单一 `NSPanel` 显示当前 Codex 会话状态；不控制 Codex UI；
- 事件链保持 `Codex Hooks → 签名 Helper → 私有 Unix Socket → Store →
  AppKit/Metal`；App Server 只用于有界标题匹配；
- 不读取或转发 Prompt、命令、参数、工具输出、模型内容、会话记录或完整
  路径；不新增账号、凭据、网页抓取、遥测、云端转发或权限；
- 额度菜单、Widget、更新器和额度重置 Demo 不受本功能状态影响。

## 状态与事件映射

生产状态固定为：未连接、待机、思考、工作、压缩上下文、等待确认、完成、
失败和不可用。事件按以下语义投影：

| Hook 事件 | 状态 / 生命周期 |
|---|---|
| `SessionStart(startup/resume/clear)` | 待机 |
| `SessionStart(compact)`、`UserPromptSubmit` | 思考 |
| `PreToolUse`、`SubagentStart` | 工作 |
| `PermissionRequest` | 等待确认 |
| `PostToolUse`、`PostCompact`、`SubagentStop` | 思考 |
| `PreCompact` | 压缩上下文 |
| `Stop` | 完成并启动收起计时 |
| `SessionEnd` | 立即隐藏；更早事件不能重新打开 |

新活动立即展开。状态切换不能创建第二个岛、改变既有文案语义或使旧事件
覆盖较新的 SessionEnd。

## 显示、动画与时间设置

| 设置 | 持久化键 | 默认值 / 有效值 |
|---|---|---|
| 显示灵动岛 | `preferences.codexActivity.islandEnabled` | 开启 |
| 显示屏幕 | `preferences.codexActivity.screenPlacement` | `followHotspot`；可选 `codexScreen` |
| 光球动画 | `preferences.codexActivity.orbAnimation` | `particleOrb`；可选 `rippleGlow` |
| 完成后缩小 | `preferences.codexActivity.compactDelay` | 20 秒；`5...60`，步进 5 |
| 缩小后隐藏 | `preferences.codexActivity.hiddenDelayAfterCompact` | 100 秒；`5...120`，步进 5 |

- 关闭显示只隐藏浮窗，不卸载 Hook、不关闭 Socket 或丢失最新状态；重新
  开启后按真实状态恢复；
- “跟随热区”保持既有 `NSScreen.main` 定位；“Codex 屏幕”使用 Codex
  进程最大可见、零层级窗口与显示器的实际交集确定目标屏幕，窗口跨屏时
  选择交集面积更大的屏幕；
- 设置页使用单一“锁定到 Codex 屏幕”开关表达两种互斥状态：关闭对应
  `followHotspot`，开启对应 `codexScreen`；
- Codex 未运行、窗口最小化/隐藏、窗口几何不可用或目标显示器已断开时，
  自动回退“跟随热区”，不得让灵动岛消失或停留在屏幕外；切换设置、激活
  应用或显示器配置改变后重新定位；
- 仅当“Codex 屏幕”模式且灵动岛可见时，以 1 秒间隔复核窗口屏幕；隐藏、
  关闭灵动岛或切回“跟随热区”后必须停止该计时与窗口查询；
- 设置页使用“上方实时预览、下方名称”的粒子球/波澜光晕双选项；预览与
  生产浮窗复用同一渲染器；
- 粒子球保持既有九状态 Metal 动画；波澜光晕使用 `style = 9`、128 个
  Float、半径 `0.535`、轮廓形变 `0` 和 `1.5×` 节奏，状态连续插值且外轮廓
  始终为圆形；
- 修改时间时，正在等待的完成/空闲事件按新档位重新计时；非法旧值归一到
  最近的 5 秒档；
- Reduce Motion 使用静态状态反馈；波澜光晕 Metal 初始化失败时回退粒子球。

## 本地连接与安全

- Helper 固定安装在 Application Support，合并 `~/.codex/hooks.json` 时保留
  用户现有 Hook 并创建备份；首次连接只能引导用户在 Codex 中完成官方信任
  审查，QuotaView 不自动确认；
- Helper 只发送哈希会话 ID、工作区最后一级、事件类型、粗粒度工具类别、
  SessionStart 来源和时间；
- 屏幕定位只读取 Codex 进程 ID、可见窗口矩形和显示器矩形；不读取窗口
  标题、窗口内容或像素，不申请辅助功能或屏幕录制权限，非 Codex 条目
  立即丢弃；
- stdin 上限 2 MiB，Socket 消息上限 64 KiB；私有目录/Socket 权限分别为
  `0700/0600`，握手使用随机令牌并校验文件所有者与时效；
- 连接开关管理 Hook/Socket，显示开关只管理窗口，两者不得互相冒充。

## Requirement 与验收

| ID | 要求 |
|---|---|
| `ACTIVITY-ISLAND-01` | 单一非激活窗口、九状态和稳定事件顺序 |
| `ACTIVITY-ISLAND-02` | 最小脱敏本地链路及有界输入、权限和信任审查 |
| `ACTIVITY-ISLAND-03` | 显示开关不改变连接和最新状态 |
| `ACTIVITY-ISLAND-04` | 两种动画共用生产渲染器并覆盖九状态、Reduce Motion 与失败回退 |
| `ACTIVITY-ISLAND-05` | 两段时间范围、5 秒档位、持久化和运行中重新计时 |
| `ACTIVITY-ISLAND-06` | 中英文、键盘、VoiceOver 与设置页系统语义样式 |
| `ACTIVITY-ISLAND-07` | 可持久化选择跟随热区或 Codex 屏幕；多屏、跨屏与不可定位状态必须稳定回退 |

0.3.6 Build 2 的 Demo、66 项测试、Universal 构建与正式发布均已完成；
不可变资产、签名、公证、Release 和 appcast 证据见
[`VERSION_HISTORY.md`](../../VERSION_HISTORY.md#036-build-2)。完整生产视觉与
辅助功能交叉矩阵仍按 [`design-qa.md`](../../design-qa.md) 记录，不由发布
事实自动推导为通过。0.3.7 Build 1 的屏幕定位实现、72 项测试和 Universal
无签名 Release 构建已通过，App、Widget 与 Activity Hook 均为
`x86_64 + arm64`；多屏视觉与交互等待产品所有者验收，尚未签名、发布或
进入 appcast；该精确版本已获准启动正式签名、公证与发布链，完成前仍保持
`Verifying`。
