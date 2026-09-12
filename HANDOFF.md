# QuotaView 当前 Handoff

更新日期：2026-09-13

公开版本的唯一事实源：**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。
本文件定位开发最新版、未完成验证和下一步。历史过程按需查阅
[2026-09-12 交接快照](docs/archive/handoff-2026-09-12.md)，不要从历史“下一步”恢复任务。

## 工作区与版本定位

| 对象 | 当前定位 |
|---|---|
| 公开稳定版 | `0.4.8 Build 4 / internal 26 / v0.4.8-build.4`；已发布 |
| 稳定版发布源码 | `09c5a2cc9c1505cdbc7897e9c5e9433f05b00d97`；资产、签名、公证见版本历史 |
| 开发最新版 | `LONG-020` 特效长时间稳定性修复；包含稳定版之后的本地工作，未发布 |
| 开发工作区 | `/Users/sukduoasa/Documents/widget/.worktrees/QuotaView-0.4.8` |
| 当前配置身份 | 暂为 `0.4.8 / display Build 4 / internal 26`；不表示源码等同已发布包 |
| 稳定回滚入口 | `v0.4.7-build.3`；完整证据见版本历史 |

进入工作区后用 `git status --short --branch` 与 `git log -1` 核实实时状态；
不按目录名、版本号或旧 Handoff 中的开发 HEAD 判断哪份源码最新。
根 checkout 保留旧实验，不是当前开发入口。继续开发时保留未提交工作，
不从稳定 tag 覆盖开发版；形成下一可分发候选前按[发布规则](docs/workflow/RELEASE.md)
确定新产品 Build、内部更新序号和唯一资产身份。

## 开发最新版：特效长时间稳定性修复（未发布）

[LONG-020 规格](docs/design/quotaview-effect-longevity.md)，已获实现授权。
旧版量子噪声长时间精度退化已通过生产 Metal 函数复现；四种现用特效已修复。
完整回归 226 项，224 通过、2 跳过、0 失败；24 小时运动/噪声、30 天时钟和
四种效果回绕的 GPU 数值检查通过。Universal Release 与永久开发台构建通过。
等待用户检查实际画面和长时间运行；加速验证不等于真实桌面连续运行验收。
版本身份暂沿用 0.4.8 Build 4 / internal 26，未形成新发布；不替换已安装正式版。
本地验证证据：`dist/verification/long-running-effects/`；自动化及视觉结果按规格跟踪。
用户随后要求启动修复版：已退出安装版主进程，启动不含 Widget 的独立临时副本；
启动检查通过、stderr 为空、Codex 配置指纹一致。正式安装保留，画面仍等待用户验收。
当前副本路径与启动记录见该证据目录的 `debug-launch-result.json`，后续清理需按此定位。

## 下一步与验收边界

- 优先跟进开发最新版 LONG-020 的实际画面和长时间运行反馈；加速 GPU 数值
  检查、构建和启动成功不能替代真实桌面连续运行验收。
- 已发布首次连接流程、小组件实际显示、真实 Intel 首次安装、系统权限、
  深浅色/多屏/VoiceOver/Increase Contrast/Reduce Motion 尚有待验收项；
  范围和既有证据见 [CONNECTION-019](docs/design/quotaview-codex-first-connection-0.4.8.md)
  及[链路审计](docs/design/quotaview-connection-audit-0.4.8.md)。
- 更新器 [APP-UPDATES-07](docs/design/quotaview-app-updates-0.3.5.md) 的真实
  N → N+1 客户端替换与重启仍需记录。
- 上述用户验收不妨碍完成已授权的独立代码或文档工作。发布及 appcast 准入
  需绑定将要发布的精确版本，不能沿用稳定版 Build 4 的历史授权。

## 文档维护状态

2026-09-13 按 Astra 文章整理 SDD：AGENTS 改为任务路由，设计/验证/发布细则
按需读取，历史 Handoff 归档，贡献和 PR 要求按变更范围执行。
本次仅修改文档和 SDD Skill，不改变开发代码、产品版本、安装副本或发布渠道。
三个自建 Skill 的官方格式校验通过；27 份修改 Markdown 的 162 个本地链接/锚点
及 diff 检查通过。原界面契约、发布门禁、版本历史与开发代码保持完整。
推送范围仅为文档；LONG-020 的未提交实现、测试和本地验证产物仍留在开发工作区。
规格影响：维护既有 `QV-SDD-PROCESS-001` / `QV-SDD-INDEX-001`，不新增产品迭代。

## 文档入口

- [任务约束与读取路由](AGENTS.md)
- [SDD 注册表](docs/specs/README.md) / [工作方式与完成条件](docs/specs/DEVELOPMENT_PROCESS.md)
- [按风险验证](docs/workflow/VALIDATION.md) / [发布与回滚](docs/workflow/RELEASE.md)
- [详细界面规范](docs/design/QUOTAVIEW_UI_RULES.md) / [历史视觉验收](design-qa.md)
