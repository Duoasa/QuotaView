# QuotaView 项目 Handoff

更新日期：2026-08-29

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
| 当前开发 | `0.4.0 Build 1`；Sparkle 内部序号 `12`；`Discovery` |
| 当前主题 | 大版本升级；版本身份已建立，产品范围与阶段目标待产品所有者定义 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一版本内逐次递增；
Sparkle `CFBundleVersion` 跨 Marketing Version 单调递增。

## 2. 当前规格与状态

| Spec | 状态 | 结论 / 未完成项 |
|---|---|---|
| [`QV-RELEASE-0.4.0-001`](docs/design/quotaview-0.4.0-development.md) | `Draft / Discovery` | 产品所有者已授权使用 `0.4.0 Build 1`；尚未定义或授权具体大功能 |
| [`QV-PRODUCT-QUOTA-WINDOWS-003`](docs/design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 多周期额度已随 0.3.7 Build 1 发布并进入 Stable Feed |
| [`QV-PRODUCT-ACTIVITY-ISLAND-004`](docs/design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；不包含多任务 Preview |
| [`QV-PRODUCT-APP-UPDATES-003`](docs/design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.3.5、0.3.6 与 0.3.7 已进入 Stable Feed；尚缺一次真实 N → N+1 替换与重启记录 |

`0.3.7 Build 1` 的 72 项测试、GitHub CI、Universal、Developer ID、Apple
公证/Staple、GitHub Release/Latest、回下载、两次启动冒烟与公开 EdDSA
appcast 均已完成；不可变证据只在
[版本历史](VERSION_HISTORY.md#037-build-1) 保存。完整视觉与辅助功能交叉
矩阵，以及真实 0.3.6 → 0.3.7 应用内替换和重启，尚未记录为通过。

`0.4.0 Build 1` 开发身份已完成首轮自动化核对：App 与 Widget 的 Xcode
Release Build Settings 均解析为 Marketing `0.4.0`、内部序号 `12`、产品
Build `1`；`swift test` 72 项通过、0 失败；App 与 Widget Info.plist 语法、
`git diff --check`、临时 Debug 标记和真实额度消费调用搜索均通过。本轮尚未
实现 0.4.0 具体功能，也未生成 Universal Release 产物或进行视觉验收。

## 3. 长期边界

- 后续版本必须由产品所有者针对精确版本重新批准，不能沿用 0.3.7 的
  appcast 准入；
- `0.4.0 Build 1` 当前只是开发身份，不是 tag、Release、GitHub Latest 或
  Stable appcast 条目；
- GitHub push、tag 或 Release 默认不进入自动更新序列；
- 稳定版只保留单任务灵动岛。多任务 Preview 的 tag、Release 和归档分支
  `codex/archive-0.3.2-preview.1-multitask-island` 仅供历史参考；
- 完整视觉、交互与辅助功能结论只能由产品所有者验收后记录。

## 4. 下一步

1. 由产品所有者定义 `0.4.0` 的主要用户结果、功能范围、非目标和必须保持的
   0.3.7 行为；在规格进入 `Accepted` 并获得实现授权前，不开始具体大功能；
2. 将确认后的 0.4.0 范围拆成可独立验证、可回滚的阶段，并为每一阶段登记
   Requirement、降级语义和验收条件；
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
