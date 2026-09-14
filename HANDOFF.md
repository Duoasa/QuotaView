# QuotaView Handoff

更新日期：2026-09-14

当前公开版本：[版本历史](VERSION_HISTORY.md#当前最新版本)。当前规格：[SDD 注册表](docs/specs/README.md)。
更早交接按需查阅[历史快照](docs/archive/handoff-2026-09-12.md)，不从历史“下一步”恢复任务。

## 工作区与版本定位

| 项目 | 当前状态 |
|---|---|
| 公开稳定版 | [0.5.0 Build 3](https://github.com/Duoasa/QuotaView/releases/tag/v0.5.0-build.3)；internal 29，已进入 Stable appcast |
| 发布源码 | `cf92f76cd856bfa7c47dd6d2e25c0312580ddc9a`；PR #53 已合并 main |
| 当前配置身份 | `0.5.0 / display Build 3 / internal 29`；已发布，尚未创建下一开发版本 |
| 开发工作区 | `/Users/sukduoasa/Documents/widget/.worktrees/QuotaView-0.4.8`；目录名不是产品版本 |
| 已确认动效基线 | `0.5.0 Build 2`；正常动效参数保持，原本地归档保留 |
| 回滚入口 | `v0.4.8-build.4` / `09c5a2cc9c1505cdbc7897e9c5e9433f05b00d97`；完整资产记录见版本历史 |

进入后先用 `git worktree list`、`git status --short --branch` 与 `git log -1` 核实实时状态。
正式发布在隔离工作区完成，原开发目录的分支与未提交改动保留；当前文档已同步，
不能将分支名或旧 HEAD 当成当前源码版本。下一可分发迭代使用新的 Build 身份。

## 0.5.0 Build 3 已发布

2026-09-14 用户明确授权 main、GitHub Stable Release 与 appcast。该链路已完成：
共用动效、纯黑底色和 LONG-020 正式发布，中英文 README 的 0.5.0 更新章节直接播放用户提供的[介绍录屏](https://github.com/user-attachments/assets/46482b21-735c-4073-96c3-7d6f10848f90)，顶部保留原产品图。
完整 240 项回归、4 项 AppKit、57 项生产来源核对、Universal、Developer ID、公证 / Staple、
公开回下载与签名 Feed 验证通过；公开包 15 秒启动冒烟通过，Codex 配置指纹不变。
首轮 CI 的代理夹具冷启动超时已作测试范围修复并复验；生产源码和公证资产未变化。

发布证据在 `dist/verification/0.5.0-build3-release/`，完整不可变事实只记录于版本历史。
开发台保留相同生产动效与渲染实现；原 Build 1 / 2 / 3 本地开发包保留，正式 ZIP 单独归档。
下面是开发过程历史；其中“当时未发布 / 未获准”不代表 Build 3 的当前发布状态。

### Build 2 已确认动效与审计历史

[ISLAND-MOTION-021](docs/design/quotaview-island-motion-0.5.0.md)：用户已授权将开发台动效
接入真实任务灵动岛；共用呼出、尺寸过渡和两段隐藏时间线。最终位置保持原位，
保留任务完成、自动缩略与隐藏计时；数据刷新不重启动画，关闭功能立即停止。
App / Widget / 兼容配置统一为 0.5.0 Build 2 / internal 28；未获 appcast 准入。
Build 1 首次接入的完整回归和启动记录保留在 `dist/verification/0.5.0-build1/`。
该次按用户要求把最新共同回弹动效构建进真实应用：Universal 构建、版本/资源/签名检查及 15 秒启动冒烟通过，
stderr 为空、Codex 配置指纹一致；构建当轮未重跑完整回归。旧 Build 1 进程与开发台已退出。
运行路径及校验记录见 `dist/verification/0.5.0-build2/launch-result.json` 与 `artifact-check.json`；
本地归档为 `dist/development/QuotaView-0.5.0-build.2-local.zip`。Build 1 归档、正式安装与 Widget 保留，运行副本不含 Widget。

本轮开发台调优：按用户最新要求，缩略 → 展开复用呼出的 0.82 秒果冻回弹；
展开 → 缩略为 0.28 秒柔和起止、无回弹。用户已同意改为文字、图标、外壳共享末端视觉回弹；
逻辑几何首次到位后固定，通过共同容器 frame / bounds 缩放保持文字排版稳定。
旧内容起步 0.08 秒淡出，呼出 / 展开延迟 0.12 秒后用 0.14 秒淡入，淡入仅辅助内容切换。
前轮 236 项完整回归（2 项跳过、无失败）保留在 `dist/verification/island-text-stability/`；
调优当轮按用户要求仅构建与冒烟，证据使用 `dist/verification/island-shared-rebound/`。
新版开发台启动后关闭旧实例，主要由用户手动检查。
共享源码当时用于 Build 2 开发应用；2026-09-13 用户确认动效满意，冻结正常路径的参数与表现。

随后完成[动效代码审计](docs/design/quotaview-island-motion-0.5.0.md#2026-09-13-动效冻结与代码审计)：
修复呼出中途隐藏时单轴反向长大、回弹悬停区域偏差；正常五条路径的 50,005 个采样与已确认源码完全一致。
完整回归 240 项（239 通过、1 项代理集成未启用、0 失败），包含真实 20 + 100 秒计时；
实际 AppKit 3 项、共用时间线检查及 Universal 构建通过。证据为 `dist/verification/0.5.0-build2-audit/`。
已确认的 61 项构建输入保存在 `approved-baseline/`；审计后源码指纹单独记录。
审计结束时保留原主应用 Build 2 归档和运行实例，两处源码修复当时尚未打入新的主应用包。
2026-09-13 已按用户要求重建并启动独立动效开发台（0.5.0 Build 2 / internal 28），
包含两处审计修复；单实例、签名与 57 项生产来源指纹核验通过，主应用继续保持原运行版本。
启动证据：`dist/verification/console-audit-fixes-launch/launch-result.json`。

### 继承的 LONG-020 修复

[LONG-020 规格](docs/design/quotaview-effect-longevity.md)，已获实现授权。
旧版量子噪声长时间精度退化已通过生产 Metal 函数复现；四种现用特效已修复。
完整回归 226 项，224 通过、2 跳过、0 失败；24 小时运动/噪声、30 天时钟和
四种效果回绕的 GPU 数值检查通过。Universal Release 与永久开发台构建通过。
等待用户检查实际画面和长时间运行；加速验证不等于真实桌面连续运行验收。
上述修复最初验证时沿用 0.4.8 Build 4 / internal 26，现已纳入 0.5.0 开发候选；不替换已安装正式版。
本地验证证据：`dist/verification/long-running-effects/`；自动化及视觉结果按规格跟踪。
用户随后要求启动修复版：已退出安装版主进程，启动不含 Widget 的独立临时副本；
启动检查通过、stderr 为空、Codex 配置指纹一致。正式安装保留，画面仍等待用户验收。
当时的 0.4.8 副本路径与启动记录见该证据目录的 `debug-launch-result.json`；旧主进程现已退出。

## 下一步与验收边界

- 2026-09-13：[灵动岛开发台](Prototypes/IslandTextConsole/README.md) 与生产共用动画源码；
  后续调整仍保留单实例、手动状态与呼出 / 隐藏，并在新版启动成功后关闭旧开发台。
  Build 2 动效已获用户确认；保持正常曲线与参数。当前 Build 3 已纳入审计边界修复和纯黑底色，
  已正式发布，继续跟进实际使用反馈；只做最小规格与交接同步。
- 优先跟进开发最新版 LONG-020 的实际画面和长时间运行反馈；加速 GPU 数值
  检查、构建和启动成功不能替代真实桌面连续运行验收。
- 已发布首次连接流程、小组件实际显示、真实 Intel 首次安装、系统权限、
  深浅色/多屏/VoiceOver/Increase Contrast/Reduce Motion 尚有待验收项；
  范围和既有证据见 [CONNECTION-019](docs/design/quotaview-codex-first-connection-0.4.8.md)
  及[链路审计](docs/design/quotaview-connection-audit-0.4.8.md)。
- 更新器 [APP-UPDATES-07](docs/design/quotaview-app-updates-0.3.5.md) 的真实
  N → N+1 客户端替换与重启仍需记录。
- 上述用户验收不妨碍完成已授权的独立代码或文档工作。Build 3 已获精确版本发布与 appcast 授权并完成；后续新版本仍需对应准入。

## 文档维护状态

2026-09-14 已同步 0.5.0 Build 3 正式发布事实、README 视频、当前规格与版本历史。以下保留前轮维护历史。

2026-09-13 完成当前版本与陈旧入口同步：根 checkout 的 README、Handoff、版本历史
改为指向本工作区，旧正文保留为带日期的归档；当前 SDD、Design QA、开发台说明及
LONG-020 记录同步到 Build 2 与审计后的真实状态。公开稳定版已只读核对 GitHub Latest，
仍为 0.4.8 Build 4；0.3.3 仅作为历史发布 / 原型背景保留。
后续开发构建、审计或用户验收改变事实时，同一任务内更新当前记录，不等到正式发布。
本轮仅文档维护，不改变源码、配置、运行包或发布渠道。

同日较早的 Astra 文档整理：AGENTS 改为任务路由，设计/验证/发布细则
按需读取，历史 Handoff 归档，贡献和 PR 要求按变更范围执行。
该轮仅修改文档和 SDD Skill，不改变开发代码、产品版本、安装副本或发布渠道。
三个自建 Skill 的官方格式校验通过；27 份修改 Markdown 的 162 个本地链接/锚点
及 diff 检查通过。原界面契约、发布门禁、版本历史与开发代码保持完整。
推送范围仅为文档；LONG-020 的未提交实现、测试和本地验证产物仍留在开发工作区。
规格影响：维护既有 `QV-SDD-PROCESS-001` / `QV-SDD-INDEX-001`，不新增产品迭代。

## 文档入口

- [任务约束与读取路由](AGENTS.md)
- [SDD 注册表](docs/specs/README.md) / [工作方式与完成条件](docs/specs/DEVELOPMENT_PROCESS.md)
- [按风险验证](docs/workflow/VALIDATION.md) / [发布与回滚](docs/workflow/RELEASE.md)
- [详细界面规范](docs/design/QUOTAVIEW_UI_RULES.md) / [历史视觉验收](design-qa.md)
