# QuotaView SDD 注册表

> 文档编号：`QV-SDD-INDEX-001`
>
> 状态：`Accepted`
>
> 最近同步：2026-10-05。公开稳定版：[0.7.5 Build 3](../../VERSION_HISTORY.md#当前最新版本)，内部52，已发布 GitHub Stable / Latest 与 appcast。
>
> 已发布源码：[PR #75](https://github.com/Duoasa/QuotaView/pull/75) 已合并 main；长会话恢复、设置反馈、正式发行配置和中英文产品文档已交付。其PR/main CI各663项、6跳过、0失败，签名公证、公开回下载及线上Feed验签通过。开发基准HEAD `f881356`；此前本地Build6/内部55包含记忆Hook身份、待机百分比与纯色描边修订。Build3记忆候选124条冒烟、Build4记忆修复交付、Build5历史UI交付和Build6构建/签名/190项输入核对分别见Handoff；这些历史结果不作为本轮Build7重复验证。
>
> 当前本地已交付：0.7.5/Build7/内部56观察等待恢复与原生异步问题本地退场；App PID62058、Widget PID62064。首轮编译失败日志保留，修正后Universal构建、190项生产输入/4项安装二进制哈希、同Team Developer ID签名、旧新权限声明及实际加载/活动通道核对通过；首次本地交付未新增或运行本地测试，真实交互待用户验收。30秒无人接管及发送/结果未知后3秒退场只管理本地展示；同thread/turn/question哈希持久账本有界4096项，不能证明原生缩略或已回答/关闭。源码与对应CI/main集成见 [PR #77](https://github.com/Duoasa/QuotaView/pull/77)；CI恢复修订尚未重新编译或替换安装，上述产物证据不包含后续源码；不发布Release/appcast。证据与边界见[信息契约](codex-island-information-contract.md#观察等待与本地提醒退场--2026-10-05)、[原生关闭合同](../design/codex-native-question-closure-contract-2026-10-03.md#2026-10-05-本地退场增量)及Handoff。
>
> 2026-10-05 新增源码：完成详情直接渲染 Codex 最终回答与可点击链接；有界摘要、重复刷新抑制、扫光/Metal 时钟连续修订。见[信息契约](codex-island-information-contract.md#完成回答与刷新成本--2026-10-05)及[效果契约](PROGRESS_EFFECT_ADAPTATION.md#8-2026-10-05-刷新与动画连续性修订)。用户随后授权运行，Debug arm64 增量开发编译通过，开发主 PID43098 已替换旧正式主进程；实际效果待用户验收，GitHub 合入状态见 Handoff。
>
> 开发入口与当前本地运行包见 [Handoff](../../HANDOFF.md#工作区与版本定位)。源码发布与规格完整验收分别记录；原生异步提问组关闭、真实 Intel 和完整客户端更新安装仍保留验收边界。

本文件只负责规格发现和状态定位，不复制 Requirement、实现或完整发布证据。

## 当前规格

| Spec ID | 文档 | 状态 | 当前结论 |
|---|---|---|---|
| `QV-PRODUCT-FEEDBACK-001` | [0.7.5 设置反馈入口](../design/quotaview-feedback-settings-0.7.5.md) | `Accepted / Released` | 独立Bug反馈页，QQ群原图二维码sheet与GitHub Issues跳转；标题副标题移除、退出常驻边框；4项冒烟、开发/正式身份构建与资源核对通过，随0.7.5 Build3正式发布，视觉全矩阵不由构建推断 |
| `QV-PRODUCT-CODEX-ISLAND-INFORMATION-001` | [Codex 与灵动岛的信息契约](codex-island-information-contract.md) | `Accepted / Verifying` | Build7/内部56本地已交付Hook有界历史/floor、notice去重、完整owner pending聚合结算及异步本地退场；真实RPC只依精确native结算，工具事件仅撤弱观察。30秒无人接管、草稿接管、发送/未知后3秒交回及持久4096项退场账本保留。Universal构建、190输入/4哈希、同Team签名与加载/活动通道核对通过，首次本地交付无本地测试；源码CI/main见PR #77；CI恢复源码未重新编译或替换安装，真实交互待用户验收，原生minimize精确同步及问题组关闭仍未实现 |
| `QV-PRODUCT-ACTIVITY-ISLAND-BACKGROUND-MEMORY-001` | [记忆整理的来源、生命周期与底栏展示](../design/quotaview-background-memory-2026-10-03.md) | `Accepted / Verifying` | 2026-10-05两个临时任务来源已确认，现场读取均准确匹配；旧Hook宿主与原生线程身份假设导致漏分流。以独一原生记忆turn绑定真实Hook生命周期，迟到身份仅撤回同turn别名卡，保留并行父任务；记忆复用既有底栏AI球，不按名称过滤。Build3候选124条冒烟通过；Build4/内部53已交付记忆修复，Build6包含UI修订，当前Build7/内部56延续这些逻辑并含等待与本地退场修复；本轮Universal构建、190项输入/4哈希、签名及实际Core加载核对通过，未重跑记忆冒烟；未公开发布，活动通道和视觉验收见Handoff。 |
| `QV-CODEX-DESKTOP-CONFIRMATION-SYNC-001` | [Desktop 确认详情与双向同步](codex-desktop-confirmation-sync.md) | `Accepted / Verifying` | 原任务 owner IPC 回传、普通/同步/异步独立解除和自动详情导航已实现；98 项必要冒烟、真实只读握手、开发构建/签名通过，真实交互待用户验收；已推送 PR #68，完整 CI/合并以 PR 为准。 |
| `QV-PRODUCT-ACTIVITY-ISLAND-PRODUCTION-003` | [刘海生产交互与显示规则](../design/quotaview-island-production-interaction-review-2026-09-30.md) | `Accepted / Verifying` | 用户授权独立 0.7.3 并采用推荐默认值；冻结开发台保留。真实活动、公开内容、十类请求与生命周期已实施；正常新建聊天分类已修复，每卡片可本地按轮次归档，跨重启保留，新轮重新显示。具备已证明 Desktop owner 能力的请求可原地回应，详见新同步规格；Figma 重置使用页和双向 3D 卡片过渡已接入；入口整块分割线下方含留白为热区，使用账户底部渐变高光；重置页Asta Sans标题15pt、正文11pt、按钮13pt、辅助10.5pt，35项相关冒烟和运行包核对通过，进出共用起步至缓动落位节奏，卡面高光 2 秒；0 次空态、未知次数和刷新恢复已补齐，重置仅演示；主入口迁移至刘海，设置/刷新统一工具区与六页彩色设置已接入；基础用量固定显示，仅成本/活动可调，自动弹出和 1–10 秒停留时间可调，四项特效采用紧凑同心预览；底部关于管理版本/更新，通用页退出带确认；四页上下栏字号、间距与 hover 统一。内联详情布局同步恢复锚点、显示前提交，预热目标卡片并保留中间可见集与轨道，用户滚动优先；纯授权采用“批准”。请求视口最多 440 pt，命令默认 8 行/2048 字符，长选项两行缩略，完整查看/复制保留原始回传。本轮 239 项相关冒烟、开发构建和包核对通过；动态子任务高度与公开进展已统一，已更新运行包，此前增量源码已随0.7.5 Build3发布；2026-10-05 Build6本地交付待机“就绪”及仅百分比，普通/选中或hover描边为不透明纯色#181818/#202020，主卡与子agent背板一致，构建签名和实际连接核验通过；视觉/交互验收范围见Handoff。 |
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-002` | [下一版压缩状态与多任务](../design/quotaview-island-multitask-next.md) | `Accepted / Verifying` | 2026-09-30 独立开发台固定为 2026-09-30-3s-sync-noise65；原包与 129 项构建输入已存档，3 秒同相、外围可全灭/噪点 65% 下限。停止 UI 迭代，未迁入生产；历史实现与验证见原规格，实际效果由用户验收。 |
| `QV-PRODUCT-MENU-QUOTA-022` | [0.5.1 菜单栏额度快捷显示](../design/quotaview-menu-quota-0.5.1.md) | `Accepted / Released` | Build 9 单周期 14 pt Regular 基线下移 1.5 pt，双周期保留单色横条；GitHub / Stable appcast 已发布，视觉仍由用户持续验收 |
| `QV-PRODUCT-ISLAND-MOTION-021` | [0.5.0 灵动岛动画接入](../design/quotaview-island-motion-0.5.0.md) | `Accepted / Released` | Build 3 已合并 main，GitHub / appcast 正式发布；240 项回归、4 项 AppKit、Universal、签名公证和公开回下载通过。纯黑底色与审计修复保留 Build 2 正常动效 |
| `QV-FIX-EFFECT-LONGEVITY-020` | [特效长时间稳定性](../design/quotaview-effect-longevity.md) | `Accepted / Released` | 随 0.5.0 Build 3 正式发布；5 项 GPU / 时钟检查随完整 240 项回归通过。真实长时间 / Intel 验收待补 |
| `QV-FIX-CODEX-FIRST-CONNECTION-019` | [0.4.8 首次连接引导](../design/quotaview-codex-first-connection-0.4.8.md) | `Accepted / Released` | [链路审计](../design/quotaview-connection-audit-0.4.8.md)完成；221 项测试零失败（2 跳过）、Universal/永久开发台及 PR/main CI 通过；Developer ID、公证、公开包和 Feed 验证通过，已发布；完整实机/视觉矩阵仍待验收；Build 13 内置 CLI 路径修复已发布 GitHub，249 项 CI（2 跳过）与正式产物验证通过，appcast 已发布并验证 |
| `QV-PROTOTYPE-ISLAND-TEXT-018` | [灵动岛内容控制台](../design/quotaview-island-text-console.md) | `Accepted / Released` | 单岛手动开发台源码随 Build 3 合并 main；共用生产动效与渲染器，57 项来源一致、4 项 AppKit 通过；不单独发布开发台二进制 |
| `QV-PRODUCT-PROXY-017` | [0.4.7 自定义代理](../design/quotaview-proxy-settings-0.4.7.md) | `Accepted / Released` | Build 3 修复文字显示、代理菜单对齐和设置图标，已合并 main 并发布到 GitHub / appcast；旧 Build 2 转为草稿 |
| `QV-PROTOTYPE-QUANTUM-MOTION-016` | [量子噪点动效与控制台](../design/quotaview-quantum-motion-console.md) | `Accepted / Released` | 用户已验收当前效果；177 项本地及 CI 测试、Universal、签名、公证、回下载与线上 appcast 验证完成；0.4.6 Build 2 已发布 |
| `QV-FIX-CODEX-TOKEN-COMPATIBILITY-015` | [0.4.6 Token 兼容修复](../design/quotaview-codex-token-compatibility-0.4.6.md) | `Accepted / Released` | [链路审计](../design/quotaview-activity-logic-audit-0.4.6.md)的 9 个场景已修复；[重构验证](../design/quotaview-activity-refactor-verification-0.4.6.md)本地及 CI 166 项测试通过，用户已确认真实五步视觉；正式签名、公证、Latest 与 appcast 已验证 |
| `QV-RELEASE-0.4.5-001` | [0.4.5 Build 1 发布](../design/quotaview-0.4.5-release.md) | `Accepted / Released` | 130 项测试、Universal Developer ID、公证/Staple、GitHub Latest、回下载验证与 Stable appcast 在线 EdDSA 均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-CONFIRMATION-REMINDER-014` | [0.4.5 灵动岛等待确认提醒](../design/quotaview-activity-island-confirmation-reminder-0.4.5.md) | `Accepted / Released` | 等待确认满 10 秒显示静态黄色描边和四周光晕；已随 0.4.5 发布 |
| `QV-PRODUCT-ACTIVITY-ISLAND-TURN-TOKENS-013` | [0.4.5 灵动岛本次任务 Token](../design/quotaview-activity-island-turn-token-usage-0.4.5.md) | `Accepted / Released` | 原功能随 0.4.5 发布；0.4.7 Build 3 已修复共用文字边界和完成百分号，用户已通过控制台手动检查，参见规格第 6 节 |
| `QV-PRODUCT-ACTIVITY-ISLAND-HOVER-TRANSPARENCY-012` | [灵动岛悬停透明](../design/quotaview-activity-island-hover-transparency-0.4.5.md) | `Accepted / Verifying` | 原固定透明度已发布；现扩展为0–100%悬停可见度、默认20%、即时保存与单项恢复默认；已整合上游Build13，255项回归（2跳过、0失败）及Universal无签名构建通过。待PR审查和实机验收，未发布 |
| `QV-PRODUCT-CODEX-SOCKET-AUTOCONNECT-011` | [0.4.5 Codex 本地任务流自动连接](../design/quotaview-codex-socket-autoconnect-0.4.5.md) | `Accepted / Released` | 只读本地任务流主通道、共享 Socket/Hook 回退及量子噪点单一灵动岛已随 0.4.5 发布 |
| `QV-RELEASE-0.4.3-001` | [0.4.3 Build 1 发布](../design/quotaview-0.4.3-release.md) | `Accepted / Released` | 104 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线 EdDSA 均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-QUANTUM-NOISE-009` | [量子噪点效果修正](../design/quotaview-quantum-noise-effect-correction.md) | `Accepted / Released` | 连续相位、压缩上下文可见性、闪灭、文字层级与完成反馈已随 0.4.3 发布；完整视觉矩阵仍待验收 |
| `QV-RELEASE-0.4.2-001` | [0.4.2 Build 1 发布](../design/quotaview-0.4.2-release.md) | `Accepted / Released` | 103 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线 EdDSA 均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008` | [0.4.2 任务连续性修正](../design/quotaview-activity-island-lifecycle-continuity-0.4.2.md) | `Accepted / Released` | 实时事件不再因局部步骤结束而误隐藏或提前完成；完成态只接受真实 `Stop`，已随 0.4.2 发布 |
| `QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007` | [0.4.2 进度条效果库](../design/quotaview-progress-effects-0.4.2.md) | `Accepted / Released` | 四种真实预览、状态配色适配、平滑进度与三个新增效果的完成高亮已随 0.4.2 发布 |
| `QV-RELEASE-0.4.1-001` | [0.4.1 发布](../design/quotaview-0.4.1-release.md) | `Accepted / Released` | 93 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线签名核验均已完成 |
| `QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006` | [进度条灵动岛](../design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Released` | `exec` 计划计数、4 秒 1%识别窗口、单步骤回退、完成高光分层与结束事件收敛已随 0.4.1 Build 1 发布 |
| `QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005` | [灵动岛展开尺寸](../design/quotaview-codex-activity-island-size-0.4.0.md) | `Superseded / Released` | 0.4.1 的 AI 球尺寸能力保留为发布历史；0.4.5 已移除 AI 球及其展开尺寸选择器 |
| `QV-PRODUCT-QUOTA-WINDOWS-003` | [多周期额度展示](../design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 已随 0.3.7 Build 1 发布并进入 Stable appcast |
| `QV-PRODUCT-ACTIVITY-ISLAND-004` | [稳定单任务灵动岛](../design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；多任务实验不在稳定范围 |
| `QV-PRODUCT-APP-UPDATES-003` | [应用检查与更新](../design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.7.5 Build3/内部52已发布GitHub与签名Stable Feed；正式身份、Developer ID、公证/Staple、公开回下载与旧版公钥验证通过；真实 N → N+1 安装操作待记录 |

## 已替代的当前迭代规格

| Spec ID | 文档 | 状态 | 结论 |
|---|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-CODEX-PLAN-010` | [0.4.4 Codex 多步计划兼容](../design/quotaview-codex-plan-compatibility-0.4.4.md) | `Accepted / Superseded` | 0.4.4 未发布；原生计划与共享桥成果已进入 0.4.5 自动发现候选 |
| `QV-RELEASE-0.4.0-001` | [0.4.0 大版本开发](../design/quotaview-0.4.0-development.md) | `Superseded / Released` | 0.4.0 保留为开发身份记录，不发布；成果已由 0.4.1 Build 1 正式发布 |

当前版本与下一步见 [Handoff](../../HANDOFF.md)，不可变发布事实见
[Version History](../../VERSION_HISTORY.md#当前最新版本)。

## 按需规格与历史参考

| Spec ID | 文档 | 读取条件 |
|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001` | [0.3.2 多任务 Preview](../design/quotaview-codex-activity-island-multitask.md) | 仅研究公开 Preview；不能静默迁入稳定版 |
| `QV-PRODUCT-TOKEN-ACTIVITY-001` | [Token 活动](../design/quotaview-token-activity.md) | 修改范围、网格、Tooltip 或面板收展时 |
| `QV-PRODUCT-USAGE-OVERVIEW-002` | [用量概览](../design/quotaview-usage-overview-0.3.4.md) | 修改主额度、Spark、30 日用量或成本时 |
| `QV-DESIGN-WIDGET-001` | [WidgetKit 契约](../design/quotaview-widgetkit-solution.md) | 修改 Widget Target、共享快照、App Group 或布局时 |
| `QV-EXEC-CORE-002` | [核心架构摘要](../design/quotaview-core-architecture-evolution.md) | 修改 Provider、刷新、投影或写操作边界时 |
| `QV-EVIDENCE-CORE-0.2.0-001` | [0.2.0 重构报告](../design/quotaview-core-refactor-0.2.0-report.md) | 调查 0.2.0 架构回归时 |
| `QV-EVIDENCE-DESIGN-QA-001` | [Design QA](../../design-qa.md) | 核对历史视觉验收结论时 |

## 阅读与维护规则

- 已知规格时直接阅读受影响章节；本表用于查找，不要求逐条打开。
- 恢复开发任务查阅 Handoff 的开发最新版；核对发布身份才读版本历史当前节。
  两者可能使用相同配置版本号，不能据此把未发布源码当作稳定版。
- 新功能或新的架构边界注册唯一 Spec ID；现有行为修复复用其 Requirement。
  无行为影响的文档修复注明 `Spec impact: None` 即可，不新增产品规格。
- 状态词汇、完成条件、授权与维护规则统一见 [SDD 开发流程](DEVELOPMENT_PROCESS.md)。
  仅在这些条件需要解释或变更时读取该流程。
- 本次文档整理维护 `QV-SDD-PROCESS-001` / `QV-SDD-INDEX-001`，保留上表
  既有产品交付和验收状态。历史计划不构成新任务授权。
