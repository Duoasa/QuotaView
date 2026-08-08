# QuotaView for Codex v1.0.0-preview.3 发布候选

状态：`Draft / Not Committed / Not Tagged / Not Released`

本候选是在独立插件仓库
`/Users/sukduoasa/Documents/QuotaView-for-Codex` 中实现的用量快照版本。
公开的 `v1.0.0-preview.1` 只可作为既有活动事件版本事实；它不满足当前
QuotaView 1.0.0 的 `codex-usage-snapshot` 能力要求。

## 候选内容

- 插件版本：`1.0.0-preview.3`；
- Bridge protocol：`1`；usage schema：`1`；
- Manifest capabilities：`codex-activity-events`、`codex-usage-snapshot`；
- 启动官方 `codex app-server`，只调用
  `account/rateLimits/read` 与 `account/usage/read`；
- 只写白名单 `usage.json`，原始响应只在进程内存存在；
- 不写凭证、Cookie、邮箱、账号/工作区 ID、重置券、Prompt、工具内容、
  回复或推理；
- `0600` 原子写入、独占刷新锁，并在 `SessionStart` / `Stop` 中同步刷新，
  高频事件按 5 分钟窗口合并；
- 活动 Hook 继续保持 fail-open，并最多轮转 512 条脱敏事件。

## 已完成验证

- `zsh -n`；
- `zsh tests/test-bridge.zsh`；
- mock app-server 注入邮箱、重置券和额外 summary 字段，确认均不落盘；
- 本机官方 `codex app-server` 两个只读方法完成一次真实刷新；
- 从官方 Codex 信任插件 Hooks 后，真实 `Stop` / `SessionEnd` 事件连续落盘，
  且无需手动命令即可推进 `usage.json` 快照时间；
- 真实 `usage.json` 通过 QuotaView 生产目录安全和 Swift 解码器；验证输出
  未打印账号或用量内容；
- 插件和主 App 工作树均通过 `git diff --check`。

## 发布前门禁

- [ ] 审查两个仓库的最终 diff，不纳入本地凭证、真实响应或用户路径；
- [ ] 在插件仓库创建独立 commit；
- [ ] 创建新的 annotated tag，不移动或覆盖任何旧 tag；
- [ ] 运行 branch/tag CI 和确定性资产构建；
- [ ] 创建公开 Pre-release，记录资产名、大小和 SHA-256；
- [ ] 从公开固定 tag 在全新 Codex 环境安装、信任 Hooks、登录、刷新用量、
  生成活动事件、配对 QuotaView、断开、卸载和重装；
- [ ] 回下载公开资产并复验内容与 SHA-256；
- [ ] 将主 App 的插件状态从 `candidate` 改为 `released`；
- [ ] 将 Review Notes 和安装说明中的占位符替换为该固定 tag/URL。

以上动作都需要产品所有者另行授权。本轮没有 commit、push、tag、Release 或
外部安装状态变更。
