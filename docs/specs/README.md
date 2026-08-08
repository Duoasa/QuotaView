# QuotaView App Store 发行规格索引

> 文档编号：`QV-SDD-INDEX-APPSTORE-001`
>
> 规格状态：`Accepted`
>
> 生效日期：2026-08-05

## 当前状态

新 Codex 项目的独立交接入口：
[APPSTORE_CODEX_PROJECT_HANDOFF.md](APPSTORE_CODEX_PROJECT_HANDOFF.md)。

| 项目 | 当前值 |
|---|---|
| 稳定代码基座 | `0.3.1 (Build 2)` / `v0.3.1-build.2` |
| 基座提交 | `3119171f45163fe45d68a4f774a0488968f14fd7` |
| 当前分支 | `codex/appstore-runtime-spike` |
| 内部发行代号 | `QuotaView v1.0.0a` |
| App Store 版本 | `1.0.0 (Build 4)` |
| 发布渠道 | `appstore` |
| 当前规格 | `QV-APPSTORE-RELEASE-1.0.0-001` |
| 规格状态 | `Accepted` |
| 交付状态 | `Implementing` |
| 发布状态 | 尚未提交 App Review，尚未发布 |

`v1.0.0a` 只作为本次适配工作的内部代号。Apple 要求用户可见的
`CFBundleShortVersionString` 使用三段纯数字，因此生产配置使用 `1.0.0`；
字母 `a` 不写入 Marketing Version、Build Number 或 App Store 版本字段。

## 规格注册表

| 文档编号 | 文档 | 状态 | 当前用途 |
|---|---|---|---|
| `QV-APPSTORE-RELEASE-1.0.0-001` | [App Store 发行适配规格](../design/quotaview-app-store-release-1.0.0.md) | `Accepted` / `Implementing` | 驱动 `1.0.0` App Store 适配开发 |
| `QV-APPSTORE-CODEX-USAGE-SNAPSHOT-BRIDGE-001` | [官方 Codex 用量快照桥实施规格](../design/quotaview-app-store-codex-usage-snapshot-bridge.md) | `Accepted` / `Implemented, Live Validated` | 官方 Codex 拥有登录；插件读取 app-server 并写入脱敏 `usage.json`；QuotaView 只读验证与展示 |
| `QV-APPSTORE-NATIVE-ACCOUNT-PROVIDER-001` | [原生账户 Provider 历史规格](../design/quotaview-app-store-native-account-provider.md) | `Superseded` / `Removed` | OpenAI Support Case `12874203` 拒绝独立第三方 OAuth Client 批准路径；仅保留为历史 No-Go 证据 |
| `QV-APPSTORE-CODEX-ISLAND-BRIDGE-001` | [Codex 灵动岛插件桥接实施规格](../design/quotaview-app-store-codex-island-plugin-bridge.md) | `Accepted` / `Implemented, Usage Plugin Release Pending` | App 沙盒只读桥已落地；旧 Preview 1 活动版已公开，支持用量快照的 Preview 7 已进入公开仓库主分支并通过本地发行检查，固定 tag/Release 仍待完成；灵动岛随付费 App 全量提供，不含 IAP 门禁 |
| `QV-APPSTORE-CODEX-ACCOUNT-RUNTIME-001` | [Codex 账户 Runtime 历史规格](../design/quotaview-app-store-codex-account-runtime.md) | `Superseded` / `Historical No-Go` | 已被原生账户 Provider 替代，不再驱动实施；保留包内 Runtime 决策与边界历史 |
| `QV-SPIKE-APPSTORE-ACCOUNT-RUNTIME-P0-001` | [Account Runtime Phase 0 Spike 报告](../spikes/APPSTORE_ACCOUNT_RUNTIME_PHASE0.md) | `Executed` / `Archived No-Go` | 记录固定上游、双架构沙盒、Device Code、Keychain、额度和约 436 MiB 包体证据；不再阻塞现行路线 |
| `QV-HANDOFF-APPSTORE-001` | [App Store Codex 项目交接入口](APPSTORE_CODEX_PROJECT_HANDOFF.md) | `Active` | 固化独立 worktree、现行原生 Provider 起点、历史 Runtime 证据、插件路线与版本控制边界 |

发行操作草案：
[App Review Notes](../release/APP_STORE_REVIEW_NOTES_DRAFT.md)、
[App Privacy Answers](../release/APP_STORE_PRIVACY_ANSWERS_DRAFT.md)、
[App Store Metadata](../release/APP_STORE_METADATA_DRAFT.md)、
[OpenAI Authorization Request](../release/OPENAI_AUTHORIZATION_REQUEST_DRAFT.md)、
[Plugin Preview 1 Release](../release/PLUGIN_RELEASE_V1.0.0_PREVIEW.1.md)、
[Plugin Preview 3 Historical Candidate](../release/PLUGIN_RELEASE_V1.0.0_PREVIEW.3_DRAFT.md)。这些文件不改变
当前 `Implementing` 状态，也不得在外部门禁关闭前直接提交。

产品所有者本机审核使用
[App Store 初步改造本机审核单](../release/LOCAL_MANUAL_REVIEW_CHECKLIST.md)。
当前阶段不上传、不发布，不为扩大覆盖面临时新增测试代码；只做必要构建与
静态检查，视觉和交互结果由产品所有者运行后确认。正式发行规格仍保持
`Implementing`，本机初审就绪不等同于可以提交 App Review。

## 当前追踪

| Requirement ID | 当前证据 | 当前结论 |
|---|---|---|
| `AS-BASE-001` | Git 分支与基座提交 | 已从不可移动稳定 tag 创建独立分支 |
| `AS-VERSION-001` | App 与 Widget xcconfig、App Info.plist、Universal Release 产物 | 已实现，版本与渠道验证通过 |
| `AS-UPDATE-001` | `SettingsView.swift` 与 2 项新增自动化测试 | 已实现，等待视觉验收 |
| `AS-RESET-001` | 主面板、设置、Core、Widget 合同与面板高度测试 | 已实现；当前常规回归执行 61 项、0 失败、1 项显式 live 插件 E2E 跳过，官方 Codex 真实快照单独运行通过；Widget 数据显示已由产品所有者确认，其他视觉状态等待验收 |
| `AS-ACCOUNT-001` | `CodexPluginUsageSnapshot`、`CodexPluginUsageProviderAdapter`、主面板连接入口、“连接与灵动岛”设置页、独立灵动岛显示开关、插件 `usage.json`、mock 与 live E2E | 已移除 App 自有 OAuth/Keychain/`wham`；官方 Codex 拥有登录，插件只调用两个读 RPC 并落盘字段白名单；QuotaView 不含网络权限，只读用户授权目录。关闭灵动岛只停止展示，不停止数据消费；真实官方 Codex 链路已通过生产解码器，视觉交互等待用户验收 |
| `AS-PRICING-001` | `paid-upfront` 构建配置、无 IAP 运行时/设置页/测试资源、付费 App readiness 门禁 | QuotaView 采用 `USD 4.99` 基准价的一次性付费下载，全部内置功能直接可用；代码侧 IAP 与灵动岛 entitlement 门禁已移除，App Store Connect 价格状态仍为 `pending` |
| `AS-SANDBOX-001` | `ENABLE_APP_SANDBOX = YES`、App Group、用户所选目录只读 bookmark、隐私清单；旧 CLI/Runtime/Helper/Socket 链路已删除 | 主 App 的 Network Client 已删除；网络和认证由官方 Codex 进程拥有；当前 Universal 无签名 Release 通过 Bundle 审计，最终签名 Archive 仍须在外部门禁关闭后重建 |
| `AS-VERIFY-001` | 61 项 SwiftPM 测试、插件 mock/live 验证、付费价格/用量快照/插件/隐私/支持页状态门禁、双语元数据、Privacy Manifest、URL/ATS、普通 readiness 与 Universal Release Bundle 审计 | 0 失败、1 项显式 live E2E 普通运行跳过；Build 4 Universal Release 与 Bundle 审计通过，App、Widget、Framework 均为双架构；提交模式按设计首先阻断未配置价格，现有签名 Archive 仅保留为历史证据；价格、公开页面、内容权利和产品验收仍是提交门禁 |

App Store 版本完成审核与公开分发之前，不得把交付状态写为 `Released`，
也不得改变 `v0.3.1-build.2` 的稳定发布事实或覆盖其 Release 资产。
