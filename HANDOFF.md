# QuotaView 项目 Handoff

更新日期：2026-08-30

公开版本、tag、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。
本文件只保存当前迭代、未完成验证和下一步；分支、HEAD 与工作树状态必须
通过 Git 实时读取。

## 1. 当前定位

| 项目 | 当前值 |
|---|---|
| 稳定版 | `0.4.2 Build 1` / `v0.4.2-build.1` / GitHub Latest |
| 回滚基线 | `0.4.1 Build 1` / `v0.4.1-build.1` |
| 公开预览 | `0.3.2 Preview 1`；不属于稳定源码或 Stable appcast |
| 当前候选 | 未指定发布版本的本地冻结检查点：量子噪点与完成态绿色辉光修正；尚未封包或发布 |
| 当前主题 | 量子噪点相位、完成态、压缩上下文可见性与粒子不透明度修正；进度条左侧文字采用两级淡灰并增强操作状态流光；完成描边与呼吸光晕统一绿色基准 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一版本内逐次递增；
Sparkle `CFBundleVersion` 跨 Marketing Version 单调递增。

## 2. 当前规格与状态

| Spec | 状态 | 结论 / 未完成项 |
|---|---|---|
| [`QV-PRODUCT-ACTIVITY-ISLAND-QUANTUM-NOISE-009`](docs/design/quotaview-quantum-noise-effect-correction.md) | `Accepted / Verifying` | 保留 `dropField` 持久化兼容；独立连续相位、增强闪灭及完成态中密度粒子覆盖已通过 104 项测试和 Universal 构建，等待产品所有者视觉验收 |
| [`QV-RELEASE-0.4.2-001`](docs/design/quotaview-0.4.2-release.md) | `Accepted / Released` | Developer ID、公证/Staple、GitHub Latest、回下载启动和 Stable appcast 在线 EdDSA 均已完成 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008`](docs/design/quotaview-activity-island-lifecycle-continuity-0.4.2.md) | `Accepted / Released` | 投递来源、ACK/队列、turn 感知终态锁与生命周期动画门控已实现；完成态只接受真实 `Stop` |
| [`QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007`](docs/design/quotaview-progress-effects-0.4.2.md) | `Accepted / Released` | 四种真实预览、细密 Drops、清晰 Slosh、状态配色适配和平滑完成反馈已随 0.4.2 发布 |
| [`QV-RELEASE-0.4.1-001`](docs/design/quotaview-0.4.1-release.md) | `Accepted / Released` | Developer ID、公证/Staple、GitHub Latest、回下载启动和 Stable appcast 在线签名核验均已完成 |
| [`QV-RELEASE-0.4.0-001`](docs/design/quotaview-0.4.0-development.md) | `Superseded / Released` | 0.4.0 只保留为大规模开发身份，不创建公开 Release；成果已由 0.4.1 Build 1 正式发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006`](docs/design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Released` | 进度条顶层样式、计划识别、单步骤回退、完成高光分层与结束事件收敛已随 0.4.1 Build 1 发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005`](docs/design/quotaview-codex-activity-island-size-0.4.0.md) | `Accepted / Released` | 100% / 85% / 75% AI 球展开尺寸及进度条固定双语几何已随 0.4.1 Build 1 发布 |
| [`QV-PRODUCT-QUOTA-WINDOWS-003`](docs/design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 多周期额度已随 0.3.7 Build 1 发布并进入 Stable Feed |
| [`QV-PRODUCT-ACTIVITY-ISLAND-004`](docs/design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；不包含多任务 Preview |
| [`QV-PRODUCT-APP-UPDATES-003`](docs/design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.3.5、0.3.6、0.3.7、0.4.1 与 0.4.2 均已进入 Stable Feed；尚缺一次真实 N → N+1 替换与重启记录 |

### 2.1 本地冻结检查点（2026-08-30）

产品所有者已要求停止本日开发并固定当前版本。检查点位于分支
`codex/0.4.2-product-images`，由本地提交
`chore: freeze post-0.4.2 island refinements` 固定；正式发布身份仍是
`0.4.2 Build 1`，源码配置保持 Marketing `0.4.2`、Sparkle 内部序号 `14`，
不得把该本地提交解释为新的 Release、Build 或 Stable appcast 条目。

冻结范围包括量子噪点更名与连续相位、细密闪灭、完成态中密度高亮、压缩
上下文专属灰白可见性、粒子不透明度提高 `10%`、进度条左侧两级不透明淡灰
与增强流光，以及完成描边和背后光晕统一 sRGB `#00FF11` / `100%` 亮度
基准、呼吸只改变光晕半径。主体改造曾通过完整 `swift test` 104 项；最终
视觉微调按产品所有者要求只运行对应定向冒烟测试，均为 1 项通过、0 失败，
最终 Universal Release 无签名构建通过且为 `x86_64 arm64`，本地候选已启动。
最终微调后未重跑完整测试；颜色、完成辉光和完整辅助功能矩阵不得记录为
视觉已通过。

本检查点未封包、签名、公证、推送、创建 tag、修改 Release 或更新 appcast。

`0.4.1 Build 1` 的 93 项测试、PR #34 GitHub CI、Universal、Developer ID、
Apple 公证/Staple、GitHub Release/Latest、回下载、启动冒烟与公开 EdDSA
appcast 均已完成；不可变证据只在
[版本历史](VERSION_HISTORY.md#041-build-1) 保存。完整视觉与辅助功能交叉
矩阵，以及真实 N → N+1 应用内替换和重启，尚未记录为通过。

`0.4.2 Build 1` 已通过 PR #36 合并为发布提交
`6c8434950d59afd9439b2f6f50d8c8b091a40f6d`。四种进度效果、真实设置预览、
九种状态配色适配、减速后的计划进度前沿和三个新增效果的克制完成高亮均已
进入稳定版。生命周期改造以 Hook `Stop` 作为唯一完成真相，`SessionEnd`
只隐藏；局部工具步骤、事件沉默和 App Server 状态不再制造完成或隐藏。

发布门禁为 103 项测试、GitHub CI、Universal、Developer ID、Apple 公证与
Staple、GitHub Latest、回下载逐字节与独立启动、Stable appcast 在线 EdDSA
全部通过。正式资产 `QuotaView-v0.4.2-build.1.zip` 为
`13,166,133 bytes`，SHA-256
`a87f7f03da644fb014a8c90b617b99697bbb6aae72a7c35928d3386bbf2c05a3`；
公证 Submission 为 `5cad0ca0-7f2e-49ef-beda-34b151ed2f45`。Stable appcast
由 `gh-pages` 提交 `ead810f540261fbd3e67d17f0f0d32401606b0c0`
发布，线上 SHA-256 为
`a8ddb8809340caed56dbf0743ab71f51bb2bae6a1a8a067676853cfd76185e8b`。
产品所有者已批准发布；完整深浅色、多屏、VoiceOver、Increase Contrast 与
Reduce Motion 交叉矩阵未单独记录为全量通过。

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

- 后续版本必须由产品所有者针对精确版本重新批准，不能沿用 0.4.2 的
  appcast 准入；
- `0.4.2 Build 1` 是当前正式 Release、GitHub Latest 与 Stable appcast
  条目；`0.4.1 Build 1` 是封存回滚基线，0.4.0 不创建公开 Release；
- GitHub push、tag 或 Release 默认不进入自动更新序列；
- 稳定版只保留单任务灵动岛。多任务 Preview 的 tag、Release 和归档分支
  `codex/archive-0.3.2-preview.1-multitask-island` 仅供历史参考；
- 完整视觉、交互与辅助功能结论只能由产品所有者验收后记录。

## 4. 下一步

1. 下一次会话先读取本地冻结检查点，确认视觉结果并由产品所有者决定目标
   Marketing Version / Build；不得默认把它发布为另一个 `0.4.2 Build 1`；
2. 未获明确发布授权前，不封包、不推送、不创建 tag、不修改 Release 或
   appcast；
3. 如需关闭更新器规格的 `APP-UPDATES-07`，使用正式旧版客户端完成一次
   到 0.4.2 的真实应用内检查、下载、替换与重启；
4. 完整深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 矩阵
   仍由产品所有者按需验收；
5. 新任务从 [SDD 注册表](docs/specs/README.md) 只读取对应的一份当前规格。

## 5. 文档入口

- [长期执行与设计规范](AGENTS.md)
- [SDD 注册表](docs/specs/README.md)
- [SDD 开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（按需读取）
