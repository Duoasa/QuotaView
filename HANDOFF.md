# QuotaView 项目 Handoff

更新日期：2026-08-26

公开版本、tag、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。
本文件只保存当前迭代、未完成验证和下一步；分支、HEAD 与工作树状态必须
通过 Git 实时读取。

## 1. 当前定位

| 项目 | 当前值 |
|---|---|
| 稳定版 | `0.3.6 Build 2` / `v0.3.6-build.2` / GitHub Latest |
| 回滚基线 | `0.3.5 Build 5` / `v0.3.5-build.5` |
| 公开预览 | `0.3.2 Preview 1`；不属于稳定源码或 Stable appcast |
| 当前开发 | `0.3.7 Build 1`；Sparkle 内部序号 `11`；已获本精确版本 appcast 准入，发布链执行中 |
| 当前主题 | 多周期额度展示与灵动岛多屏定位选项 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一版本内逐次递增；
Sparkle `CFBundleVersion` 跨 Marketing Version 单调递增。

## 2. 当前规格与状态

| Spec | 状态 | 结论 / 未完成项 |
|---|---|---|
| [`QV-PRODUCT-QUOTA-WINDOWS-003`](docs/design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Verifying` | `codex.primary` 与 `secondary` 已独立建模并按时长显示；纳入 0.3.7 Build 1 发布候选 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-004`](docs/design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Verifying` | 0.3.7 Build 1 新增“锁定到 Codex 屏幕”开关；不包含多任务 Preview |
| [`QV-PRODUCT-APP-UPDATES-003`](docs/design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.3.5 与 0.3.6 已进入 Stable Feed；尚缺一次真实 0.3.5 → 0.3.6 检查、下载、替换与重启记录 |

`0.3.6 Build 2` 的自动化、Universal、Developer ID、公证/Staple、GitHub
Release/Latest、回下载与 EdDSA appcast 均已完成，完整证据只在
[版本历史](VERSION_HISTORY.md#036-build-2) 保存。完整视觉与辅助功能交叉
矩阵未被记录为全量通过。

`0.3.6 Build 3/4/5` 的开发内容已晋升为 `0.3.7 Build 1` 发布候选，不再
作为独立候选；Codex 主/次窗口按实际时长从短到长显示，Spark 保持独立。本版进一步
新增灵动岛屏幕定位：默认跟随热区，也可锁定最大可见 Codex 窗口所在屏幕，
不可定位时回退热区。72 项测试与 Universal 无签名 Release 构建已通过，
App、Widget 和 Activity Hook 均为 `x86_64 + arm64`；视觉与多屏交互等待
产品所有者验收。产品所有者已于 2026-08-26 明确批准精确版本
`0.3.7 Build 1`（内部序号 `11`、tag `v0.3.7-build.1`、资产
`QuotaView-v0.3.7-build.1.zip`）进入 Stable appcast；发布事实须在链路完成
后写入版本历史。

## 3. 长期边界

- 后续版本必须由产品所有者针对精确版本重新批准，不能沿用 0.3.7 的
  appcast 准入；
- GitHub push、tag 或 Release 默认不进入自动更新序列；
- 稳定版只保留单任务灵动岛。多任务 Preview 的 tag、Release 和归档分支
  `codex/archive-0.3.2-preview.1-multitask-island` 仅供历史参考；
- 完整视觉、交互与辅助功能结论只能由产品所有者验收后记录。

## 4. 下一步

1. 完成 0.3.7 Build 1 的测试、Universal 构建、Developer ID 签名、Apple
   公证/Staple、GitHub Latest、回下载与 EdDSA appcast 发布；
2. 发布完成后把实际 tag 提交、资产大小/SHA-256、公证与 Feed 证据同步到
   `VERSION_HISTORY.md`，再把本文件收口为已发布状态；
3. 如需关闭更新器规格的 `APP-UPDATES-07`，使用正式 0.3.5 客户端完成一次
   到 0.3.6 的真实应用内更新；
4. 新任务从 [SDD 注册表](docs/specs/README.md) 只读取对应的一份当前规格。

## 5. 文档入口

- [长期执行与设计规范](AGENTS.md)
- [SDD 注册表](docs/specs/README.md)
- [SDD 开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（按需读取）
