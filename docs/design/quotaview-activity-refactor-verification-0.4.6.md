# QuotaView 0.4.6 任务逻辑重构验证

日期：2026-09-05。开发身份：0.4.6 / 产品 Build 1 / 内部 18。
状态：本地重构与自动验证完成；本轮真实五步视觉已获用户确认，已随 0.4.6 发布。

依据：[审计报告](quotaview-activity-logic-audit-0.4.6.md)。
当前工作区与发布入口：[HANDOFF](../../HANDOFF.md)。
公开版本事实：[VERSION_HISTORY](../../VERSION_HISTORY.md#当前最新版本)。

## 行为契约

`执行单元类别 → (session, turn, legacy generation) → 事件接纳 → 单任务状态 → 展示选择 → 渲染身份`

1. 内部审核及其他 subagent 执行单元不是用户主任务。SQLite、目录发现、共享
   通知和 Hook 均经过类别判断；内部任务不能抢占岛体或产生用户完成回执。
2. 当前展示与后台状态独立。后台 Stop / SessionEnd 不改变当前任务的展示、
   动画、提醒或收起计时；相同 session 的旧 turn 也不能结束新 turn。
3. 只有匹配当前 turn 且满足来源权威要求的终态才可结束该 turn。
   权威顺序为 localRollout > appServer > Hook；强来源已建立的 turn 不会被
   较弱来源 Stop 提前结束。SessionEnd 表示会话关闭，不表示任务成功。
4. Goal 完成与 turn 完成不同。计划全完成仍封顶 95%，等待 turn 自己的成功终态；
   缺少 turn 的迟到等待消息不会复活已结束任务。
5. 相同已知 turn 的重复开始保持计划、Token 和等待状态。带 event ID 的重复
   投递去重；旧 Hook 没有 turn ID 时，以显式新提示和本地 generation 区分轮次。
6. 同一任务内进度继续平滑；切换 session 或 turn 时重置生产进度投影和完成动画。
   渲染不能只靠 visualState 变化识别新任务。
7. 启动恢复使用实时 Token 聚合规则，保留完整数值分段后批量发布一次。
   100 → 400 → 100 → 150 的恢复结果为 550，直接汇总继续优先。

## 自动验证

- `swift test`：**166 项，0 失败**。
- 9 个原始审计场景保留在 `CodexActivityOwnershipTests`，行为断言全部通过。
- `CodexActivityTaskContractTests` 覆盖三来源准入、内部类别、未知类别兼容、
  无身份/弱来源终态、跨任务进度重置、跨来源时间、缓存淘汰、Hook 元数据、
  本地回调内停止重启、重入轮询、符号链接、共享通知、超长行、恢复通知次数、
  共享 Token 非法数值，以及共享停止回调内重启。
- 旧完成/收起测试补充合法开始前提，原有完成、提醒、收起与 Token 数值断言
  保持；无 turn 的事件不再被当作新 turn 的充分证据。
- Universal Release 无签名构建通过；App、Widget、Core 和 Hook 为
  `x86_64 arm64`。App / Widget：`0.4.6` / `18`，正式图标及 Asset Catalog 完整。
- `git diff --check` 通过；没有新增虚拟值、自动展开、点击或截图入口。

本机证据：

- `/private/tmp/quotaview-046-refactor-tests.log`
- `/private/tmp/quotaview-046-refactor-build.log`
- `/private/tmp/quotaview-046-refactor-release/Build/Products/Release/QuotaView.app`
- `/private/tmp/quotaview-046-refactor-signed-smoke/`
- 当前运行的最终本地签名包：`/private/tmp/quotaview-046-refactor-reviewed/QuotaView.app`。
  Developer ID / Team `BUUH229D5Q`，保留正式 App Group 权限；仅本地验证，未做本轮公证。

## 实机证据

- 16:21:57，另一用户任务 `a7dfba8e855f` 的 Hook Stop 和本地 Stop 到达，
  均未抢占仍在运行的主任务 `1385faaefb21`；日志标记 `task_ignored`。
- 真实内部审核 `9f0ca6d714de` 在主任务运行期间多次启动并结束，包括
  16:25:53、16:26:16；新应用未将其投递到展示状态。主任务持续接收工具活动。
- Developer ID 验证包运行真实 Codex CLI 0.153.3 四步任务，四次 `sleep 6`
  均 exit 0。用户任务 `df43719409ab` 在 16:32:35、16:32:48、16:33:02、
  16:33:16、16:33:31 的五次计划均实际 `task_applied`，16:33:35 的自身
  成功 Stop 也实际 `task_applied`。此后仅补充停止回调内重启的代次保护，新增
  回归使总数达到 166；最终包重新构建、签名、启动并确认实时主任务回执正常。
- 计划进度由同次生产 Framework 解码验证为 2.5%、27.5%、52.5%、77.5%、95%，
  成功终态由 Store 投影为 100%。未把普通无计划任务称为精确步骤进度。

实机过程中，ad-hoc 临时包曾阻塞在 Widget 共享容器的原子写入，主线程堆栈
为 `CodexStatusStore → QuotaViewWidgetSnapshotWriter → Data.write → open`。
换成既有 Developer ID 与 App Group 权限后实时回执恢复；未修改 Widget 业务
或放宽系统权限。该次受阻四步运行不计为通过，以上记录来自重跑后的签名包。
本地签名包只用于验证，未进行本轮正式公证和发布。

## 保留边界

- 展示选择仍为“最近活动的用户主任务”，不是 Codex 当前窗口选中任务。
- 旧环境缺少类别元数据时保留有限兼容；未知流不能抢占已确认用户任务。
  元数据未知不是用户类别的强证据，也不能把弱来源终态升级为原生终态。
- 本地单次增量读取最多 1 MiB，启动尾读最多 16 MiB；最多跟踪 128 个 session，
  发现和共享线程元数据最多 1024 个候选。超出读取窗口、缺少活动 turn 开始
  或缺少可信终态时，不猜测成功。没有新的进程存活证明接口。
- 自动化和日志证明数据链路；视觉、材质、交互与辅助功能交叉矩阵仍由用户验收。
- 审计结束时，0.4.6 尚未提交本轮重构、推送/合并、创建 tag/Release 或更新 appcast。
  之前已公证的审计前 ZIP 作废为本轮候选；本次发布已重新打包、签名、公证。

## 产品所有者验收与继续发布（2026-09-05）

用户要求在五分钟内执行包含不同状态的真实多步任务，且以真实终态结束。
验收任务读取目录、通过 apply_patch 创建数字文件、用 Python 计算并断言
sum=21 / count=3、写入报告；计划全部完成后实际执行 `sleep 12`，成功后才
产生真实 turn 完成。应用接纳 5 次计划更新和 1 次真实成功 Stop，所有命令成功。
证据：`/private/tmp/quotaview-acceptance-5min/verification.json` 与 `app-receipt.log`。
用户明确回复“我这边没问题，继续之前的推送”。本轮思考、执行、文件编辑、
计划进度与完成回执视觉验收通过。等待确认与上下文压缩本轮未自然发生，
不扩展为这两项或完整辅助功能矩阵已通过。

此前“未推送/未发布”描述记录审计阶段边界；最终发布状态以 VERSION_HISTORY
和 HANDOFF 的联动记录为准。

正式发布已于 2026-09-05 完成：PR #45 合并，GitHub Latest、回下载公证包与
公开签名 appcast 均核验通过。完整资产、提交和签名证据见
[VERSION_HISTORY.md](../../VERSION_HISTORY.md#当前最新版本)。
