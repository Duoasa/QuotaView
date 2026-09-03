# QuotaView 项目 Handoff

更新日期：2026-09-03

公开版本、tag、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。
本文件只保存当前迭代、未完成验证和下一步；分支、HEAD 与工作树状态必须
通过 Git 实时读取。

## 1. 当前定位

| 项目 | 当前值 |
|---|---|
| 稳定版 | `0.4.3 Build 1` / `v0.4.3-build.1` / GitHub Latest |
| 回滚基线 | `0.4.2 Build 1` / `v0.4.2-build.1` |
| 公开预览 | `0.3.2 Preview 1`；不属于稳定源码或 Stable appcast |
| 当前候选 | 无；0.4.3 已完成正式发布 |
| 当前主题 | 量子噪点相位、完成态、压缩上下文可见性与粒子不透明度修正；进度条左侧文字采用两级淡灰并增强操作状态流光；完成描边与呼吸光晕统一绿色基准 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一版本内逐次递增；
Sparkle `CFBundleVersion` 跨 Marketing Version 单调递增。

## 2. 当前规格与状态

| Spec | 状态 | 结论 / 未完成项 |
|---|---|---|
| [`QV-RELEASE-0.4.3-001`](docs/design/quotaview-0.4.3-release.md) | `Accepted / Released` | 104 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线 EdDSA 均已完成 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-QUANTUM-NOISE-009`](docs/design/quotaview-quantum-noise-effect-correction.md) | `Accepted / Released` | 保留 `dropField` 持久化兼容；连续换色、增强闪灭、压缩上下文与完成反馈已随 0.4.3 发布 |
| [`QV-RELEASE-0.4.2-001`](docs/design/quotaview-0.4.2-release.md) | `Accepted / Released` | Developer ID、公证/Staple、GitHub Latest、回下载启动和 Stable appcast 在线 EdDSA 均已完成 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008`](docs/design/quotaview-activity-island-lifecycle-continuity-0.4.2.md) | `Accepted / Released` | 投递来源、ACK/队列、turn 感知终态锁与生命周期动画门控已实现；完成态只接受真实 `Stop` |
| [`QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007`](docs/design/quotaview-progress-effects-0.4.2.md) | `Accepted / Released` | 四种真实预览、细密 Drops、清晰 Slosh、状态配色适配和平滑完成反馈已随 0.4.2 发布 |
| [`QV-RELEASE-0.4.1-001`](docs/design/quotaview-0.4.1-release.md) | `Accepted / Released` | Developer ID、公证/Staple、GitHub Latest、回下载启动和 Stable appcast 在线签名核验均已完成 |
| [`QV-RELEASE-0.4.0-001`](docs/design/quotaview-0.4.0-development.md) | `Superseded / Released` | 0.4.0 只保留为大规模开发身份，不创建公开 Release；成果已由 0.4.1 Build 1 正式发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006`](docs/design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Released` | 进度条顶层样式、计划识别、单步骤回退、完成高光分层与结束事件收敛已随 0.4.1 Build 1 发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005`](docs/design/quotaview-codex-activity-island-size-0.4.0.md) | `Accepted / Released` | 100% / 85% / 75% AI 球展开尺寸及进度条固定双语几何已随 0.4.1 Build 1 发布 |
| [`QV-PRODUCT-QUOTA-WINDOWS-003`](docs/design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 多周期额度已随 0.3.7 Build 1 发布并进入 Stable Feed |
| [`QV-PRODUCT-ACTIVITY-ISLAND-004`](docs/design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；不包含多任务 Preview |
| [`QV-PRODUCT-APP-UPDATES-003`](docs/design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.4.3 已进入 Stable Feed；尚缺一次由旧版客户端发起的真实 N → N+1 替换与重启记录 |

### 2.1 0.4.3 Build 1 发布（2026-09-03）

产品所有者已将 2026-08-30 固定的视觉检查点指定为 `0.4.3 Build 1`，
Sparkle 内部序号从 `14` 单调递增为 `15`，并授权合并 `main`、发布 GitHub
Release 与更新 Stable appcast。

范围包括量子噪点连续相位、细密闪灭、完成态粒子覆盖、压缩上下文灰白
可见性、粒子不透明度增强、两级不透明淡灰文字与操作流光，以及统一为
sRGB `#00FF11` 的完成描边和呼吸光晕。完整视觉与辅助功能交叉矩阵仍只由
产品所有者验收，不以自动化测试替代。

PR #40 已合并到 `main`，发布提交为
`b76c317d640e73621b6e2119e4363d0cac6ddff6`。完整 `swift test` 104 项通过、
0 失败；Universal、Developer ID、Apple 公证/Staple、GitHub Latest、远端
资产逐字节回下载、`/Applications` 启动与单一 Widget 注册均已验证。

正式资产 `QuotaView-v0.4.3-build.1.zip` 为 `13,166,345 bytes`，SHA-256
`a2b35249c3c146444207fc82d041121e790d099cc534b597775262e42160d54c`；
公证 Submission 为 `e3f5f0fa-8f36-4ed3-8b26-3b6ef1861344`。Stable appcast
由 `gh-pages` 提交 `56c02c07cebfbeb19a2684ee3dff2bce2f6bbe0c` 发布，
线上 SHA-256 为
`2e5b058592c5b823511391e54a4d873c962d787f54899c1dc1e9da034a9eb40a`，
逐字节与 EdDSA 验证通过。完整视觉与辅助功能交叉矩阵未单独记录为全量
通过。

## 3. 长期边界

- 后续版本必须由产品所有者针对精确版本重新批准，不能沿用 0.4.3 的
  appcast 准入；
- `0.4.3 Build 1` 是当前正式 Release、GitHub Latest 与 Stable appcast
  条目；`0.4.2 Build 1` 是封存回滚基线，0.4.0 不创建公开 Release；
- GitHub push、tag 或 Release 默认不进入自动更新序列；
- 稳定版只保留单任务灵动岛。多任务 Preview 的 tag、Release 和归档分支
  `codex/archive-0.3.2-preview.1-multitask-island` 仅供历史参考；
- 完整视觉、交互与辅助功能结论只能由产品所有者验收后记录。

## 4. 下一步

1. 下一次迭代从 `0.4.3 Build 1` 稳定基线建立新的精确规格，不复用已发布
   候选身份；
2. 如需关闭更新器规格的 `APP-UPDATES-07`，使用正式旧版客户端完成一次
   到 0.4.3 的真实应用内检查、下载、替换与重启；
3. 完整深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 矩阵
   仍由产品所有者按需验收；
4. 新任务从 [SDD 注册表](docs/specs/README.md) 只读取对应的一份当前规格。

## 5. 文档入口

- [长期执行与设计规范](AGENTS.md)
- [SDD 注册表](docs/specs/README.md)
- [SDD 开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（按需读取）
