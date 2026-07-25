# Codex Pulse

Codex Pulse 是一个原生 macOS 菜单栏应用，用于查看本机 Codex 的账户状态、周期用量、刷新时间、Credits 余额和 Token 使用情况。

当前 MVP 不抓取网页，也不读取或复制 `~/.codex` 中的登录凭据。它启动本机 `codex app-server`，通过官方 JSON-RPC 接口读取当前已登录账户的数据。

## 当前功能

- 显示 Codex 是否可用、接近限额或已经耗尽额度
- 显示当前周期的已用和剩余百分比
- 显示下次限额刷新倒计时
- 区分套餐剩余额度与额外 Credits 余额
- 将可用额度刷新次数作为独立入口展示
- 提供额度刷新二级页面、风险确认和最终确认弹窗
- 当前额度刷新流程为演示模式，不会调用真实重置接口或消耗次数
- 显示最近一天与累计 Token
- 每 60 秒自动同步数据，也支持手动同步
- 能定位 ChatGPT 应用内置、Homebrew 或自定义路径中的 `codex`
- 离线、未安装和 App Server 错误状态

Finder 启动后的第一次账户限额请求可能需要 20–30 秒。客户端为冷启动保留 45 秒响应窗口，后续刷新通常会明显更快。

应用会在自身的 macOS 偏好域中保存最近一次刷新成功时间、状态和错误摘要，不保存令牌或完整账户响应。需要诊断时可以运行：

```bash
defaults read com.codexpulse.menubar
```

## 环境要求

- macOS 14 或更高版本
- Swift 6 工具链或 Xcode 16+
- 已安装 ChatGPT/Codex，并且已经登录

应用按以下顺序查找 Codex：

1. `CODEX_EXECUTABLE` 环境变量
2. `/Applications/ChatGPT.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. 当前 `PATH`

## 快速验证

先运行单元测试：

```bash
swift test
```

再运行只读数据探针：

```bash
swift run CodexPulseProbe
```

探针会输出套餐、周期使用百分比、刷新时间、Credits 和累计 Token，不会输出登录令牌。

## 构建菜单栏应用

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/CodexPulse.app
```

构建脚本会生成并临时签名：

```text
dist/CodexPulse.app
dist/CodexPulse.zip
```

`CodexPulse.zip` 在应用离开当前工作区时能更好地保留 bundle 和签名结构。两者仍然都是本机开发版本；分发给其他用户前，需要使用 Apple Developer ID 正式签名并进行 notarization。

## 开发时直接运行

```bash
swift run CodexPulse
```

启动后应用只显示在 macOS 菜单栏，不显示 Dock 图标。

## 使用 Xcode

标准原生工程位于：

```text
CodexPulse.xcodeproj
```

直接用 Xcode 打开，选择共享的 `CodexPulse` scheme 和 `My Mac`，即可运行或测试：

```bash
open CodexPulse.xcodeproj
```

工程包含三个 target：

- `CodexPulse`：菜单栏主应用
- `CodexPulseCore`：可复用的数据模型与 App Server 通信 framework
- `CodexPulseTests`：Core 的单元和进程通信测试

应用 target 明确关闭了 App Sandbox，因为它需要启动用户本机安装的 `codex app-server`。当前使用本地 ad-hoc 签名；加入 App Group、WidgetKit 和正式分发前，需要在 Xcode 的 Signing & Capabilities 中选择你的 Apple Developer Team。

## 数据协议

连接建立后，客户端依次发送：

```text
initialize
initialized
account/rateLimits/read
account/usage/read
```

主要字段：

| UI | App Server 字段 |
| --- | --- |
| 当前状态 | `rateLimitReachedType`、`spendControlReached`、`primary.usedPercent` |
| 已用比例 | `primary.usedPercent` |
| 剩余比例 | `100 - primary.usedPercent` |
| 刷新时间 | `primary.resetsAt` |
| Credits | `credits.balance`、`credits.unlimited` |
| 免费重置次数 | `rateLimitResetCredits.availableCount` |
| Token | `summary.lifetimeTokens`、`dailyUsageBuckets` |

`Credits` 和“套餐剩余百分比”是两种不同概念，界面不会把二者合并。

当前版本仅实现额度刷新交互和安全确认，不发送
`account/rateLimitResetCredit/consume`。待整体产品功能和交互完成后，再接入真实额度刷新，
并为每次操作增加幂等键、结果处理和协议兼容性测试。

## 项目结构

```text
Sources/
├── CodexPulse/              # SwiftUI 菜单栏界面和状态容器
├── CodexPulseCore/          # App Server 客户端、定位器、数据模型
└── CodexPulseProbe/         # 无 UI 的真实数据验证工具
Tests/
└── CodexPulseCoreTests/     # JSON 映射和状态判断测试
```

## 下一阶段

1. 增加 Codex 活跃任务列表和 `thread/status/changed` 实时通知。
2. 使用 `ServiceManagement` 增加“登录时启动”。
3. 增加历史趋势图和接近限额通知。
4. 添加 WidgetKit 扩展，通过 App Group 与菜单栏应用共享最近一次快照。
5. 添加 Developer ID 签名、notarization 和自动更新。

App Server 的 schema 与安装的 Codex 版本对应。发布版本应在 CI 中运行 `codex app-server generate-json-schema`，并把协议兼容性测试纳入构建流程。
