# QuotaView Handoff

公开稳定版与回滚资产：[VERSION_HISTORY.md#当前最新版本](VERSION_HISTORY.md#当前最新版本)。

## 0.7.5 Build3 正式发行 · 2026-10-04 进行中

用户已审核发布文案，并明确授权使用两张产品图、更新原有中英文 README、推送 GitHub、合并 main、发布最新版及 appcast。精确身份为 **0.7.5 / 显示 Build3 / 内部52**，tag `v0.7.5-build.3`，ZIP `QuotaView-v0.7.5-build.3.zip`。本节取代下方历史交付中的等待发布授权状态；正式签名、公证、CI、公开回下载和签名 Feed 部署正在执行，未完成前不记为已发布。

当前公开稳定与回滚基线仍是 `v0.5.1-build.13` / `ec99dc184d84fbb011f3e337c95be1f3d82c775c`，完整资产证据见版本历史。生产源码保持已验收的 Build3，README 使用原始产品图；不含记忆 DEBUG 注入。原生异步提问组关闭能力保持既有边界，视觉与真实交互以用户结论为准。

## 0.7.5 Build3 长会话元数据恢复 · 2026-10-04 当前迭代

用户反馈当前会话只显示目录名 `widget`、模型未知与 Token 缺失，其他会话正常。只读核对确认当前 rollout 超过 280 MiB，默认末尾 16 MiB 内有真实 `turn_context` 与 Token 记录，但没有本轮 `task_started`；原恢复 decoder 因没有活跃轮次而丢弃其后的模型/用量/公开内容。原目录名标题缓存还会阻断或覆盖迟到真实标题，空元数据可能覆盖有效字段。

**0.7.5 / 显示Build3 / 内部52 已构建并替换既有开发运行包，PID16910**。独立 name/title/model/effort/线程累计元数据只补已有卡片；数据库累计不进入本轮消耗账本。尾部恢复仅匹配 Registry 当前已准入的真实轮次，补模型、精确本轮/累计 Token、公开内容及只读 Desktop follow；不生成 lifecycle，不重放历史问题或扩大 owner 应答权限。EOF 迟到准入与旧 decoder 跨轮次可固定预算重扫；最新公开消息与工具共用200条/2MiB预算。所有空值保留有效字段，目录名低级占位不能覆盖明确 name，首次 late Hook 观测不再挡住同轮更早累计展示，计数保持单调。

**101项必要冒烟零失败**，fresh Debug arm64与正式身份Universal Release无签名构建通过，187项生产输入一致，App/Widget均0.7.5/3/52。实际 Core 产物只读读取当前真实长会话，恢复标题 `QuotaView 0.7.3 继续开发`、gpt-6.1-sol/ultra、累计/本轮Token及133条公开记录，输出0条合成活动；测试覆盖旧轮次、旧代次、terminal、后台记忆/内部任务、时序、预算、空值和无请求副作用。首轮98项出现1项等待不足（Token/模型先到，测试提前停止公开回放）的失败，已改为等真实公开消息；同时新增工具洪流保留消息、换轮取消保护及late Hook显示反例，最终101项通过，不隐藏首轮证据。

已运行包路径仍为 `dist/development-0.7.3/QuotaView 0.7.3 Development.app`，实际可见名0.7.5。deep strict ad-hoc签名及主程序/Debug dylib/Core实际加载通过，真实活动socket归新PID所有，当前会话同轮Hook与Local事件已被新进程准入。旧PID51374退出，完整旧包备份 `.build/runtime-package-backups/20261003T222531Z/`；稳定PID13504保持，用户数据与固定开发身份不变。设置反馈与发行准备资源保留，QQ原图哈希及28款头像/NOTICE、图标再次核对通过。

证据 `.build/075-long-session-live-evidence.json`、`.build/075-build3-recovery-smoke-final.log`、`.build/075-build3-development-build.log`、`.build/075-build3-distribution-build.log`、`.build/075-build3-live-recovery-result.json`、`.build/075-build3-artifact-verification.json`、`.build/075-build3-delivery.json`、`.build/075-build3-live-channel-verification.json`；首轮失败日志 `.build/075-build3-recovery-smoke.log` 保留。独立只读审查未发现明确阻断。发行预检身份改为唯一 `v0.7.5-build.3` / `QuotaView-v0.7.5-build.3.zip`，实际无签名正式候选再次被appcast门禁拒绝、未读取私钥或生成Feed。

本轮设置/发行准备与长会话修复源码均未提交；Release/公开appcast继续等待用户体验后决定，视觉与真实交互待用户验收。原生异步提问组关闭边界仍未完成。当前规格见[信息契约](docs/specs/codex-island-information-contract.md)、[反馈规格](docs/design/quotaview-feedback-settings-0.7.5.md)与[更新规格](docs/design/quotaview-app-updates-0.3.5.md)。

## 0.7.5 Build2 发行准备与设置反馈 · 2026-10-04 上轮交付

用户要求为0.7.5接入发行前appcast准备，增加独立Bug反馈入口（QQ群原图二维码/GitHub Issues），退出按钮加框并删除各页大标题副标题。**先构建运行供用户验收，Release和公开appcast等待用户后续决定**；没有正式发布授权。按同版本新迭代规范使用 **0.7.5 / 显示Build2 / 内部51**，预期唯一tag为 `v0.7.5-build.2`、ZIP为 `QuotaView-v0.7.5-build.2.zip`；当前没有创建tag/Release或发布Feed。

默认开发身份 `com.quotaview.development073`、AppGroup、数据和活动socket保持。显式 `Configs/Distribution.xcconfig` / `scripts/build-app.sh` 提供正式 `com.quotaview.menubar`、Widget及正式AppGroup入口；包内版本/资源/Feed/公钥与正式打包约束已核对。应用恢复 `updateController.start()`，Debug/开发/无正式签名环境继续由更新控制器拒绝；开发首启初始化只作用于开发身份。appcast生成在读取签名钥匙前核对真实ZIP身份/版本/Feed/公钥及Developer ID/Staple，仅当前ZIP进入生成输入，历史Feed资产URL保持。

[反馈规格](docs/design/quotaview-feedback-settings-0.7.5.md)和[更新规格](docs/design/quotaview-app-updates-0.3.5.md)记录当前行为。**4项相关冒烟零失败**、fresh Debug arm64与正式身份Universal Release无签名构建通过，187项生产输入一致，App/Widget均0.7.5/2/51；原图二维码逐字节保留，28款子agent头像/NOTICE及图标资源齐全。开发包deep strict ad-hoc签名及主程序/Debug dylib/Core实际加载核对通过；已替换既有开发运行包并启动PID **51374**，旧PID18877退出，备份 `.build/runtime-package-backups/20261003T214657Z/`。当前持有真实活动socket，无记忆DEBUG参数；稳定PID13504保持。

证据 `.build/075-release-settings-smoke.log`、`.build/075-build2-development-build.log`、`.build/075-build2-distribution-build.log`、`.build/075-build2-artifact-verification.json`、`.build/075-build2-delivery.json`、`.build/075-build2-live-channel-verification.json`。发行预检记录 `.build/075-appcast-preparation/readiness.json`；现有线上Feed已验签，封存Stable Build13 ZIP回下载哈希、正式签名/Staple/Gatekeeper核对通过。本地保存已验签历史Feed到 `.build/075-appcast-preparation/updates/appcast.xml`，发行时以最终签名公证ZIP为输入生成，不发布当前无签名候选。本轮设置/发行准备源码未提交，视觉、二维码扫描和交互待用户验收。原生异步提问组关闭边界保持未完成。

上一轮源代码[PR #73](https://github.com/Duoasa/QuotaView/pull/73)已合并main。其main CI两处连接测试因异步轮询尚处checking而过早断言；[PR #74](https://github.com/Duoasa/QuotaView/pull/74)仅增加有界最终状态等待，PR CI 646项/6跳过/0失败并已合并。main提交 `8bc618c718586ae4fa95f12697c6a076cab7c29e` 的 [CI](https://github.com/Duoasa/QuotaView/actions/runs/37156130589)已通过；证据 `.build/075-ci-timing-integration.json`。本轮未提交候选不包含在该PR CI中。

## 0.7.5 Build1真实通道与main集成 · 2026-10-04 上轮交付

用户已授权停止记忆DEBUG、恢复真实通道，将开发版本设为 **0.7.5 / 显示Build1 / 内部50**，推送GitHub并合并main。隔离演示PID1893已停止，原真实包恢复PID3048；模拟源码副本、演示包和Derived Data已清理，生产Sources不含DEBUG注入。`com.quotaview.development073`、AppGroup及既有开发包路径继续作为固定开发身份，保护用户数据与开发socket/队列边界，073后缀不代表产品版本；界面与包内实际版本是0.7.5。公开Release/appcast仍无本版本准入，稳定安装和发布指针保持。

本次整合精确记忆来源/当前轮次身份、有界只读执行元数据和早晚乱序撤销、底栏真实AI球，原生子agent父关系/头像/堆叠横条和公开进展，滚动收起同步恢复，批准语义/长内容预览，量子时钟，重置整区热区/排版，以及18pt共用小球和统一卡片组描边/hover。历史 `HANDOFF-NEXT-SESSION-2026-09-27.md` 与 `Prototypes/MultitaskIslandConsole/` 保留本地，不进入提交。

**177项相关本地冒烟零失败**，覆盖记忆/来源/代次/预算、子任务准入/逐出/头像/单向滚动、Store分流、批准预览和文案、量子时钟、滚动恢复及真实请求投影。fresh Debug arm64与Universal Release均通过；App/Widget均为0.7.5/显示Build1/内部50，Release App/Widget/Core含arm64+x86_64，28款头像及出处NOTICE齐全。185项冻结生产输入、deep strict ad-hoc签名和实际主程序/Debug dylib/Core加载核对通过。开发运行包已替换并启动PID **18877**，旧PID3048退出；完整旧包备份 `.build/runtime-package-backups/20261003T212127Z/`。当前进程无演示参数且持有真实活动socket，临时演示已全部恢复/清理；稳定PID13504保持。运行路径仍沿用 `dist/development-0.7.3/QuotaView 0.7.3 Development.app`，实际包显示名/版本为0.7.5。

证据 `.build/075-related-smoke.log`、`.build/075-development-build.log`、`.build/075-universal-release-build.log`、`.build/075-artifact-verification.json`、`.build/075-delivery.json`、`.build/075-live-channel-verification.json`。源码提交 `0329da18fb37e13c3312a0bffd6182fbb2043f6f` 已推送至 [PR #73](https://github.com/Duoasa/QuotaView/pull/73)，指向main；用户授权完整CI通过后合并。本地检查与GitHub完整CI分开记录，PR/main检查及最终集成以该PR与运行manifest为准，不从本地构建推断。视觉与真实交互由用户验收。

**原生异步提问组关闭仍未完成。** 本次不扩大此能力，现有边界见[关闭合同](docs/design/codex-native-question-closure-contract-2026-10-03.md)。

## 白色18pt记忆演示与统一卡片描边 · 2026-10-04 历史演示已停止

原生视图实测展开底栏播放中的球为18×18pt，收起宿主暂停的球同为18×18pt；记录保存在 `native-visibility-check.json` 的 `currentExpandedState` 与明确尺寸字段。

演示已停止，原开发包已恢复并启动 PID **3048**；原二进制与 184 项生产输入核对一致，临时构建副本已清理。 最新生产包包含下文18pt小球、卡片组描边以及重置热区和排版修订，生产PID99320暂时停止，原包完整保存在 `.build/073-memory-footer-demo-white-small-orb/original/`；当前演示PID **1893**。仅忽略目录构建副本2个文件追加DEBUG展示覆盖：白色固定 `DEBUG-记忆整理`、18pt原AI球和24pt切换/停止图标。真实活动持续工作，模拟不进入Store/Hook/会话统计/Codex，不改变重置的本地演示边界。

fresh Debug构建、deep strict ad-hoc签名、184项生产输入和实际主程序/Debug dylib/Core路径核对通过。启动时原生记录确认展开显示；当前panel visible/onActiveSpace/unoccluded均true、playback=true且精确标签存在，compact=False，保留后续用户收起操作，不强制重开。以上不代替视觉/点击验收。证据 `.build/073-memory-footer-demo-white-small-orb/build.log`、`native-visibility-check.json`、`demo-record.json`。监督exec session **63211**，停止/退出自动恢复本轮生产包、核对指纹、重新启动并清理临时源码/构建；后续改源码前先创建 `.build/073-memory-footer-demo-white-small-orb/stop-requested` 并等待恢复。稳定PID13504保持。

## 18pt小球与卡片组统一描边 · 2026-10-04 当前交付

用户核实DEBUG记忆球尺寸并要求主卡/子agent描边与hover一致。底栏此前22pt，compact18pt（30pt仅排布槽位），同渲染器但直径大22.2%。现在两处复用 `IslandSmallActivityOrb` 的18pt球，任务卡28pt保持。主卡非选中描边此前白0.055、背板固定0.16且无hover；现共用 `IslandTaskCardAppearance`，普通白0.16、hover/选中0.22，完成态保原绿色，普通背景白0.045/hover0.07。hover由整个堆叠组持有，进入主卡或子条同步高亮，审批头卡也共用。前卡不透明底和底圆角、伸出层次、行高、Metal/完成光晕、独立归档及原滚动条件保持。

**64项相关冒烟零失败**（35Island073、11子agent横条、18滚动），fresh Debug arm64构建、184项冻结输入、28款头像、deep strict ad-hoc签名和实际主程序/Debug dylib/Core加载核对通过。既有开发包已替换，生产PID **99320**，旧PID89838退出；备份 `.build/runtime-package-backups/20261003T210801Z/original/QuotaView 0.7.3 Development.app`。身份保持0.7.3/显示Build1/内部49/com.quotaview.development073；证据 `.build/073-small-orb-card-border-final-smoke.log`、`.build/073-small-orb-card-border-build.log`、`.build/073-small-orb-card-border-delivery.json`。同次包含下文重置热区和排版。无UI自动化，视觉与真实交互待用户验收；稳定PID13504及用户数据保持，无提交推送或发布。

## 白色记忆演示与重置热区排版 · 2026-10-04 历史演示已停止

演示已停止，原开发包已恢复并启动 PID **89838**；原二进制与 184 项生产输入核对一致，临时构建副本已清理。 最新生产包包含下文整区热区和重置页排版修订，生产PID82834暂时停止，原包完整保存在 `.build/073-memory-footer-demo-white-reset/original/`；当前演示PID **84942**。仅忽略目录构建副本2个文件追加DEBUG展示覆盖：白色固定 `DEBUG-记忆整理`、22pt原AI球和24pt切换/停止图标。真实活动持续工作，模拟不进入Store/Hook/会话统计/Codex，不改变重置的本地演示边界。

fresh Debug构建、deep strict ad-hoc签名、184项生产输入和实际主程序/Debug dylib/Core路径核对通过。启动时原生记录确认展开显示；当前panel visible/onActiveSpace/unoccluded均true、playback=true且精确标签存在，compact=False，保留后续用户收起操作，不强制重开。以上不代替视觉/点击验收。证据 `.build/073-memory-footer-demo-white-reset/build.log`、`native-visibility-check.json`、`demo-record.json`。监督exec session **81657**，停止/退出自动恢复本轮生产包、核对指纹、重新启动并清理临时源码/构建；后续改源码前先创建 `.build/073-memory-footer-demo-white-reset/stop-requested` 并等待恢复。稳定PID13504保持。

## 重置入口整区与页面排版 · 2026-10-04 当前交付

账户卡片分割线下方整区现在由同一个按钮 label 承载，包含左右14pt、上10pt和下14pt留白；surface不再在按钮外保留不可点击内边距。上半区吸收余高，不与入口重叠。原2秒卡面高光、底部最亮并在中部消失的hover渐变、无手形指针/新增描边保持；卡片过渡源锚点仍是票券自身边界。

重置页统一Asta Sans：标题及次数15pt Semibold，额度标签11pt Regular、数值11pt Medium，须知/空态/未知标题11pt Semibold，正文11pt Regular和3pt行距，按钮13pt Semibold，演示/待刷新说明10.5pt Regular。共享底栏保持12pt Medium，动态自然高度与中英文长文、0次、未知和待刷新分支继续适配；真实重置仍只演示。

**35项Island073冒烟零失败**，fresh Debug arm64构建、184项生产输入、28款头像、deep strict ad-hoc签名与实际主程序/Debug dylib/Core加载核对通过。既有开发包已替换，生产PID **82834**，旧PID77983退出；备份 `.build/runtime-package-backups/20261003T205614Z/original/QuotaView 0.7.3 Development.app`。身份仍为0.7.3/显示Build1/内部49/com.quotaview.development073；证据 `.build/073-reset-entry-typography-final-smoke.log`、`.build/073-reset-entry-typography-build.log`、`.build/073-reset-entry-typography-delivery.json`。本轮无UI自动化；视觉和实际交互由用户验收。稳定PID13504及用户数据保持，无提交推送或发布。

## 白色记忆演示恢复 · 2026-10-04 历史演示已停止

演示已停止，原开发包已恢复并启动 PID **77983**；原二进制与 184 项生产输入核对一致，临时构建副本已清理。 新版对齐/伸出/白色数量已进入真实生产包；当前临时PID **76166**，生产PID73881已临时停止，完整原包保存在 `.build/073-memory-footer-demo-white-alignment/original/`。仅忽略目录构建副本2个文件有DEBUG展示覆盖，继续白色 `DEBUG-记忆整理`、22pt AI球及24pt切换/停止图标按钮；真实任务继续更新，模拟不入Store/Hook/会话统计/Codex。

演示fresh Debug构建和deep strict签名通过；原生检查panel visible/onActiveSpace/unoccluded均true、compact=false、playback=true，准确标签存在；实际加载主程序/Debug dylib/Core、演示包指纹和184项生产输入核对一致。证据 `.build/073-memory-footer-demo-white-alignment/build.log`、`native-visibility-check.json`、`demo-record.json`。监督exec session **84625**，停止/退出自动恢复本轮真实生产包、验指纹、重新启动并清理演示源码/构建。后续修改源码前先创建 `.build/073-memory-footer-demo-white-alignment/stop-requested` 并等待恢复。稳定PID13504保持；视觉待用户验收。

## 子 agent 对齐、伸出层次与白色数量 · 2026-10-04 当前交付

根据用户 04:30–04:35 截图修正横条：头像占位改为11pt正文同字体，横向固定14pt；子 agent之间固定24pt，不再依靠三个约9.475pt的空格。rich lane 使用独立CoreText line显式基线，让11pt capHeight中线和14pt图标中心一致，并按实际CTRun保留静止省略号与同步图标裁剪。动画仍在原textTrack中单向运动，同一成员的文字/时长更新保留时钟；普通与闪烁文字保留CATextLayer。数量白色，名称和括号灰色，固定组标签不进入滚动。

已确认首张普通卡异常来自半透明主卡让上移10pt短底卡的顶圆角/描边透出；Quantum实心底所以同截图第二卡正常。改为全高下层backing在主卡后延伸到底，card+28pt横条零间距排布，主卡原背景后加实心圆角黑底遮住后层；主卡自身底部圆角线保留，不新增顶部胶囊线，不clip整卡以免裁完成光晕。主卡Metal范围、总高度、滚动锚点、卡片选择与独立归档按钮范围保持。

**74项相关冒烟零失败**（11横条、10子任务投影、18滚动、35Island073），fresh Debug arm64构建、184项生产输入、28款头像资源、deep strict ad-hoc签名及实际加载主程序/Debug dylib/Core核对通过。既有开发包已替换，生产PID **73881**，旧PID61633退出；备份 `.build/runtime-package-backups/20261003T204312Z/`。身份保持0.7.3/显示Build1/内部49/com.quotaview.development073；证据 `.build/073-agent-strip-alignment-final-smoke.log`、`.build/073-agent-strip-alignment-build.log`、`.build/073-agent-strip-alignment-delivery.json`。没有UI自动化，视觉/实际交互由用户验收。稳定PID13504保持；无提交推送或发布。

## 白色底栏记忆球演示 · 2026-10-04 历史演示已停止

演示已停止，原开发包已恢复并启动 PID **61633**；原二进制与 184 项生产输入核对一致，临时构建副本已清理。 当前临时 PID **55939**；真实生产包已更新为堆叠子 agent 横条、Codex 原生头像/单向滚动、末尾 Codex/hover 归档共用槽位和量子时钟修复，生产包 PID 53846 已临时停止并完整保存在 `.build/073-memory-footer-demo-white/original/`。

仅忽略目录构建副本追加 DEBUG 底栏演示：白色固定文案 `DEBUG-记忆整理`、22 pt 原 AI 球和两个不压缩的 24 pt 图标按钮；循环箭头切换状态，关闭圆圈停止，均带中文 help/辅助功能标签。模拟不进入 Store、Hook、会话统计或 Codex；真实任务继续更新。持续 thinking，无自动结束；可切换 completed/error/unavailable。停止/退出由监督 exec session 73003 恢复原生产包、核对二进制与184项生产输入、重新启动并清理副本。后续改源码前先创建 `.build/073-memory-footer-demo-white/stop-requested` 并等待恢复结束，避免覆盖保留包。

fresh Debug 构建和 deep strict ad-hoc 签名通过；原生状态确认在 DELL U2725QE 主屏顶部展开，panel visible/onActiveSpace/unoccluded 均 true，compact=false、playback=true，白色标签对应的精确文案存在；真实加载主程序/Debug dylib/Core 与演示包指纹、184项生产源码输入一致。证据 `.build/073-memory-footer-demo-white/build.log`、`native-visibility-check.json`、`demo-record.json`。稳定进程 PID 13504 保持。这些原生检查不代替用户视觉或点击验收。

## 子 agent 堆叠横条、原生头像与量子动画 · 2026-10-04 当前交付

按用户 04:04 参考，主卡后放独立下层卡片，10 pt 重叠、28 pt 可见横条；主卡内容与 Metal 画布不再含子任务。左侧固定 Codex 图标/子 agent 数量，右侧各 agent 名称、模型、真实状态及耗时单向循环滚动，成员稳定时文字宽度变化保留滚动时钟，隐藏与减少动态效果停止。列表/详情/审批共用同一完整行高；审批只露出底卡时仍维持可见播放。隐私模式不带子任务信息。

原生头像来自本机 Codex 的 28 款深色资源及 UTF-16 31 倍模 2147483647、再模 28 的线程 ID 规则；SPM 与 Xcode 包含相同 64 px PNG，14 pt 显示。固定模型/耗时之后末尾仅留一个槽位，平时显示 Codex，整卡 hover 时变归档，操作仍是独立按钮。出处与资源清单保存在 `.build/073-agent-avatar-evidence/`。

量子动画确认修复普通状态更新反复重置 lastFrameAt 及重复布局写入相同尺寸的缺陷，只在真实播放边界重置时钟；60 FPS/原 shader 保持。离屏原 shader GPU 基准：60 pt 主卡 p95 0.108 ms，旧 228 pt 大画布 0.236 ms，跨状态最坏 0.353 ms；不能据此说 GPU 超预算，也不替代用户实际帧率验收。运行采样中的 Local 发现扫描负载未证实为卡顿原因，未在本轮改变。

**111 项相关冒烟零失败**，可见范围接线补齐后 **63 项聚焦复验零失败**；fresh Debug arm64 构建、184 项冻结生产输入、28 款资源、deep strict ad-hoc 签名和实际加载主程序/Debug dylib/Core 核对通过。原开发包 PID 18582 已退出，新生产包 PID **53846**，原包备份 `.build/runtime-package-backups/20261003T201904Z/`。身份保持 **0.7.3 / 显示 Build 1 / 内部 49 / com.quotaview.development073**。证据 `.build/073-agent-strip-quantum-final-smoke.log`、`.build/073-agent-strip-visibility-smoke.log`、`.build/073-agent-strip-quantum-build.log`、`.build/073-agent-strip-quantum-delivery.json`。无 UI 自动化；视觉与真实交互由用户验收。本轮尚未提交推送，稳定进程 PID 13504 及用户数据保持。

## 底栏记忆球持续演示 · 2026-10-04 历史演示已停止

用户未看到前一次限时演示，检查时原开发进程 PID 7383 已不在运行，不能只归因于演示时长。当前改用隔离构建副本的持续 DEBUG 展示覆盖，仅底栏增加 22 pt 原 AI 球、黄色 DEBUG · 记忆整理演示文案、切换及停止按钮。真实 Store、Hook、会话计数与请求持续工作；模拟不写入这些通路。当前临时 PID **13810**，版本身份和原包位置保持，原包保存在 `.build/073-memory-footer-demo-held/original/`。

演示已停止，原开发包已恢复并启动 PID **18582**；原二进制与 156 项生产输入核对一致，临时构建副本已清理。 无短时自动结束；停止或异常退出由监督进程恢复原包、验证指纹并清理临时源码/构建产物。原生检查确认在 DELL U2725QE 主屏顶部居中展开：panel visible/onActiveSpace/unoccluded 均 true，compact=false，playback=true，底栏演示标签存在；实际加载主程序、Debug dylib、Core 来自临时包。156 项生产输入保持一致，稳定进程 PID 13504 保持。证据 `.build/073-memory-footer-demo-held/native-visibility-check.json` 及 `demo-record.json`；这些检查不代替用户视觉验收。

## 底栏记忆球现场演示 · 2026-10-04

用户明确要求直接在当前灵动岛注入模拟数据。仅在忽略目录内的构建副本添加 DEBUG 展示覆盖，复用生产底栏 22 pt AI 球；带黄色 DEBUG 状态及停止按钮，整理中/完成/失败/状态待更新各 20 秒。真实任务持续更新，模拟不进入 Store、Hook、会话统计或 Codex，应答路径未改。

80 秒流程及结束恢复已完成，四状态和恢复检查点均到达。临时演示进程 PID 7119 已退出；原开发包已恢复并启动 PID **7383**，原二进制指纹、实际加载主程序/Debug dylib/Core 和全部 **156 项生产输入**核对一致。临时源码副本、演示包与 Derived Data 已清除，仅保留 `.build/073-memory-footer-demo/demo-record.json` 和日志证据。生产源码没有模拟入口，稳定进程 PID 13504 保持；视觉效果由用户验收。

## Vibe 通信梳理、记忆执行身份与父子卡片 · 2026-10-04 当前增量

用户要求整体研究 Vibe Island 与 Codex 的通信，彻查记忆普通卡，并补齐父卡片中的真实子 agent 和公开进展。已结合 Vibe 官方更新/隐私材料、本机主程序与 helper 的只读静态消息证据、当前 Codex 原生 schema 和生产源码，形成[信息通信契约](docs/specs/codex-island-information-contract.md)。静态字符串不能证明 Vibe 的完整运行分支；其中 cwd/prompt 前缀规则也不替代 QuotaView 的精确身份。Desktop owner IPC 的请求/应答、独立 App Server 用量与观察、Hook 生命周期、Local 公开内容及执行元数据各自保留边界。

本次 memories 实例在旧已运行 Core 中也能严格解析，全部旧交付输入一致，排除旧包；该次 start 正文 54385 bytes。历史诊断不足以确定单一触发原因。已确认并修正的结构性缺口包括早到身份被丢弃而 Local 只发差量、全局日志记录窗口/失败全空、持久来源和轮次用途混用、旧轮次读取节流，以及重置前端晚于新目录观察启动。现在目录/generation 共用有界原生读取服务，按已观察执行优先和历史游标推进；覆盖集合控制撤销，同 session/turn/generation 的 pending 证据在真实事件准入时消费。真实只读探针连续三次匹配目标轮次，22/34/36 ms；部分覆盖不清除未读线程证据。记忆保留底栏 AI 球，不按标题过滤，也不获得用户应答能力。

`thread_spawn` 子 agent 与其它内部任务分开。只由一致的原生父线程关系归到对应主卡片，展示自身名称、状态、模型及耗时，不增加用户会话数。关系不能伪造正在执行；真实生命周期、迟到关系、来源失效和轮次终态分别处理。主卡片保留最近公开进展，工具结束不再清空；运行子任务摘要可填入状态行，私有消息与 reasoning 不进入展示。分组高度与原滚动几何使用同一度量，并修正静态高度缓存未包含动态子任务的问题。子 agent 缓存逐出时同步撤回执行展示，持久父子身份有界保留，仅真实重新准入恢复。

最终 **239 项相关冒烟零失败**，覆盖来源、读取预算/覆盖、身份早到、旧轮次/旧代次、子任务私密边界、动态几何，以及 128 执行/1024 来源逐出和 Shared 稀疏恢复；既有展示基准 P95 **4.64 ms**，只代表状态投影。fresh Debug arm64 构建、冻结的 **156 项生产输入**与 deep strict ad-hoc 签名通过。既有开发运行包已替换并启动（PID **91302**，旧 PID **17729** 已退出）；实际加载主程序、Debug dylib、Core 的路径、arm64 架构和包指纹核对通过。旧包与 manifest 备份到 `.build/runtime-package-backups/20261003T185012Z`，身份保持 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。证据 `.build/073-information-contract-smoke.log`、`.build/073-information-contract-build.log`、`.build/073-information-contract-delivery.json`，真实只读材料另保存在该记录引用的 `.build` 文件。本轮增量源码未提交推送；视觉与实际交互待用户验收，稳定进程 PID 13504 与用户数据保持。

**异步原生提问组关闭仍未完成。** owner 接受答案、真实请求结算和 Codex 前端关闭独立管理，不把 ACK 当成关闭或再发一次答案；现有边界见[原生关闭合同](docs/design/codex-native-question-closure-contract-2026-10-03.md)。本轮来源与子任务调整不扩大此能力。

## 收起闪动、批准页缩略与临时记忆来源 · 2026-10-03 上轮开发交付

用户已确认上一轮列表位置修复；收起时闪动来自排队恢复之前的临时顶部位置，以及提前更新的可见卡片/轨道。当前源码改为布局就绪时同步定位、显示前提交，并预热旧集合和目标附近卡片；异步仅清理事务，原生与旧鼠标滚动仍优先。受支持的空字段 MCP form 改为“批准工具操作 / 批准 / 批准后继续”，实际参数表单仍需填写与验证。详见[生产交互规格](docs/design/quotaview-island-production-interaction-review-2026-09-30.md#收起详情的同步布局与纯批准文案--2026-10-03)。23 项聚焦冒烟通过，含 18 项滚动与 5 项批准语义，证据 `.build/073-scroll-flicker-focus-smoke.log`。

用户随后要求缩短长批准页。内容视口最多 440 pt，并服从小屏幕可用高度；按钮和底栏固定。长命令默认 8 行、2048 字符，展开完整内容仍在相同高度内滚动；选项标题、说明及命令规则最多两行，路径中部省略，可查看或复制完整内容。度量与实际文本限制一致，原命令、选项和回传数据不截断。

`memories_v2` 的实际临时线程不进入 state_5.sqlite、rollout 或 Desktop owner，只有 Hook 事件；此前来源识别因 SQLite 缺失而把 unknown 送入普通列表。现只读所选 Codex logs_2.sqlite 的严格原生 start 结构，以 `TurnInputRequest.start.turn_trigger=memory_consolidation` 和 Submission.id 绑定准确线程/轮次；不按标题猜测。读取限定 24 小时、128 记录、2 MiB 总量、64 KiB 单条与 50 ms 查询预算，不完整时保留未知，已有刷新可重试。迟到识别撤回旧普通卡片，转入底栏 AI 球；不同新轮次、淘汰、停止连接撤销临时标签。该补充不增加应答权限，不永久标记整个会话。详见[记忆整理规格](docs/design/quotaview-background-memory-2026-10-03.md)。

最终 **198 项相关冒烟零失败**，含 18 项滚动、5 项批准语义、3 项长内容排版及 13 项临时记忆反例；既有展示基准 P95 4.80 ms，仅代表状态投影。Debug arm64 构建、155 项生产输入和 deep strict ad-hoc 签名通过。既有开发包已替换并启动（PID **17729**，旧 PID **66379** 退出）；主程序、Debug dylib 和 Core 加载路径核对通过，旧包和 manifest 备份到 `.build/runtime-package-backups/20261003T125330Z`。身份保持 0.7.3 / 显示 Build 1 / 内部 49。证据 `.build/073-interaction-fixes-smoke.log`、`.build/073-interaction-fixes-build.log`、`.build/073-interaction-fixes-delivery.json`。本轮源码尚未提交，视觉和真实交互待用户验收；稳定版进程、安装和用户数据保持。

## 内联详情收起时保持列表位置 · 2026-10-03 上轮交付

已定位“底部任务展开再收起后跳到顶部”的几何更新根因：内容先缩短时旧视口更高，AppKit 临时将合法偏移夹到零，后续视口缩小不能恢复。任务排序、稳定 ID 和 hosting view 不变。现在在详情布局变化前捕获任务锚点，最终文档/视口就绪后只恢复一次，用户原生或轨道滚动优先，失效/卸载撤销旧恢复。没有吸附或滚轮拦截；详见[生产交互规格](docs/design/quotaview-island-production-interaction-review-2026-09-30.md#内联详情收起时保持列表位置--2026-10-03)。

59 项相关冒烟零失败（含 13 项原生滚动专项及既有展示基准），最终 Debug arm64 构建、154 项生产输入指纹和 deep strict ad-hoc 签名通过。沿用已授权的开发包替换，当前 PID **66379**，旧 PID **17592** 已退出；旧包与 manifest 备份到 `.build/runtime-package-backups/20261003T112903Z`。已核对运行包加载主程序、Debug dylib 和 Core；版本身份仍为 0.7.3 / 显示 Build 1 / 内部 49。证据 `.build/073-scroll-restoration-related-smoke.log`、`.build/073-scroll-restoration-build.log`、`.build/073-scroll-restoration-delivery.json`。实际展开/收起待用户验收；本轮修复源码尚未提交，稳定安装和用户数据保持。

## 记忆整理底栏显示 · 2026-10-03 已交付

用户已授权统一来源解析、事件接收与展示：确定的记忆整理单独使用底栏 AI 球，不进入用户会话列表、统计、自动呼出或应答能力。已接入精确 `memory_consolidation` 标识、独立后台生命周期、迟到身份迁移和只读 Desktop/App Server/Local 通路。名称或 `unknown` 不推断为记忆；Hook 不读取不存在的来源字段。

[专项规格](docs/design/quotaview-background-memory-2026-10-03.md)记录权威来源、身份/状态边界、底栏布局和失败语义。154 项相关冒烟零失败，Debug arm64 构建通过；证据 `.build/073-background-memory-smoke.log`、`.build/073-background-memory-build.log`。未知 Desktop 来源不能只凭历史类别缓存获得跟随或应答资格；迟到内部分类可撤回旧用户卡片，但不提交或回答 Codex 任务。

源码 `82a7e8a6470a3294dd0065bfd22fbd3f9ca2e02b` 已通过 [PR #72](https://github.com/Duoasa/QuotaView/pull/72) 合并 main `ea5cbcddf6f0123b3de9324e80e3642714eb2343`；PR CI 与同 SHA 的 main CI 均成功，PR CI 545 项 Swift 检查（6 项跳过）和 44 项原生合同检查零失败。

用户随后授权替换运行包。刷新 Debug arm64 构建、154 项生产输入指纹核对、嵌套 ad-hoc 签名及 deep strict 验证通过；既有 `dist/development-0.7.3/QuotaView 0.7.3 Development.app` 已替换并启动，该次交付开发 PID **17592**，旧 PID **75451** 已退出，旧包及 manifest 保存到 `.build/runtime-package-backups/20261003T110345Z`。主程序、Debug dylib 和 Core 的加载路径核对通过；身份仍为 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`，视觉待用户验收。运行证据 `.build/073-background-memory-runtime-build.log`、`.build/073-background-memory-delivery.json`。稳定进程与安装、公开 Release/appcast、版本身份和用户数据保持。

## 原生提问关闭接口调查与 AX 合同 · 2026-10-03 本轮最新

已继续核对公开生命周期与当前 renderer 状态：同步 resolved 不适用于异步问题，外部 steering 不执行原生本地关闭。纯 Dismiss 会清线程的整个选题组，可包含同轮次跨 source 的后续问题；Skip 可能提交其它草稿，不能作关闭兜底。当前未建立可用的精确组关闭接口、AX 组身份/草稿映射或事务性 lease/CAS，生产 AX 桥未启用。

[最小合同与接口证据](docs/design/codex-native-question-closure-contract-2026-10-03.md)列出具体源位置、排除原因、实际工具拒绝逐字文本和范围，以及必须由人验证的权限/身份/关闭动作。运行期工具限制不等于不能开发产品 AX；本轮只添加隔离合同夹具，不读取/操作真实 Codex UI、不激活权限或回答真实任务。实际桥接停在依赖这些证明的操作之前；夹具不宣称 native widget 已关闭。

PR #70 的合并提交 `9e67f2bde7a8a31d981e5e21e6a1cf1bfdb4ad8c` 已补查 postmerge push CI：run [37073125800](https://github.com/Duoasa/QuotaView/actions/runs/37073125800)，同 SHA，completed/success，508 项测试、6 项跳过、零失败。运行开发包仍沿用上轮已验证输入；本轮没有生产源码改动或替换安装。以下为此前修复/交付记录。

隔离合同 44 项冒烟通过（0 失败、0 真实操作），专用 CI 仅运行模拟夹具；本次记录不代表生产 AX 或原生框关闭完成。

## 已合并交付：提问提示清理与排版修正 · 2026-10-03

已补齐当前轮次、已观察异步问题的原生回答哈希结算，回答后仍保留的只读提示可精确清理；并行请求和匿名等待保持。问题标题/编号对齐、输入框区分、无物理刘海的收起标题可用空间已修正。模块根因、证据和未完成边界见 [提问生命周期梳理](docs/design/quotaview-question-lifecycle-review-2026-10-03.md)。

203 项必要冒烟、Debug arm64 构建和 deep strict ad-hoc 签名通过；181 项输入与运行包核对一致。开发包交付时 PID 75451，身份保持 0.7.3 / 显示 Build 1 / 内部 49。证据 `.build/073-question-presentation-smoke.log`、`.build/073-question-presentation-build.log`、`.build/073-question-presentation-delivery.json`。视觉与真实点击待用户验收。

**原生异步提问框关闭仍未实现或验证。** 答案回传 ACK、精确回答结算和原生界面关闭是三个阶段；当前 follower 只覆盖前两个。已自主核查 Vibe 官方材料与本地静态实现，仍无同类异步框关闭的确证；不新增系统权限，不自动回答、重复提交或用同步结束事件冒充异步关闭。仅本轮已验证修复进入源码集成；交付时源码含未提交修复，基准 HEAD `baffcbd1fe82695bc590270ab9cdef9d1c0e59cf`。上一轮 PR #69 已合并 main `f17ac8eba2143f49a1ab2f55593d16583c2f9652`，不包含本轮修复。稳定安装、版本身份、Release/appcast 与用户数据保持。

本轮安全修复源码提交 `f828264e8af7dfab06fcc1da5cf953174541348f` 已推送至 [PR #70](https://github.com/Duoasa/QuotaView/pull/70)。用户已授权对应提交 CI 通过后合并 main；CI 与最终 main 集成状态以该 PR 为准。203 项本地验证与已运行开发包单独记录，原生异步提问框关闭仍未完成。

## 历史交付：Desktop 问题交互与真实连接修复 · 2026-10-02

本轮先核对原版 Vibe Island 1.0.51、本机 Codex Desktop 26.928.40906（bundle `com.openai.codex`，CLI 0.159.2 单独记录）和实际运行包，梳理传输、当前轮次、来源准入、响应能力与 View 草稿入口。反复“仅查看”并非只缺按钮：原 socket 读取短回复会等待填满缓冲；canonical 历史/live suffix 的当前轮次合成与原生语义不一致；未知 Desktop 来源未借用仍验证有效的 Local 用户身份。另在真实多会话跟随中发现本会话完整快照约 **14.55 MiB**，超限触发旧全局 resource pause，使正常会话也丢失能力。

现使用非阻塞 socket 短帧读取与单块消费背压；超过 **9 MiB 完整帧物化预算** 的快照有界流式排空，只保留最多 64 KiB 信封元数据。完整声明帧到齐后核验当前 owner、目标、conversation/host/epoch 与版本，精确隔离对应 follow；单会话 8 MiB、总保留 32 MiB 预算保持。无法唯一归属、超出原生 256 MiB wire 边界或排空超时才暂停整条连接；不会把超限当成已回答。旧 deadline/异步失效回调在 stop/start 后不能关闭新 epoch。超大会话本身仍交由 Codex 处理，不通过提高内存上限或压缩用户任务制造可操作能力。

当前轮次按原生 canonical/live 合成规则处理；canonical 引用缺失时保持非权威，不能清除旧等待。未知 source 仅借用当前目录代次内仍验证且保留的用户身份，internal、无效、已撤销、旧目录身份拒绝；来源准入不代替 owner 输入能力证明。问题 View 和冒烟共用 `IslandQuestionInteractionEntry` 及真实 Board UUID 草稿 Binding：选项/自行输入只更新草稿和选中状态，切换保留文字，点击“确认”才单次回传。可覆盖的问题使用“跳过 / 确认”，无法覆盖才在 Codex 处理。同步跳过原生空 answers；异步原生界面跳过没有 follower RPC，Island 仅隐藏提示，不能声称关闭 Codex 提问。

最终 **188 项必要隔离冒烟**、Debug arm64 构建、固定身份/资源和 deep strict ad-hoc 签名通过，开发包 PID **94157**，替换旧开发实例 [63703]；身份保持 **0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`**。178 项构建输入指纹核对一致。证据 `.build/073-question-capability-smoke.log`、`.build/073-question-capability-build.log`、`.build/073-question-capability-delivery.json`。

打包 Core 真实只读多 follow 核对：超大会话 scope 被隔离，同一连接仍收到命名测试任务的权威快照、owner 输入能力；probe 仅在显式 stop 后断开，真实答案发送数为 0。实际开发进程同样保持 connected 并记录会话级 resource_limit。测试任务当时已完成，不能据此声称真实待确认点击验收通过；该行为由隔离真实 Unix socket + 生产 View 草稿入口 smoke 验证，实际交互仍待用户验收。证据 `.build/073-question-capability-stock-readonly.json`、`.build/073-question-capability-stock-multifollow-readonly.json`。181 项中间包只读单任务核对没有覆盖多 follow 资源问题，不能作为最终交付；187 项后又补旧 epoch 回调边界并以 188 项完成复验，历史证据保留。

本轮修复提交 `3317b3c92d27b518b9d275214c28170af0dc8a9e` 已推送至 [PR #69](https://github.com/Duoasa/QuotaView/pull/69)，指向 main。用户明确授权检查 GitHub CI 后合并；GitHub 完整 Swift CI 与实际合并状态以该 PR 为准。本轮 188 项本地验证与已运行开发包输入独立记录；历史 PR #68 不包含本轮新修订。仅更新既有开发包；稳定安装、版本身份、公开 Release/appcast 和用户数据保持。没有 UI 自动化或真实任务回答。下列交付数字和 PID 均为历史记录，当前结果以上述最新节为准。

## 历史交付：问题交互、手动收起与等待纠正 · 2026-10-02

问题页补齐原生允许的“自行输入”，选项和输入只改草稿，切换选择保留文字；有明确选中反馈，全部必填内容就绪后点击“确认”才按原请求身份发送一次。同步提问的“跳过”发送原生空 answers；异步提问的原生跳过仅属于界面本地状态，灵动岛只隐藏本轮提示，不发送空答案或伪造 steering，也不能保证关闭 Codex 原生窗口提示。未支持的结构、多选或未证明 Desktop 能力继续在 Codex 处理。原始 Desktop owner/epoch/turn 与 ACK/解决边界保持。

待确认可以手动收起；同请求的普通刷新不会重新展开，草稿保留，新请求/新待确认会话仍按自动弹出偏好呼出。补齐 local-only 用户任务的只读 Desktop follow，临时原始线程身份只来自验证过的当前目录/轮次元数据，不落盘或提升观察通路权限；停用、换目录、LRU 撤销和分类期间迟到回调同步失效。

卡在“请求详情暂不可用”的根因是 Desktop runtime flags 被投影丢弃，且 Core/Island 只在移除 typed 请求时同步解除等待。现同时读取当前 owner 的完整 pending 集合与 runtime flags，明确运行且无待确认时清理同轮次匿名等待，即使没有 typed 删除也同步 Core 状态。未知/部分数据、未来 RPC、真实 typed/async 和并行等待保留；已绑定 owner/epoch 的证据只在对应作用域解除，重新观测到同 blocking 请求可迁移等待证据与真实 handle，避免重连留下旧 aggregate wait。已核实的 time/token/attestation 自动服务 RPC 不作为确认阻塞。

最终 **134 项必要隔离冒烟、Debug arm64 构建、固定身份/资源、deep strict ad-hoc 签名及准确路径启动核对通过**，当前开发包 PID **240**，替换旧开发实例 [90147]；身份保持 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。证据 `.build/073-question-interaction-final-smoke.log`、`.build/073-question-interaction-final-build.log`、`.build/073-question-interaction-delivery.json`。新增夹具首次混用模拟和 live 时间，已统一时钟，14 项专项复验及最终 134 项复验通过；首次失败与修正证据保留在 `.build/073-question-interaction-fixture-clock-*.log/json`。176 项输入指纹与已运行包核对一致；生产源码在最终构建后未改变，只修正测试夹具。

本轮修订尚未提交推送，基准 HEAD `800d1ce53814459fe8d2d36750d0941d4345a260`；上轮 [PR #68](https://github.com/Duoasa/QuotaView/pull/68) 已合并 main `870c89dc2f648f2b3256960c62758c9a8853d7dd`，不能视为包含本轮新修订。稳定安装、冻结开发台、版本身份和公开 Release/appcast 保持。未操作真实待确认、未做 UI 自动化或完整本地回归；视觉和实际点击由用户验收。以下为历史交付，旧 PID/验证数字属于当时记录。

## Desktop 直接确认与双向同步 · 2026-10-02

按用户要求参考原版 Vibe Island 1.0.51 和本机 Codex 0.159.2 的实际 Desktop owner/follower IPC，实现原任务确认详情与回传；模块职责、协议和失败语义见 [Desktop 确认同步规格](docs/specs/codex-desktop-confirmation-sync.md)。普通审批、同步提问和受支持工具表单使用原始 RPC；异步问题使用原生 questionItemId 和回答 steering 消息，不伪装成审批。新真实请求自动进入详情，刷新不抢焦点，既有手动页面、其他请求草稿和自动弹出偏好保持。此前纯观察模式只适用于没有已证明 Desktop 能力的来源。

能力由实际 owner、当前轮次、精确 typed ID 和连续状态证明，不能从 Local/Shared/Hook 的观察详情推断。ACK 仅为已发送，权威请求移除或精确接受的答案才解除；外部 Codex 操作同步清理，对应 Core 等待和提醒随之更新，并行请求保留。首次 owner 尚未就绪可有界恢复；切目录先撤销旧代次，分类重入和晚 ACK 不回写新状态。资源按会话撤销能力而不假装已回答，内存、帧和队列有界，原始会话状态不落盘。协议属于当前 Codex 私有接口，未知版本/类型、外部授权和复杂表单仍在 Codex 处理。

98 项必要隔离冒烟、真实只读 initialize 握手、新 Derived Data Debug arm64 构建、固定身份/资源和 deep strict ad-hoc 签名通过；证据 `.build/073-desktop-confirmation-smoke.log`、`.build/073-desktop-confirmation-handshake.json`、`.build/073-desktop-confirmation-build.log`、`.build/073-desktop-confirmation-delivery.json`。仅更新既有开发包，当前 PID **90147**，身份保持 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。未替用户处理真实确认；视觉和真实点击待用户验收，本地无完整回归或 UI 自动化。用户已授权本轮源码推送 GitHub 并合并 main；源码提交 `5461059bedb918dc74f344feac2fe7b852020153` 已推送至 [PR #68](https://github.com/Duoasa/QuotaView/pull/68)，完整 Swift CI 和合并状态以该 PR 为准。基准 PR #67 已合并；manifest 保留已运行包的实际输入指纹和本轮集成状态。以下保留历史交付，稳定安装与公开 Release/appcast 保持。

## Hook 原生配置与待确认关联修复 · 2026-10-02

本轮按用户要求全面梳理 Hook 配置、传输重播、任务准入、请求生命周期和状态投影，修复 Codex 更新后的配置失效、真实提问漏报、确认内容错配与回答后卡住。职责、反例和边界见 [Hook 与请求状态模块梳理](docs/design/quotaview-hook-request-module-review-2026-10-02.md)。

Hook 启动时幂等维护稳定命令，通过 Codex 原生 `hooks/list` 核验和 `config/batchWrite` 完成首次所选目录授权及热重载。首次仍需一次授权，不使用 Terminal/expect 模拟按键。私有路由文件与 Helper 按渠道、数据目录隔离；只迁移能验证 Socket/令牌归属的旧条目。`config/read` 只解码 Hook 偏好键，尊重常规、内联表、引号等合法配置中的显式禁用，也兼容其它字段为 null。用户停用意图在清理前持久化；清理失败、重新检查、重启和旧事件均不能恢复已停用通路。App Server 与本地读取继续独立工作。

配置事实、原生信任、历史送达和本轮新鲜送达分开记录。队列先缓冲，配置就绪后明确重播；拒绝不依赖下一次文件写入才能重试。运行代次使换目录、停止后的旧回调失效。收到旧事件不能恢复已撤销的信任。

所有生产公开消息先通过 Store/Registry 的目录、连接和当前轮次准入，再附着详情。迟到旧轮次不能先覆盖 Island。无线程 ID 的解决通知仅按同连接已观察到的数字/字符串 RPC 关联；重连和歧义 ID 不跨任务清理。启动恢复只取 active 用户线程的最新 inProgress 轮次元数据（limit 1 / notLoaded）；没有明确当前轮次或接口不支持时，历史保持未确认，不猜测运行。

请求生命周期集中管理调用、RPC、详情升级与解决，任务状态从执行事实和阻塞证据派生。同步和异步提问使用同一模式定义，展示真实标题、问题及选项；异步发送回执不视为回答。工具 B 不清除 A，线程恢复不回答独立异步问题，未知输出不建立未来请求的解决标记。精确解除通过同轮次、同连接证据同步 Core 快照和提醒；仍有并行阻塞时继续等待。无身份 Hook 等待只由权威线程解除或轮次结束清除。本地观察保持只读，实际应答权不从独立 App Server 推断；私有推理不进入显示。

76 项必要隔离冒烟通过，包括 Shared → Store → Island 的端到端乱序、重连、暂停恢复及并行请求场景、原生配置和 Helper/队列边界。Debug arm64 构建、固定身份和 deep strict ad-hoc 签名核对通过，当前开发包 PID 41104。身份保持 0.7.3 / 显示 Build 1 / 内部 49；源码/包指纹记录在忽略的开发 manifest。证据 `.build/073-native-hook-final-smoke.log`、`.build/073-native-hook-build.log`。完整 CI 暴露的终态夹具遗漏第二轮原生来源，已明确其 App Server 来源，并与旧轮次拒绝场景一起专项复验 2 项通过（`.build/073-native-hook-ci-terminal-smoke.log`）；生产准入约束不变。CI 暴露的短 compact 观察窗口改为先观察再同步武装隐藏计时，假服务 RPC 预算与 Runtime 的 8 秒上限对齐；配置夹具、3 项真实原生探针与计时共 9 项专项复验通过，证据 `.build/native-hook-fixture-rpc-budget-smoke.log`、`.build/073-native-hook-ci-fixture-smoke.log`。计时、授权哈希断言与生产实现保持。真实 Helper 传输夹具已按生产契约同时启动 Socket 和私有队列，按 eventID 等待状态应用并验证重复回放；与独立 Socket ACK 共 2 项专项复验通过（`.build/073-native-hook-ci-transport-smoke.log`），生产 750 ms 预算保持。此前启动核验的 12 组开发 Hook 迁移与 6 组其它 Hook 内容保留证据继续保留。首次原生授权及视觉、真实交互待用户操作和验收。本地未扩展完整回归或 UI 自动化；GitHub 完整 Swift CI 和 main 合并状态以 [PR #67](https://github.com/Duoasa/QuotaView/pull/67) 为准，本轮未发布 Release/appcast。


## 设置精简与自动弹出 · 2026-10-02

按本轮截图与反馈精简设置：通用的退出入口改为整行红色图标/文字按钮，确认后退出；用量显示只保留成本估算和 Token 活动两个开关，移除页面预览。周期额度、Spark（有数据时）、Credits、一天/30 天/累计 Token 与重置入口始终显示，旧七项偏好仅保留存储。移除显示位置说明，自动展开改为可操作设置。

自动弹出默认开启，任务开始、完成和待确认沿用默认展开行为。停留时间 1–10 秒，默认 3 秒，下次自动弹出采用新时长；待确认保持展开。关闭后这些事件均不自动打开，手动打开、选择卡片、用量/重置和固定页面保持可用；关闭设置只收起自动打开的预览。后台任务观察继续运行，内容更新不重复计时。四种实际特效缩成单排预览：预览高 32 pt、外框高 48 pt，外圆角 12 pt、内边距 8 pt、内圆角 4 pt，四角同心；名称置于外框下方。中英文说明、加载/旧数据/隐私、请求状态和重置须知均已精简，失败原因、未知数据与演示限制保留。

独立审查修正了无条件要求在 Codex 处理请求的文案，提示按实际应答能力显示。10 项相关隔离冒烟通过，覆盖路由/本地化、基础数据固定显示、偏好持久化与时长边界、关闭后三类事件、7 秒计时、手动/固定页保持、实际预览圆角、刘海安全区及重置/页面高度。最终 Debug arm64 构建、资源/固定身份、ad-hoc 深度签名与启动核对通过；开发包 PID **80544**，仍为 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。证据 `.build/073-settings-simplify-smoke.log`、`.build/073-settings-simplify-build.log`。视觉与真实交互待用户验收，无截图或 UI 自动化；历史基准保留，本轮未重复。

源码提交 `60c76e4cac70ac9a5c783a7a9f18fc485dad15cf` 已推送至 [PR #66](https://github.com/Duoasa/QuotaView/pull/66)，用户已授权合并 main；CI 与合并状态以该 PR 为准。以下为此前交付历史；本节的两个用量开关、紧凑特效和自动弹出控制替代上一轮九项开关及只读说明。稳定安装、版本身份、公开 Release/appcast 和冻结开发台保留。

## 设置设计、显示偏好与上下栏统一 · 2026-10-02

按用户已打开的 Vibe Island 原生设置窗口读取通用、显示、用量与集成页，参考其彩色分类图标、分组卡片、中性菜单选中/悬停、右侧开关、值菜单与圆形双箭头，以及可视化选项的布局和选中描边。设置重组为通用、灵动岛、用量显示、Codex 连接、网络代理和侧栏固定底部的关于；菜单共用选中与 hover 反馈，保留 Tab 焦点、上下键切换、原生菜单/开关与中英文。六项菜单及页头图标均为彩色圆角图标。

通用只管理语言、设置窗口外观和退出。外观使用系统/浅色/深色可视化选项；关于沿用老通用页的正式 96 pt App Icon、产品信息和实际版本布局，并承接更新状态及正式构建可用的更新操作。调试构建显示真实不可用原因。Codex 目录、兼容 Hook 与 HTTP/SOCKS5 代理保存/测试能力保留。

恢复状态烟雾、晶钻前沿、量子噪点、液态涌浪四项选择，使用既有真实渲染器预览并把选择接入任务及待确认卡片。用量显示复用原有持久化偏好，九个开关实际控制周期概览、Spark、Credits、一天/30 日/累计 Token、成本估算、Token 活动和重置入口；周期概览恢复全部实际可用周期。可视化预览缩放复用生产用量页，读取当前/缺失/隐私状态，不新增演示账户数据。隐藏项不保留空槽；当前页面与固定状态保持，真实重置仍仅演示。

任务、用量、重置与待确认页共用展开态栏位：文字统一为返回任务使用的 12 pt Medium，状态仅区分颜色；按钮 28 pt 命中区域，图标组间距 8 pt，容器左右 28 pt、文字前导 8 pt、底部 12 pt。共用底栏替代各页独立字号/高度/内边距。上栏的用量、返回、请求切换、筛选、固定、收起，以及所有下栏刷新/设置，都使用相同胶囊 hover 8.5% / 按压 14% 白色高亮；无手型或额外描边。摄像头安全区保留，长统计内容在可用高度内滚动，底栏固定可达，重置说明移到内容区避免压缩底栏。

六项相关隔离冒烟通过，覆盖六页路由/本地化/系统符号、九项偏好与特效持久化、真实刘海安全区、刷新去重、页面/固定状态以及小屏幕高度。最终 Debug arm64 构建、资源、固定身份、ad-hoc 深度签名与启动核对通过，开发包 PID **46481**，身份保持 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。证据 `.build/073-settings-reference-chrome-smoke.log`、`.build/073-settings-reference-chrome-build.log`。只读取参考应用和用户截图，没有对 QuotaView 进行截图或 UI 自动化；视觉与真实交互待用户验收。用户已授权本轮源码推送并合并 main；源码提交 `bd4d928075b3ba916ae64f927ea4c2abbcccf21f` 已推送，CI 与合并状态以 [PR #65](https://github.com/Duoasa/QuotaView/pull/65) 为准。稳定安装、公开 Release/appcast 与冻结开发台保留。

## 刘海主入口与设置重组 · 2026-10-02

0.7.3 开发版由新版刘海灵动岛承接主入口，启动不再创建状态栏快捷显示或旧弹出面板。任务、用量、重置页右下角共用“刷新用量、设置”两项工具，保持相同顺序、28 pt 命中尺寸、系统符号与胶囊 hover/按压高亮；不占用刘海两侧的导航与待确认空间。刷新状态跨页面共享，并发点击只产生一次用量请求；加载/缺失状态也保留设置和刷新入口。

设置默认打开“通用”，侧栏按“应用 / 服务”分组为四项：通用（语言、设置窗口外观、实际版本、软件更新状态、退出）；灵动岛（隐私开关及当前显示/任务/动效行为说明）；Codex 连接（自动连接、目录选择及既有兼容 Hook）；网络代理（既有 HTTP/SOCKS5、保存及连接测试）。旧菜单栏、旧面板内容、旧玻璃质感和隐藏主岛的设置已从可达菜单移除，保留旧偏好存储。固定位置、展开时长、动效和观察模式只作真实行为说明，不提供尚未实现的切换器；开发版不显示不可用的在线更新操作。

主岛随应用运行保持可达，旧独立岛的隐藏偏好不再隐藏主入口；锁屏/休眠生命周期继续保持。再次打开应用可唤起设置窗口；关闭设置窗口不退出应用。“通用 → 退出软件”沿用既有异步关闭流程，停止 QuotaView 用量服务和本地观察，Codex 中的任务继续运行。设置沿用系统字体、语义色、原生控件、现有窗口几何与圆角，灵动岛保持原有黑色界面；重置继续仅演示。

四项必要隔离冒烟通过，覆盖仅当前能力的设置路由与中英文/系统符号、跨页面刷新去重和状态保持、页面固定/高度以及固定生命周期。Debug arm64 构建、资源、固定身份、ad-hoc 深度签名和启动核对通过；开发包当前 PID **19448**，身份仍为 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。证据 `.build/073-primary-island-settings-smoke.log`、`.build/073-primary-island-settings-build.log`。未扩展完整本地回归或重复基准，未进行截图或 UI 自动化；视觉与真实交互待用户验收。用户已授权本轮源码推送并合并 main，源码提交 `021cd8cf7590e6b9f9cd3eacc91dd45ac5813693` 已推送，CI 与合并状态以 [PR #64](https://github.com/Duoasa/QuotaView/pull/64) 为准；稳定安装、公开 Release/appcast 和冻结开发台保留。

## 重置入口排版与返回节奏修正 · 2026-10-02

重置入口移除内层圆角背景和额外 6 pt 内边距，恢复账户卡片原有 14 pt 内容对齐。悬停只点亮账户卡片背景：底部白色高光 12%，向上渐隐，到中部透明；文字和票券上不叠遮罩，无新增描边或指针变化。移开、进入过渡或卸载时清理高亮；减少动态保留静态反馈。

返回原先倒放展开的时间曲线，使落位缓动出现在起步阶段。现将空间方向反转，但进出共用正向时间曲线：返回立即旋转缩小，最后轻微过冲并缓动落位。完整 360° 旋转、0.76 秒总时长、实际布局锚点和中途反向衔接保留；只改变图层，不逐帧改变窗口或排版。落位后继续 3D 悬停缓动和 2 秒高光周期；真实重置仍仅演示。

三项必要隔离冒烟通过，覆盖双向相同起步节奏、返回首帧位移、完整旋转与最终落位、途中切换/减少动态/卸载，以及页面固定/高度。Debug arm64 构建、资源/固定身份、ad-hoc 深度签名与启动核对通过，开发包当前 PID **98149**；身份保持 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。证据 `.build/073-reset-hover-return-smoke.log`、`.build/073-reset-hover-return-build.log`；交付清单记录源码与可执行文件/调试库指纹。未重复完整本地回归或基准，未进行截图或 UI 自动化；视觉与真实交互待用户验收。

用户已授权本次修正推送 GitHub 并合并 main；源码提交 `cc9a13e` 已推送，[PR #63](https://github.com/Duoasa/QuotaView/pull/63) 为本轮 CI 与 main 合并状态的依据。当前开发包与源码构建输入一致，视觉与实际交互仍待用户验收。以下保留此前交付历史；稳定版、版本身份、公开 Release/appcast、本机冻结开发台及旧交接文件保持。

## 重置卡 0 次空状态 · 2026-10-02

重置次数明确为 0 时，用量入口显示“0次 · 暂无可用”，仍可点击查看状态；使用页保留卡片、真实额度和更新时间，原重置前提醒改为“暂无可用重置卡”及返回查看额度/恢复时间的说明。全宽操作按钮禁用并显示空态文案，刷新和返回入口可用。缺失次数继续显示破折号及“重置卡数据尚未读取”，不伪造零。刷新恢复可用次数后恢复正常演示按钮；次数变化清理旧演示反馈，旧“演示完成”不能覆盖空态。真实重置仅演示。

两项必要隔离冒烟通过，覆盖零/未知/可用状态、简中/English 文案、旧反馈覆盖和最后一张卡恢复，以及既有页面高度/返回逻辑。最终 Debug arm64 构建、资源/固定身份、ad-hoc 深度签名与启动核对通过，开发包当前 PID **85142**；身份保持 0.7.3 / 显示 Build 1 / 内部 49。证据 `.build/073-reset-empty-smoke.log`、`.build/073-reset-empty-build.log`。本轮局部空态修订未重复基准或完整本地回归，视觉与真实交互待用户验收，无 UI 自动化。

用户已授权完成后推送 GitHub 并合并 main；空态源码提交 `acc4487` 已推送，[PR #62](https://github.com/Duoasa/QuotaView/pull/62) 为本轮 CI 与 main 合并状态的依据。此前 [PR #61](https://github.com/Duoasa/QuotaView/pull/61) 已合并，以下为历史交付与验证记录。本机开发台及旧交接文件继续保留。

## 本轮源码集成 · 2026-10-01

用户已授权将本轮开发源码推送 GitHub 并合并 `main`：入口 hover、本地按轮次归档、正常聊天来源修复、重置卡使用页/完整旋转/周期高光以及用量失败恢复。保留本机冻结开发台和旧交接文件；独立开发身份仍为 0.7.3 / 显示 Build 1 / 内部 49，运行包 PID 70578。本轮为源码集成，视觉与实际交互仍由用户验收；源码提交 `55e1cc3` 已推送至 GitHub，[PR #61](https://github.com/Duoasa/QuotaView/pull/61) 为 CI 与 main 合并状态的依据。下方“未提交推送”属于各次修改当时的历史状态。

沿用已通过的必要隔离冒烟、128 任务基准和最终开发构建，不重复本地完整回归或 UI 自动化；GitHub CI 按仓库既有工作流运行。最新证据 `.build/073-usage-recovery-smoke.log`、`.build/073-usage-recovery-build.log`，归档/来源和动效证据见下方记录。

## 用量失败恢复与重置入口修订

2026-10-01：定位到开发版每 60 秒刷新失败后清空 `snapshot`，运行时随错误丢弃用量页整份数据；此前首次加载也使用相同“无法获取”空态。截图中的 38% 属于稳定版，不能作为开发版取数证据。开发版自己的诊断有 22:58:33 成功读取记录，但成功会移除上一条错误，故历史失败的具体上游原因未确定。

已改为原子化发布灵动岛用量状态：首次读取显示加载，超时/连接退出/暂时不可用时保留内存中上次成功数据，页面明确标记“上次成功数据 · 等待刷新”并披露安全的错误类别；成功自动恢复。权限拒绝、找不到程序、格式错误、连接配置更换和停止清空旧快照，缺失数据不伪造零。顶部当前额度、连接状态及操作可用性仍要求最近读取成功；隐私态不披露旧快照。额外保留最近失败类别及时间，后续成功不抹去该诊断；不保存原始响应。

卡片进入完整旋转 360° 后落位，退出沿原样本反向旋转缩小；红色“额度重置”按钮复用提醒操作按钮的 42 pt 高度、10 pt 圆角和 13 pt 半粗文字，铺满内容宽度。重置入口只增加 hover 背景高亮与少量提亮，无描边或指针变更；保留 3D 缓动、2 秒高光周期与 1.6 秒扫动。真实重置仍为演示。

6 项必要隔离冒烟和最终 Debug arm64 构建通过；资源、固定身份、ad-hoc 深度签名和启动核对通过。独立开发包当前 PID **70578**，0.7.3 / 显示 Build 1 / 内部 49；稳定版安装未动。证据 `.build/073-usage-recovery-smoke.log`、`.build/073-usage-recovery-build.log`。前轮 128 任务基准仅保留历史证据，本轮未重复；视觉及真实交互由用户验收，未自行截图或 UI 自动化，源码未提交推送。

交付后只读核对：开发版自己的最近成功读取为 **23:20:36**，可用状态 `ready`；本轮启动后尚无新增失败类别。当前成功不推断历史失败原因。安全诊断证据 `.build/073-usage-recovery-diagnostics.log`，只含时间/类别/状态及交付核对，无账户响应。

## 重置卡使用页与双向 3D 过渡

2026-10-01：按 [Figma 140:3 中的重置使用页 149:292](https://www.figma.com/design/hS0Dwc9S9EJGEbkkplxH4v/QuotaView?node-id=149-292) 实现独立内容页：378 pt 基准宽度、201.29 × 120 pt 卡片、真实重置次数/周额度、提醒区、红色演示操作和更新时间/刷新。真实刘海较宽时只扩展页面宽度以容纳导航；沿用原刘海外壳。Figma 提醒的重复占位文案使用既有三条重置说明替换；次数未知不伪造零，缺失/耗尽禁用演示按钮。演示标记可见，点击只显示本地反馈，不调用消费接口。

用量页 53.6774 × 32 pt 小卡片与使用页大卡片采用实际布局锚点；0.76 秒内只在 Core Animation 图层插值位移、尺寸和透视旋转，轻微过冲后落位。初版退出按同一组轨迹和旋转样本倒放（时间倒放已由 2026-10-02 的返回节奏修正替代），途中返回从当前呈现位置衔接；两页保持最终排版并淡入淡出，不逐帧改变窗口或页面布局。原卡面与 OpenAI 标记矢量资源和新 Figma 导出一致，按 3.75 倍比例复用。落位后保留固定平面悬停 3D 缓动及标记视差。

高光统一为每 2 秒一次，扫动段从 1.2 秒放慢至 1.6 秒，周期前后各留 0.2 秒卡外停顿；大卡片等比缩放光带和圆角。隐藏页、收起、暂停特效、减少动态和卸载时停止；普通快照刷新不重启动画。减少动态直接切换页面，Escape 先返回用量再返回任务；固定状态保持，新任务通知不打断正在查看的用量/重置流程。原系统模态遮罩和卡内说明均已由此页替代。

5 项隔离冒烟、128 任务基准（120 次，P95 3.443 ms、最大 49.555 ms）、Debug arm64 构建、资源/身份及 ad-hoc 深度签名检查通过。开发包已更新并启动 PID **56673**；0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073` 保持。证据 `.build/073-reset-flight-smoke.log`、`.build/073-reset-flight-build.log`。视觉及真实交互待用户验收；本次只读取 Figma 和用户视频参考，未自行截图或 UI 自动化，源码未提交推送。

## 历史：票券周期高光与演示遮罩修复（已由使用页替代）

2026-10-01：白色额度重置票券增加每 5 秒一次的斜向高光，单次扫动 1.2 秒，其余时间停在卡片外；叠在卡面上并跟随既有 3D 倾斜。使用单条 Core Animation 渐变位移动画，不逐帧刷新 SwiftUI 布局或数据；统计页离开、岛隐藏/收起、减少动态及卸载时停止，常规数据刷新不重启周期。

用户截图中的大片阴影来自系统 `.alert` 对灵动岛整段预留高度透明窗口施加的模态遮罩。已移除系统弹窗，改为账户卡内 176 pt 宽的说明浮层，含“知道了”关闭按钮；保持重置仅演示，不消耗次数或改变真实额度。

2 项必要冒烟（高光启停/重刷周期、用量页切换/固定/高度）、Debug arm64 构建、身份与 ad-hoc 签名检查通过。开发包已更新并启动 PID 44980；0.7.3 / 显示 Build 1 / 内部 49 保持。证据 `.build/073-ticket-sweep-smoke.log`、`.build/073-reset-note-smoke.log`、`.build/073-ticket-sweep-build.log`。视觉及真实点击待用户验收，未自行截图或 UI 自动化，源码未提交推送。

## 额度重置票券 3D 缓动

2026-10-01：白色额度重置票券增加鼠标悬停跟随的 3D 缓动：水平最大 10°、垂直最大 7°，0.35 秒阻尼弹簧回正；少量光泽、投影和标记视差增强层次。保留 53.677 × 32 pt 几何和静态素材；固定平面跟踪鼠标，不跟随倾斜面改变命中区域。移开/卸载回正，无常驻计时器或后台循环。减少动态效果时取消倾斜、视差、缩放和动画，保留静态 hover/按压反馈；点击仍仅打开重置演示，不消费真实额度。

1 项已有用量面板切换/固定/高度冒烟及 Debug arm64 构建通过，独立开发包身份和 ad-hoc 签名核验通过，已启动 PID 41767；0.7.3 / 显示 Build 1 / 内部 49 保持。证据 `.build/073-ticket-motion-smoke.log`、`.build/073-ticket-motion-build.log`。实际 3D 观感由用户验收，本次未截图或 UI 自动化；源码仍未提交推送。

## 本地归档与任务来源修复

2026-10-01：修复正常交接聊天 `source=vscode / thread_source=agent_created_thread` 被误判内部任务导致的“0 会话”；真正 `subagent` 和 `guardian_review` 仍排除。每张卡片（含待确认页来源卡片）右上角增加归档按钮，仅隐藏 QuotaView 当前轮次及其详情/计数，本地保存哈希，刷新与重启保持隐藏，新轮任务重新出现；不归档/删除 Codex 聊天、不停止任务、不改变待确认请求。数据面板 hover 胶囊保留。

5 项隔离冒烟、128 任务基准（P95 3.467 ms、最大 43.248 ms）和 Debug arm64 构建通过，开发包 ad-hoc 签名/身份检查通过并启动，PID 34738；0.7.3 / 显示 Build 1 / 内部 49 不变。只读诊断已确认本聊天新的本地事件 `task_applied`，不代表 UI 验收。证据 `.build/073-local-archive-smoke.log`、`.build/073-local-archive-benchmark.log`、`.build/073-local-archive-build.log`、`.build/073-live-source-verification.log`；实际视觉/交互待用户验收。本次含上一轮 hover 的本机增量未提交推送，基线提交仍为 `4fb9899`。

## 数据面板入口 hover 修订

2026-10-01：数据面板入口增加 hover 深灰胶囊（28 pt 高、左右各 8 pt 内边距），按下加深并轻微缩放，减少动态时保留静态反馈。1 项已有用量面板切换冒烟、Debug arm64 构建、身份与 ad-hoc 签名检查通过；开发包已更新并启动，PID 26238，0.7.3 / 显示 Build 1 / 内部 49 保持。证据 `.build/073-usage-hover-build.log`、`.build/073-usage-hover-smoke.log`；视觉与交互待用户验收。本次源码未提交推送，先前 `4fb9899` 为基线提交。

## 2026-10-01 当前源码提交与会话交接

本轮用户授权推送并合并 main，范围为统计页 Figma 排版、图表与 Token 单位修正、任务自动展开/待确认常态展开、收起态状态内容及无刘海居中。22 项相关冒烟通过，128 任务基准 P95 3.481 ms、最大 3.626 ms（`.build/073-final-source-merge-smoke.log`）；沿用已验证开发构建 `.build/073-compact-center-build.log`，PID 12943 与源码指纹一致。仅交付源码，不发布或替换稳定安装；视觉与交互由用户验收。提交包含新增重置票券 SVG 资源，本机冻结开发台和旧交接文件保留。后续入口见 [本轮开发交接](HANDOFF-CONTINUE-2026-10-01.md)。下方“未提交推送”为各次修改当时的历史记录；本轮 GitHub 合并结果以 PR 为准。


2026-10-01：收起态无刘海使用等宽左右区域，使状态区域相对整岛居中；短文字居中、长文字在中间裁切滚动。有刘海沿用左侧安全区域，右侧统计不变。开发构建、签名与启动核验通过（`.build/073-compact-center-build.log`，PID 12943），视觉待用户验收，未提交推送。

2026-10-01：收起态中间文字改为状态与公开操作内容组合，操作为空时回退任务名称，无任务时显示已有连接/空状态摘要。沿用原有隐私脱敏、滚动与刘海安全区域。覆盖全部视觉状态的中英文及空内容冒烟通过，开发构建与签名校验通过；新版 PID 11399，视觉待用户验收，未提交推送。证据 `.build/073-compact-status-smoke.log`、`.build/073-compact-status-build.log`。

2026-10-01：任务启动及完成自动展开 3 秒，内容刷新不延长计时；任意待确认持续展开，全部解除后收起；固定状态保留。首次快照及恢复可见不重播历史完成事件，隐藏时取消计时。19 项既有冒烟及 1 项新增生命周期冒烟通过，Debug arm64 构建、签名校验通过，新开发包 PID 9289。证据 `.build/073-auto-preview-smoke.log`、`.build/073-auto-lifetime-smoke.log`、`.build/073-auto-preview-build.log`；视觉与真实交互待用户验收，未提交推送。

最新修订（2026-10-01）：PID **5272** 已启动。成本绘图区在卡片既有 14 pt 内边距基础上增加顶部 14 pt 安全留白，最终顶部 28 pt、底部保持 14 pt；柱高按剩余绘图区计算。文字区、卡片尺寸及灰度规则保持。开发构建、签名与启动冒烟通过（`.build/073-cost-safe-inset-build.log`）；视觉待用户验收，未提交推送。

最新修订（2026-10-01）：PID **3919** 已启动。按连续反馈，成本绘图区左右居中并随两侧文字自然高度铺满有效上下空间，移除固定 52 pt 高度，最高柱抵达绘图区上沿。最终配色覆盖中间蓝色方案：成本按金额相对大小分为不透明灰度 0.35/0.48/0.62/0.76，选中/悬浮纯白带描边，零/缺失 0.18；Token 活动仍蓝色。卡片内边距、柱宽/间距/圆角不变。开发构建、签名与启动冒烟通过（`.build/073-cost-gray-fill-build.log`）；视觉由用户验收，未提交推送。

最新修订（2026-10-01）：PID **99996** 已启动。成本图普通柱从灰度 0.76 调为不透明 0.40，选中/悬浮从 0.95 调为纯白，缺失数据仍 0.16。几何与交互保持。开发构建、签名及启动冒烟通过（`.build/073-cost-highlight-build.log`）；高亮效果由用户验收，未提交推送。

最新修订（2026-10-01）：PID **98641** 已启动。统计标题全部移除图标；成本柱共享活动格子的宽度公式、3 pt 间距、最大 2 pt 圆角，30 日柱不再均分拉伸，tooltip 锚点按真实柱间距计算。成本左右等宽摘要，金额统一 Asta Sans 21，左下最近30天、右下估算说明；外层边距保持。三档宽度几何检查、开发构建、签名与启动冒烟通过（`.build/073-chart-rhythm-build.log`）；视觉由用户验收，未提交推送。

最新修订（2026-10-01）：PID **97065** 已启动。共用 Token 紧凑计数器增加 B：十亿起使用 B，例如 7.7B；不足十亿沿用 M/K，统计指标、成本提示与任务计数同步生效。活动图中文万/亿提示仍遵循已确认的 Codex 样式。1 项边界冒烟、开发构建、签名与启动检查通过（`.build/073-token-b-*`），未提交推送。

最新修订（2026-10-01）：PID **95243** 已启动。修复活动图浮层被成本卡片遮挡：移除成本卡固定 zIndex，在同级卡片处仅抬高当前悬浮卡片；内部浮层层级、边距与刘海遮罩保持。开发构建、签名与启动冒烟通过（`.build/073-tooltip-layer-build.log`）；实际遮挡效果待用户验收，未提交推送。

最新修订（2026-10-01）：PID **93900** 已启动。按用户 Figma 140:3 更新统计页：左列额度横条及三项 Token，右列等高账户卡与重置票券；成本图横向紧凑排布，活动标题与周期同一行，数值使用既有 Asta Sans。沿用实际 IslandVibeLayout.listInset=28 及原有刘海轮廓、上下边距，不照搬 Figma 外壳。每周/累计改为 53 列×7 格的底部堆叠图，以高度表示用量、整列悬浮高亮；累计包含窗口之前用量并按周显示。额度、积分、次数均来自快照，重置仅演示。3 项针对性冒烟、arm64 Debug 构建、资源与签名检查通过（`.build/073-figma-layout-*`）；不作视觉验收。本轮尚未提交推送。

最新交付（2026-10-01）：用户授权将本轮统计页及显示调整提交 GitHub、合并 main。Figma 可编辑稿已绘制至 https://www.figma.com/design/hS0Dwc9S9EJGEbkkplxH4v/QuotaView?node-id=143-2 ，采用截图示例数据。源码 18 项针对性冒烟（含 128 任务基准）通过，P95 1.645 ms、最大 4.412 ms；证据 `.build/073-source-merge-smoke.log`。沿用已通过的最终开发构建，不发布 Release、不修改 appcast、不替换稳定安装；冻结开发台与本机交接文件不纳入提交。视觉与交互仍由用户验收。

最新修订（2026-10-01）：PID **81293** 已启动。Token 活动采用蓝色四档热力图：每天/期间累计为 7 行×53 周列，每周为 53 个周汇总列，UTC 日期桶与既有口径一致；按实际卡片宽度精确计算方格与月份标签，整体无横向滚动。活动和成本图按用户新增要求显示深灰圆角 hover 浮层，日期/Token/估算值在对应图内披露并约束横向边界；不恢复任务卡片 tooltip。1 项宽度/聚合冒烟、最终构建/签名/启动通过（`.build/073-codex-heatmap-*`）；视觉由用户验收，源码未提交推送。

最新修订（2026-10-01）：PID **78697** 已启动。用量页取消固定 548 pt 上限与内部 ScrollView，按内容自然高度回报更新整岛尺寸；活动周期、语言、空态变化同步适配，0.5 pt 去重防布局回环。任务列表滚动规则保持。1 项内容高度/固定状态冒烟、构建、签名和启动通过（`.build/073-usage-fit-*`）；视觉待用户验收，未提交推送。

最新修订（2026-10-01）：PID **76772** 已启动。点击左上角额度进入 Bento 用量页，卡片分为额度、账户、三项 Token、30 日成本图、活动热力图，返回任务保持固定状态，收起后默认回任务。复用 CurrentCodexPresentation / EstimatedCostChartModel / TokenActivityGridModel，不重复估算口径；无数据与隐私态显示占位。图表点击在卡内披露数据，不加 hover tooltip；活动支持周/月/三月/半年。刷新调用现有额度刷新；重置入口仅弹出明确演示说明，不执行消费。页面超出可用高度内部滚动。1 项切换/固定/高度冒烟、最终构建、签名、启动通过（`.build/073-usage-bento-*`）。视觉待用户验收；本轮源码尚未提交推送。

最新修订（2026-10-01）：PID **70396** 已启动。运行状态采用 RGB 0.92 近白，具体操作采用 #C3C3C3；流光不再覆盖为统一 0.45 灰底，改为保留传入纯色底色并扫过白色高光。等待黄/完成绿保持，周期和带宽不变。构建/签名/启动通过（`.build/073-readable-operation-build.log`）；视觉待用户验收，源码未提交推送。

最新修订（2026-10-01）：PID **69459** 已启动。展示层将操作前缀 exec 替换为“执行中”/“Executing”，后面的操作详情保留；原始工具事件、命令详情与协议字段不改。构建/签名/启动通过（`.build/073-executing-label-build.log`）；尚未提交推送。

最新修订（2026-10-01）：PID **67768** 已启动。额度标题去掉“重置”/“Reset”，显示为“53% · 5天”（英文“53% · 5d”）；数据与倒计时规则不变。构建/签名/启动检查通过（`.build/073-short-reset-build.log`）；未提交推送。

最新修订（2026-10-01）：PID **65735** 已启动。取消灵动岛卡片、详情、状态、模型及按钮的原生 hover tooltip；说明保留为辅助功能提示，点击详情与悬停展开不变。包含上一轮移除底部三段式用量统计的修改。构建/签名/启动检查通过（`.build/073-no-hover-tooltip-build.log`）；本轮与上一轮源码未提交推送。

最新修订（2026-10-01）：PID **64779** 已启动。按用户要求去掉底部周额度三段统计，普通底栏仅保留会话数和状态统计；审批页同步移除额度行及 24 pt 高度预留。左上角百分比、重置倒计时和额度圆环保留。删除不再使用的分段组件与对应测试。构建、签名和启动检查通过（`.build/073-remove-quota-footer-build.log`）；本轮改动尚未提交推送。

## 2026-10-01 收工源码合并

用户授权提交当前 0.7.3 开发源码并合并 main，提交邮箱 `xuchen1995@gmail.com`。分支 `codex/island-0.7.3-source`；合入远端 0.5.1 Build 13 路径热修复和悬停可见度基础实现。旧单岛的悬停偏好/控制器保留；新多任务刘海沿用已确认的悬停展开与可点击交互，不恢复旧穿透悬停设置页。独立开发身份不变，不发布 Release、appcast 或覆盖稳定安装。

当前运行仍为此前构建 PID 49675，合并后的源码通过本轮构建/必要冒烟后提交，不自动重启。冻结开发台、其真实内容夹具、截图、归档包及本机诊断文件保留本机，未纳入本次源码提交；文档中的相关本机链接属于历史证据。下一步等待用户继续与视觉验收。

最新修订（2026-10-01）：PID **49675** 已启动。移除任务列表 ScrollViewReader 及 detailID/onAppear 自动 scrollTo：不再把卡片与长详情整体滚入视口，保持原生滚动位置，初始停在顶部并保留 12 pt 内边距。内容缩短时仍由系统限制合法滚动范围。构建、签名与启动检查通过（`.build/073-preserve-scroll-build.log`）；真实交互待用户验收。

最新修订（2026-10-01）：PID **47588** 已启动。恢复原生严格列表裁剪，取消向外扩展遮罩；列表内部上下各 12 pt，滚动可见性坐标同步更新。点击选中只发布一次模型更新，去掉旧选中布局的重复刷新。命令默认最多两行/120 字预览，输出默认折叠，查看原文恢复完整缓存内容。1 项冒烟与 128 任务基准通过，P95 1.58 ms、最大 56.67 ms；该基准不代表真实展开流畅度验收。最终构建与签名通过，日志 `.build/073-list-insets-*`，视觉与偶发卡顿待用户确认。本条覆盖下方放宽裁剪的方案。

最新修订（2026-10-01）：PID **44437** 已启动。用户发现青色实心辉光串到其他卡片；撤销上轮跨层辉光与坐标同步/观察器，恢复辉光归属卡片，列表裁剪仅向上下放宽 12 pt。完成描边切换不再重播 1.16 秒等待及 0.24 秒淡入，外围辉光保持 3 秒节奏。2 项相关冒烟与构建/签名通过（`.build/073-glow-ownership-*`），视觉待用户验收。本条覆盖下方独立辉光层方案。

最新修订（2026-10-01）：PID **38846** 已启动。固定后岛外点击不再收起，仅手动收起；完成卡片外围辉光脱离列表裁剪并跟随原生滚动，仍受整岛遮罩约束。左上角改为百分比 + 重置倒计时（同一额度窗口），圆环 14 pt / 2.8 pt 环线，复用额度风险色。2 项相关冒烟、arm64 Debug 构建与签名通过；日志 `.build/073-glow-clip-pin-*`。实际视觉与交互待用户验收。下方运行记录为历史。

最新修订（2026-10-01）：PID **34477** 已启动。「已完成」状态标签改为不透明绿色 RGB (0.36, 0.80, 0.55)，完成详情保持白色。构建及签名通过；日志 `.build/073-completed-label-build.log`，运行清单更新，视觉由用户验收。

最新修订（2026-10-01）：PID **31792** 已启动。按用户追加要求，完成描边保持常亮，仅外围辉光采用 3 秒周期并在暗段全灭，覆盖此前描边同步熄灭的记录。1 项针对性冒烟、构建及签名通过；日志 `.build/073-steady-outline-*`，清单已更新，视觉待用户验收。

更新日期：2026-10-01

## 当前开发入口：0.7.3 独立版本

最新运行 PID **26630**：完成态选中卡片的辉光与发光边缘改为同步 3 秒周期，暗段完全熄灭（每轮约 0.6 秒）；复用已有合成层节奏，无新增计时器。未选中淡绿描边/慢速球保持。1 项针对性冒烟、arm64 Debug 构建及签名通过，日志 `.build/073-completed-pulse-*`，清单已更新，视觉待用户验收。下方 PID 均为历史。

### 2026-10-01 最新运行修订：PID 23170

后续用户反馈覆盖下方五段/双行设计：普通底栏恢复单行 28 pt，左会话、中间周额度、右状态统计，统一 10 pt medium；移除「本地活动数据」等来源标签。三段额度条宽 146.4 pt（+20%）、厚 3 pt，59% 填充 `[1, 0.77, 0]`，沿用真实周窗口与额度风险色。审批页仍为独立确认底栏。

文字流光按用户录屏和本机 Codex `cadencedShimmer` 调整：示例文字一半约 85 pt 固定高光宽度（不是每条文案的一半），40%～60% 平顶，1 秒/48 步扫动，每 4 秒重复，首次 600 ms 延迟；用不透明 RGB 灰阶表现。此前窄亮点方案已替换。2 项针对性冒烟、最终构建和签名通过；日志 `.build/073-reference-footer-*`，清单已更新，实际效果由用户验收。

### 2026-10-01 最新运行修订：PID 17305

0.7.3 / Build 1 / 内部 49 最新包已启动，覆盖下方旧 PID。完成卡片保留慢速球、未选中淡绿边框、选中复用单岛辉光；运行状态标签和详情共用更窄、更亮的文字流光。进度解析改为任务持有，共用原单岛算法，选择/重建恢复原位置，新轮才归零。只有固定按钮触发固定，卡片/筛选/紧凑态点击不会自动固定。

展开页最下方居中显示真实周额度五段条（上方保留会话统计）。每段 20%，59% 的填充为 `[1, 1, 0.95, 0, 0]`；≥50% 绿、20%～49% 黄、<20% 红。只取 10080 分钟窗口，缺值显示「—」，不使用短周期主额度代替。审批页同样保留底栏，最大正文高度扣除该 24 pt。

本轮分步完成 4 项针对性冒烟与 1 项 128 任务展示基准（P95 1.516 ms，最大 7.696 ms），不是视觉验收。最终 arm64 Debug 构建、身份和签名验证通过。日志 `.build/073-completion-card-*`、`.build/073-card-switch-*`、`.build/073-weekly-quota-*`，运行清单已更新。固定 Demo、稳定安装不变。

2026-10-01 完成状态与进度修复已构建并启动，PID **5058**，版本身份保持不变。`IslandLiveStore` 不再将 Socket 接收时间与 rollout 发生时间做全局先后比较，按来源校验，避免当前轮明确完成被误丢；终态清理活动工具，旧轮事件仍不能覆盖新轮。无结构化计划传 `nil`，恢复单岛已有的 4 秒识别 / 无计划 50% 上限估算，而非固定 1%。两项针对性冒烟、arm64 Debug 构建和签名核验通过；原开发台冻结包未改。日志 `.build/073-completion-progress-{smoke,build}.log`，运行清单已更新，实际效果待用户验收。

用户于 2026-09-30 授权按照交互与显示规则实施 **0.7.3**，采用推荐默认值。开发工作区为 `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget`，detached HEAD 基于 `71932fd` 并复制原有未提交开发输入；没有提交。

身份 **0.7.3 / 显示 Build 1 / 内部 49**，Bundle `com.quotaview.development073`；包在 `dist/development-0.7.3/QuotaView 0.7.3 Development.app`，只作本机开发，未发布或替换稳定安装。

[规则](docs/design/quotaview-island-production-interaction-review-2026-09-30.md)为 Accepted / Verifying；[分类交付记录](docs/design/quotaview-0.7.3-development-delivery-2026-10-01.md)记录当前覆盖及边界。真实请求处于观察模式，提供“在 Codex 处理”，没有真实回传。8 项必要冒烟和 1 项基准通过，实际效果等待用户验收。构建、签名与运行证据见 `dist/development-0.7.3/development-manifest.json`。

原工作区源码和固定开发台 **2026-09-30-3s-sync-noise65** 保留。下方为历史记录；不按历史“下一步”自动恢复任务。公开版仍由 [版本历史](VERSION_HISTORY.md#当前最新版本) 定位。

## 历史基线：开发台固定与生产规则审核稿

用户要求将开发台固定在 **2026-09-30-3s-sync-noise65**，暂不继续 UI 修改。[持久快照与恢复说明](Prototypes/MultitaskIslandConsole/Frozen/2026-09-30-3s-sync-noise65/README.md)保存现有应用包、129 项构建输入、SHA256 与上一轮证据；运行主程序、源码清单和归档输入核验一致。本次没有重建或重启，冻结时仍为 PID 35278；身份保持 0.5.2 / 显示 Build 7 / 内部 48。冻结不等于生产/视觉验收。

[生产交互与显示规则审核稿](docs/design/quotaview-island-production-interaction-review-2026-09-30.md)已整理，Spec 为 QV-PRODUCT-ACTIVITY-ISLAND-PRODUCTION-003，Review / Discovery。覆盖显示、十类待确认、通信生命周期、异常、性能与 14 项审核决策。只读核对源码及官方协议，不做真实连接/回传。下一步仅等待用户审核；本文下方历史“下一步”不恢复执行。新的明确修改要求应从固定版本副本继续，不覆盖快照。

新会话接手当前多任务开发台，先读[专项交接（2026-09-27）](HANDOFF-NEXT-SESSION-2026-09-27.md)，含最新刘海轮廓、代码入口、授权边界及启动验证。

当前公开版本：[版本历史](VERSION_HISTORY.md#当前最新版本)。当前规格：[SDD 注册表](docs/specs/README.md)。
更早交接按需查阅[历史快照](docs/archive/handoff-2026-09-12.md)，不从历史“下一步”恢复任务。

## 2026-09-30 待确认辉光与量子噪点同步

用户追加指定 3 秒周期，并要求噪点不要全灭，覆盖上一轮 5 秒。待确认卡片与整岛辉光共用 ConsoleConfirmationPulse 的时间原点、关键帧与 3 秒周期，明暗节奏一致：外围辉光最低为 0，每轮约 0.6 秒全灭；噪点保留原等待态 65% 的低亮下限。卡片重新挂载、离屏返回或暂停恢复均接入同一相位。

开发台组装副本移除量子噪点等待态原有的独立正弦明暗，只给 Metal 效果层添加共用节奏的合成动画；粒子连续运动时钟、进度范围、颜色映射与其他状态保留，文字和黑底不参与明灭。不增加计时器或逐帧 SwiftUI 更新，仅适配组装副本的 CodexActivityStateSmoke.swift。

2 项必要冒烟通过，覆盖原生 Metal 渲染器、3 秒相同相位、两种明暗下限、离屏返回、刷新不重启、暂停/减少动态与清理。源码清单一致，69 项生产文件哈希未变，实际观感由用户验收。

新版 PID 35278，关闭旧实例 [33255]；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.a8tklx/Multitask Island Console.app`。最终证据位于开发台 `.build/confirmation-noise-floor-20260930/`，此前同步阶段证据保留在 `.build/confirmation-pulse-sync-20260930/`。

## 2026-09-30 辉光慢速明灭

按最新反馈，仅调整整岛待确认辉光：周期 5 秒，亮度从 0 渐亮到 1 再降到 0，每轮完全熄灭约 1 秒；保留原黄色与辉光扩散范围，两层同相播放。使用同一 CAAnimationGroup 同步透明度与半径，不增加计时器；显示数据刷新与展开/收起不重启周期。暂停/减少动态仍为静态辉光，隐藏与请求清理沿用现有停止逻辑。

2 项必要冒烟通过，覆盖全灭关键帧、周期、两层同步、刷新不重启及停止/减少动态。首次断言读取整数关键帧时误转为 Double 数组，已修正为 NSNumber 读取并复验；日志保留。生产 69 项文件哈希不变，实际节奏由用户验收。

新版 PID 29151，关闭旧实例 [25964]；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.6rlEOE/Multitask Island Console.app`，源码清单一致。证据位于开发台 `.build/confirmation-glow-breath-20260930/`。

## 2026-09-30 待确认整岛辉光

待确认提示提升到整个刘海外缘：复用原单岛 ActivityIslandCompletionGlowView 的黄色、显现与呼吸动画，仅在开发台组装副本增加可选刘海轮廓。辉光位于黑色外壳下方、内容遮罩外，跟随收起/展开路径过渡；任务卡片、文字和按钮保持原布局。

任何任务处于待确认时显示整岛辉光，返回列表或收起仍保留；全部待确认任务离开该状态后清除。暂停/减少动态显示静态辉光，隐藏、移出窗口与退出清理动画。窗口两侧和屏幕可用底边统一预留原单岛 30 pt 效果空间；原生窗口仍固定，不增加逐帧布局或新计时器。

4 项必要冒烟通过，覆盖整岛轮廓、明确图层顺序、状态清理、暂停/减少动态、固定窗口、透明区域穿透及确认面板自适应。首次冒烟直接检查离屏窗口的 backing layer 插入顺序失败；改为显式 zPosition 并核验外壳与辉光层级，保留初次日志。未做视觉或真实交互验收。

新版运行 PID 25964，关闭旧实例 [16470]；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.Pvtz6p/Multitask Island Console.app`。源码清单一致，69 项生产文件哈希未变；证据在开发台 `.build/confirmation-shell-glow-20260930/`。仍为纯 Demo，实际效果由用户验收。

## 2026-09-30 待确认顶部复用选中任务卡片

待确认页删除独立的图标、任务标题与“请求确认”副标题，直接复用列表的 ConsoleTaskCard 展示组件：60 pt 行高、选中描边与量子噪点，任务标题、待确认状态/操作、模型/推理强度、Codex 来源、运行时长和会话 Token 均来自同一任务。确认页中的卡片只展示信息，返回仍使用顶栏入口；各类确认内容及底部操作保持原有布局。

移除旧标题高度测量，以共用卡片高度参与内容自适应。卡片仍随请求正文连续滚动，复用现有可见性观察，离屏后停止文字与特效播放，不增加滚动吸附、逐帧状态或窗口 resize。

4 项必要冒烟通过，覆盖十类场景中英文本高度、自适应高度与草稿、单一选中卡片宿主及离屏停止。1 项离屏表单滚动基准（120 次）同步布局 P95 1.28 ms，主循环 P95 12.28 ms、最大 19.53 ms；这些结果不代表视觉/实际交互验收。源码清单一致，69 项生产文件哈希未变。仍为独立纯 Demo，无真实回传，实际效果由用户验收。

运行 PID 16470，关闭旧实例 [128]；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.Z1Ot7T/Multitask Island Console.app`。证据位于开发台 `.build/approval-task-card-20260930/`。

## 2026-09-30 待确认面板按内容与屏幕自适应高度

用户反馈第三方工具选项仍被截在滚动区域下沿。根因是正文固定上限 320 pt，且原生窗口只预留列表/详情固定画布。本轮移除该固定正文上限：待确认面板优先按实际内容展开，最大高度来自当前屏幕顶部到可用底边的空间，避开底部 Dock 并保留 24 pt 余量；扣除顶栏和固定操作底栏后才限制正文，超长内容在内部滚动。普通短请求不被撑高，既有按钮配色、1/2/3 个按钮布局与其他任务详情保持。

原生画布按屏幕可用高度预留，不随请求内容或展开/收起逐帧 resize；只有屏幕几何变化才调整。审批尺寸缓存纳入可用高度，屏幕缩小和恢复都会重新计算；虚拟刘海同样使用真实可用底边。

4 项必要冒烟与 1 项离屏表单滚动基准通过：十类场景在 900 pt 高测试屏幕上完整展开，截图对应第三方选项超过旧 320 pt 后仍完整显示；小屏/Dock 边界回退到内部滚动，屏幕恢复后缓存正确更新；长正文、固定原生窗口和透明区域穿透也通过。基准在 600 pt 测试屏幕触发滚动，同步布局 P95 0.90 ms，主循环最大 12.06 ms，不代表视觉验收。

当前运行 PID 128，关闭旧实例 91692；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.s4JNTj/Multitask Island Console.app`。源码清单一致，69 项生产文件哈希未变；证据位于开发台 `.build/approval-adaptive-height-20260930/`。仍为纯 Demo，实际效果由用户验收。

## 2026-09-30 操作按钮铺满底栏

按用户最新反馈，取消、拒绝、通过统一为实体按钮：取消沿用深灰底，拒绝红底白字，通过保留白底黑字。底栏共用 `ConsoleApprovalActionLayout`，只计算实际存在的按钮：单个占满，两个等宽，三个从左至右取消/拒绝/通过按 3:3:4 分配；同为 42 pt 高、8 pt 间距、10 pt 圆角，没有中间 Spacer 或不存在操作的占位。这覆盖上一轮 248 pt 固定主按钮及文字取消样式。无额外批准/取消操作被伪造，草稿和模拟通信行为未变。

十类场景必要冒烟通过、构建及签名/源码清单核验通过。之前几何冒烟曾出现屏幕原点变化（宽高相同），未经源码修改重试通过；记录原始失败，未扩大回归或重复基准。当前 PID 91692，关闭旧实例 76242，运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.rPRSFF/Multitask Island Console.app`。69 项生产文件哈希未变，仍为纯 Demo；证据在开发台 `.build/approval-buttons-20260930/`，实际效果由用户验收。

## 2026-09-30 待确认 UI 统一与批准范围优化

用户已确认十类场景可见，本轮按现有刘海风格全面优化：保持 680 pt 黑色外壳、13/12/11/10 pt 字级和不透明白灰文字；来源任务与正文用细线分区，控件采用统一深色表面、10 pt 圆角及选中/悬停/输入焦点反馈。

问题增加编号、整行选择、补充输入与回答进度；权限按访问项及期限分组；表单采用标签/控件双列。命令、目录与差异完整展示，文件名/路径/增删分层，第三方参数以键值对展示，外部授权采用两步流程，原生验证保留独立入口。固定底栏主按钮在右侧（248×42 pt），拒绝与取消在左侧。

针对用户指出的「更多选择」问题，已删除通用菜单。命令/文件的批准范围、网络的允许/阻止域名规则直接列在正文；选择只更新请求草稿，主按钮才提交原始 decision。外部授权/表单/验证直接取消，不生成额外范围菜单。模拟网络阻止规则不再错误恢复工作中。仍为纯 Demo，无真实连接、回传或打开外部页面。

9 项必要冒烟通过，覆盖十类最终面板数据、中文/English 真实正文高度、草稿及响应生命周期、范围选择和阻止规则。1 项离屏表单滚动基准（120 次）同步布局 P95 0.61 ms，主循环 P95 11.13 ms、最大 11.61 ms；不是视觉或真实输入验收。源码清单一致，69 项生产文件哈希未变，版本仍为 0.5.2 / 显示 Build 7 / 内部 48。实际效果由用户验收。

当前运行 PID 76242，已关闭旧实例 54580；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.SaXAL2/Multitask Island Console.app`。证据位于开发台 `.build/approval-polish-20260930/`。

## 2026-09-30 按 Codex 请求结构区分待确认 UI

2026-09-30 请求覆盖修复（上一运行版）：此前入口调整没有修复根因，`MultitaskState.update` 在操作文案改变后重新生成通用确认，覆盖了场景刚安装的 `protocolRequest`，导致十类 UI 都退回「拒绝／允许一次」。现保留显式安装的新请求；仅在未提供新请求时生成默认确认，旧请求仍随手动操作变化或离开待确认状态失效。补充最终面板数据断言后先复现失败，再通过 7 项必要冒烟，覆盖十类场景的类型、参数、问题选项、表单字段和上下文，以及请求替换／清理。此前冒烟只覆盖夹具和尺寸，不能证明类型数据到达面板。已重新构建启动 PID 54580，关闭旧实例 [46479]；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.nJpwOt/Multitask Island Console.app`，源码清单一致，69 项生产文件哈希未变。证据位于开发台 `.build/approval-payload-fix-20260930/`。仍为纯 Demo，无真实回传；实际界面待用户验收。

以下为前两次构建记录，入口修正当时仍存在上述覆盖问题：

2026-09-30 入口修正：用户反馈新版看不出变化。核对原运行 PID 39331 确为新包，但启动仍显示旧日常预设，下拉框改值也未立即载入。现启动即展开命令批准，类型切换即时载入并展开；「只剩待确认」进入当前类型，按钮改为「重载当前场景」。1 项受影响冒烟通过，未重复基准或视觉验收。新版 PID 46479，已关闭旧实例 [39331]；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.s8Hdch/Multitask Island Console.app`，源码清单一致，生产文件哈希未变。证据 `.build/typed-approval-ui-20260930/entry-delivery.json` 位于开发台目录。

新版独立 DEBUG 开发台已构建并启动，PID 39331，启动器关闭的旧实例为 [6453]；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.zFxhVX/Multitask Island Console.app`。运行包源码清单与当前源码一致，归档校验和签名验证通过，69 项生产文件哈希未变，版本身份仍为 0.5.2 Build 7 / 内部 48。实际 UI 待用户验收。

用户反馈上一版各场景过于相同；旧的「标题＋通用内容框」没有形成有效适配。本轮保留刘海外壳与公共操作条，正文改由 `Editable/ConsoleApprovalTypedContent.swift` 按真实请求字段选择独立布局。Demo 任务标题与请求说明分开，不再重复类型名称。

| 场景 | 当前正文与操作 |
|---|---|
| 命令批准 | 命令终端块、工作目录、请求原因；允许执行及批准范围 |
| 终端输入 | 已有终端标识、转义显示的待发送输入；发送输入 |
| 文件修改 | 每个文件的路径与逐行差异；增删以克制底色和符号区分，允许修改 |
| 网络访问 | 域名目标面板及协议；允许访问，更多选择中保留网络规则 |
| 权限范围 | 读取、写入与网络分项授权块，勾选及本轮/会话期限 |
| 第三方操作 | MCP 工具名称、参数与独立并排选择；不凭任务名推断，依据 `mcpToolCall` 上下文识别 |
| 问题选择 | 编号问题、原始选项与补充输入；提交回答 |
| 工具表单 | 标签/控件双列，类型、必填和约束；提交参数 |
| 外部授权 | 服务商目标与打开/返回两步流程；打开授权页面后变为继续 |
| 原生验证 | 独立锁盾面板及跳回入口；不显示伪造的同意验证 |

仍为纯 Demo，不访问真实服务或回传批准；授权和跳回也模拟。依据本机 Codex CLI 0.159.0 生成的接口与 item 上下文字段，不声称这些 Demo 是正在运行的真实请求。卡片布局、字体、纯色文字、连续滚动、无吸附和原有球/量子噪点保持。

6 项必要本地冒烟及 1 项滚动基准通过；滚动/布局 P95 0.57 ms，主线程心跳最大 42.40 ms，有 1 次超过 33.33 ms。离屏基准不代替实际流畅度或视觉验收。源码、构建与交付证据位于开发台 `.build/typed-approval-ui-20260930/`。新界面实际效果待用户验收。以下为上一版及历史记录。

## 2026-09-30 十类待确认 UI Demo

独立 DEBUG 开发台已于本轮继续后重新打包并启动，PID 6453；启动器未发现需关闭的旧实例。运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.lC49jq/Multitask Island Console.app`，包内源码清单与当前源码一致，归档校验与签名验证通过，69 项生产文件哈希未变。交付证据为开发台 `.build/approval-types-20260930/delivery.json`。实际 UI 和操作效果仍待用户验收。

按用户最新要求，本轮只提供界面 Demo，优先实际显示效果，不接入真实审批或回传。开发台新增「待确认类型 / 载入待确认场景」，覆盖命令、终端输入、文件修改、网络访问、权限范围、第三方操作、问题选择、工具表单、外部授权及原生验证。载入后直接展开独立刘海面板；返回保留未提交内容，替换请求释放草稿。既有卡片、原生连续滚动、无吸附与动效保持。

命令等场景保留提供的选项，并用「更多选择」容纳会话允许和规则记忆；权限逐项选择及本轮/会话期限；问答显示原选项、其他输入和秘密字段；表单按字符串、数字、布尔及枚举显示控件，显示名称与枚举值分开，未满足必要条件时不能模拟提交。提交延迟、失败重试、拒绝/取消均模拟；授权页面和跳回 Codex 也模拟，不访问服务。

本轮曾加入的真实连接及回传代码已撤销，69 项生产 Sources/Configs/Support 文件哈希与本轮开始时一致，版本身份仍为 0.5.2 Build 7 / 内部 48。已有 5 项本地 UI/协议冒烟及 1 项滚动基准通过，本次继续不重复检查。布局 P95 0.55 ms，心跳 P95 18.22 ms、最大 49.70 ms、有 1 次超过 33.33 ms；离屏基准不能代替真实流畅度或视觉验收。证据保存在开发台 `.build/approval-types-20260930/`。

完整交接见[专项交接](HANDOFF-NEXT-SESSION-2026-09-27.md)。以下为上一运行版与更早历史，本节覆盖固定两按钮及此前暂停记录。

## 2026-09-30 待确认独立刘海面板、取消吸附；暂停 UI 迭代

待确认已移出任务卡片：选中待确认任务时，展开刘海切换为独立授权面板，顶栏显示橙黄色「待确认」和返回入口，正文显示来源任务、完整问题与影响框；底部「拒绝 / 允许一次」并排等宽、42 pt 高，允许白底黑字，拒绝暗底。返回/收起保留请求，提交中禁用按钮，失败可重试，成功或拒绝后返回列表；确认仍为隔离模拟。

按用户要求彻底删除卡片吸附的停点、阈值、滚轮监听、手势状态机、等待定时与动画，保留原生连续滚动、惯性和独立轨道。`ConsoleTaskListLayout` 只计算可见项；绑定仅观察 clip 边界和 document 尺寸，卸载恢复原通知标志。进展/完成/失败详情仍紧随对应卡片，通过同一外层列表按自然高度浏览。用户随后提出的「卡片固定顶部、详情限定剩余高度并内部滚动」未实施即被取消，无需回退源码。

最终 12 项必要冒烟与 1 项 9 任务/120 次滚动基准通过；同步滚动/布局 P95 0.72 ms，主线程心跳 P95 17.91 ms、最大 29.60 ms，本次采样无超过 33.33 ms。这是离屏主线程采样，不代表输入延迟、GPU 帧率或视觉验收。结束时只更新交接，未追加测试、构建或重启。证据：`Prototypes/MultitaskIslandConsole/.build/notch-approval-20260930/`。

当前独立 DEBUG 开发台 PID 88655，旧实例 [54728] 已关闭；运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.NMo84f/Multitask Island Console.app`。运行包源码清单与公开原文夹具一致，69 项生产 Sources/Configs/Support 文件哈希未变，身份仍为 0.5.2 Build 7 / 内部 48。真实内容订阅和真实审批未接入。

用户表示「目前版本暂时看起来不错，先不做下一步的修改了」：保留当前效果，暂停后续 UI 迭代，等待新的明确要求；不扩大为完整功能验收或迁回生产授权。本节覆盖以下历史记录中的卡片内确认与滚动吸附方案。

## 2026-09-30 淡化未选中卡片层级

按用户截图反馈，未选中卡片底色从 0.065 / 0.095（普通 / 悬停）调整为 0.045 / 0.07，1 pt 边线从 0.085 / 0.14 调整为 0.055 / 0.095；保留常驻底色与边界。选中描边 0.22、量子噪点及布局、文字保持原值。仅修改两个装饰颜色表达式。1 项完整刘海列表/轨道冒烟及构建、归档签名通过；未重复基准或视觉自动化。新版独立开发台 PID 54728，已精确关闭旧实例 [31674]，运行包 `/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.1cCqxB/Multitask Island Console.app`；源码清单一致，69 项生产文件哈希未变，仍为 0.5.2 Build 7。实际层级效果待用户验收。证据：`Prototypes/MultitaskIslandConsole/.build/card-softening-20260930/`。

## 2026-09-30 按 Vibe Island 官网状态重组详情 UI

已观察官网「总览 / 批准 / 询问 / 跳回」四种预览，并保存截图与适配依据。详情从平铺日志改为状态面板：思考/执行默认突出最近公开消息和最近工具，较早记录折叠，运行输出通过「查看原文」披露；待确认突出完整问题与独立影响框，右侧 136×42 pt 白色主按钮和暗色拒绝按钮；完成直接显示可用输出，失败优先展示失败工具及原始错误。未观察到的失败样式按本地状态语义适配，不声称来自官网。

公开消息为 13 pt、命令/输出 11 pt，辅助标签 10–12 pt。表面使用黑灰层级，文字保持不透明 RGB，橙黄色用于待确认、红色用于失败。原文参考夹具不改写、不翻译，历史展开可找回全部保留事件。原生 680 pt 外壳、60 pt 会话行、8 pt 行距、Ripple Glow 与选中量子噪点保持；详情仍紧随对应任务并共用同一个滚动列表。历史展开计入有界高度缓存、轨道与吸附，不引入嵌套滚动、逐帧测量或窗口 resize。

7 项必要冒烟与 1 项 9 任务/120 次原生滚动基准通过，覆盖原文完整披露、按状态呈现、历史展开/收起与缓存、实际列表高度、确认失败重试/拒绝及旧回调取消。默认参考详情由此前 580 pt 收敛至 314 pt；同步滚动/布局 P95 0.67 ms，主线程心跳 P95 20.00 ms、最大 44.47 ms、1 次超过 33.33 ms。此为离屏主线程采样，不是输入延迟、GPU 帧率或视觉验收。证据：`Prototypes/MultitaskIslandConsole/.build/vibe-state-redesign-20260930/`。

新版独立 DEBUG 开发台已启动（PID 31674），旧实例 [11288] 已按 Bundle ID 与精确路径核对关闭。运行包：`/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.at6pKz/Multitask Island Console.app`；包内源码清单及原文资源与当前源码一致，69 项生产 Sources/Configs/Support 文件哈希未变化，版本身份保持 0.5.2 Build 7。实际视觉、交互待用户验收；公开内容仍为历史参考，确认仍是隔离模拟。

[官网预览与适配记录](Prototypes/MultitaskIslandConsole/References/vibe-web-20260930/README.md)。以下为历史实现记录，旧按钮配色与默认平铺八条记录的布局由本节替代。

## 2026-09-30 详情 UI 与 Codex 公开原文参考

用户反馈上一版三条模拟摘要脱离实际，本轮移除固定三步故事及伪造时间点。日常场景改为本会话经 Codex `read_thread` 返回的公开 `agentMessage`、`commandExecution`、`fileChange` 原文参考，保留来源事件 ID、命令、可用输出、文件差异、状态与退出码。界面分组显示进度消息和工具卡片，长输出可展开；只展示来源提供的原文，来源截断明确提示，切换语言不翻译或改写。最多保留八条事件，其他预设只记录实际输入的模拟状态事件，不补写推理故事。公开轨迹仍是历史参考夹具，并非实时订阅；详情标明「Codex 原文参考」，模拟事件单独标注。不得显示或补造内部推理。直接读取 Codex 窗口被工具权限限制，内容依据来自会话读取接口，未声称视觉一致。

待确认采用左侧完整问题与影响、右侧操作栏：按钮 136×42 pt、13 pt Semibold，允许一次使用提亮橙黄色实底与黑字，拒绝使用中性暗底。提交中禁用两个按钮，失败保留问题并允许重试，拒绝仍为取消；按钮仅处理模拟请求。窄宽度时操作栏转至正文右下方，正常 680 pt 岛体保持右侧布局。

详情继续紧随对应卡片，公开消息为 12 pt、命令/输出为 11 pt 等宽文字，全部文字使用不透明纯色。原文展开、换行高度、吸附与轨道共用同一测量结果；按内容/语言/展开项/宽度缓存，缓存最多两项，时长刷新与滚动复用不变内容的高度。固定窗口与额外视口最多 200 pt、独立轨道及 8 pt 间距保持既有契约，没有新增逐帧布局或嵌套滚动容器。

6 项相关冒烟与 1 项 9 任务/120 次原生滚动基准通过；缓存修订后复验受影响的 2 项几何冒烟与该基准。当前参考详情自然高度 580 pt，同步滚动/布局 P95 0.85 ms；主线程心跳 P95 27.40 ms、最大 48.68 ms、4 次超过 33.33 ms。此为离屏主线程采样，不是输入延迟、GPU 帧率或无卡顿保证。证据位于 `Prototypes/MultitaskIslandConsole/.build/detail-codex-ui-20260930/`。实际视觉、交互由用户验收；真实内容订阅和真实审批未接入。

新版独立 DEBUG 开发台已启动（PID 11288），旧实例 [93610] 已按 Bundle ID 与精确路径核对关闭。运行包：`/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.w1uxsv/Multitask Island Console.app`；包内源码清单与原文参考资源均与当前源码一致，69 项生产 Sources/Configs/Support 文件哈希未变化，版本身份保持 0.5.2 Build 7。实际显示与交互等待用户验收。

[原文来源与展示边界](Prototypes/MultitaskIslandConsole/References/codex-public-detail-content-2026-09-30.md)。以下为历史实现记录，固定三条摘要已被本轮替换。

## 2026-09-30 详情改为进展轨迹与模拟确认

按用户确认的方案，详情不再重复标题、状态、模型、时长与 Token，改为最近三条公开进展/执行记录（内部保留五条）；按事件更新，时长和元信息刷新不制造记录。待确认时优先显示完整问题、操作影响与「允许一次 / 拒绝」。仅接隔离开发台的模拟请求，标明「模拟」，不连接真实 Codex 审批或内部推理。点击后保持待确认并禁用按钮，收到模拟响应后才转为运行/取消；失败保留原问题可重试。控制窗口有「模拟下一次确认提交失败」开关，拒绝不记为成功，也不持续提醒。

长正文自然换行，详情按实际宽度测量高度，额外视口最多 200 pt，使用同一外层任务列表完整浏览；吸附、可见性与正文共用实际高度。局部冒烟发现 LazyVStack 的离屏行高估算不适合大详情，已改为明确行槽与有界近邻缓存；仅视口播放，AI 球避免状态未变化时重复重绘。固定 NSPanel、既有卡片、8 pt 轨道间距、文字纯色与动效契约保留。

10 项相关冒烟及 1 项含详情的 9 任务/120 次滚动基准通过，覆盖事件去重、确认失败/重试/拒绝、旧请求/退出取消、长正文、回调接线、实际轨道、筛选与固定窗口。同步滚动/布局 P95 0.74 ms，心跳 P95 22.72 ms、最大 42.09 ms、1 次超过 33.33 ms；这是离屏原生主线程基准，不是输入延迟或 GPU 帧率，不能据此保证无卡顿。证据位于 `Prototypes/MultitaskIslandConsole/.build/task-detail-20260930/`。真实内容接入与实际交互、视觉仍待后续实施/用户验收。

新版独立 DEBUG 开发台已启动（PID 93610），旧实例 [50449] 已按 Bundle ID 与精确路径核对关闭。运行包：`/private/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-multitask-console-run.X1kh2a/Multitask Island Console.app`；包内源码清单与当前源码一致，69 项生产 Sources/Configs/Support 文件哈希未变化，版本身份保持 0.5.2 Build 7。实际显示与交互等待用户验收。

## 2026-09-29 滚动实现审查、清理与等距布局

用户已确认滚动条可见，要求先检查实现质量再调整间距。本轮先删除 AppKit 强制隐藏内置滚动条的重复控制，统一采用 SwiftUI `.never`；将重叠手势标志收敛为单一状态机，补齐原绑定对象恢复、监听去重与卸载取消。清理阶段 6 项冒烟通过后，再将卡片—滑块—岛体边缘统一为 8 pt，轨道上下对齐卡片区域，尺寸由公共指标推导。详情见[审查记录](Prototypes/MultitaskIslandConsole/References/scroll-implementation-audit-2026-09-29.md)。

最终 6 项冒烟、1 项基准通过：9 任务滚动/布局 P95 5.22 ms，心跳 P95 14.10 ms（离屏基准）；生产源码哈希未变化。新版已启动（PID 50449），旧实例精确核对后关闭；证据 `Prototypes/MultitaskIslandConsole/.build/scroll-audit-20260929/`。新间距和真实手感待用户验收。

## 2026-09-29 滚动条避让刘海遮罩，改用独立轨道

用户再次反馈滚动条不可见，前两轮实际显示未通过；局部绘制/组件属性检查不足以证明完整岛体内可见。完整容器冒烟定位到遮罩几何：展开态凹角让主体左右各内缩 16 pt，680 pt 宿主的实际右边界是 x=664；原生滚动条位于 x=667…680，整条在遮罩外。此前将自绘路径作为根因的判断不完整。

现停用滚动容器内置滚动条，改为列表外层的独立原生轨道，通过 Core Animation 图层直接显示深灰轨道和亮灰滑块。轨道 14 pt 命中宽、末端距宿主右边 18 pt，范围 x=648…662，全部在遮罩内；滑块宽 6 pt、轨道宽 4 pt。超过四个任务时卡片右内距只增加 4 pt，为轨道留位；四项及以下不显示。保留原生拖动/辅助功能、惯性结束后吸附及可见项按行边界更新，不发布逐帧 SwiftUI 滚动偏移。

构建、归档签名和最终 4 项滚动冒烟通过，覆盖实际刘海容器启动后 4→11 项、虚拟刘海、祖先可见性、轨道完整落在遮罩内、双向滚动关联、详情尺寸、展开/收起和筛选。修复前该遮罩检查失败，移入后通过。1 项 9 任务/120 次滚动基准通过：滚动/布局 P95 5.63 ms，主线程心跳 P95 15.42 ms（离屏基准，不是 GPU 帧率或真实输入延迟）。新版已启动（PID 41114），旧实例按精确路径关闭；运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-independent-rail-wf7n7129/Multitask Island Console.app`，证据：`Prototypes/MultitaskIslandConsole/.build/independent-rail-20260929/`。最终视觉和交互仍由用户验收。

## 2026-09-29 滚动条绘制与惯性卡顿修正

用户反馈上一版滚动条依旧不可见、滚动卡顿，上一版实际体验未通过。已定位 `NSScroller` 默认 `wantsUpdateLayer=true`，绕过自定义 `draw`；现显式使用自绘路径，保留常驻 6 pt 灰色滑块和 4 pt 轨道。冒烟增加离屏绘制输出检查，不能只凭 `hasVerticalScroller=true` 认定可见。

移除每行 `GeometryReader`/Preference 的逐帧位置测量，改为依据原生 clip 偏移和既有固定行高计算可见项，只在任务进入/离开视口时更新动效可见性。滚轮事件仅旁路读取、不拦截，显式区分手指滚动与惯性阶段；惯性结束并静止 200 ms 后才按原 35% 阈值吸附。新手势会取消旧吸附/惯性记录，详情揭示和筛选不会抢滚动位置。

构建、归档签名、7 项相关冒烟与 1 项滚动基准通过，最终手势取消补充后复验 4 项滚动冒烟。相同 9 任务、120 次原生滚动/布局采样，P95 从 12.11 ms 降到 4.69 ms；主线程心跳 P95 从 22.41 ms 降到 14.06 ms。这是离屏主线程基准，不代表输入延迟、GPU 帧率或视觉验收。新版已启动（PID 29151），旧实例按精确路径核对后关闭；运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-scroll-fix-y982vkgf/Multitask Island Console.app`，证据：`Prototypes/MultitaskIslandConsole/.build/scroll-fix-20260929/`。实际可视度、触控板/滚轮手感待用户验收。

## 2026-09-29 多任务滚动条与底部吸附

超过四个任务时，展开列表改用常驻原生滚动条：6 pt 不透明灰色滑块、4 pt 暗灰轨道，保留拖动和系统辅助功能。滚动条占用独立边栏，并补偿列表右内距，卡片宽度和位置不变；四个及以下不占滚动条空间。

用户滚动结束后，以移动方向的 35% 区间为阈值吸附到相邻卡片下沿，底部保留既有 8 pt 间距；160 ms 原生缓动，减少动态时直接定位。吸附位置计入内联详情，顶部和最后一张卡片均有边界停点。仅响应原生用户滚动事件，程序化揭示详情不触发吸附；新手势、筛选、收起和卸载取消待执行吸附，不使用逐帧 SwiftUI 状态或窗口 resize。

构建、归档签名与 6 项相关冒烟通过，覆盖阈值/详情几何、原生滚动事件与卸载恢复、实际 SwiftUI 列表挂载和筛选。新版已启动（PID 22599），旧实例按精确路径核对后关闭；运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-scroll-snap-y6lejddz/Multitask Island Console.app`，证据：`Prototypes/MultitaskIslandConsole/.build/scroll-snap-20260929/`。滚动手感、可视度和实际交互由用户验收。

## 2026-09-29 纯色文字与无刘海模式间距

按用户要求，所有自定义文字灰度采用不透明 RGB：次要状态 `#B3B3B3`、元信息/统计 `#7D7D7D`、运行详情 `#8C8C8C`，alpha 均为 1；控制窗口辅助文案同步使用纯色灰。运行流光改为不透明灰阶颜色渐变，在文字形状遮罩内移动，活动时隐藏重复的底层文字；不再叠半透明白色提亮。保留文字抗锯齿覆盖、滚动及整岛展开/收起过渡，背景、边框与图标透明度不属于文字灰度。

用户截图指出无物理刘海时滚动内容紧贴会话统计。收起态在左侧文字区与右侧统计区间增加固定 16 pt 空隙，左侧内容独立裁剪，整体仍 340×30 pt。硬件/虚拟刘海继续用中央避让区；启动默认改为真实屏幕几何（虚拟刘海关闭），保留手动开关供比较。

构建、归档签名与 7 项相关冒烟通过，含流光颜色 alpha、滚动/停止生命周期和刘海几何。新版已启动（PID 17872），旧实例按精确路径核对清理；运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-solid-text-gap-wap126m7/Multitask Island Console.app`，证据：`Prototypes/MultitaskIslandConsole/.build/solid-text-gap-20260929/`。实际文字观感和间距由用户验收。

## 2026-09-29 虚拟刘海适配原岛体尺寸

用户认为上一版虚拟刘海过大，现恢复收起态原尺寸 340×30 pt，不再由模拟摄像头撑大岛体。中央模拟遮挡缩为 96×30 pt，含左右各 8 pt 安全距离的避让宽为 112 pt；扣除外距后两侧内容各 94 pt。展开宽仍 680 pt，顶栏左右内容各 246 pt。控制开关改名「虚拟硬件刘海 · 适配当前岛体」；此为展示用缩小模拟，不冒充真实硬件尺寸，真实屏幕几何路径保持原行为。

构建、归档签名及 5 项相关冒烟通过；新版已启动（PID 93209），旧实例已关闭。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-fit-notch-4r5iss3k/Multitask Island Console.app`；证据：`Prototypes/MultitaskIslandConsole/.build/fit-notch-20260929/`。尺寸与实际布局由用户验收。

## 2026-09-29 虚拟硬件刘海预览

按用户要求在隔离开发台默认开启可关闭的「虚拟硬件刘海」：192×38 pt 的模拟中央遮挡（示例尺寸，非当前外接屏真实硬件），以细边线和暗色镜头标记位置。中央预留宽 208 pt，包含两侧各 8 pt 安全距离；收起总宽 472 pt，扣除外侧各 20 pt 后，左右内容各 112 pt。展开宽 680 pt，顶栏左右内容各 198 pt。摄像头模式显式等分两侧并裁剪溢出，文字不进入中央遮挡；球体所在左侧按整条带高度裁剪，保留球体羽化余量。列表卡片仍在顶栏下方使用原布局。

关闭开关恢复当前屏幕真实几何；当前 DELL 外接屏恢复 340×30 pt、无摄像头避让。只影响开发台，不修改系统菜单栏或生产设置。构建、归档签名与 5 项相关冒烟通过，覆盖虚拟/真实切换、左右尺寸及展开收起窗口不 resize；视觉由用户验收。新版已启动（PID 90876），旧实例已关闭。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-virtual-notch-nrdog53d/Multitask Island Console.app`；证据：`Prototypes/MultitaskIslandConsole/.build/virtual-notch-20260929/`。

## 2026-09-29 球体有限超采样修订

用户截图反馈上一版像素级平滑后仍有明显锯齿，上一版视觉未通过。本轮仅对 AI 球画布启用每轴 2× 超采样（相对 backing，像素数 4×），线性缩小呈现；边缘平滑维持约 1.5 个最终显示像素，不随超采样缩窄。关闭宿主与内部容器的边界裁切，以保留圆周羽化。列表、文字与量子噪点不增加采样，隐藏/暂停仍停止渲染。

构建、归档签名、2 项冒烟与 1 项基准通过。2× 屏幕下 18/28 pt 球画布分别为 136×136 / 210×210 像素（含留白）。16 次过渡 resize 为 0；主线程心跳 P95 11.48 ms、最大 19.68 ms、超过 33.33 ms 为 0；这不是 GPU 性能或视觉验收。新版已启动（PID 85554），旧开发台已关闭；运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-orb-ssaa-8gq1er9r/Multitask Island Console.app`，证据：`Prototypes/MultitaskIslandConsole/.build/orb-ssaa-20260929/`。新版效果待用户验收。

## 2026-09-29 Ripple Glow 小尺寸抗锯齿

修正 18/28 pt 球体缩小时固定比例边缘过渡不足一个像素的问题：隔离开发台 shader 的边缘覆盖过渡宽度至少为 1.5 个实际渲染像素，外侧提前返回边界同步调整；去掉 RGB 中重复乘入的边缘覆盖率，由最终 alpha/混合应用一次，避免暗边。`Editable/ConsoleRippleAntialias.metal` 由 `prepare.py` 注入组装副本，原生产 shader 和状态材质保留。球体宿主按实际 backing 倍率显式同步 drawable，尺寸和屏幕倍率变化时更新，不增加超采样或逐帧 SwiftUI 布局。

构建、归档签名、2 项冒烟与 1 项基准通过；冒烟确认原生 Ripple Glow shader 成功加载，2× 屏幕下 18/28 pt 球分别使用 68×68 / 105×105 像素画布（含外侧留白），隐藏/卸载暂停仍有效。16 次过渡 resize 为 0，主线程心跳 P95 11.13 ms、最大 23.03 ms、超过 33.33 ms 为 0（非 GPU 帧率）。新版已启动（PID 82913），旧开发台已关闭。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-orb-aa-0nnpos8i/Multitask Island Console.app`；证据：`Prototypes/MultitaskIslandConsole/.build/orb-aa-20260929/`。边缘观感由用户验收。

## 2026-09-29 AI 球切换为 Ripple Glow

按用户要求更换 AI 球动效，开发台收起态和未选中任务统一使用已有原版 `Ripple Glow`（涟漪辉光），替换 `Particle Orb`。继续通过隔离适配器调用原生 Metal 渲染器与原状态配色；按 Ripple Glow 自身半径契约维持原 18/28 pt 可见尺寸。选中卡片继续只有量子噪点进度，没有 AI 球。保留原降级路径及可见性、非运行状态、减少动态、卸载停止规则；生产源码不变。

构建、归档签名、2 项相关冒烟和 1 项基准通过。冒烟确认实际加载 Ripple Glow，而非静默降级；16 次过渡窗口 resize 为 0，主线程心跳 P95 11.80 ms、最大 21.58 ms、超过 33.33 ms 为 0（不是 GPU 帧率）。新版已启动（PID 79246），旧开发台已关闭。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-ripple-orb-28zpkhdc/Multitask Island Console.app`；证据：`Prototypes/MultitaskIslandConsole/.build/ripple-orb-20260929/`。视觉与实际流畅度由用户验收。

## 2026-09-29 两种状态统一橙黄色待确认提示

按用户最新反馈，待确认提示沿用原感叹号的橙黄色相并提亮至 RGB 1/0.76/0.44，覆盖上一轮偏亮黄的方案。收起态显示「待确认」，展开态右上显示「待确认 + 数量」，共用提示组件；移除展开态未筛选时的 75% 透明度，保持充分亮度。展开提示仍是待处理筛选按钮，筛选状态以字重和辅助功能值表达。错误/不可用保留独立提示及对应数量，避免混合状态误报为待确认。

构建、归档签名及 3 项相关冒烟通过，新版已启动（PID 74222），旧开发台已关闭。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-amber-confirmation-3v658u8e/Multitask Island Console.app`；证据：`Prototypes/MultitaskIslandConsole/.build/amber-confirmation-20260929/`。实际颜色和交互由用户验收。

## 2026-09-29 收起态使用亮黄色待确认文字

按用户截图，收起态右侧等待确认的感叹号改为固定文字「待确认」（English: `Confirm`），12 pt Semibold，亮黄色 RGB 1/0.88/0.20；会话数量仍为灰色。错误/不可用保留独立提示，避免同时存在时被待确认覆盖。此调整限定收起态，等待确认通过辅助功能值同步表达。

构建、归档签名及 3 项相关冒烟通过，新版已启动（PID 72189），旧开发台已关闭。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-confirmation-label-58ycycsz/Multitask Island Console.app`；证据：`Prototypes/MultitaskIslandConsole/.build/confirmation-label-20260929/`。实际效果由用户验收。

## 2026-09-29 任务详情跟随卡片展开

详情改为对应任务卡片下方的列表内内容，与卡片同宽、相隔 8 pt，随列表一起滚动。切换任务时只在新任务下显示详情；再次点击或关闭详情恢复原列表。超过四条任务仍保持有界视口：普通四行 272 pt，展开详情后 380 pt，详情 100 pt；总展开高度与原方案一致，固定 NSPanel 不变。仅选择任务时滚动到卡片和详情可见处，运行时长刷新不触发滚动。卡片与详情独立判断视口可见性，离屏文字动效停止。

构建、归档签名与 7 项相关冒烟通过；新版独立开发台已启动（PID 66405），旧实例已关闭。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-inline-detail-pdkt25vi/Multitask Island Console.app`；证据：`Prototypes/MultitaskIslandConsole/.build/inline-detail-20260929/`。实际布局与交互由用户验收。

## 2026-09-29 收敛文字用色与信息层级

按用户最新反馈，以白灰文字层级承载日常信息，覆盖此前“每种状态使用独立文字色”的方案。思考/工作/压缩用 70% 白色状态文字，完成/待机/未知用次要灰；待确认用柔和橙、失败用柔和红。状态仍由名称明确表达，只有需要处理的状态用强调色。页脚各状态计数统一灰色，不再重复彩色统计。

额度充足时圆环为白灰色，保留原额度风险阈值，在不足/紧张时使用橙/红；额度文字仍白色。模型和时长底色统一减弱至 3.5%，来源图标以 72% 不透明度呈现，元信息退为辅助层。运行详情继续灰色流光，流光峰值从 80% 降至 45%、肩部从 18% 降至 12%。保留原 Particle Orb/量子噪点渲染器及其状态色，当前任务由选中效果和清晰卡片边界突出；没有新增动画或计时器。

构建、归档签名与 5 项相关冒烟通过。当前独立运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-restrained-color-fqxzpxp0/Multitask Island Console.app`（PID 58415）；旧开发台已关闭，证据：`Prototypes/MultitaskIslandConsole/.build/restrained-color-20260929/`。用色层级与实际观感由用户验收；未替换正式安装、未改变版本身份。

## 2026-09-28 加强卡片边界与可读性

按用户截图反馈，未选中卡片不再透明：常驻 6.5% 白色底，悬停 9.5%；卡片加 1 pt 细边线（普通 8.5%、悬停 14%、选中 22% 白色），卡片间距由 2 pt 增至 8 pt，四行视口同步更新为 272 pt。行高 60 pt、字号、两行排版和选中量子噪点不变；选中行继续没有 AI 球和左侧占位。底色和边线均静态，无新计时器或逐帧布局。

构建、归档签名与 7 项相关冒烟通过。当前独立运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-card-separation-mp70vb2h/Multitask Island Console.app`（PID 2142）；旧开发台已关闭，证据：`Prototypes/MultitaskIslandConsole/.build/card-separation-20260928/`。卡片分隔效果由用户验收。

## 2026-09-28 稳定版 Codex 路径热修复已发布

0.5.1 Build 13 / internal 49 已发布 GitHub Latest 和 Stable appcast；用户明确授权
热更新，README 保持不变。发布源码 `ec99dc184d84fbb011f3e337c95be1f3d82c775c`，
文档提交 `175e044`（署名修正后；引用同步 `cef1c23`），tag `v0.5.1-build.13`。隔离工作区：
`/Users/sukduoasa/Documents/widget/.worktrees/QuotaView-0.5.1-codex-path-fix`。
基于公开 Build 9，不含本目录的多任务/压缩实验；路径兼容源码与测试已同步本目录。
当前 0.5.2 配置与实验保留，后续新包内部序号须高于 49。

5 项路径冒烟、系统 PATH 下的真实额度读取、Universal Developer ID 构建、Apple 公证/
Staple、Gatekeeper、15 秒解压启动、249 项 CI（2 跳过、0 失败）通过。GitHub 公开包
回下载与最终 ZIP 一致；Pages `36408068235` 成功，线上 Feed 与本地逐字节一致并通过
旧版应用内置公钥验证。完整资产/hash/提交记录见版本历史；未替换本机正式安装。


## 2026-09-28 日常文案、统一状态色与额度圆环

默认预设改为“日常场景”：四条任务混合短标题、较长问题标题和一条较长确认详情，Token、模型等级及运行时长使用正常量级；保留“文字极限”作为手动边界预设。状态/工具名前缀、详情右下状态和页脚各状态计数共用原多任务颜色：思考紫、工作青、压缩白、待确认橙、完成绿、失败红、不可用灰。额度文字纯白，左侧图标改为 16 pt 百分比圆环，复用已有额度风险分段颜色并随剩余值更新；会话行 Codex 来源图标保留。

构建、归档签名与 4 项相关冒烟通过（末次仅调整两条模拟文案并重新构建）。当前独立运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-realistic-status-knqq5v3f/Multitask Island Console.app`（PID 87437）；旧开发台已关闭，证据：`Prototypes/MultitaskIslandConsole/.build/realistic-status-20260928/`。显示、颜色和圆环观感由用户验收。

## 2026-09-28 状态分色、详情流光与超长文案滚动

模型与思考等级按可见 Vibe Island 的短标签显示，例如 `6 Astra · High` / `6 Astra · XHigh`。已识别的模型仅保留版本与家族，思考等级统一短名称；标签按自然宽度完整静态显示，不滚动、不省略，原始全称保留在 Tooltip。标题和操作详情继续单向滚动。

短模型标签修订已构建并启动，1 项元信息冒烟通过。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-short-metadata-4uzvb9ho/Multitask Island Console.app`（PID 83704），旧开发台已关闭；证据：`Prototypes/MultitaskIslandConsole/.build/short-metadata-20260928/`。显示效果由用户验收。

前一轮选中行去除左侧占位修订：构建、归档签名与 1 项相关冒烟通过，已启动 `/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-no-orb-gap-311pszst/Multitask Island Console.app`（PID 76715），旧开发台已关闭；证据：`Prototypes/MultitaskIslandConsole/.build/no-orb-gap-20260928/`。实际效果由用户验收。

标题下方按“状态 · 详情”呈现，只有状态/工具名保留语义色：`exec` 等具体工具名仍优先显示；运行详情为灰色加流光，完成详情为白色，其他状态详情为静态灰色。状态标签固定，详情独立滚动；标题、收起摘要和展开详情中的超长文字也滚动，不再仅靠省略号。Token 与时长保持静止。

新增独立 `Editable/ConsoleScrollingText.swift`，使用裁剪的原生 CATextLayer、Core Animation 位移与文字遮罩渐变；超长文字以 26 pt/s 向左单向循环，首尾各停顿 1.2 秒，副本相隔 32 pt 从右侧接续，无反向回滚；流光周期 2.6 秒。无逐帧 SwiftUI 更新或新 Timer；每秒时长刷新不重启文字动画。只有溢出文字滚动，收起/离开视口/暂停/卸载时停止对应宿主，Reduce Motion 静态显示，完整文案仍可通过 Tooltip/辅助功能读取。文字极限预设、选中态不显示 AI 球的规则保持。

单向滚动修订已构建并启动，2 项文字冒烟通过（含位移不反向、隐藏与减少动态停止）。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-one-way-u8pmqrux/Multitask Island Console.app`（PID 73844）；旧开发台已关闭，证据见 `Prototypes/MultitaskIslandConsole/.build/one-way-20260928/`。本轮未重复基准，实际观感仍由用户验收。

上一轮 4 项相关冒烟及 1 项文字极限基准通过。16 次过渡、窗口 resize 0 次；主线程心跳 P95 11.50 ms、最大 29.84 ms、超过 33.33 ms 为 0（非 GPU 帧率）。构建、归档签名与启动核验通过；上一轮独立运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-text-motion-xijzl16p/Multitask Island Console.app`（PID 66183），旧开发台已关闭。证据：`Prototypes/MultitaskIslandConsole/.build/text-motion-20260928/`。实际滚动和流光观感由用户验收。

## 2026-09-28 选中任务隐藏 AI 球

展开列表选中行移除 Particle Orb 宿主，仅显示量子噪点进度效果；同时去掉图标列占位及其 12 pt 间距，标题与详情从卡片左侧 10 pt 内距开始。未选中行和收起态沿用原版 Particle Orb。

历史调试曾默认载入“文字极限”预设（现默认“日常场景”），填满四条会话的标题、具体操作、模型/推理强度、Token 和运行时长；包含超长中文、英文无空格串和长路径，可从同名按钮恢复。普通预设继续保留。

本轮构建、归档签名及 2 项渲染生命周期冒烟通过。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-text-limit-nn31e2_2/Multitask Island Console.app`（PID 61036），已关闭旧版独立开发台；证据见 `Prototypes/MultitaskIslandConsole/.build/text-limit-20260928/`。视觉与文字极限效果待用户验收。

## 2026-09-28 按 Vibe Island 可见界面统一字号与密度

用户明确要求从目前可见的单会话研究并推导多任务，不再以试用限制中断。基准改为真实 Vibe Island 窗口及截图，覆盖较早生成图的宽松卡片方案；依据与测量记录见 `Prototypes/MultitaskIslandConsole/References/vibe-layout-measurements.md`，原生截图保存在 `References/vibe-native-expanded.png`。字体数值为可见栅格比例适配，未取得其私有源码精确值。

- 外接屏收起态 340 × 30 pt，展开宽 680 pt；顶栏 36 pt、列表外距 28 pt。
- 60 pt 卡片 + 2 pt 行距；标题 13 pt、蓝色具体操作 11 pt、元信息 10 pt。图标槽 34 pt，Particle Orb 28 pt；文字起点约 84 pt，与原生约 85 pt 对齐。
- 第一行标题 + 模型/推理强度 + Codex 来源图标 + 时长，第二行具体操作 + 会话 Token。收起态按参考聚焦操作与会话数量，Token 在展开会话中显示。
- 多任务直接复用单行纵向排列，四行以上滚动；保留选中行量子噪点、图钉/筛选/详情与应用级常驻。未仿制许可证购买区。

9 项相关冒烟通过，实际视觉与交互仍由用户验收。本轮只做必要冒烟和构建，不重复全套性能采样或视觉自动化。

构建、归档签名及启动检查通过。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-vibe-metrics-k_gpqwba/Multitask Island Console.app`（PID 56305）；日志和启动记录：`Prototypes/MultitaskIslandConsole/.build/vibe-metrics-20260928/`。只启动独立 DEBUG 开发台，未替换正式应用。

## 2026-09-28 选中会话使用量子噪点进度特效

展开态中，当前选中/查看的会话卡片使用原单岛 `ActivityStateSmokeMetalView` 的 `.dropField`（量子噪点），直接复用其进度解析、状态 Profile、完成推进/淡出；原黑色底面、完成描边与辉光也从单岛复用。卡片现有 Particle Orb、两行文字、Token/模型信息与 76 pt 几何不变，特效位于内容下层，其他行不创建此进度特效。

原生适配放在开发台 `Editable/ConsoleParticleOrbAdapter.swift`，只追加到组装副本，不改生产。选中卡片滚出视口、刘海收起/隐藏、取消选择或拆卸时停止渲染，Reduce Motion 保留静态进度，Metal 不可用保留黑底与信息。查看已完成会话不重播填充动画。开发台选中任务恢复“量子噪点 · 模拟进度”滑杆，运行最高 95%，完成为 100%。

5 项定向冒烟与 1 项基准通过。16 次过渡、0 次窗口 resize；主线程心跳 P95 10.60 ms、最大 11.07 ms，超过 33.33 ms 为 0。该采样不是 GPU 帧率；实际特效与可读性由用户验收。

构建、归档签名和启动检查通过。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-selected-quantum-ywen_zld/Multitask Island Console.app`；日志、基准与启动记录：`Prototypes/MultitaskIslandConsole/.build/selected-quantum-20260928/`。


## 2026-09-28 以用户选定设计图为准恢复布局

用户明确要求按既有设计图实施，不另行自由改排。会话行恢复：左侧原版 Particle Orb，中间上行任务标题、下行“执行中 · 具体操作”，右上白色半粗 Token，右下灰色“模型 · 推理强度 · 时长”。移除上一轮自行添加的 Codex 图标、模型/时长徽章和行内“累计”前缀；累计口径留在 Tooltip、详情与模拟编辑器中。第一项夹具采用图中 Saidex 更新图标示例。

按所附卡片比例调整为 76 pt 行高、44 pt 球、12 pt 圆角、两行文字间距 6 pt；四项可见、超出滚动，固定窗口画布同步适配。8 项定向冒烟通过；视觉尺寸与手感由用户验收，不做 UI 自动化验收。以上布局取代上一节“元信息右上、Token 右下”的错误排法。

构建、归档签名及启动检查通过。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-reference-layout-ke4u2hxh/Multitask Island Console.app`；日志与启动记录：`Prototypes/MultitaskIslandConsole/.build/reference-layout-20260928/`。


## 2026-09-28 补齐会话元信息与具体操作

右侧第一行显示模型、推理强度、Codex 应用图标和运行时长；第二行左侧直接显示具体操作（例如 `exec · swift test`），运行态为蓝色，右侧保留单会话累计 Token。AI 球、原布局与应用级常驻继续保留。

模型、推理强度及起始时长是明确的 DEBUG 模拟字段，可在开发台逐会话编辑；应用级单个 1 秒时钟只给运行/思考/压缩会话累计时间，待确认、完成、暂停时不累计，退出时销毁时钟。图标来自本机 ChatGPT 应用内的 Codex 原始 PNG，归入独立开发台资源，不改生产资源或声明真实模型识别。

2 项定向冒烟通过，覆盖字段映射、时长累计与停止、关闭控制窗口后继续更新；未运行完整回归或 UI 验收。旧记录中“无字段所以不显示模型和耗时”已由本次显式模拟元信息替代，正式接入仍需可信数据。

构建、归档签名和启动检查通过。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-session-metadata-joq7ztnl/Multitask Island Console.app`；日志及启动记录：`Prototypes/MultitaskIslandConsole/.build/session-metadata-20260928/`。


## 2026-09-28 刘海改为应用级常驻

修复刘海随开发台失焦/遮挡消失：移除与控制窗口 occlusion、关闭及 SwiftUI 拆卸的生命周期绑定。`MultitaskConsoleSession` 由应用代理持有，独立订阅模拟模型变化，控制窗口关闭后仍接收演示和任务更新；最后一个控制窗口关闭不退出应用。刘海不随应用隐藏，只有完全退出（⌘Q）才清理窗口、渲染与观察者。开发台移除“隐藏预览”按钮，改为常驻说明。

1 项定向生命周期冒烟通过：关闭控制窗口后任务更新仍到达刘海，退出清理后停止显示与播放。没有做 UI 自动化验收或重复性能采样；实际失焦、最小化及关闭体验由用户验收。

构建、归档签名和启动检查通过。当前运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-resident-notch-njfkwlhw/Multitask Island Console.app`；日志与启动记录：`Prototypes/MultitaskIslandConsole/.build/resident-notch-20260928/`。


## 2026-09-28 Particle Orb 与会话累计 Token

按选定的新方案在独立开发台实施：直接复用原版 Particle Orb 的 Metal 渲染器、着色器和状态动效；`Editable/ConsoleParticleOrbAdapter.swift` 仅追加到组装副本，同文件访问私有类型，生产源码不变。展开行采用左侧球、中间任务标题与状态/操作、右侧累计 Token；收起态显示所选会话的球、操作、Token、会话数及待处理提醒。摄像头区域只做真实安全区避让，不绘制示意图中的镜头。模型、推理强度、耗时没有可信字段，当前不显示。

会话累计是本开发台模拟值口径，不把真实生产“本轮”数据直接改称累计。行内明确标注“会话累计”，详情沿用该口径。原有筛选、固定、收起与详情关闭继续保留。

隐藏的另一套内容、滚出视口的行、完成/待确认等静止状态及 Reduce Motion 均停止连续 Orb 渲染；移出窗口与拆卸也暂停。固定窗口与 Core Animation 外壳过渡不变。11 项定向冒烟通过（含原生 Metal 播放生命周期），1 项基准通过：16 次过渡、0 次窗口 resize，主线程心跳 P95 10.94 ms、最大 13.67 ms、超过 33.33 ms 为 0。这是主线程采样，不是 GPU 帧率或视觉验收。

构建、归档签名及启动检查通过。运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-particle-orb-eiwv2p82/Multitask Island Console.app`；验证日志与基准：`Prototypes/MultitaskIslandConsole/.build/particle-orb-20260928/`。实际效果由用户验收。


## 2026-09-28 当前开发台仅保留刘海灵动岛

按用户最新要求，移除任务抽屉、Cover Flow、方案切换入口及三份专用源码；预览仅创建刘海控制器。保留纵向多会话、筛选、详情、图钉、收起及现有 Core Animation 动画。移除不适用的特效与百分比进度控件。10 项定向冒烟通过；源码及旧说明备份于 `Prototypes/MultitaskIslandConsole/.build/retired-concepts-20260928/`，不参与编译。

独立构建、归档签名及启动检查通过；新版运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-notch-only-o5p45w51/Multitask Island Console.app`。日志与启动记录：`Prototypes/MultitaskIslandConsole/.build/notch-only-20260928/`。

以下旧记录中“保留前两项/三个方案”属于历史状态，已被本次要求取代。仍为隔离 DEBUG 开发台，未迁入生产、未改变版本身份。后续只做基准与冒烟，实际效果由用户验收。

## 2026-09-27 点击区域修复

用户反馈右上图钉/收起与详情叉号无法点击。修正 ConsoleNotchSurface.hitTest：先将父视图坐标转换为本视图坐标，再检查外壳并转发给当前内容视图，避免 flipped 坐标混用。三个按钮增加 28 × 28 pt 矩形点击区域。仅构建/签名通过，未重跑测试或 UI 自动化；实际点击效果由用户验收。

运行包：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-notch-hit-fix-cnv6h_d0/Multitask Island Console.app`。后续仅做基准与冒烟测试，实际效果由用户验收。

## 工作区与版本定位

| 项目 | 当前状态 |
|---|---|
| 公开稳定版 | [0.5.1 Build 13](https://github.com/Duoasa/QuotaView/releases/tag/v0.5.1-build.13)；internal 49，已进入 Stable appcast |
| 发布源码 | `ec99dc184d84fbb011f3e337c95be1f3d82c775c`；已推送 main |
| 当前开发配置身份 | `0.7.5 / display Build 3 / internal 52 / com.quotaview.development073`；长会话恢复已构建运行，未发布 |
| 开发工作区 | `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget`；`codex/0.7.5-release-preparation`；本轮设置/发行准备及长会话修复未提交，main集成以本文件顶部和对应PR为准 |
| 已运行开发包 | `dist/development-0.7.3/QuotaView 0.7.3 Development.app`；实际0.7.5/Build3/internal52，真实PID16910，187项输入核对；无DEBUG模拟，现有数据路径保持 |
| 已确认动效基线 | `0.5.0 Build 2`；正常动效参数保持，原本地归档保留 |
| 回滚入口 | `v0.5.1-build.9` / `927749b1a205495c86b6090e69044b0c39d85730`；完整资产记录见版本历史 |

进入后先用 `git worktree list`、`git status --short --branch` 与 `git log -1` 核实实时状态。
正式发布在隔离工作区完成，原开发目录的分支与未提交改动保留；当前文档已同步，
不能将分支名或旧 HEAD 当成当前源码版本。下一可分发迭代使用新的 Build 身份。

## 当前开发台：Vibe Island 纵向会话与展开性能修复（2026-09-27）

用户要求参考本机 Vibe Island 的设计、排版、多任务布置和展开收起，且反馈旧开发台卡顿。
本轮实际观察本机收起态、原生展开态及设置中的 0.15 秒悬停延迟；额外会话被许可证遮挡，
用户明确补充「多会话页面其实就是将单会话的卡片复制排列下来」。据此实现同一会话行的纵向列表。

- 第三方案改为紧凑工具栏 + 纵向两行会话：左侧状态图标，标题和操作说明，右侧来源、状态与 Token。
  四行以内随内容定高，更多任务在有限视口中滚动，采用 LazyVStack；取消横向四卡与翻页。
  没有可用模型/耗时数据时不伪造 Vibe Island 的模型和时间标签。状态图标使用 SF Symbols。
- 收起态显示当前模拟任务操作和会话数；有摄像头时优先留出安全区。无刘海屏幕高度 30 pt。
  悬停延迟 0.15 秒，离开预览 0.45 秒收起，点击固定、待处理筛选、岛内详情、Esc 分层关闭继续保留。
- 外壳改为固定 NSPanel 内的 CAShapeLayer 路径/遮罩动画；展开/收起不再逐帧修改系统窗口尺寸。
  两份内容视图保留最终布局，只做透明度与轻微位移动画；阴影提供 shadowPath，移除每行 TimelineView。
  采用本地适配的 0.38 秒展开、0.25 秒收起和缓出曲线，可从当前 presentation layer 打断接续；
  未取得 Vibe Island 原生源码或精确曲线，不声明逐帧一致。
- 透明区域按实际动画轮廓命中；收尾有一次指针复核，防止静止鼠标下的透明区域继续挡点击。
  隐藏、切换与 Reduce Motion 清理动画，稳定态无动画驱动定时器；窗口菜单可定位「任务总览 · DEBUG」。
- 14 项定向逻辑/几何/生命周期冒烟 + 1 项显式 AppKit 性能采样通过（共 15 项），独立构建、归档签名通过。
  相同 16 次切换：窗口 resize 通知 418 → 0，主线程心跳 P95 17.26 → 10.91 ms，最大间隔
  70.82 → 18.91 ms，超过 33.33 ms 的间隔 4 → 0。这不是 GPU 帧率或最终视觉验收。
  未运行完整生产回归。正式源码/配置逐文件指纹保持一致；前两方案、产品身份和发布状态不变。

证据：`Prototypes/MultitaskIslandConsole/.build/vibe-reference-20260927/`，含本机参考截图、
`performance.json`、`final-smoke.log`、`build.log`、`production-integrity.json` 与运行包路径 `launch.json`。
`prototype-*.png` 是早期 NSView 缓存绘制实验，未包含完整合成遮罩，不能作为真实窗口画面验收。
视觉、滚动手感与真实多屏/全屏仍由用户验收；当前只在隔离 DEBUG 开发台实施。

## 前轮开发台：第三方案改为刘海式「任务总览」（2026-09-27）

用户要求自主重设计，并明确作为第三选项、形态仍须是灵动岛。开发台现提供
「任务抽屉 / Cover Flow / 任务总览」，启动默认第三项，原两项保留。
第三方案改为屏幕顶边的黑色刘海外壳：真实刘海中间留空，两翼显示状态摘要；
无刘海屏幕用贴顶标签。默认收起，悬停 0.20 秒预览，移开 0.45 秒收回，点击固定；
固定后点击外部/收起按钮退出，Esc 分层关闭。根据本机 Vibe Island 收起态和官方展开演示，
去掉窄颈与横肩，整条上沿贴顶，使用小内凹顶角与大圆底角。内容避让摄像头；
展开外壳占用中央菜单栏区域，透明小顶角鼠标穿透。
岛内横向展示四项任务，支持翻页、待处理筛选、
岛内详情、手动收起和完成回看；收起仍保留运行数、待处理数和额度。
展开完成态显示总 Token。运行状态环不伪造进度，隐藏/暂停/减少动态时停止。
独立实现：`Editable/ConsoleConceptBoard.swift`，仍使用隔离 DEBUG 夹具；不接生产。
12 项定向冒烟、独立构建、归档/签名和启动检查通过，当前 PID 3951，启动器已关闭
旧实例 PID 98143。产品身份仍为 0.5.2 / Build 7 / internal 48。视觉与交互待用户验收。

## 开发台前两项：任务抽屉与 Cover Flow（2026-09-26）

用户选择在隔离多任务开发台比较两种新方案。`Prototypes/MultitaskIslandConsole/`
顶部现提供「任务抽屉 / Cover Flow」切换，同一组模拟任务与选择保留。两者主岛
复用单岛原生圆角矩形、字号、布局及果冻；Cover Flow 侧卡改为 160 × 66 pt、
12 pt 圆角，侧倾由 60° 调小到 25°，侧卡中心间距 128 pt，避免浅角度卡片互挡。
后台标题和状态均居中对齐；特效透明度为 50%，移除描边和完成辉光。卡片与文字沿连续轨道
移动、侧倾、转正进入固定中心位，支持点击、左右按钮、拖动和滚动吸附；角度与
时长为经典 Cover Flow 结构的本地拟合，并非 Apple 公开原始参数。抽屉支持
选择后关闭、外部点击和 Escape。
只有全部完成才缩略，新任务可打断收尾。

开发入口为该目录 `Editable/ConsoleConcept{Controller,Layout,Views}.swift`，
保留原生产多任务视图/动效快照供复用；旧液态效果不再作为开发台可选项。
7 项定向冒烟、独立 DEBUG 构建、归档/签名与启动检查通过，新实例 PID 66833，
旧开发台 PID 64493 已退出。产品仍为 0.5.2 / Build 7 / internal 48；本次不改
生产源码和版本。运行包为开发台 `dist/MultitaskIslandConsole.zip`，视觉与实际
交互等待用户验收。详见[开发台说明](Prototypes/MultitaskIslandConsole/README.md)。

## 0.5.2 Build 7：主岛字号恢复基线（当前生产开发版）

用户指出 Build 6 的主岛字过大。原因是 Build 5 曾调大单岛/主岛共享字号；Build 6
复用了同一个渲染器，却没有恢复这组字号。本轮从 Build 5 修改前的源码副本核对并恢复
原字号：标题 12.5 pt、说明与 Token 11.5 pt、状态 15 pt、完成提示 16 pt、
完成辅助文字 11 pt。原生完成额度值 28 pt 与百分号 14 pt 本来未变。

单岛与多任务主岛仍由同一个 `ActivityIslandContentView` 排版和绘制；子岛维持
13 pt Semibold，以及状态色描边、标题滚动和绿色完成呼吸辉光。完成汇总仅投影
任务数、总 Token 和真实额度，不再引入独立字体或版式。岛体尺寸及果冻不变。

3 项针对性冒烟通过，涵盖基线文字绘制、原生完成汇总与果冻同步。
Universal Release App / Widget / Helper 双架构、资源、版本（0.5.2 / Build 7 / internal 48）
与独立运行副本 ad-hoc 签名核验通过。已启动：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-052-build7-real.g3je08na/QuotaView.app`，
PID 79204；启动 21.1 秒后存活，stderr 为空，Hook Socket 监听正常。
旧 Build 6 开发进程正常退出，多任务偏好保留，安装版 Info.plist 指纹不变；运行
副本无嵌入 Widget。证据：`dist/verification/0.5.2-build7/`。仅冒烟与构建/启动检查，
视觉由用户验收；未提交、推送、公证或发布。

## 0.5.2 Build 6：主岛复用与子岛字号（历史基线）

用户进一步要求多任务主岛的字体、字号和排版完全复用单岛模式。本轮删除独立的
多任务完成汇总视图，不再维护系统字体、完成图标、两组文字或额度标题的另一套布局。
活动态与完成态均直接使用 `ActivityIslandContentView`；多任务仅将全部完成提示、
总 Token、任务数和真实额度投影为原生渲染数据，单岛字号与布局本身未进一步改变。

完成展开态沿用单岛左侧两行完成提示/Token、右侧数值与百分号布局；此前多任务
专有的「额度剩余」上标题与绿色勾图标不再显示。缩略态用同一个原生标题区域显示
「全部完成 · N 项任务」并保留同心额度环，仅按真实文字宽度补足容器宽度。
子岛标题与状态短提示按追加要求从 11 pt 提升到 13 pt Semibold，文字视口高 20 pt，
胶囊仍为 104 × 52 pt。状态描边、绿色完成辉光、标题滚动、全部果冻及同时融合保持。

6 项针对性冒烟通过（主岛 4 项、追加字号相关 2 项）；中英文、4/128 任务、展开/缩略
逐项对照单岛原生视图的字体、文本位置、对齐和透明度，验证数据缺失占位与同心额度环；
另验证子岛长标题完整滚动、状态回切与 Reduce Motion，兼顾辉光和果冻。
Universal Release App / Widget / Helper 双架构、资源与版本（0.5.2 / Build 6 / internal 47）
及独立运行副本 ad-hoc 签名核验通过。追加子岛字号后已重新构建最终产物。
已启动：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-052-build6-real.k2mblc70/QuotaView.app`，PID 53307；
启动 45.3 秒后存活，stderr 为空，Hook Socket 监听正常。旧 Build 5 开发进程
正常退出，多任务开启偏好保留，安装版 Info.plist 指纹保持；运行副本不带嵌入 Widget。
证据：`dist/verification/0.5.2-build6/`。仅冒烟与构建/启动检查，无 UI 自动化或额外模型调用。
视觉由用户验收；工作区、分支及既有未提交工作保留，未提交、推送或发布。

## 0.5.2 Build 5：状态描边与主岛排版（历史基线）

2026-09-25 记录的三项待办已于 2026-09-26 实施：

1. 子岛移除状态圆点/图标，统一用真实状态颜色的 1 pt 描边；完成态保留绿色高光描边与呼吸辉光。短标题居中，长标题继续滚动，释放原图标所占空间。
2. 主岛与单任务岛复用的展开文字调整为标题 15 pt、说明/Token 13 pt、状态 17 pt、完成提示 18 pt。融合完成态为提示 18 pt、Token/额度标题 13 pt、额度值 26 pt。岛体尺寸与缩略字号保持。
3. 融合完成态复用原主岛按字形居中绘制的文字组件，按实际文字高度把左右两组内容分别整体垂直居中，完成图标同轴；右侧继续上方「额度剩余」、下方百分比且右对齐。

果冻、分离/同时融合时间线、特效原始亮度、标题滚动与状态短提示保留。
默认关闭、关闭回退单岛、手动选择主任务及真实数据链路保持。工作区/分支不变，
此前未提交工作保留。

7 项针对性冒烟通过，覆盖全部真实状态描边、绿色呼吸及清理、Reduce Motion、
完整标题/状态回切、中英文完成态居中与文字边界、缩略同心额度环、果冻同步及同时融合。
Universal Release App / Widget / Helper 双架构、资源与版本（0.5.2 / Build 5 / internal 46）
核验通过；独立运行副本去除嵌入 Widget 并完成 ad-hoc 签名校验。复制的 Finder 元数据
曾导致首次签名失败，仅清理临时副本的扩展属性后复验通过。

已启动：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-052-build5-real.hdwwgrse/QuotaView.app`，PID 41429；
启动 73.9 秒后存活，stderr 为空，真实 Hook Socket 监听正常。
旧 Build 4 开发进程正常退出，多任务开启偏好保留，安装版 Info.plist 指纹保持。
证据：`dist/verification/0.5.2-build5/`。仅冒烟及构建/启动检查，无截图、UI 自动化
或额外模型调用；视觉由用户验收。未提交、推送、公证或发布。

## 0.5.2 Build 4：统一标题与子岛滚动（历史基线）

用户要求去掉兜底文案中的 Codex，范围包括主岛、子岛、单任务岛：三者共用
真实会话名 → 工作区名 → 未命名任务的标题规则；真实标题自带 Codex 时保留。
子岛长标题新增 22 pt/s 往返滚动，首尾各停 1.2 秒，短标题不滚动。状态短提示
结束后恢复标题滚动；重复事件不重启，隐藏/禁用停止，Reduce Motion 静态。
主岛和单任务岛只调整标题兜底规则，既有排版、果冻及完成反馈保留。

5 项相关冒烟通过，涵盖标题兜底/真实 Codex 标题保护、完整滚动距离/停顿/不重启、
状态回标题、隐藏停止、绿色完成反馈及果冻同步；最终滚动边界另复验 1 项。
Universal Release App / Widget / Helper 双架构、资源、版本（0.5.2 / Build 4 / internal 45）
及独立运行副本 ad-hoc 签名核验通过。

已启动：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-052-build4-real.179qfs2w/QuotaView.app`，PID 82841；启动 56.4 秒后存活，stderr 为空，Hook Socket 监听正常。
旧 Build 3 开发进程正常退出；现有多任务开启偏好保留，安装版 Info.plist 指纹不变，
运行副本不带嵌入 Widget。证据：`dist/verification/0.5.2-build4/`。只做冒烟和构建/启动，
无 UI 自动化或额外模型调用，视觉由用户验收；未提交、推送、公证或发布。

## 0.5.2 Build 3：绿色完成描边与呼吸辉光（历史基线）

用户要求真实完成的子岛带绿色高光描边、呼吸辉光，并去掉完成态状态圆点；
同时取消子岛进度特效的 40% 亮度限制，恢复原始亮度。完成态标题居中，
状态短提示继续生效，全部融合阶段也不恢复勾图标。描边、外部辉光、黑色表面、
文字和特效共用果冻变形；离开完成态、隐藏、禁用及时清理，Reduce Motion 静态。
主岛默认色板/完成时序和原有动效保持，工作区与既有未提交工作保留。

4 项针对性冒烟通过，含完成指示/绿色呼吸清理、原始亮度、状态回标题、
Reduce Motion、同时融合及共享果冻。Universal Release App / Widget / Helper 双架构、
资源与版本（0.5.2 / Build 3 / internal 44）及独立副本 ad-hoc 签名核验通过。
已启动：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-052-build3-real.ftgtnqj7/QuotaView.app`，PID 63592；启动 56.6 秒后存活，stderr 为空、Hook Socket 监听正常。
旧 Build 2 开发进程正常退出，既有多任务开启偏好保留，安装版 Info.plist 指纹不变。
证据：`dist/verification/0.5.2-build3/`。本轮仅冒烟和构建/启动检查，视觉由用户验收。
正式安装与 Widget 保留；未提交、推送、公证或发布。

## 0.5.2 Build 2：子岛内容与完成回执（历史基线）

用户授权在真实多任务上细化并启动新版，仅冒烟、视觉由用户验收。源码加入
104 × 52 胶囊子岛、40% 亮度的全幅状态特效、标题左侧真实状态指示；任务状态
变化显示最新状态 2.4 秒并单次流光，再自动回标题。同状态刷新不重放。
主岛展开尺寸与所有原有单岛/多岛果冻不变。全部完成仍同时融合，展开左侧总 Token，
右侧「额度剩余」在上、百分比在下且右对齐；缩略直接复用单岛同心额度环，
仅为任务数补足紧凑宽度。总 Token 只汇总展示组真实轮次数据，缺失显示占位。

工作区与分支不变，既有未提交工作和永久开发台保留。多任务默认关闭，关闭恢复
单岛；继续使用手动主岛选择，自动焦点能力没有新增。10 项相关冒烟通过，覆盖
真实状态/Token 汇总、状态提示自动回标题、全幅 Metal/Reduce Motion、双语回执
同心圆环及原单岛果冻。Universal Release 的 App / Widget / Helper 双架构、
0.5.2 / 2 / 43 版本、资源、独立运行副本 ad-hoc 签名均通过。

新开发版已启动：`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-052-build2-real.sc4apjot/QuotaView.app`；PID 52434，启动 115.2 秒后存活、stderr 为空，
真实 localRollout 活动与 Hook Socket 监听正常。旧 Build 1 开发进程已正常退出。
用户现有多任务偏好为开启，未修改；运行副本无嵌入 Widget，安装稳定版 Info.plist
指纹保持。证据：`dist/verification/0.5.2-build2/`。只做冒烟及构建/启动核验，
未执行完整回归、UI 自动化或额外模型调用；视觉和真实多任务长期体验由用户验收。
公开稳定版仍为 0.5.1 Build 9，未提交、推送、公证或发布。

## 0.5.2 Build 1：真实多任务接入（历史基线）

用户已授权开始 0.5.2、接入多任务并完成后启动开发版。工作区/分支不变，
既有压缩修正及永久开发台保留，未提交、推送或发布。规格：
[多任务 002](docs/design/quotaview-island-multitask-next.md)，`Accepted / Verifying`。

设置「灵动岛 → 多任务灵动岛」默认关闭，用户开启后才显示真实多任务。
每任务独立状态、计划、Token、标题；手动点击子岛切换主任务，右键菜单访问
全部任务。后台不抢选，主岛居中，新增球紧邻右侧；全部成功完成才同时融合、
缩略及隐藏，新活动取消收尾。关闭即停止专用渲染/计时/额外查询并回到原单岛。
原生主岛内容/果冻与已有压缩状态保留，默认不启用任何实时焦点采集器。

**当前能力边界：自动跟随 Codex 正在查看的任务尚未接入。** 之前 Computer Use
安全限制仍有效，没有以 AX、AppleScript、截图或私有 IPC 绕过。当前只由用户
在 QuotaView 选择主岛；开发台的新建并进入效果没有虚构成生产焦点能力。

8 项生产相关冒烟、2 项开发台兼容性冒烟通过。Universal Release 的 App /
Widget / Helper 均为 arm64 + x86_64，版本与资源核验通过；独立运行副本
去除嵌入 Widget 并完成 ad-hoc 签名校验。已启动：
`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-052-build1-real.47_l76uh/QuotaView.app`。旧 Build 12 开发进程已退出；新进程 PID 9145，01:32 存活、stderr 为空，
收到真实 localRollout 活动，Hook Socket 监听正常；多任务偏好缺省为关闭。
证据目录：`dist/verification/0.5.2-build1/`。正式安装 Info.plist 指纹保持。
视觉与真实多任务交互由用户验收；没有发送测试消息或额外模型调用，未触发
自然压缩验证；公开稳定版和安装版 Widget 保留。

## 历史：压缩状态与多任务探索（2026-09-24）

用户启动下一版，先要求压缩状态排查和多任务方案，随后明确授权先修复压缩
状态、构建并启动；多任务只完善方案，暂不实现或构建。
[排查与方案](docs/design/quotaview-island-multitask-next.md)为 `Draft / Discovery`：
真实日志样本只有压缩完成记录，现有本地解析依赖开始记录；共享通知又屏蔽
item 开始/结束且缺少压缩解码，导致无法补齐正在压缩状态。
Build 11 在现有采集、状态机和单任务灵动岛内补齐压缩链路：
原生 item 开始/结束携带真实时间戳和脱敏 item 身份；本地日志提供结束及恢复
依据。现有 Hook 安装器支持仅启用 PreCompact / PostCompact，并可独立识别
为有效安装；收到真实压缩事件才建立连接证据，启动检查仍只读。
缺少轮次的 Hook 绑定当前任务，不重置 Token 或计划。重复、乱序、错轮次、
错 item、孤立结束以及终态后的迟到事件不会误开压缩；真实后续活动可恢复
丢失结束事件的压缩状态。原生断连、本地读取失败或移除对应 Hook 时，当前
压缩转为现有不可用状态，等待真实后续事件，不猜测成功。

完整回归 252 项：默认运行 250 项通过、2 项跳过，随后显式补跑两项均通过，
合计 252 项通过、0 失败。补跑覆盖实际 20 + 100 秒收起计时、安装版 Codex
连接隔离的本地 HTTP / SOCKS5 夹具；不使用真实账户或模型推理。
压缩专项 8 项含未修改 Helper 二进制 → 私有 Socket → ACK → Store 与队列
去重集成，沙箱禁止测试 Helper 写入生产队列。Universal App / Widget / Helper、
资源、版本与本地签名验证通过。

已启动独立真实数据包：
`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-051-build11-real.xe_oexyp/QuotaView.app`。
55 秒存活、stderr 为空，私有 socket 存在，真实本地任务事件接纳及共享额度
快照更新已确认。旧 Build 10 主应用已退出；`/Applications/QuotaView.app`
与安装版 Widget 保留。证据：`dist/verification/0.5.1-build11/`。
未提交、推送、公证或发布。

**真实自然压缩验证未通过（10:47 用户截图）：**当前共享实时入口拒绝连接，因此已按本轮
授权用现有安装器给 hooks.json 增加 QuotaView 的两个压缩处理器；Vibe Island
及其他第三方内容语义保持，config.toml 不变，原配置有 0600 权限备份。
安装和监听成功不代表 Codex 已加载/信任或实际投递新增 Hook；没有替用户
进行安全信任或重启 Codex。随后用户截图确认 Codex 正在自动压缩时，灵动岛
仍显示工作中。对应 rollout 在 10:47:20 写入压缩完成，实际开始时间为
10:45:17；没有落盘开始事件，QuotaView 在 10:47:21 仅收到 localRollout
PostCompact，没有收到该次 Hook 开始或结束，不能记录为自然压缩通过。
只读 hooks/list 返回两个 QuotaView 处理器 enabled / trusted，解析错误为零；
已安装 Helper 的私有 Socket / ACK 检查两项通过，令牌和实际监听地址一致。
原生共享 Socket 与 Hook 接收 Socket 是不同端点；前者拒绝连接，后者正常。
源码两路并行启动，原生连接不会停用 Hook。故障发生时 Codex / App Server 从
9 月 23 日运行，而 Hook 于 9 月 24 日 10:07 安装；旧会话未重新加载是主要
待验证假设，尚未直接读到其内存中配置。用户随后已自行重启：10:56:13 主进程
换为 44487，10:56:15 App Server 换为 44526，当前任务已恢复；启动参数没有
禁用 Hook 的覆盖项。Hook 接收 Socket 正常，原生共享入口仍拒绝连接。
重启后尚无自然压缩记录，因而没有新的压缩 Hook 投递可核对，仍不能确认修复；
等待正常使用中的自然事件，不重复要求重启。QuotaView 保持原 Build 11 进程。
本轮未改生产源码或重建；证据在 `dist/verification/0.5.1-build11/natural-compaction-followup/`。
用户明确要求不为测试消耗 Token，禁止堆上下文、额外任务或模型调用以促成
压缩。Hook 是事件触发通道，没有持续
连接心跳；缺失结束时仅由后续真实事件恢复，不采用时间猜测。
多任务仍为 Draft / Discovery，曾在压缩排查期间按用户要求暂停，未实现或构建。
2026-09-24 继续调研确认：采集层
已有多任务候选与身份基础，主要缺口是 Store 的每任务完整状态、稳定主任务
选择、独立回执/提醒和持续观察。方案已补充任务计数、重启恢复、后台完成、
容量边界和验证场景；默认主卡加列表入口还是直接三行仍待用户偏好确认。
用户随后允许研究新增焦点信息链路：建议系统/辅助功能通知驱动，稳定任务
标识优先、唯一标题匹配回退，前台小范围轮询补漏；亚秒级为待测目标。
窗口变化与具体会话身份需分别验证，不能把焦点变化当作任务开始。
多任务调研阶段只改文档；随后的压缩 Hook 修正见下。

### Build 12：压缩 Hook 等待提示与连接证据

用户确认重启后兼容 Hook 一直显示「等待第一条消息」。重新核对配置：共
12 个处理器，其中 Vibe Island 10 个、QuotaView 2 个；QuotaView 仅接收
PreCompact / PostCompact，普通消息不会触发它的处理器，旧提示不适用。
Build 12 按 QuotaView 自身安装范围区分中英文提示：仅压缩模式显示「等待
压缩事件 / 等待自然压缩」，完整模式保持首条消息引导。只读安装检查同步
识别范围，压缩模式的连接证据独立于旧完整模式，不能用普通消息或自动连接
的健康状态伪造压缩投递成功。真实 Hook 配置及第三方处理器保持原样。

回归中发现未启动的 Unix Bridge.stop 也会 unlink 相同监听路径，已修正为
仅启动过的实例清理，并让 Runtime 使用注入安装器的 Socket 地址。测试期间
受影响的 Build 11 监听已立即重启恢复；此问题不能倒推为 10:47 失败的根因。
Build 12 已通过 254 项唯一回归：最后默认运行 252 项通过、2 项跳过，两个
显式开启项在同轮已通过；33 项专项通过。新监听测试初次因夹具路径过长
失败，缩短后专项及完整复验通过。Universal App / Widget / Helper、版本、
本地 Developer ID 签名通过；没有模型测试调用或强制压缩。

已启动独立开发包：
`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-051-build12-real.m_ey4ytw/QuotaView.app`。
Build 11 已退出，正式安装和 Widget 保留；Codex 未再次重启。证据：
`dist/verification/0.5.1-build12/`。尚未观察重启后的自然压缩开始与结束，
不能宣称自然识别已修复；继续正常使用验证，未提交或发布。

### 多任务方案恢复探索：整体完成才缩略

用户随后恢复多任务方案探索，明确「全部任务完成后才缩小成缩略态」。已同步
草案：任何思考 / 工作 / 压缩 / 等待确认任务存在时保持展开，主任务完成不
代表整岛完成；最后一项可信完成后显示整体回执，再允许缩略。新任务到来
取消旧缩略 / 隐藏计时，失败或状态未知不冒充全部完成。此前两张概念图中的
「3 项进行中」缩略示意作废，后台列表仍待完善。仅更新方案文档，未实现或
构建多任务，运行包保持 Build 12；异常收尾和手动收起例外尚未确认。

### 多任务隔离开发台（最新授权）

用户看过两张预览后要求做成可操作开发台。已新增
[多任务开发台](Prototypes/MultitaskIslandConsole/README.md)：右侧任务列 / 底部
任务条两个入口，台内保留任务状态切换，共用单个浮岛。原
[单任务开发台](Prototypes/IslandTextConsole/README.md)及其保存包不变。
提供逐任务编辑、全部完成才缩略、新任务取消缩略、后台选择 / 滚动，以及
可停止的 20 秒演示。默认 3 秒完成提示仅用于原型，生产时长仍待决定。

复用当前生产 Metal 特效与动效时间线；模拟状态和组合布局只在隔离原型。
构建身份继承 Build 12 / internal 41，独立 Bundle ID，本机 ad-hoc 包，不运行
真实数据服务；生产多任务未实现，正式安装和真实 Build 12 进程保留。
25 项状态检查、3 项原生宿主 / 计时检查、构建签名与两个入口启动通过，
单实例替换已验证。视觉等待用户实际体验，未提交、推送或发布。
证据：`dist/verification/multitask-console/`；交付状态改为 Draft / Prototype。

用户随后要求关闭开发台：已退出 `com.quotaview.multitask-island-console`
的 PID 5607，核对无剩余同 ID 实例；悬浮预览随之关闭，源码与入口保留。
最新探索改为「主岛与卫星球」：当前会话沿用原单岛，后台任务从右侧黏性
分离为小球，会话切换交换大小角色，全部完成再融合收拢。已补全视觉草案并
生成关键帧效果图；此新方向尚未实现、构建或启动，等待视觉反馈。
用户进一步明确：完成任务合并为小号完成分岛；当前主任务已完成时汇总融入
主岛并显示完成任务数，切回未完成会话则重新分离，可从完成列表选择会话。
当前主任务完成不再自动切换到其他任务；所有任务完成才整体缩略的前提保留。
已更新视觉草案，旧原型不含此逻辑且保持关闭。

**2026-09-24 后续授权与最新状态：**用户暂停完成汇总，明确保持任务逻辑次序，
选中主岛位于屏幕顶部水平中心；已按最新授权构建并启动「居中液态分岛」。
入口为 `Prototypes/MultitaskIslandConsole/Open Liquid Islands.command`。
主岛直接复用生产视图，子岛直径 52 pt；使用 Apple Spring 0.42 秒 / bounce 0.15，
短距离连接及时断开，参与变化的岛均有轻微果冻反馈。当前任务完成不抢换焦点，
所有任务完成才缩略；完成汇总不在本次实现范围。前两个布局保留为历史对照。
25 项状态检查、8 项原生 / 动效 / 计时检查通过，构建签名与启动通过，视觉待用户
体验。证据：`dist/verification/liquid-island-console/`。仅隔离原型，生产多任务、
真实活动数据服务、版本身份与正式安装未改动；真实 Build 12 进程仍在运行。

用户再次要求同时启动开发版与开发台：原临时 Build 12 包已被清理，按现有源码
重新完成 Universal Release 构建，并启动真实数据运行副本
`/var/folders/zy/l0cfwlkd1gd9bnc1yh71bn0r0000gn/T/quotaview-051-build12-real.on2qvb9m/QuotaView.app`。
版本仍为 0.5.1 / Build 12 / internal 41，运行副本不嵌入 Widget，ad-hoc 签名验证
通过。居中液态分岛开发台同时启动。证据在 `dist/verification/0.5.1-build12/relaunch-*`；
本次未修改功能源码、正式安装或 Codex 配置，自然压缩验收状态不变。

后续液态视觉细化：保持生产任务状态、文字与特效；单任务使用生产圆角矩形，
新增子岛按鼓起 / 短颈 / 断开分阶段过渡，约 0.36 秒断开后主岛轮廓回弹并变为
胶囊，宽高中心不变。隔离副本增加可逆圆角适配，生产渲染器源码未改动。
按用户最新要求仅做构建、签名和 4 项冒烟，全部通过；完整回归未重跑，视觉及
交互由用户验收。证据：`dist/verification/liquid-island-refinement/`。

用户随后反馈仍缺少果冻抖动：已将单纯圆角回弹补为外壳压扁 / 反向伸展 / 衰减，
主岛与新子岛均在断开后反馈。布局宽高和中心保持固定，外壳短暂形变后恢复，
文字反向补偿保持字形。仅改隔离适配；构建签名和 4 项冒烟通过，视觉仍由用户
验收。最新证据：`dist/verification/liquid-island-jelly/`。

用户要求在不改原全部果冻的前提下做多任务。排查确认新宿主复用视图却遗漏了
原 `ActivityIslandMotion`，已接回原呼出、展开 / 缩略、隐藏、共享回弹、文字跟随
和打断时间线；多任务动效只负责队列与融合 / 分离叠加，单任务不套用新增覆盖。
4 项局部冒烟及构建签名通过，生产渲染 / 动效源码和原单岛开发台无改动。
最新证据：`dist/verification/liquid-island-preserve-single/`；视觉仍由用户验收。

最新完成收尾按用户选图实现：全部完成后显示「已完成全部任务」，子岛由近到远
依次从原侧融入居中主岛，双方保留果冻，融合收拢后再缩略为「全部完成｜N 项任务」。
部分完成仍不汇总；新任务取消旧收尾与计时，任务身份不丢失。单任务原动效不变。
4 项局部冒烟、构建签名及开发台启动通过，证据 `dist/verification/liquid-island-completion/`；
仅隔离开发台，视觉由用户验收，生产多任务未接入。

用户反馈逐个融合拖沓，已改为所有子岛同时启动、同时融入，共用约 0.46 秒过程，
不再按任务数量累加时长。主岛只回应一次果冻，避免多任务叠加强度；原单岛、
完成门槛和中断恢复保留。4 项局部冒烟与构建签名通过，最新证据：
`dist/verification/liquid-island-simultaneous/`，视觉由用户验收。

最新修正全部果冻的内容跟随：主岛取消文字 / 完成回执的反向缩放，子岛外壳、
文字与图标共用缩放容器，覆盖分离、切换和同时融合。逻辑排版与视觉形变分开，
避免子岛回弹膨胀时误切大岛渲染器。原单岛时间线、动效参数和生产源码不变。
4 项局部冒烟、隔离构建签名及重启通过；最新证据
`dist/verification/liquid-island-shared-content/`，视觉由用户验收。

新子岛规则再细化：始终从当前主岛右侧分离并留在紧邻位置，旧右侧子岛同步
向右让位，左侧与旧任务相互次序不变。替换旧队尾分离源，保留主岛焦点与共同
果冻；全部完成后新任务恢复主岛的既有规则保留。4 项局部冒烟、构建签名及
开发台重启通过，最新证据 `dist/verification/liquid-island-main-origin/`。
仅隔离原型修改，生产源码未变，视觉由用户验收。

用户反馈基础动效基本完成，随后授权模拟前台创建：开发台增加「新建并进入」
与「后台新增」两个入口。前者一次提交新增与焦点，新任务接管居中渲染器，
旧任务向左分离、左侧让位，原内容淡出后整组换为新内容；后者保持右侧分离。
连续创建、切回已有任务及 Reduce Motion 已做局部冒烟；连同原单岛、原生宿主、
完成融合等共 6 项通过，构建签名及重启通过。最新证据
`dist/verification/liquid-island-focus-handoff/`。仍为隔离模拟，真实 Codex 焦点
与事件聚合未接入；新交接视觉待用户验收，生产与原单岛开发台源码未改。

**2026-09-25 接入方案与回退要求：**用户认可多路任务状态、独立焦点识别与统一
动画调度的方向，并明确生产接入前须增加「多任务灵动岛」设置，默认关闭，
仅用户主动开启才运行多任务。关闭后无需重启即恢复原单岛选择与完整动效，
停止多任务专用观察、轮询及调度，隔离迟到回调；共享状态采集和压缩 Hook
继续按原单岛规则工作。偏好持久化，缺省 / 升级不自动开启。详见
[最新接入与回退要求](docs/design/quotaview-island-multitask-next.md#2026-09-25接入方向与默认关闭的回退开关已确认要求待实现)。
本轮仅更新方案与索引，生产开关、真实焦点和多任务接入均待实现；未构建、
启动或改变版本身份。后续先验证焦点，再接隔离开发台；局部冒烟覆盖运行中
关闭和重启保持，视觉与实际切换由用户验收，不通过模型调用制造验证事件。

用户随后要求焦点实测；Computer Use 对 `com.openai.codex` 明确返回安全
访问拒绝，未取得界面树或选中任务，延迟与准确率未测。此为工具访问限制，
不代表已证明焦点方案不可行；不能通过其他脚本或私有接口绕过。本轮仅
记录阻塞，未修改生产功能、构建或发送模型消息。继续实测需要允许的读取
接口或用户提供切换观察结果，详见方案中的焦点实测记录。

继续后完成独立的 `Prototypes/MultitaskIslandConsole/FocusValidation/` 规则原型，
6 组离线冒烟、30 项断言通过；覆盖身份匹配、不可信证据、窗口与开关过期回调，
并确认选择不改变现有任务状态 / Token / 次序。仅编译运行夹具命令行程序，
没有实时采集器、生产或开发台 UI 接入，也未重建 / 启动 App。证据在
`dist/verification/focus-rules-offline/smoke.log`。真实焦点仍未验证；用户未打开
Vibe Island，暂无其跟随表现的人工观察，不能将离线结果视为接入验收通过。

## 0.5.1 Build 9：单周期文字垂直对齐（已发布）

根据用户与右侧 CodexBar 的对比截图，将原生状态栏文字基线下移 1.5 pt，
修正 14 pt Regular 文字视觉偏上。保留原生系统着色、图标位置与双周期布局。
正式 Release 与 Stable appcast 已完成。Universal Release、完整测试、Apple 公证 / Staple、
Gatekeeper、公开回下载和 Feed 签名验证通过。构建与启动验证见 `dist/verification/0.5.1-build9/`；
视觉仍由用户持续验收。
Universal Release 与 35 秒启动冒烟通过，曾运行
`/tmp/quotaview-051-build9-real.gV2CL7/QuotaView.app`，旧 Build 8 已退出。

发布事实：tag `v0.5.1-build.9`，ZIP `QuotaView-v0.5.1-build.9.zip`，
Apple Submission `e6120807-7d60-414a-8952-9293e06c1e1b`，Stable appcast 提交
`b00d414e5d96e7146e14cbfb3a233de3de8f3c8d`。

## 0.5.1 Build 7：单周期常规字重

按用户要求，单周期原生文字与设置预览从半粗改为 Regular，字号仍为 13 pt。
双周期和数据逻辑不变。Build 7 / internal 36，视觉待验收，未发布。

## 0.5.1 Build 8：单周期 14 pt 常规字重

按用户最新要求，单周期状态栏和设置预览改为 14 pt Regular；其余文字排版、
双周期布局和真实数据逻辑保持不变。Build 8 / internal 37，未发布。

Build 8 全新 Universal Release 构建与真实数据开发启动通过；运行包为
`/tmp/quotaview-051-build8-real/QuotaView.app`，旧 Build 7 已退出。
真实数据错误为空。证据：`dist/verification/0.5.1-build8/result.json`。

## 0.5.1 Build 6：单周期恢复纯文字

用户认为上文下条效果不佳，要求恢复最初无进度条的文字版本，字号排版参考
相邻 CodexBar。单窗口恢复原生状态栏「剩余百分比 + 可选倒计时」，无周期
标签或进度条；使用 13 pt semibold，设置预览同步。双周期布局保持不变。
Build 6 / internal 35，真实数据开发，未发布，视觉待验收。

## 0.5.1 Build 5：单窗口上文下条

用户要求单窗口周期和百分比在上方，采用双窗口相同的 9 pt semibold 字体；
下方为与文字组合等宽的 4 pt 高单色横条。现按此实现，上方周期左对齐、
百分比右对齐，中间 8 pt；倒计时开启时仍位于右侧。双窗口和真实数据来源不变。
Build 5 / internal 34，视觉待验收，未发布。

## 0.5.1 Build 4：单窗口排版收紧

用户提供与 CodexBar 相邻截图，反馈布局松散、字号偏小。单窗口字号从
12 增至 13 pt semibold，图标到文字收紧 3 pt，各字段间距从 6 降至 4 pt。
百分比改按实际文字宽度布局，去掉为 100% 预留而出现在 9% 前面的空白。
数字位数变化允许状态项自然伸缩；双窗口保留原固定列布局。
当前身份为 Build 4 / internal 33，真实数据路径不变，未发布。

## 0.5.1 Build 3 开发

用户要求单窗口也显示周期、进度条、百分比与重置时间，其中进度条竖向。
现已实现单行横排：周期 + 5 × 16 pt 竖向单色条 + 剩余百分比 + 可选倒计时。
剩余额度自底部向上填充；百分比预留 100% 宽度。继续沿用额度、图标和倒计时
开关；缺失数据用 —，双窗口保持原布局。版本为 Build 3 / internal 32。
构建与启动证据见 `dist/verification/0.5.1-build3/`。未发布，视觉待验收。

## 0.5.1 Build 2 开发

2026-09-17 用户授权加入逐窗口重置时间。默认双行额度保持紧凑；Tooltip /
VoiceOver 始终提供两个窗口各自的倒计时；开启重置倒计时后在各行百分比
之后显示，关闭额度而保留倒计时时显示周期标签与各自时间。仅周窗口继续单行。
展开面板已使用各窗口自己的重置日期，保持该行为。菜单栏和设置预览每 30 秒
本地刷新时间，不增加额度请求；未知时间显示 —，到期显示待刷新 / Due。

App / Widget 为 0.5.1 Build 2 / internal 31。3 项局部冒烟测试与 Universal
Release 无签名构建通过，未运行完整回归。已启动独立 Build 2 Plus DEBUG 预览：
`/tmp/quotaview-051-build2-plus-run/QuotaView Plus DEBUG.app`，开启倒计时，
27 秒进程存活检查通过，旧 Build 1 预览已退出。未替换正式安装；生产源码无虚拟注入。
开发预览与视觉验收状态见
[MENU-QUOTA-022](docs/design/quotaview-menu-quota-0.5.1.md)。未发布、未获 appcast 准入。

### Build 2 切换真实数据

用户确认 Plus DEBUG 的双行与倒计时“目前看起来没啥问题”，随后要求取消
虚拟注入、接入真实数据。已退出 DEBUG 预览与正式版主进程，启动不含 Widget
的独立真实数据开发包 `/tmp/quotaview-051-build2-real/QuotaView.app`。
使用已验证的 Build 2 Release 产物，生产源码和临时预览源码均无虚拟注入。
本次启动后的真实额度刷新成功、共享快照 available，无记录错误；Codex 配置
指纹不变。正式安装和用户数据保留，未发布。证据：
`dist/verification/0.5.1-build2/real-data-launch.json`。
用户确认仅覆盖所看的 Plus DEBUG 场景，不扩大为全部外观或真实数据验收。

## 0.5.1 Build 1 开发

2026-09-17 用户授权以 0.5.0 Build 3 为基线启动 0.5.1，首项为菜单栏双行
单色额度快捷显示。修改前逐文件核对发布 tag 的 71 个生产源码与配置文件，
当前工作区内容完全一致；旧分支名与已有未提交工作保留。

[MENU-QUOTA-022](docs/design/quotaview-menu-quota-0.5.1.md)：图标右侧按 primary /
secondary 身份显示两行周期、单色进度条与剩余百分比；周期来自真实时长，
Plus 双窗口为 5h / 7d；Pro 仅周窗口时保持原单行百分比。布局依据真实
快照是否同时具有两个窗口，不凭订阅名推造缺失窗口。设置预览共用模板图片，图标和重置倒计时的现有开关继续有效。
App / Widget / 兼容配置统一为 0.5.1 Build 1 / internal 30。
两项菜单栏局部冒烟测试、Universal Release 无签名构建、App / Widget 版本与
双架构、资源及 diff 检查通过，未运行完整回归。证据：`dist/verification/0.5.1-build1/`。
随后用户授权虚拟 Plus 数据体验：已从当前源码复制独立 Debug 构建，启动
`/tmp/quotaview-051-plus-run/QuotaView Plus DEBUG.app`（独立 Bundle ID，未嵌入 Widget）。
显示 5h 90% / 7d 78%，界面与辅助文本带 DEBUG 标识；禁用预览的真实轮询、
更新与任务服务。正式源码无虚拟注入，正式安装保持原样。视觉等待用户验收。
构建与启动记录：`dist/verification/0.5.1-build1/plus-preview-*`。
未获发布与 appcast 准入。

## 2026-09-15 桌面小组件恢复

用户反馈额度显示异常。共享快照有效；旧 Widget 进程跨版本运行，实际仍映射
已被移除的 Sparkle 更新缓存文件，另有发布验证临时副本残留注册。
已归档并清理 `/private/tmp` 下 20 个未运行的 QuotaView 应用副本，注销临时
Widget、重新注册正式扩展并重启旧 Widget 进程。正式 App 保持 0.5.0 Build 3。
唯一注册和新进程均来自 `/Applications/QuotaView.app`，小号与中号时间线请求
成功；共享额度快照持续更新。用户随后确认“正常了”。
源码、永久开发台、正式安装和用户数据保留；未修改生产代码或公开发布资产。
可恢复归档、清理清单与验证证据：`dist/verification/widget-recovery-2026-09-15/`。
后续本机发布验证按[收尾检查](docs/workflow/RELEASE.md#本机验证收尾)执行。

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

2026-09-17 Build 3 验证：4 项局部冒烟通过，App / Widget Universal Release
构建及 0.5.1 / Build 3 / internal 32 身份核对通过。已启动真实数据副本
`/tmp/quotaview-051-build3-real/QuotaView.app`，旧 Build 2 主进程已退出。
本次启动后额度刷新成功；无虚拟注入，正式安装保留。视觉等待用户验收。
证据：`dist/verification/0.5.1-build3/result.json`。

Build 4：4 项局部冒烟、Universal Release、App / Widget 版本核对通过。
已启动 `/tmp/quotaview-051-build4-real/QuotaView.app`，旧 Build 3 已退出，
真实数据刷新成功。用户所附 Build 3 截图反馈已用于本次调整，Build 4 视觉待验收。
证据：`dist/verification/0.5.1-build4/result.json`。

2026-09-17 用户再次要求 Plus 虚拟数据：已启动独立 Build 4 DEBUG 预览，
路径 `/tmp/quotaview-051-build4-plus-run/QuotaView Plus DEBUG.app`。
5h 剩余 90%、7d 剩余 78%，倒计时开启；无真实额度轮询或 Widget 写入，
正式生产源码无注入。真实数据开发版继续保留运行，可通过 DEBUG 标识区分。

Build 5 验证：4 项冒烟、Universal Release、App / Widget 版本身份检查通过。
已启动 `/tmp/quotaview-051-build5-real/QuotaView.app`，旧真实数据 Build 4 已退出，
启动后的真实额度刷新成功。Plus DEBUG 对比副本保留，生产源码无虚拟注入。
视觉待用户验收；证据 `dist/verification/0.5.1-build5/result.json`。

Build 6：4 项局部冒烟、Universal Release、App / Widget 版本身份检查通过。
已启动 `/tmp/quotaview-051-build6-real/QuotaView.app`，旧 Build 5 已退出，
本次真实数据刷新成功。Plus DEBUG 对比副本保留；Build 6 视觉待用户确认。
证据：`dist/verification/0.5.1-build6/result.json`。

Build 7 Universal 构建、App / Widget 版本检查与启动冒烟通过。已启动
`/tmp/quotaview-051-build7-real/QuotaView.app`，旧 Build 6 已退出，
真实数据刷新成功；字重修改未重跑逻辑测试，视觉待确认。
证据：`dist/verification/0.5.1-build7/result.json`。
