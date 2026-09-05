# QuotaView 0.4.6 Codex Token 兼容修复

> Spec ID：`QV-FIX-CODEX-TOKEN-COMPATIBILITY-015`
>
> 状态：`Accepted / Verifying`（链路重构和自动验证完成，用户已确认本轮视觉，准备发布）
>
> 开发版本：`0.4.6 Build 1`，Sparkle 内部 Build `18`
>
> 用户已授权修复及版本身份，并在实机视觉确认后授权 GitHub 发布和 appcast。

后续用户发现任务未结束时出现完成回执，要求完整逻辑审计。发布已暂停，
见 [审计报告](quotaview-activity-logic-audit-0.4.6.md)。此前常规测试和单一
四步任务的通过不覆盖跨线程、多来源和启动恢复问题；原公证候选不可直接发布。

## 范围与依据

继承 `TURN-TOKENS-03` 至 `TURN-TOKENS-09` 的计数、完成、布局及隐私约束。
本规格替代当前实现的 `TURN-TOKENS-01/02` 读取方式；0.4.5 规格保留发布历史。
已核对 Codex 0.153.3 协议及只读任务记录：线程累计值跨 turn 可能回落，
固定减去上一轮基线会少算或丢失本次 Token。新记录 `token_usage_record`
提供 `turn_id`、`turn_token_usage`、`usage` 与 `thread_token_usage`。

## Requirements

| ID | Requirement |
|---|---|
| `TOKEN-COMPAT-01` | 只接受当前活动 turn 的 `token_usage_record`，线程/turn 标识哈希比对；优先采用 `turn_token_usage.total_tokens`，仅投影整数及哈希，不保存 response ID、正文或工具输入输出 |
| `TOKEN-COMPAT-02` | 同一 turn 一旦收到直接汇总，旧 `token_count` / Socket 累计值不得覆盖它或重复相加；直接汇总按最大已知值去重，第一次权威值可以纠正回退估算 |
| `TOKEN-COMPAT-03` | 旧格式继续支持累计差值，累计回落时重建分段基线并保留同 turn 已计算量；乱序、负数、布尔、小数及溢出值不污染状态；终态后冻结，旧 turn 不覆盖新 turn |
| `TOKEN-COMPAT-04` | 启动恢复保留活动 turn 的最新直接汇总；即使缺少 ordinal、夹有旧格式、压缩记录或上下文切换，计数仍可恢复；历史终态不得重放 |
| `TOKEN-COMPAT-05` | 本地主通道只按结构化 `ContextCompaction` item 开始/完成映射已有压缩状态，不读取正文、不扩大 Socket 内容订阅；`compacted` 与 `new_context` 不构成新 turn 或成功完成 |
| `TOKEN-COMPAT-06` | 异步提问是非阻塞调用，不能仅按工具名触发 awaitingConfirmation 或完成；保持既有真实等待状态的 10 秒提醒 |
| `TOKEN-COMPAT-07` | App、Widget、兼容 plist 为 0.4.6 / 产品 Build 1 / 内部 18；正式发布完成后同步 Latest、README 下载、Release 与 appcast |

## 非目标与降级

不新增待答问题 UI、不更改岛体/主额度/订阅、不启用实验配置、不迁入 Kimi 或
多任务预览、不写 Codex 数据、不重新定义 token 为账单成本。无有效直接汇总时
保留旧格式回退；没有完整活动 turn 证据时不凭 Token 记录复活历史任务。

## 验收

- 脱敏 fixtures 覆盖 151228 被旧算法算为零、1003450 被少算的累计重置场景。
- 覆盖直接/旧格式混合、重复、非法整数、旧 turn、终态后更新和无 ordinal 启动恢复。
- 压缩和上下文切换保留 turn、Token 与计划；异步问题不触发等待/完成。
- 完整 swift test、Universal Release 无签名构建、版本/架构/资源、diff 检查。
- 本轮实机视觉由用户确认；未覆盖的完整辅助功能交叉矩阵不标记通过。

## 审计后重构验证（2026-09-05）

按 [链路审计](quotaview-activity-logic-audit-0.4.6.md) 重构了统一类别准入、
任务身份、终态接纳、展示选择和渲染绑定。Hook / 本地日志 / 共享服务经过一致
的状态接纳层；后台 Stop 不抢占展示，Goal 完成不结束 turn，重复开始不清进度。
旧 Token 恢复保留全部数值分段、按实时算法批量归并，只通知界面一次。

本地 166 项测试和 Universal 构建通过。真实 guardian 隔离、后台任务 Stop 和
四步计划已验证；完整证据与兼容边界见 [重构验证记录](quotaview-activity-refactor-verification-0.4.6.md)。
用户已确认本轮真实五步任务视觉无问题；旧签名/公证候选不可用于发布。

## 审计前验证历史（2026-09-05，不能替代本轮验收）

- `swift test`：140 项通过、0 失败，包含本轮新增 10 项兼容回归。
- 直接汇总修正 151228 与 1003450 两个数值案例；覆盖旧格式分段回落、
  重复与乱序、整数边界/累加溢出、迟到旧终态、完成冻结和新 turn 隔离。
- 启动恢复覆盖无 ordinal、直接与旧记录交错及历史完成不重放；
  ContextCompaction、compacted、new_context 与异步问题保持正确 turn 语义。
- Universal Xcode Release 无签名构建成功；App、Core、Widget、Activity Hook
  均为 `x86_64 arm64`。App/Widget 为 `0.4.6 / Build 1 / internal 18`。
- `AppIcon.icns`、App 与 Widget `Assets.car` 均完整；未新增资源。
- `git diff --check` 通过，生产 Sources 无临时虚拟值、截图、自动展开、自动点击
  或 UI QA 入口。沿用既有布局、本地化、额度不可用占位与等待提醒规则。
- 构建日志：`/private/tmp/quotaview-046-build.log`；测试日志：
  `/private/tmp/quotaview-046-tests.log`。构建产物：
  `/private/tmp/quotaview-046-release/Build/Products/Release/QuotaView.app`。
- 已启动 0.4.6 本地副本，使用 Codex CLI 0.153.3 运行真实四步任务；四次
  `sleep 6` 全部成功。仅测试进程启用计划工具并关闭 Hook，运行中的应用通过
  本地任务流收到 5 次计划更新和 1 次真实成功终态。
- 以同次 Release Framework 解码本次记录，进度依次为 2.5%、27.5%、52.5%、
  77.5%、95%；本轮相关定向检查 24 项通过。数据链路验证不代表无结构化计划
  的普通任务具有真实步骤百分比，也不改变当前 Desktop 会话的工具配置。
- 用户于 2026-09-05 确认视觉无问题并授权正式发布。签名、公证、Release 与
  appcast 的最终证据将在发布完成后回填，历史版本记录保留。
