# 0.4.8 连接与活动链路审计

日期：2026-09-12；规格：`QV-FIX-CODEX-FIRST-CONNECTION-019` FIRST-01～14。
范围为本地发现 → 增量读取/历史恢复 → 任务准入 → 连接状态 → 设置与 Hook 生命周期。
开发身份：0.4.8 Build 4 / internal 26。当前工作见 [Handoff](../../HANDOFF.md)。

## 结论与证据

本轮完成相关链路的代码审计、职责整理及必要修复。保留已有事件解码、任务归属、
Token 计数与真实终态契约，替换重复状态和跨职责的协调代码。没有整套推倒重写，
也没有为了兼容旧测试继续保留失效的展示分支。

| 编号 | 审计发现 | 证据/影响 | 最终处理 |
|---|---|---|---|
| A1 | 只用文件大小判断重置，原子替换可沿用旧解码器 | 未修复代码反例失败：替换文件的 Token 被归到旧 turn，并误弹历史任务 | 同时校验设备/inode、候选 session 和打开的文件身份；变化后重建游标和解码器 |
| A2 | 已启动读取器更换订阅时不发送当前健康状态 | 未修复代码中第二个订阅者的 ready 期望超时 | 每次订阅同步当前状态，保留 generation 防重入 |
| A3 | 历史恢复只携带旧时间，Token 无法选择任务；共享服务已知任务又被重复开始去重挡住 | 两个反例失败：旧任务持续有新 Token，但画面仍停留在另一个已完成任务 | 新确认时间单独作为选择证据；恢复同一 turn 时保留 Token 和计划，不伪造事件时间或新 turn |
| A4 | 连接事实多处镜像，旧文案分支只被旧测试调用 | 代码路径审计：服务已连接但本地缺记录时仍可能显示等待；状态点与标题可能矛盾 | 自动连接快照由 localHealth + sharedState 构成，整体状态与文案统一推导；保留局部读取错误说明 |
| A5 | Runtime 混合 Store、文案、Hook 支持和传输，目录环境构造重复 | 3851 行文件覆盖多种职责，修改边界不清 | Runtime 收敛为 1095 行宿主协调；按职责拆分，统一目录环境构造，恢复门禁独立为纯组件 |
| A6 | 多个 Hook 操作布尔值、未追踪任务和异步分类后的检查缺口 | 代码审计确认在途事件可能在移除后继续进入 Store | 单一操作枚举与操作代次；移除立即使旧 Hook 事件代次失效；分类结束再次校验准入，停止/目录变更也校验代次 |
| A7 | 数据库候选取满 24 项后提前结束，后续内部任务排除信息丢失 | 30 个普通候选 + 后置内部任务反例失败；目录合并把内部记录加回候选 | 候选数量与排除扫描分别限额；在 SQL 的 1024 行上限内继续读取排除信息 |

A1/A2/A3 的原始 Build 3 源码在 `dist/verification/build4/audit-baseline/`。
失败日志分别为 `audit-baseline-tests.log`、`audit-recovery-baseline.log`；
A3 的共享服务变体和 A7 进一步反例保存在 `audit-known-recovery-baseline.log`、
`audit-discovery-baseline.log`。这些日志记录修复前结果，最终结果以完整回归为准。
A4/A5/A6 属于代码路径与职责审计，其中 A6 补充了可暂停分类回调的实际生产路径测试，
不将修复后通过的测试描述为已经在旧版运行过。

## 当前职责边界

| 文件 | 唯一主要职责 |
|---|---|
| `QuotaViewCore/CodexLocalRolloutDiscovery.swift` | 只读数据库与有界目录发现、元数据和内部任务排除 |
| `QuotaViewCore/CodexLocalRolloutActivityClient.swift` | 文件游标、解码、健康状态和订阅生命周期 |
| `QuotaViewCore/CodexLocalActivityRecovery.swift` | session + turn 历史上下文等待、确认和有界逐项淘汰 |
| `QuotaViewCore/CodexActivityTaskIdentity.swift` | 任务身份、来源权限、去重及选择准入 |
| `QuotaView/CodexActivityStore.swift` | 活动状态、Token、终态和显示计时 |
| `QuotaView/CodexActivityConnectionPresentation.swift` | 自动连接状态推导、本地化文案及目录环境构造 |
| `QuotaView/CodexActivityCopy.swift` | 灵动岛业务文案与 Token 格式 |
| `QuotaView/CodexActivityBridges.swift` | 兼容传输、队列和诊断 |
| `QuotaView/CodexActivityHookSupport.swift` | Hook 检查、安装/移除及安全确认支持 |
| `QuotaView/CodexActivityRuntime.swift` | 宿主启动/停止、用户操作、偏好与界面协调 |

后续改动应进入对应职责文件。新连接事实先更新快照，避免另存一个连接布尔值；
历史恢复以同一 session + turn 的新证据为前提；新异步入口明确取消和代次边界。
测试调用生产模型和真实文件读取路径，避免创建仅供测试通过的旧逻辑分支。

## 验证

- 完整 Swift 回归：221 项，219 通过、2 项既有 opt-in 跳过、0 失败。
  首次连接与恢复 24 项，相比 Build 3 新增 9 项，并强化原 Hook 移除测试以覆盖在途事件。
- 覆盖空目录到新任务、历史恢复、重复开始、文件原子替换、订阅替换、目录/文件权限、
  旧数据库、内部任务分页、停止和切目录后的旧分类结果、Hook 移除、共享服务与本地错误并存。
- Universal Release 无签名构建成功；App/Widget 均为 0.4.8 Build 4 / internal 26。
  App、Widget、Core、Hook 均含 arm64 + x86_64，AppIcon.icns / Assets.car 完整。
- 永久 IslandTextConsole 从当前生产源码重新构建，独立归档与解压副本签名校验通过；
  没有更改控制台源码、运行生产 Store 或注册新的 Widget。
- `git diff --check`、源码变更范围与临时注入检查通过。未提交、未推送、未发布。

完整证据：`dist/verification/build4/{swift-tests.log,universal-release.log,console-build.log,artifact-check.json}`。
审计没有更改代理、额度业务、渲染器或正式安装，没有重启当前调试应用。
Build 3 调试副本仍属于上轮运行状态，不能将其画面算作 Build 4 的验收。

## 仍需验收的范围

真实 Intel 全新安装、系统权限交互、长时间持续运行及视觉/交互仍由用户验收。
本轮未重跑既有可选真实 120 秒收起周期和已安装 Codex 的代理测试；普通计时与
Token/终态回归已随完整测试执行。自动化结果不是零缺陷或所有真实环境均兼容的保证。
公开稳定版本、README 和 appcast 继续保持既有发布状态。

## 后续发布状态

上述“未发布/未替换安装”记录为审计结束时状态。随后用户授权并完成 0.4.8 Build 4
正式发布、本机安装及调试残留清理；当前结果以 [版本历史](../../VERSION_HISTORY.md#当前最新版本)
和 [Handoff](../../HANDOFF.md) 为准。实机画面不由发布结果替代验收。
