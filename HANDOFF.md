# QuotaView 开发交接

## Windows 0.8.3-win.13 正式发布（2026-10-31）

公开稳定版、不可变资产与回滚事实见 [版本历史](VERSION_HISTORY.md#当前最新版本)。源码 PR #118、#120 已合入 main；终态去重、设置精简及自动更新默认开启一并交付，明确关闭偏好保留。独立 Windows 签名 appcast 更新到 win.13，保留 win.10 回滚项；README 仅更新链接，macOS 通道不变。发布说明中英双语。

55 项业务回归、30 项更新专项、原生和最终包冒烟及发布提交两平台 CI 通过。运行开发包已切至 Windows/webview2/build/development-runtime-win13/QuotaView.Native.exe，版本 win.13、PID 38644，后台代码与本次构建哈希一致；现有用户数据、旧目录及正式安装保留。报告者现场与视觉/真实升级体验待用户验收。下方 win.11/12 的未发布描述仅为历史阶段，当前状态以上文为准。

## Windows 设置精简 0.8.3-win.12（2026-10-31）

设置页继续移除常驻说明，以明确标题、控件及连接状态表达用途；详情默认折叠，操作相关提示按需出现。前端与原生开发编译通过，独立开发运行入口切至 win.12；继承上一轮 Issue #114 修复。当前运行路径与验收边界见 [Windows Handoff](Windows/HANDOFF.md)。源码尚未推送，公开版本不变。

## Windows 本地修复 0.8.3-win.11（2026-10-31）

[Issue #114](https://github.com/Duoasa/QuotaView/issues/114) 的通知与完成展开按轮次去重，Codex 重复会话、轮次身份和断线终态回退已修复，兼容旧归档；设置页精简重复说明。24 项定向检查与 8 项原生适配检查通过，独立开发运行包已启动。源码尚未提交或推送，正式版与 appcast 不变；具体运行路径、证据及待用户验收范围见 [Windows Handoff](Windows/HANDOFF.md#本地开发版-083-win112026-10-31)。

公开稳定版：[版本历史](VERSION_HISTORY.md#当前最新版本)。

## 当前开发：0.9.1 Build 3 / 重置卡到期日期（2026-11-01）

Codex 重置页在次数下方显示到期日期与时分，多张卡显示最近到期的一张；接口未返回日期显示「未提供」，零次数或次数未知隐藏。与消费选择共用有效卡片筛选，支持六种语言及系统时区，不从额度恢复时间推算。详见[重置规格](docs/specs/codex-quota-reset.md#重置卡到期日期2026-11-01091-build-3)。

16 项隔离重置冒烟、708 个源码模板/728 条目录文案的本地化检查通过。2026-11-01T17:09:34.502648+08:00 已完成 Debug arm64 增量构建并更新开发包，PID 18611，0.9.1 Build 3 / 内部 136；254 个生产输入、18 项资源、App/Widget 身份、完整包与实际加载路径匹配，旧包已备份，正式安装保持。证据 `.build/reset-expiry-091b3-runtime/`。仅本地开发，未提交、推送或发布；未消耗真实重置卡，视觉与交互由用户验收。

## 前序开发：0.9.1 Build 2 / 公告直接加载 PNG（2026-11-01）

2026-11-01 本批源码已按用户授权经 [PR #126](https://github.com/Duoasa/QuotaView/pull/126) 合入 main `d4b5557d5f6b0c8e1f416e90982e4d62f94b4422`，源码提交 `768ac0f9dd086f3ea670a9fc1ee05e134c8408d3`。[PR CI 41285622270](https://github.com/Duoasa/QuotaView/actions/runs/41285622270) 与精确 [main CI 41285953015](https://github.com/Duoasa/QuotaView/actions/runs/41285953015) 均成功，各 750 项测试、7 跳过、0 失败及 44 项契约检查通过。254 个生产输入与合并提交及当前 0.9.1 Build 2 运行包一致，工作区已快进；证据 `.build/source-integration-091b2/`。未创建 Release/tag 或更新 appcast。下方“仅本地”是历史阶段事实；合并结果补记保留本地，无关未跟踪文件保留。

用户反馈公告图标毛边并要求直接使用 PNG。公告现在独立读取随包 `QuotaViewAppIcon.png`，不再使用资产目录/ICNS 图像表示，采用原色、高质量插值，移除额外阴影，保留 64 pt 大小及用户原图高光。PNG 与现有原始素材逐字节一致，Xcode 与 SwiftPM 均声明该独立资源；关于页及其他图标入口未改动。

2026-11-01T15:34:50.862814+08:00 已构建并启动 0.9.1 Build 2 / 内部 135，PID 97346；254 输入、18 项编译资源、原始 PNG、完整包与实际加载路径一致，正式安装哈希保持。3 项公告策略冒烟及运行包 PNG 解码/透明通道/1024 像素和原图哈希核验通过；证据 `.build/announcement-png-091b2-runtime/`。仅本地修改，未推送或发布；实际视觉由用户检查。

## 前序开发：0.9.1 Build 1 / 精简更新公告（2026-11-01）

用户审核并批准五项精简公告：全新外观、设置体验、Agent 接入（预览）、多语言支持、重置保护；已写入现有「亮点 / 改进 / 新功能」分组，替换旧的公告使用说明与品牌预告，保留窗口布局和按版本提醒策略。公告通过 AppCopy 与随包翻译覆盖六种语言。用户明确将开发版升级到 0.9.1，产品 Build 重置为 1、内部序号递增至 134；App、Widget 和兼容 Info.plist 同步，开发身份与数据保持。

2026-11-01T15:30:05.202895+08:00，Debug arm64 增量构建成功并更新启动开发包，PID 93844；253 输入、18 项编译资源、六语言资源、完整包与实际加载路径一致，正式安装哈希保持。证据 `.build/announcement-091b1-runtime/`。本地化目录校验及 3 项公告策略冒烟通过；未执行 UI 自动验收。公告正式自动展示名单仍为内部 102，本轮仅更新开发内容，不追加 Release/appcast 准入，不推送或发布。

## 前序开发：0.8.7 Build 31 / 实际链路与 OpenCode 完成修复（2026-11-01）

用户追问「能做到可以使用吗」，本轮进一步验证真实调用链。本机未找到 Cursor、Gemini CLI、OpenCode、Copilot CLI 程序；仅发现 Gemini 配置目录。没有将上一批夹具当成真实客户端已可用。

从官方发布下载 OpenCode 1.19.5 到隔离测试目录，使用独立配置/缓存/数据目录与 localhost 确定性模型响应，未使用真实账号额度。真实客户端自动加载生产插件、产生真实会话和任务事件，首次发现回答完成但岛卡仍在 thinking：其事件分派不等待插件，进程退出截断异步队列。修复为终态通过私有辅助程序同步排空最多 257 条事件，ACK 校验、1.5 秒上限，重发在途消息按 epoch/sequence 去重，不影响工具或审批决定。

修复后官方客户端到任务卡模型的状态为 thinking → completed。未改动插件的最终实测成功；另有立即 process.exit 的回归冒烟通过。三个命令 Hook 由安装器真实写配置并启动辅助程序，经过生产 listener/runtime，验证开始/完成、来源身份隔离、停用只撤下对应任务。共 7 个相关用例最终通过（4 个原扩展 + 3 个新增运行链路），其中官方客户端用例按环境变量显式开启；没有跑完整回归或 UI 自动化。证据 `.build/agent-usable-087b31/`，可重复的本地模型脚本 `Tests/Fixtures/agent-integrations/run_opencode_smoke.py`。

2026-11-01T14:54:34.946957+08:00 已构建并启动 0.8.7 Build 31 / 内部 133，PID 74867；253 输入、18 资源、App/Widget 身份、完整包与加载路径一致，证据 `.build/agent-usable-087b31-runtime/`。四个接入开关仍由用户启用。Cursor、Gemini CLI、Copilot CLI 尚无真实客户端/账号任务结论；OpenCode 已验证官方客户端任务状态链路，模型服务由本地夹具提供，不等同订阅认证、额度或完整工具/审批路径验收。视觉由用户检查。本轮未推送/发布，正式安装保留。

## 前序开发：0.8.7 Build 30 / 四个 Agent 与官方图标（2026-11-01）

按用户「接入，使用官方 icon」要求新增 Cursor、Gemini CLI、OpenCode、GitHub Copilot CLI，沿用现有 Agent 接入列表、独立开关和本地事件连接。四来源默认关闭；启用后重启对应客户端。采用官方品牌 SVG 与 GitHub Primer Copilot 矢量，原色离线打包并附来源/许可证。没有增加虚构额度或进度，权限仍在原客户端处理；OpenCode 依据当前稳定版 v1.19.5 插件 API，2.x 预览未承诺兼容。详细行为与限制见[Agent 接入规格](docs/specs/agent-integrations.md#四来源扩展2026-11-01087-build-30)。

4 项新增隔离冒烟通过，覆盖配置保留/重复启停/非法配置保护、官方事件白名单与隐私过滤、OpenCode 12 条实际 socket 消息、子任务与错误终态隔离；既有 DSH 插件 1 项冒烟通过。运行包中的辅助程序通过 4 路真实 IPC 夹具及坏路由中性输出检查。首次 IPC 脚本误指旧 SwiftPM 输出目录，已改指实际运行包；最终验证不是基于旧二进制。证据 `.build/agent-expansion-087b30/`。

Debug arm64 增量构建与启动冒烟通过，2026-11-01T14:35:29.154127+08:00 已更新开发包，PID 67850，0.8.7 / Build 30 / 内部 132；253 个生产输入、18 项预览/来源资源、完整包、App/Widget 身份及实际加载路径一致。证据 `.build/agent-expansion-087b30-complete-runtime/`。仅本地开发，未提交/推送/发布；正式安装和既有用户配置保留。真实客户端任务与视觉/交互由用户验收，没有执行真实账户任务或消费重置卡。

## 前序开发：0.8.7 Build 29 / 退出行右侧图标（2026-11-01）

按用户最新截图要求，在「退出 QuotaView」右侧添加红色 `power` 图标，13 pt Semibold、20 pt 槽位，与卡片内边距右对齐；保留整行点击和确认流程，图标不重复朗读。详见[退出入口右侧图标](docs/design/QUOTAVIEW_UI_RULES.md#退出入口右侧图标2026-11-01087-build-29)。

Debug arm64 增量构建与启动冒烟通过，2026-11-01T13:13:45.682640+08:00 已更新开发运行包，PID 39452，0.8.7 / Build 29 / 内部 131；241 输入、完整包、App/Widget 身份及实际加载路径一致。证据 `.build/quit-trailing-icon-087b29-runtime/`。仅局部图标调整，未新增重复实现测试或执行 UI 验收；实际视觉由用户检查。本批已通过 [PR #125](https://github.com/Duoasa/QuotaView/pull/125) 合入 main `267aff00fb7883b608c165ad046438b493ce70cc`，源码提交 `ec06ee99e6f404f358cbe522fe9844348db6fdda`。[PR CI 41276737653](https://github.com/Duoasa/QuotaView/actions/runs/41276737653) 与 [main CI 41276987516](https://github.com/Duoasa/QuotaView/actions/runs/41276987516) 均成功，各 743 项测试、6 跳过、0 失败及 44 项契约检查通过。241 个生产输入与合并提交及当前 Build 29 一致，工作区已快进；证据 `.build/source-integration-087b29/`。合并结果补记保留本地，原有未跟踪文件保持，正式安装与发布通道保持。

用户随后明确重置卡优先使用最接近到期日的卡。现有生产实现已经按到期时间升序选取可用卡，未提供到期日期的排后；结果未知的重试固定原卡。补充多卡乱序与重试保护测试，3 项隔离冒烟通过，证据 `.build/reset-expiry-priority-087b29/smoke.log`；见[重置规则](docs/specs/codex-quota-reset.md)。没有调用真实消费接口；仅测试和规则补充，运行包继续为 Build 29。

## 前序开发：0.8.7 Build 28 / 设置固定宽度与完成配色恢复（2026-11-01）

设置窗口按用户指定固定为 820 pt，禁止横向调整，最大化按钮置灰，原生窗口禁用 zoom、全屏和系统平铺扩张，保留纵向调整。完成态恢复原紫—蓝—青高光及紫/青外辉光，保留 6 秒循环；前序四种新增语言、32 pt 代理输入框、非聚焦卡片淡色与深黑侧栏保持。详见[界面规则](docs/design/QUOTAVIEW_UI_RULES.md#设置固定宽度与完成配色回调2026-11-01087-build-28)与[完成态配色契约](docs/specs/PROGRESS_EFFECT_ADAPTATION.md#087-build-28恢复原完成配色2026-11-01)。

5 项相关冒烟与 Debug arm64 增量构建通过。2026-11-01T03:42:22.907872+08:00 已更新开发运行包，PID 92757，0.8.7 / Build 28 / 内部 130；241 输入、完整包及实际加载路径一致。证据 `.build/settings-fixed-width-087b28/smoke.log`、`.build/settings-fixed-width-087b28-runtime/`。仅编译和冒烟，视觉与交互由用户检查。

本批 Build 25–28 已通过 [PR #124](https://github.com/Duoasa/QuotaView/pull/124) 合入 main，源码提交 `6da89de5f1a92a4aa81ddac8ec64ee4d062c4e3e`，合并提交 `14f51937af6e2b3124905f032d46ba88017d35cf`。[PR CI 41235821503](https://github.com/Duoasa/QuotaView/actions/runs/41235821503) 与精确 [main CI 41236289809](https://github.com/Duoasa/QuotaView/actions/runs/41236289809) 均成功，各 741 项测试、6 跳过、0 失败及 44 项契约检查通过。241 个生产输入与源码提交、合并提交及当前 Build 28 运行包逐项一致；工作区已快进到合并提交。证据 `.build/source-integration-087b28/`。合并结果补记保留本地，原有未跟踪文件保持；前序“仅本地”是当时阶段事实。未发布 Release、tag 或 appcast，未替换正式安装或消耗真实重置卡。

## 前序开发：0.8.7 Build 27 / 完成描边、状态着色与深色侧栏（2026-11-01）

按本轮三项要求：完成高光改为蓝—青—绿闭合渐变，6 秒循环，轮廓不移动、描边亮度不脉冲，蓝/绿外辉光保留呼吸；非聚焦卡片从 AI 球实际配色取得淡化状态底色，聚焦任务特效保持；设置左栏保留材质并叠加 60% 中性黑色，覆盖顶部与底部。详见[完成态契约补充](docs/specs/PROGRESS_EFFECT_ADAPTATION.md#087-build-27完成态蓝青绿流动描边2026-11-01)和[界面规则](docs/design/QUOTAVIEW_UI_RULES.md#完成描边非聚焦着色与深色侧栏2026-11-01087-build-27)。

7 项定向冒烟通过，覆盖色环闭合、重复更新不重启、状态切换与隐藏停播、Reduce Motion、宿主离窗、旧缩略分支与淡色卡片。Debug arm64 增量构建通过，2026-11-01T03:38:18.710130+08:00 已更新开发运行包，PID 88677，0.8.7 / Build 27 / 内部 129；241 输入、完整包与实际加载路径一致。证据 `.build/completion-flow-087b27/smoke.log`、`.build/completion-flow-087b27-runtime/`。用户再次明确只做冒烟，实际视觉/交互由其检查；没有截图或 UI 自动验收。本批仅本地修改，未推送、发布或替换正式安装。

## 前序开发：0.8.7 Build 26 / 代理输入框高度（2026-11-01）

地址与端口输入框统一增高至 32 pt，13 pt 系统字、10 pt 水平内边距，背景和焦点边框覆盖完整输入高度。保留原宽度及右侧对齐、输入绑定、禁用状态与六语言辅助功能。规则见[代理输入框高度](docs/design/QUOTAVIEW_UI_RULES.md#代理输入框高度2026-11-01087-build-26)。

Debug arm64 增量构建通过，2026-11-01T03:29:42.323662+08:00 更新并启动开发包，PID 83982，0.8.7 / Build 26 / 内部 128；241 个生产输入、完整包与加载路径一致。翻译资源检查通过；仅局部布局修改，不增加重复单元测试。证据 `.build/settings-input-height-087b26-runtime/`。本批仅本地，未推送或发布；实际视觉和交互由用户验收。

## 前序开发：0.8.7 Build 25 / 四种新增语言（2026-11-01）

按用户更正新增**日语、韩语、繁体中文、西班牙语**，保留简体中文与 English。通用 → 语言提供原生名称与跟随系统，偏好跨重启保留；设置、任务、权限、用量、重置和辅助功能文案及小组件共用翻译资源。动态参数与模板分离，繁体转换只作用于应用文案，任务原文、命令、账户名及路径保持原样。实际语言传递到灵动岛、悬浮胶囊和内容测量；详见[多语言规格](docs/specs/app-localization.md)。

14 项定向冒烟通过，708 个源码模板覆盖、715 条目录文案的日/韩/西翻译与占位符检查通过。Debug arm64 增量构建完成，2026-11-01T00:57:44.271094+08:00 已更新开发运行包，PID 77192，0.8.7 / Build 25 / 内部 127；241 个生产输入、完整包、加载路径和主程序/小组件翻译资源一致。证据 `.build/localization-087b25/`、`.build/localization-087b25-runtime/`。本批仅本地修改，未提交、推送或发布；上一批 PR #123 已合入 main。未消耗真实重置卡，正式安装不变；翻译显示长度、视觉与交互由用户检查。

## 前序开发：0.8.7 Build 24 / 预览背景明暗联动（2026-11-01）

按用户后续要求，灵动岛预览壁纸随实际玻璃外观变暗/变亮：深色叠加 42% 黑色，浅色叠加 14% 白色；自动复用系统外观解析，经典材质沿用深色回退。不改变任务卡、文字、图标及真实岛体，不修改壁纸文件。减少动态时取消 0.16 秒色调过渡。

Debug arm64 增量构建通过，2026-11-01T00:26:28.052931+08:00 已更新并启动开发包 PID 60063，0.8.7 / Build 24 / 内部 126；239 输入、14 资源、完整包与加载路径一致。证据 `.build/settings-preview-tone-087b24-runtime/`。已由 [PR #123](https://github.com/Duoasa/QuotaView/pull/123) 合入 main `93888fda0c368c56cea8c507e65d5ee95c6bfcfb`，PR 源码 `462380dad18ef17ac62915df55ba8dda74b4470e`。PR [CI 41219772256](https://github.com/Duoasa/QuotaView/actions/runs/41219772256) 与精确 main [CI 41220041828](https://github.com/Duoasa/QuotaView/actions/runs/41220041828) 均通过（各 731 测试、6 跳过、0 失败，44 契约检查），239 运行输入与合并提交一致；集成证据 `.build/source-integration-087b24/`。视觉/滚动手感由用户验收，未发布 Release/appcast。

## 前序开发：0.8.7 Build 23 / 系统滚动边缘分层（2026-11-01）

用户反馈 Build 22 仍为纯色面板。确认本机 Reduce Transparency / Increase Contrast 均关闭；macOS 26+ 改为系统 safeAreaBar 固定预览与 scrollEdgeEffectStyle(.soft)，由系统在滚动内容与固定栏之间处理模糊边界，不在此路径叠加自绘背景。旧系统继续走兼容分支。保留 28 pt 下边距、左栏顶部 12 pt 留白、同一滚动可用宽度，以及 Build 17–22 的设置、图标加载和重置保护。实际视觉与滚动效果仍由用户验收。

Debug arm64 增量构建通过，2026-11-01T00:22:05.152130+08:00 已更新并启动开发包 PID 52533，0.8.7 / Build 23 / 内部 125；239 输入、14 资源、完整包与加载路径一致。证据 `.build/settings-native-scroll-edge-087b23-runtime/`。

用户已明确授权完成后将当前代码推送 GitHub 并合并 main，本批按 Build 23 集成；保留无关未跟踪文件，不发布 Release/appcast、不替换正式安装。集成证据 `.build/source-integration-087b23/`，PR 与精确 main CI 结果完成后回填。前序「仅本地」为阶段记录。

## 前序开发：0.8.7 Build 22 / 原生磨砂与设置图标渲染（2026-11-01）

用户再次指出磨砂未出现，已将 SwiftUI regularMaterial + mask 改为明确 `.withinWindow` 混合、`.headerView` 材质和 `.active` 状态的 NSVisualEffectView，由原生 alpha 随滚动渐显，不对材质施加 SwiftUI opacity/mask。减少透明度仍回退系统底色。预览下边距从 12 增至 28 pt，左栏红绿灯区域下方新增 12 pt 留白；Build 21 的原生滚动量与可用宽度对齐继续保留。磨砂实际呈现、对齐和间距等待用户验收。

用户澄清原 PNG 的均匀高光应保留，仅修正设置中的突兀横线。关于页此前优先读取仅有较小表示的 ICNS，现优先读取原始 QuotaViewAppIcon PNG 资源；96 pt 尺寸保持。全部 15 项图标资源与 Build 16 合并源码逐字节一致。图像试修未采用，没有替换原图或修改用户文件。

Debug arm64 增量构建与 3 项定向设置检查通过（原生材质、滚动容器和页面路由），2026-11-01T00:15:07.442560+08:00 已更新并启动开发包 PID 45704，0.8.7 / Build 22 / 内部 124；239 输入、14 资源、完整包与加载路径一致，正式安装未变。证据 `.build/settings-native-frost-087b22-runtime/`。仅本地，未推送/发布；重置保护继续生效，真实卡未消费。

## 前序开发：0.8.7 Build 21 / 重置保护与滚动层修正（2026-11-01）

用量显示新增「禁用重置卡使用」，默认关闭、独立持久化。开启时 Codex 重置与确认按钮禁用，撤销未提交的确认；协调器在发送前再次读取策略。已发送的操作继续核对结果，待确认幂等记录保留；Claude 复制命令保持原逻辑。仅使用隔离模拟服务验证，未消费用户重置卡。规格见 [重置保护](docs/specs/codex-quota-reset.md#禁用重置卡使用2026-11-01087-build-21)。

用户指出 Build 20 的磨砂未出现、两层横向偏移后，改用原生 NSScrollView/NSClipView 通知读取滚动量与实际可用宽度，按同一宽度排列预览与内容，处理常驻滚动条占位；滚动 0–48 pt 渐显原生磨砂背景，底部渐隐。原生容器夹具核验了滚动量、滚动条宽度与观察停止。视觉和滚动手感由用户继续验收，不将夹具结果等同实机视觉通过。

Debug arm64 增量编译、15 项定向测试（12 项重置、3 项设置）通过。2026-11-01T00:07:44.784807+08:00 已更新并启动开发包，PID 41873，0.8.7 / Build 21 / 内部 123；239 输入、14 资源、完整包和实际加载路径一致，正式安装未变。证据 `.build/reset-protection-scroll-087b21-runtime/`。本批保留本地，未推送、合并或发布。

## 前序开发：0.8.7 Build 18–20 / 固定预览、归类与侧栏（2026-10-31—2026-11-01）

Build 18 将交互与隐私及屏幕设置移回通用页；连接改为 Agent 接入与实心芯片图标，公告改为实心布告板式图标，关于页新增 GitHub 仓库入口。固定 210 pt 预览于滚动内容上方。增量构建、2 项定向冒烟通过，证据 `.build/settings-pinned-087b18-runtime/`。

Build 19 恢复液态玻璃/经典纯色两个独立材质选项（标题、说明及选择标记），增加随滚动渐显的磨砂背景；用户后续反馈的滚动/对齐问题已由 Build 21 修正。Build 20 侧栏改为四色：灰色通用/代理/关于，蓝色灵动岛/Agent 接入，紫色用量，橙色反馈。Build 20 增量编译、3 项定向冒烟及运行包核验通过，证据 `.build/settings-sidebar-colors-087b20-runtime/`。此批仅本地，视觉由用户验收。

## 前序开发：0.8.7 Build 17 / 设置分组与紧凑选项（2026-10-31）

完成 Build 16 的 GitHub 合并后，按用户 macOS 设置参考调整本地设置页：玻璃外观与任务特效采用左标题、右侧 276 pt 缩略选项；材质改为同行分段选择。灵动岛重组为外观、布局与显示、交互与隐私，屏幕跟随/固定屏幕从通用移至布局组；设置卡片和反馈/退出行使用圆角底色，保留组内细分隔与选中轮廓。左栏组内 4 pt、组间 20 pt，移除导航分组及栏间分割线。功能图标保持单色圆角底托，退出仍为纯文字。

Debug arm64 增量编译及 3 项定向冒烟通过；2026-10-31T23:53:09.347232+08:00 已更新并启动开发包，PID 32981，0.8.7 / Build 17 / 内部 119。239 输入、14 资源、完整包和实际加载路径核对一致，正式安装未变。证据 `.build/settings-layout-087b17-runtime/`；没有主动 UI 操作或截图，实际视觉由用户验收。本批只保留本地修改，未沿用上一批 GitHub 推送授权。

## 前序开发：0.8.7 Build 16 / 最新图标替换（2026-10-31）

Build 16 / 内部 118 已由 [PR #122](https://github.com/Duoasa/QuotaView/pull/122) 合入 main `57864ea448cc3936d2cba419e504cca6f1797552`，PR 源码 `6c226a3945d15348cd678b6ae0cf442f246689e8`。PR [CI 41216313923](https://github.com/Duoasa/QuotaView/actions/runs/41216313923) 与精确 main [CI 41216625276](https://github.com/Duoasa/QuotaView/actions/runs/41216625276) 均成功，各 727 测试、6 跳过、0 失败，44 契约检查；239 项运行输入与合并源码一致。保留 main 的 Windows 更新与无关本地文件，未发布。证据 `.build/source-integration-087b16/`。下方未提交描述为此前阶段记录。

按用户新文件 `QV-icon-iOS-Solid@1x.png` 替换 AppIcon 全尺寸及应用内图标，同步现有 Dock 临时预览，保留关于布局，不操作窗口。2026-10-31T23:23:51.771595+08:00，开发包更新启动 PID 16048；239 输入、14 资源、完整包及加载路径核对通过。证据 `.build/app-icon-087b16-runtime/`，Dock 预览记录 `.build/current-dock-icon-preview.json`。仅本地，未提交/推送/发布，正式安装保持。

2026-10-31：按用户要求清理 Dock 临时程序，5 个独立预览目录已移至废纸篓，预览进程已全部退出；当前开发版与正式安装的身份、可执行文件和图标哈希保持不变，开发版继续运行。清理清单与恢复路径见 `.build/dock-icon-preview-cleanup-20261031/`；当前 Dock 预览记录已标记 cleanedUp。

## 前序开发：0.8.7 Build 15 / 最新图标替换（2026-10-31）

按用户新文件 `QV-icon-iOS-Default-1024-2@1x.png` 替换 AppIcon 全尺寸及应用内图标，同步现有 Dock 临时预览，保留关于布局，不操作窗口。2026-10-31T23:21:21.456870+08:00，开发包更新启动 PID 15116；239 输入、14 资源、完整包及加载路径核对通过。证据 `.build/app-icon-087b15-runtime/`，Dock 预览记录 `.build/current-dock-icon-preview.json`。仅本地，未提交/推送/发布，正式安装保持。

## 前序开发：0.8.7 Build 14 / 最新图标替换（2026-10-31）

按用户最新同名 PNG 替换 AppIcon 全尺寸与应用内图标；仅更新当前开发包及 Dock 预览，不操作设置或其他窗口。2026-10-31T23:14:30.462925+08:00，开发包更新启动 PID 13496，239 输入、14 资源、完整包及加载路径核对通过。保留现有关于布局；证据 `.build/app-icon-087b14-runtime/`。独立 Dock 预览已同步同一编译图标资源，记录 `.build/current-dock-icon-preview.json`。仅本地，未提交/推送/发布。

## 前序开发：0.8.7 Build 13 / App 图标再次更新与 Dock 预览（2026-10-31）

用户更新同名图标 PNG 后，已重新生成所有 AppIcon 尺寸及应用内图标资源；文件哈希已确认改变。保留关于页 96 pt 图标、构建日期与版权布局。2026-10-31T23:05:57.062402+08:00，Debug arm64 增量构建通过，开发包已更新启动 PID 10332；239 输入、14 资源、完整包与加载路径核对通过。证据 `.build/app-icon-087b13-runtime/`，素材规格见[App 图标试装](docs/design/quotaview-app-icon.md)。

旧 Dock 预览已退出，新独立预览 `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget/.build/dock-icon-preview-20261031-230644/QuotaView Icon Preview.app` 已启动，使用 Build 13 的 ICNS 与 Assets.car；不含 QuotaView 业务逻辑。用户表示已看到效果、不需要继续打开窗口，已停止 UI 操作，保留开发版及预览供查看。当前记录 `.build/current-dock-icon-preview.json`。仅本地，未提交/推送/发布，正式安装保持。

## 前序开发：0.8.7 Build 12 / 关于信息补全与图标放大（2026-10-31）

按用户参考图将关于图标由 64 pt 放大至 96 pt，补齐「构建于」日期和与 LICENSE 一致的 `© 2026 Duoasa`；日期来自当前包可执行文件时间并按应用语言显示，版权来自 Info.plist。保持名称、说明、真实版本号和纯色居中布局。规范见[关于页信息补全](docs/design/QUOTAVIEW_UI_RULES.md#关于页信息补全2026-10-31087-build-12)。2026-10-31T22:51:07.810836+08:00，Debug arm64 增量构建通过，开发包已更新启动 PID 7016；239 输入、14 资源、完整包、元数据和实际加载路径核对一致。证据 `.build/about-info-087b12-runtime/`。仅本地，未提交/推送/发布，正式安装保持；视觉由用户检查。

用户随后要求查看 Dock 效果，已创建并启动独立临时应用 `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget/.build/dock-icon-preview-20261031-225252/QuotaView Icon Preview.app`，Bundle ID `com.quotaview.icon-dock-preview`，PID 7849，常规 Dock 应用；图标 ICNS 与 Assets.car 和 Build 12 逐字节一致。预览仅运行最小 AppKit 主循环与退出菜单，不含 QuotaView 业务、连接、Hook 或数据访问。保留运行供用户查看，可右键 Dock 图标退出；记录 `.build/current-dock-icon-preview.json`。

## 前序开发：0.8.7 Build 11 / App 图标素材更新（2026-10-31）

按用户新图 `QV-icon-iOS-Default-1024@1x.png` 更新 AppIcon 全部尺寸及应用内图标资源，保留 Build 10 关于页纯色居中布局。素材原样缩放，1024 px 主资源与原图一致；图标编译尺寸 16–1024 px 核对通过。规格见[App 图标试装](docs/design/quotaview-app-icon.md)。2026-10-31T22:48:49.520740+08:00，Debug arm64 增量构建通过，开发包已更新启动 PID 5499；239 输入、14 项既有资源、完整包与加载路径一致。证据 `.build/app-icon-087b11-runtime/`。仅本地更新，未提交/推送/发布，正式安装保持，视觉由用户查看。

## 前序开发：0.8.7 Build 10 / 关于页纯色居中布局（2026-10-31）

按用户参考图移除关于页顶部壁纸横幅与重复页标题，图标、名称、说明和真实版本信息在系统纯色背景上居中纵向排列；保留更新与公告操作区。图标没有额外阴影或描边，原图上下边缘高光保持。规范见[关于页纯色与居中布局](docs/design/QUOTAVIEW_UI_RULES.md#关于页纯色与居中布局2026-10-31087-build-10)。2026-10-31T22:40:49.979324+08:00，Debug arm64 增量构建通过，开发包已更新启动 PID 3289；239 输入、14 项既有资源、完整包及加载路径核对一致。证据 `.build/about-layout-087b10-runtime/`。局部布局未新增重复实现测试、未做 UI 自动验收，实际效果由用户检查。本次仅本地，未提交/推送/发布，正式安装保持。

## 前序开发：0.8.7 Build 9 / 用户 App 图标试装（2026-10-31）

按用户提供的 `QV-icon-1024@1x.png` 替换 AppIcon 全部 macOS 尺寸，同步应用内 App 图标备用资源；原图造型、颜色与透明边缘保留。规格见[App 图标试装](docs/design/quotaview-app-icon.md)。2026-10-31T22:34:12.732838+08:00，Debug arm64 增量构建通过，开发包已更新并启动 PID 99340；239 输入、14 项既有资源、图标 16–1024 px 编译资源、完整包及实际加载路径核对通过，无临时预览参数。证据 `.build/app-icon-087b9-runtime/`。视觉由用户查看，本次仅本地试装，未提交/推送/发布，正式安装保持。

## 前序开发：0.8.7 Build 8 / 标签图标尺寸与原色（2026-10-30）

按用户反馈将用量标签圆底缩至 16 pt、标志 11 pt，左内距 4 pt 保持与 24 pt 胶囊左端同心。取消未选中图标降透明度，将玻璃移至独立背景层，图标以原色绘于上层；重置卡保留发行版灰色渐变。规格见[来源图标](docs/design/quotaview-provider-icons.md)。17:21（上海）0.8.7 / Build 8 / 内部 110 Debug arm64 增量构建成功，开发包已更新启动 PID 76809；239 输入、14 资源、完整包/旧包与实际加载路径核对通过，无临时参数，正式安装保持。仅绘制修订，未新增或重复功能测试；diff 检查通过。证据 `.build/provider-capsules-087b8-runtime/`。

2026-10-30 17:28（上海），本轮源码已通过 [PR #117](https://github.com/Duoasa/QuotaView/pull/117) 合入 main：最终源码 `4ea4167db9310182d27ffdeca970a03a2a762500`，合并 `6c3f55fe26fb6b1172156fd801c82c91b1992865`。[PR CI 41032932756](https://github.com/Duoasa/QuotaView/actions/runs/41032932756) 与 [main CI 41033704295](https://github.com/Duoasa/QuotaView/actions/runs/41033704295) 均成功，各 727 项测试、6 跳过、0 失败及 44 项契约检查通过。239 项生产输入与源码提交、合并提交及当前 Build 8 运行包逐项一致，无需重建。证据 `.build/source-integration-087b7/`（目录沿用初次集成命名，最终记录为 Build 8）。工作区已快进到合并提交，原有未跟踪文件保持；合并后结果补记保留本地。未发布 Release、tag 或 appcast，正式安装保持，视觉由用户验收。

## 前序开发：0.8.7 Build 7 / 标签圆底与重置卡恢复（2026-10-30）

用量标签的 Agent 图标改为 18 pt 圆底，24 pt 胶囊的左内距由半径差计算为 3 pt，使两者同心；Codex 白底黑标，Claude 橙底白标。重置卡按用户最新要求逐字节恢复 `v0.8.6-build.21` 灰色渐变原始素材。Build 6 曾临时改为黑标并更新本地包，已由本批覆盖，未单独提交。规格见[来源图标](docs/design/quotaview-provider-icons.md)。

17:16（上海）0.8.7 / Build 7 / 内部 109 Debug arm64 增量编译成功，开发包已更新启动 PID 73983；239 输入、14 资源、完整包/旧包及实际加载路径核对通过，无临时参数。重置素材与稳定 tag 逐字节一致；本批绘制修改未新增/重复功能测试，既有设置行对齐冒烟通过。证据 `.build/provider-capsules-087b7-runtime/`。用户已授权本轮 0.8.7 源码推送 GitHub 并合入 main，正在执行源码审查与集成；此前各批“未提交/推送”保留为阶段事实。发布、appcast 与正式安装不在本轮范围内，视觉由用户验收。

## 前序开发：0.8.7 Build 5 / 退出入口仅文字（2026-10-30）

按用户要求移除退出行图标和占位，保留文字、危险动作样式、行高及确认流程；其他设置图标保持。规格见[退出入口](docs/design/QUOTAVIEW_UI_RULES.md#退出入口仅保留文字2026-10-30087-build-5)。16:16（上海）0.8.7 / Build 5 / 内部 107 Debug arm64 增量构建成功，开发包已更新启动 PID 66649；239 输入、14 资源、完整包/备份和实际加载路径核对通过，正式安装未变。仅移除装饰图标，未新增或重复功能测试；视觉由用户检查。运行证据 `.build/quit-text-087b5-runtime/`。本批仅本地修改，未提交、推送或发布。

## 前序开发：0.8.7 Build 4 / 设置图标圆角底托（2026-10-30）

按用户 macOS 设置参考，子页面功能图标改为灰色圆角矩形底托与白色单色符号，覆盖页标题、设置行、反馈和退出入口。复用侧栏图标组件，保留 20 pt 槽位、原排版与分组间距；官方品牌素材保持。具体规则见[设置图标规范](docs/design/QUOTAVIEW_UI_RULES.md#单色图标保留圆角底托2026-10-30087-build-4)。

16:12（上海）0.8.7 / Build 4 / 内部 106 Debug arm64 增量构建成功，开发运行包已更新启动 PID 65079。239 输入、14 资源、完整包/旧包备份与实际加载路径核对通过，无临时参数，正式安装未变。证据 `.build/settings-icon-tiles-087b4-runtime/`；备份 `.build/runtime-package-backups/settings-icon-tiles-087b4-20261030-161250/QuotaView.app`。仅绘制和退出图标排版调整，未新增或重复运行功能测试；diff 检查通过。本批仅本地修改，未提交、推送或发布；视觉由用户验收。

## 前序开发：0.8.7 Build 3 / 设置排版与单色图标（2026-10-30）

按用户要求统一设置子页面排版：功能图标使用无彩底单色符号，设置框统一宽度、圆角、内距和基础行高；页顶/分组 24、组内 12、标题间距 8，普通/说明行最小高 44/56。玻璃选项标题和内距统一，连接详情框左右对齐。官方品牌标识保持上一批素材。具体边界见[设置规范](docs/design/QUOTAVIEW_UI_RULES.md#子页面单色图标与统一间距2026-10-30087-build-3)。

16:08（上海）0.8.7 / Build 3 / 内部 105 Debug arm64 增量构建成功，开发包已更新启动 PID 62834。239 输入、14 资源、完整包与旧包、实际加载路径核对通过，无临时参数，正式安装保持。既有设置行控件对齐冒烟 1 项通过，0 失败，日志 `layout-smoke.log`。证据 `.build/settings-layout-087b3-runtime/`；备份 `.build/runtime-package-backups/settings-layout-087b3-20261030-160846/QuotaView.app`。视觉与交互由用户验收；本批仅本地修改，未提交、推送或发布。

## 前序开发：0.8.7 Build 2 / 官方来源图标（2026-10-30）

按用户修订，Claude 使用官方应用包内橙底白色图标，截图仅作样式参考。任务卡、子任务、连接设置和普通来源图标共用；ChatGPT/Codex 用量与重置卡切换官方应用内 Blossom 矢量路径，现有官方任务应用图标保留。来源、哈希及覆盖范围见[图标规格](docs/design/quotaview-provider-icons.md)。

15:53（上海）0.8.7 / Build 2 / 内部 104 Debug arm64 增量构建成功，开发运行包已更新启动 PID 59363，无临时参数。239 输入、14 资源、完整包与旧包备份、实际加载路径核对通过；四项 AppKit 资源解码冒烟及官方路径/PNG 一致性检查通过。证据 `.build/provider-icons-087b2/` 和 `.build/provider-icons-087b2-runtime/`；备份 `.build/runtime-package-backups/provider-icons-087b2-20261030-155346/QuotaView.app`。正式安装保持，视觉由用户验收，未新增/运行完整功能测试或 UI 自动验收。本批仅本地修改，未提交、推送或发布；0.8.7 未获 appcast 准入。

## 前序开发：0.8.7 Build 1（2026-10-30）

按用户「开始 0.8.7 版本的开发」初始化本地开发迭代。App、Widget 与兼容 Info.plist 已同步为 0.8.7 / Build 1 / 内部 103，开发 Bundle ID 与数据身份保持；功能沿用 0.8.6 Build 21，具体功能范围尚未指定，暂无新增功能规格。

基于当前工作区 `fbcc8da` 开始；该提交相对稳定 tag 仅补充发布记录和规格。保留现有分支 `codex/0.8.6-announcement-settings` 与未跟踪文件，本轮未提交或推送。当前周期稳定回滚基线为 `v0.8.6-build.21` / `3b737073d8a33b8362448d497141772629c3d989`，完整发布资产事实见[版本历史](VERSION_HISTORY.md#当前最新版本)。0.8.7 未获发布或 appcast 准入；公告名单继续仅包含已发布内部 102，未将 103 加入自动展示名单。

15:45（上海）Debug arm64 增量构建成功，开发运行包已更新并启动 PID 52763，无临时预览参数。237 项输入、13 项资源、完整包与旧包备份、实际加载路径核对通过，正式安装身份及主程序哈希未变；旧包位于 `.build/runtime-package-backups/development-087b1-20261030-154509/QuotaView.app`。仅版本配置调整，未新增或运行功能测试，未执行视觉/交互验收。证据目录 `.build/development-087b1-runtime/`。

## 最近公开发布：0.8.6 Build 21（2026-10-30）

用户授权的 0.8.6 发布完成：源码经 [PR #115](https://github.com/Duoasa/QuotaView/pull/115) 合入 main `3b737073d8a33b8362448d497141772629c3d989`，PR/main CI 成功；Universal 签名、公证/Staple、Gatekeeper、解压启动、公开 ZIP 回下载和签名 appcast 线上验证通过。GitHub Stable/Latest 与应用内更新目标均为 Build 21 / 内部 102。完整不可变事实见[版本历史](VERSION_HISTORY.md#当前最新版本)，回滚 `v0.8.5-build.1`，发布规格见 [0.8.6](docs/specs/release-0.8.6.md)。README 未改，Release 说明简短，正式安装和 Windows 通道不变。

修复 Codex 记录归档/删除后的缓存误报；公告启用本次正式内部 102，首次启动展示一次并保留设置查看入口，第二个公告版本未指定。默认自动检查更新 true，尊重已有偏好。727 项本地测试（6 跳过、0 失败）和 44 项契约通过，没有消费真实重置卡。视觉与真实升级体验由用户验收。

Build 21 开发包已更新启动 PID 2846；237 输入、完整包及实际加载路径核对通过，无临时预览参数。运行证据 `.build/release-086b21-runtime/`，发布证据 `dist/verification/0.8.6-build21-release/`。Build 20 曾完成本地签名验证，但因正式公告开关遗漏而顺延 Build 21，前者未公开。

## 前序开发：0.8.6 Build 19 / 恢复设置默认宽度（2026-10-29）

2026-10-30：用户原要求打包发布 0.8.6、默认开启更新检查并发布 Release/appcast、README 不动；随后明确「先暂停，检查一下这个问题」，因此发布暂停，尚未打包或发布。检查发现本地记录归档后的读取健康误报：`CodexLocalRolloutDiscovery.discoveredFiles` 保留带有旧 resourceValues 的 URL，已移走的 JSONL 仍通过 regular-file 判断，再被 `isReadableFile` 判成读取失败；`recheck()` 只重置枚举器，无法清除该缓存。隔离夹具从两个文件移走一个后，剩余候选为 1 但连续三次 `readFailed=true`，重新检查后仍为 true。本机现存 58 个 rollout 全部可读取，日志仍有 localRollout 活动。证据 `.build/codex-directory-diagnosis-20261030/result.json` 与同目录 `discovery-probe.swift`。本轮仅诊断，未改生产源码或重启运行包；修复及验证未完成，恢复发布需用户继续指令。

2026-10-29 15:41（上海）[PR #113](https://github.com/Duoasa/QuotaView/pull/113) 已合并 main，源码 `71f5e4f90e29f200f1458d014a3a29571d1ffff9`，合并 `691eed672fd6b1d4e9827740e87a3350a781b09c`。[PR CI 40836619344](https://github.com/Duoasa/QuotaView/actions/runs/40836619344) 与 [main CI 40837017488](https://github.com/Duoasa/QuotaView/actions/runs/40837017488) 均成功，各 726 项测试、6 跳过、0 失败及 44 项契约检查。当前 Build 19 运行包的 237 输入与源码/合并提交逐项一致，无需重建。证据 `.build/source-integration-086b19/source-proof.json`。未创建 Release、标签、安装包或 appcast 更新；正式安装未变。合并后的交付结果补记保留本地，GitHub PR 描述同步最终 CI 事实。

用户已接受当前公告与设置修改，并明确授权本轮源码推送 GitHub、合并 main，先不发布。提交包含 Build 16–19 的通用公告、紧凑元素、恢复材质双选项及设置原宽度；保留开发身份与正式公告空名单。本轮 PR / main CI 与合并均已完成，见下方记录；此授权不包含 Release、标签、appcast 或正式安装替换。

按用户要求恢复设置默认 780 × 680、最小 740 × 560、内容最大宽 560。仅回调窗口/内容宽度，保留 Build 18 的紧凑图标、字体、行高、原生控件及玻璃/纯色上下双选项，公告保持无交通灯的 460 × 580。规范见[恢复原默认宽度](docs/design/QUOTAVIEW_UI_RULES.md#恢复原默认宽度2026-10-29086-build-19)。

15:32（上海）0.8.6 / Build 19 / 内部 100 Debug arm64 增量构建成功，开发运行包已更新启动 PID 98311，无公告预览参数。237 输入、13 资产、完整包/旧包及实际加载路径核对通过；证据 `.build/settings-width-restore-086b19-runtime/`，备份 `.build/runtime-package-backups/settings-width-restore-086b19-20261029-153244/QuotaView.app`。尺寸常量修订未新增或重复运行测试，diff 检查通过，视觉由用户检查。未提交、推送、发布或改动正式安装。

## 前序开发：0.8.6 Build 18 / 公告与设置尺寸对齐参考（2026-10-29）

用户提供 VibeIsland 同屏截图，要求公告/设置元素尺寸参考其调整，材质恢复发行版上下双选项，并明确公告不要红绿灯。公告为 460 × 580，顶部图标/标题 64/18 pt、分类图标/标题 20/13 pt、正文 12 pt；收紧卡片留白，隐藏三颗系统按钮，底部「好」、回车和 Escape 保持关闭。设置默认宽 620、内容宽 400、页标题 16、设置行最小高 36、下拉字体 13，使用原生紧凑开关；侧栏去掉重复「设置」标题。玻璃/纯色恢复 `v0.8.5-build.1` 上下选项、原中英文说明和右侧单选标记，原偏好绑定保持。详见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#参考对照图调整元素尺寸2026-10-29086-build-18)和[公告规格](docs/specs/brand-announcement.md)。

15:29（上海）0.8.6 / Build 18 / 内部 99 Debug arm64 增量构建通过；开发包最终更新启动 PID 95905，携带公告预览参数。237 输入、13 资产、完整包/旧包与实际加载路径核对通过；最终证据 `.build/settings-announcement-density-086b18-final/`，备份 `.build/runtime-package-backups/settings-announcement-density-086b18-20261029-152859/QuotaView.app`。已有设置行尾部控件布局冒烟 1 项通过（`.build/settings-announcement-density-086b18-runtime/layout-smoke.log`）；未新增测试、截图或执行 UI 自动验收，实际效果由用户检查。本批仅本地编辑，未推送、发布、修改正式安装或 appcast。

## 前序开发：0.8.6 Build 17 / 紧凑更新与公告（2026-10-29）

用户要求参考 VibeIsland 更新弹窗，原品牌公告扩展为通用信息窗口。内容模型支持亮点、新功能、改进、公告、提醒以及可选版本信息；分类卡片可独立折叠，正文滚动，关闭按钮固定。设置入口更名为「关于 → 更新与公告」。保留按活动和内部版本记录已读的策略，正式发布名单为空；当前内容随包提供，不接入网络公告或系统通知。规格见[更新与公告](docs/specs/brand-announcement.md)。

Build 16 初版 580 × 780 已构建运行；用户反馈尺寸太大，Build 17 将默认窗口缩为 460 × 620，图标 72 pt、标题 20 pt，减少顶部及底栏留白，正文保持 13 pt。可调整大小，最小 400 × 360。实际观感继续由用户检查。

15:20（上海）0.8.6 / Build 17 / 内部 98 Debug arm64 增量构建通过，开发运行包更新启动 PID 91652，携带 `--preview-brand-announcement` 供查看；预览不写入正式已读记录。237 输入、13 资产、完整包/备份及实际加载路径核对一致。证据 `.build/announcement-compact-086b17-runtime/`；旧包 `.build/runtime-package-backups/announcement-compact-086b17-20261029-151959/QuotaView.app`。Build 16 三项已有公告策略冒烟通过，日志 `.build/announcement-center-086b16-runtime/policy-smoke.log`；Build 17 仅尺寸、间距与版本配置改变，未重复策略测试或进行 UI 自动验收。修改仅本地，未提交、推送、发布，正式安装不变。

## 前序开发：0.8.6 Build 15 / 再次移除代理可视化（2026-10-29）

用户认为没有理想方案，要求去掉可视化。已移除网络代理壁纸区域、节点、路径、蓝色选中框与动效，以及专用源码/测试和工程引用；SettingsView.swift 与工程文件逐字节恢复至已合入 main 的 Build 12 基线，实际代理配置与测试功能保留。Build 13–14 方案作废，详见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#网络代理仅保留设置2026-10-29086-build-15)。删除前两份专用文件保存在忽略目录 `.build/proxy-visual-removal-086b15/`，供本地历史回查，不参与构建。

14:28（上海）0.8.6 / Build 15 / 内部 96 Debug arm64 增量构建通过，开发运行包更新启动 PID 79728，无临时参数；237 输入、13 资产、完整包/备份与实际加载路径核对通过。专用符号在 Sources、Tests、工程文件中零残留，diff 检查通过；未新增测试或主动执行 UI 验收。证据 `.build/proxy-visual-removal-086b15-runtime/`；备份 `.build/runtime-package-backups/proxy-visual-removal-086b15-20261029-142847/QuotaView.app`。本批仅本地修改，未推送或发布，正式安装保持不变。

## 前序开发：0.8.6 Build 14 / 当前通路蓝色选中框（2026-10-29）

用户指出 Build 13 未体现参考中的蓝色节点选中框。已将当前通路改为蓝色细实线、浅蓝沿线流光，并补上参与当前通路节点的蓝色轮廓；QuotaView 描边跟随原始图标圆角，无额外填充底板，代理/云端使用无填充圆角六边形。代理关闭时其选中框隐藏。保持路由草稿、真实测试状态、停播规则和公开版背景。详见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#当前通路蓝色描边2026-10-29086-build-14)。

14:05（上海）0.8.6 / Build 14 / 内部 95 Debug arm64 增量编译通过，开发包更新启动 PID 73692，无临时参数；238 输入、13 资产、完整包/备份及加载路径核对通过。证据 `.build/proxy-route-blue-086b14-runtime/`；备份 `.build/runtime-package-backups/proxy-route-blue-086b14-20261029-140557/QuotaView.app`。本批为绘制修订，未新增或重复运行状态测试，实际样式由用户验收。未推送或发布，正式安装保持不变。

## 前序开发：0.8.6 Build 13 / 代理路径动效（2026-10-29）

用户要求参考 Dribbble 网络路径表达，在实际开发版直接实现动效。恢复公开版壁纸视口，原始 App Icon 无额外底托；直连/代理两条细线拓扑，圆角折线经过代理节点，草稿切换时绘入当前高亮路线，短线段沿线移动。无额外说明文字，状态用节点符号表达；只消费既有草稿和真实测试状态，不发起请求或保存偏好。未测试不显示成功；错误/无效状态停流，减少动态和不可见时停止。详见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#代理路径动效2026-10-29086-build-13)。

13:52（上海）0.8.6 / Build 13 / 内部 94 Debug arm64 增量编译通过，开发运行包更新启动 PID 70953，无临时参数；238 输入、13 资产、完整包/备份和实际加载路径核对通过。三个状态与离窗冒烟测试通过，未执行 UI 自动化或真实代理连接测试，实际动效由用户查看。证据 `.build/proxy-route-motion-086b13/smoke.log` 与 `.build/proxy-route-motion-086b13-runtime/`；备份 `.build/runtime-package-backups/proxy-route-motion-086b13-20261029-135230/QuotaView.app`。本次仅本地修改，未沿用前批推送授权，未发布或修改 appcast，正式安装保持不变。

## 前序开发：0.8.6 Build 12 / 移除代理可视化（2026-10-29）

用户已授权将 Build 10–12 的公告预览、原生设置下拉和代理可视化移除推送 GitHub 并合并 main；不发布 Release。[PR #112](https://github.com/Duoasa/QuotaView/pull/112) 已于 2026-10-29 11:50（上海）合并，源码 `f579a8da34a62195fb5604ee7a45dda5d4c86b70`、合并 `e635bc2e8de4108af2089ac8999873a7002c6d22`。PR CI [40813874636](https://github.com/Duoasa/QuotaView/actions/runs/40813874636) 成功：726 项测试、6 跳过、0 失败，另 44 项契约检查通过；精确 main CI [40814390673](https://github.com/Duoasa/QuotaView/actions/runs/40814390673) 也已成功（726 项测试、6 跳过、0 失败，44 项契约检查通过）。237 项运行包输入与源码及合并提交完全一致，证据 `.build/source-integration-086b12/`。新的代理可视化只生成三张独立设计图，按显示顺序编号 1/2/3，待用户选择后实施；对应原图路径与第三张已告知的文字错误见该证据目录 `design-options.json`。

用户要求去掉网络代理可视化窗口。已移除顶部壁纸与路由节点、状态摘要及其专用动画/绘制代码；标题下直接显示实际设置，不保留原区域高度。代理配置、保存、测试及错误反馈保持。详见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#移除网络代理可视化2026-10-29086-build-12)。

11:29（上海）0.8.6 / Build 12 / 内部 93 Debug arm64 增量构建成功，开发运行包更新并启动 PID 49396，无预览参数；237 输入、13 资产、完整包/备份和加载路径核对通过，代理专用可视化符号扫描零匹配，diff 检查通过。证据 `.build/remove-proxy-visual-086b12-runtime/`；旧包 `.build/runtime-package-backups/remove-proxy-visual-086b12-20261029-112915/QuotaView.app`。本次未新增测试或执行 UI 自动化，布局由用户查看。修改仅本地，未推送或发布，正式安装不变。

## 前序开发：0.8.6 Build 11 / 原生设置下拉选择（2026-10-29）

按用户截图，将设置中的共用普通命令菜单替换为原生 NSPopUpButton，系统提供真实选中项、勾选、高亮和菜单定位；覆盖语言、固定屏幕、停留时间、代理协议。保留真实偏好、动态屏幕列表、禁用状态和中英文。详见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#原生下拉选择2026-10-29086-build-11)。

11:24（上海）0.8.6 / Build 11 / 内部 92 Debug arm64 增量构建成功，开发运行包更新并启动 PID 47103，无预览启动参数；237 输入、13 资产、完整包/备份与实际加载路径核对通过。源码检查覆盖选中项同步、空列表、禁用、动态列表和回调绑定；本次未增加 UI 自动化或重复实现测试，视觉由用户验收。证据 `.build/native-settings-popup-086b11-runtime/`；备份 `.build/runtime-package-backups/native-settings-popup-086b11-20261029-112413/QuotaView.app`。品牌公告代码保留，仍可从设置手动查看；两个正式版本尚未配置。所有本次修改仍为本地未提交，未推送、发布或改动 appcast，正式安装保持原样。

## 前序开发：0.8.6 Build 10 / 品牌升级公告预览（2026-10-29）

用户要求先设计更新后首次启动的公告弹窗，后续两个版本均可展示，暂不发布；已确认先用现有名称和 Logo。已在实际开发应用接入原生 520 × 520 公告窗口，使用 QuotaView 图标、升级预告和“继续使用”按钮；中文/English 同步，支持关闭、Escape 和回车，可由“设置 → 关于 → 品牌升级公告 → 查看”重开。设计待用户验收，详见[公告规格](docs/specs/brand-announcement.md)。

展示策略按活动与内部 Build 分别记录关闭状态，两个指定版本各提示一次；跳过首个版本仍可在第二个版本看到。当前发布 Build 列表为空，正式渠道尚未启用；待设计接受且发布版本确定后填写两个精确序号。开发预览由 Debug + 开发身份 + `--preview-brand-announcement` 开启，不写入正式展示记录。

11:09（上海）0.8.6 / Build 10 / 内部 91 Debug arm64 增量构建成功，开发包更新并启动 PID 43256，携带上述预览参数；237 输入、13 资产、完整包/备份和实际加载路径核对通过。三个展示策略冒烟测试通过，未进行 UI 自动化或视觉验收。证据 `.build/brand-announcement-086b10/policy-smoke.log` 与 `.build/brand-announcement-086b10-runtime/runtime-result.json`；旧包 `.build/runtime-package-backups/brand-announcement-086b10-20261029-110923/QuotaView.app`。本次仅本地开发，未推送、发布、修改 appcast 或替换正式安装。

## 前序开发：0.8.6 Build 9 / 设置说明与信息层级（2026-10-29）

用户已确认本次设置修改可以，并授权源码推送 GitHub、合并 main；明确不发布 Release 包。[PR #111](https://github.com/Duoasa/QuotaView/pull/111) 已于 2026-10-29 10:50（上海）合入 main，源码提交 `e8d2aa4692477274cddf0308b120be42fe5fffc7`，合并提交 `8988528ef2f853338091bc763f39e2321a2df3a8`。PR CI [40808299936](https://github.com/Duoasa/QuotaView/actions/runs/40808299936) 与精确 main CI [40808752752](https://github.com/Duoasa/QuotaView/actions/runs/40808752752) 均成功：723 项测试、6 跳过、0 失败，另 44 项原生问题关闭契约检查通过。当前 Build 9 运行包的 236 项输入与源码提交及 main 合并提交逐项一致；证据 `.build/settings-source-integration-086b9/`。未发布 Release、标签、安装包或 appcast。

按用户要求删除设置页重复说明，用布局表达归属和选择：页头去掉复述、语言合并为单行菜单、材质使用分段控件、Agent 详情紧接所属行缩进展开、Claude 启用/状态只在列表展示、更新按钮不重复标题。移除外观、胶囊、立即生效及关闭模块不占位等冗余说明；代理仅在测试发生或有未保存更改时呈现反馈。保留输入/认证限制、隐私/权限范围、错误与安装确认提示。中英文同步，偏好绑定和实际功能保持。详见[设置规范](docs/design/QUOTAVIEW_UI_RULES.md#信息层级与重复说明清理2026-10-29086-build-9)。

10:22（上海）0.8.6 / Build 9 / 内部 90 Debug arm64 增量构建成功，开发运行包更新启动 PID 31625，无临时参数；236 输入、13 资产、完整包/备份和加载路径核对通过。既有分段控件设置行布局冒烟 1 项通过，未新增重复实现测试或 UI 自动化。证据 `.build/settings-copy-cleanup-086b9/` 和 `.build/settings-copy-cleanup-086b9-runtime/`；备份 `.build/runtime-package-backups/settings-copy-cleanup-086b9-20261029-102213/QuotaView.app`。用户已接受本次设置调整；源码已由 PR #111 合入 main，未发布 Release 或 appcast，正式安装未替换。

## 前序开发：0.8.6 Build 8 / 审批特效验收与临时卡清理（2026-10-29）

用户确认“效果没问题了”，接受本次实际灵动岛待批准卡的显示效果，并要求清理临时审批卡和注入。已移除会话显示副本中的模拟卡、Debug 开关/参数读取、选择/归档/审批等模拟回调、自动聚焦和临时 Tooltip；两个修改文件逐字节恢复到预览前生产基线，保留已合入的特效修复和 Build 6 默认自动检查配置。`Sources` 临时标记及符号扫描零匹配。

09:49（上海）0.8.6 / Build 8 / 内部 89 Debug arm64 增量构建成功，开发运行包已更新并启动 PID 27248，无临时启动参数。236 输入、13 资产、完整包/旧包备份和实际加载路径核对通过；App/Widget 版本同步，自动检查默认 true 保留。证据 `.build/approval-card-cleanup-086b8-runtime/`；备份 `.build/runtime-package-backups/approval-card-cleanup-086b8-20261029-094943/QuotaView.app`。仅本地修改，未推送/发布，正式安装未替换。用户验收仅覆盖本次查看的效果，不扩展为所有设备或真实审批协议验收。

## 前序开发：0.8.6 Build 7 / 实际灵动岛临时审批卡（2026-10-29）

用户明确要求在实际运行的灵动岛内查看，拒绝独立预览窗口。已退出独立预览并清理其生成源码副本、构建和 app；开发运行包增加一张 `DEBUG · 临时审批任务卡`，停在 65% awaitingConfirmation，初始聚焦列表并展开，点击进入真实审批页。当前用户设置的特效继续生效。

临时注入只在 `#if DEBUG`、`com.quotaview.development073` 和 `--debug-approval-card` 参数共同满足时启用；只修改会话显示副本，不写生产 Store、真实任务、审批或归档数据。模拟选择/归档/审批/claim/下一个等入口全部隔离，批准与拒绝仅显示模拟反馈，归档可移除此卡。界面、Tooltip 与辅助功能标明 DEBUG。当时按要求保留供用户查看；用户验收后，已由上方 Build 8 移除全部注入、临时 Tooltip 和启动参数。

09:46（上海）0.8.6 / Build 7 / 内部 88 Debug arm64 增量编译成功，更新运行包并启动 PID 25147，确认携带唯一临时参数。236 输入、13 资产、完整包/备份、实际加载路径与独立预览已退出核对通过。证据 `.build/temporary-approval-card-086b7-runtime/`；备份 `.build/runtime-package-backups/temporary-approval-card-086b7-20261029-094658/QuotaView.app`。仅本地，未推送/发布，正式安装未替换，视觉由用户验收。

## 前序开发：0.8.6 Build 6 / 默认自动检查更新（2026-10-29）

用户要求后续 Release 包默认开启自动检查更新。`SUEnableAutomaticChecks` 已改 true，正式打包脚本门禁同步要求 true，更新规格和发布规则已同步；保留 24 小时周期、已保存用户偏好和手动下载安装，开发身份仍禁用更新器。不发布包或 appcast，此追加变更仅本地，未沿用上一批推送授权。

01:35（上海）0.8.6 / Build 6 / 内部 87 Debug arm64 增量构建成功，开发包已更新启动 PID 3178；236 输入、13 资产、完整包/备份与实际加载路径核对通过。产物自动检查 true、自动更新两个开关 false、周期 86400 核对通过，发布脚本语法检查通过。证据 `.build/automatic-update-checks-086b6-runtime/`；备份 `.build/runtime-package-backups/automatic-update-checks-086b6-20261029-013509/QuotaView.app`。正式安装未替换，未做 UI 自动化。

用户随后要求创建审批卡查看效果：已从 Build 6 当前生产源码构建并打开隔离预览 `.build/approval-card-preview-086b6/Approval Card Preview.app`，独立身份 `com.quotaview.confirmation-preview`，初始审批页、65% 待批准，支持任务列表/审批页和三种特效切换。所有模拟按钮仅更新本地预览反馈，不构造生产服务或提交真实审批。此独立预览方案随后被用户拒绝，现已退出并清理生成包/源码副本/构建；由上方 Build 7 实际灵动岛临时卡替代。

## 前序开发：0.8.6 Build 5 / 待确认进度特效（2026-10-29）

用户授权修复待确认/审批聚焦卡特效丢失、推送 GitHub 合并 main，并完成后更新本机开发运行包；明确不发布任何 Release 包或修改 appcast。移除 `IslandQuantumProgressHost` 在 awaitingConfirmation 时隐藏和禁播特效的分支，沿用原进度、等待 Profile、确认边缘呼吸光和可见性/减少动态策略。历史分支由 2026-10-11 `066b397` 引入，0.8.3 至 Build 4 的相关状态映射、审批头卡与渲染器未变，不能断言是最近版本引入。

配置已同步 0.8.6 / Build 5 / 内部 86。宿主回归先复现旧代码 12 个断言失败，修复后四项渲染冒烟与八项审批布局/语义冒烟全部通过；Debug arm64 增量构建成功。证据 `.build/confirmation-progress-086b5/`。截图使用当前生产视图的隔离源码副本，独立身份 `com.quotaview.confirmation-preview`，仅内存模拟，无生产 Store/桥/Hook/真实批准回调，不向生产 Sources 注入。用户最初要求列表/审批页两张截图，随后明确“先不截屏”；截图暂缓，隔离预览未启动，临时预览源码、构建和应用已清理，视觉未验收。

[PR #110](https://github.com/Duoasa/QuotaView/pull/110) 已合入 main，合并提交 `694417d15246bdff6f7fa15590a178141f9ae4df`。PR CI `40734718174` 与精确 main CI [40735725793](https://github.com/Duoasa/QuotaView/actions/runs/40735725793) 均成功：723 项测试、6 跳过、0 失败，另 44 项契约检查通过。

01:32（上海）开发运行包已更新为 0.8.6 / Build 5 / 内部 86 并启动 PID 99025，无预览参数；236 输入、13 资产、完整包/备份及实际加载路径核对通过。证据 `.build/confirmation-progress-086b5-runtime/`；旧包 `.build/runtime-package-backups/confirmation-progress-086b5-20261029-013224/QuotaView.app`。正式安装身份与主可执行文件哈希未改，未发布 Release、安装包或 appcast。

## 前序开发：0.8.6 Build 4 / 图标验收与预览清理（2026-10-28）

用户已授权本次源码推送 GitHub 并合并 main。[PR #109](https://github.com/Duoasa/QuotaView/pull/109) 于 2026-10-28 15:43（上海）合并为 `186961a3c34954540d31a55b22d4b8bd39422741`，源码提交 `c9d88a91dddaa3e5a8e166f6521d49259369cd5d`。PR CI `40651280979` 成功（722 测试、6 跳过、0 失败，44 契约检查通过）；精确 main CI [40651890373](https://github.com/Duoasa/QuotaView/actions/runs/40651890373) 也已成功，Swift tests 与原生问题关闭契约检查均通过。提交和合并后的 236 项输入均与当前开发运行包匹配；证据 `.build/source-push-provider-icons-20261028/`。本次未发布 Release 或 appcast。

用户确认“图标没问题了”，接受 Claude、DSH、Kimi 的圆角矩形真实品牌图标，并要求清理三张虚拟任务卡及临时注入。已移除模拟卡生成、Debug 开关/启动参数读取、临时选择/归档分支和预览 Tooltip 修饰器，保留已验收图标与真实任务流程。`Sources` 中临时注入标记与预览符号扫描无匹配；此次视觉结论仅覆盖用户查看的图标。

15:30（上海）0.8.6 / Build 4 / 内部 85 Debug arm64 增量编译成功，开发运行包已更新并启动 PID 93658，进程未带预览参数。App/Widget 版本同步，236 输入、13 资产、完整运行包/旧包备份及实际加载路径核对通过。证据 `.build/provider-preview-cleanup-086b4-runtime/`，旧包 `.build/runtime-package-backups/provider-preview-cleanup-086b4-20261028-153010/QuotaView.app`。正常运行仅显示真实任务；开发身份和数据保留，正式安装身份与主可执行文件哈希未改，未提交/推送/发布，未做额外 UI 自动化。

## 前序开发：0.8.6 Build 3 / 三来源图标预览（2026-10-28）

Build 2 将 Claude、DSH、Kimi 主任务卡、子任务行及归档按钮品牌展示态统一为圆角矩形真实产品 Logo；复用连接页现有素材，保留 Codex 原图、图标槽位和归档行为。详见[图标规格](docs/design/quotaview-provider-icons.md#task-provider-icons)。15:09 Debug arm64 增量编译完成，0.8.6 / Build 2 / 内部 83 更新启动 PID 88979，证据 `.build/task-provider-icons-086b2-runtime/`。

用户随后要求虚拟另外三个 Agent 的任务卡检查效果。Build 3 / 内部 84 增加仅 Debug、开发 Bundle ID 与 `--debug-provider-cards` 启动参数共同开启的 `DEBUG-ONLY-MOCK` 展示，三张卡置于列表前方；标题、说明、Tooltip 与辅助功能标明 DEBUG。数据仅在进程内，不调用真实任务选择、归档或审批，不修改连接、用户账户、额度和持久化任务。支持归档逐张关闭；正常退出后不带参数重启即停用。当时暂留供用户查看；现已由上方 Build 4 在图标验收后清理。

15:13（上海）Build 3 Debug arm64 增量编译成功，开发包已启动 PID 91323，带上述临时预览参数。App/Widget 版本一致，236 输入无漂移、13 资产、完整包/备份和实际加载路径核对通过；证据 `.build/provider-cards-preview-086b3-runtime/`，旧包 `.build/runtime-package-backups/provider-cards-preview-086b3-20261028-151349/QuotaView.app`。正式安装身份与主可执行文件哈希未改；仅本地修改，未提交/推送/发布或修改 appcast，未做 UI 自动化，视觉由用户检查。

## 前序开发：0.8.6 Build 1（2026-10-28）

按用户要求建立 0.8.6 开发起点，仅同步 App、Widget 配置与兼容 Info.plist 为 0.8.6 / 显示 Build 1 / 内部 82；功能沿用 0.8.5，具体修改等待用户后续指示。保持开发身份 `com.quotaview.development073` 和现有数据，不切换分支。公开稳定版仍为 0.8.5 Build 1；本次未授权发布或 appcast 准入。

14:53（上海）Debug arm64 最小增量编译成功，开发运行包已更新并启动 PID 85897。App/Widget 版本一致，236 项输入构建前后无漂移，13 项资产、完整运行包/旧包备份与实际 App/Debug dylib/Core 加载路径核对通过。证据 `.build/development-086b1-runtime/`；旧开发包备份 `.build/runtime-package-backups/development-086b1-20261028-145321/QuotaView.app`。正式安装身份与主可执行文件哈希保持不变；未消费真实重置卡，未执行 UI 自动化或视觉验收，未提交、推送或发布。

## README 视频播放修复（2026-10-27）

初版 README 将视频封面指向 GitHub 的仓库文件页，文件下载检查虽通过，该页面对约 5–6 MB MP4 显示无法预览，不能作为播放器。中英文入口现改用现有 GitHub Pages 的 `demos/0.8.5/en/` 与 `demos/0.8.5/zh-CN/`：原始 H.264 视频、JPEG 封面、原生播放控件、播放/暂停按钮、下载与语言切换；页面及视频在 `gh-pages` 分支维护。README 的 MP4 原视频链接也直接指向 Pages 媒体地址。

修复验证包含真实浏览器播放、时间推进、视频解码尺寸、HTTP 视频类型与 Range 请求，不以下载成功代替播放。沿用本次 GitHub README 交付授权发布修复；不改版本、安装包或签名 appcast。证据见 `.build/readme-video-playback/`。

## README 中英文媒体整理（2026-10-27）

用户提供独立中英文实机配图与演示视频。`README.zh-CN.md` 使用 13 张中文 JPEG 与约 75 秒中文 MP4，`README.md` 使用 11 张英文 JPEG 与约 68 秒英文 MP4；各自素材位于 `docs/media/readme/zh-CN/`、`en/`。保留原始媒体字节，未混用两种语言；QQ 二维码转为白底 JPEG。首页按演示、任务/审批、用量/重置、设置、支持范围与安装重新组织，旧版本逐段介绍合并为当前更新摘要。

初版视频通过仓库文件链接接入，播放入口已由上方修复改为 GitHub Pages；未上传 GitHub 附件。素材说明保留真实采集/后期合成和原任务语言的边界。用户已授权本次 README、媒体与交接改动推送 GitHub 并合并 main；本次交付范围不涉及应用版本、已发布包、appcast 或开发运行包。链接、语言隔离、JPEG 格式及源文件哈希核验见 `.build/readme-media-085/`；文档变更不重建应用。

## 已发布：0.8.5 Build 1 / Codex 手动重置

2026-10-27 用户明确要求 0.8.5、真实 Codex 重置、GitHub/main 和 appcast 更新，同时禁止开发验证消耗其重置卡。本次精确发布身份为 0.8.5 Build 1 / 内部 81，tag `v0.8.5-build.1`、ZIP `QuotaView-v0.8.5-build.1.zip`；完整 macOS Stable/Latest 和签名 appcast 链路已授权。Windows 独立渠道及正式安装保持。规格见[手动重置](docs/specs/codex-quota-reset.md)、[0.8.5 发布](docs/specs/release-0.8.5.md)。

实现：官方 App Server 先读取具体卡片，人工确认后重新核对账户/卡片再消费；记录绑定账户哈希、明确卡片 ID 与幂等 UUID，未知结果经再次确认复用原操作，不后台重试。只升级灵动岛 Codex；Claude 继续复制命令，旧菜单演示保留。确认卡、等待/失败/未知结果均支持中英文，真实额度来自刷新。包含本轮玻璃、额度对齐与特效选项前移；已同步 origin/main，保留 Windows 发布记录。

本地完整测试 722 项、6 跳过、0 失败，审批契约 44 项通过；消费请求只在内存模拟服务和明确的临时假进程中执行，未使用真实卡。10:37（上海）0.8.5 开发包已更新并启动 PID 82509，236 输入/13 资产、完整包/备份与加载路径一致；证据 `.build/codex-reset-085-runtime/`。上一稳定版 `v0.8.3-build.1` / `178a2b03e94cf16119777c14ebdd9d2fd6ed97dc` 的公开 ZIP 已回下载，SHA-256 与版本历史一致。已由 [PR #105](https://github.com/Duoasa/QuotaView/pull/105) 合入 main，PR/main CI 均成功；Universal 正式包完成 Developer ID、公证/Staple、Gatekeeper 和解压启动。GitHub Stable / Latest 与签名 macOS appcast 已上线，公开 ZIP 与 Feed 的字节、身份和内置公钥验签通过。完整不可变事实见[版本历史](VERSION_HISTORY.md#当前最新版本)，回滚入口 `v0.8.3-build.1`。真实扣卡与视觉留给用户验收。

## 前序开发：0.8.3 Build 6 / 重置操作区深浅适配

2026-10-27：修复重置页按钮/下方说明固定白字或浅灰的问题。普通复制按钮浅色黑字、深色白字，材质同步外观；危险重置保留白字并加强浅色红底；说明与底栏共用外观前景。范围仅重置操作区，深色内容/审批卡按钮、复制和演示业务保持。配置 0.8.3 Build 6 / 内部 80。规格见[重置操作区深浅适配](docs/specs/island-glass-appearance.md#重置操作区深浅适配2026-10-27)。

10:05（上海）Debug arm64 增量编译成功，开发包更新并启动 PID 70532；234 输入、13 资产、完整运行包/备份及实际加载路径一致，App/Widget 版本同步。证据 `.build/reset-actions-appearance-20261027/`，旧包 `.build/runtime-package-backups/reset-actions-appearance-20261027-100526/QuotaView.app`。已审查可用/禁用、复制完成/演示反馈、深浅/自动与实体回退路径；未做 UI 自动化或真实重置，视觉待用户验收。仅本地修改，未推送、发布或替换正式安装。

## 前序开发：0.8.3 Build 5 / 额度左右对齐

2026-10-27：按用户修订，额度行恢复左标签/右百分比，与须知共用 14 pt 内容内距、上下各 16 pt 间隔；标签 10.5 pt Regular、数值 12 pt Medium，保持旧数据说明与未知值。配置 0.8.3 Build 5 / 内部 79。详见[额度左右对齐](docs/specs/island-expanded-glass.md#重置页额度左右对齐2026-10-27)。

10:00（上海）Debug arm64 增量编译成功，开发包更新并启动 PID 67706；234 输入、13 资产、完整运行包/备份及实际加载路径一致，App/Widget 版本同步。证据 `.build/reset-quota-alignment-20261027/`，旧包 `.build/runtime-package-backups/reset-quota-alignment-20261027-100028/QuotaView.app`。仅本地修改，未推送、发布或替换正式安装；视觉由用户验收。

## 前序开发：0.8.3 Build 4 / 任务特效前移

2026-10-27：按用户截图，将灵动岛设置中的任务特效网格移至顶部岛预览正下方；后续依次为外观与布局、显示内容、自动展开。保持三项特效的尺寸、偏好与实时预览绑定，使切换控件靠近预览。配置 0.8.3 Build 4 / 内部 78。规格见[任务特效前移](docs/specs/island-glass-appearance.md#任务特效前移2026-10-27)。

09:57（上海）Debug arm64 增量编译完成，开发包已更新并启动 PID 65551；234 输入、13 资产、完整包/备份与实际加载路径一致。证据 `.build/settings-effects-order-20261027/`，旧包 `.build/runtime-package-backups/settings-effects-order-20261027-095722/QuotaView.app`。未做 UI 自动化，实际效果待用户验收；仅本地开发修改，未推送、发布或替换正式安装。

## 前序开发：0.8.3 Build 3 / 重置页额度摘要

2026-10-27：按用户截图，将原两端分散的额度行收拢到重置次数下方，居中显示“剩余额度 + 百分比”，标签 10.5 pt Regular、数值 12 pt Medium，组间及行内均为 8 pt；旧数据与未知值语义保留。说明卡片延续 Build 2 深色玻璃，真实重置保持演示。规格见[额度摘要排版](docs/specs/island-expanded-glass.md#重置页额度摘要排版2026-10-27)。

0.8.3 Build 3 / 内部 77 Debug arm64 增量编译成功，09:53（上海）开发包更新并启动 PID 61927；App/Widget 版本同步，234 输入、13 资产、完整包/备份与实际加载路径一致。证据 `.build/reset-quota-summary-20261027/`，回退 `.build/runtime-package-backups/reset-quota-summary-20261027-095311/QuotaView.app`。受影响中英文、旧数据/未知状态与辅助功能已源码审查；未新增测试或做 UI 自动化，视觉待用户验收。仅本地修改，未推送、发布或替换正式安装。

## 前序开发：0.8.3 Build 2 / 重置说明深色玻璃

2026-10-27：按用户截图，将 `IslandResetPage` 的重置须知容器从独立纯黑背景/手工描边改为用量卡片相同的 `islandGlass`，采用 14 pt continuous 圆角、white 0.075 / alpha 0.75 和共享实体回退；空态、未知次数与 Claude 说明同步。文字、内距、重置券及演示逻辑不变。规格见[展开态玻璃](docs/specs/island-expanded-glass.md#重置说明卡片统一深色玻璃2026-10-27)。

0.8.3 Build 2 / 内部 76 Debug arm64 增量构建成功，09:46（上海）开发包已更新并启动 PID 56501；234 输入、13 资产、完整运行包/备份与实际加载路径一致。证据 `.build/reset-notice-glass-20261027/`；旧开发包备份 `.build/runtime-package-backups/reset-notice-glass-20261027-094613/QuotaView.app`。本次仅本地开发修改；未推送、发布或替换正式安装，视觉待用户验收。

## Windows 首个正式版与更新通道（2026-10-23）

按用户要求，完整 Windows 源码自 `Duoasa/quotaview-windows@cfc5490` 迁至 [Windows/](Windows/README.md)，后续开发、发布和问题反馈统一使用本仓库。首个正式版 **QuotaView 0.8.3-win · Windows** 基于 `0.8.3-win.10` 发布；包内版本、ZIP 名称和 tag 保留 `.10`，使用独立签名 appcast。macOS 生产源码、版本、Latest 与 Sparkle feed 保留。

[Windows 更新规格](docs/specs/windows-channel.md)记录当前边界；[发布工具](Windows/updates/README.md)生成签名条目，本轮获准加入 Windows 通道的首项为 `0.8.3-win.10`。Release 已公开，原 ZIP 回下载、哈希、签名及 324 个文件验证通过；资产与 feed 不可变事实见[版本历史](VERSION_HISTORY.md#当前最新版本)。中英文 README 增加 Windows 上线及系统/架构差异导致功能降级适配、后续持续完善的说明。原有 macOS Release 仅在标题补充平台，不修改资产或更新通道。

本轮只发布已通过 CI 的原包并更新 feed/docs，不变更应用代码或替换正在运行的同版本目录。发布提交的 Windows CI [39977526421](https://github.com/Duoasa/QuotaView/actions/runs/39977526421)、macOS CI [39977526026](https://github.com/Duoasa/QuotaView/actions/runs/39977526026) 成功；feed/docs 合入和精确 main CI 以 [PR #104](https://github.com/Duoasa/QuotaView/pull/104) 与 [Actions](https://github.com/Duoasa/QuotaView/actions) 为准。发布证据保存在 `Windows/webview2/build/release-evidence/`。真实升级体验仍待用户验收；可选的辅助进程实机实验未执行，不扩大现有验收结论。

迁移 CI 首轮复现已有的短屏 Claude 用量底栏裁切：正文高度未扣除完整胶囊预留及头尾区域。正文现按原生窗口同一高度预算计算，既有裁切断言保留。

源码与原生构建、30 项更新专项及 7 项既有移植检查通过；实际 standalone ZIP 的签名、长度、SHA-256、版本与 324 个文件解压检查通过，8 项原生桥冒烟通过。源码合入与精确提交的 CI 以 [PR #103](https://github.com/Duoasa/QuotaView/pull/103) 和 [Actions](https://github.com/Duoasa/QuotaView/actions) 为准。Windows 本机开发入口继续使用原 `webview2-migration/webview2/release/standalone/QuotaView.Native.exe`，仅更新运行目录内容以保留 Hook 路径；新源码位于 `quotaview-unified/Windows`。用户负责视觉与真实升级体验验收。

## 当前发布：0.8.3 Build 1

2026-10-16：按用户授权，最新开发代码已封装为 0.8.3 Build 1，源码经 [PR #101](https://github.com/Duoasa/QuotaView/pull/101) 合入 main；PR/main CI 通过。Universal 正式包已签名、公证、Staple，GitHub Stable / Latest 和签名 appcast 已上线，公开 ZIP、Feed 字节与内置公钥验证通过。中英文 README 已同步。完整不可变事实见[版本历史](VERSION_HISTORY.md#当前最新版本)，回滚入口 `v0.8.2-build.2`。

范围：macOS 27 玻璃兼容、底栏/胶囊统一浅深自动、设置分组、图标文字细调与 Widget 字体归档修复。开发包已更新启动，当前运行定位见下表；正式安装保持此前本机测试 Build 10，本轮未替换。小组件仅本机 Medium 场景由用户确认恢复，其他视觉/设备场景待用户验收。证据 `dist/verification/0.8.3-build1-release/`，规格 [0.8.3 发布](docs/specs/release-0.8.3.md)。

## 0.8.2 Build 10 / Widget 字体跨进程兼容

2026-10-15：用户反馈 macOS 27 桌面小组件只剩空框。系统正在加载 `/Applications/QuotaView.app` 的正式 0.8.2 Build 2 扩展；签名核验通过，Timeline 请求成功，但 NotificationCenter 解码 timeline 和 placeholder 均报 `SwiftUI.CodablePlatformFont.Error.invalidFont`，继而 `badTimelineData` 重载循环。非账户、卡片玻璃路径问题；尚不能证明所有 macOS 27 设备/全新安装均会复现。

旧 `CTFontCreateWithGraphicsFont` 的内存字体没有来源 URL。Widget 的 Asta Sans 改为从随包文件 descriptor 创建、校验 face/URL/字形，并保留文件地址；缺失/非法字体回退系统字体。主应用继续使用原直接数据加载，避免改变此前同名字体冲突修复。字号、布局、快照和字体资产不变。详见 [Widget 契约](docs/design/quotaview-widgetkit-solution.md#macos-27-字体归档兼容2026-10-15)。

0.8.2 / Build 10 / 内部 74 Debug arm64 增量构建成功，03:00 开发包已启动 PID 68163；234 输入、13 资产、完整包/备份与加载路径一致，正式安装未替换。证据 `.build/widget-font-20261015/`。最初只更新开发包，随后按用户明确授权完成本机签名安装并获“显示了”的反馈，详见下方实机交付记录。两项定向字体测试通过，覆盖三种字重、9/12/16/32 pt、来源 URL/重建、缺失/损坏/错误字重回退。修复已由 PR #100 合入 main，PR/main CI 均通过；不发布 Release/appcast。

### Build 10 本机签名安装与用户验收

用户随后明确授权完整备份并替换本机安装。2026-10-15 03:10：Release arm64 本机包完成 Developer ID 签名，App/Widget 同为 0.8.2 / 10 / 74，沿用正式应用身份和 App Group。完整旧包备份 `.build/runtime-package-backups/formal-before-widget-font-20261015-030910/QuotaView.app`；新包 `/Applications/QuotaView.app` 已启动 PID 76548，Widget PID 76553，实际加载新扩展和三种随包字体。开发实例已退出，避免双实例；开发运行包仍保留 Build 10。

新时间线于 03:10:13 成功加载；用户明确回复“显示了”，确认本机桌面小组件恢复。这覆盖本机当前 Medium 场景，不扩展为所有 macOS 27 安装、Small、所有外观/空态的验收。源码和本机包 234 输入与 main 合并提交一致；安装/备份清单通过。未公证，未发布 Release/appcast，不把本机测试安装称为公开更新。

源码已由 [PR #100](https://github.com/Duoasa/QuotaView/pull/100) 合入 main `f632288fb706b83e691000e365004f6ed9654d94`（源码 `7c3387d2f302496e6ac91bbae1be834025d1f0ab`）；PR CI 38620390253、main CI 38621030447 均成功。此段为合并后的本地交付补记。

## 0.8.2 Build 9 / 胶囊与岛体统一玻璃

用户反馈胶囊比岛体下方明显偏暗：移除胶囊独立黑 0.55 / 白 0.22 底色，真实岛体、胶囊、设置预览共用无染色 clear 材质组件；深浅/自动仍控制外观与文字，经典/减少透明度保留实体回退。顶部黑色渐变和深色内容卡片保持。

2026-10-15 02:46（上海）：Debug arm64 增量构建成功，0.8.2 / Build 9 / 内部 73 开发包已启动 PID 57632。234 输入、13 资产、完整包/备份和实际加载路径核对通过，正式安装文件未变。证据 `.build/capsule-unified-glass-20261015/`；旧包备份 `.build/runtime-package-backups/capsule-unified-glass-20261015-024643/QuotaView.app`。视觉待用户验收。

本轮源码已通过 [PR #99](https://github.com/Duoasa/QuotaView/pull/99) 合入 main `12f2c2ed1d3f268fc6fc86f12f8371d604a86fd3`，源码 `d9ee109700ac91b53c6c5815bf85938c7752d151`；PR CI 38618123882、main CI 38618820561 均成功。Build 9 的 234 输入与合并提交核对一致。公开 Release / appcast 保持 0.8.2 Build 2。

## 0.8.2 Build 8 / 文案 Regular 与来源标签留白

按用户要求，“返回任务 / 返回”、“用量统计”、Codex 与 Claude Code 来源标签统一 12 pt Regular；来源标签右内距 8 → 12 pt，左内距保持 8 pt。工具图标沿用 11 pt Semibold、按钮 24 pt，其他工具栏文字不变。

2026-10-15 02:43（上海）：Debug arm64 增量构建成功，0.8.2 / Build 8 / 内部 72 开发包已启动 PID 54893。234 输入、13 资产、完整包/备份、实际加载路径核对通过；正式安装文件未变。证据 `.build/usage-labels-regular-20261015/`；旧包完整备份 `.build/runtime-package-backups/usage-labels-regular-20261015-024315/QuotaView.app`。视觉待用户验收。

本轮全部源码通过 [PR #99](https://github.com/Duoasa/QuotaView/pull/99) 集成，当前新增样式更新待推送及 PR/main CI；用户已授权合并 main。公开 Release / appcast 保持 0.8.2 Build 2。

## 0.8.2 Build 7 / 工具图标 11 pt Semibold

用户要求将上下工具图标改为 11 pt、字重增加一档。共享 `IslandChromeMetrics.iconFont` 从 10 pt Medium 改为 11 pt Semibold，顶部固定/收起、底部刷新/设置、返回箭头及设置预览同步；24 pt 按钮与 12 pt Medium 工具栏文字保持。统一玻璃外观与明确黑/白前景沿用 Build 6。

2026-10-15 02:40（上海）：Debug arm64 增量构建通过，0.8.2 / Build 7 / 内部 71 开发包已更新启动 PID 52224；234 输入、13 资产、完整包/备份和实际加载路径一致，正式安装文件不变。证据 `.build/chrome-icons11-20261015/`，旧包备份 `.build/runtime-package-backups/chrome-icons11-20261015-024005/QuotaView.app`。用户视觉验收仍待完成；本轮源码已获推送/合并授权，PR/main CI 待完成，未发布 Release/appcast。

## 0.8.2 Build 6 / 玻璃按钮对比度

用户反馈 Build 5 上下四个按钮图标偏灰。共用样式前一轮改成 `.primary` 后受非激活窗口语义前景影响；本轮改为按已解析外观明确选择黑/白前景。顶部继承固定深色，图标保持白色；底部随浅/深切换黑/白，禁用态仍保留 0.4 opacity。底栏文字与设置预览同步显式前景，玻璃材质及统一胶囊选择保持。

2026-10-15 02:37（上海）：Debug arm64 增量构建成功，0.8.2 / Build 6 / 内部 70 开发包已启动 PID 50130。234 输入、13 资产、完整运行包与备份、实际 App/Debug dylib/Core 加载路径核对通过；正式安装文件不变。证据 `.build/glass-icon-contrast-20261015/`，旧包备份 `.build/runtime-package-backups/glass-icon-contrast-20261015-023712/QuotaView.app`。前一轮偏好/解析与编译兼容冒烟 3 项通过；实际按钮观感仍由用户检查。

用户已授权本轮全部源码推送并合并 main，PR/main CI 尚待完成；不发布 Release/appcast。

## 0.8.2 Build 5 / 底部玻璃与胶囊统一外观

2026-10-15：按用户补充，将浅色/深色/自动限定到下部玻璃、底栏文字/按钮及悬浮胶囊；黑色渐变和深色卡片保留。胶囊独立配色入口与读取移除，旧存储保留；设置重排为外观与布局、显示内容、任务特效、自动展开。三张系统风格缩略图只在液态玻璃显示，默认深色，自动使用公开 AppKit 外观观察并同步现有预览。详见[统一外观规格](docs/specs/island-glass-appearance.md)。

0.8.2 / Build 5 / 内部 69 的 App、Widget 与兼容 Info.plist 同步。Debug arm64 增量构建成功，开发包已更新启动 PID 46542；234 输入、13 资产、完整包和备份、实际 App/Debug dylib/Core 加载路径核对通过，正式安装文件不变。两项偏好/解析冒烟通过；同时修正 Swift 6.4 下旧问题投影测试的 optional 推断并验证该测试，合计 3 项通过。证据 `.build/glass-appearance-20261015/`。旧包备份 `.build/runtime-package-backups/glass-appearance-20261015-023229/QuotaView.app`。实际视觉、系统切换和辅助功能体验由用户验收。

用户已授权当前源码推送 GitHub、合并 main 并启动开发版；PR 与 main CI 待完成。此次不创建 Release、不修改 appcast；公开稳定版仍为 0.8.2 Build 2。

## 0.8.2 Build 4 / 炭灰玻璃调校

2026-10-15：用户反馈 Build 3 过亮，并提供桌面 `0.8.1/2.jpg` 作为参考。macOS 27 近黑表面改用未染色 clear 玻璃与原强度独立底色，用量卡片恢复 75% 炭灰、任务卡 42%（hover 32%）、深色胶囊 55%；不再使用 30% 强度的填充，保留原生折射、高光与原语义色。规格见[炭灰调校](docs/specs/island-expanded-glass.md#macos-27-炭灰玻璃调校2026-10-15覆盖-build-3)。App / Widget / 兼容 Info.plist 同步 0.8.2 / Build 4 / 内部 68。

Debug arm64 增量构建通过，开发包已更新启动 PID 39648。234 项输入、13 个资产、完整包与备份、实际 App/Debug dylib/Core 加载路径核对通过；正式安装文件保持不变。Build 3 完整备份于 `.build/runtime-package-backups/macos27-charcoal-20261015-022310/QuotaView.app`。视觉待用户验收；证据 `.build/macos27-charcoal-20261015/`。本轮仅本地开发，未提交、推送、发布或更新 appcast。

## 0.8.2 Build 3 / macOS 27 深色玻璃（已反馈过亮）

2026-10-15：用户要求适配 macOS 27 并更新开发版。源码身份为 0.8.2 / Build 3 / 内部 67；App、Widget 配置与兼容 Info.plist 同步。共享玻璃组件对 macOS 27 的近黑染色改用未染色原生材质与原色 30% 强度的独立填充，覆盖用量卡片、任务卡、深色胶囊及设置预览；旧系统、非深色强调控件、经典和减少透明度回退保持。见[适配规格](docs/specs/island-expanded-glass.md#macos-27-深色玻璃兼容2026-10-15)。

共享组件 Swift 5 / macOS 14 部署目标类型检查与 Debug arm64 增量构建通过。开发运行包已更新启动，PID 37335；234 项输入、13 资产、完整构建/运行包与旧包备份、实际 App/Debug dylib/Core 加载路径核对通过，正式安装 Info.plist 与可执行文件保持不变。旧开发包完整备份于 `.build/runtime-package-backups/macos27-glass-20261015-022114/QuotaView.app`。Xcode 升级后许可由用户完成确认；实际视觉待用户验收。证据 `.build/macos27-glass-20261015/`；本轮仅本地开发，未提交、推送、发布或更新 appcast。

## 0.8.2 Build 2 已发布

[0.8.2 Build 2](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.2-build.2) 已发布 GitHub Stable / Latest，源码经 PR #97 合入 main，PR/main CI 均成功；签名 appcast 在线字节、签名与更新目标核对通过。简短 Release 与中英文 README 介绍显示位置设置和子 Agent 排版修复。完整不可变事实见[版本历史](VERSION_HISTORY.md#当前最新版本)。

发布时开发运行包 0.8.2 / Build 2 / 内部 66，PID 8948；当时正式安装未替换。公开 ZIP 回下载与签名包一致，公证/Staple、解压启动通过，证据 `dist/verification/0.8.2-build2-release/`。回滚基线 v0.8.1-build.2 保留；视觉、多屏实际体验由用户验收。

## 0.8.1 Build 5 开发记录（内部 65）

2026-10-12：通用设置新增灵动岛显示位置。焦点跟随使用中性滑动开关，固定屏幕复用语言 SettingsValueMenu。默认保持主屏；开启后按活动应用前台窗口所在屏幕定位，每秒复用现有刷新检查，单屏不扫描窗口。固定屏幕保存显示器 UUID，断开回主屏、重连恢复；设置列表随屏幕连接变化刷新。用量胶囊随岛体移动。

Build 4 完成功能，Build 5 调整控件样式。增量 Debug arm64 构建与重启通过，PID 92879；234 输入、13 资产、运行包清单和加载路径一致。证据 `.build/screen-controls-20261012/`。实际多屏及视觉待用户验收。2026-10-13 已启动开发版 PID 4427，并经 PR #96 合入 main `43cea68af36ecf374221558e925fad85aca61aab`（源码 `f225e7b`）。屏幕选择与偏好持久化冒烟 3 项通过；PR CI 38415670896、main CI 38416416308 均成功。本次仅同步源码，未发布安装包或 appcast。此交付事实补记保留本地。

## 子 Agent 居中：0.8.1 Build 3（内部 63）

2026-10-12：子 Agent 的 18 pt 内容在下方 28 pt 区域内垂直居中，上下各 5 pt，卡片总高度与主区域特效不变。按用户新要求，每批开发版应用修改递增可见 Build 与内部序号；规则已同步 AGENTS 与发布规则。

增量 Debug arm64 编译及运行包更新通过，PID 185；实际加载路径、源码输入、包清单与版本身份核对通过。证据 `.build/subagent-row-centering-20261012/`。视觉待用户检查。仅本地开发修改，未推送、打包或更新 appcast；公开稳定版仍为下方 Build 2。

## 0.8.1 Build 2 已发布

[0.8.1 Build 2](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.1-build.2) 已发布 GitHub Stable / Latest，源码经 PR #94 合入 main；PR/main CI 均通过。用户已授权并推送签名 appcast，完整版本、哈希、公证与回滚事实见[版本历史](VERSION_HISTORY.md#当前最新版本)。前一稳定版 `v0.7.9-build.1` 保留。

本轮包含最新设置紧凑化、中英文 README 七张功能配图、设置页同款纯 QQ 二维码及多 Agent About。开发运行包 PID 58221，身份 0.8.1 / Build 2 / 内部 62，正式安装未替换。发布证据 `dist/verification/0.8.1-build2-release/`；公开回下载与本地签名公证 ZIP 一致，解压启动通过，视觉/实际交互最终由用户验收。


## 设置窗口与元素紧凑化（2026-10-11 23:32）

按用户与 macOS 系统设置对比反馈，将默认窗口由 1040×760 调整为 780×680 pt，最小 740×560；侧栏 180、外圆角 24、内容最大 560、水平内距 20。导航图标 20、行高 32，页标题 18；设置行标题/说明 13/11、最小行高 44、内距 12×8，原生控件 small。分组间距、预览高度（灵动岛 210，代理/关于 132）及效果选项高度 44 同步收紧。保留自动换行、滚动和用户放大窗口的能力。

Debug arm64 编译通过，开发包已更新重启 PID 47007，0.8.1 Build 1 / 内部 61；234 输入、13 资产、包/备份及实际加载路径一致，正式安装未改。效果卡圆角/裁切定向冒烟 1 项通过。证据 `.build/settings-compact-20261011/`；测试 `/private/tmp/qv-settings-compact-test.log`。实际视觉由用户检查。此轮仅本地修改，尚未纳入下方已封装 ZIP，未提交/推送/重新打包。

## 0.8.1 Build 1 本地封装与产品图交付

版本为 **0.8.1 / 显示 Build 1 / 内部 61**。源码 `ff9906d9b39e76c8c2db386992a1124dedfb832b` 已经 [PR #93](https://github.com/Duoasa/QuotaView/pull/93) 合入 main `c0773493ab6a1f9f57d949f56948584ec7dc9bb5`；PR CI 38148405962、main CI 38148718069 均成功。本批包含黑色至玻璃平滑过渡、清透区域优化、用量胶囊深浅染色及右对齐设置。705 项本地 Swift 测试执行、6 跳过、0 失败；原生审批契约 44 项通过、真实动作 0。

本地包：`dist/QuotaView-v0.8.1-build.1.zip`，25,022,141 bytes；SHA-256 `45430481515fb67ca2f191850f1e2bd173a8b9ce70bec16a70ea6c5579b222ca`。Universal arm64 + x86_64，Developer ID Chenchen Xu (BUUH229D5Q)，Apple 公证 Accepted / Staple（`e8cf1733-980e-42ea-8977-b726039f13c9`）。解压包签名、架构、166 个源输入冻结一致性以及 15 秒启动/实际动态库路径检查通过；核验进程已退出。证据 `dist/verification/0.8.1-build1-package/`。开发运行包 PID 94359 保留，正式安装未改。未发布新的 GitHub Release 或 appcast；公开稳定版仍为 v0.7.9-build.1。

原 Figma 文件 UI2 右侧新增四张可编辑产品图，使用虚拟数据，不改变生产账户或任务：

- [三状态任务页](https://www.figma.com/design/hS0Dwc9S9EJGEbkkplxH4v/QuotaView?node-id=198-337)：思考中、工作中、待确认。
- [用量页](https://www.figma.com/design/hS0Dwc9S9EJGEbkkplxH4v/QuotaView?node-id=205-401)：Codex / Claude Code 来源切换、双周期额度、账户、Tokens、成本及活动热图。
- [审批页](https://www.figma.com/design/hS0Dwc9S9EJGEbkkplxH4v/QuotaView?node-id=205-402)：完整命令、理由、范围与操作按钮。
- [重置卡页](https://www.figma.com/design/hS0Dwc9S9EJGEbkkplxH4v/QuotaView?node-id=205-403)：2 次虚拟重置、须知、红色按钮与演示说明。

尺寸、文字与轮廓按源码映射，按钮 24 pt / 图标 10 pt；玻璃使用 Figma 原生 GLASS 效果，其光学呈现不等同于 macOS 合成器。AI 球及进度特效使用真实 Metal 静态渲染；按用户产品图要求，选中工作卡和待确认卡均展示进度特效，待确认保留赤金色光晕（生产当前会隐藏待确认噪点，此处仅为画板展示覆盖，不改应用）。重置卡为原始 SVG，文字/布局可编辑，未嵌入整页截图。四页导出检查完成；最终产品图视觉由用户验收。节点与本地渲染材料见 `.build/081-figma-assets/`。

## 胶囊配色切换右对齐（2026-10-11 22:34）

移除胶囊配色 Picker 的 140 pt 居中外框，按原生固有宽度布局，右端使用 NativeSettingsRow 共用 18 pt 内距，与相邻开关对齐；配色行为不变。Debug arm64 编译通过，开发包更新重启 PID **87644**（0.7.9 Build 2 / 内部 60），234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/capsule-picker-alignment-runtime-20261011/`；视觉由用户检查，未提交/推送/发布。

## 胶囊浅色恢复清透玻璃（2026-10-11 22:16，覆盖前序浅色定义）

用户明确修正：深色仅为深色染色液态玻璃，浅色为之前完全清透的无着色液态玻璃。保留深色 black 0.55 tint；浅色移除 white 0.76 tint，恢复 clear tint、深色玻璃环境与白字，取消浅色底配深字的方案。两模式均使用 clear 原生材质，实际胶囊/设置预览共用样式；减少透明度保留深色实体回退确保白字可读。设置说明同步，现有选择与持久化不变。

Debug arm64 编译通过，开发运行包更新重启 PID **80290**，仍 0.7.9 Build 2 / 内部 60，234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/capsule-clear-light-runtime-20261011/`。视觉由用户检查；未提交/推送/发布。

## 用量胶囊深浅配色（2026-10-11 22:13）

设置 → 灵动岛 → 显示新增“胶囊配色”深色/浅色分段选项。深色为黑色 0.55 染色 clear 玻璃、白字；浅色为白色 0.76 染色 clear 玻璃、0.10 深灰字。次要文字与分隔线跟随前景色，胶囊局部 colorScheme 随选项切换，主岛和设置窗口仍保留原外观。减少透明度/旧系统回退底色为 0.12 / 0.94。风险色环保持语义色。

`island.usageCapsuleTone` 自动保存，默认及非法旧值回退 dark；关闭胶囊时配色选择器禁用并保留值。Runtime → Session → Display 传递新偏好，真实胶囊和固定双周期设置示例共用样式，切换立即生效，真实数据与预览数据边界不变。

定向偏好持久化测试通过（默认、重载、开关联动、非法值回退）。Debug arm64 编译成功，开发运行包更新重启 PID **78054**，仍 0.7.9 Build 2 / 内部 60；234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/capsule-tone-runtime-20261011/`，测试 `/private/tmp/qv-capsule-tone-test.log`。实际可读性与视觉由用户检查，未截图/操作验收；未提交、推送或发布。

## 缩短渐隐与移除玻璃下方暗影（2026-10-11 22:09）

用户反馈上一版渐隐范围过大、真实玻璃较预览偏暗。黑色平台位置不变，渐隐长度缩至原先剩余高度的 70%，后 30% 玻璃区不叠黑；仍用五次平滑曲线，范围保留 20%–80%。例如默认黑色 55%，渐隐在 86.5% 结束，底部 13.5% 全透明。真实/设置预览共用参数。

发现实际 IslandNotchSurface 的经典 shell.shadowPath 在 clear 背景下仍保留 0.26 黑色阴影；玻璃模式关闭此额外阴影，保留系统玻璃自有深度，经典模式阴影保持。实际用量胶囊同时切换为与设置预览相同的无 tint clear 玻璃。原生材料受背后壁纸影响，未宣称实机与预览光学完全一致。

定向范围/渐隐契约测试通过，Debug arm64 编译通过，开发运行包更新重启 PID **74237**（0.7.9 Build 2 / 内部 60）；234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/glass-clear-footer-runtime-20261011/`，测试 `/private/tmp/qv-glass-clear-footer-test.log`。视觉由用户检查，未截图或 UI 验收；未提交/推送/发布。

## 黑色到玻璃的平滑长渐变（2026-10-11 22:05）

用户要求参照 Droppy 截图改善过渡，并在后续选项中明确保留 20%–80% 范围。本机 Droppy 16.0.1 当前 dynamicGlassLevel 为 0.5；只读核对，未改其设置。旧公开副本不含 DynamicGlassMelt，当前官方文档也未给出精确色标/滑杆参数，因此本轮是按用户截图独立调校，不宣称复制 Droppy 私有实现或精确数值。参考入口：[官方外观说明](https://getdroppy.app/docs/notch)、[设置参考](https://getdroppy.app/docs/settings)。

保持黑色平台结束位置 `1 - normalized(glassDegree)`，随后渐变覆盖到整块岛体底部；撤除原“短过渡后突然全透明”的横带。使用 16 段采样五次平滑曲线 `alpha = 1 - (6t^5 - 15t^4 + 10t^3)`，起止斜率为零，中点透明度 0.5，末端透明度 0；全程同一黑色色相，原生 clear 玻璃、动画和裁切结构保持。真实岛体与设置预览共享色标计算，无新增计时器、滤镜或逐帧布局。保留当前保存的滑杆值，默认 0.45，范围仍 0.2…0.8。

定向渐变契约测试通过（范围两端/默认值、色标单调、底部透明、平滑端点、非法值归一化）。Debug arm64 编译成功，开发运行包更新重启 PID **71019**，仍 0.7.9 Build 2 / 内部 60；234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/glass-smooth-melt-runtime-20261011/`，测试日志 `/private/tmp/qv-glass-melt-test-20261011.log`。视觉由用户验收，未截图或 UI 操作；本轮未提交/推送/发布。

## 当前批次 GitHub 合入准备（2026-10-11）

用户已授权推送并合并 main。本轮包含真实用量胶囊/设置开关与双周期静态预览、完成球流光与对号交替、用量数据卡底色；真实岛体 Demo 已移除。完整 Swift 测试 703 项、6 跳过、0 失败；原生审批关闭契约 44 项通过、真实动作 0。源码与已运行开发版一致（证据 `.build/settings-clear-capsule-runtime-20261011/`），正式安装、版本与发布渠道不变。视觉仍由用户验收。PR/main CI 与最终合并提交见 GitHub PR 交付记录；历史未跟踪文件和 Prototype 冻结目录不纳入此次提交。

## 设置预览胶囊清透玻璃（2026-10-11 19:31）

设置预览胶囊改用与岛体相同的 clear 原生玻璃，取消原 regular 玻璃暗底与 tint；实际岛体胶囊参数和真实用量保持。本次仅预览传入 clearSurface，双周期示例、固定预览大小和无障碍回退保持。

Debug arm64 编译通过，开发运行包更新重启 PID **4439**（0.7.9 Build 2 / 内部 60），234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/settings-clear-capsule-runtime-20261011/`。视觉由用户验收，未提交/推送/发布。

## 设置双周期胶囊与固定预览高度（2026-10-11 19:29）

设置可视化胶囊固定采用双周期示例：5 小时剩余 72%、3 小时 20 分钟重置；周额度剩余 46%、4 天重置，与原预览周数据一致。仅设置示例变化，真实灵动岛继续读取真实快照。预览区域高度固定 256 pt，开关胶囊或隐私模式不改变区域大小；宽度沿用设置内容区约束。

Debug arm64 编译成功，开发包更新重启 PID **1746**，0.7.9 Build 2 / 内部 60。234 输入/13 资产及包/备份/加载路径一致，正式安装未改；证据 `.build/settings-dual-quota-runtime-20261011/`。未截图或视觉验收，效果由用户检查；未提交/推送/发布。

## 胶囊恢复真实数据与设置预览同步（2026-10-11 19:26）

已按用户要求删除真实岛体的双周期 Demo 注入及 `debug.floatingUsageDemo` 偏好，胶囊恢复现有真实快照；生产 Sources 无该 Demo 或 DEBUG-ONLY-MOCK 标记。上一节保留 Demo 的要求已撤销。

设置可视化新增相同胶囊组件。按用户纠正，设置页只使用原预览一致的静态示例：周额度剩余 46%、4 天重置；不读取真实周期，不注入生产快照，无计时器。开关/隐私设置联动，开启时预览区域从 212 增至 256 pt，留出下方胶囊。实际胶囊与设置预览共用液态玻璃、排版和周期选择组件。

Debug arm64 编译成功，开发运行包更新重启 PID **98668**，0.7.9 Build 2 / 内部 60；234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/usage-capsule-settings-runtime-20261011/`，中间恢复真实版证据 `.build/floating-usage-real-runtime-20261011/`。`git diff --check` 通过，视觉由用户验收，未提交/推送/发布。

## 双周期胶囊 Demo（2026-10-11 19:23）

用户明确要求注入带 5 小时额度的 Demo，保留供用户检查。仅 Debug + 开发 bundle + `debug.floatingUsageDemo` 开启时在胶囊局部替换展示：5 小时剩余 72% / 启动后 3 小时 20 分钟重置，周剩余 64% / 启动后 5 天 6 小时重置。界面和辅助功能标注 DEMO，源码 DEBUG-ONLY-MOCK；不写真实快照、用量页或账户数据。使用现有胶囊设置开关可隐藏；退出演示并恢复真实显示需关闭该 debug 偏好后重启。提交/推送/发布前移除此注入。本次用户明确要求的可见 Demo 覆盖任务结束即清理规则。

Debug arm64 编译成功，开发运行包更新重启 PID **94922**，0.7.9 Build 2 / 内部 60，234 输入/13 资产及包/备份/加载路径一致。证据 `.build/floating-usage-demo-runtime-20261011/`；正式安装未改，实际效果由用户验收，未提交或推送。

## 灵动岛下方悬浮用量胶囊（2026-10-11 19:19）

新增默认开启的“悬浮用量胶囊”开关（灵动岛 → 显示）。胶囊高 32 pt、距岛体 8 pt，宽度随内容自适应；有 300 分钟窗口显示 5 小时 + 周，无则只显示周；剩余百分比/重置倒计时来自现有 Codex 快照，缺失或失效为占位，隐私模式隐藏。复用当前窗口与统一过渡，页面底部预留 44 pt，无新增轮询。

Swift build 与定向窗口选择测试通过；Debug arm64 开发包更新重启 PID **92359**，仍 0.7.9 Build 2 / 内部 60，234 输入/13 资产及包/备份/加载路径一致，正式安装未改。证据 `.build/floating-usage-runtime-20261011/`；测试 `/private/tmp/qv-floating-usage-test.log`。视觉由用户检查，未提交/推送/发布。规格 `QV-ISLAND-FLOATING-USAGE-001`，见 `docs/specs/island-floating-usage.md`。

## 完成态 AI 球流光与对号交替（2026-10-11 18:28，覆盖前序聚散方案）

按用户反馈修正对号 Y 方向，使用两段圆头连续距离场线条（半宽 0.075 球半径、导数抗锯齿），移除全部 18 光点/聚散运动。完成态基础高光速度从 0.12 提至 0.28；8 秒周期：流光 2 秒、淡入 0.8 秒、对号停留 4 秒、淡出 1 秒、流光 0.2 秒。对号阶段交叉淡化内部流光，保留绿色球体与边缘；其他状态不变，减少动态显示静态对号，复用原 pipeline/停播生命周期。

定向 Metal pipeline 契约测试 1 项通过，Debug arm64 编译成功。开发运行包更新重启 PID 71888（0.7.9 Build 2 / 内部 60），234 输入/13 资产与包、备份、实际加载路径一致；正式安装未改。证据 `.build/completion-orb-crossfade-runtime-20261011/`，测试日志 `/private/tmp/qv-orb-crossfade-20261011.log`。未做截图或视觉验收，实际效果由用户检查；未提交、推送或发布。

## 当前运行：完成球高光对号循环（2026-10-11 18:21）

完成态球内高光 6 秒聚拢成对号、停留、飘散循环；绿色球体与其他状态配色保留，减少动态为静态对号。通过原生 Metal 源码组合新增 completion 通道（132 floats），不改生成 shader 资源，复用现有缓存与播放生命周期。

Debug arm64 编译成功，定向 Metal pipeline 契约测试 1 项通过；开发版更新重启 PID **66446**，仍 **0.7.9 Build 2 / 内部 60**。234 输入/13 资产、包/备份/实际加载路径一致，正式安装未改。证据 `.build/completion-orb-checkmark-runtime-20261011/`；测试日志 `/private/tmp/qv-orb-check-20261011.log`。`git diff --check` 通过，视觉由用户验收；未提交、推送或发布。

## 当前运行：用量页深灰卡片（2026-10-11 18:12）

用户确认修改所有数据卡背景。共享 surface 采用中性深灰 white 0.075 / 玻璃 tint alpha 0.75，悬停 white 0.12，经典模式同色；14 pt continuous，图表语义色及券面不变。本地 Debug arm64 编译通过，运行包更新重启 PID **56760**，仍 **0.7.9 Build 2 / 内部 60**；234 输入/13 资产、包/备份/实际加载路径一致。证据 `.build/usage-card-colors-runtime-20261011/`，正式安装未改，`git diff --check` 通过，视觉由用户验收。此改动未提交/推送。

上一轮源码已经 PR #91 合并 main，提交 `f96e0fd4de90f27a70ffcc96a3363e88b7db2b78`。本地 702 项测试、6 跳过、0 失败；PR CI 38129559407 与 main CI 38129857158 均成功。交付证据 `.build/main-merge-clean-runtime-20261011/github-delivery.json`。无 Release/appcast 发布。

## GitHub main 合并准备（2026-10-11）

用户已授权推送当前源码并合并 main。本次包含灵动岛原生玻璃/经典材质、20%–80% 黑色覆盖、稳定外壳几何过渡、卡片/子 Agent/详情/审批排版、设置分栏与预览，以及配套规范和此前文档清理归档。按提交门禁移除生产 Sources 中常驻 DEBUG Demo 注入及其选择/归档分支；用户偏好和数据保留。未跟踪的历史 MultitaskIslandConsole 冻结包及旧独立 Handoff 保持本地，不作为本轮应用源码提交。

清理后 Debug arm64 编译成功，开发包更新重启 PID **38595**，仍 **0.7.9 Build 2 / 内部 60**；234 输入/13 资产、包/备份/加载路径一致，正式安装未改。证据 `.build/main-merge-clean-runtime-20261011/`。原生确认关闭契约 44 项通过、真实操作数 0；完整 Swift 测试和 PR/main CI 待下方交付结果确认。视觉仍由用户验收，本次不发布安装包/Release/appcast。

## 当前运行：重置按钮深红强调（2026-10-11 17:37）

额度重置演示按钮单独使用深红 0.78 染色 regular 液态玻璃与白字，提升提示强度，其他审批按钮和演示行为保持。Debug arm64 编译成功，运行包更新重启 PID **34557**，仍 **0.7.9 Build 2 / 内部 60**；234 输入/13 资产、包/备份/加载路径一致，正式安装未改。证据 `.build/reset-button-depth-runtime-20261011/`。`git diff --check` 通过，视觉由用户验收。未提交、推送或发布。

## 当前运行：统一运动节奏（2026-10-11）

展开/收起/切页外壳统一 0.38 秒、正文位移同周期、双向显隐 0.23 秒；正常操作保持背景节点身份，目标改变从当前插值续接，重复刷新不重启动画。减少动态/隐藏时停止仍在执行的插值。

Debug arm64 编译成功，运行包更新重启 PID **32382**，仍 **0.7.9 Build 2 / 内部 60**；证据 `.build/glass-continuity-runtime-20261011/`。运行包/备份/源码及加载路径核对一致，正式安装未改。`git diff --check` 通过。当前受限沙盒的跨工作区写入和重启通过权限批准执行；无截图、UI 操作或视觉验收，连续操作实际效果由用户检查。未提交、推送或发布。

## 当前运行：原生背景几何过渡（2026-10-11 17:28）

用户反馈上一版展开/切页乱跳，撤除整窗 glassContainer transform 与整页强制零透明度淡入，改为固定宿主内的轻量背景几何插值。原生玻璃、遮色与紧凑黑色共用尺寸/轮廓，展开和收起保留挂载；相同尺寸刷新不重启动画。正文与窗口不参与逐帧布局，原有重置券转场和经典路径动画保持。此次覆盖前序“共享外层 compositor transform”方案，待用户视觉验收。

Debug arm64 编译成功，开发运行包已更新重启 PID **27964**，仍 **0.7.9 Build 2 / 内部 60**。234 输入/13 资产、包/备份/实际加载路径一致，正式安装未改。证据 `.build/glass-native-motion-runtime-20261011/`；`git diff --check` 通过。按用户要求未截图、UI 操作或性能采样，未提交、推送或发布。

## 当前运行：过渡、图标与特效选项轮廓（2026-10-11 17:25）

玻璃与遮色共用外层 compositor transform，展开及展开态尺寸切换恢复 0.38 秒过渡，从 presentation 尺寸衔接中断；页类切换正文淡入 0.23 秒。收起保留原紧凑壳过渡，不新增逐帧布局。卡片 Agent 移除额外 0.72 opacity。三个设置特效图片共享任务卡 16 pt continuous，外背景/选中描边按 8 pt 内距为 24 pt。

依次完成 Debug arm64 过渡包（PID 23355，`.build/glass-transition-runtime-20261011/`）、图标包（PID 23732，`.build/agent-icon-brightness-runtime-20261011/`）及最终选项轮廓包；当前 PID **25154**，证据 `.build/effect-option-contour-runtime-20261011/`。仍 **0.7.9 Build 2 / 内部 60**，234 输入/13 资产、包/备份/加载路径一致，正式安装未改。`git diff --check` 通过，未 UI 操作、截图或性能采样，实际视觉由用户验收。未提交、推送或发布。

## 当前运行：黑色遮色同步（2026-10-11 17:20）

移除黑色 glassClipping 独立 0.38 秒展开动画，让遮色轮廓与已提交尺寸的玻璃同轮更新，清除残留 path 动画；保留内容淡入和经典外壳过渡。Debug arm64 编译通过，开发运行包更新重启 PID **20083**，仍 **0.7.9 Build 2 / 内部 60**。234 输入/13 资产、包/备份/加载路径一致，正式安装未改。证据 `.build/glass-shade-sync-runtime-20261011/`；`git diff --check` 通过。实际视觉由用户验收，未截图或 UI 操作，未提交、推送或发布。

## 当前运行：黑色覆盖 20%–80%（2026-10-11 17:19）

按用户纠正，黑色覆盖限于 20%–80%；滑杆/旧值归一化/预览/真实外壳同步，默认黑色 55% 保持。Debug arm64 增量编译通过，开发包更新重启 PID **17899**，仍 **0.7.9 Build 2 / 内部 60**；234 输入/13 资产、包/备份/加载路径一致，正式安装未改。证据 `.build/glass-range-runtime-20261011/`。`git diff --check` 通过，实际视觉由用户验收。未提交、推送或发布。

## 当前运行：完整玻璃轮廓（2026-10-11 17:18）

修复玻璃程度拉满后外壳暴露圆角矩形：原生玻璃改用完整 IslandNotchShape，移除宿主左右 lip 内缩，顶部内凹肩部与外壳一致。旧系统模糊材质同步轮廓与尺寸更新。Debug arm64 编译通过，开发包更新重启 PID **16269**，仍 **0.7.9 Build 2 / 内部 60**；234 输入/13 资产、包/备份/实际加载路径一致，正式安装未改。证据 `.build/glass-contour-runtime-20261011/`。`git diff --check` 通过，未做 UI 验收，视觉由用户检查。未提交、推送或发布。

## 当前运行：液态玻璃范围滑杆（2026-10-11 17:15）

设置 → 灵动岛 → 液态玻璃新增“玻璃程度”，左黑色/右玻璃；自动保存 island.glassDegree，默认 0.45 保持原 55%–80% 渐变。运行外壳与设置预览共用渐变计算，仅更新现有遮色层；经典模式隐藏设置并保留值。Debug arm64 编译通过，运行包已更新重启 PID **13422**，仍 **0.7.9 Build 2 / 内部 60**；234 输入/13 资产、包/备份/实际加载路径一致，正式安装未改。证据 `.build/glass-degree-runtime-20261011/`。`git diff --check` 通过，未执行 UI 验收，视觉由用户检查。未提交、推送或发布。

此前用量问题独立读取复现远端 403；按用户要求清理约 367 MB 开发 ModuleCache/Metal 缓存后仍返回 403，未修改登录或网络配置，不能记录为恢复。

## 当前运行：低亮度赤金整片光与近白主按钮（2026-10-11 17:07）

用户最新要求覆盖前序外壳仅边缘光：恢复完整填充呼吸，父层 alpha 0.28；审批主题与光晕使用待确认 AI 球上部高光赤金色（1 / 0.56 / 0.12）。量子噪点色板与用量警告色不变。右侧非破坏性首选按钮为白色 0.90 染色 regular 玻璃、深字，经典回退 0.94 灰度；保留超椭圆、渐隐与底栏 20 pt 间距。

Debug arm64 增量编译成功，开发包已更新重启 PID **6041**，仍 **0.7.9 Build 2 / 内部 60**。234 项输入、13 项资产、运行包/备份/加载路径核对一致，正式安装未改；证据 `.build/approval-warm-glow-runtime-20261011/`。未截图或进行 UI 验收，实际效果由用户检查。未提交、推送、发布。

## 当前运行：审批玻璃与边缘提醒（2026-10-11 16:59）

审批提醒改为外壳/头卡边缘呼吸光，待确认头卡不渲染粒子；选项/主操作按钮/主要内容面板采用连续曲率玻璃与经典回退。移除内容/按钮分隔线，主按钮与工具底栏间距 20 pt。滚动正文顶部黑色渐隐、底部逐组件透明度渐隐，上下最多 12 pt，固定动作区不参与。未改审批协议、按钮动作或授权语义。

Debug arm64 增量编译成功，开发包更新重启 PID **98864**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/approval-edge-glass-runtime-20261011/`。`git diff --check` 通过；无截图、UI 操作或性能采样，实际效果由用户验收。沙盒切换为受限后，本次跨工作区写入/开发包更新已通过工具权限批准。未提交、推送、发布。

## 当前运行：设置可视化超椭圆（2026-10-11 16:52）

灵动岛/代理/关于桌面预览统一 20 pt continuous 外框，壁纸图片单独裁切以保留原生玻璃材质；任务卡与特效选项继续使用连续曲率，设置页残余普通圆角背景/描边/命中形状同步 continuous。主卡真实特效保留。

Debug arm64 增量编译成功，开发包更新重启 PID **92032**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/settings-contours-runtime-20261011/`。`git diff --check` 通过，无截图或 UI 操作，视觉由用户验收。未提交、推送、发布。

## 当前运行：预览排版与真实卡片特效（2026-10-11 16:50）

预览工具栏同步 24 pt 按钮、10 pt 白色图标、12 pt 浅色文字、两侧 28 pt 和底部 12 pt 留白；主卡同步 62 pt 高/10 pt 内距/6 pt 行间距，外壳高度派生 158 pt，避免按钮贴角。按用户后续要求，主卡恢复单个真实 Metal 特效预览（既有 24 fps/有界分辨率/可见播放/减少动态/图片回退宿主）；壁纸和三个特效选项仍为图片，玻璃/经典切换保留。

排版包 `.build/preview-chrome-layout-runtime-20261011/` 于 16:49 构建运行 PID 88574；最终真实特效包 Debug arm64 增量编译成功，16:50 开发包更新重启 PID **89674**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；最终证据 `.build/preview-live-effect-runtime-20261011/`。`git diff --check` 通过；无 UI 检查、截图或性能采样，实际体验由用户验收。未提交、推送、发布。

## 当前运行：外观合并与图片材质预览（2026-10-11 16:45）

移除独立外观分类，材质切换合并至灵动岛页，设置窗口固定 darkAqua/深色并移除窗口外观选项。按用户后续明确要求继续采用图片方案：保留壁纸/任务特效图片和既有示例布局，重绘原生外层 clear 玻璃、55%–80% 黑色过渡、任务玻璃与按钮材质；经典纯色同步回退。隐私/宽度联动保留。主预览和三个特效选项不再挂载实时 Metal 宿主，无新增后台任务/计时器，真实灵动岛播放不变。

Debug arm64 增量编译成功，开发包更新重启 PID **85295**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/settings-material-merge-runtime-20261011/`。`git diff --check` 通过；没有截图、UI 操作或性能采样，视觉和性能体感由用户验收。未提交、推送、发布。

## 当前运行：侧栏背景填满（2026-10-11 16:40）

侧栏材质改为显式 Rectangle 填充，移除继承窗口 containerShape 引起的内侧右上/右下圆弧，仅由窗口外轮廓裁切外侧圆角。其余布局不变。

Debug arm64 增量编译成功，开发包更新重启 PID **81885**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/sidebar-fill-runtime-20261011/`。`git diff --check` 通过，无截图或 UI 操作，视觉由用户验收。未提交、推送、发布。

## 当前运行：设置经典左右分栏（2026-10-11 16:38）

用户要求设置改为左右分栏并沿用现有彩色图标。左栏固定 200 pt、24 pt 原彩色分类图标、38 pt 行高；保留八个分类，分三组，支持上下键切换。右侧标题/说明/预览/设置统一滚动，不固定占用预览高度。默认窗口 1040×760 pt、最小 920×600 pt，右侧内容最大宽 744 pt、左右内距 24 pt。现有设置功能与数据绑定保持。

Debug arm64 增量编译成功，开发包更新重启 PID **79690**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/settings-sidebar-runtime-20261011/`。`git diff --check` 通过；未截图、UI 操作或额外测试，视觉/键盘体验由用户验收。未提交、推送、发布。

## 当前运行：用量环 12 pt（2026-10-11 16:35）

环形进度外径改为 12×12 pt，线宽保持 2 pt；24 pt 胶囊左内距自动为 6 pt，圆心继续与左端圆弧同心。

Debug arm64 增量编译成功，开发包更新重启 PID **77709**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/quota-ring12-runtime-20261011/`。`git diff --check` 通过，未截图或操作 UI，视觉由用户验收。未提交、推送、发布。

## 当前运行：用量环同心对齐与减细（2026-10-11 16:33）

用量胶囊高 24 pt，与工具按钮一致。环形外径仍 14 pt，左内距由 8 改为 5 pt，使圆心与胶囊左端圆弧同在距左 12 pt 位置；线宽从 2.8 降为 2 pt，内绘制留白随半线宽变化。文字与右内距保持。

Debug arm64 增量编译成功，开发包更新重启 PID **75519**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/quota-ring-alignment-runtime-20261011/`。`git diff --check` 通过，无截图、UI 操作或额外测试，视觉由用户验收。未提交、推送、发布。

## 当前运行：底栏移除额外阴影（2026-10-11 16:30）

用户反馈底部按钮重阴影，已删除底栏整体黑色 0.45、半径 1 pt、下偏 1 pt 的额外阴影；保留原生 clear 玻璃自身光影、24 pt 按钮与 10 pt 图标。

Debug arm64 增量编译成功，开发包更新重启 PID **73455**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/footer-no-shadow-runtime-20261011/`。`git diff --check` 通过，未截图、UI 操作或额外测试，视觉由用户验收。未提交、推送、发布。

## 当前运行：系统工具图标 10 pt（2026-10-11 16:29）

用户要求恢复原系统符号：pin/pin.fill、chevron.up 恢复，顶部固定/收起/返回与底部刷新/设置图标统一 10 pt Medium；按钮仍 24×24 pt，状态文案 12 pt。移除新增 SVG 组件和三个编译资产，用户桌面原件保留，轻玻璃样式保持。

Debug arm64 增量编译成功，开发包更新重启 PID **71377**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码/资源输入、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/system-icons10-runtime-20261011/`。`git diff --check` 通过；无截图、UI 操作或额外测试，视觉由用户验收。未提交、推送、发布。

## 当前运行：SVG 12 pt（2026-10-11 16:25）

按用户要求，pin/pined/up SVG 完整画布均改为 12×12 pt，按钮保持 24×24 pt；状态映射、原始圆框/透明度和材质不变。

Debug arm64 增量编译成功，开发包更新重启 PID **68205**，仍 **0.7.9 Build 2 / 内部 60**。240 项源码/资源输入、包/备份与加载路径匹配，正式安装未改；证据 `.build/toolbar-svg12-runtime-20261011/`。`git diff --check` 通过，未截图或操作 UI，效果由用户验收。未提交、推送、发布。

## 当前运行：24 pt 按钮与 pin SVG（2026-10-11 16:22）

顶部/底部圆形工具按钮统一 24×24 pt，文字胶囊高度同步，底栏派生高 36 pt。用户 pin.svg、pined.svg、up.svg 原样进入矢量资产，分别对应未固定/已固定/收起；SVG 画布显示 22 pt 居中，内部图形约 12–13 pt，底部现有 12 pt 图标保留。保持原始白色透明度、轻玻璃及纯色回退。

Debug arm64 增量编译成功，开发包更新重启 PID **66055**，仍 **0.7.9 Build 2 / 内部 60**。240 项源码/资源输入、原有 13 项资产及新增 3 项工具图标确认编入，包/备份与加载路径匹配，正式安装未改；证据 `.build/chrome24-svg-runtime-20261011/`，新增图标记录 `toolbar-assets.json`。`git diff --check` 通过；未截图、UI 操作或额外测试，视觉由用户验收。未提交、推送、发布。

## 当前运行：工具按钮 22 pt（2026-10-11 16:17）

顶部/底部圆形工具按钮统一 22×22 pt，文字胶囊高度同步，底栏派生高度 34 pt；现有图标仍 12 pt。用户将提供 SVG 图标后再替换，目前未收到文件，未改图标。轻玻璃与纯色回退保持。

Debug arm64 增量编译成功并更新重启开发包 PID **62384**，仍 **0.7.9 Build 2 / 内部 60**。234 项源码、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/chrome22-runtime-20261011/`。`git diff --check` 通过，未截图、UI 操作或额外测试，视觉由用户验收。未提交、推送、发布。

## 当前运行：顶部/底部工具按钮 20 pt（2026-10-11 16:15）

顶部固定/收起及底部刷新/设置圆形按钮统一 20×20 pt，图标保持 12 pt；顶部同步 clear 原生玻璃与轻白染色。文字胶囊高度 20 pt、宽度按内容，底栏高随共享尺寸变为 32 pt。底栏状态文字仍 12 pt Medium。经典与减少透明度回退保留。

Debug arm64 增量编译成功，开发包更新重启 PID **60321**，保持 **0.7.9 Build 2 / 内部 60**。234 项源码、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/chrome20-clear-runtime-20261011/`。`git diff --check` 通过；未截图、UI 操作或额外测试，实际效果由用户验收。未提交、推送、发布。

## 当前运行：tokens 右缘对齐（2026-10-11 16:13）

tokens 向左收 4 pt，按 24 pt 操作按钮内 16 pt 图标的可见区域右缘对齐；无独立操作按钮的头卡不增加该补偿。10 pt 内距、6 pt 行间距和高度保持。底部轻玻璃按钮已包含在当前包。

Debug arm64 增量编译成功，开发包更新重启 PID **57305**，保持 **0.7.9 Build 2 / 内部 60**。234 项源码、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/token-icon-alignment-runtime-20261011/`。`git diff --check` 通过；无 UI 检查、截图或额外测试，效果由用户验收。未提交、推送、发布。

## 当前运行：底部工具按钮轻玻璃（2026-10-11 16:12）

刷新/设置等底部共享按钮改为原生 clear 玻璃和 0.04 白色轻染色，移除重黑染色。头部按钮保持，经典/减少透明度仍纯色回退，旧系统 ultraThinMaterial。大小、点击及 hover 行为保持。

Debug arm64 增量编译成功，开发包更新重启 PID **55950**，保持 **0.7.9 Build 2 / 内部 60**。234 项源码、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/footer-clear-glass-runtime-20261011/`。`git diff --check` 通过；没有截图、UI 操作或额外测试，实际效果由用户验收。未提交、推送、发布。

## 当前运行：底部透明度渐隐（2026-10-11 16:07）

按用户 16:05 反馈保留顶部黑色渐层，删除底部黑色覆盖。仅跨过下边界的任务卡/详情使用最多 12 pt alpha 渐变；外层玻璃背景不在遮罩中，完整卡片不加 mask，边界在空隙时停用。底部渐隐修饰器观察滚动位置，轨道/顶部仍由 CALayer 更新；没有新增轮询。截断卡片的合成及实际视觉仍待用户验收。

Debug arm64 增量编译成功，开发运行包更新重启 PID **51910**，保持 **0.7.9 Build 2 / 内部 60**。234 项源码、13 项资产、包/备份及加载路径匹配，正式安装未改；证据 `.build/bottom-alpha-fade-runtime-20261011/`。`git diff --check` 通过；未截图或操作 UI、未运行额外测试。未提交、推送、发布。

## 当前运行：列表上下边缘局部渐隐（2026-10-11 16:03）

用户 16:00 截图否定先前系统 soft 效果，外层列表现改为独立 AppKit 黑色到透明渐层：上下最多 12 pt，仅在任务卡或详情跨过视口边界时触发，深度随越界距离和剩余可见长度收缩。完整卡片和间隙不启用，横向限定卡片区域；不遮罩玻璃祖先、不覆盖轨道或固定头尾。原生滚动通知直接更新 CALayer，详情内部系统 soft 保留。此为局部遮蔽过渡，底部玻璃融合程度未视觉验收。

Debug arm64 增量编译成功，16:03 开发运行包更新重启 PID **48554**，仍为 **0.7.9 Build 2 / 内部 60**。234 项源码、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/list-edge-fade-runtime-20261011/`。`git diff --check` 通过；未作 UI 操作、截图或额外测试，由用户验收。未提交、推送或发布。

## 当前运行：完成与运行 Demo 分开（2026-10-11 15:59）

完成 Demo 已移除子 Agent，按真实完成组件显示 62 pt 双行卡；新增独立 working 父任务 Demo，第三行为工作中、思考中及已完成子 Agent，卡高 90 pt。两张均复用生产组件且标记 DEBUG/DEMO，各自归档可关闭对应偏好，不进入真实会话操作。四边 10 pt、行间 6 pt 规则保留。

Debug arm64 增量编译成功并更新重启开发版 PID **44818**，仍为 **0.7.9 Build 2 / 内部 60**。234 项源码、13 项资产、包/备份与加载路径匹配，正式安装未改；证据 `.build/two-state-demo-runtime-20261011/`。`git diff --check` 通过，无 UI 检查或截图，效果由用户验收。未提交、推送、发布。

## 当前运行：卡片四周 10 pt、行间 6 pt（2026-10-11 15:57）

用户 15:53 反馈 tokens 靠边，现将任务卡四周内距改为 10 pt、两行间距 6 pt、两行各 18 pt，基础高计算为 62 pt；内宽明确为卡片宽度减 20 pt。归档按钮、子 Agent 两侧及底部、长模型测量、详情内距同步；详情范围 62–132 pt，带子 Agent 标准卡高 90 pt。列表占位/滚动步距、审批头卡与主区域进度特效沿用共享尺寸，轮廓仍为 16 pt continuous。常驻 DEBUG Demo 保留。

Debug arm64 增量编译成功，15:57 更新并重启开发包 PID **43434**，版本仍 **0.7.9 Build 2 / 内部 60**。234 项源码输入、13 项资产、包与备份及加载路径匹配，正式安装未改；证据 `.build/card-insets10-runtime-20261011/`。`git diff --check` 通过；没有 UI 检查、截图或额外测试，视觉由用户验收。未提交、推送或发布。本节覆盖下方 8 pt/60 pt 排版记录。

## 当前运行：统一卡片排版与岛内常驻 Demo（2026-10-11 15:52）

按用户要求直接在灵动岛注入完整 DEBUG Demo，未建立新开发台。仅 Debug + 开发 bundle + `debug.completeCardDemo` 偏好启用，当前已开启；模拟完成卡带三名子 Agent 和完成详情，首次显示固定展开，归档可关闭并持久化。数据仅进入显示投影，不发送真实任务选择或归档。该授权例外与发布前清理约束已记录 AGENTS。用户要求去掉的 Computer Use 鼠标对应 SkyComputerUseService 已终止；没有截图确认。

完成 AI 球已移至标题左侧，18 pt；完成玻璃为近黑微绿 RGB (0.025, 0.055, 0.035)，不恢复绿色描边。两行各 18 pt、间距 8 pt、四边内距 8 pt，基础高 60 pt；两种任务状态共用宽度和 16 pt continuous 轮廓，额外子 Agent/长模型行才增高。

15:52 Debug arm64 增量编译成功，开发运行包更新并重启 PID **39030**，仍为 **0.7.9 Build 2 / 内部 60**。234 项源码输入、13 项资产、包与备份清单及实际加载路径匹配，正式安装未改。证据 `.build/resident-card-layout-runtime-20261011/`；前序浅绿与标题球证据 `.build/completed-subtle-green-runtime-20261011/`、`.build/completed-title-orb-runtime-20261011/`。`git diff --check` 通过；没有 UI 检查、截图或新增测试，视觉由用户验收。未提交、推送或发布。

## 当前修订：柔和滚动边缘与完成卡绿色玻璃（2026-10-11 15:39）

任务列表与详情内部滚动区在 macOS 26 接入系统 `.scrollEdgeEffectStyle(.soft, for: .vertical)` 并显式启用，不遮罩原生玻璃祖先；旧系统保留原滚动回退。详情仍在 60–128 pt 内按内容适应。完成任务卡移除额外绿色描边，原生玻璃 tint 改为低饱和绿 RGB (0.12, 0.30, 0.19)，普通/hover 透明度 0.50/0.40；子 Agent 行共享染色，选中完成卡既有边缘呼吸保持。

15:39 Debug arm64 增量编译成功并重启开发版 PID **28161**，仍为 **0.7.9 Build 2 / 内部 60**。234 项输入、13 项资产、完整包/备份及加载路径匹配，正式安装未改；最终证据 `.build/completed-green-glass-runtime-20261011/`，前序软边包 `.build/island-soft-scroll-edges-runtime-20261011/`。没有 UI 操作、截图或测试；原生软边是否达到期望与淡绿色材质效果均待用户检查，未提交/推送/发布。

## 当前修订：移除详情较早记录（2026-10-11 15:32）

按用户要求移除生产详情的较早记录入口、数量、展开内容、更早记录提示和对应布局占位/界面状态，只显示最近公开进展与工具信息或最终回答；原始活动数据、当前工具原文和独立开发台保留。15:32 Debug arm64 增量编译成功并重启开发版 PID **18779**，身份仍为 **0.7.9 Build 2 / 内部 60**。234 项输入、13 项资产、完整包/备份及加载路径匹配，正式安装未改；证据 `.build/detail-no-history-runtime-20261011/`。未做 UI 操作、截图或测试，效果待用户检查，未提交/推送/发布。

## 当前修订：详情自适应高度、字号和间距（2026-10-11 15:29）

用户 15:26–15:28 要求更小正文、消除空白、统一间距，并否定手动收窄按钮和过窄标题栏。最终正文与详情标题同为 12 pt，高度按内容在 60–128 pt 内自动贴合，超过上限才滚动；中间添加的大小按钮与其状态已移除。标题栏 24 pt，上下内距各 8 pt、正文间隔 6 pt；内容块间距 6 pt、工具内距 6 pt/内部间距 4 pt。公开正文复用同一 TextKit 排版进行测量与显示，Markdown 末段不额外留白，次要灰色和原文保留。

15:29 Debug arm64 增量编译成功，已重启开发版 PID **16133**；仍为 **0.7.9 Build 2 / 内部 60**。234 项输入、13 项资产、完整包/备份及加载路径匹配，正式安装未改。最终证据 `.build/detail-adaptive-spacing-runtime-20261011/`；中间按钮版本在 `.build/detail-size-toggle-runtime-20261011/`，不代表当前实现。未做 UI 操作、截图或测试，效果由用户检查，未提交/推送/发布。

## 当前修订：子 Agent 特效边界与详情文字层级（2026-10-11 15:23）

用户 15:18 要求子 Agent 第三行与主内容分隔、进度特效保持原范围，15:22 看图后改为取消分割线。最终实现无分割线；进度渲染表面按主内容高度（常规 60 pt）顶部对齐，不因第三行扩展，父子仍共用完整玻璃，完成描边与边缘辉光保持完整卡片轮廓。列表与审批共用此实现。15:20 要求详情正文与标题区分：正文和工具文本改用“查看原文”同款 #B3B3B3 次要色，完成 Markdown 普通正文复用相同令牌，标题/强调/链接层级保留。

最终 Debug arm64 增量编译成功，15:23 重启开发版 PID **8205**，仍为 **0.7.9 Build 2 / 内部 60**。234 项源码输入、13 项资产、完整包/备份及加载路径匹配，正式安装未改；证据 `.build/subagent-no-divider-runtime-20261011/`。前序分割线包与文字色包分别保留在 `.build/subagent-divider-effect-runtime-20261011/`、`.build/detail-secondary-text-runtime-20261011/`。未进行 UI 操作、截图、测试或性能采样；最终视觉由用户检查，未记录通过，未提交/推送/发布。

## 当前修订：详情占格、滚动宽度与子 Agent 第三行（2026-10-11 15:15）

普通进展和完成详情按内容占一格 60 pt 或两格 128 pt，标题/关闭入口固定，长正文在内部滚动；采用任务卡相同的 16 pt 连续曲率轮廓与深色玻璃，材质不放进正文裁切层。去掉重复来源、“最近进展”和成功退出码等标签，收紧间距，原文、失败信息、命令展开和较早记录入口保留。首个紧凑包于 15:12 启动 PID 91052，用户随后反馈滚动条出现时撑宽；当前补充任务卡、详情卡、正文视口的显式宽度约束及覆盖式原生滚动条，轨道只占内部预留空间。

子 Agent 已从外接条带合入父任务卡的第三行（28 pt），共享一个完整玻璃表面及描边/辉光轮廓；多子 Agent 继续横向展示，长模型补充行保留。审批头卡同步，并改为与标题行共用归档按钮垂直对齐线。既有几何断言已同步新布局，未新增或运行测试。

15:15 Debug arm64 增量编译成功，开发运行包已更新并重启 PID **94192**，仍为 **0.7.9 Build 2 / 内部 60**。234 项源码输入、13 项资产、完整包/备份及加载路径匹配，正式安装未改；最终证据 `.build/detail-subagent-width-runtime-20261011/`，首个详情包 `.build/detail-card-slots-runtime-20261011/`。没有 UI 操作、截图或性能采样，实际宽度、滚动、第三行与轮廓由用户检查，尚无通过结论。未提交、推送或发布。

## 当前修复：卡片边缘发光与右上角对齐（2026-10-11 15:01）

用户要求修复整卡青色发亮，并使模型、时长与 Agent/归档图标垂直居中。任务卡辉光改为空心 1 pt 轮廓和环形阴影源，单独的辉光遮罩扣除内部，只保留 2 pt 内缘及外侧呼吸；不再依赖黑色实心卡面遮挡彩色光源，也不遮罩玻璃祖先。旧单岛/外围提醒默认光源保持。右上角控件跟随标题行的共用垂直中心线，替代固定顶部 6 pt 偏移，归档仍为独立的 24 pt 命中目标。

Debug arm64 增量编译成功并更新开发版 PID **79816**，仍为 **0.7.9 Build 2 / 内部 60**。234 项源码输入、13 项资产、完整包/备份及实际加载路径匹配，正式安装未改；证据 `.build/card-edge-alignment-runtime-20261011/`。本轮未做 UI 操作、截图、单元测试或性能采样；视觉由用户检查，尚未获通过结论。未提交、推送或发布。上轮已授权的活跃外观兼容修复保留。

## 当前修复：首次展开玻璃活跃外观（2026-10-11 14:55）

用户明确回复“允许此兼容修复”，候选补丁已应用至 `IslandNotchPanel`：四个未公开 AppKit 外观查询恒定返回活跃，均为无状态 `nonisolated` 方法；不覆盖真实 key 状态、不添加激活应用或抢焦点调用。首次展开不再需要以固定动作作为活跃外观的代码前提。经典纯色、原固定/悬停交互、卡片和 55%–80% 过渡保留。此为已授权的窗口外观兼容例外，未引入私有光学滤镜、截图采样、全局方法替换或轮询；详见[规格](docs/specs/island-expanded-glass.md#首次展开活跃外观修复2026-10-11已授权)。

**当前运行包已更新，视觉结果待用户检查。** 14:55 Debug arm64 增量编译成功并重启 PID **74867**；仍为 **0.7.9 Build 2 / 内部 60**。234 项源码输入、13 项资产、完整运行包、备份和实际加载路径匹配；正式安装未改。证据 `.build/glass-active-panel-runtime-20261011/`。遵照用户最新要求，本轮没有 UI 操作、截图、隔离探针、单元测试或性能采样；不能宣称首次展开/固定/失焦已通过视觉验收。未提交、推送或发布。

## 修复前反馈：首次展开玻璃仍未恢复（2026-10-11 14:50）

用户两张截图再次确认非固定/首次展开与固定后的材质有明显差异，上一轮不算修复完成。随后明确要求由用户检查，停止主动 UI 验证。当前生产源码/运行包仍为下方 14:25 版本，PID 61559（本轮只读核对），没有新增构建。

准备了仅作用于 IslandNotchPanel 的活跃外观兼容补丁 `.build/island-active-appearance-proposal-20261011/IslandConceptBoard.patch`，未应用。它通过未公开的 AppKit 窗口外观查询保持材质活跃，不获取真实键盘焦点；考虑现行“不引入私有光学 API”约束，待用户确认此窄范围例外后再应用。参考和限制见同目录 README。不得将候选方案写成已修复或已运行。

## 当前修订：外观切换与玻璃实机诊断（2026-10-11 14:25）

新增“外观”设置页，液态玻璃/经典纯色立即切换并持久化；经典模式释放外层玻璃、停用卡片与按钮材质。已实机验证双向切换、经典重启保持、恢复液态玻璃及再次重启选中状态，最后偏好为 `liquidGlass`。连续曲率深色任务卡、无框 Agent/归档图标和 55%–80% 黑色渐变保留；按照 DroppyKit 的明确渲染约束移除玻璃祖先 mask，仅裁切黑色渐变。外层现为独立 SwiftUI Clear 玻璃宿主，旧系统毛玻璃保留圆角。

**未完成：非激活面板的通透度与高光仍未达到 Droppy。** 用户 13:56 明确否定首版。授权实机检查后，观察到仅置顶即可恢复高光，无需改变尺寸；首次布局、公开 SwiftUI 活跃环境等隔离探针均未解决，无效覆盖已撤回，不抢走悬停时的键盘焦点。Droppy 16.0.1 主源码未能取得；公开旧 fork 与官方 DroppyKit 不包含当前 DynamicGlassMelt，实现不能宣称逐行复刻。已询问用户是否有当前源码路径。继续时优先解决此项，勿再仅凭猜测调整透明度或记录视觉通过。

最终 Debug arm64 增量编译通过并启动 PID **61559**，仍为 **0.7.9 Build 2 / 内部 60**。234 项源码输入、13 项资产、完整包及实际加载路径匹配，正式安装未改。证据 `.build/glass-final-runtime-20261011/`；前序设置持久化/公开 API 探针对照见[规格](docs/specs/island-expanded-glass.md#当前证据与边界)。用户授权范围内进行了窗口截图和有限 UI 操作，未新增单元测试或性能采样，未提交真实回答/归档/额度重置。临时 GlassProbe 已退出。未提交、推送或发布。

## 当前外观：连续曲率任务卡与原生玻璃（2026-10-11 13:54）

卡片右侧 Agent/归档按钮移除玻璃外框，保留原图标与 24 pt 命中区域。任务卡/审批头卡改为 16 pt 连续曲率轮廓和深色原生玻璃，移除实心黑底；完成描边与外光同步轮廓，子 Agent 材质仅覆盖下方条带。外层黑色节点改为 0/55/67.5/80/100%，alpha 为 1/1/.45/0/0；Clear 原生玻璃侧边对齐岛体下部，移除人工白色描边。保留隐藏页 `.identity` 和重置转场生命周期修复。

Debug arm64 增量编译通过并启动 PID 30405，仍为 0.7.9 Build 2 / 内部 60，开发身份不变；234 项源码输入、13 项资产、完整运行包及实际加载路径一致，正式安装未改。证据 `.build/glass-card-refine-runtime-20261011/`；修改前源码 `.build/glass-card-refine-20261011/`。未新增/运行测试、UI 自动化或性能采样；卡片材质、实际通透度、高光与流畅度待用户验收。未提交、推送或发布。

## 当前修复：重置卡 3D 转场（2026-10-11 13:36）

玻璃启停改为稳定修饰器的 `.identity` 切换，保留内容与锚点身份；飞行宿主始终挂载，等待窗口/有效布局，避免首次更新时丢弃动画。Core Animation 在事务提交时起播，由实际完成回调交接静态卡片，取消点击后固定 0.8 秒截断；仅保留未启动时的 2 秒恢复保护。快速返回、隐藏/卸载和旧回调按序号隔离。原 0.76 秒 3D 轨迹及任务卡片材质保持，无新增逐帧刷新。

Debug arm64 增量编译通过并启动 PID 15235，仍为 0.7.9 Build 2 / 内部 60。234 项源码输入、13 个资产、完整运行包及加载路径一致，正式安装未改。最终证据 `.build/reset-flight-commit-runtime-20261011/`；前一步运行证据 `.build/reset-flight-lifecycle-runtime-20261011/`。未新增/运行测试、UI 自动化或帧率采样；动效是否完整、真实流畅度待用户验收。本轮未推送或发布。

## 当前修复：玻璃图层遮挡（2026-10-10 20:40）

用户 20:39 截图显示用量正文被背景玻璃覆盖、隐藏重置按钮泄漏。移除全页 GlassEffectContainer，用量卡片将内容直接交给玻璃修饰器；新增可见性环境值，隐藏用量/重置页及收起态停用玻璃，保留布局与转场锚点。任务卡片材质未变。

增量编译并启动 PID 24940，仍为 0.7.9 Build 2 / 内部 60，234 项输入和完整包/加载路径匹配；证据 `.build/glass-layer-fix-runtime-20261010/`。实际画面待用户复核；未新增测试、截图或发布。

## 当前开发：玻璃控件与用量卡片（2026-10-10）

保留任务卡片背景；按钮、用量卡片、重置动作采用共用原生玻璃样式，增强次要文字对比度，保留主操作/危险操作及禁用语义。采用 GlassEffectContainer，未为图表柱子或 Token 方格增加玻璃，无新计时器。详见[玻璃规格](docs/specs/island-expanded-glass.md)。

20:38（上海）增量编译并更新开发版，PID 22555；仍为 0.7.9 Build 2 / 内部 60。234 项输入、13 项资产、完整包和加载路径匹配；正式安装未变。本轮未新增/运行测试或性能采样，实际可读性与流畅度待用户验收；未推送。证据 `.build/glass-controls-final-runtime-20261010/`。

## 当前外观修订：Droppy 百分比梯度（2026-10-10）

用户要求仅修改外层黑色渐变与玻璃/边缘，内部卡片不动。按参考截图估计，黑色覆盖顶部 40%，40%–65% 快速过渡，底部约三分之一通透；使用 Clear 原生玻璃与向下增强的 0.8 pt 高光描边，比例随岛体高度缩放。

开发版已增量编译并启动，PID 18134，0.7.9 Build 2 / 内部 60；234 项输入及完整包/加载路径匹配。证据 `.build/glass-droppy-gradient-runtime-20261010/`。未新增/运行测试，真实视觉待用户验收；未推送发布。下方为上一版运行记录。

## 当前开发：展开态液态玻璃（2026-10-10）

按用户 Droppy 截图制作第一版：展开背景使用 macOS 26 原生玻璃、顶部黑色渐变、下部透明材质与细描边；收起保持黑色。减少透明度时回退黑色，旧系统使用原生毛玻璃。布局、尺寸及点击路由沿用，未增加逐帧计时器或截图采样。

20:26（上海）增量构建并启动 PID 12675，身份仍为 0.7.9 Build 2 / 内部 60；234 项输入、13 项资产及完整运行包/加载路径一致。正式安装未变，运行正式版主进程已退出。未新增/运行测试或视觉自动化，实际效果待用户验收；本次新外观尚未推送。规格 [展开态玻璃](docs/specs/island-expanded-glass.md)，证据 `.build/liquid-glass-runtime-20261010/`。

## Build 2 源码已合并 main（2026-10-10）

[PR #90](https://github.com/Duoasa/QuotaView/pull/90) 已合并，main 提交 `8cef117c69f04e78c37b234a83ddb6adbe01c1ba`。PR CI `38028275285` 与 main CI `38028483240` 均通过（Swift tests / 原生问题关闭契约夹具）。234 项运行包构建输入与合并提交一致，无需重复编译。独立文档整理及原型仍保留本地；未发布 Build 2 或更新 appcast。证据 `.build/confirmation-main-merge-20261010/result.json`。下方未推送描述为合并前阶段记录。

## 当前开发身份：0.7.9 Build 2（2026-10-10）

用户要求 Build +1，App、Widget 和兼容 Info.plist 已同步为显示 Build 2 / 内部 60。包含下方确认订阅同步修复。11:29（上海）增量编译并启动开发包，PID 19261；234 项输入、13 项资产、完整包及加载路径匹配。证据 `.build/079-build2-runtime-20261010/`。正式安装仍为 Build 1，未推送或发布，Build 2 未获 appcast 准入。仅版本身份变化，未重复功能测试。

## 当前开发修复：Codex 确认订阅同步（2026-10-10）

- 本地源码在 0.7.9 基线上修复状态流重建后旧 revision 阻挡新请求的问题；每个 ledger 生命周期具有独立 streamGeneration，同代次保持序号校验，旧代次快照与旧句柄不能恢复操作能力。延迟 owner discovery 也按独立尝试身份撤销。
- 异步问题及真实审批的隔离复现已转为回归测试，包含序号降低、迟到快照、重复快照和旧句柄失效。两轮共 95 项不同针对性测试通过（63 + 34，重叠 2 项）；未向真实任务提交回答。
- 11:10（上海）已更新并启动开发包，PID 13771；身份仍为 `com.quotaview.development073` / 0.7.9 / 显示 Build 1 / 内部 59。234 项生产输入、13 项资产、完整包及实际加载路径匹配。正式版主进程已退出，正式安装文件未变；新修复未推送或发布，真实交互待用户验收。
- 证据：`.build/confirmation-stream-runtime-20261010-verified/`；前两次替换因退出确认失败自动回退，最终记录与回退包以该目录 `runtime-result.json` 为准。
- 下方公开发布及旧运行记录保留；当前开发源码和运行包已领先发布 tag。

## 当前发布：0.7.9 Build 1（2026-10-09，已完成）

**公开稳定版：0.7.9 Build 1 / 内部 59**，源码经 [PR #88](https://github.com/Duoasa/QuotaView/pull/88) 合并 main，GitHub Stable / Latest 与签名 appcast 已发布且公开回下载核验通过。完整 tag、资产、哈希、签名、公证、Feed 和 CI 证据只保存在[版本历史](VERSION_HISTORY.md#当前最新版本)；回滚入口 `v0.7.7-build.1`。

开发包仍为 `.build/DevelopmentRuntime/QuotaView.app` / `com.quotaview.development073`，18:54 已更新 `0.7.9 / 1 / 59`，PID 42476；包含 DSH ACK 延迟修复，234 项输入、13 项资源及加载路径匹配。正式安装保持独立，旧版运行记录仅作历史参考。

发布前最终 700 项本地测试无跳过/失败；44 项确认契约及 DSH/Kimi 隔离事件夹具通过。新封面和精简双语 README/英文 Release 已更新。视觉与真实客户端交互仍由用户验收，详见[发布规格](docs/specs/release-0.7.9.md)。独立历史文档整理和原型继续保留在本地。

更新：2026-10-09。公开稳定版与回滚发行资产见[版本历史](VERSION_HISTORY.md#当前最新版本)。
本页只保存当前工作；历史运行记录与旧计划见[清理前快照](docs/archive/maintenance-20261008/README.md)。

2026-10-09 用户最新持续授权：每次应用源码、UI 或资源修改完成后，增量编译、更新并启动当前开发版，不再等待单独“启动”。保持开发身份；正式打包、发布与推送仍需对应授权。规则见 [AGENTS.md](AGENTS.md#验收与开发工具)。

## 工作区与版本定位

| 对象 | 当前事实 |
|---|---|
| 开发工作区 | `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget` |
| 分支 / 源码提交 | `codex/0.9.1-agent-announcement`；HEAD `d4b5557`（Build 2 经 PR #126 合并）；Build 3 到期日期修改与交付记录保留本地 |
| 开发身份 | `com.quotaview.development073`；源码与运行包均为 0.9.1 / Build 3 / 内部 136 |
| 运行包 | `.build/DevelopmentRuntime/QuotaView.app` |
| 最近运行核验 | 2026-11-01T17:09:34.502648+08:00；PID 18611，254 输入、18 项资源、完整包与加载路径一致，无临时参数 |
| 源码与运行包 | 0.9.1 Build 3 已运行，新增重置卡到期日期，继承 Build 2 功能；新 Agent 的真实客户端验证边界保持，视觉/交互由用户验收。 |
| 公开稳定版 | 0.8.6 Build 21；完整事实与回滚入口见 [版本历史](VERSION_HISTORY.md#当前最新版本) |
| 本机正式安装 | 当前实测 `/Applications/QuotaView.app` 为 0.8.3 Build 1 / 内部 75；本轮未替换 |

PID 仅是这次核验记录；继续任务先核对 `git worktree list`、目标 Git 状态及实际进程，不按目录名、版本号或历史 PID 推断源码。

## 代理虚线参考样式（2026-10-09，已进入开发包）

- 按用户新提供的流程图参考，将两段连接改为白色虚线、实心菱形起点与实心三角终点；替代上一轮圆环和沿线小箭头。线宽 1.2 pt，虚实间距 3/2 pt，末端三角 8 pt；以细暗影保证亮壁纸对比度。
- 保留 2.4 秒流光周期（测试时 1.2 秒），高光使用同一虚线路径遮罩，避免动画填平间隙；原停播和性能约束保持。
- 18:26 Debug arm64 增量编译通过，开发包已替换启动 PID 22429；234 项输入、13 个资源及完整包/备份、加载路径一致，开发身份与正式安装不变。未新增/运行测试或 UI 自动化，视觉待验收。
- 证据 `.build/proxy-dashed-route-runtime-20261009/`；修改前源码 `.build/proxy-dashed-route-20261009/`；旧包 `.build/runtime-package-backups/proxy-dashed-route-20261009-182646/QuotaView.app`。本轮未推送发布。

## 代理连线细节与节奏（2026-10-09，已进入开发包）

- 用户反馈箭头看不清、流光过慢，要求连线细节丰富。新增圆环端点、暗色衬线/白色渐变内线、两处方向标记与 11 pt Bold 白色主箭头，细暗影保证亮色壁纸上对比度。
- 流光从 28 × 2 pt 调整为 36 × 2.5 pt；完整周期由 4.8 秒缩短为 2.4 秒，实际测试时 1.2 秒。仍复用两个 Core Animation 图层，顺序运动，隐藏/失败/Reduce Motion 停播，不增加轮询。
- 18:16 Debug arm64 增量编译通过，替换启动 PID 19736；234 项输入、13 个资产、完整包/备份及 App/Core 加载路径匹配。身份仍为 0.7.7 / 显示 Build 2 / 内部 58，正式安装未变。
- 证据 `.build/proxy-route-detail-runtime-20261009/`，修改前源码 `.build/proxy-route-detail-20261009/SettingsView.swift.before`；旧包 `.build/runtime-package-backups/proxy-route-detail-20261009-181603/QuotaView.app`。未新增/运行测试或 UI 自动化，视觉待验收；未推送发布。

## 用量图表显示微调（2026-10-09，已进入开发包）

- 成本与 Token 图表的横向滚动条改为 3 pt 轨道、4 pt 滑块，保留原生拖动/命中区域，减少额外底部留白。
- Token 方格最小边长从 8 pt 放大至 10 pt，间距仍为 3 pt；53 列内容最小宽度 686 pt，继续横向滚动并默认显示最近数据。成本柱宽不随本次方格调整变化。
- 增量编译通过并替换启动 PID 18083；234 项源码输入、完整运行包/备份和实际加载路径匹配。开发身份不变，未新增/运行测试或 UI 自动化；视觉与拖动由用户验收。
- 证据 `.build/chart-polish-runtime-20261009/`，修改前源码 `.build/chart-polish-20261009/`；旧包 `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget/.build/runtime-package-backups/chart-polish-20261009-181235/QuotaView.app`。本轮未推送或发布。

## 设置实时动效（2026-10-09，已进入开发包）

- 用户最新要求替代静态特效限制：上方示例卡与三个效果选项都接入真实 Metal 渲染，固定 60% 工作状态；宽度、隐私、示例和原布局保持。
- 复用现有缓存管线；仅设置预览限制 24 fps、1 像素/pt，无逐帧 SwiftUI 状态。窗口不可见/最小化、应用隐藏、滚出视口和卸载停播；Reduce Motion 静止，Metal 不可用回退图片。正式任务渲染预算保持原样。
- 17:24 Debug arm64 增量编译通过，替换启动 PID 7419；版本仍 0.7.7 / 显示 Build 2 / 内部 58。234 项输入、13 个资产、完整包/备份与 App/Core 加载路径匹配，正式安装未变。
- 证据 `.build/settings-live-preview-runtime-20261009/`；修改前源码 `.build/settings-live-preview-20261009/`；旧包 `.build/runtime-package-backups/settings-live-preview-20261009-172454/QuotaView.app`。
- 未新增/运行测试或 UI 自动化；未采集 GPU 耗时/掉帧/能耗，视觉与实机性能待用户验收。未推送或发布。规格：[实时特效预览](docs/specs/settings-live-effect-preview.md)。

## 展开宽度与图表横向滚动（2026-10-09，已进入开发包）

- 设置 → 灵动岛 → 显示新增“展开宽度”，普通范围 560–680 pt、默认 680 pt；依据实际刘海宽度自动保留两侧各 144 pt 工具空间。偏好持久化，仅影响任务列表/内联详情与用量页，收起态、审批、额度重置保持原宽度规则。
- 双额度继续横排，窄卡内部允许文字换行；账户列随宽度收紧。成本柱与 Token 方格至少 8 pt，空间不足时使用原生横向滚动条；初次打开、切换来源/模式、宽度或日期变化定位最近数据，普通数据刷新保留历史阅读位置。Tooltip 锚点在滚动裁切层外绘制，保留相邻卡片层级修复。
- Debug arm64 增量编译通过，16:26（上海）替换启动 PID 92747；身份保持 0.7.7 / 显示 Build 2 / 内部 58。234 项输入、13 个资产、完整包/备份与 App/Core 实际加载路径匹配，正式安装身份及可执行文件未变。
- 证据 `.build/island-width-runtime-20261009/`，修改前源码 `.build/island-width-20261009/`；旧运行包 `.build/runtime-package-backups/island-width-20261009-162621/QuotaView.app`。
- 当前可读取屏幕为无刘海 1920 × 1080 pt；没有带刘海实机视觉结论，范围两端、图表滚动/hover、两侧空间和独立页面尺寸待用户验收。未新增/运行测试、截图或 UI 自动化；本轮没有推送或发布。
- 用户后续要求设置可视化也随宽度变化：静态预览按实际宽度/上限映射，680 pt 对应 510 pt、560 pt 对应 420 pt；保持顶部居中、高度、字号与图标尺寸，任务卡/工具栏重新排布，原轮廓只伸缩中段以保留圆角与阴影。完整示例、隐私与静态特效联动继续生效。
- 预览修订再次增量编译通过，17:04（上海）替换启动 PID 3115；234 项输入、13 个资产、完整运行包/备份及 App/Core 加载路径匹配，开发身份和正式安装保持原样。未新增/运行测试或 UI 自动化，视觉待用户验收。
- 最新证据 `.build/island-width-preview-runtime-20261009/`；预览修改前源码 `.build/island-width-preview-20261009/SettingsView.swift.before`；最近旧包 `.build/runtime-package-backups/island-width-preview-20261009-170415/QuotaView.app`。
- 规格：[展开宽度与窄屏图表](docs/specs/island-expanded-width.md)。此前 PR #87 的 CI 仅对应上一批已合并源码，不覆盖本轮功能。

## 源码推送与 main 合并（2026-10-09）

- 按用户本次授权，将当前应用源码、资源及对应功能说明通过 [PR #87](https://github.com/Duoasa/QuotaView/pull/87) 合并。功能提交 `4fdbcda`，断言同步提交 `736d397`；16:04（上海）合并为 `4dd1e50`。独立历史文档整理、归档包与未跟踪原型未纳入本次提交。
- 首次 CI 唯一失败为 `Island073SmokeTests` 仍要求特效预览不超过 32 pt；按用户已要求的 56 pt 更新现有断言，保留圆角与裁切检查。未增加测试，也未为此改动应用源码或重建相同运行包。
- PR 提交 `736d397` 的 [CI 37902336835](https://github.com/Duoasa/QuotaView/actions/runs/37902336835) 已通过 Swift tests 与 native question closure contract fixtures；合并提交 `4dd1e50` 的 [CI 37902770195](https://github.com/Duoasa/QuotaView/actions/runs/37902770195) 同样全部通过；已核对远端 main 指向该提交。
- 本次合并时 15:50 开发包的 234 项构建输入与 main 逐项匹配，身份仍为 0.7.7 / 显示 Build 2 / 内部 58；没有正式打包或发布。记录见 `.build/push-main-20261009/`。CI 通过不代表用户视觉验收通过。

## 代理简化与关于居中（2026-10-09 15:50，已进入开发包）

- 用户认为 15:35 方案不合格，要求不滥用色块、保留合理特效、排版简洁规整，指出关于明显偏向一侧；该版没有视觉通过结论。
- 关于偏移来自文字列 `.frame(maxWidth: .infinity)` 将右侧空白计入居中。改为图文组按固有宽度整体居中，保留 80 pt 图标、22 pt 间距、28 pt 标题和 12 pt 说明，版本改为 11 pt 纯文字，移除浅色胶囊。
- 代理移除大面积白色卡片、地址/状态胶囊，改为三个 104 pt 等宽节点、52 pt 小面积原生玻璃底托；图标中心与细线对齐，标题同一基线，地址和状态置于下方一行。macOS 14–15 使用 regularMaterial 回退。
- 两段流光用共享媒体时间顺序播放，平时周期 4.8 秒、测试时 1.6 秒；只表达路由方向，实际连接结果仍来自现有测试。无效/失败、切页、隐藏/最小化及 Reduce Motion 停止；不增加帧计时器、状态轮询或自动网络请求。
- Debug arm64 增量编译通过，15:50（上海）替换启动 PID 75842，身份仍为 0.7.7 / 显示 Build 2 / 内部 58。234 项输入、13 个资产、完整包、旧包备份与 App/Core 实际加载路径一致，正式安装身份及可执行文件不变。
- 证据 `.build/proxy-about-refine-runtime-20261009/`，修改前源码 `.build/proxy-about-refine-20261009/SettingsView.swift.before`；旧运行包 `.build/runtime-package-backups/proxy-about-refine-20261009-155003/QuotaView.app`。未新增/运行测试、截图自动化或真实代理测试，视觉及动画仍待用户验收。未推送或发布。

## 代理与关于首轮可视化（2026-10-09 15:35，已由上方修订替代）

- 代理旧模块只有 5% 白色底面，在壁纸上几乎不可见。改为三张完整近白色卡片：同高 92 pt、宽 120 / 172 / 120 pt，图标和标题置于卡片内，中央显示协议与草稿地址；链路总宽 540 pt，底部保留独立状态胶囊。没有增加整体黑框。
- 代理模式/协议与状态加入短淡入；仅真实连接测试期间沿箭头播放轻量 Core Animation 流动。每条线只移动一个图层，无帧计时器或逐帧 SwiftUI 状态更新；测试结束、切页、窗口隐藏/最小化及 Reduce Motion 停止。直连、配置无效和测试结果单独呈现，不将直连误标为成功。
- 关于页图标从 96 pt 调整为 80 pt，图文间距 22 pt，名称 28 pt、说明 12 pt，实际版本采用 24 pt 高浅色胶囊。继续使用壁纸，无外层黑色面板。
- Debug arm64 增量编译通过，15:35（上海）替换启动 PID 71831；0.7.7 / 显示 Build 2 / 内部 58 不变。234 项输入、13 个资产、完整包与 App/Core 实际加载路径匹配，正式安装身份及可执行文件保持不变。
- 证据：`.build/proxy-about-runtime-20261009/`；旧运行包：`.build/runtime-package-backups/proxy-about-visual-20261009-153544/QuotaView.app`；修改前源码：`.build/proxy-visual-20261009/SettingsView.swift.before`。未新增/运行测试、UI 自动化或真实代理测试；视觉和动画观感待用户验收。未推送或发布。规则见[设置窗口](docs/design/QUOTAVIEW_UI_RULES.md#设置窗口)。

## 设置页可视化精简与白色导航选中态（2026-10-09，已进入开发包）

- 按用户最新要求，用量显示、Bug 反馈不再挂载顶部可视化或占位内距，标题与实际菜单直接位于导航下方。成本估算/Token 活动开关、QQ 群二维码弹窗和 GitHub Issues 入口保持。
- 网络代理与关于保留壁纸视口、现有内容和排版尺寸，移除摘要内容外层半透明黑色圆角面板；灵动岛完整静态预览保持。
- 已移除用量收起态和反馈顶部摘要的专用视图代码，原始资源继续保留。定向 Swift 5 类型检查与补丁空白检查记录：`.build/settings-visual-simplify-20261009/`；未新增/运行测试或 UI 自动化。
- 用户随后要求每次修改都更新开发版，已完成 14:51 的最小增量编译及替换运行；证据 `.build/settings-visual-runtime-20261009/`。
- 同轮截图要求导航选中项统一白色：七个页面的选中图标/文字均为纯白，未选中保持次要语义色；深色胶囊背景保持白色 13%，浅色用黑色 70% 叠加确保白字可读。页面正文标题图标仍沿用原配色。
- 导航修订再次完成 Debug arm64 增量编译，14:52（上海）替换启动 PID 62470。版本保持 0.7.7 / 显示 Build 2 / 内部 58；234 项输入、13 个静态资产、完整运行包及实际 App/Core 加载路径匹配，正式安装保持不变。
- 最新证据：`.build/settings-nav-white-runtime-20261009/`；旧包备份：`.build/runtime-package-backups/settings-nav-white-20261009-145243/QuotaView.app`。未新增/运行测试、UI 自动化、推送或发布；视觉待用户验收。规则见[设置窗口](docs/design/QUOTAVIEW_UI_RULES.md#设置窗口)。

## DSH 定制客户端兼容（2026-10-09，已进入开发包）

- 按用户要求兼容 Scoder、DeepViewer 等基于 DSH 的客户端，列表与任务仍统一显示 DSH。实际源码确认二者使用独立 `DSH_HOME=userData/harness-home`，原接入只检查默认根目录而漏掉这些配置。
- 增加默认/环境目录、Application Support 下固定层级 DSH profile 的发现，以及非标准路径的添加/移除/重新检查。依据 profile 清单和所有权识别，不按品牌命名；不递归读取会话、凭据或备份。配置目录只用于接入，不迁移客户端数据。
- DSH 事件增加数据目录哈希命名空间，隔离不同客户端的同名会话、父子任务、工具和轮次。私有安装清单记录写入意图与历史配置路径，停用/移除只清理 QuotaView 本渠道标记块，保留其他设置。
- 四个相关 Swift 文件定向类型检查、JS 语法检查与补丁空白检查通过；未新增/运行测试。证据与修改前副本：`.build/dsh-custom-clients-20261009/`。
- 随后按用户“启动”授权完成 Debug arm64 增量编译，14:26（上海）替换启动 PID 53217；版本仍为 0.7.7 / 显示 Build 2 / 内部 58。234 项输入、13 个静态资产、完整包和实际 App/Core 加载路径均匹配，正式安装保持不变。
- 当前 DSH 开关已启用，运行时已为 9 个数据根目录的 13 个 profile 写入本渠道插件及对应目录命名空间；逐文件核对原有其他配置、权限和修改前备份保持完整，实际安装的插件源码与本次源码一致。未主动重启 Scoder/DeepViewer 或创建真实任务；需客户端加载插件后验收真实联动。
- 构建/运行与配置核对证据：`.build/dsh-custom-runtime-20261009/`；旧包备份：`.build/runtime-package-backups/dsh-custom-clients-20261009-142600/QuotaView.app`。未新增/运行测试或 UI 自动化。
- 规格：[Agent 接入](docs/specs/agent-integrations.md#dsh-定制客户端与多目录)。未推送或发布。

## 设置样式、导航修复与 Agent 接入（2026-10-09，已进入开发包）

- 其他设置页采用 Figma UI2 的系统语义背景和胶囊导航；通用页直接显示菜单，用量保留 760 × 120 pt 静态壁纸与完整固定示例，代理/反馈/关于使用 160 pt 静态视口。灵动岛静态预览与三种 56 pt 效果列宽裁切保留。
- 用户随后报告页面停留在“用量显示”：已为装饰壁纸关闭命中，视口设置 contentShape，导航 zIndex 提升。旧进程样本有部分 Metal drawable 等待，但不等于全局死锁；点击问题与视觉仍需用户实际确认。
- 按用户指定 VibeIsland 列表改为 Codex / Claude Code / DSH / Kimi Code 四行 Agent，名称、图标、状态、开关统一；点击名称展开原有必要设置。连接页去掉独立壁纸摘要和无关统计。用户后续要求箭头在最左：现为 12 pt 固定箭头列、22 pt / 5 pt 连续圆角品牌图标、名称；状态列固定为中文 76 pt / English 116 pt。DSH 使用官方 npm 鲸鱼矢量，Kimi 使用官网声明的原始应用图标；Codex 与 Claude 保留原始品牌形状。
- DSH 原创原生 session/event 插件与 Kimi 官方 Hooks 已接入私有本机桥。独立 Provider 身份、生命周期、工具、权限提醒、压缩、完成、失败、中断、标题与模型；DSH 仅显示实际事件 Token。权限确认仍在原客户端。明确提供父子身份时隔离子任务，避免结束事件覆盖主任务。
- DSH / Kimi 首次默认关闭。启用会备份并更新本渠道标记块，重启对应 Agent 后接收新事件；配置完成显示“等待会话”，收到有效事件才显示“已连接”。“已连接”不是在线心跳。没有新增两者的额度、历史成本或完整回答同步；Kimi Stop 可能被其他 Hook 阻止，详见[规格边界](docs/specs/agent-integrations.md)。
- Agent 接入编译及 DSH JS 语法检查通过。图标与对齐修订随后完成 Debug arm64 增量编译，10:35（上海）替换启动 PID 18740。0.7.7 / 显示 Build 2 / 内部 58 不变；234 项构建输入、13 个资产、完整运行包/备份及 App/Core 实际加载路径一致，正式安装 Info.plist / 主可执行文件保持不变。之前 10:24 接入构建已核对原有 DSH/Kimi 配置指纹未变；用户截图已显示 DSH 收到事件，但完整真实会话生命周期仍待验收。
- 当前图标构建证据：`.build/agent-row-icons-runtime-20261009/`；旧包：`.build/runtime-package-backups/agent-row-icons-20261009-103542/QuotaView.app`。图标来源及修改前副本在 `.build/agent-row-icons-20261009/`。接入研究和先前构建证据保留于 `.build/agent-integrations-20261009/`、`.build/agent-integrations-runtime-20261009/`。
- 未新增/运行测试或 UI 自动化；尚未真实启动 DSH/Kimi 任务验证。本次非测试本地检查不代替用户验收；没有推送或发布。连接列表采用真实品牌图标；其他任务入口仍沿用上一轮图标约定，本次只改用户指出的列表。
- 下一步：用户检查设置切换和列表，启用并重启 DSH/Kimi 后检查真实任务状态与权限提醒；有实际问题再定位，不能把编译通过记录为端到端通过。

## 设置预览高度与连接标题图标（2026-10-09，已进入开发包）

- 三个任务特效静态图片视口由 32 pt 加高至 56 pt，保留上下各 8 pt 内距；外框总高从 48 pt 变为 72 pt，继续三列等宽。
- 连接页 Codex / Claude Code 分组标题增加 22 pt、5 pt 连续圆角图标，图文间距 8 pt。复用包内 Codex 应用图标与 Claude 原始矢量标志（奶油色底），保留标题辅助功能语义。
- `SettingsView.swift` 定向 Swift 5 类型检查通过，补丁空白检查通过；证据在 `.build/effect-preview-height-20261009/`。未新增/运行测试，视觉待用户验收。
- 随后按用户“运行”授权完成 Debug arm64 最小增量编译并替换启动。09:25（上海）新进程 PID 76697；保持 0.7.7 / 显示 Build 2 / 内部 58。222 项输入无漂移、9 个静态资产、完整运行包及实际 App/Core 加载路径均核对一致。
- 运行证据：`.build/settings-preview-runtime-20261009/`；旧包备份：`.build/runtime-package-backups/settings-preview-height-icons-20261009-092501/QuotaView.app`。正式安装 Info.plist 与主可执行文件保持原样。未新增/运行测试、推送或发布；视觉待用户验收。

### 效果选项横向溢出修复（同日 09:26）

- 用户截图指出 09:25 加高包的三张预览互相覆盖；原因是只固定图片高度，`scaledToFill` 按原比例撑宽了网格子项。此前类型检查和编译未覆盖视觉布局。
- 用 `GeometryReader` 接收每列的可用宽高，显式约束并裁切图片。网格决定卡片宽度，继续 56 pt 高图片与 8 pt 内距；不新增动画或后台工作。
- Debug arm64 增量构建通过，09:26（上海）替换启动 PID 78011，版本身份不变。222 项输入、9 个资产、完整包、备份及 App/Core 实际加载路径核对一致；正式安装 Info.plist 与主可执行文件原样保留。
- 证据：`.build/effect-viewport-runtime-20261009/`；旧包备份：`.build/runtime-package-backups/effect-viewport-fix-20261009-092630/QuotaView.app`。未新增/运行测试或自动化视觉验收；待用户复验，不将构建成功记作视觉通过。

## 连接页整理（2026-10-09，已进入开发包）

- 按用户澄清，以 Claude 设置为参考整理 Codex：统一无彩色行图标的简洁设置行、状态圆点与“连接详情”入口。连接、目录和任务事件操作直接可见，技术说明/诊断信息默认折叠。
- 移除 Claude 的套餐、额度、Tokens 和成本卡片及此页专用统计计算；继续在已有用量页显示。保留启用、岛上审批、官方用量读取等接入控制。Codex 仍为自动读取加可管理的 Hook，不用假开关表示不存在的能力。
- Claude 错误重试移到连接行；配置完成但未收到事件显示“等待会话”。Codex 授权、启用/停用、故障重新检查与目录失败提示可直接访问；运行时与偏好行为未改。
- Debug arm64 最小增量编译通过，09:17（上海）替换启动 PID 71892；222 项源码/资源输入无漂移，9 个静态资源、完整包与 App/Core 加载路径均匹配。沿用 0.7.7 / 显示 Build 2 / 内部 58。
- 旧包备份：`.build/runtime-package-backups/connections-settings-20261009-091741/QuotaView.app`；证据与修改前文件：`.build/connections-settings-20261009/`。正式安装 Info.plist 与主可执行文件保持原样。
- 本轮未新增/运行测试或 UI 自动化，视觉与交互待用户验收；未推送或发布。相关规则见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md#设置窗口)与[Claude 规格](docs/specs/claude-code-support.md)。

## 隐私模式设置预览修复（2026-10-09，已进入开发包）

- 原因：上一轮将“Demo 信息完整展示”解释为始终显示完整内容，静态 `SettingsIslandPreview` 不再读取隐私偏好；真实岛的 `IslandLiveStore` 隐私处理仍在。
- 恢复隐私开关联动：开启时静态任务名显示“Codex 任务”，进展显示“内容已隐藏”；关闭时恢复完整示例。状态、模型、耗时、Tokens、额度与统计保持，辅助功能同步隐私状态。继续使用静态资源和现有尺寸，不引入真实任务、Metal 或计时器。
- 当前目标依赖下 `SettingsView.swift` Swift 5 定向类型检查通过；补丁空白检查通过。未新增/运行测试；随后按用户“启动替换”授权完成增量构建与开发包替换启动，见下方运行记录。未推送或发布，视觉与交互待用户验收。
- 修改前副本、命令与检查日志：`.build/settings-privacy-preview-20261009/`。下方 2026-10-08“预览不随隐私开关隐藏”描述是修复前阶段记录，以本节为准。

## 用量来源标签与 Claude 图标（2026-10-09，已进入开发包）

- 用量来源标签在名称前增加 14 pt 对应图标，间距 5 pt；选中状态、标签高度与切换逻辑保持。图标对辅助功能隐藏，按钮读出来源名与选中状态。
- Claude 原来使用 SF Symbol `asterisk` 占位，现改为官网 ClaudeWordmark 的原始标志路径及 `#D97757` 色；本地矢量资源经共用图标入口缓存，用量标签、任务卡、子任务和重置卡均复用；重置卡静态着色为既有奶油白，SwiftUI/AppKit 保持一致。Codex 继续使用现有包内图标；资源加载兼容 Xcode 与 SwiftPM。
- Swift 5 定向类型检查、资源目录编译、AppKit 加载及项目/补丁检查通过。未新增/运行测试；随后按用户“启动替换”授权进入开发运行包，见下方运行记录。未推送或发布，视觉待用户验收。
- [图标来源与约束](docs/design/quotaview-provider-icons.md)；修改前副本、官方页面快照、矢量路径来源与检查日志在 `.build/usage-provider-icons-20261009/`。

## 隐私与来源图标运行包更新（2026-10-09）

- 按用户“启动替换”授权完成 Debug arm64 最小增量编译；沿用 0.7.7 / 显示 Build 2 / 内部 58、`com.quotaview.development073`。
- 旧进程 49703 正常退出，新进程 60905 于 08:53（上海）运行。220 项输入构建前后匹配；7 个设置预览资产及 `ClaudeProviderIcon` 已进入 Assets.car；完整包、备份及实际 App/Core 加载路径均匹配。
- 旧包完整备份：`.build/runtime-package-backups/privacy-provider-icons-20261009-085330/QuotaView.app`。正式安装的 Info.plist 和主可执行文件保持不变；没有发布、推送或 appcast 更新。
- 构建与运行证据：`.build/privacy-provider-runtime-20261009/`。未新增/运行测试或自动化视觉验收，实际显示与交互待用户确认。

## 用量标签无框图标与胶囊修订（2026-10-09，已进入开发包）

- 根据运行截图反馈，Codex 用量标签使用既有重置标志的矢量主轮廓，纯白填充、透明底；Claude 继续使用官网陶土橙标志，两个图标均无应用底框。
- 选中背景和点击热区改为 Capsule；高度、字号与内距直接复用顶部用量按钮的 `IslandChromeMetrics`（28 pt / 12 pt Medium / 水平 8 pt）。图标 14 pt、图文和标签间距 6 pt，标签左缘与下方卡片对齐，文字完整显示。
- 当前目标依赖下 `IslandConceptBoard.swift` 定向类型检查、矢量资产编译和 AppKit 加载检查通过；未新增/运行测试或视觉自动化验收。此次修订已按用户“运行”授权完成最小增量开发构建及替换启动，见下方记录；未推送或发布。
- 修改前副本、轮廓来源与检查记录：`.build/usage-provider-capsules-20261009/`；视觉由用户验收。

## 无框图标与胶囊运行包更新（2026-10-09）

- 按用户“运行”授权完成 Debug arm64 最小增量构建并替换启动；保持 0.7.7 / 显示 Build 2 / 内部 58、`com.quotaview.development073`。
- 09:03（上海）新进程 PID 66085；222 项源码/资源输入前后相同，9 个静态资产包含 `CodexProviderMark`、`ClaudeProviderIcon` 和七个设置预览资源。完整运行包、旧包备份及实际 App/Core 加载路径已核对。
- 旧包备份：`.build/runtime-package-backups/usage-provider-capsules-20261009-090356/QuotaView.app`；正式安装的 Info.plist 与主可执行文件保持原样。
- 证据：`.build/provider-capsule-runtime-20261009/`。没有新增/运行测试、UI 自动化验收、推送或发布；视觉待用户验收。

## 开发基线

- 用户在 2026-10-06 否定旧审计开发版，要求从 `v0.7.7-build.1` 继续；2026-10-07 只迁入 Claude 适配与已确认的设置/卡片修改。
- [PR #84](https://github.com/Duoasa/QuotaView/pull/84) 的集成明确撤回旧审计改动；本地 HEAD 已含该集成。不要重新套用 `dc49a3e` 审计快照或恢复其运行包。
- 设置默认 872 × 760 pt，顶部导航与可视化、下方独立滚动选项。所有页面已按新稿统一为语义窗口背景；通用直接显示设置，其他页使用桌面壁纸内的静态示意与现有状态摘要。连接页包含 Codex 与 Claude 各自状态/开关；局部示例与真实账户、任务、审批隔离。选中任务卡只保留进度特效，未选中保留 AI 球。参数见[界面规范](docs/design/QUOTAVIEW_UI_RULES.md)。

## Claude 修订与验证

- 停止后可重新启动监听；配置任务按修订隔离，旧结果不能覆盖新状态；停用清理失败保留错误和重试；取消用量刷新后不接受迟到回写。
- 关闭岛上审批立即撤销应答能力、无决定释放 helper，保留终端只读提醒；迟到请求同样回退，再次开启不重新接管旧请求。
- 19 项 Claude 隔离冒烟、0 失败；使用临时配置和测试 socket。首轮 SIGPIPE 属于测试客户端，补齐断管保护后复验通过；未代答真实审批。
- 按用户“替换”授权完成 Debug arm64 增量编译；201 项生产输入前后相同，加载二进制匹配构建产物。原运行包与历史产物/主要资源一致；历史缺少全量输入清单，不能据此声称原包完全可重现。
- 构建沿用已有非阻断并发兼容警告。未执行完整本地回归或视觉自动化；详细行为与边界见 [Claude 规格](docs/specs/claude-code-support.md)。

## 字体容错修复（2026-10-08，已进入开发包）

- 用户截图中出现方框的额度、Tokens、金额与 Asta Sans 使用位置对应；具体受影响设备的触发原因尚未复现，不能据此断言是同名字体冲突或某个 macOS 版本。
- `AstaSansFont.swift` 改为从应用内字体数据创建并缓存 Core Text 字体，校验 PostScript 名称和数字/字母/百分号/金额符号/占位符字形。SwiftUI 与 AppKit 统一使用这些字体对象，失败时按原字号/字重回退系统字体。
- 注册结果与错误码写入 `com.quotaview.menubar` / `fonts` 日志；注册失败时仍可使用已校验的直接加载字体。移除“尚未成功即标记已注册”的可变状态，加载提前到 AppDelegate 初始化，字体首次访问也可安全触发加载。
- Swift 5 类型检查（字体模块及实际 AppKit 适配函数）通过；未新增/运行字体测试。随后按用户“更新运行包”授权完成增量编译与启动，已进入当前运行包；受影响设备仍待复测。

## 用量 hover 修复与性能检查（2026-10-08，已进入开发包）

- 用户配合移动鼠标后，对运行进程 41350 采样 10 秒。主线程 6528 个样本中，1036 个经过 `IslandUsageBento.chart`：柱子的颜色/高度等重复重建成本模型，执行历史遍历与日期计算；活动网格也随 hover 重建。
- `IslandConceptBoard.swift` 为成本及日/周/累计活动模型增加单代缓存；按实际活动数据、累计 Tokens 或 UTC 日期变化失效。成本柱图闭包复用同一个模型，重复进入同一悬停目标不再重复写入状态。
- 黑线来自本卡片的外层描边盖住内部提示框。将该描边移入背景层，并保留相邻卡片之间的 hover 层级；不改变提示框内容、热区或统计口径。
- 隔离冒烟 39 项、0 失败，覆盖缓存复用、数据/定价/累计值更新、UTC 跨日、缺失与零值及数据源切换。371 天合成历史、80 次 Debug 模型访问基准：中位数 `44.62 → 0.019 ms`，P95 `45.03 → 0.019 ms`。基准不含 SwiftUI 绘制，不能据此宣称实际帧率或整个 hover 延迟。
- 受影响 `IslandConceptBoard.swift` 使用当前目标源文件列表和依赖执行 Swift 5 定向类型检查，通过；相关补丁 `git diff --check` 通过。
- 按用户“更新运行包”授权完成 Debug arm64 增量编译、旧包备份与开发包替换启动。202 项生产输入构建前后相同；完整包与构建产物一致，App/Core 实际加载路径已核对。沿用 0.7.7 / Build 2 / 内部 58，未 Developer ID 签名或发布，正式安装保持原样；后续源码推送见下方集成记录。
- 实际 hover 交互与黑线消除等待用户复测，尚无更新后交互采样。原始采样、基准、构建日志及 `runtime-update-result.json` 保存在 `.build/usage-hover-20261008/`。

## Codex 额度窗口横排（2026-10-08，已进入开发包）

- Codex 实际返回两个主额度窗口时，与 Claude Code 一样横向排列，间距 10 pt；单窗口占满左侧额度行。保留原有窗口排序、数据和空态，右侧账户卡片不再随两张额度卡纵向堆叠而拉长。
- Debug arm64 增量编译通过，并沿用本轮运行授权更新开发包；202 项生产输入未漂移，完整运行包、备份及 App/Core 加载路径已核对。没有新增或重跑测试；布局待用户验收；后续源码推送见下方集成记录。证据：`.build/quota-horizontal-20261008/`。

## 灵动岛设置与完成展示 GitHub 集成（2026-10-08）

- 用户授权当前源码推送并合并 main。[PR #86](https://github.com/Duoasa/QuotaView/pull/86)，源码提交 `d65b3330d877940654f154ee72e7835c1929aba7`；2026-10-08 18:42（上海）合并为 `13a74949760a6360b410064928fb246e577e9365`。
- 28 个文件仅含本轮功能、Figma 资源、既有测试期望更新与相关文档增补；另一批文档重排、归档和未跟踪原型保留本地。未新增或运行本地测试。
- PR CI `37764807284` 与合并提交 main CI `37765299181` 均全部通过（Swift tests 与原生问题关闭契约夹具）；main CI 于 2026-10-08 18:47（上海）结束。
- 提交与当前运行包的 217 项生产输入逐项匹配；版本、开发身份和运行包不变。正式安装、公开 Release 和 appcast 未变。视觉与真实交互仍由用户验收。
- 提交范围、PR/CI 元数据、日志及源码输入核对见 `.build/source-push-island-20261008/`。下方较早“未提交/未推送”属于当时的阶段记录。

## GitHub 源码集成（2026-10-08）

- 用户授权推送源码并合入 main。[PR #85](https://github.com/Duoasa/QuotaView/pull/85)，源码提交 `18b7a17`，CI 跟进 `342d908`；仅按路径/段落提交本轮功能与相关记录，现有文档重排、归档和未跟踪原型保留本地。
- 首轮 CI `37751300309` 出现隔离输入服务等待超时，并在 Claude socket 夹具中因 SIGPIPE 退出。修正 Darwin 接受连接继承非阻塞标志导致首包迟到即关闭；现有测试加入延后发送与断管保护，隔离 Python 冷启动等待 15 秒，应用连接/请求时限及功能断言保持。
- 跟进 PR CI `37752297701` 全部通过；PR #85 已于 2026-10-08 16:57（上海）合并，main 提交 `0216fd4dbaf154849496dd81374a7ef05d53bfb8`。对应 main CI `37753343092` 全部通过（Swift tests 与原生问题关闭契约夹具）。原始日志与提交范围证据见 `.build/source-push-20261008/`。

## main 合并后运行包更新（2026-10-08）

- 按用户“完成后更新运行包”授权，在 PR 与 main CI 通过后完成 Debug arm64 最小增量构建；沿用 0.7.7 / 显示 Build 2 / 内部 58。Claude 接受连接的首包延迟修复已进入当前运行包。
- 202 项生产输入构建前后匹配；旧进程正常退出，新进程 PID 5824 的 App、Debug dylib 和 Core 实际加载路径已核对，运行包完整文件/链接与构建产物相同。旧包完整备份，正式安装 Info.plist 与主可执行文件哈希保持不变。
- 证据：`.build/merged-runtime-20261008/` 下构建命令/日志、输入哈希、替换前状态、实际加载路径和 `runtime-result.json`。没有追加本地测试或自动化视觉验收，用户交互验收仍待完成。

## 完成展示与收起态焦点（2026-10-08，已进入开发包）

- 列表任务全部成功完成时，收起态持续显示真实剩余额度百分比与“全部任务已完成”；未知额度保留“—”。失败、中断、待确认不会被算作成功完成。
- 仍有运行中任务时，新完成提示在收起态保留 3 秒，再优先展示运行中任务；新完成连续到达合并计时，展开时暂停到收起后展示。完成身份包含会话/轮次，新轮次、任务移除或待确认立即撤销旧提示；历史首屏不重播。展开列表手动选择和详情保持独立。
- 收起态和列表完成球共用播放资格；Ripple Glow 完成速度由 0.36 调为 0.12，保持慢速绿色流动。隐藏、离屏、禁播或 Reduce Motion 仍停止，任务状态/完成计数不变。
- Swift 语法检查、实际目标依赖下 `IslandConceptBoard.swift` Swift 5 定向类型检查及受影响补丁 `git diff --check` 通过。未新增/运行测试；随后按用户“更新包”授权完成 Debug arm64 增量构建与替换启动，沿用 0.7.7 / Build 2 / 内部 58。202 项生产输入前后匹配，运行包与构建产物完整一致，旧包备份及实际 App/Core 加载路径已核对；正式安装保持原样。未提交/推送；真实交互待用户验收。命令、输入哈希、构建日志、加载路径及 `runtime-result.json` 见 `.build/compact-completion-20261008/`。

## 灵动岛设置页 Figma 接入（2026-10-08，已进入开发包）

- Codex 重启后，连接器成功读取 Figma `165:17` 的设计上下文、截图和原始资源；未再使用此前失败请求的推测数据。
- 本页顶部改为窗口语义背景，桌面壁纸预览最大 760 × 212 pt，内置 510 × 160 pt 静态刘海示意；任务卡 454 × 60 pt，保留左侧标题/状态、右侧模型/耗时和 Tokens 的位置关系，文字图标不缩放。图内工具不接真实操作。
- 四种特效切换本地原始静态图片；隐私开关切换示例内容。移除该页的生产任务卡及 Metal 预览宿主，不启动预览计时器或真实任务观察。选项顺序改为“显示 → 任务特效 → 自动展开”，保留原生开关与时长菜单；其他页面未改稿。资源与图层映射见[接入记录](docs/design/quotaview-settings-island-figma-20261008.md)。
- 按用户查看效果的授权完成 Debug arm64 最小增量编译与开发包替换启动；沿用 0.7.7 / 显示 Build 2 / 内部 58。219 项输入前后匹配，8 个静态资产已进入 Assets.car，完整运行包与构建产物一致，旧包完整备份；正式安装身份与主可执行文件哈希未变。编译仅保留已有非阻断并发兼容/AppIntents 警告。
- 未新增/运行测试或 UI 自动化验收，视觉与真实交互待用户确认；未提交、推送、发布或修改 appcast。证据在 `.build/island-settings-figma-20261008/`：构建命令/日志、输入哈希、编译资产元数据、运行包替换记录及实际加载路径。

## 移除晶钻前沿（2026-10-08，已进入开发包）

- 按用户修订移除晶钻前沿枚举、着色器分支及静态资源，设置选项变为状态烟雾、量子噪点、液态涌浪三列均分；其他效果的原始标识和 shader 索引 0、2、3 保持不变。
- 旧 `diamondFront` 偏好经现有加载回退和保存流程迁移为 `dropField`；已选用其他效果的偏好保持。同步修改已有测试中的失效枚举引用和预期列表，未新增/运行测试。
- Swift 语法检查与 Debug arm64 增量编译通过；217 项输入前后匹配，运行包与产物完整一致，已核对 7 个资源及晶钻资源缺席。开发包已替换启动，版本身份仍为 0.7.7 / 显示 Build 2 / 内部 58；正式安装未改，视觉待用户验收。证据：`.build/island-three-effects-20261008/`。

## 可视化比例与完整示例（2026-10-08，已进入开发包）

- 重新读取 Figma `165:17`，并单独复取 `172:331` 最新岛体轮廓；直接替换原始 SVG，包含修改后的底部圆角。壁纸和任务卡背景与上轮原图哈希一致，保持复用。
- 岛体轮廓改为 510 × 150 pt、内容高 150.4 pt；任务卡加宽到 462 × 60 pt，内部字号和排列不变。工具栏字号/图标 9.6 pt，占位 22.4 pt，用量环 11.2 pt；顶部/底部工具栏水平内距 20、任务列表水平内距 24，底栏总高 30.4 pt。
- 按用户补充要求，预览始终使用完整固定示例，所有文本字段均有内容，中英文示例以自身尺寸完整显示，不随隐私开关留空或显示占位。隐私设置仍控制真实岛；示例没有真实任务/账户来源或操作能力，三种特效仍为静态切换。
- Debug arm64 最小增量编译、217 项输入一致性、7 个资源及完整包/加载路径核对通过，开发包已替换启动；版本身份仍为 0.7.7 / 显示 Build 2 / 内部 58。正式安装保持，未新增/运行测试或自动化视觉验收，效果待用户确认。证据：`.build/island-preview-proportions-20261008/`；构建/安全替换辅助脚本位于忽略目录 `.build/update-settings-runtime.py`。

## 未完成项

1. 用户验收真实 Claude 会话、岛上审批、状态栏刷新，以及与其他 PermissionRequest Hook 并存的行为。
2. 用户验收当前设置布局、Codex/Claude 混合任务、长内容和真实请求交互；记录范围见 [Design QA](design-qa.md)。
3. Codex 原生异步问题组的精确关闭仍未实现/验证；ACK、问题结算、本地提醒退场均不能证明原生框关闭。见[同步规格](docs/specs/codex-desktop-confirmation-sync.md)。
4. 多屏、Intel、长时间运行及辅助功能组合继续保留实机验收边界。历史测试总数不作为当前版本完整验收。

## 编译、回退与证据

- 保留增量编译目录 `.build/Development075Build3`；当前 Products 为其 `Build/Products/DebugBuild2SettingsProportion`。**禁止将构建输出直接指向独立运行包目录**，Xcode 清理可能移除正在使用的资源。
- 最近替换前完整回退包：`.build/runtime-package-backups/settings-proportions-20261008-182408/QuotaView.app`。此前 `three-effects-20261008-181437/QuotaView.app`、`island-settings-20261008-180725/QuotaView.app`、`compact-completion-20261008-173051/QuotaView.app`、`main-merge-20261008-170429/QuotaView.app`、 `quota-horizontal-20261008-163147/QuotaView.app`、 `usage-hover-20261008-162700/QuotaView.app` 与 `claude-followup-20261008-095749/QuotaView.app`（同一备份根目录下）继续保留。其他旧重复包/缓存的清理清单见[维护记录](docs/archive/maintenance-20261008/README.md)。
- Claude 证据：`.build/claude-followup-20261008/` 内 `baseline.json`、`claude-smoke-final.log`、`replacement-preflight.json`、`replacement-runtime.json`、`development-build.log`、`replacement-loaded-paths.log`。
- 设置基线证据：`.build/settings-proportion-20261007/`；迁入差异：`.build/claude-integration-20261007/`；审计源码恢复记录：`.build/source-rollback-20261006-173911/`。这些源码副本、差异和日志保留。
- 当前 SwiftPM 增量产物、依赖缓存、公开发行 ZIP、冻结开发台资产保留。历史交付目录中的已清理二进制路径只代表当时位置，不再保证可恢复。

## 后续工作边界

按 [AGENTS.md](AGENTS.md) 与[规格索引](docs/specs/README.md)读取受影响范围。默认保持本地源码迭代；推送、合并、正式包装或新版本发布需对应请求。真实重置按 0.8.5 手动重置契约执行；开发验证不消耗用户卡。
`Prototypes/IslandTextConsole/` 是永久工具；`Prototypes/MultitaskIslandConsole/` 的固定快照保持，历史“下一步”不触发重新构建或迁移。
