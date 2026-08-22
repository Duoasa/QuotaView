# QuotaView 0.3.6 灵动岛升级规格

> 文档编号：`QV-PRODUCT-ACTIVITY-ISLAND-004`
>
> 规格状态：`Accepted`
>
> 交付状态：`Verifying`
>
> 目标版本：`0.3.6 (Build 2)`
>
> 内部更新序号：`CFBundleVersion = 7`

## 1. 已确认范围

- 本版只升级当前单任务 Codex 灵动岛，不加入 `0.3.2 Preview 1` 的多任务
  实验；
- 在设置的“Codex 灵动岛”页面增加独立显示开关。关闭只隐藏浮窗，Codex
  本地 Hook、Socket 和状态连接继续工作；重新开启后按当前真实状态恢复；
- 提供两种动画：现有动画命名为“粒子球”，已确认的新动画命名为“波澜
  光晕”；设置页使用“上方实时光球预览、下方名称”的双选项布局，选择后
  立即作用于生产灵动岛；
- “完成后缩小”范围为 `5...60 秒`，“缩小后隐藏”范围为
  `5...120 秒`，步进均为 `5 秒`；控件显示全部档位刻度、当前档位和端点；
- 新活动立即展开灵动岛；修改等待时间时，正在等待的完成/空闲事件按新值
  重新计时；设置持久化并即时生效；
- 产品 Build 在 Marketing Version 改变后从 1 重新计数。本轮是
  `0.3.6 Build 2`，Sparkle 内部更新序号保持全局递增为 `7`。

## 2. 动画与状态要求

- “粒子球”保持当前稳定 Metal 动画和九种状态语义；
- “波澜光晕”复用已验收 Demo 着色器与参数：`style = 9`、玻璃开启、
  128 个 Float / 512 bytes、球体半径固定 `0.535`、轮廓形变固定 `0`、
  动画速度为参考节奏的 `1.5×`；
- 两种动画都适配未连接、空闲、思考、工作、压缩上下文、待确认、完成、
  失败和未载入九种状态；切换动画不能改变现有 AppKit/CoreText 外壳、状态
  文案、展开/紧凑几何和本地事件链；
- “波澜光晕”在状态切换时连续插值，并在速度变化时保持相位，球体不得出现
  不规则外轮廓；
- 设置页预览和生产浮窗复用同一渲染实现；Metal Pipeline 按设备与像素格式
  缓存，避免预览与浮窗重复编译；
- 开启 macOS“减少动态效果”后，两种光球和窗口收展改用静态状态反馈；
  Metal 初始化失败时“波澜光晕”降级到“粒子球”。

## 3. 设置与持久化

| 设置 | 键 | 默认值 / 范围 |
|---|---|---|
| 显示灵动岛 | `preferences.codexActivity.islandEnabled` | 开启 |
| 光球动画 | `preferences.codexActivity.orbAnimation` | `particleOrb` |
| 完成后缩小 | `preferences.codexActivity.compactDelay` | 20 秒；5...60 |
| 缩小后隐藏 | `preferences.codexActivity.hiddenDelayAfterCompact` | 100 秒；5...120 |

非法或旧存储值按 5 秒步进归一到最近的有效档位。设置页使用 macOS 系统
字体、语义颜色、小号原生 Switch 和 Slider；中文与 English 都必须完整
显示，并为选项、Slider 当前值和连接状态提供辅助功能语义。

## 4. 隐私与行为边界

- 不新增账号、凭据、网页抓取、遥测、云端转发或权限；
- 不读取或迁入多任务 Preview 的任务轨道、任务切换、当前任务跟随与仲裁
  逻辑；
- 手动关闭“显示灵动岛”不能卸载 Hook、关闭连接或丢失最新状态；
- 连接开关继续独立管理 Codex Hook 与本地连接，不与显示开关互相冒充；
- 隔离 Demo 保留在 `Prototypes/CodexActivityOrbVisualDemo` 作为动画调参和
  回归证据，不再作为生产运行入口。

## 5. 验证证据与出口条件

- 隔离 Demo：5 项测试、九状态 `128 × 128` Metal 离屏绘制通过；产品
  所有者已确认视觉、圆形轮廓和加快 50% 的节奏；
- 生产 `swift test`：66 项通过，0 失败；覆盖设置默认值、持久化、时间档位
  归一、运行中重新计时和“波澜光晕”资源/Pipeline；
- Universal Xcode Release 无签名构建通过；App、Widget 和 Hook 均为
  `x86_64 arm64`；App/Widget 均读取为 `0.3.6 / 7 / 产品 Build 2`；
- `AppIcon.icns`、`Assets.car` 和 `CodexActivityRippleGlowShader.txt` 均已
  进入 App 包；
- 本地 ad-hoc 验收包为 `dist/QuotaView-v0.3.6-build.2.zip`，SHA-256
  `2aacc1beab25ba82899f64d0e44de028e7a6239ada6ad3deaebf84b3050da807`；
  ZIP 全新解压后的深度签名、版本、资源与 Universal 架构复核通过；
- 代码与自动化验证完成后，交付维持 `Verifying`。设置页排版、两种预览、
  即时切换、开关和两段计时的视觉/交互结论等待产品所有者运行应用验收；
- 产品所有者已在 2026-08-23 明确批准 `0.3.6 Build 2` 进入完整稳定发布
  和自动更新序列；预期 tag / ZIP 为 `v0.3.6-build.2` /
  `QuotaView-v0.3.6-build.2.zip`。签名、公证、Release、回下载和 appcast
  证据只有实际完成后才能回填为已发布。
