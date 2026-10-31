# QuotaView SDD 注册表

Windows 当前发布：**0.8.3-win.13** · Released / User Acceptance Pending。包括终态通知修复、设置精简和默认开启自动检查更新；已接入独立签名 appcast，现有关闭偏好保留。完整证据见[版本历史](../../VERSION_HISTORY.md#当前最新版本)。下方 win.11/12 为开发阶段记录。

Windows 设置精简后续：本地开发版 `0.8.3-win.12` 已改为以标题、控件和状态表达用途，详情折叠、说明按需出现。构建通过，视觉待用户验收；见 [Windows Handoff](../../Windows/HANDOFF.md)，未推送或发布。

## Windows 本地修复：0.8.3-win.11

[终态与通知修复](windows-channel.md#windows-终态与通知修复2026-10-31) · `Accepted / Verifying`：Issue #114 的轮次去重、重复日志合并和断线终态稳定，以及设置页说明精简。定向检查与原生适配通过，本地开发包已启动；反馈者现场和视觉待验收。未推送或发布，运行定位见 [Windows Handoff](../../Windows/HANDOFF.md)。

## 当前开发：0.8.7 Build 23

[系统滚动边缘分层](../design/QUOTAVIEW_UI_RULES.md#系统滚动边缘分层2026-11-01087-build-23) · `Implemented / User Acceptance Pending`：macOS 26+ 改用系统 safeAreaBar 和 soft scroll edge effect，移除当前系统路径的自绘面板。保留设置归类、四色侧栏、原始图标加载、GitHub 入口和重置禁用保护。增量构建及运行核验通过；当前运行 Build 23 / 内部 125。用户已授权本批源码推送/合并，集成状态见 Handoff，视觉继续由用户检查。

## 前序开发：0.8.7 Build 22

[窗口内原生磨砂与留白](../design/QUOTAVIEW_UI_RULES.md#窗口内原生磨砂与留白2026-11-01087-build-22) · `Implemented / User Acceptance Pending`：明确 withinWindow 原生磨砂，预览下方 28 pt、左栏顶部新增 12 pt 留白；关于页改为优先原始 PNG，图标文件未修改。增量编译及运行包核验通过，当前运行 0.8.7 Build 22 / 内部 124，仅本地；实际效果由用户验收。

## 前序开发：0.8.7 Build 21

[重置卡禁用保护](codex-quota-reset.md#禁用重置卡使用2026-11-01087-build-21) · `Implemented / User Acceptance Pending`：用量显示新增保护开关，禁用按钮并撤销旧确认，发送前再次拦截；偏好持久化，验证未使用真实重置卡。

[固定预览与原生滚动分层](../design/QUOTAVIEW_UI_RULES.md#原生滚动位置与宽度对齐修正2026-11-01087-build-21) · `Implemented / User Acceptance Pending`：原生滚动量控制渐显磨砂，同一可用宽度对齐预览与设置；恢复双材质独立选项，通用页接回交互/隐私和屏幕设置，侧栏四色，Agent 接入与关于 GitHub 入口已更新。增量构建、15 项定向检查和 239 输入/运行包核验通过，当前已运行 Build 21 / 内部 123；仅本地，视觉由用户继续检查。

## 前序开发：0.8.7 Build 17

[紧凑选择与底色分组](../design/QUOTAVIEW_UI_RULES.md#紧凑选择与底色分组2026-10-31087-build-17) · `Implemented / User Acceptance Pending`：任务特效/玻璃外观改为同行紧凑选择，灵动岛重组为外观、布局与显示、交互与隐私；设置框使用底色，左栏仅用间距分组。增量编译、3 项定向冒烟及运行包核验通过，开发包已更新；本批仅本地，视觉待用户检查。

## 前序开发：0.8.7 Build 16

[最新 App 图标与 Dock 预览](../design/quotaview-app-icon.md) · `Implemented / User Acceptance Pending`：Build 16 已按用户要求替换最新 `QV-icon-iOS-Solid@1x.png`，源码已由 [PR #122](https://github.com/Duoasa/QuotaView/pull/122) 合入 main `57864ea`，PR/main CI 均通过（各 727 测试、6 跳过、0 失败及 44 契约检查），239 项输入与当时运行的 Build 16 一致。独立 Dock 预览后续已清理；未发布。

[关于页信息补全](../design/QUOTAVIEW_UI_RULES.md#关于页信息补全2026-10-31087-build-12) · `Implemented / User Acceptance Pending`：图标放大 50% 至 96 pt，增加实际包构建日期与版权；0.8.7 Build 12 开发运行包已更新，视觉由用户验收。

[最新 App 图标](../design/quotaview-app-icon.md) · `Implemented / User Acceptance Pending`：用户新 PNG 已装入 0.8.7 Build 11，完整图标尺寸及运行包核对通过，保留纯色关于页；仅本地试装。

[关于页纯色居中布局](../design/QUOTAVIEW_UI_RULES.md#关于页纯色与居中布局2026-10-31087-build-10) · `Implemented / User Acceptance Pending`：移除壁纸横幅，图标与真实产品信息纵向居中；Build 10 开发包已更新，保留更新操作，视觉由用户查看。

[App 图标试装](../design/quotaview-app-icon.md) · `Implemented / User Acceptance Pending`：用户 PNG 已装入 0.8.7 Build 9 开发版，图标资源、构建和运行包核对通过；仅本地，视觉由用户查看。

## 前序开发：0.8.7 Build 8

[标签图标尺寸与原色](../design/quotaview-provider-icons.md) · `Accepted / Verifying`：圆底/标志缩至 16/11 pt，左内距 4 pt 保持同心；图标完整不透明度绘于独立玻璃背景上方。重置卡保持发行版灰色渐变。本轮已通过 [PR #117](https://github.com/Duoasa/QuotaView/pull/117) 合入 main `6c3f55f`，PR/main CI 均成功（各 727 测试、6 跳过、0 失败，44 契约检查）；239 项运行输入与源码/合并提交一致。完整证据见 Handoff，视觉由用户检查；未发布。

## 前序开发：0.8.7 Build 7

[标签圆底与重置卡恢复](../design/quotaview-provider-icons.md) · `Accepted / Verifying`：用量标签圆形图标与胶囊左端同心，重置卡恢复 0.8.6 Build 21 原始灰色渐变素材。运行核验及用户已授权的本轮源码推送/main 合并结果见 Handoff；视觉待用户检查，未授权发布或 appcast。

## 前序开发：0.8.7 Build 5

[退出入口仅文字](../design/QUOTAVIEW_UI_RULES.md#退出入口仅保留文字2026-10-30087-build-5) · `Accepted / Verifying`：移除退出行图标及占位，保留危险动作样式和确认流程。开发包更新与核验见 Handoff，视觉由用户检查，仅本地修改。

## 前序开发：0.8.7 Build 4

[设置图标圆角底托](../design/QUOTAVIEW_UI_RULES.md#单色图标保留圆角底托2026-10-30087-build-4) · `Accepted / Verifying`：按 macOS 设置参考，将子页面功能图标统一为灰色圆角底与白色符号，覆盖页标题、设置行、反馈及退出入口；Build 3 排版保持。构建与开发包状态见 Handoff，视觉由用户验收，仅本地修改。

## 前序开发：0.8.7 Build 3

[设置排版与单色图标](../design/QUOTAVIEW_UI_RULES.md#子页面单色图标与统一间距2026-10-30087-build-3) · `Accepted / Verifying`：子页面功能图标改为单色，统一设置框尺寸规则、页顶留白及分组/组内间距；品牌图标保留官方素材。增量编译、开发包更新与加载路径核验通过（239 输入、14 资源），既有控件对齐冒烟结果见 Handoff；视觉由用户验收。本批仅本地修改。

## 前序开发：0.8.7 Build 2

[官方来源图标](../design/quotaview-provider-icons.md) · `Accepted / Verifying`：Claude 使用官方应用包内橙底白标，ChatGPT/Codex 用量与重置卡使用官方 Blossom 路径；截图仅作参考。增量构建、开发运行包核验、四项资源解码及官方素材一致性检查通过；239 输入、14 资源，视觉与小尺寸效果由用户验收。仅本地开发，运行证据见 [Handoff](../../HANDOFF.md#工作区与版本定位)。

## 前序开发：0.8.7 Build 1

2026-10-30 按用户要求初始化 0.8.7 / Build 1 / 内部 103。App、Widget 与兼容 Info.plist 同步，保留开发身份；功能沿用 0.8.6 Build 21，具体功能范围尚未指定，暂无新增功能规格。Debug arm64 增量构建及开发包更新启动完成，237 输入、完整包与实际加载路径核对通过；本次初始化 `Complete`，具体功能待定。证据见 [Handoff](../../HANDOFF.md#工作区与版本定位)。仅本地开发，未授权发布或 appcast 准入。

## 最近公开发布：0.8.6 Build 21

[0.8.6 发布](release-0.8.6.md) · `Released / User Acceptance Pending`：Build 21 / 内部 102，PR/main CI、签名公证、公开 ZIP 与签名 appcast 已验证；公告已启用，Codex 缓存误报已修复，默认检查更新开启。公开 README 未改，视觉及真实升级体验由用户验收。


2026-10-29：用户接受 Build 19 的公告与设置修改后，本轮已由 [PR #113](https://github.com/Duoasa/QuotaView/pull/113) 合入 main `691eed6`；PR 与 main CI 均通过（726 测试、6 跳过、0 失败，44 契约检查），运行包 237 输入与合并源码一致。未发布；完整事实见 Handoff。下方各批「本地修改」保留为阶段记录。


[设置恢复原宽度](../design/QUOTAVIEW_UI_RULES.md#恢复原默认宽度2026-10-29086-build-19) · `Accepted / Verifying`：按用户要求恢复默认 780 × 680、最小 740 × 560、内容最大宽 560；保留紧凑元素与上下材质选项。Build 19 已增量构建并更新开发运行包，输入/产物/加载路径核对通过；证据见 Handoff，视觉由用户验收。


[公告与设置元素尺寸](../design/QUOTAVIEW_UI_RULES.md#参考对照图调整元素尺寸2026-10-29086-build-18) · `Accepted / Verifying`：按用户同屏 VibeIsland 对照收紧图标、标题、行高和控件；设置窗口宽 620，恢复发行版玻璃/纯色上下双选项。公告隐藏系统交通灯，保留底部按钮与键盘关闭。Build 18 已构建并更新开发运行包，既有设置行布局冒烟通过；运行证据见 Handoff，视觉由用户验收。

## 前序开发：0.8.6 Build 15

[网络代理仅保留设置](../design/QUOTAVIEW_UI_RULES.md#网络代理仅保留设置2026-10-29086-build-15) · `Accepted / Verifying`：用户否定当前可视化方案并要求移除，专用视图、绘制与动画已清理，恢复无可视化的代理设置布局。Build 13–14 方案不再作为实施目标；运行核验见 Handoff。本次仅本地开发。

## 前序开发：0.8.6 Build 14

[当前通路蓝色描边](../design/QUOTAVIEW_UI_RULES.md#当前通路蓝色描边2026-10-29086-build-14) · `Accepted / Verifying`：补齐参考中的蓝色路径与节点选中轮廓，保留无额外填充底板和已有动效。运行核验见 Handoff，视觉待用户查看；仅本地开发。

## 前序开发：0.8.6 Build 13

[代理路径动效](../design/QUOTAVIEW_UI_RULES.md#代理路径动效2026-10-29086-build-13) · `Accepted / Verifying`：用户授权在开发版实现参考中的路径层级表达，保留公开版背景、无额外图标底托和说明。两条路线随草稿切换并沿线流动，真实测试状态独立表达；三个隔离冒烟、增量编译及运行包核验通过，实际动效待用户验收。本批仅本地开发。

## 前序开发：0.8.6 Build 12

[网络代理布局](../design/QUOTAVIEW_UI_RULES.md#移除网络代理可视化2026-10-29086-build-12) · `Accepted / Verifying`：移除顶部可视化及专用动画，标题后直接显示真实设置。开发构建与运行状态见 Handoff；Build 10–12 已通过 [PR #112](https://github.com/Duoasa/QuotaView/pull/112) 合入 main，PR 与精确 main CI 均成功。新的可视化仍为独立设计方案，未接入应用；未发布 Release。

## 前序开发：0.8.6 Build 11

[原生设置下拉](../design/QUOTAVIEW_UI_RULES.md#原生下拉选择2026-10-29086-build-11) · `Accepted / Verifying`：按用户系统设置参考，四处下拉共用原生弹出式选择控件，系统管理选中勾选、高亮和定位。增量编译、开发运行包与加载路径核对通过；视觉待用户验收，仅本地修改。

## 前序开发：0.8.6 Build 10

[更新与公告](brand-announcement.md) · `Review / Verifying`：原公告扩展为可滚动、可折叠的通用内容窗口，支持亮点、新功能、改进、公告和提醒；保留指定发布版本各展示一次的规则，正式名单为空。Build 18 进一步调整元素尺寸为 460 × 580 并隐藏交通灯；原提醒策略保持，构建与运行证据见 Handoff，视觉由用户验收。

## 前序开发：0.8.6 Build 9

[设置说明与信息层级](../design/QUOTAVIEW_UI_RULES.md#信息层级与重复说明清理2026-10-29086-build-9) · `Accepted / User Verified`：移除页头/语言/外观等重复解释，用分段选择和 Agent 就近展开表达关系，合并 Claude 重复启用开关与更新按钮标题；保留操作限制、错误及未保存提示，中英文同步。Build 9 / 内部 90 增量编译、运行包加载与既有设置行布局冒烟通过。用户已接受本次调整；[PR #111](https://github.com/Duoasa/QuotaView/pull/111) 已合入 main，PR 与精确 main CI 均通过（723 项测试、6 跳过、0 失败，另 44 项契约检查），运行输入与合并源码一致。证据见 Handoff；未发布 Release 或 appcast。

## 前序开发：0.8.6 Build 8

[聚焦待确认特效](PROGRESS_EFFECT_ADAPTATION.md) · `Accepted / User Verified`：用户确认实际灵动岛临时审批卡效果无问题。Build 8 已清理模拟卡、全部 Debug 注入及临时启动参数，恢复真实任务展示；两个文件恢复预览前生产基线。0.8.6 / Build 8 / 内部 89 增量编译、运行包和加载路径核对通过，生产临时标记扫描零匹配。仅本地修改，未推送或发布；验收范围限本次查看的效果。

## 前序开发：0.8.6 Build 7

用户要求直接在实际灵动岛检查审批卡。临时 `DEBUG` 任务以 65% 待批准状态注入开发会话显示副本，默认聚焦列表，可点击进入审批页；仅模拟交互，不执行真实命令或审批。独立预览已退出并清理；Build 7 / 内部 88 增量编译、运行包更新、参数及加载路径核对通过。临时注入已在用户验收后由上方 Build 8 清理；详见 [Handoff](../../HANDOFF.md)。

## 前序开发：0.8.6 Build 6

[应用更新](../design/quotaview-app-updates-0.3.5.md) · `Accepted / Verifying`：后续 Release 默认开启自动检查更新，正式打包门禁同步校验；保持用户可关闭、24 小时周期和手动下载安装。Build 6 / 内部 87 增量编译与运行包启动、产物更新配置、加载路径和发布脚本语法检查通过。此追加变更仅本地；未发布包或 appcast。

## 前序开发：0.8.6 Build 5

[聚焦待确认特效](PROGRESS_EFFECT_ADAPTATION.md) · `Accepted / Verifying`：移除待确认状态对整个进度特效的隐藏/禁播，列表聚焦卡与审批头卡保留所选特效及原进度，确认边缘光保持。三种特效与首次待确认、状态切换、可见性/离窗、减少动态的宿主级回归通过；相关渲染和审批冒烟共 12 项通过，Debug arm64 增量编译通过。[PR #110](https://github.com/Duoasa/QuotaView/pull/110) 已合入 main，PR 与精确 main CI 均通过（723 项测试、6 跳过、0 失败，另 44 项契约检查）；Build 5 开发运行包已更新启动并核对加载路径。用户已暂缓任务列表/审批页隔离模拟截图，临时预览已清理，后续实际灵动岛效果已获用户验收；源码合并与运行包状态见 [Handoff](../../HANDOFF.md#工作区与版本定位)。本次仅源码集成和本地开发运行包更新，不发布 Release、安装包或 appcast。

## 前序开发：0.8.6 Build 4

[任务来源图标](../design/quotaview-provider-icons.md#task-provider-icons) · `Accepted / User Verified`：Claude、DSH、Kimi 任务卡使用圆角矩形真实 Logo，用户已确认图标无问题；Build 4 清理三张模拟卡及全部临时注入，恢复纯真实任务展示。0.8.6 / Build 4 / 内部 85 增量编译、运行包、无预览参数启动及加载路径核对通过。图标验收不扩展为真实来源协议或其他场景验收。源码已由 [PR #109](https://github.com/Duoasa/QuotaView/pull/109) 合入 main，PR 与精确 main 提交 CI 均通过，证据见 Handoff；未获发布/appcast 准入；当前运行证据见 [Handoff](../../HANDOFF.md#工作区与版本定位)。

## 前序开发：0.8.6 Build 1

2026-10-28 按用户要求更新开发版本为 0.8.6 / Build 1 / 内部 82，App、Widget 与兼容 Info.plist 同步；增量编译及运行包更新、启动和加载路径核对通过。功能沿用 0.8.5，具体改动等待用户指示，暂无新增功能规格。仅本地开发，未授权发布或 appcast 准入；公开稳定版仍为 0.8.5 Build 1，证据与当前运行定位见 [Handoff](../../HANDOFF.md#工作区与版本定位)。

## 前序发布：0.8.5 Build 1

[Codex 手动额度重置](codex-quota-reset.md) · `Released / User Acceptance Pending`：明确确认后调用官方接口，绑定具体卡片、账户和持久化幂等操作；隔离模拟验证，不消费本机真实卡。[0.8.5 发布](release-0.8.5.md)已完成 PR/main CI、签名公证、GitHub Stable/Latest 与 macOS appcast 上线及公开回下载核验。中英文 README 与开发版已更新，回滚基线 0.8.3 Build 1；真实扣卡与视觉待用户验收。完整事实见版本历史，当前运行状态见 Handoff。

## 前序开发：0.8.3 Build 6

[重置操作区深浅适配](island-glass-appearance.md#重置操作区深浅适配2026-10-27) · `Accepted / Verifying`：Claude 复制按钮和两种来源的操作说明接入统一玻璃外观；危险重置保留白字并加强浅色红底。只作用于重置操作区，保留自动与实体回退。增量编译、开发运行包与加载路径核对通过，证据见 Handoff；视觉待用户验收。

## 前序开发：0.8.3 Build 5

[重置页额度左右对齐](island-expanded-glass.md#重置页额度左右对齐2026-10-27) · `Accepted / Verifying`：按用户修订恢复左标签/右百分比，两侧共用须知的 14 pt 内容内距，上下间距各 16 pt；增量编译、开发运行包及加载路径核对通过，证据见 Handoff；视觉待用户验收。

## 前序开发：0.8.3 Build 4

[任务特效前移](island-glass-appearance.md#任务特效前移2026-10-27) · `Accepted / Verifying`：特效三选项移动到顶部预览正下方，后续依次为外观与布局、显示内容、自动展开；绑定、尺寸和保存行为不变。增量编译、开发包及实际加载路径核对通过，证据见 Handoff；视觉待用户验收。

## 前序开发：0.8.3 Build 3

[重置页额度摘要](island-expanded-glass.md#重置页额度摘要排版2026-10-27) · `Superseded by Build 5`：“剩余额度 + 百分比”并入重置次数下方的居中摘要，标签 10.5 pt Regular、数值 12 pt Medium，保留真实/旧数据/未知态。增量编译、开发运行包及加载路径核对通过，证据见 Handoff；视觉待用户验收，仅本地修改。

## 前序开发：0.8.3 Build 2

[重置说明深色玻璃](island-expanded-glass.md#重置说明卡片统一深色玻璃2026-10-27) · `Accepted / Verifying`：须知/空态/Claude 说明容器接入用量卡片相同的深色玻璃与辅助功能回退。增量编译、开发运行包及加载路径核对通过；视觉待用户验收，当前修改仅本地，详见 Handoff。

## Windows 首个正式版：0.8.3-win

[Windows 工程与独立更新通道](windows-channel.md) · `Released / User Acceptance Pending`：公开名称 `0.8.3-win · Windows`，包内和更新版本保留 `0.8.3-win.10`。原始 ZIP 已发布并公开回下载验签，首个条目加入独立 Windows appcast；中英文 README 增加上线与功能降级适配说明。macOS Release 仅补充平台名称，原更新通道不变。完整事实见[版本历史](../../VERSION_HISTORY.md#当前最新版本)，真实升级体验待用户验收。

## 前序发布：0.8.3 Build 1

[0.8.3 发布规格](release-0.8.3.md) · `Released / User Acceptance Pending`：GitHub Stable / Latest 与签名 appcast 已发布，源码 PR/main CI、公开 ZIP 与 Feed 验证通过。中英文 README 已更新，回滚基线 0.8.2 Build 2；完整发布事实见版本历史，开发运行包见 Handoff。

## 前序开发：0.8.2 Build 10

[Widget 字体归档兼容](../design/quotaview-widgetkit-solution.md#macos-27-字体归档兼容2026-10-15) · `Accepted / Verifying`：针对实机 NotificationCenter 的 invalidFont 解码错误，扩展改用保留随包文件 URL 的字体 descriptor，主应用字体不变。开发构建与运行包已更新；用户另授权备份替换本机安装，已签名安装 Build 10，并确认桌面恢复显示。本机当前 Medium 场景已验收，其他设备/尺寸/状态仍待验证。源码经 PR #100 合入 main，CI 与交付见 Handoff。

## 已合入源码：0.8.2 Build 9

[底部玻璃与胶囊统一外观](island-glass-appearance.md) · `Accepted / Verifying`：浅色 / 深色 / 自动三选项只在液态玻璃显示，统一底栏与胶囊；黑色渐变和深色卡片保留，设置按外观与布局、显示内容、任务特效、自动展开分组。Build 6 已修正非激活按钮前景发灰，Build 7 按用户要求统一工具图标为 11 pt Semibold，Build 8 将四处导航文案改为 12 pt Regular 并增加来源标签右内距；Build 9 移除胶囊独立染色，与岛体/预览共用 clear 玻璃；编译与开发包核对通过；前序 3 项定向冒烟通过。用户已授权推送源码并合并 main，GitHub 结果与运行状态见 [Handoff](../../HANDOFF.md)，视觉待用户验收。

## 前序本地适配：macOS 27 深色玻璃

`Accepted / Verifying`：按用户参考图继续调深至 0.8.2 Build 4（内部 68）。macOS 27 近黑表面采用未染色 clear 玻璃与原强度独立底色，修正 Build 3 过亮；共用于任务、用量卡片、深色胶囊及预览。macOS 26 与辅助功能回退保持原样；[调校规格](island-expanded-glass.md#macos-27-炭灰玻璃调校2026-10-15覆盖-build-3)。增量编译与开发运行包核对通过，证据见 [Handoff](../../HANDOFF.md)，视觉待用户验收。此适配已纳入上方 0.8.3 发布。

## 前序发布：0.8.2 Build 2

[0.8.2 发布规格](release-0.8.2.md) · `Released / User Acceptance Pending`。版本 `0.8.2 / 2 / 66` 已发布 GitHub Stable / Latest 并推送签名 appcast。本次为显示位置设置与子 Agent 排版修复的小更新。完整事实见[版本历史](../../VERSION_HISTORY.md#当前最新版本)，运行状态见 [Handoff](../../HANDOFF.md)。前一稳定版 [0.8.1](release-0.8.1.md) 保留为回滚基线；实际多屏与视觉由用户验收。

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
| `QV-BRAND-ANNOUNCEMENT-001` | [更新与公告](brand-announcement.md) | Review / Verifying | 多类型分组、滚动与折叠、按版本提醒；正式名单待配置 |
| `QV-WINDOWS-CHANNEL-001` | [Windows 工程与独立更新通道](windows-channel.md) | `Released / User Acceptance Pending` | 完整 Windows 源码统一维护，首个正式版发布并加入独立签名 appcast；支持用户触发下载安装，真实升级体验待验收。 |
| `QV-SETTINGS-LIVE-PREVIEW-001` | [设置实时特效预览](settings-live-effect-preview.md) | `Accepted / Verifying` | 三个效果选项与上方卡片实时播放；24 fps / 1 像素每 pt，不可见停播；已编译运行，实机性能待验收。 |
| `QV-ISLAND-EXPANDED-WIDTH-001` | [展开宽度与窄屏图表](island-expanded-width.md) | `Accepted / Verifying` | 任务列表/用量页 560–680 pt 调节与刘海安全下限，实时设置预览同比例联动；图表横向滚动并默认显示最近数据。当前编译/运行证据见 Handoff，实机视觉待验收。 |
| `QV-PRODUCT-AGENT-INTEGRATIONS-001` | [Agent 连接与 DSH / Kimi Code 接入](agent-integrations.md) | `Accepted / Verifying` | DSH 多目录兼容与会话命名空间已进入 14:26 开发包；编译与配置核对通过，真实多客户端联动待验收。 |
| `QV-PRODUCT-CLAUDE-CODE-001` | [Claude Code 适配](claude-code-support.md) | `Accepted / Verifying` | 生命周期和审批开关修复已在开发包运行；19 项冒烟通过，真实交互待验收。 |
| `QV-PRODUCT-CODEX-ISLAND-INFORMATION-001` | [Codex 与灵动岛的信息契约](codex-island-information-contract.md) | `Accepted / Verifying` | 来源、轮次、等待结算与本地退场；原生问题组关闭仍未完成。 |
| `QV-ISLAND-GLASS-APPEARANCE-001` | [底部玻璃与胶囊统一外观](island-glass-appearance.md) | `Accepted / Verifying` | 仅液态玻璃显示浅色/深色/自动三选项，底栏与胶囊统一；设置分组、自动跟随和偏好持久化，视觉待用户验收。 |
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

- [灵动岛显示位置](island-display-placement.md)：QV-PRODUCT-ISLAND-DISPLAY-001，已实现，待用户多屏验收。
