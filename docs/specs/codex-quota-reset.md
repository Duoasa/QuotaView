# Codex 手动额度重置

Spec ID：`QV-CODEX-QUOTA-RESET-001` · `Accepted / Verifying` · 2026-10-27。

## 授权与范围

用户要求将 0.8.5 接入真实 Codex 重置接口，并明确不得消耗其本机重置卡。实现限灵动岛 Codex 重置页的手动操作；Claude 保留复制原生 `/limit-reset` 命令，旧菜单演示与自动重置不升级为真实操作。开发和发布验证只调用隔离的模拟服务，禁止通过真实按钮、探针或脚本调用本机消费接口。

## 行为与不变量

- 首次点击仅读取官方 `account/read`、`account/rateLimits/read`，展示本次确认；取消、进入页面、刷新、切换账户、重启和后台任务都不会消费。
- 使用现有本地 Codex App Server 和代理配置，不提取登录凭据、不模拟网页或直连内部 HTTP。旧 CLI 不支持方法时说明需要更新；有次数但无具体卡片明细时停止操作。
- 明细须为 `available`、`codexRateLimits`，具有非空 ID，且未过期；优先到期较早的卡。发送明确的 `creditId`，绝不让重试自动选另一张卡。
- 确认有效期 60 秒，绑定账户邮箱的本地 SHA-256、明确卡片 ID 和随机 UUID。发送前重新读取账户及卡片；账户变化、卡片变化、无次数或不可读时中止。账户邮箱不写入操作记录。
- 发出消费请求前原子保存操作 UUID、账户哈希与卡片 ID。存储不可用时不发送。并发点击互斥，同一确认不能重复执行。
- 调用官方 `account/rateLimitResetCredit/consume`。成功 `reset` / `alreadyRedeemed` 后重新读取额度，不在本地虚构 100% 或扣减次数；`nothingToReset` / `noCredit` 如实提示。
- 超时、断线、未知响应或结果记录清理失败保留原记录。应用重启后只显示待核对入口，用户重新确认后复用原 `idempotencyKey` 和 `creditId`；不后台自动重试。原卡已消费、当前次数为零时也能核对原操作。
- 隐私开启、切换来源、离开重置页或代理配置变化撤销尚未提交的确认。已经明确提交的操作继续等待结果并刷新，避免将取消等待误报成未消费。
- 提示经 `AppCopy` 支持中英文，操作区沿用深浅玻璃；确认卡保持深色。禁用态、未知态与真实执行反馈有独立文案。

## 依据与验证

- [官方额度与卡片明细](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)
- [官方消费接口与幂等语义](https://learn.chatgpt.com/docs/app-server#8-earned-rate-limit-resets-chatgpt)
- 本机 CLI 生成的请求/响应 schema 与文档一致；没有在真实服务上执行消费。
- `CodexRateLimitResetTests` 使用临时文件和内存模拟服务检查确认/取消、重复点击、超时后重启、账户及卡片变化、过期、无明细、存储失败和结果分支；`CodexAppServerClientTests` 使用明确指定的临时假进程检查 RPC 格式。发布结果见 [0.8.5 规格](release-0.8.5.md)。

真实业务扣卡与视觉体验留给用户验收，不以模拟成功替代真实服务的端到端验证。
