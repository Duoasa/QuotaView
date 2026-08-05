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
| 当前分支 | `codex/app-store-v1.0.0a` |
| 内部发行代号 | `QuotaView v1.0.0a` |
| App Store 版本 | `1.0.0 (Build 1)` |
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
| `QV-APPSTORE-CODEX-ISLAND-BRIDGE-001` | [Codex 灵动岛插件桥接实施规格](../design/quotaview-app-store-codex-island-plugin-bridge.md) | `Accepted` / `Planned` | `AS-SANDBOX-001` 的从属实施规格；固化 Git Marketplace 预览渠道、插件桥接、沙盒授权与未来公共目录迁移 |
| `QV-APPSTORE-CODEX-ACCOUNT-RUNTIME-001` | [Codex 账户 Runtime 实施规格](../design/quotaview-app-store-codex-account-runtime.md) | `Accepted` / `Planned` | `AS-ACCOUNT-001`、`AS-SANDBOX-001` 的从属实施规格；固化包内 Runtime、Device Code、Keychain、额度与 App Store 沙盒边界 |
| `QV-HANDOFF-APPSTORE-001` | [App Store Codex 项目交接入口](APPSTORE_CODEX_PROJECT_HANDOFF.md) | `Active` | 固化独立 worktree、新任务启动顺序、当前检查点、首个 Runtime Spike 与版本控制边界 |

## 当前追踪

| Requirement ID | 当前证据 | 当前结论 |
|---|---|---|
| `AS-BASE-001` | Git 分支与基座提交 | 已从不可移动稳定 tag 创建独立分支 |
| `AS-VERSION-001` | App 与 Widget xcconfig、App Info.plist、Universal Release 产物 | 已实现，版本与渠道验证通过 |
| `AS-UPDATE-001` | `SettingsView.swift` 与 2 项新增自动化测试 | 已实现，等待视觉验收 |
| `AS-RESET-001` | 主面板、设置、Core、Widget 合同与 1 项面板高度测试 | 已实现，53 项测试通过，等待视觉验收 |
| `AS-ACCOUNT-001` | 已接受 [Codex 账户 Runtime 实施规格](../design/quotaview-app-store-codex-account-runtime.md) | 方案已固化，尚未开始源码实施；必须先通过 Runtime、登录、Keychain、额度一致性和 Archive Spike |
| `AS-SANDBOX-001` | 已接受 [Codex 灵动岛插件桥接实施规格](../design/quotaview-app-store-codex-island-plugin-bridge.md) 与 [Codex 账户 Runtime 实施规格](../design/quotaview-app-store-codex-account-runtime.md) | 两条并列方案已固化，均尚未开始源码实施；主 App 仍未开启沙盒，不能提交审核 |
| `AS-VERIFY-001` | 53 项测试、Universal Release 与产物检查 | 第二阶段验证通过；版本、渠道、架构与资源检查通过 |

App Store 版本完成审核与公开分发之前，不得把交付状态写为 `Released`，
也不得改变 `v0.3.1-build.2` 的稳定发布事实或覆盖其 Release 资产。
