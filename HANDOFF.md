# QuotaView 项目 Handoff

更新日期：2026-08-30

公开版本、tag、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。
本文件只保存当前迭代、未完成验证和下一步；分支、HEAD 与工作树状态必须
通过 Git 实时读取。

## 1. 当前定位

| 项目 | 当前值 |
|---|---|
| 稳定版 | `0.4.1 Build 1` / `v0.4.1-build.1` / GitHub Latest |
| 回滚基线 | `0.3.7 Build 1` / `v0.3.7-build.1` |
| 公开预览 | `0.3.2 Preview 1`；不属于稳定源码或 Stable appcast |
| 当前候选 | `0.4.2 Build 1`；Sparkle 内部更新序号 `14`；产品所有者已批准发布，正式发布门禁执行中 |
| 当前主题 | 在 0.4.1 的独立进度条灵动岛内增加晶钻前沿、液滴涌动和液态涌浪，与现有状态烟雾组成四选一；设置页提供圆角方形真实预览；修复活动任务误隐藏与任务结束后鬼影动画 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一版本内逐次递增；
Sparkle `CFBundleVersion` 跨 Marketing Version 单调递增。

## 2. 当前规格与状态

| Spec | 状态 | 结论 / 未完成项 |
|---|---|---|
| [`QV-RELEASE-0.4.2-001`](docs/design/quotaview-0.4.2-release.md) | `Accepted / Verifying` | 产品所有者已批准当前候选发布；等待 Developer ID、公证、GitHub Latest、回下载与 Stable appcast 闭环 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008`](docs/design/quotaview-activity-island-lifecycle-continuity-0.4.2.md) | `Accepted / Verifying` | 投递来源、ACK/队列、turn 感知终态锁与生命周期动画门控已实现；App Server 合成完成路径已删除，完成态只接受真实 `Stop`，103 项测试通过 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007`](docs/design/quotaview-progress-effects-0.4.2.md) | `Accepted / Verifying` | Drops 已改为细密微粒、Slosh 可视性已提高，三个新效果逐状态复用状态烟雾 Profile；当前候选已获发布批准 |
| [`QV-RELEASE-0.4.1-001`](docs/design/quotaview-0.4.1-release.md) | `Accepted / Released` | Developer ID、公证/Staple、GitHub Latest、回下载启动和 Stable appcast 在线签名核验均已完成 |
| [`QV-RELEASE-0.4.0-001`](docs/design/quotaview-0.4.0-development.md) | `Superseded / Released` | 0.4.0 只保留为大规模开发身份，不创建公开 Release；成果已由 0.4.1 Build 1 正式发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006`](docs/design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Released` | 进度条顶层样式、计划识别、单步骤回退、完成高光分层与结束事件收敛已随 0.4.1 Build 1 发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005`](docs/design/quotaview-codex-activity-island-size-0.4.0.md) | `Accepted / Released` | 100% / 85% / 75% AI 球展开尺寸及进度条固定双语几何已随 0.4.1 Build 1 发布 |
| [`QV-PRODUCT-QUOTA-WINDOWS-003`](docs/design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 多周期额度已随 0.3.7 Build 1 发布并进入 Stable Feed |
| [`QV-PRODUCT-ACTIVITY-ISLAND-004`](docs/design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；不包含多任务 Preview |
| [`QV-PRODUCT-APP-UPDATES-003`](docs/design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.3.5、0.3.6、0.3.7 与 0.4.1 均已进入 Stable Feed；尚缺一次真实 N → N+1 替换与重启记录 |

`0.4.1 Build 1` 的 93 项测试、PR #34 GitHub CI、Universal、Developer ID、
Apple 公证/Staple、GitHub Release/Latest、回下载、启动冒烟与公开 EdDSA
appcast 均已完成；不可变证据只在
[版本历史](VERSION_HISTORY.md#041-build-1) 保存。完整视觉与辅助功能交叉
矩阵，以及真实 N → N+1 应用内替换和重启，尚未记录为通过。

`0.4.2 Build 1` 当前本地候选已完成四种进度条效果与真实圆角方形设置预览，
并修正活动任务因局部结束事件沉默 20 秒而误隐藏的问题。第一轮视觉验收后，
Drops 已从大颗粒改为 `2.35` 渲染像素单元的细密微粒场，Slosh 主体、波峰和
回波可视强度已提高；三个新增效果在九种 Codex 视觉状态下完整复用状态烟雾
Profile。计划进度前沿向新目标值的追赶速度已减半，达到同等接近程度的时间
约翻倍；晶钻、液滴和涌浪在完成填充走满后新增 `0.30 s`、峰值 `14%` 的
局部细节高亮，状态烟雾保持原样，Reduce Motion 不播放该脉冲。真实百分比、
单调投影与完成事件来源保持不变。本轮 `swift test` 103 项、0 失败；
Universal Xcode Release 本地
ad-hoc 构建通过，App、Widget 与 Activity Hook 均为 `x86_64 arm64`，包内
身份为 Marketing `0.4.2`、内部序号 `14`、产品 Build `1`，`AppIcon.icns`、
`Assets.car` 和严格深层签名检查通过。本地归档为
`QuotaView-v0.4.2-build.1.zip`，SHA-256
`42f0e35695857bac0203c522ec73253fb1fe05fbf89dc97c788b37406c2bf4fe`。
本地候选已退出旧实例并重新启动，运行路径指向本工作树 `dist`；安装的
Activity Hook 与包内 Helper SHA-256 一致。产品所有者已确认当前候选完成度
满足发布；正式提交、Developer ID、公证、GitHub Release、回下载与 appcast
证据仍在执行。完整深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce
Motion 交叉矩阵未单独记录为全量通过。
本轮 600 秒本地序列覆盖开始、思考、工具、权限、压缩、子任务、长静默、
完成、迟到事件、新一轮和 SessionEnd，并暴露两项终态边界：`Stop` 后的
`SessionEnd` 曾被误拦截；后续任务若缺少 `UserPromptSubmit`，首个前置活动
也曾无法解除完成态。两项均已修正。修复后 35 秒已安装 Hook 序列确认迟到
`PostToolUse` 被忽略、无提示提交的新 `PreToolUse` 被应用、最终
`SessionEnd` 被应用；诊断日志现在区分应用/忽略并在容量满后安全滚动。
真实四步任务进一步暴露 `PostToolUse` 后 App Server 会瞬时返回当前 turn 的
`completed/idle`，导致状态机在真实 `Stop` 前主动制造完成态；turn ID 匹配
无法修正这项语义冲突。现已删除 App Server 终态核对与合成完成快照，局部
步骤只保持 active，完成态唯一来源为真实 Hook `Stop`；终态锁在 turn ID
可用时还会拒绝同一已完成轮次的迟到前置事件。修复包已重新启动，当前候选
已获产品所有者发布批准。

0.4.0 开发周期的尺寸切片在本次截图修正前曾完成 `swift test` 78 项、
0 失败。进度条改造按产品所有者要求仅运行
`swift test --filter 'StateSmoke|CodexActivityExpandedSize|NativeSettingsRow'`：13 项通过、
0 失败，覆盖旧偏好迁移、
隐私化计划计数、
近似进度计算与生命周期、从 0% 开始的进度前沿投影、无计划单步任务随时间与状态推进并封顶 50%、计划接管不倒退、扩散
shader、完成态烟雾淡出、四周绿色辉光时间与几何边界、Reduce Motion、展开左对齐/
紧凑居中文字几何、展开与紧凑态跨简中/英文固定尺寸、最大内容不裁切、
普通烟雾在当前前沿范围内由最左 50% 到尾端 100% 的动态透明度增强、压缩态低亮度冷灰白配色与低速弱扩散、执行态低饱和亮青蓝配色、其他活动状态更快且周期变速的双尺度动态扩散、完成动画绕过局部渐变、无文字阴影、统一次级文字色、
0.5 pt 状态圆点描边、20 pt 展开圆角
与生产 Metal 管线；设置页已移除分段 Picker 外层会把可见控件居中的
`200 / 160 pt` 透明固定框，并由实际 `NSSegmentedControl` 几何测试确认
右边缘贴齐设置行 `18 pt` 右内边距；另有 3 项定向测试覆盖顶层样式默认值、
持久化和“尺寸档位只作用于 AI 球”的几何边界。进度条已从 AI 球动画枚举中
拆出，旧 `smokeProgress` 会迁移为独立样式；完成态将岛体内部缩进的圆角
路径作为下层四周阴影源，另以独立上层 `1 pt`、sRGB `#00FF11`
绿色描边保持边缘纯净；
呼吸只改变下层外部辉光强度与半径。进度条窗口透明效果预留由 `10 pt`
扩大到 `30 pt`，上层岛体表面自然覆盖内部光源，已移除偶奇遮罩且不再由
窗口边界裁出矩形；同一轮 `Stop` 后的迟到结束事件会被忽略，完全缺少
`Stop` 时结束型事件静默 `20 s` 后隐藏，重启旧事件按原始时间收敛；
随后为 0.4.1 定版补跑 `swift test` 93 项、0 失败。Universal Xcode Release
无签名构建通过，App、Widget 与 Activity Hook 均为
`x86_64 arm64`；候选身份为 Marketing `0.4.1`、内部序号 `13`、产品 Build `1`；
Activity Hook 对真实 `exec` 包装输入的一次性 Unix Socket 端到端检查确认
输出仅含三类步骤状态计数，不含原始脚本、步骤文字或 explanation；
最新 ad-hoc 本地验收包已重新构建并启动；`git diff --check`、临时 Debug 标记
和真实额度消费调用搜索通过。正式发布提交为
`e14039eeb7021041f384b10db386a80844694b0f`；Developer ID 封包、Apple
公证/Staple（Submission `fd08ea22-9a55-4f63-9279-f10f0663eb7a`）、
GitHub Latest、回下载逐字节一致与启动冒烟均通过。正式资产为
`QuotaView-v0.4.1-build.1.zip`，大小 `13,068,004 bytes`，SHA-256 为
`ae8cf53acc6e6473ebf33bb853b7448672b48c4e849ef4b219efd74b18a9a2a3`。
Stable appcast 已由 `gh-pages` 提交
`e8312e45e344fbb9fcb01875ab27a65ce47506d0` 发布，线上 SHA-256 为
`afcce62e375f3f35f6557308343e47349e0d895ab23489fb101b537c58abc852`，
逐字节与 EdDSA 验证通过。产品所有者已确认当前生产 App 没有发现新的视觉
问题并批准发布；完整深浅色、多屏、VoiceOver、Increase Contrast 与
Reduce Motion 交叉矩阵仍未单独记录为全量通过。

## 3. 长期边界

- 后续版本必须由产品所有者针对精确版本重新批准，不能沿用 0.4.1 的
  appcast 准入；
- `0.4.1 Build 1` 是当前正式 Release、GitHub Latest 与 Stable appcast
  条目；0.4.0 不创建公开 Release；
- GitHub push、tag 或 Release 默认不进入自动更新序列；
- 稳定版只保留单任务灵动岛。多任务 Preview 的 tag、Release 和归档分支
  `codex/archive-0.3.2-preview.1-multitask-island` 仅供历史参考；
- 完整视觉、交互与辅助功能结论只能由产品所有者验收后记录。

## 4. 下一步

1. 从最终提交完成测试、Universal、Developer ID、公证/Staple 与回解压核验；
2. 创建 `v0.4.2-build.1` GitHub Latest，并回下载核对资产字节、签名、版本、
   架构与独立启动；
3. 将同一正式资产加入 Stable appcast，核对线上文件与 Sparkle EdDSA；
4. 如需关闭更新器规格的 `APP-UPDATES-07`，使用正式旧版客户端完成一次
   到 0.4.2 的真实应用内检查、下载、替换与重启；
5. 完整深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 矩阵
   仍由产品所有者按需验收；
6. 新任务从 [SDD 注册表](docs/specs/README.md) 只读取对应的一份当前规格。

## 5. 文档入口

- [长期执行与设计规范](AGENTS.md)
- [SDD 注册表](docs/specs/README.md)
- [SDD 开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（按需读取）
