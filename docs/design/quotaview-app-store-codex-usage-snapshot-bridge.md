# QuotaView 1.0.0 官方 Codex 用量快照桥实施规格

> 文档编号：`QV-APPSTORE-CODEX-USAGE-SNAPSHOT-BRIDGE-001`
>
> 规格状态：`Accepted`
>
> 交付状态：`Implemented / Live Validated`
>
> 用户确认日期：2026-08-08
>
> 父级 Requirement：`AS-ACCOUNT-001`、`AS-SANDBOX-001`

## 1. 决策

OpenAI Support Case `12874203` 确认，Support 不能为独立第三方
macOS App 批准专用 ChatGPT/Codex OAuth Client，也没有向这类 App
开放个人 Codex 额度的通用第三方授权流。QuotaView 因此移除
自有 OAuth、Keychain 凭证和非公开 HTTP 用量端点。

现行路线为：

```text
用户在官方 Codex 登录
        │
QuotaView for Codex 插件
        ├─ 启动官方 codex app-server
        ├─ account/rateLimits/read
        ├─ account/usage/read
        └─ 只写入白名单 usage.json
                │
QuotaView.app（App Sandbox）
        ├─ 用户选择目录的只读 bookmark
        ├─ 验证 manifest / schema / 安装 ID / 时效 / 字段白名单
        └─ 面板 / 菜单栏 / Widget 的脱敏投影
```

插件是数据生成方，不是身份提供方。登录、Token 保存、刷新和
网络请求始终由官方 Codex 进程拥有。

## 2. `usage.json` 合同

快照最大 `128 KiB`，协议和 usage schema 均为 `1`，来源必须为
`codex-app-server`，且 `installationIdentifier` 必须与 `bridge.json`
一致。快照超过 24 小时或超前 5 分钟均拒绝。

唯一允许字段：

- `bridgeProtocolVersion`、`usageSchemaVersion`、`capturedAt`、
  `source`、`installationIdentifier`；
- `planType`；
- `primary.usedPercent`、`windowDurationMins`、`resetsAt`；
- `credits.hasCredits`、`unlimited`、`balance`；
- `limitReached`；
- `lifetimeTokens`、`recentDailyTokens`、`recentDailyDate`。

任何未知的顶层、`primary` 或 `credits` 字段都会导致拒绝，而不是
被解码器静默忽略。

## 3. 隐私与禁止数据

插件不得写入：

- OAuth/Access/Refresh/ID Token、Cookie、密码或凭证路径；
- 邮箱、OpenAI 账号 ID、Workspace ID 或其他稳定账号标识；
- Prompt、命令、工具输入/输出、文件内容、模型响应或推理；
- 原始 app-server 响应；
- `rateLimitResetCredits`、可用重置次数、重置券 ID/描述或消费入口；
- 全部日用量历史；只保留 app-server 返回顺序中最新的一桶。

QuotaView 不包含 Network Client entitlement，不启动 `codex`、Shell 或
任何 Helper。插件不直接发起 HTTP，只与官方 app-server 的
JSONL stdio 合同通信。

## 4. 产品状态

- 尚未配对：主面板显示“连接官方 Codex”，按钮跳转设置
  的“Codex 连接”页；
- 已配对但无快照：提示用户在官方 Codex 完成登录；
- 有效快照：自动恢复用量图表，并依据现有偏好显示各指标；
- 短暂读取失败：保留最后有效展示，连接状态标记不可用；
- 更换/断开目录：立即清除旧 App、Widget 和诊断快照，不跨安装沿用。

Codex 灵动岛继续消费同一目录中的脱敏活动事件。用量失败不得
阻断灵动岛。

插件在 `SessionStart` 和 `Stop` 生命周期 Hook 中执行同进程只读刷新，避免
Hook 结束时后台子进程被 Codex 回收。自动刷新按 5 分钟窗口合并；QuotaView
状态栏按钮只立即重新读取当前快照和事件，真正绕过合并窗口的强制刷新仍由
插件 `--refresh-usage` 命令完成。Codex 空闲时不常驻 Helper，快照可以停留在
最后一次活动时间，但 24 小时内仍按有效快照处理。

## 5. 验证证据

- 官方 schema 确认两个读方法及目标字段；
- mock app-server 证明邮箱、重置券库存、其他 summary 字段和原始响应
  不会进入 `usage.json`；
- Swift decoder 负向测试拒绝未批准的 `email` 字段；
- 本机已登录的官方 Codex 完成一次只读 live 请求，插件产物通过
  QuotaView 生产目录安全与快照解码器。验证输出未打印账号或用量内容；
- 官方 Codex 中完成非绕过式 Hook 信任后，真实任务自动写入 `Stop` 和
  `SessionEnd`，并通过活动 Hook 自动推进快照时间；
- App 生产源码、Info.plist、xcconfig 与 entitlement 无 OAuth、凭证端点
  和 Network Client。

本规格已完成代码与 live 技术验证；插件新 tag/Release、App Store
Connect 价格、公开隐私/支持页和产品所有者视觉验收仍是独立发行门禁。
