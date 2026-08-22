# QuotaView 项目 Handoff

更新日期：2026-08-23

公开版本、tag、Release、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。

本文只维护当前工作区、正在进行的迭代、尚未完成的验证和下一步，不复制
Release Notes 或完整历史。

## 1. 当前版本定位

| 项目 | 当前值 |
|---|---|
| 公开稳定版 | `0.3.6 (Build 2)` / `v0.3.6-build.2` / GitHub Latest |
| 稳定发布提交 | `ab033001a194b78e2ec80f31e1f334ea1cae0021` |
| 稳定资产 | `QuotaView-v0.3.6-build.2.zip`；SHA-256 `b90e05ee724f8adf7856be469476f8b2224304a981c8869e4200aee4ce525bae` |
| 稳定回滚基线 | `0.3.5 (Build 5)` / `v0.3.5-build.5` / `58e676a8317d907107af3d1731ab11a0ded52684` |
| 公开预览版 | `0.3.2 Preview 1` / `v0.3.2-preview.1`；不属于稳定源码或 Stable appcast |
| 当前开发版本 | 尚未定义；生产配置保持产品 `0.3.6 Build 2` / Sparkle 内部序号 `7` |
| 当前主题 | 0.3.6 Build 2 已发布，等待下一阶段产品指令 |

产品可见 Build 在 Marketing Version 变化后归 `1`，同一 Marketing Version
内每次迭代递增；Sparkle 内部更新序号跨 Marketing Version 单调递增。

## 2. 当前迭代

| 项目 | 当前状态 |
|---|---|
| Spec | `QV-PRODUCT-ACTIVITY-ISLAND-004` |
| 规格 / 交付状态 | `Accepted` / `Released` |
| 当前规格 | [0.3.6 灵动岛升级](docs/design/quotaview-codex-activity-island-0.3.6.md) |
| 已完成 | 新动画 Demo 定稿；生产灵动岛动画选项；独立显示开关；两段时间设置；测试与 Universal Build；Developer ID、公证、Release 与 appcast |
| 已确认方向 | 只升级当前单任务灵动岛；不加入多任务实验 |
| 未完成 | 完整视觉/辅助功能交叉矩阵，以及真实 0.3.5 → 0.3.6 应用内安装操作的独立验收记录 |

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
并行保持 `Accepted / Verifying`：`0.3.5 Build 5` 已发布更新器，`0.3.6
Build 2` 已作为内部序号更高的第二个正式版本进入公开 Feed；线上版本判断、
资产和签名链已验证，但真实应用内下载、替换与重启尚未形成独立操作记录。

## 3. 当前工作区

| 项目 | 当前值 |
|---|---|
| 工作区 | `.worktrees/QuotaView-0.3.6-build.1` |
| 分支 | `main`（发布证据通过短期文档 PR 回填） |
| 基线 | `origin/main` |
| 远程 | `https://github.com/Duoasa/QuotaView.git` |

工作树目录名保留最初建立 Build 1 时的名称；当前代码已合并到 `main`，
生产版本身份以配置和本节的 `0.3.6 Build 2 / CFBundleVersion 7` 为准。
开发 HEAD 与状态使用 Git 命令实时读取，不写入会在提交后立即失效的固定值。

多任务 Preview 只保留在：

- 分支：`codex/archive-0.3.2-preview.1-multitask-island`
- worktree：`.worktrees/QuotaView-0.3.2-preview.1-backup`
- 提交：`f835bcd46a3d0197e9dc09e0b5a25a6d5d69521c`

## 4. 当前验证

### 0.3.6 Build 2 正式发布

- App 与 Widget：Marketing Version `0.3.6`、产品 Build `2`、Sparkle
  内部 `CFBundleVersion = 7`；
- `swift test`：66 项通过，0 失败；
- Universal Xcode Release 正式构建通过；App、Widget 和 Hook 均为
  `x86_64 arm64`；
- App/Widget 包内版本复核均为 `0.3.6 / 7 / 产品 Build 2`；
- `AppIcon.icns`、`Assets.car` 与新
  `CodexActivityRippleGlowShader.txt` 资源存在；
- 正式资产 `QuotaView-v0.3.6-build.2.zip` 大小 `12,861,638 bytes`，
  SHA-256
  `b90e05ee724f8adf7856be469476f8b2224304a981c8869e4200aee4ce525bae`；
- 使用 Developer ID 证书 SHA-1
  `E52D0A9C7C377AF77C484155CC0CFCFB27D949D3` 与 Hardened Runtime；Apple
  notarization `Accepted` 并 Staple，Submission
  `ff3fef0b-d92f-47cd-8798-3cb388aa2d9e`；
- GitHub 回下载资产与本地正式 ZIP 逐字节一致；全新解压后通过严格深度
  签名、Gatekeeper、Staple、版本、资源与 Universal 架构复核；
- Stable appcast 已部署到 `https://duoasa.github.io/QuotaView/appcast.xml`；
  `gh-pages` 提交 `421486caac313e04795e429ac36ab14df9d918fd`，Feed
  SHA-256 `06a9007a3814192deb6469490dadb2b0ca540b3ea6c836a7a623c0107c94a211`；
  线上文件逐字节一致且 EdDSA 验证通过；
- 源码搜索未发现 Debug Mock、临时 UI QA、自动展开、自动点击或截图入口；
- 版本已正式发布；未单独完成的完整视觉/辅助功能矩阵不记录为“已通过”。

### 0.3.6 Build 1 历史开发基线

- `swift test` 64 项通过；Universal ad-hoc Release 通过；
- 历史验证包 `dist/QuotaView-v0.3.6-build.1.zip`，SHA-256
  `d592a011a383ab5a42eaf22c224dee4c8030c3e926a49ef8c314d0c6c640c07a`；
- 该包未签名公证、未发布、未进入 appcast，现已由 Build 2 开发状态替代。

## 5. 发布与自动更新边界

- `0.3.6 Build 2` 已完成 Developer ID、Hardened Runtime、公证/Staple、
  GitHub Stable/Latest、回下载复核和签名 appcast 部署；证据见
  [VERSION_HISTORY.md](VERSION_HISTORY.md#当前最新版本)；
- GitHub 推送、tag 或 Release 默认不进入自动更新序列；
- 只有产品所有者对精确版本、产品 Build、tag 和最终 ZIP 明确批准“纳入自动
  更新序列”后，才同步执行签名、公证、公开 Release 和 appcast 完整门禁；
- 产品所有者已在 2026-08-23 明确批准 `0.3.6 Build 2` 进入完整稳定发布和
  自动更新序列；`v0.3.6-build.2` /
  `QuotaView-v0.3.6-build.2.zip` 的全部发布门禁已完成；
- 后续版本仍需产品所有者针对精确版本重新授权，不因本次发布自动进入
  appcast。

## 6. 下一步

1. 等待产品所有者定义下一 Marketing Version 与产品 Build；版本变化后
   产品 Build 归 1，Sparkle 内部序号继续从 7 单调递增；
2. 如需关闭更新器规格的 `APP-UPDATES-07`，从正式 0.3.5 Build 5 客户端
   实际执行一次 0.3.6 Build 2 的检查、下载、替换与重启验收；
3. 完整视觉与辅助功能矩阵仅在产品所有者明确执行并给出结论后记录。

## 7. 文档入口

- [长期规范：AGENTS.md](AGENTS.md)
- [SDD 规格注册表](docs/specs/README.md)
- [精简开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（仅在相关任务中读取）

大型历史架构、Widget 和 Preview 方案保留在 `docs/design/`，但不属于默认
会话调用链；仅在任务直接涉及对应模块时按注册表路由读取。
