# QuotaView 1.0.0 App Store 原生账户 Provider 实施规格

> 文档编号：`QV-APPSTORE-NATIVE-ACCOUNT-PROVIDER-001`
>
> 规格状态：`Superseded / Rejected by Provider`
>
> 交付状态：`Removed from Production`
>
> 用户确认日期：2026-08-06
>
> 父级 Requirement：`AS-ACCOUNT-001`、`AS-SANDBOX-001`
>
> 依赖基线：QuotaView `0.3.1 (Build 2)`
>
> 目标版本：QuotaView `1.0.0 (Build 1)` / 内部代号 `v1.0.0a`
>
> 被替代于：`QV-APPSTORE-CODEX-USAGE-SNAPSHOT-BRIDGE-001`

> 2026-08-08 决策更新：OpenAI Support Case `12874203` 明确表示不能为
> 独立第三方原生 App 批准专用 OAuth Client，ChatGPT/Codex 额度也没有
> 通用第三方 OAuth 授权流。因此本规格只保留为已否决的历史
> 实验记录，不得继续驱动实施。现行规格是
> [QV-APPSTORE-CODEX-USAGE-SNAPSHOT-BRIDGE-001](quotaview-app-store-codex-usage-snapshot-bridge.md)。

## 1. 决策摘要

App Store 版本的基础额度改为 **全原生 Swift Account Provider**。QuotaView
自己完成 OAuth PKCE 登录、Token 刷新、Keychain 保存和 HTTPS 用量请求，
不再打包或启动 OpenAI Codex App Server Runtime。

本规格采用以下产品边界：

- 基础额度、Credits、菜单栏、主面板和 Widget 不依赖 Codex 插件；
- Token 只进入 QuotaView 自有 Keychain，不进入 UserDefaults、App Group、
  日志、Widget、插件或 QuotaView 服务器；
- 主 App 和 Widget 全部沙盒化；
- 不读取或写入外部 `~/.codex/auth.json`、Cookie、浏览器数据或 Codex Keychain；
- 不启动外部 CLI、App Server、Helper、Terminal、Expect 或后台守护进程；
- App Store Target 不包含 Rust Runtime、Sparkle、Cookie 抓取或网页解析；
- Codex 实时灵动岛继续使用独立 Git 插件桥，作为付费下载 App 已包含的功能，
  不参与账号和额度获取，也不依赖 OpenAI 账号。

此前完成的包内 Runtime Phase 0 仍作为历史技术证据保留，但约 436 MiB 的
Universal Runtime 路线已被产品所有者淘汰，不再等待包体、嵌套 Archive 或
`clientInfo.name` 决策，也不得重新成为生产实施入口。

## 2. 参考优先级

### 2.1 首要实践参考：AI Usage Tracker

本机已安装且已经通过 Mac App Store 审核的 AI Usage Tracker 是本规格的
首要产品、沙盒和 Provider 路线参考。对其已签名 App Bundle 和二进制的只读
检查确认了以下可观察事实：

- 原生 Swift / SwiftUI，Universal `arm64 + x86_64`；
- 主 App 与 Widget 均使用 App Sandbox；
- 只有主 App 与 Widget，不包含 Codex CLI、Rust Runtime 或 Helper；
- 使用原生 OAuth PKCE 浏览器登录；
- Access Token、Refresh Token、Account ID 和过期时间保存在自身 Keychain；
- 直接请求 `https://chatgpt.com/backend-api/wham/usage`；
- 请求可携带 `OpenAI-ChatGPT-Account-ID`；
- Widget 通过 App Group 消费裁剪后的本地快照；
- 包体保持在轻量原生应用范围。

QuotaView 应复现这条 **行为合同**，不得复制该 App 的代码、签名、Bundle
身份、专属回调地址或未经确认可复用的 OAuth Client ID。

### 2.2 最终事实来源：QuotaView 真实账号 Spike

AI Usage Tracker 是闭源 App，只能证明可观察路径和 App Store 先例。正式
实现前必须用 QuotaView 自己的 OAuth 回调、Keychain 和真实账号验证响应
字段、Token 刷新、账号切换、登出、沙盒和 Widget 一致性。Spike 结果是进入
生产迁移的最终 Go / No-Go 依据。

### 2.3 次要工程参考：CodexBar

CodexBar 只用于参考开源可审计的可靠性模式：

- 请求 generation、配置修订和账号范围的发布守卫；
- Token 刷新去重和单次 401 重试；
- 可损解码、未知字段容忍和独立可选 enrichment；
- 刷新中、stale、临时错误和已知不可用的区分；
- ephemeral URLSession、同源 HTTPS 重定向和有界响应。

QuotaView 不采用 CodexBar 的 CLI 回退、Cookie 回退、`auth.json` 读取、
WebKit 抓取、本地会话扫描或多 Provider 产品复杂度。

### 2.4 规范边界

Apple 与 OpenAI 官方文档用于约束审核、隐私、插件、Hook 和官方支持范围。
它们没有把本规格中的 `wham` 路径公布为第三方稳定 API；因此不得把同类 App
先例描述为 OpenAI 对 QuotaView 的正式授权或长期兼容承诺。

正式 OAuth Client、redirect、scope 和只读用量 API 的申请问题、关闭证据与
拒绝时降级边界见
[OpenAI 授权申请草案](../release/OPENAI_AUTHORIZATION_REQUEST_DRAFT.md)。OAuth
Client 与 usage API 必须使用两个独立的 `approved` 提交门禁，不能用候选接口
可访问或同类 App 已上架代替正式授权。
该边界同时在运行时执行：Release Bundle 固定声明 `approved-only`，只有两项
状态均为 `approved` 且 Client/endpoint 配置有效时才启用 Provider；Debug
Bundle 才声明 `candidate-allowed`。关闭状态必须在读取 Keychain 或建立网络
请求之前返回：账号控制器不得执行启动恢复或重新授权检查中的 Keychain
读取，Provider 也不得读取凭证或发起 HTTPS 请求。不得使用残留 Debug 凭证
绕过发行审批。

## 3. 产品能力与发行边界

### 3.1 App 已包含的功能

- 连接、重新连接和断开 ChatGPT 账号；
- 当前主额度周期的已用、剩余比例和重置时间；
- 服务返回时的次额度周期与额外额度窗口；
- OpenAI 方案显示名称；
- 普通 Credits 余额；
- 最近一天 Token 与累计 Token（必须通过真实 Profile Spike）；
- 菜单栏额度、主面板、设置和 Small / Medium Widget；
- 启动、面板打开、手动、定时、系统唤醒和网络恢复刷新；
- 断网、Token 失效、Schema 漂移和服务错误时的稳定降级。

### 3.2 Codex 灵动岛集成

- Codex 实时灵动岛展示；
- 插件事件实时消费与活动状态诊断；
- Session、Turn、工具调用、权限等待、压缩、子任务和完成状态展示。

QuotaView 采用 `USD 4.99` 付费下载，以上功能均包含在 App 中；不提供 IAP、
订阅或单独功能解锁。灵动岛只要求插件安装、Hooks 信任和只读目录配对，不得
关闭登录、额度、Widget 或普通刷新。详细插件安装和事件桥见
[Codex 灵动岛插件桥接实施规格](quotaview-app-store-codex-island-plugin-bridge.md)。

### 3.3 禁止行为

- 复用 AI Usage Tracker、Codex、ChatGPT Desktop 或浏览器的 Token；
- 读取 `~/.codex/auth.json`、Cookie 数据库、浏览器 Local Storage 或进程环境；
- 支持用户粘贴 Access Token 或把 Token 导出为文件；
- 使用 WebView 注入、网页 DOM 解析、网络代理、OCR 或 Accessibility 抓取；
- 启动外部 `codex`、App Server、Git、Shell、Terminal 或 Helper；
- 调用或预留额度重置消费接口；
- 将非公开接口返回的未知字段直接显示、记录或写入 Widget；
- 在用量请求失败时回退为 Cookie、CLI、Runtime 或虚构的 0% 数据。

## 4. 目标架构

```text
QuotaView.app（App Sandbox）
    │
    ├─ ASWebAuthenticationSession
    │       └─ OAuth 2.0 Authorization Code + PKCE
    │
    ├─ ChatGPTAccountSessionStore
    │       └─ QuotaView Keychain
    │           ├─ access token
    │           ├─ refresh token
    │           ├─ account id
    │           └─ expiry / minimal account scope
    │
    ├─ NativeChatGPTUsageProvider
    │       ├─ GET /backend-api/wham/usage
    │       └─ GET /backend-api/wham/profiles/me（Spike 通过后启用）
    │
    ├─ CodexStatusStore / ProviderSnapshot
    │       ├─ Menu Bar / Main Panel / Settings
    │       └─ App Group 中的脱敏 WidgetSnapshot
    │
    └─ Plugin Activity Provider
            └─ 配对后读取插件 PLUGIN_DATA → Codex 灵动岛
```

### 4.1 组件责任

| 组件 | 负责 | 不负责 |
|---|---|---|
| `ChatGPTOAuthClient` | PKCE、state、授权 URL、code exchange、refresh | UI 状态、用量解析 |
| `ChatGPTCredentialStore` | Keychain 的原子读写、清除和最小账号范围 | UserDefaults、App Group、日志 |
| `ChatGPTAccountSessionStore` | 登录、刷新去重、登出、账号切换 | 灵动岛和 Widget Token |
| `ChatGPTUsageClient` | HTTPS、Header、响应限制、状态码与解码 | Cookie、网页、CLI 回退 |
| `NativeChatGPTUsageProvider` | 数据归一化、错误分类和 ProviderSnapshot | 插件事件 |
| Widget Writer | 只写脱敏、可过期快照 | 登录、Keychain、网络请求 |
| Plugin Activity Provider | 插件协议验证、目录读取和事件消费 | 账号、额度和 Credentials |

## 5. OAuth、Keychain 与账号状态

### 5.1 OAuth PKCE

- 使用 `ASWebAuthenticationSession`，不嵌入或伪装登录网页；
- 每次登录生成高熵 `state`、`code_verifier` 和 S256 `code_challenge`；
- 回调固定为 `quotaview://oauth/openai`，并严格核对 scheme、host、port、path、
  单一 code/state 与一次性 state；源码配置、运行时和最终 Bundle 任一漂移都
  必须失败关闭，且不得先读取 Keychain；
- Info.plist 只注册 `quotaview` 一个 Scheme，标识使用反向域名
  `com.quotaview.menubar.oauth`、角色为 `Editor`；不得添加 ATS 例外；
- 取消、回调错误、code exchange 失败和工作区限制是明确状态；
- OAuth Client ID、允许的回调 URI 与第三方使用边界必须在 Spike 中记录；
- 不把 AI Usage Tracker 的回调 URI 或 App 身份复制到 QuotaView。

### 5.2 Keychain

- Token 使用 QuotaView 自有 Keychain service 和 access group；
- Widget、插件和 App Group 不加入 Token access group；
- Keychain JSON 或字段不得出现在 SwiftUI 可观察状态、日志和崩溃诊断；
- 登出原子删除 access token、refresh token、account id 与过期时间；
- 账号切换必须提高 configuration revision，旧账号响应不得发布。
- 凭证被清除或替换时，先清除旧账号在主 App、Widget 和诊断中的快照并重置
  `expectedAccountScope`，再发起刷新；普通断网保留旧快照的策略不得跨登出或
  账号切换继续生效，第一份新账号结果也不得被旧作用域误判为过期结果；
- 启动恢复、连接、重新授权检查和断开必须共享单调状态修订号；断开或新操作
  发起后，旧 Keychain 查询及旧浏览器回调不得再发布登录状态。

### 5.3 状态模型

```text
signedOut
  → authorizing
  → exchangingCode
  → signedIn
  → refreshingToken
  → signedIn

任意登录阶段 → cancelled / recoverableError / signedOut
401 刷新失败 → reauthenticationRequired
用户登出 → signingOut → signedOut
```

## 6. 用量接口与字段门禁

### 6.1 必需额度接口

候选请求：

```text
GET https://chatgpt.com/backend-api/wham/usage
Authorization: Bearer <access-token>
OpenAI-ChatGPT-Account-ID: <account-id>   # 账号存在时
Accept: application/json
```

只有真实 Spike 验证以下字段后才进入生产 Provider：

- `plan_type`；
- `rate_limit.primary_window`；
- `rate_limit.secondary_window`；
- `additional_rate_limits`（可选）；
- `credits`；
- 窗口的 used percent、reset timestamp 和 duration。

### 6.2 Profile / Token 用量接口

候选请求：

```text
GET https://chatgpt.com/backend-api/wham/profiles/me
```

该路径的公开实测证据表明可能返回 `daily_usage_buckets` 和
`lifetime_tokens`，但它不是 AI Usage Tracker 已确认的核心额度合同，也不是
公开稳定 API。进入生产前必须验证：

- 当前 OAuth Token 与 account header 可以访问；
- 最近一天与累计 Token 的字段和单位与现有 App Server 展示一致；
- 空数组、延迟更新和服务端 stale 可以被明确表达；
- 可选 Profile 失败不会清空有效额度快照。

如果该门禁失败，App Store `1.0.0` 不得通过扫描本地 Codex 数据、读取
`auth.json` 或 Cookie 来补齐。产品所有者必须在“暂时隐藏最近一天/累计
Token”与“推迟发布”之间另行选择。

### 6.3 传输约束

- 使用 ephemeral `URLSessionConfiguration`；
- 只允许 HTTPS，并限制到预期 OpenAI / ChatGPT host；
- 重定向必须在发送下一请求前保持 HTTPS、同一 host、同一有效端口且无 URL
  用户信息，不把 Authorization 或 Token 请求体转发到其他 origin；
- OAuth Token 响应必须再次核验最终 HTTPS origin，不只依赖底层会话的
  重定向策略；刷新响应不得静默切换既有 account scope；
- 响应必须具有标准 JSON 或 `+json` 媒体类型，不接受 HTML 中包含 JSON
  字样的宽松匹配，并设置严格 body 上限；
- 401 最多刷新一次 Token 后重试原请求；
- 429 尊重服务端 retry 信息，不做高频重试；
- 5xx、断网和超时保留最后有效快照并标记 stale；
- 解析失败只记录清洗后的错误类别，不记录响应正文。

## 7. Provider、UI 与 Widget 映射

### 7.1 Provider 发布资格

一次请求只有同时满足以下条件才可更新 UI：

- generation 仍是当前刷新；
- configuration revision 未变化；
- account scope 与请求发起时一致；
- Provider 仍启用；
- 响应时间未越过 deadline。

### 7.2 当前界面字段

| QuotaView 字段 | 新数据来源 | 降级 |
|---|---|---|
| 方案 | `plan_type` | 未知值显示破折号 |
| 本周期剩余/已用 | `primary_window.used_percent` | 保留旧快照或破折号 |
| 下次重置 | `primary_window.reset_at` | 破折号 |
| 次周期额度 | `secondary_window` | 无字段则隐藏 |
| Credits 余额 | `credits` | 无字段则破折号 |
| 最近一天 Token | Profile daily bucket | Profile 失败不影响额度 |
| 累计 Token | Profile lifetime tokens | Profile 失败不影响额度 |

现有方案名称归一、风险颜色、倒计时、最后有效快照和 60 秒最小刷新策略继续
复用；不得把 `prolite` 等原始枚举直接显示给用户。

### 7.3 Widget

- 主 App 完成网络请求和数据清洗；
- App Group 只保存方案、额度比例、重置时间、Credits、Token 汇总、更新时间
  和 schema version；
- Widget 不包含 Token、account id、邮箱、错误正文或接口 URL；
- 快照超时后显示不可用或过期状态，不自行访问 OpenAI。

## 8. App Sandbox 与轻量化

主 App 最终只保留完成产品功能所需的 entitlement：

- App Sandbox；
- Outgoing Network Connections；
- Widget App Group；
- QuotaView 自有 Keychain access group；
- 灵动岛配对所需的 user-selected read-only 文件访问。

必须从 App Store 生产 Target 删除或停用：

- `CodexExecutableLocator` 和外部 `CodexAppServerClient` 启动路径；
- Bundled Runtime、Runtime supervisor、独立 Runtime Home；
- Activity Helper、Hook Installer、Terminal / Expect 和 Unix Socket；
- Sparkle、自更新器、Cookie / WebKit 数据源和网页解析；
- 任何运行时下载、安装或执行外部代码的路径。

当前无 Runtime 的 Release App 约 26.3 MiB。原生 OAuth、插件桥和网络
代码不应引入大型资源，目标安装 Bundle 继续保持约 20–30 MiB；最终以
Distribution Archive 和 App Store processing 后的实测大小为准。

## 9. 实施阶段

### Phase 0：原生账户真实 Spike（外部验证待完成）

- 冻结 OAuth client、redirect URI、scope 和候选接口；
- 完成真实 PKCE 登录、Token exchange、Keychain 恢复和登出；
- 验证 `wham/usage`、account header、Token refresh 和账号切换；
- 验证 `wham/profiles/me` 的最近一天与累计 Token；
- 与 0.3.1 Build 2 / Codex 官方界面比较同一账号数据；
- 输出字段快照、错误矩阵、包体基线和 Go / No-Go，不保存秘密。

当前 OAuth/HTTP/Schema/401 重试使用可注入 transport 完成自动化验证，但
候选 Client、真实回调和 `wham` 仍未取得正式授权，也未完成真实账号验证。
自动化同时覆盖跨 origin Token 响应、刷新账号范围变化和 Keychain 异常空
Access Token 的 fail-closed 行为；Access/Refresh/ID Token 的大小、空白和
控制字符以及账号 Header 内容也必须在网络请求前通过校验。
候选 Client 只进入 Debug，Release Client ID 保持为空；提交模式预检必须在
授权状态改为 `approved` 后才允许 Archive。该门禁失败时不得发布；不得恢复
旧 CLI、Runtime、Cookie 或本地文件路线。

### Phase 1：账户与传输基础设施（已完成）

- 实现 OAuth、Keychain、Account Session、Usage Client；
- 使用可注入 transport、clock 和 credential store 完成单元测试；
- 建立错误分类、刷新去重、发布守卫和 stale 策略。

### Phase 2：Provider 与现有产品接入（已完成，等待视觉验收）

- 新 Provider 映射到现有 DomainModels 和 CurrentCodexPresentation；
- 接入主面板、菜单栏、设置和 Widget；
- 增加登录、重新连接、登出和账号失效体验；
- 保持基础额度与灵动岛完全解耦。

### Phase 3：沙盒与旧链路删除（已完成无签名验证）

- 开启主 App Sandbox、Network Client 和所需共享 entitlement；
- 删除生产 Runtime、外部 Codex、Cookie、Helper、Hook Installer 和 Socket；
- 检查 App 包内没有 Rust Runtime、外部 CLI 或自更新器。

### Phase 4：Codex 灵动岛并行接入（本地实施完成）

- 建立独立插件仓库、Hook writer、目录授权和事件消费；
- 协议和目录授权通过后，新鲜插件事件可以直接驱动实时灵动岛；
- App 内不保留 StoreKit 商品、购买恢复或功能门禁。

### Phase 5：Archive 与 App Review（待完成）

- 真实 Distribution Archive、Paid Apps Agreement 与 `USD 4.99` 价格配置；
- 登录、额度、插件和无插件的完整审核路径；
- 包体、签名、Privacy Manifest、App Store Connect 隐私答案和 Review Notes；
- 产品所有者完成视觉与交互验收。

## 10. Requirement 与验收标准

### NA-AUTH-001：原生账户登录

- QuotaView 自己完成 PKCE、Token exchange、刷新和登出；
- 不依赖 Runtime、CLI、Cookie 或外部 Codex 登录态；
- Token 只保存到 QuotaView Keychain。

### NA-USAGE-001：基础额度

- 无插件时仍可显示真实额度和 Widget；
- `wham/usage` 字段映射通过真实账号验证；
- 失败时不伪造 0% 或清空仍有效的旧快照。

### NA-PROFILE-001：Token 汇总

- 最近一天与累计 Token 只有真实 Profile Spike 通过后才启用；
- Profile 失败不影响基础额度；
- 不通过本地文件、Cookie 或 CLI 补齐。

### NA-PRIVACY-001：凭证隔离

- Widget、插件、App Group、日志和崩溃报告不含凭证或账号标识；
- 登出和账号切换不会保留可继续使用的旧 Token；
- 用户可以在设置中明确断开账号。

### NA-SANDBOX-001：轻量沙盒

- 主 App、Widget 全部启用 App Sandbox；
- App Bundle 不包含 Runtime、Helper、CLI、自更新器或 Cookie 抓取组件；
- 安装 Bundle 目标约 20–30 MiB，并记录最终 Archive 实测值。

### NA-REVIEW-001：审核可复现

- Review Notes 说明第三方登录、只读用量、Keychain、Widget、付费下载模式和
  可选插件集成；
- 提供可复现登录、刷新和插件测试步骤；
- 如果 Apple 要求第三方服务授权证明，必须如实提供或记录阻断，不伪造授权。

## 11. 风险与回滚

| 风险 | 策略 |
|---|---|
| OAuth client 或 redirect 不接受 QuotaView | Phase 0 直接 No-Go，不复制其他 App 身份 |
| `wham` Schema 或路径变化 | 可损解码、旧快照、App 更新；不回退 Cookie/CLI |
| Profile 数据延迟或缺失 | 标记 stale/不可用，不影响额度；必要时隐藏对应行 |
| Apple 要求第三方服务许可 | 提供真实材料；无法提供时视为发布阻断 |
| 插件不可用或未配对 | 基础额度继续工作，灵动岛保持不可用并提供安装/配对说明 |
| 新 Provider 回归 | 发布前保留分支级回滚点，不把 Runtime 重新装入 App Store 包 |

## 12. 参考

- 本机已安装的 Mac App Store 版 AI Usage Tracker：首要可观察实践参考；
- [CodexBar OAuth UsageFetcher](https://github.com/steipete/CodexBar/blob/dd029db4cb17811edd5805d952c5d5fc23395be3/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift)：仅作工程容错参考；
- [OpenAI Codex authentication](https://learn.chatgpt.com/docs/auth)；
- [OpenAI Codex App Server account API](https://learn.chatgpt.com/docs/app-server#api-overview-1)：仅用于比较当前字段，不作为新 Runtime 入口；
- [OpenAI Codex profile usage issue](https://github.com/openai/codex/issues/25479)：`wham/profiles/me` 候选路径的公开实测证据；
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)；
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)；
- [Authentication Services](https://developer.apple.com/documentation/authenticationservices)。
