# Codex 异步提问生命周期与显示梳理 · 2026-10-03

本轮处理用户截图中的旧提问长期停留、自行输入与选项难以区分、问题标题错位，以及无物理刘海时收起标题左侧裁切。答案送达、请求已回答和 Codex 原生框关闭分别记录；当前仍未实现或验证原生异步框关闭，不能将本轮提交描述为三个阶段全部完成。

## 根因与模块边界

| 阶段 | 当前证据与行为 | 不能据此推断 |
|---|---|---|
| 答案送达 | Desktop owner/follower steering 的 ACK；本轮不改变该提交路由 | ACK 不代表原始问题已回答或界面已关闭 |
| 精确问题已回答 | 原生接受的回答包含同一 questionItemId 与原问题；本地 rollout 仅发布两项哈希 | 不生成提交能力，不清理其它问题、同步 RPC 或匿名等待 |
| Codex 原生框关闭 | 原生 renderer 提交成功后另行清理 selectedQuestion；外部 steering 没有执行该清理 | 当前未实现或验证；不能用第二次提交、Skip、伪造结束或改写任务数据代替 |

现有 Desktop 完整快照超出预算时只撤销该会话的响应能力，但旧详情会保留。该会话已有精确接受的原生回答时，本地读取此前没有公开此项结算证据，于是回答后只读提示仍留在灵动岛。上下文压缩不是“已回答”的证据；界面收起标题裁切则来自左侧隐形统计占位，两者需要独立修正。

`CodexLocalPublicContent` 新增的回答结算分支仅接受 `response_item/message/role=user` 的单段完整原生回答包装。原生 questionItemId 必须与规范三元组编码完全相等；该分支只发布问题与身份的 SHA-256 哈希，不再次公开答案或原问题明文，普通用户消息继续排除。既有原问题/选项与 assistant 公共内容仍用于展示；答案不进入显示或日志。数量、字节、索引与标量类型均有界；畸形、重复或不完整条目整体拒绝。

`IslandLiveStore.RequestLifecycle` 只结算当前任务、当前轮次中已经观察到的异步问题：原生身份与原问题哈希同时相等。本地多问题组必须全部精确回答才移除；未观察的回答不能创建未来解决标记，不从相似文字映射不同来源 ID。部分已回答的活动组保留其证据，另保留最近 256 项已结束证明用于重复快照防重播；这是有界窗口，不承诺任意历史身份永久去重。同步请求、匿名等待和运行时压缩状态保持独立，观察结算不调用响应路由、不提升只读能力。

## 界面修正

- 问题编号与标题按首行基线对齐；可选 header 单独位于标题列，标题右侧的输入/完成指示器移除。高度测量同步使用实际编号、间距与标题可用宽度。
- 自行输入去掉笔图标、选项圆圈与勾选标记，使用高于选项背景的输入表面与焦点反馈；秘密字段的锁语义保留。选项、自填互斥与草稿保持沿用现有入口，选择与编辑不提交，显式确认才发送。
- 无物理刘海的收起布局移除左侧隐形统计副本：短标题仍对整个灵动岛居中，长标题使用 Orb 到真实统计之间的可用空间与既有滚动文本控件。压缩与待确认的辅助功能语义使用同一实际状态。

## 原生关闭与 Vibe 证据限制

本机 Codex Desktop 26.928.40906（`com.openai.codex`）的异步 `agentMessage.questions` 与同步 `item/tool/requestUserInput` 是两种请求。异步原生提交发送 `<send_user_message_question_reply>`，成功后 renderer 还执行本地 selectedQuestion 清理；当前 follower owner handler 只执行相同答案发送。外部已接受的回答更新原生提交/草稿基线，但不会执行这一界面清理。因此已收到答案不能作为原生提示消失的验证。

现已检查 owner/follower 方法、原生导航与关闭分支：`serverRequest/resolved` 和 user-input 自动解决事件服务于同步 RPC，不能拿异步 questionItemId 冒充。真实 turn completion 或问题失效可以关闭，但不能为消除提示伪造这些状态。深链可打开线程，没有已证明的公开“关闭指定异步问题”方法。原生纯 Dismiss 不再次发送答案，但关闭的是所选整个问题组，不能在没有同一线程/问题组身份及其它未答草稿证明时按标题或按钮猜测点击。

原版 Vibe Island 1.0.51 的本地静态符号包含 QuestionTransport、选项/自行输入脚本、页面探测和 AX 辅路；[官方更新记录](https://vibeisland.app/changelog/)描述 Codex 提问支持。官方 [社区仓库](https://github.com/vibeislandapp/vibe-island)不提供产品实现源码；其中 [Issue #241](https://github.com/vibeislandapp/vibe-island/issues/241)（2026-09-24，目前 Open / enhancement / triage）报告新式会话内到期提问尚未接入。报告没有原生类型或版本、没有维护者结论；本地二进制亦没有找到 async 标签/身份字面量。这些证据不能证明 Vibe 支持并关闭同一种 Desktop 异步框，也不能仅靠字符串缺失断言绝对不支持。同步 RPC 的支持不作为本场景成功证据，本轮核查已自主完成可用的源码、文档和本地静态范围。

静态定位证据保存在 `/private/tmp/quotaview-desktop-ipc-readonly/`，与已安装 Codex bundle 核对一致：`app-primary-fc3cefe64ba8.js` 的 Iqe 位置 487915 和 Bqe 成功回调 491460–492884，`app-shared-360504a28a87.js` follower steer 2682164，`app-initial-27bc4044d9e8.js` 的 dPt/rS 1306577/1307133。位置按解码后字符串计，属于当前安装版本的本地调查证据，不是稳定 API。Vibe binary 的 `thread-follower-submit-user-input` 与 `item/tool/requestUserInput` 字符串分别位于字节 24476928/24476976；脚本符号不能证明其选路或真实执行结果。

未请求或启用系统权限、未自动回答真实请求、未注入或修改 Codex、未实现猜测身份的界面桥接。当前工具明确禁止控制 `com.openai.codex`；不通过其他工具绕过该限制。当前源码合并仅覆盖本节之前的安全修复，原生异步关闭作为明确未完成项保留。

## 后续原生关闭合同 · 2026-10-03

已继续完成可用接口调查与 [AX 最小合同](codex-native-question-closure-contract-2026-10-03.md)，包含同步/异步排除证据、完整 renderer 问题组边界、Skip 非纯关闭、逐字工具拒绝和其运行期范围。隔离夹具不读取实际应用；产品 AX 可开发，但当前缺组身份/草稿和事务性动作证明，实际桥接依赖权限/人工验证前停止，不能宣称原生框关闭完成。PR #70 合并后的同 SHA push CI 37073125800 已确认成功，508 项测试、6 项跳过、0 失败。

## 验证与已运行包

203 项必要隔离冒烟通过（0 失败），包括生产问题草稿入口、真实 Unix socket 夹具、并行与旧轮次请求、只读精确回答结算、容量边界以及 NSHostingView 文本布局。展示基准 P95 4.598 ms。Host 尺寸与实际紧凑标题控件 frame 验证不代替像素、基线和真实点击验收。

最终 Debug arm64 构建、资源/固定身份、deep strict ad-hoc 签名通过；181 项构建输入指纹与已运行包一致。开发包路径 `dist/development-0.7.3/QuotaView 0.7.3 Development.app`，交付时 PID 75451，替换旧开发实例 94157；身份保持 0.7.3 / 显示 Build 1 / 内部 49 / `com.quotaview.development073`。

证据：`.build/073-question-presentation-smoke.log`、`.build/073-question-presentation-build.log`、`.build/073-question-presentation-inputs.json`、`.build/073-question-presentation-delivery.json`。首轮新增夹具缺显式 self 的编译失败及修正记录保留；最终源码通过后冻结。命名本会话的只读 rollout 核对记录 `.build/073-question-presentation-rollout-evidence.json`，确认旧同身份答案已记录，不保存答案；不作为原生提示消失证明。

本地不扩大完整回归、不替用户处理真实确认，视觉和真实交互待用户验收。本轮安全修复源码提交 `f828264e8af7dfab06fcc1da5cf953174541348f` 已推送至 [PR #70](https://github.com/Duoasa/QuotaView/pull/70)。用户已授权对应提交 CI 通过后合并 main；CI 与最终 main 集成状态以该 PR 为准。203 项本地验证与已运行开发包单独记录，原生异步提问框关闭仍未完成。 先前 PR #69 不包含本轮修复。没有发布 Release/appcast、使用重置卡或购买额度。
