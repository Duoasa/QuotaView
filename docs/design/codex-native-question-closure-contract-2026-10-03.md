# 原生异步提问框关闭：接口调查与 AX 最小合同

状态：**方案与隔离夹具；生产 AX 桥未启用，原生框关闭仍未完成。** 2026-10-03。
范围为 Codex Desktop 26.928.40906 / Build 12694 / `com.openai.codex`，不把 CLI 版本或后续 Desktop 更新混为同一接口契约。

## 本轮结论

在当前安装包、公开 App Server 文档与现有可调用工具中，未建立“按原始异步问题组身份提交并关闭”的接口路径。现有 API 能送达答案并得到精确接受证据；原生窗口还需要 renderer 本地状态变化。不能因 Vibe 缺少公开源码或字面字符串未命中断言它不能解决；当前缺的是同一种异步分支成功的可核实证据。

本轮不增加生产响应路由或猜测型 AX adapter。隔离合同只输出模拟意图，不访问实际应用；不会将夹具中的虚拟身份/租约当成系统已提供的能力。

## 支持的生命周期与已排除路径

公开 [App Server 协议](https://learn.chatgpt.com/docs/app-server#toolrequestuserinput)把 `serverRequest/resolved` 绑定到真实 `item/tool/requestUserInput` 的 `{threadId, requestId}`，包括回答和真实轮次开始/结束/中断时的清理。[API 总览](https://learn.chatgpt.com/docs/app-server#api-overview)中的 `turn/steer` 只承诺将输入加入在途轮次并返回接受的 turnId；没有把 renderer 异步提示关闭作为返回语义。公开协议不能代替本机 Desktop 私有 owner/follower 的具体行为。

| 已核查入口 | 具体行为 / 证据 | 为什么不能用于本问题 |
|---|---|---|
| 同步 `thread-follower-submit-user-input` | owner 的 `replyWithUserInputResponse` / `applyUserInputResponse` 从 `conversation.requests` 校验、移除真实 RPC；shared 2656518 / 3108487 | 异步三元组不是 pending requestId，伪造 resolved 会混淆请求 |
| `replyWithOptionPickerResponse` / 动态工具响应 | 同步 picker 或 onboarding/environment 响应；shared 2657468 / 3108487 | 不能接收异步 questionItemId，不用于关闭 async selection |
| `serverRequest/resolved` / user-input 自动解决 | 更新同步 RPC 和系统通知；initial 9564288 / 9604300 | 通知隐藏不等于 async widget 清理，不能发假超时或完成 |
| 异步 `thread-follower-steer-turn` | owner 只执行 `manager.steerTurn`；shared 2682164 | 没有执行 renderer 的本地清理 |
| 原生异步 `Bqe` 提交 | 发送原 tuple/原问题/答案，成功回调另执行 `Iqe`；primary 491650 / 492473，Iqe 487915 | 回答与关闭是两个动作；外部 ACK 不能当关闭证明 |
| accepted reply 投影 `iPt` | 更新 lastSubmission、draftBaseline，保留已经修改的草稿；initial 1303790 | 已接受答案并不自动清 selectedQuestion |
| 内部问题通知导航 | `{hostId,threadId,entityKey,itemId}` 的内部 route state 生产/消费；initial 9600841 / 10025286 | 未发现外部可调用的同组关闭入口；深链导航也没有选题身份 ACK |
| `completeRequest` / `cancelRequest` 同名字面量 | 分别落在 thread 构造器、认证网络取消中 | 不是问题完成或取消协议 |
| turn 完成 / 问题实体移除 | 会导致相应 renderer 状态清理 | 必须来自真实生命周期；不能中断、删除、compact 或改写任务来消除框 |
| App 导航/打开面板工具 | 可打开线程、文件或面板 | 当前工具描述没有按问题组 dismiss/respond 控制；导航成功不是题目选中证明 |

上述位置是 `/private/tmp/quotaview-desktop-ipc-readonly/` 的当前安装版本静态源解码后字符位置：`app-primary-fc3cefe64ba8.js`、`app-initial-27bc4044d9e8.js`、`app-shared-360504a28a87.js`。不是稳定公共 ABI。已核对本机安装版本和来源 bundle；静态证据不等于运行期动作验证。

提取源 SHA-256：primary `d3a4a112b9ba0ba2658cc6291016a214fdd6aa749c29577ea52f97a87b928544`；initial `712ac9f965de1a4c9cb75ae1c149cf25747da8056b8c32039dc1e2c43e3dc124`；shared `297c44bb873f07774cf3465fdde01f7ae88eb8974702cceb7c9f57cc754a6e4d`。

## 关闭的单位是完整 renderer 选题组

原生选择结构是 `selectedQuestionKey: {hostId,threadId,entityKey,itemId}` 加 `questionIds: [nativeQuestionItemId...]`，每题状态另含 `turnId/deadlineMs/draft/draftBaseline/lastSubmission/isSubmitting/isSkipped`。

`aPt`（initial 1304903）会把同一 entity、同一轮次后来的问题追加到当前 `questionIds`，可跨多个 agentMessage；`oPt` 从通知打开时可以改为单题。`dPt`（1306577）按选中 entityKey/itemId 检查后调用 `rS`（1307133）清除线程的整个 selectedQuestion。当前结构没有已证明的外部 selection generation、lease 或 CAS API。故一个 nativePending 已回答不能证明可以关闭整个面板。 所选 `itemId` 必须是该组 `questionIds` 中的规范 native ID；非空字符串、相同成员集或相同 generation 均不能代替这个绑定。

`data-request-input-dismiss` 同时用于异步 Skip（primary 484307）：末题存在其它草稿时可提交那些答案。纯关闭路径是 `onMinimize → onClose("user") → $$s → dPt → rS`。不能按这个 data 属性泛选按钮，也不能用 Skip、Next、Send 或通用 Escape 代替。

`data-conversation-id` 仅发现于主 composer textarea，不含 turn/item/group，data 属性也不保证映射到 AXIdentifier。窗口标题、题目文字、部分可见选项和线程 deep link 均不足以证明原生组身份。

## 最小 AX 方案

优先保持一次 owner/follower API 答案提交；AX 仅尝试已核实的纯关闭，永不选择选项、编辑输入或再 Send。原生选项可能约 180 ms 后自动发送，所以“AX 选择后再确认”存在重复提交，固定延时不是同步协议。

三个结果分开：`delivered` 是 ACK，`answered` 是同作用域原生身份的精确接受证据，`rendererClosed` 是该选题组确实消失的新观察。API submit 前先 reservation/sendStarted；超时、断连或结果未知禁止自动重发和自动换 AX 路由。

关闭许可需要同时具备：

1. 用户明确启用此兜底，QuotaView 已获辅助功能权限。默认不请求、授予或打开权限页面；拒绝/撤销时保持原 API 与明确原生处理入口。
2. 绑定 app bundle/build、process incarnation、owner、connection epoch、host、conversation、turn、entityKey、所选原生 questionItemId，以及**完整有序组成员**。每个成员保存其 source/index/native ID 与内容哈希；不把整个组误归为单一 sourceItem。
3. 当前 AX element/window 身份、完整组和草稿来自可信且新鲜的实际观察；每个组成员都已精确接受，全部草稿与最后接受基线相等，没有未提交内容、后台提交或未知成员。resource_limit 撤销后的旧描述不能替代新鲜证明。
4. 只有明确 pure Dismiss 的目标元素可候选；动作前再次核对作用域、组、元素 generation 和草稿。不关闭并行线程或后加入的题目组，不用近似文本匹配。
5. 读取到执行之间还需能使同组关闭具有事务性保护的 lease/CAS，或等价且已证明的原生条件动作。**当前未发现这种能力。** 两次读取不消除用户编辑或新题在最后时刻到达的 TOCTOU；没有证明时返回 handoff，不自动 press。夹具中的 exclusive guard 是未来合同的虚拟前提，不是当前接口。
6. 关闭意图和结果未知的账本按作用域留存，不重复 press、不再次送答案；只有新观察精确证明同组被移除才进入 rendererClosed。命令返回成功、窗口切走或查不到元素均不算关闭成功。

该设计允许将来开发 AX adapter，但当前缺少组身份、草稿和事务性证明，不能靠“有 AX 权限”自动补齐。允许的当前回退是用户在 Codex 原生界面自行关闭已回答提示；不是自动再次提交。

## 隔离夹具与生产隔离

合同原型位于 `Prototypes/NativeQuestionBridgeContract/`，不在 App、Core、Swift Package 或 Xcode 生产 Target。纯 Python 标准库，只有合成数据和模拟 effect；没有网络、AX/TCC、剪贴板、系统权限提示、实际 App 读取或真实任务动作。测试证明缺条件拒绝、精确绑定、一次提交与三个状态的区别；不能证明真实 AX 树会提供这些字段，不能证明实际框关闭或消除 TOCTOU。

必要场景涵盖权限未配置/拒绝/撤销、ACK 与接受分离、结果未知/重复 Confirm、owner/epoch/process/build/线程/轮次变化、同文字不同身份、部分已答组、跨 source 新题追加、隐藏题草稿变化、完整组证明缺失、pureDismiss 与 Skip 混用、执行前重校验、并行组独立、迟到回调、关闭成功/未知与不同作用域观察。最终 44 项 synthetic 冒烟全部通过，0 失败、0 真实操作（Python 3.9，0.012 s）；专用 CI 步骤只运行该夹具。实际关闭仍未验证。

## 实际工具限制及适用范围

本会话 2026-10-02 23:43:41（Asia/Shanghai），`cua.getApp("com.openai.codex")` 实际返回：

> Computer Use is not allowed to use the app 'com.openai.codex' for safety reasons.

原始记录为本会话 rollout 的 9844/9847 行，提取证据 `.build/073-native-question-tool-boundary.json`。这是该工具针对 Codex 界面访问的实际限制：本代理不能经它继续读取/操作此 App，也不以 shell AX、JXA、osascript、CGEvent、改应用数据或另一 App 名绕过。该限制不等于整个产品不能开发 AX，不禁止静态源码分析、写 QuotaView 代码/合同或运行不访问真实 App 的夹具。辅助功能系统许可与代理运行期工具许可是两层不同约束；前者授予后不自动解除后者。

本轮没有重新尝试 Codex UI，没有请求或更改系统权限，没有处理真实问题、消耗重置卡、购买额度或发布 Release。

## 必须停止并等待人工验证的边界

当前停在真实 AX adapter 读取/按键之前。后续实际验证需要：

- 用户明确选择启用兜底，并自行在 macOS 辅助功能里授权**实际签名/身份的 QuotaView 包**；不能用别的应用权限代替，也不以 Screen Recording/Automation 扩权兜底。仅授权仍不足以开始自动关闭。
- 在工具政策允许的执行环境，由人操作受控测试会话采集实际 AX 字段；证明可精确获得 selectedQuestionKey、完整原生组、当前轮次、成员身份、完整草稿基线与元素生命周期。若没有，adapter 保持拒绝，不能把可见文案升格为身份。诊断仅保留身份/内容哈希、缺字段标记与版本计数，不落盘答案、草稿、整窗 AX 内容或截图。
- 建立并证明同组动作的事务性保护；当前缺失，不默认存在。否则只能保留手动原生关闭，不能用两次读取声明安全自动关闭。
- 在专用测试任务手动验收：选择/自填仅保存，确认只送一次；Codex 收到正确原身份、全组已答且框消失；并行/追加问题与新草稿不被关闭；撤权、重启、换轮次、迟到/未知结果不会误点或重复发送。不得自动回答任何真实用户任务。

权限和手动验收尚未进行，原生异步框关闭不记录为完成；夹具通过、CI 或源码合并不能替代这一结论。

## 交付与已有 main 核验

PR #70 合并提交 `9e67f2bde7a8a31d981e5e21e6a1cf1bfdb4ad8c` 的 [postmerge push CI](https://github.com/Duoasa/QuotaView/actions/runs/37073125800)已只读核验：head SHA 完全一致，completed/success，508 项测试、6 项跳过、0 失败。证据 `.build/073-question-presentation-postmerge-ci.json` 和 `.log`。此前 203 项本地冒烟、运行包与修复内容不重复验收；本轮未修改生产源码或替换运行包。

本轮隔离合同：`python3 Prototypes/NativeQuestionBridgeContract/smoke.py`，44 项、0 失败、`REAL_ACTIONS=0`。fixture 仅有 `policy.py`、`smoke.py` 和 `README.md`，其 CI 步骤不引入生产 target。没有生产输入修改，故不重复构建或替换上轮已验证开发包。
