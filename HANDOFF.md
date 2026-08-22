# QuotaView 项目 Handoff

更新日期：2026-08-23

公开版本、tag、Release、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。

本文只维护当前工作区、正在进行的迭代、尚未完成的验证和下一步，不复制
Release Notes 或完整历史。

## 1. 当前版本定位

| 项目 | 当前值 |
|---|---|
| 公开稳定版 | `0.3.5 (Build 5)` / `v0.3.5-build.5` / GitHub Latest |
| 稳定发布提交 | `58e676a8317d907107af3d1731ab11a0ded52684` |
| 稳定资产 | `QuotaView-v0.3.5-build.5.zip`；SHA-256 `d8524ddf5739501bd797cdd082cc8738a7775d8b994fe99033068af8f821b2e1` |
| 稳定回滚基线 | `0.3.3 (Build 3)` / `v0.3.3` / `a93a81af4f90610a57783ceb16a744f07e216c6a` |
| 公开预览版 | `0.3.2 Preview 1` / `v0.3.2-preview.1`；不属于稳定源码或 Stable appcast |
| 当前开发版本 | 产品 `0.3.6 Build 2`；Sparkle 内部更新序号 `CFBundleVersion = 7` |
| 当前主题 | 单任务灵动岛视觉与个性化设置升级 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一 Marketing Version
内每次迭代递增；Sparkle 内部更新序号跨 Marketing Version 单调递增。

## 2. 当前迭代

| 项目 | 当前状态 |
|---|---|
| Spec | `QV-PRODUCT-ACTIVITY-ISLAND-004` |
| 规格 / 交付状态 | `Accepted` / `Verifying` |
| 当前规格 | [0.3.6 灵动岛升级](docs/design/quotaview-codex-activity-island-0.3.6.md) |
| 已完成 | 新动画 Demo 定稿；生产灵动岛动画选项；独立显示开关；两段时间设置；自动化与 Universal Build |
| 已确认方向 | 只升级当前单任务灵动岛；不加入多任务实验 |
| 未完成 | Developer ID 打包、公证/Staple、GitHub Stable Release、回下载验证、appcast 部署与最终发布证据 |

生产分支已经实现：

- 设置页新增独立“显示灵动岛”Switch。关闭只隐藏浮窗，不卸载 Hook、不停止
  Codex 本地连接；重新开启后按当前状态恢复；
- 动画选择采用上方实时预览、下方名称的双选项布局。“粒子球”为既有动画，
  “波澜光晕”为已验收 Demo 动画，切换即时作用于生产灵动岛；
- “波澜光晕”保持半径 `0.535`、轮廓形变 `0`、速度 `1.5×`，适配现有
  九种运行状态；状态切换连续插值并保持速度相位；
- “完成后缩小”为 5...60 秒，“缩小后隐藏”为 5...120 秒，均为 5 秒
  档位；设置页显示刻度与当前值，持久化并即时重排等待任务；
- 保留单一 NSPanel、当前 Hook / Unix Socket / 本地状态链、Reduce Motion
  和失败时回退“粒子球”；没有迁入多任务 Preview。

更新器规格
[QV-PRODUCT-APP-UPDATES-003](docs/design/quotaview-app-updates-0.3.5.md)
并行保持 `Accepted / Verifying`：`0.3.5 Build 5` 已发布更新器和公开 Feed，
但真实应用内 N → N+1 仍需由后续获准、正式签名、公证且内部序号更高的版本
完成。

## 3. 当前工作区

| 项目 | 当前值 |
|---|---|
| 工作区 | `.worktrees/QuotaView-0.3.6-build.1` |
| 分支 | `codex/0.3.6-build.1-island` |
| 基线 | `origin/main` |
| 远程 | `https://github.com/Duoasa/QuotaView.git` |

工作区和分支名保留最初建立 Build 1 时的名称；生产版本身份以配置和本节的
`0.3.6 Build 2 / CFBundleVersion 7` 为准。开发 HEAD 与状态使用 Git
命令实时读取，不写入会在提交后立即失效的固定值。

多任务 Preview 只保留在：

- 分支：`codex/archive-0.3.2-preview.1-multitask-island`
- worktree：`.worktrees/QuotaView-0.3.2-preview.1-backup`
- 提交：`f835bcd46a3d0197e9dc09e0b5a25a6d5d69521c`

## 4. 当前验证

### 0.3.6 Build 2

- App 与 Widget：Marketing Version `0.3.6`、产品 Build `2`、Sparkle
  内部 `CFBundleVersion = 7`；
- `swift test`：66 项通过，0 失败；
- Universal Xcode Release 无签名构建通过；App、Widget 和 Hook 均为
  `x86_64 arm64`；
- App/Widget 包内版本复核均为 `0.3.6 / 7 / 产品 Build 2`；
- `AppIcon.icns`、`Assets.car` 与新
  `CodexActivityRippleGlowShader.txt` 资源存在；
- 本地 ad-hoc 验收包 `dist/QuotaView-v0.3.6-build.2.zip` 已生成并从 ZIP
  全新解压复核；SHA-256
  `2aacc1beab25ba82899f64d0e44de028e7a6239ada6ad3deaebf84b3050da807`；
  `codesign --deep --strict`、版本、资源与 Universal 架构通过；未启用
  Hardened Runtime；
- 源码搜索未发现 Debug Mock、临时 UI QA、自动展开、自动点击或截图入口；
- 视觉和交互结论仍为“等待产品所有者验收”。

### 0.3.6 Build 1 历史开发基线

- `swift test` 64 项通过；Universal ad-hoc Release 通过；
- 历史验证包 `dist/QuotaView-v0.3.6-build.1.zip`，SHA-256
  `d592a011a383ab5a42eaf22c224dee4c8030c3e926a49ef8c314d0c6c640c07a`；
- 该包未签名公证、未发布、未进入 appcast，现已由 Build 2 开发状态替代。

## 5. 发布与自动更新边界

- `0.3.5 Build 5` 已完成 Developer ID、Hardened Runtime、公证/Staple、
  GitHub Stable/Latest、回下载复核和签名 appcast 部署；证据见
  [VERSION_HISTORY.md](VERSION_HISTORY.md#当前最新版本)；
- GitHub 推送、tag 或 Release 默认不进入自动更新序列；
- 只有产品所有者对精确版本、产品 Build、tag 和最终 ZIP 明确批准“纳入自动
  更新序列”后，才同步执行签名、公证、公开 Release 和 appcast 完整门禁；
- 产品所有者已在 2026-08-23 明确批准 `0.3.6 Build 2` 进入完整稳定发布和
  自动更新序列，预期身份为 `v0.3.6-build.2` /
  `QuotaView-v0.3.6-build.2.zip`；发布门禁正在执行，尚未完成的步骤不得
  提前记录为已发布。

## 6. 下一步

1. 完成 Developer ID、Hardened Runtime、公证/Staple 和最终 ZIP 验证；
2. 合并并推送 `main`，创建 `v0.3.6-build.2` Stable/Latest Release，
   回下载验证不可变资产；
3. 生成、签名并部署 Stable appcast，随后回填全部 Release 与 Feed 证据。

## 7. 文档入口

- [长期规范：AGENTS.md](AGENTS.md)
- [SDD 规格注册表](docs/specs/README.md)
- [精简开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（仅在相关任务中读取）

大型历史架构、Widget 和 Preview 方案保留在 `docs/design/`，但不属于默认
会话调用链；仅在任务直接涉及对应模块时按注册表路由读取。
