# QuotaView Privacy Policy

Effective date: August 8, 2026

QuotaView is an independent, read-only macOS companion for Codex. It is not
affiliated with or endorsed by OpenAI or Apple.

## Data the developer does not collect

The QuotaView developer does not operate an account server, analytics service,
advertising service, telemetry endpoint, crash-reporting service, or remote log
collector for the app. QuotaView does not sell data, track users across apps or
websites, or use data for advertising.

## Codex sign-in and usage data

QuotaView does not provide its own OpenAI sign-in, receive OpenAI credentials,
or store OAuth tokens in its Keychain. Users sign in through the separately
installed official Codex application.

The optional public QuotaView for Codex plugin asks the official local
`codex app-server` for the signed-in user's read-only rate-limit and usage
information. Authentication, credential storage, refresh, and service network
requests remain owned by the official Codex process. The plugin does not send
direct HTTP requests and does not write the raw app-server responses to disk.

The plugin writes only an allowlisted local usage snapshot containing the
plan name, primary used percentage, window duration and reset time, Credits
availability/balance, limit state, lifetime token count, and newest daily token
bucket. It excludes credentials, cookies, email, account or workspace IDs,
reset-credit inventory, prompts, commands, files, model responses, reasoning,
and all other response fields.

## Local app and Widget data

After the user selects the plugin data folder in the macOS system picker,
QuotaView receives read-only access to its manifest, sanitized usage snapshot,
and sanitized activity events. QuotaView validates their schema, size,
installation identifier, age, ownership, and permissions before use.

QuotaView stores display preferences, refresh state, a security-scoped folder
bookmark, and the minimum sanitized display snapshot needed by its Widget in
the app container or App Group. The Widget never receives credentials, raw
app-server responses, or plugin event files. This information stays on the
user's Mac and is not used for analytics or advertising.

Disconnecting the folder revokes QuotaView's saved bookmark and clears its
derived usage and activity state. Deleting QuotaView removes data in its app
container; uninstalling the companion plugin removes its local writer.

## Codex Island activity events

The optional plugin retains at most the newest 512 local lifecycle events.
They can contain one-way session and turn hashes, the final workspace folder
name, a coarse tool category, lifecycle state, timestamps, sequence data,
plugin version, and bridge health.

The activity events do not contain prompts, commands, full paths, file
contents, tool inputs or outputs, model responses, reasoning, account data,
tokens, cookies, or credentials.

## Third-party services

The QuotaView app itself has no outbound network-client entitlement. The
official Codex application communicates with OpenAI under OpenAI's terms and
privacy policy. Apple handles purchase and download of the paid QuotaView app
through the Mac App Store; QuotaView has no in-app purchase flow and receives
no payment-card details or Apple Account credentials. Public help links open
in the user's default browser.

## Children

QuotaView is a developer utility and is not directed to children. The app does
not knowingly collect personal information from children.

## Changes

Material changes will be published at the same URL with an updated effective
date. If QuotaView later adds a server, telemetry, advertising, third-party
analytics, or remote logging, this policy and the App Store privacy answers
will be updated before release.

## Contact

The developer and copyright holder is Chenchen Xu. Privacy questions can be
emailed to [fierceviking@163.com](mailto:fierceviking@163.com) or filed through
the public [QuotaView App Store support tracker](https://github.com/Duoasa/QuotaView-AppStore-Pages/issues).

---

# QuotaView 隐私政策

生效日期：2026 年 8 月 8 日

QuotaView 是独立的 macOS Codex 只读伴侣应用，与 OpenAI、Apple 不存在
隶属或官方背书关系。

## 开发者不收集的数据

QuotaView 开发者不为本 App 运营账号服务器、分析服务、广告服务、遥测端点、
崩溃上报或远程日志服务。QuotaView 不出售数据，不跨 App 或网站跟踪用户，
也不将数据用于广告。

## Codex 登录与用量数据

QuotaView 不提供自有 OpenAI 登录、不接收 OpenAI 凭证，也不在自己的
Keychain 中保存 OAuth Token。用户在另行安装的官方 Codex 应用中登录。

可选的公开 QuotaView for Codex 插件通过本机官方 `codex app-server` 读取
当前登录用户的只读限额与用量。身份验证、凭证保存、刷新及服务网络请求均由
官方 Codex 进程负责。插件不直接发送 HTTP 请求，也不会把 app-server 原始
响应写入磁盘。

插件只写入白名单本地快照：方案名称、主周期已用百分比、周期长度和重置时间、
Credits 可用性/余额、触顶状态、累计 Token 和最新一日 Token 桶。快照排除
凭证、Cookie、邮箱、账号或工作区 ID、额度重置券、提示词、命令、文件、模型
回复、推理及其他响应字段。

## App 与 Widget 本地数据

用户通过 macOS 系统选择器选择插件数据目录后，QuotaView 只读访问其中的
Manifest、脱敏用量快照和脱敏活动事件，并在使用前验证协议、大小、安装 ID、
时效、所有者和权限。

QuotaView 在 App 容器或 App Group 中保存显示偏好、刷新状态、目录安全书签，
以及 Widget 显示所需的最小脱敏快照。Widget 不接收凭证、app-server 原始
响应或插件事件文件。数据只保留在用户 Mac 上，不用于分析或广告。

“断开目录”会撤销 QuotaView 保存的书签并清除派生的用量与活动状态。删除
QuotaView 会移除 App 容器数据；卸载伴侣插件会移除其本地写入器。

## Codex 灵动岛活动事件

可选插件最多保留最近 512 条本地生命周期事件。事件可以包含单向
Session/Turn 哈希、工作区最后一级目录名、粗粒度工具类别、生命周期状态、
时间、序列、插件版本和桥接健康状态。

事件不包含提示词、命令、完整路径、文件内容、工具输入或输出、模型回复、
推理、账号数据、Token、Cookie 或凭证。

## 第三方服务

QuotaView App 本身没有出站 Network Client 权限。官方 Codex 应用依据
OpenAI 的条款和隐私政策连接 OpenAI。付费 QuotaView 的购买与下载由 Mac
App Store 处理；QuotaView 不提供 App 内购买，也不接收银行卡或 Apple 账号
凭证。公开帮助链接会在用户默认浏览器中打开。

## 儿童

QuotaView 是开发者工具，不以儿童为目标用户，也不会主动收集儿童个人信息。

## 政策变更

重大变更会在同一网址发布并更新生效日期。如果未来加入服务器、遥测、广告、
第三方分析或远程日志，会在发布前同步更新本政策与 App Store 隐私答案。

## 联系方式

开发者与版权持有人是 Chenchen Xu。隐私问题可以发送至
[fierceviking@163.com](mailto:fierceviking@163.com)，或通过公开的
[QuotaView App Store 支持区](https://github.com/Duoasa/QuotaView-AppStore-Pages/issues) 提交。
