# QuotaView 开发交接

公开稳定版及回滚入口见[版本历史](VERSION_HISTORY.md#当前最新版本)。本页记录 macOS 开发分支、已启动的运行包和本机待验收项。

## 工作区与版本定位

| 对象 | 当前状态 |
|---|---|
| 工作区 | `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget` |
| 重构分支 | `codex/macos-architecture`，Build 33/34 源码基线 `e49e139` |
| 开发版 | 0.9.9 Build 3（内部 283），`com.quotaview.development073` |
| 运行包 | `.build/DevelopmentRuntime/QuotaView.app`，本地未提交工作树构建，签名、版本、构建输入与实际加载路径见 `.build/macos-architecture/cc-child-roles/runtime-result.json` |
| Widget 试点保存点 | 本地分支 `spike/swift6-build35`，提交 `f841624`。Build 41 已恢复兼容夹具、验证 Swift 6 包模块及 App/Widget 的原生编译归属 |
| 工作进度 | Claude Code 并行子行角色名已修复并通过隔离验证，开发包已更新，用户已在本机 CC 并行验收中确认子行显示成功 |

## macOS 0.9.9 Build 2 / 正式发布

正式版 Build 2（内部 284）包含 Antigravity 直接父子归组与 Claude Code 角色名修复。GitHub 与 Sparkle 均已发布。已用正式 Build 1 的 Sparkle 确认可以查询到 Build 2。上一稳定版为 `v0.9.9-build.1` / `b0afb04`。[发布证据及回滚入口](VERSION_HISTORY.md#当前最新版本)

## 0.9.9 Build 3 / Claude Code 并行子 Agent 名称

隔离回归在修复前复现名称丢失。修复后 4 项定向测试通过，涵盖三个并行子行的省略与空白角色字段、单个角色显式更新、各子任务结束及父轮次持续运行。开发签名、App 与 Widget 版本及主进程加载路径已核验，仅开发版运行。测试与部署证据位于 `.build/macos-architecture/cc-child-roles/`。

使用 Claude Code 2.1.292 和本地模拟模型实际派生 Explore、Plan 与 general-purpose。验收脚本在转发子任务读取文件的工具事件时省略角色字段，三条子行并行显示期间用户确认成功。

## 0.9.9 Build 2 / Antigravity 直接父子识别

隔离测试 4 项通过。双父任务并行时，父关系迟到的子任务从独立卡迁到正确父卡，保留开始时间与活动状态，旧审批失效。子任务的计划已达 95%，结束后父任务的计划、最终回答、21 个 Token 与速率均独立，全局统计含子任务共 121 个 Token。旧版摘要库、系统消息头和多客户端歧义均有夹具覆盖。Xcode Debug 增量构建、开发签名及实际加载路径已核验。测试与部署记录位于 `.build/macos-architecture/anti-children/`。实际客户端交互待验收。

11 月 28 日并行验收期间，桌面摘要库中 3 个 `research` 会话具有同一个直接父 UUID。使用真实关系和模拟 Hook 事件在开发源码回放，1 张父卡显示 3 个子行，逐一结束后子行递减到 0，父卡持续运行。记录在 `.build/macos-architecture/anti-children/parallel-real-source-replay.log`。当时已安装 Build 1 与开发 Build 2 均有启用的 Anti Hook，两个在屏灵动岛窗口的位置和大小完全相同。随后按用户授权正常退出正式版，已确认在屏灵动岛只剩开发版进程 87886，开发通道 Hook 已启用，监听套接字存在。用户随后反馈单开开发版验收通过。

## 0.9.9 Build 1 / 正式发布

macOS 0.9.9 Build 1（内部 281）已发布到 [GitHub](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.9-build.1) 与 [Sparkle](https://duoasa.github.io/QuotaView/appcast.xml)。回滚基线为 `v0.9.7-build.1` / `8109feb`。发布验证在独立检出中完成。[版本历史与验证证据](VERSION_HISTORY.md#当前最新版本)

## 0.9.9 Build 1 / 更新与公告

四组十条公告已按用户定稿写入，覆盖六种界面语言。3 项公告提醒测试与本地化检查通过，已逐条核对简体中文标题、正文和分组顺序。Xcode Debug 开发包已启动，已核验进程加载路径、包内文案与翻译资源，以及 App 和 Widget 的 0.9.9 Build 1（内部 281）身份。用户可在「设置 → 关于 → 更新与公告 → 查看」验收。证据目录为 `.build/macos-architecture/announcement-099/`。

## Build 42–43 / 进行中步骤与计划进度

Build 42（内部 279）的隔离用例验证了 Antigravity 追加 `update_focus` 后，无需新的 Hook 即可在卡片和详情读取标题，完成后仍显示本轮最终回答。Build 43 同步 `update_steps` 状态和 Claude Code 的成功计划回执。复用原有进度效果与无计划估算，运行中计划上限 95%，真实成功结束后 100%。

Build 43 的 8 项 Swift 定向冒烟全部通过。Claude Code 2.1.292 的现代和旧版任务工具在隔离目录通过本地模拟模型实际执行。Xcode Debug 开发签名构建成功，已重新启动并核对本机运行包。证据在 `.build/macos-architecture/antigravity-focus/` 和 `.build/macos-architecture/agent-plans/`。实际客户端视觉与交互待用户验收。

## Build 41 / Swift 6 编译归属与旧快照兼容

独立 SwiftPM 构建覆盖四个 Swift 6 模块，原生 Xcode Debug 的 Core 使用 Swift 6，App、Widget 与 Hook 直接编入的共享源码继续使用 Swift 5。旧 Widget 快照经生产文件存储器读写逐字节一致。隔离全量 XCTest 发现 895 项，884 项通过、11 项按条件跳过，失败 0 项；另外 44 项问答契约通过。详见[编译矩阵与并发审计](docs/specs/macos-architecture.md#build-41-编译边界与快照)。待用户验收真实客户端、桌面窗口和视觉效果。

## Build 40 / 活动状态职责与浮层观察

107 项 Swift 定向测试通过。相同的 12 次跨分钟事件中，折叠、展开岛的 body 各从 12 次降到 0 次，额度浮层内容仍更新 12 次；真实任务和用量变化仍更新对应视图。六场景数据、各 Store 保留理由及调度审查见 macOS 架构规格。

## Build 39 / Devin、Antigravity 与通用 Hook 分离

36 项 Swift 定向测试中 34 项通过、2 项按条件跳过（本机登录窗口、外部历史样本），44 项问答契约通过。独立测试覆盖 Devin 双端与重复提交、取消并重启后的 Antigravity 旧扫描、只读 Hook 和来源独立断开。运行时与来源职责见 Agent 接入规格。

## Build 38 / App 分层与四个主文件拆分

设置、Board、活动灵动岛与烟雾渲染已按职责拆分，157 个原顶层类型逐项核对。90 项 Swift 定向测试通过。受控开发台在隔离目录完成准备与编译，Metal 源码逐字节相同，实际编译通过。两份用户本地原型使用副本核验；多任务旧准备脚本在重构前后均依赖已失效的 glowPath 锚点，冻结输入验证通过。详细结果见本批验证目录。

## Build 37 / 请求结算与占位展示解耦

状态机只依赖 Foundation 和 QuotaViewCore，App 层负责等待文案、卡片身份及提交态投影。独立编译通过，5 个无 UI 场景以及 43 项定向用例通过（含单独运行的隔离 native fixture）。详见本批验证目录。

## Build 36 / 请求生命周期物理拆分

请求状态机移至独立源文件，七个时间参数由调用方提供。抽出部分在排除时间默认值后与上一提交逐字相同。定向套件 39 项通过，另 1 项在隔离 native fixture 中补跑通过。展示模型的依赖留给 4b。

## Build 35 / DSH 交互适配器

DSH 请求、交回和标题读取已由独立适配器管理。10 项 Swift 定向测试及 44 项问答契约用例通过。SDK 测试入口修正及复验记录见 `.build/macos-architecture/3/scope-tests.json`。实际桌面操作待用户验收。

## 0.9.7 Build 34 / OpenCode 请求回传（本地开发）

OpenCode 的交互请求登记、一次性提交、回执超时与撤销已拆到 `OpenCodeInteractionAdapter.swift`，会话和监听仍由共用运行时管理。已在隔离夹具复现原客户端回答后，同轮重放 `question.asked` 会重新出现可答卡；插件现在按原生请求身份忽略这类重复通知。详见[OpenCode 请求回传](docs/specs/agent-integrations.md#build-34-opencode-请求回传)。

7 项 OpenCode 定向测试通过，零跳过。覆盖主通路优先、官方 SDK 1.19.5 在隔离传输中回传问答及权限、双击、回执丢失后禁止重发、原客户端结题、换轮及同 ID 新题。官方 CLI 1.19.5 使用本地模型完成任务状态冒烟。开发签名的 Build 34（内部 271）已启动，保留 Build 33 的设置窗口清理。实机交互待用户验收；证据在 `.build/opencode-097b34/`。

## 0.9.7 Build 33 / 设置窗口与旧菜单清理（本地开发）

设置窗口控制器、窗口类型与尺寸规则位于 `Sources/QuotaView/Settings/SettingsWindowController.swift`。灵动岛齿轮和重新打开 App 仍调用同一控制器。已核对生产端没有创建旧菜单控制器的入口，移除旧面板、状态栏标签、菜单重置演示和专属玻璃绘制，保留偏好兼容逻辑。灵动岛使用独立的 30 天费用模型 `Sources/QuotaView/Island/State/EstimatedCostChartModel.swift` 和原有额度倒计时格式。窗口复用及历史菜单的适用范围见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#设置窗口)。

15 项定向冒烟通过，覆盖原生设置窗口、费用计算、缺失数据、额度倒计时和偏好恢复。本地化检查与 Xcode Debug 构建通过。已核验 App 和 Widget 的开发签名、App Group、运行包内容与新进程的实际加载路径。本机已启动 Build 33（内部 270），证据在 `.build/settings-menu-097b33/`，窗口交互和费用图表外观待用户验收。

## 未完成项

- 用户实机检查设置窗口复用和费用图表，以及 OpenCode 原客户端结题、换轮后旧卡撤下。
- 跨 Agent 真实请求、辅助功能、多屏、Intel 与长时间运行的历史验收范围可按来源查阅。[交互规格](docs/specs/agent-integrations.md) · [设计验收记录](design-qa.md) · [此前未完成项](docs/archive/2026-11-26/HANDOFF.md#未完成项)

## 历史入口

Build 34 及以前的开发记录、原验证结果、历史下一步和故障排查已全文归档。查验本机源码时以目标工作区的分支、状态和已运行包为准。[完整开发交接归档](docs/archive/2026-11-26/HANDOFF.md) · [工作区约束](AGENTS.md)

<a id="展开宽度与图表横向滚动2026-10-09已进入开发包"></a>

[2026-10-09 展开宽度与图表横向滚动的交付记录](docs/archive/2026-11-26/HANDOFF.md#展开宽度与图表横向滚动2026-10-09已进入开发包)
