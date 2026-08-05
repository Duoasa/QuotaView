# QuotaView 1.0.0 App Store Codex 账户 Runtime 实施规格

> 文档编号：`QV-APPSTORE-CODEX-ACCOUNT-RUNTIME-001`
>
> 规格状态：`Accepted`
>
> 交付状态：`Planned`
>
> 用户确认日期：2026-08-06
>
> 父级 Requirement：`AS-ACCOUNT-001`、`AS-SANDBOX-001`
>
> 依赖基线：QuotaView `0.3.1 (Build 2)`
>
> 目标版本：QuotaView `1.0.0 (Build 1)` / 内部代号 `v1.0.0a`

## 1. 决策摘要

App Store 版本的基础额度能力不得依赖 Codex 插件、外部 Codex CLI、
ChatGPT/Codex Desktop 是否已经安装或用户主动选择本地会话目录。QuotaView
在自身 App Bundle 中嵌入经过固定版本、Universal 构建和 App Store 签名的
OpenAI Codex App Server Runtime，通过官方 ChatGPT Device Code 登录读取
当前用户的 Codex 额度。

本规格将 App Store 版本的隐私边界从直接分发基线的“复用外部 Codex 登录、
QuotaView 不参与账号登录”调整为“最小账户接入”：

- 用户明确发起 OpenAI/ChatGPT 登录；
- 登录页面、Token 获取、刷新和登出由官方 Codex Runtime 处理；
- 凭证只保存在 macOS Keychain，不进入 UserDefaults、App Group、日志、
  Widget 或 QuotaView 自有服务器；
- QuotaView 不建立自己的账号系统，不保存邮箱，不读取项目、Prompt、线程、
  工具输出或外部 `~/.codex`；
- Runtime 与 OpenAI 直接通信，额度数据在本机清洗后才写入 App Group；
- Codex 灵动岛继续使用独立、可选的插件桥接，不参与账号和额度获取。

App Store 的沙盒、代码签名、审核和统一更新机制可以为该边界提供更强的系统
约束，但规格不得把“通过 App Store 审核”表述为绝对安全保证。隐私政策、
产品文案和 App Review Notes 必须准确披露账户接入与本地凭证处理方式。

## 2. 产品边界

### 2.1 无插件即可使用的基础功能

- 连接和断开 ChatGPT 账号；
- 读取 Codex 当前周期额度、剩余比例与周期重置时间；
- 显示 OpenAI 官方方案名称；
- 显示普通 Credits 余额；
- 在服务支持时读取只读 Usage summary；
- 菜单栏额度、主面板、设置和 Small / Medium Widget；
- App 启动、面板打开、手动刷新、定时刷新、网络恢复与系统唤醒刷新；
- 数据过期、断网、登录失效、方案不支持和服务错误的稳定降级；
- 通用页当前版本显示。

### 2.2 只由可选插件提供的功能

- Codex 灵动岛；
- Session、Turn、工具调用、权限等待、压缩、子任务和完成状态；
- 工作区末级名称与经过脱敏的活动元数据；
- 可选的线程展示名称增强。

插件未安装、未启用、未信任、协议不兼容或目录授权失效时，2.1 中的所有
基础功能必须继续工作。

### 2.3 App Store 版本禁止的行为

- 搜索或执行 `/Applications`、Homebrew、`/usr/local` 或 PATH 中的外部
  `codex`；
- 读取或复用外部 `~/.codex/auth.json`、Keychain 项、Cookie 或 Token；
- 读取 Codex rollout、Transcript、Prompt、回复或用户项目来推断额度；
- 接入私有 ChatGPT API、网页抓取、Accessibility、OCR 或网络拦截；
- 支持 API Key 作为 ChatGPT Codex 额度登录方式；
- 调用或预留 `account/rateLimitResetCredit/consume`；
- 暴露任意 App Server JSON-RPC 控制台、线程、Turn、Shell、Process、插件或
  Marketplace 方法；
- 下载、替换或自动更新 Runtime；
- 在 App 退出后保留 Runtime、守护程序、LaunchAgent 或更新循环；
- 自动安装灵动岛插件、修改 Hooks、控制 Terminal、退出或重启 Codex。

## 3. 当前基线与迁移边界

### 3.1 应保留的成熟实现

当前 `0.3.1 (Build 2)` 的额度链路使用官方 App Server 方法，协议与数据
质量已经稳定。迁移应保留：

- `CodexAppServerClient` 的 JSONL framing、请求 ID、超时、取消、最大行
  大小和错误清洗；
- `account/rateLimits/read` 与可选 `account/usage/read` 的结构化解码；
- `CodexProviderAdapter` 的额度、风险、方案、Credits 与 Usage 映射；
- `CodexStatusStore` 的刷新、最后有效快照和不可用状态；
- App Group 中经过清洗且会过期的 Widget 快照；
- 主面板、菜单栏、Widget、设置、语言、外观和辅助功能行为；
- 当前 `60` 秒最小刷新间隔与 Low Power Mode 的 `1,800` 秒下限。

### 3.2 必须替换的系统集成

直接分发基线通过 `CodexExecutableLocator` 查找 App Bundle 外部的 Codex，
并由 `Process` 启动 `codex app-server`。该路径依赖主 App
`ENABLE_APP_SANDBOX = NO`，不能原样进入 Mac App Store。

App Store 版本必须替换：

- 外部 Codex 定位器；
- `CODEX_EXECUTABLE` 环境覆盖；
- 外部可执行文件的 `Process.executableURL`；
- 对外部 Codex 登录态和 `CODEX_HOME` 的隐式依赖；
- 线程标题对外部 `thread/list` 的依赖；
- Codex 版本、Hooks 功能和安装状态的外部命令检查。

迁移原则是保留“官方 App Server 协议和额度业务层”，只替换 Runtime 所有权、
账户生命周期和沙盒边界，不改成日志抓取或插件额度桥接。

## 4. 目标架构

```text
QuotaView.app（App Sandbox）
    │
    ├─ QuotaView UI / Settings / Menu Bar
    │       │
    │       └─ CodexAccountSessionStore
    │               │
    │               └─ CodexAppServerSession
    │                       │  private stdio JSONL
    │                       ▼
    ├─ Contents/Helpers/QuotaViewCodexRuntime
    │       ├─ ChatGPT Device Code 登录
    │       ├─ macOS Keychain 凭证
    │       ├─ account/rateLimits/read
    │       └─ account/usage/read（可选）
    │                       │
    │                       ▼
    │                    OpenAI
    │
    ├─ 清洗后的 ProviderSnapshot
    │       └─ App Group / WidgetSnapshot
    │
    └─ 可选 PluginActivityProvider
            └─ 只读消费插件 PLUGIN_DATA → Codex 灵动岛
```

### 4.1 组件责任

| 组件 | 负责 | 不负责 |
|---|---|---|
| `BundledCodexRuntimeController` | 包内 Runtime 定位、启动、监督、终止 | 搜索或启动外部 Codex |
| `CodexAppServerSession` | initialize、JSONL、白名单 RPC、通知 | 暴露任意 App Server 方法 |
| `CodexAccountSessionStore` | 登录、Device Code、重连、登出、状态 | 保存 Token、建立 QuotaView 账号 |
| `AppStoreCodexQuotaProvider` | 额度刷新、清洗、错误映射 | 灵动岛、线程和项目数据 |
| Widget Writer | 写入最小、过期快照 | 登录、网络、Runtime 生命周期 |
| Plugin Activity Provider | 消费脱敏事件并驱动灵动岛 | 账号、额度与 Credentials |

## 5. Runtime 包装与生命周期

### 5.1 来源与版本固定

- Runtime 从 OpenAI `openai/codex` 官方仓库固定 tag 或 commit 构建；
- 记录上游版本、commit、构建参数、双架构产物 SHA-256 和依赖清单；
- 使用 Apache 2.0 License，并在 App 内包含适用的 License、NOTICE 和第三方
  许可证；
- 不直接下载 GitHub Release 二进制后无记录地放入 App；正式产物必须可从
  锁定源码和构建脚本重复生成；
- 上游更新先通过兼容测试和安全审计，再随新的 App Store Build 发布；
- 已提交审核的 Runtime 产物不得被服务器、插件或远程配置替换。

### 5.2 App Bundle 结构

```text
QuotaView.app/
├── Contents/MacOS/QuotaView
├── Contents/Helpers/QuotaViewCodexRuntime
├── Contents/PlugIns/QuotaViewWidget.appex
└── Contents/Resources/OpenSourceLicenses/
```

`QuotaViewCodexRuntime` 必须：

- 为 Universal `arm64 + x86_64` Mach-O；
- 位于 App Bundle 内并 `Code Sign On Copy`；
- 使用 App Sandbox inheritance；
- 只接受父进程创建的匿名 stdin/stdout Pipe；
- 不监听 TCP、WebSocket、Unix Socket 或公开 XPC endpoint；
- 不启动 updater、daemon、installer 或其他长期子进程；
- 不加载外部插件、MCP、技能或项目配置；
- App 退出、登录退出、连续协议错误或明确停止时被可靠回收。

### 5.3 独立 Runtime Home

Runtime 只使用 QuotaView 沙盒容器内的专用目录，例如：

```text
Library/Application Support/QuotaView/CodexRuntime/
```

不得使用真实用户的 `~/.codex`。安全配置至少包括：

- `check_for_update_on_startup = false`；
- `cli_auth_credentials_store = "keyring"`；
- `history.persistence = "none"`；
- 不启用 experimental API；
- 不创建或恢复 Thread；
- 不继承 `OPENAI_API_KEY`、`CODEX_API_KEY` 或其他无关秘密环境变量；
- 工作目录固定为 QuotaView 容器内的空白 Runtime 目录。

Keychain 不可用或持久化验证失败时，App 必须报告受控错误；未经新的产品和
安全决策，不得静默降级为明文 `auth.json`。

### 5.4 生命周期

1. QuotaView 需要检查账户或额度时懒启动 Runtime；
2. 建立 Pipe，发送 `initialize` 和 `initialized`；
3. 使用 `clientInfo.name = "quotaview_appstore"`、当前版本和明确标题；
4. 保持单个受监督会话，避免每次刷新重复登录和启动；
5. Runtime 崩溃时执行有上限的退避重启，不形成循环；
6. App 退出时先关闭 stdin，再限时终止 Runtime；
7. 超时后升级为强制终止，但不得留下孤儿进程；
8. Widget Extension 不启动 Runtime。

## 6. 账户登录与状态机

### 6.1 登录方式

App Store `1.0.0` 只支持官方 ChatGPT managed Device Code：

```json
{
  "method": "account/login/start",
  "params": { "type": "chatgptDeviceCode" }
}
```

不使用实验性的 `chatgptAuthTokens`，不由 Swift 主进程接收或刷新 Access
Token，不把 API Key 误当成 ChatGPT Codex 额度登录。

### 6.2 首次登录流程

1. 未登录时主面板保持稳定布局并显示连接引导，不伪造额度；
2. 用户明确点击“连接 ChatGPT”；
3. Runtime 返回 `verificationUrl`、`userCode` 和 `loginId`；
4. App 显示验证码、复制操作、倒计时和取消操作；
5. 用户点击后由系统浏览器打开 OpenAI 官方验证地址；
6. App 等待 `account/login/completed` 与 `account/updated`；
7. 成功后立即调用 `account/rateLimits/read`；
8. 获取到有效快照后刷新菜单栏、设置和 Widget；
9. 失败、超时或用户取消时回到可重试状态，不残留验证码和登录任务。

Device Code 避免本地 OAuth callback 和 Network Server entitlement。实施前
必须验证 Plus、Pro、Business、Edu、Enterprise/SSO 代表性账号；不支持的
组织策略应显示明确、可本地化的错误。

### 6.3 状态模型

| 状态 | 含义 | 用户操作 |
|---|---|---|
| `signedOut` | 尚未连接 ChatGPT | 连接 ChatGPT |
| `startingRuntime` | 启动并初始化 Runtime | 等待 / 取消 |
| `awaitingUserAuthorization` | 已生成 Device Code | 打开验证页 / 复制代码 |
| `verifying` | 等待 OpenAI 完成登录 | 取消 |
| `connected` | 凭证有效且有快照 | 刷新 / 退出登录 |
| `refreshing` | 保留最后有效值并刷新 | 等待 |
| `reauthenticationRequired` | 凭证失效或被撤销 | 重新连接 |
| `unsupportedAccount` | 当前认证方式或组织不支持额度 | 查看说明 / 退出登录 |
| `offline` | 网络不可用 | 重试 |
| `runtimeUnavailable` | Runtime 启动、签名或协议失败 | 诊断 / 联系支持 |

### 6.4 退出与账号切换

- “退出登录”必须调用 `account/logout`；
- 清除 Runtime Keychain 凭证和 App 内认证状态；
- App Group 快照立即失效，Widget 重新加载；
- 额度界面回到 `signedOut`，不继续展示敏感的最后余额；
- 删除登录状态不得删除用户的外部 Codex、ChatGPT 或插件数据；
- `1.0.0` 只支持一个当前账户；切换账号通过退出后重新登录完成。

## 7. App Server 方法白名单

### 7.1 允许的方法

- `initialize`；
- `initialized`；
- `account/read`；
- `account/login/start`；
- `account/login/cancel`；
- `account/logout`；
- `account/rateLimits/read`；
- `account/usage/read`。

允许处理的通知：

- `account/login/completed`；
- `account/updated`；
- `account/rateLimits/updated`。

### 7.2 禁止的方法

客户端必须通过类型化 API 和白名单阻止以下命名空间：

- `thread/*`、`turn/*`、`item/*`；
- `command/*`、`process/*`；
- `plugin/*`、`marketplace/*`、`mcpServer/*`；
- `skills/*`、`config/*`；
- 所有额度重置、消费、购买或账户写操作；
- 所有 experimental 方法和字段。

App 不提供调试控制台或用户可编辑 RPC 方法字符串。测试可以使用受控 Fixture，
生产构建不能包含发送任意方法的 UI 或 URL scheme。

## 8. 额度、Usage 与 Widget

### 8.1 数据合同

App Store Decoder 只映射：

- `rateLimits` 与 `rateLimitsByLimitId`；
- `limitId`、`limitName`；
- `primary`、`secondary`；
- `usedPercent`、`windowDurationMins`、`resetsAt`；
- `planType`；
- 普通 `credits`；
- `rateLimitReachedType` 与 `spendControlReached`；
- 可选 Usage summary 和 daily buckets。

`rateLimitResetCredits` 即使由服务器返回，也必须作为未知字段忽略，不进入
App Store 数据模型、日志、Widget、诊断或辅助功能文本。

`account/read` 返回的邮箱不得写入状态模型、日志或 UI。App 只保留认证类型、
是否需要 OpenAI 认证和必要的方案信息。

### 8.2 刷新策略

- App 启动且已登录：立即刷新；
- 登录成功：立即刷新；
- 打开主面板：快照超过 `60` 秒时刷新；
- 用户点击同步：立即刷新，但服从并发合并和退避；
- 正常后台：建议 `300` 秒；
- Low Power Mode：不低于 `1,800` 秒；
- 系统唤醒、网络恢复或时钟显著变化：延迟抖动后刷新；
- 可选插件发出真实任务完成事件：可以提前刷新一次，但插件缺失不得影响
  定时刷新；
- 同一账户同一时刻只允许一个额度请求；
- 失败保留最后有效快照，并按现有过期规则降级。

### 8.3 Widget 边界

- Widget 只读取团队前缀 App Group 中的清洗快照；
- Widget 不启动 Runtime、不登录、不访问 Keychain、不请求网络；
- 快照不包含 Token、Cookie、邮箱、账号 ID、原始 JSON 或历史明细；
- 登出、快照过期、账号切换和协议错误时立即刷新时间线；
- Widget 不得因为最后快照存在而在登出后继续显示余额。

## 9. 隐私与安全合同

### 9.1 对用户的最小承诺

QuotaView 可以在隐私政策和 App 内使用以下口径：

> QuotaView 使用随应用签名并沙盒化的 OpenAI Codex Runtime 完成 ChatGPT
> 登录和 Codex 用量读取。登录凭证保存在 macOS Keychain 中，额度请求直接
> 发送给 OpenAI。QuotaView 不运营账号服务器，不上传代码、Prompt、会话、
> 项目路径或灵动岛事件。

不得继续使用“QuotaView 完全不接触账号”或“无需登录”的旧口径描述 App
Store 版本。直接分发版本可以按其真实实现保留独立说明，但两个渠道的 README、
隐私政策和支持文档必须明确区分。

### 9.2 日志和诊断

- 不记录 Device Code、auth URL 查询参数、Access Token、Refresh Token、
  Cookie、邮箱或完整 App Server 响应；
- stderr 只保留有界、脱敏的错误摘要；
- 崩溃报告不得附加 Runtime Home、Keychain 内容或原始 JSONL；
- 诊断导出只包含 App/Runtime 版本、架构、登录状态枚举、最后刷新时间、
  方法名白名单和清洗后的错误码；
- 默认不上传诊断；任何未来遥测必须另行授权并更新隐私规格。

### 9.3 沙盒 Entitlement

主 App 目标：

- `com.apple.security.app-sandbox = true`；
- `com.apple.security.network.client = true`；
- `com.apple.security.application-groups`；
- 灵动岛插件配对需要的 user-selected read-only 与 app-scoped bookmark。

Runtime：

- `com.apple.security.app-sandbox = true`；
- `com.apple.security.inherit = true`；
- 不声明额外文件、Automation、Accessibility、Apple Events 或临时例外。

Widget：

- App Sandbox 与 App Group；
- 不声明网络、Keychain、用户文件或外部执行权限。

最终权限以 App Store Distribution provisioning profile 和 Archive 的实际
entitlement 为准，不能只修改 `.entitlements` 或 xcconfig 后宣称通过。

## 10. 与灵动岛插件规格的关系

本规格与
[QV-APPSTORE-CODEX-ISLAND-BRIDGE-001](quotaview-app-store-codex-island-plugin-bridge.md)
并列从属于 App Store 沙盒整改：

| 能力 | 账户 Runtime | Codex 插件 |
|---|---:|---:|
| OpenAI 登录 | 是 | 否 |
| 额度、Credits、Usage | 是 | 否 |
| Widget 快照 | 是 | 否 |
| Codex 活动事件 | 否 | 是 |
| 灵动岛 | 否 | 是 |
| Prompt、项目和工具输出 | 禁止 | 禁止 |
| 未安装插件时基础功能 | 完整 | 不适用 |

两个实现不得共享 Token、账号 ID 或写权限。插件可以用任务完成事件触发 App
提前刷新额度，但不能提供额度本身，也不能成为登录前置条件。

## 11. 代码迁移计划

### 11.1 新增或重构组件

- 把 `CodexAppServerClient` 拆分为协议会话与 Runtime 启动器；
- 新增 `BundledCodexRuntimeLocator`，只解析 `Bundle.main` 中的辅助程序；
- 新增 `BundledCodexRuntimeController`；
- 新增 `CodexAccountSessionStore` 和登录状态机；
- 新增 `AppStoreCodexQuotaProvider`；
- 为 App Store composition root 注入 bundled runtime provider；
- 为直接分发 composition root 保留现有 external runtime provider；
- 将线程标题从账户 Runtime 移除，改由插件事件或工作区名降级；
- 增加 Runtime 上游版本与构建元数据资源。

### 11.2 删除项

- App Store 目标中的 `CodexExecutableLocator` 运行时使用；
- 外部路径与 `CODEX_EXECUTABLE` 覆盖；
- 打开、终止、重启 Codex；
- `codex --version`、`features list`、`features enable hooks`；
- Terminal/Expect 安全确认；
- 外部 `thread/list` 标题补全；
- 额度重置响应映射和操作；
- 只服务于旧外部进程或 Hook 安装链路的测试和资源。

### 11.3 渠道隔离

不要在视图层散布 `#if APPSTORE`。渠道差异应集中在 composition root、
xcconfig、entitlement、Runtime provider 和少量功能能力声明中。共享 UI、
Core、Widget Contract、资源和本地化继续使用同一实现。

## 12. 仓库、Codex 项目与版本管理建议

### 12.1 推荐结论

建立一个**独立 Codex 项目/任务和独立 Git worktree** 专门实施 App Store
版本，但继续使用同一个 `Duoasa/QuotaView` GitHub 仓库。不要复制出第二个
QuotaView 主应用仓库。

推荐结构：

```text
Duoasa/QuotaView                    # 主应用唯一仓库
├── GitHub 直接分发分支 / tags
└── App Store 长期分支 / tags

Duoasa/quotaview-codex-plugin       # 灵动岛插件独立仓库
└── Marketplace、Skill、Hooks、Bridge Writer
```

本地使用两个独立工作目录：

```text
QuotaView/                          # GitHub 直接分发工作区
QuotaView-AppStore/                 # 同仓库 App Store worktree
```

在 Codex Desktop 中为 `QuotaView-AppStore` 建立独立项目，使其拥有独立任务、
终端、上下文、构建产物和 Handoff，同时 Git 历史、Issue、共享代码和 blame
仍然统一。

### 12.2 不建议拆成两个主应用仓库的原因

- App Store 与直接分发版本仍共享大部分 UI、Core、Widget、资源和测试；
- 两个仓库会复制 Bug 修复、视觉调整、本地化、依赖更新和安全修复；
- 相同文件很快产生无意义差异，跨仓库 cherry-pick 和 Release 审计更困难；
- App Store Runtime 尚需 Spike，过早复制仓库会在架构未稳定前制造永久分叉；
- Git 分支、worktree、独立 scheme/xcconfig 和渠道 tag 已能提供充分隔离。

只有未来两个产品在名称、Bundle ID、核心 UI、功能、团队、许可证或商业模式
上长期独立，且共享代码已经降到很低时，才重新评估拆分主应用仓库。

### 12.3 分支与 tag

当前阶段继续使用：

```text
codex/app-store-v1.0.0a
```

完成首个 App Store 架构验证后，建议建立受保护的长期分支：

```text
appstore/main
```

功能开发继续使用 `codex/` 前缀，从对应渠道分支创建。Tag 必须带渠道和
Build，避免与 GitHub 直接发行 tag 混淆，例如：

```text
v0.3.1-build.2                 # GitHub 直接分发
appstore-v1.0.0-build.1        # Mac App Store
plugin-v1.0.0-preview.1        # 独立插件仓库
```

App Store Build 递增不得移动既有 tag。共享修复需要明确记录来源提交和合并
方向，不允许用整仓覆盖或复制文件的方式同步。

### 12.4 后续可选的双 Target 收敛

首个 App Store 版本不应同时承担大规模 Xcode 多 Target 重构。先通过 provider
注入和 xcconfig 完成渠道隔离。两个渠道都进入持续维护后，再评估在同一分支
建立 `QuotaViewDirect` 与 `QuotaViewAppStore` 两个 App Target；只有它能
显著减少长期分支漂移时才实施。

## 13. 实施阶段与门禁

### Phase 0：Runtime 技术 Spike

- 从固定 OpenAI Codex commit 构建 arm64 / x86_64 Runtime；
- 合成为 Universal 并嵌入最小沙盒测试宿主；
- 验证 Device Code、Keychain、`account/rateLimits/read` 和退出登录；
- 验证使用独立 Runtime Home 时额度与同一 ChatGPT 账号的 Codex 消耗一致；
- 验证 App 退出后无孤儿进程；
- 验证 App Store Archive 签名与 entitlement；
- 验证上游许可证、构建复现和包体影响。

交付门禁：Spike 全部成功前，不删除当前基线 Provider，不开始正式登录 UI。

### Phase 1：协议与 Runtime 基础设施

- 保留并重构现有 JSONL 客户端；
- 加入 bundled locator、Runtime supervisor 和方法白名单；
- 固定 Runtime Home 和安全配置；
- 加入崩溃、超时、重启退避、关闭和孤儿进程测试；
- 加入上游版本与 License 资源。

### Phase 2：账户体验

- 实现登录状态机、Device Code、系统浏览器、取消和超时；
- 实现 Keychain 持久化恢复、重新认证、退出和账号切换；
- 设置页明确数据用途和本地删除方式；
- 中英文、键盘、VoiceOver 与 Reduce Motion 完整。

### Phase 3：额度与 Widget 迁移

- 接回现有 Provider Adapter；
- 实现刷新调度、Usage 可选降级和错误状态；
- 清洗 App Group 快照；
- 登出和过期时刷新 Widget；
- 确认无额度重置字段或操作回归。

### Phase 4：外部进程与 Codex 控制删除

- 删除 App Store 运行时外部 Codex 搜索和执行；
- 删除打开、退出、重启、版本检查和 Hooks enable；
- 删除 Terminal/Expect 安全确认；
- 账户 Runtime 不再调用 `thread/list`；
- 与插件规格 Phase 3 合并检查旧 Hook/Helper/Socket 链路。

### Phase 5：App Sandbox 与 Archive

- 主 App 开启 Sandbox 和 Network Client；
- Runtime 使用 inherit entitlement；
- Widget 保持最小 entitlement；
- 使用 App Store Distribution profile 生成 Archive；
- 完成签名、架构、provisioning、网络、Keychain、App Group 和真实登录测试。

### Phase 6：App Review 准备

- 准备具备 Codex 权益的专用审核账号和可复现登录步骤；
- Review Notes 说明 QuotaView 是特定第三方服务的用量客户端，不建立自身
  账号；
- 提供 App Server 官方文档、开源仓库、许可证和上游版本；
- 完成 Privacy Policy、App Privacy、支持页面和账号断开说明；
- 公开插件 Preview tag 和灵动岛可选测试步骤；
- 未完成 OpenAI 服务条款、客户端身份或 App Review 可复现性确认前不得
  提交。

## 14. Requirement 与验收标准

### AR-RUNTIME-001：自包含 Runtime

- Runtime 位于 App Bundle、Universal、签名且沙盒继承；
- 不搜索、启动或依赖外部 Codex；
- 不自更新，不在 App 退出后驻留。

### AR-AUTH-001：最小账户登录

- 只使用官方 ChatGPT managed Device Code；
- 凭证由 Runtime 存入 Keychain；
- Swift、Widget、App Group 和日志中无 Token；
- 登录取消、过期、重新认证、登出和切换完整。

### AR-QUOTA-001：无插件基础额度

- 未安装插件时，登录、额度、Credits、菜单栏与 Widget 正常；
- 额度来自官方 `account/rateLimits/read`；
- Usage 不可用时不覆盖有效额度；
- 不解析 rollout 或调用私有接口。

### AR-RPC-001：方法白名单

- 生产客户端不能发送任意 RPC；
- 禁止线程、执行、插件、配置和额度消费方法；
- 不启用 experimental API。

### AR-PRIVACY-001：本地最小数据

- 不保存邮箱、账号 ID、原始响应或会话内容；
- 不读取 `~/.codex`、项目、Prompt 或工具输出；
- 不存在 QuotaView 账号服务器或遥测上传；
- 隐私政策和 App 文案与真实行为一致。

### AR-SANDBOX-001：App Store 权限闭环

- 主 App、Runtime、Widget entitlement 最小化；
- Archive 与 provisioning profile 一致；
- 无临时沙盒例外、外部执行、Automation 或 Accessibility 权限；
- Runtime 网络只服务于官方账户和额度请求。

### AR-REVIEW-001：审核可复现

- 审核账号可完成 Device Code 登录并读取真实额度；
- Review Notes 解释第三方账号用途和 Sign in with Apple 例外口径；
- Runtime 来源、License、隐私政策和支持页面可访问；
- 插件未安装时审核人员仍能验证核心功能。

## 15. 验证矩阵

### 15.1 自动化测试

- JSONL 分片、延迟、多通知、超大行、超时、取消与进程退出；
- RPC 白名单允许和拒绝；
- Device Code 成功、取消、超时、重复回调和过期；
- Keychain 持久化、恢复、登出与不可用；
- 额度单桶、多桶、缺失、未知方案、Credits、Usage 可选失败；
- `rateLimitResetCredits` 被忽略且无消费方法；
- App Group 快照无认证和账号字段；
- 登录、登出、过期和刷新时 Widget timeline 更新；
- Runtime 崩溃退避、App 退出和无孤儿进程；
- 插件未安装、断开或不兼容时额度不受影响。

### 15.2 静态检查

至少搜索：

```bash
rg -n \
  'CODEX_EXECUTABLE|/opt/homebrew/bin/codex|/usr/local/bin/codex|features enable hooks|/usr/bin/expect' \
  Sources Configs Support QuotaView.xcodeproj

rg -n \
  'account/rateLimitResetCredit/consume|DEBUG-ONLY-MOCK|DEBUG MOCK|仅用于调试' \
  Sources Tests

git diff --check
```

生产构建允许 Bundle 内 Runtime 路径，不允许外部 Codex 路径。历史文档命中
必须逐项解释，不能以搜索命中为由删除稳定版本事实。

### 15.3 集成与发布验证

- 全新用户环境，无外部 Codex、无插件；
- Device Code 首次登录和已有浏览器会话；
- Plus、Pro、Business、Edu、Enterprise/SSO 代表性账号；
- 网络断开、代理、睡眠唤醒、系统时钟变化和凭证撤销；
- App 重启、系统重启、账号切换和退出登录；
- 主面板关闭、菜单栏长期运行与 Low Power Mode；
- Small / Medium Widget 深浅色和过期状态；
- arm64 / x86_64；
- Xcode App Store Archive、`codesign --verify --deep --strict`、嵌套 Runtime
  entitlement、provisioning profile 与 App Group；
- App 退出后检查 Runtime 无残留；
- 产品所有者完成视觉与交互验收，Codex 不代替验收。

## 16. 风险与回滚

| 风险 | 控制与回滚 |
|---|---|
| App Server 上游协议变化 | 固定 Runtime 版本、生成匹配 schema、随 App Build 升级 |
| Device Code 或组织策略不支持 | Spike 覆盖代表性账号；显示明确不支持，不转私有接口 |
| Keychain 在嵌套 Runtime 中失败 | 作为发布阻断；不静默明文落盘 |
| Runtime 包体或签名失败 | 保留当前分支，不删除基线 Provider，修复后再进入正式迁移 |
| OpenAI 客户端身份/服务条款要求 | 提前确认 `clientInfo`、企业已知客户端与第三方集成许可 |
| App Review 无法登录 | 专用审核账号、详细步骤和稳定 OpenAI 服务状态 |
| 插件延期 | 基础额度照常提交；灵动岛按独立规格决定是否随同上线 |
| App Store 方案失败 | 直接分发 `0.3.1 Build 2` 和其 tag/Release 不受影响 |

Spike 或服务许可闸门失败时，不得回退到读取用户 `auth.json`、复制 Token、
私有 API、Transcript 解析或让插件承担基础额度。应停止 App Store 额度迁移，
保留直接分发稳定版本并重新决策。

## 17. 实施前待确认项

1. 固定的 OpenAI Codex 上游 tag / commit 与升级策略；
2. Runtime 最终可执行文件名称和构建脚本位置；
3. App Store `clientInfo.name` 与是否需要 OpenAI 客户端登记；
4. 专用 App Review ChatGPT/Codex 账号来源；
5. Privacy Policy、Support URL 和隐私联系人；
6. App Store 与直接分发版本是否使用同一产品网站的分渠道说明；
7. 独立 App Store Codex 项目/worktree 的本地路径；
8. App Store 长期分支何时从当前开发分支晋升为 `appstore/main`。

## 18. 官方参考

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication / Credential storage](https://learn.chatgpt.com/docs/auth#credential-storage)
- [OpenAI Codex open source](https://learn.chatgpt.com/docs/open-source)
- [OpenAI Codex GitHub repository](https://github.com/openai/codex)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
