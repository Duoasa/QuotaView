# QuotaView SDD 注册表

[悬浮用量胶囊](island-floating-usage.md) · `QV-ISLAND-FLOATING-USAGE-001` · Accepted / Complete，开发版已更新，视觉待用户验收。

## 当前发布：0.7.9 Build 1

[0.7.9 发布规格](release-0.7.9.md) · `Released / User Acceptance Pending`。版本 `0.7.9 / 1 / 59` 已发布 GitHub Stable / Latest 与签名 appcast，最终 700 项本地测试全部通过。新增规格：[展开宽度](island-expanded-width.md)、[实时预览](settings-live-effect-preview.md)。完整发布事实见[版本历史](../../VERSION_HISTORY.md#当前最新版本)，视觉与真实客户端交互仍待用户验收。

文档编号：`QV-SDD-INDEX-001` · 状态：`Accepted` · 整理：2026-10-08。

当前源码与运行包只在 [Handoff](../../HANDOFF.md#工作区与版本定位) 维护；公开版本在[版本历史](../../VERSION_HISTORY.md#当前最新版本)维护。本表不复制 PID、构建流水或完整测试计数。

字体容错、用量 hover 与额度窗口横排遵循[界面规范](../design/QUOTAVIEW_UI_RULES.md#用量重置与共用工具区)；本次开发包交付及待验收边界见 [Handoff](../../HANDOFF.md)。
完成后百分比、收起态完成提示 3 秒后跟随运行任务、完成球慢速运动遵循[灵动岛与卡片规则](../design/QUOTAVIEW_UI_RULES.md#灵动岛与卡片)；2026-10-08 已通过定向类型检查，按用户“更新包”授权完成增量构建并进入开发运行包；本轮源码已由 [PR #86](https://github.com/Duoasa/QuotaView/pull/86) 合入 main，交互待用户验收。

灵动岛设置页按 [Figma 165:17](https://www.figma.com/design/hS0Dwc9S9EJGEbkkplxH4v/QuotaView?node-id=165-17) 接入桌面壁纸与紧凑静态预览；按后续用户修订移除晶钻前沿并迁移旧偏好，保留三种效果。最新比例、底部圆角和完整固定示例已进入开发包并随 PR #86 合入 main；尺寸、资源及不运行真实岛的边界见[设置窗口规则](../design/QUOTAVIEW_UI_RULES.md#设置窗口)，本地编译/运行状态见 Handoff，视觉等待用户验收。

2026-10-09 隐私预览修复：恢复设置隐私开关与静态示例的联动；通用任务名和“内容已隐藏”代替任务内容，关闭后恢复完整示例。源码定向类型检查通过，已按用户“启动替换”授权进入开发运行包；尚未推送，详情见 Handoff。

2026-10-09 用量标签与 Claude 图标：来源标签增加对应图标，Claude 系统星号替换为官网原始矢量标志，任务卡、子任务与重置卡同步复用。见[图标记录](../design/quotaview-provider-icons.md)；源码和资源检查通过，已按用户“启动替换”授权进入开发运行包；尚未推送。

2026-10-09 用量来源标签后续修订：两个标志统一无底框，选中态改为与用量按钮同高的 28 pt 胶囊；图文内距和字号共用工具栏参数。类型与资源检查通过，已按用户“运行”授权于 09:03 进入开发运行包；视觉待用户验收。

<a id="当前规格"></a>

2026-10-09 连接页整理：Codex 采用 Claude 的简洁设置行，连接详情统一折叠，错误与授权入口保持可见；移除套餐、额度、Tokens 和成本统计，保留实际连接控制。见[Claude 规格](claude-code-support.md#连接设置布局2026-10-09)与[界面规范](../design/QUOTAVIEW_UI_RULES.md#设置窗口)，本地构建/运行状态见 Handoff。

2026-10-09 设置微调：三种任务特效图片视口加高至 56 pt，连接页分组标题增加 22 pt 圆角图标。首个加高包经用户截图发现横向溢出，已补充独立列宽约束与裁切，重新编译并进入开发包，视觉待复验。规则见[设置窗口](../design/QUOTAVIEW_UI_RULES.md#设置窗口)；本地源码与运行包状态见 Handoff。

2026-10-09 其他设置页新样式：按 UI2 的通用、用量和连接画板调整窗口、导航与静态壁纸预览；保留当前实际菜单内容，沿用三项效果与连接控制。资源及尺寸见[接入记录](../design/quotaview-settings-style-20261009.md)，构建与运行状态见 Handoff，视觉待用户验收。

同日用户后续修订：用量显示与 Bug 反馈移除顶部可视化；代理与关于保留壁纸视口，去掉摘要外层黑色面板；导航选中图标和文字统一白色。已完成增量编译并进入当前开发运行包，视觉待验收；当前规则见[设置窗口](../design/QUOTAVIEW_UI_RULES.md#设置窗口)。用户已持续授权每次应用改动后更新运行开发版，见 [AGENTS.md](../../AGENTS.md#验收与开发工具) 和[验证规则](../workflow/VALIDATION.md)。

同日代理与关于可视化优化：用户否定首轮大色块与偏左布局后，代理改为等宽节点、小面积玻璃底托与顺序流光；关于移除版本色块，按图文固有宽度居中。尺寸和动画/性能边界见[设置窗口](../design/QUOTAVIEW_UI_RULES.md#设置窗口)，当前源码及运行状态见 [Handoff](../../HANDOFF.md)。实际观感待用户验收。

2026-10-09 源码合入：[PR #87](https://github.com/Duoasa/QuotaView/pull/87) 已将当前设置、品牌图标及 DSH / Kimi 接入合并至 main `4dd1e50`；PR 提交 `736d397` 与合并提交的 CI 均通过。首轮 CI 中过时的 32 pt 高度断言已同步为用户要求的 56 pt，保留圆角和裁切检查。该次合并时的开发运行包输入与 main 匹配；后续本地功能与当前包以 Handoff 为准，独立历史文档整理和原型保留本地，未发布正式包。

## 当前跨版本规格

| Spec ID | 文档 | 状态 | 范围 |
|---|---|---|---|
| `QV-SETTINGS-LIVE-PREVIEW-001` | [设置实时特效预览](settings-live-effect-preview.md) | `Accepted / Verifying` | 三个效果选项与上方卡片实时播放；24 fps / 1 像素每 pt，不可见停播；已编译运行，实机性能待验收。 |
| `QV-ISLAND-EXPANDED-WIDTH-001` | [展开宽度与窄屏图表](island-expanded-width.md) | `Accepted / Verifying` | 任务列表/用量页 560–680 pt 调节与刘海安全下限，实时设置预览同比例联动；图表横向滚动并默认显示最近数据。当前编译/运行证据见 Handoff，实机视觉待验收。 |
| `QV-PRODUCT-AGENT-INTEGRATIONS-001` | [Agent 连接与 DSH / Kimi Code 接入](agent-integrations.md) | `Accepted / Verifying` | DSH 多目录兼容与会话命名空间已进入 14:26 开发包；编译与配置核对通过，真实多客户端联动待验收。 |
| `QV-PRODUCT-CLAUDE-CODE-001` | [Claude Code 适配](claude-code-support.md) | `Accepted / Verifying` | 生命周期和审批开关修复已在开发包运行；19 项冒烟通过，真实交互待验收。 |
| `QV-PRODUCT-CODEX-ISLAND-INFORMATION-001` | [Codex 与灵动岛的信息契约](codex-island-information-contract.md) | `Accepted / Verifying` | 来源、轮次、等待结算与本地退场；原生问题组关闭仍未完成。 |
| `QV-ISLAND-EXPANDED-GLASS-001` | [展开态玻璃](island-expanded-glass.md) | `Accepted / Verifying` | 外观页持久化玻璃/经典纯色切换；55%–80% 渐变、连续曲率任务卡与无框图标；依据 DroppyKit 修正祖先遮罩，完整 Droppy 16.0.1 源码不可得，视觉/性能仍待验收。 |
| `QV-PRODUCT-ACTIVITY-ISLAND-BACKGROUND-MEMORY-001` | [记忆整理的来源、生命周期与底栏展示](../design/quotaview-background-memory-2026-10-03.md) | `Accepted / Verifying` | 依据原生来源和精确轮次识别记忆，独立底栏展示；真实场景待持续验收。 |
| `QV-CODEX-DESKTOP-CONFIRMATION-SYNC-001` | [Desktop 确认详情与双向同步](codex-desktop-confirmation-sync.md) | `Accepted / Verifying` | 当前 owner 回传、草稿与资源边界；本地 0.7.9 Build 2 已修复重订阅序号重置，真实交互待验收；ACK 不等于原生界面关闭。 |
| `QV-PRODUCT-ACTIVITY-ISLAND-PRODUCTION-003` | [刘海生产交互与显示规则](../design/quotaview-island-production-interaction-review-2026-09-30.md) | `Accepted / Verifying` | 生产多任务、请求与归档；详情一/两格、内部滚动和紧凑排版，子 Agent 纳入父卡第三行，实际效果待用户验收。 |

## 保留的独立开发台

| Spec ID | 文档 | 状态 | 范围 |
|---|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-002` | [多任务探索与固定开发台](../design/quotaview-island-multitask-next.md) | `Accepted / Verifying` | 固定开发台 2026-09-30-3s-sync-noise65；生产后续由 PRODUCTION-003 接续。 |
| `QV-PROTOTYPE-ISLAND-TEXT-018` | [灵动岛内容控制台](../design/quotaview-island-text-console.md) | `Accepted / Released` | 永久内容开发工具；保留手动控制和生产隔离。 |

## 历史发布与继承规格

版本号表示规格起源；状态保留既有交付记录，不表示当前整套体验已验收。被新入口替代的设置、布局和历史待办以当前生产规格为准。

| Spec ID | 文档 | 原交付状态 |
|---|---|---|
| `QV-PRODUCT-FEEDBACK-001` | [0.7.5 设置反馈入口](../design/quotaview-feedback-settings-0.7.5.md) | `Accepted / Released` |
| `QV-PRODUCT-MENU-QUOTA-022` | [0.5.1 菜单栏额度快捷显示](../design/quotaview-menu-quota-0.5.1.md) | `Accepted / Released` |
| `QV-PRODUCT-ISLAND-MOTION-021` | [0.5.0 灵动岛动画接入](../design/quotaview-island-motion-0.5.0.md) | `Accepted / Released` |
| `QV-FIX-EFFECT-LONGEVITY-020` | [特效长时间稳定性](../design/quotaview-effect-longevity.md) | `Accepted / Released` |
| `QV-FIX-CODEX-FIRST-CONNECTION-019` | [0.4.8 首次连接引导](../design/quotaview-codex-first-connection-0.4.8.md) | `Accepted / Released` |
| `QV-PRODUCT-PROXY-017` | [0.4.7 自定义代理](../design/quotaview-proxy-settings-0.4.7.md) | `Accepted / Released` |
| `QV-PROTOTYPE-QUANTUM-MOTION-016` | [量子噪点动效与控制台](../design/quotaview-quantum-motion-console.md) | `Accepted / Released` |
| `QV-FIX-CODEX-TOKEN-COMPATIBILITY-015` | [0.4.6 Token 兼容修复](../design/quotaview-codex-token-compatibility-0.4.6.md) | `Accepted / Released` |
| `QV-RELEASE-0.4.5-001` | [0.4.5 Build 1 发布](../design/quotaview-0.4.5-release.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-CONFIRMATION-REMINDER-014` | [0.4.5 灵动岛等待确认提醒](../design/quotaview-activity-island-confirmation-reminder-0.4.5.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-TURN-TOKENS-013` | [0.4.5 灵动岛本次任务 Token](../design/quotaview-activity-island-turn-token-usage-0.4.5.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-HOVER-TRANSPARENCY-012` | [灵动岛悬停透明](../design/quotaview-activity-island-hover-transparency-0.4.5.md) | `Accepted / Verifying` |
| `QV-PRODUCT-CODEX-SOCKET-AUTOCONNECT-011` | [0.4.5 Codex 本地任务流自动连接](../design/quotaview-codex-socket-autoconnect-0.4.5.md) | `Accepted / Released` |
| `QV-RELEASE-0.4.3-001` | [0.4.3 Build 1 发布](../design/quotaview-0.4.3-release.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-QUANTUM-NOISE-009` | [量子噪点效果修正](../design/quotaview-quantum-noise-effect-correction.md) | `Accepted / Released` |
| `QV-RELEASE-0.4.2-001` | [0.4.2 Build 1 发布](../design/quotaview-0.4.2-release.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008` | [0.4.2 任务连续性修正](../design/quotaview-activity-island-lifecycle-continuity-0.4.2.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007` | [0.4.2 进度条效果库](../design/quotaview-progress-effects-0.4.2.md) | `Accepted / Released` |
| `QV-RELEASE-0.4.1-001` | [0.4.1 发布](../design/quotaview-0.4.1-release.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006` | [进度条灵动岛](../design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005` | [灵动岛展开尺寸](../design/quotaview-codex-activity-island-size-0.4.0.md) | `Superseded / Released` |
| `QV-PRODUCT-QUOTA-WINDOWS-003` | [多周期额度展示](../design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` |
| `QV-PRODUCT-ACTIVITY-ISLAND-004` | [稳定单任务灵动岛](../design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` |
| `QV-PRODUCT-APP-UPDATES-003` | [应用检查与更新](../design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` |
| `QV-PRODUCT-ACTIVITY-ISLAND-CODEX-PLAN-010` | [0.4.4 Codex 多步计划兼容](../design/quotaview-codex-plan-compatibility-0.4.4.md) | `Accepted / Superseded` |
| `QV-RELEASE-0.4.0-001` | [0.4.0 大版本开发](../design/quotaview-0.4.0-development.md) | `Superseded / Released` |

## 按需参考

以下条目原为参考路由，第三列是阅读条件，不是交付状态。

| ID | 文档 | 何时阅读 |
|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001` | [0.3.2 多任务 Preview](../design/quotaview-codex-activity-island-multitask.md) | 仅研究公开 Preview；不能静默迁入稳定版 |
| `QV-PRODUCT-TOKEN-ACTIVITY-001` | [Token 活动](../design/quotaview-token-activity.md) | 修改范围、网格、Tooltip 或面板收展时 |
| `QV-PRODUCT-USAGE-OVERVIEW-002` | [用量概览](../design/quotaview-usage-overview-0.3.4.md) | 修改主额度、Spark、30 日用量或成本时 |
| `QV-DESIGN-WIDGET-001` | [WidgetKit 契约](../design/quotaview-widgetkit-solution.md) | 修改 Widget Target、共享快照、App Group 或布局时 |
| `QV-EXEC-CORE-002` | [核心架构摘要](../design/quotaview-core-architecture-evolution.md) | 修改 Provider、刷新、投影或写操作边界时 |
| `QV-EVIDENCE-CORE-0.2.0-001` | [0.2.0 重构报告](../design/quotaview-core-refactor-0.2.0-report.md) | 调查 0.2.0 架构回归时 |
| `QV-EVIDENCE-DESIGN-QA-001` | [Design QA](../../design-qa.md) | 核对历史视觉验收结论时 |

## 维护规则

- 已知规格时直接读取相关章节；新功能注册唯一 ID，已有行为修复复用原编号。
- 目标写在所属规格，当前证据写在 Handoff，发布事实写在版本历史，用户视觉结论写在 Design QA。
- 修订既有段落，不在文件顶部持续追加互相覆盖的“最新”记录；变更过程可进入带日期的归档。
- 授权、状态词汇与完成条件见 [SDD 流程](DEVELOPMENT_PROCESS.md)；历史计划不构成新任务授权。
- 清理前完整文档及原状态见[快照](../archive/maintenance-20261008/README.md)。本轮仅维护文档和产物，无产品行为变更。
