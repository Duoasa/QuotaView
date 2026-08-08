# QuotaView — OpenAI 授权申请历史记录

状态：`Closed / Rejected by Provider / Do Not Send`

OpenAI Support Case：`12874203`

## 结论

2026-08-08，OpenAI Support 明确回复：Support 无法为 QuotaView 这类独立
第三方原生 macOS App 配置、授权或批准专用 ChatGPT/Codex OAuth Client 或
自定义 redirect；个人 ChatGPT/Codex 套餐额度、Credits 与用量也没有面向
独立原生 App 的通用第三方 OAuth 权限流。

原申请提出的 `quotaview://oauth/openai`、Authorization Code + PKCE、专用
Client ID 和只读个人额度接口因此没有获批路径。候选授权失败 Request ID
`a5578bad-b242-4a5c-bd80-e0d45abdc0cd` 也不构成批准证据。

本文件仅保留为产品决策记录，不得继续作为待完成 Release 门禁、审核授权
证据或可发送申请模板。

## 已执行的产品决策

QuotaView App Store 1.0.0 已：

- 删除自有 OpenAI OAuth、回调、Keychain Token 和账号页；
- 删除候选 `wham`/非公开 HTTP 用量端点及 Network Client 权限；
- 不读取浏览器 Cookie、`~/.codex/auth.json` 或其他 App 的 Keychain；
- 不复用 OpenAI/Codex 第一方 Client ID；
- 改为由公开 QuotaView for Codex 插件调用官方本机
  `codex app-server` 的两个只读方法；
- 只向 QuotaView 暴露字段白名单、无凭证和无身份标识的本地
  `usage.json`；
- 保持 QuotaView App 只读消费用户所选目录，自身不联网、不启动
  `codex` CLI/app-server；用户可显式打开官方 GUI App。

当前实施规格见
[官方 Codex 用量快照桥](../design/quotaview-app-store-codex-usage-snapshot-bridge.md)。

## Support 回复的产品含义

- “Sign in with ChatGPT”不自动允许第三方读取会话、文件、Token、账单或套餐
  用量；额外数据需要受支持的权限流；
- Codex CLI 的 ChatGPT 登录只说明官方 Codex 产品的支持路线，不表示独立
  原生应用可以注册自己的客户端；
- Apps SDK / MCP 面向 ChatGPT 内部 App，不等同于独立 macOS 菜单栏工具；
- OpenAI API 项目和计费是另一套开发者产品，不能替代个人 ChatGPT/Codex
  套餐额度。

## 仍然存在的审核风险

Support 的拒绝回复证明旧 OAuth 路线不可用，但不自动授予 QuotaView 对
Codex 数据或品牌的商业展示权。App Store Connect 的 Content Rights 以及
Apple Guideline 2.5.2 / 5.2.2 仍需如实说明并由 App Review 最终判断。

## 禁止回退

不得恢复或改用：

- `quotaview://oauth/openai` 或第一方 OAuth Client ID；
- `chatgpt.com/backend-api/wham/*`；
- Cookie、网页解析、WebKit 登录、`~/.codex/auth.json`；
- 外部 Keychain、API Key 冒充个人套餐用量；
- 包内 Runtime、Helper 或由 QuotaView 启动 `codex` CLI/app-server。

## 官方参考

- [Codex authentication](https://learn.chatgpt.com/docs/auth)
- [Codex app-server](https://learn.chatgpt.com/docs/app-server)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
