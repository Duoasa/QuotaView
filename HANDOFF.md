# QuotaView 项目 Handoff

更新日期：2026-08-30

公开版本、tag、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。
本文件只保存当前迭代、未完成验证和下一步；分支、HEAD 与工作树状态必须
通过 Git 实时读取。

## 1. 当前定位

| 项目 | 当前值 |
|---|---|
| 稳定版 | `0.3.7 Build 1` / `v0.3.7-build.1` / GitHub Latest |
| 回滚基线 | `0.3.6 Build 2` / `v0.3.6-build.2` |
| 公开预览 | `0.3.2 Preview 1`；不属于稳定源码或 Stable appcast |
| 当前候选 | `0.4.1 Build 1`；Sparkle 内部序号 `13`；最终视觉验收已通过，正式发布链执行中 |
| 当前主题 | 0.4.1 定版：独立进度条灵动岛、AI 球三档尺寸、状态烟雾与完成辉光；多步骤计划支持 `exec` 包装解析；完成高光拆为稳定绿色描边和呼吸辉光，偶发缺失或迟到结束事件不再让无任务岛体持续显示 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一版本内逐次递增；
Sparkle `CFBundleVersion` 跨 Marketing Version 单调递增。

## 2. 当前规格与状态

| Spec | 状态 | 结论 / 未完成项 |
|---|---|---|
| [`QV-RELEASE-0.4.1-001`](docs/design/quotaview-0.4.1-release.md) | `Accepted / Verifying` | 产品所有者已完成当前生产 App 的最终视觉验收，并明确授权继续 Developer ID、公证、GitHub Latest 与 Stable appcast 发布流程 |
| [`QV-RELEASE-0.4.0-001`](docs/design/quotaview-0.4.0-development.md) | `Superseded / Verifying` | 0.4.0 只保留为大规模开发身份，不创建公开 Release；由 0.4.1 精确发布规格接管 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006`](docs/design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Verifying` | 进度条为独立顶层样式；计划识别、单步骤回退、完成高光分层和结束事件收敛均已实现并通过测试；生产 App 最终视觉验收已通过，等待发布证据 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005`](docs/design/quotaview-codex-activity-island-size-0.4.0.md) | `Accepted / Verifying` | 100% / 85% / 75% 只作用于 AI 球展开态；进度条展开与紧凑态分别按全部简中/英文内容的最大需求固定尺寸；生产 App 最终视觉验收已通过，等待发布证据 |
| [`QV-PRODUCT-QUOTA-WINDOWS-003`](docs/design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 多周期额度已随 0.3.7 Build 1 发布并进入 Stable Feed |
| [`QV-PRODUCT-ACTIVITY-ISLAND-004`](docs/design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；不包含多任务 Preview |
| [`QV-PRODUCT-APP-UPDATES-003`](docs/design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.3.5、0.3.6 与 0.3.7 已进入 Stable Feed；尚缺一次真实 N → N+1 替换与重启记录 |

`0.3.7 Build 1` 的 72 项测试、GitHub CI、Universal、Developer ID、Apple
公证/Staple、GitHub Release/Latest、回下载、两次启动冒烟与公开 EdDSA
appcast 均已完成；不可变证据只在
[版本历史](VERSION_HISTORY.md#037-build-1) 保存。完整视觉与辅助功能交叉
矩阵，以及真实 0.3.6 → 0.3.7 应用内替换和重启，尚未记录为通过。

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
和真实额度消费调用搜索通过。0.4.1
Developer ID 封包、公证、GitHub Release、回下载与 appcast 尚未完成；
产品所有者已确认当前生产 App 没有发现新的视觉问题并授权继续发布；完整
深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 交叉矩阵仍
未单独记录为全量通过。

## 3. 长期边界

- 后续版本必须由产品所有者针对精确版本重新批准，不能沿用 0.3.7 的
  appcast 准入；
- `0.4.1 Build 1` 当前只是候选身份，在签名、公证和远端核验完成前不是
  Release、GitHub Latest 或 Stable appcast 条目；0.4.0 不创建公开 Release；
- GitHub push、tag 或 Release 默认不进入自动更新序列；
- 稳定版只保留单任务灵动岛。多任务 Preview 的 tag、Release 和归档分支
  `codex/archive-0.3.2-preview.1-multitask-island` 仅供历史参考；
- 完整视觉、交互与辅助功能结论只能由产品所有者验收后记录。

## 4. 下一步

1. 从已合并的发布提交执行 0.4.1 Developer ID 封包、公证/Staple、GitHub
   Latest、回下载和 Stable appcast 核验；
2. 发布成功后把实际提交、Submission、资产大小/SHA-256 与 Feed 证据回填
   `VERSION_HISTORY.md`、本文件和 SDD；
3. 如需关闭更新器规格的 `APP-UPDATES-07`，使用正式 0.3.6 客户端完成一次
   到 0.3.7 的真实应用内检查、下载、替换与重启；
4. 完整深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 矩阵
   仍由产品所有者按需验收；
5. 新任务从 [SDD 注册表](docs/specs/README.md) 只读取对应的一份当前规格。

## 5. 文档入口

- [长期执行与设计规范](AGENTS.md)
- [SDD 注册表](docs/specs/README.md)
- [SDD 开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（按需读取）
