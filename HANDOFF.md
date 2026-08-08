# QuotaView 项目 Handoff

当前稳定发布事实：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。

更新日期：2026-08-08

集成工作区：`/Users/sukduoasa/Documents/widget`

集成分支：`codex/app-store-v1.0.0a`

新 Codex 项目工作区：`/Users/sukduoasa/Documents/QuotaView-AppStore`

新 Codex 项目分支：`codex/appstore-runtime-spike`

当前稳定发布提交与 App Store 代码基座：
`3119171f45163fe45d68a4f774a0488968f14fd7`

远程：`https://github.com/Duoasa/QuotaView.git`

当前进行中的 App Store 适配：

| 项目 | 当前值 |
|---|---|
| 内部发行代号 | `QuotaView v1.0.0a` |
| App Store 版本 | `1.0.0 (Build 4)` |
| 发布渠道 | `appstore` |
| 基座 | `0.3.1 (Build 2)` / `v0.3.1-build.2` |
| 当前规格 | `QV-APPSTORE-RELEASE-1.0.0-001` |
| 交付状态 | `Implementing` |
| 发布状态 | 尚未提交 App Review，尚未发布 |
| 当前验证 | `1.0.0 (Build 4)` 保持 App 自有 OAuth、Keychain、`wham` 端点和 Network Client 已移除；新增独立灵动岛显示偏好，关闭后继续读取用量、连接状态和活动事件；Swift 61 项、0 失败、1 项显式 live E2E 跳过；Universal 无签名 Release 与 Bundle 审计通过，App、Widget、Framework 均为 `arm64 + x86_64` |
| 产品验收 | 产品所有者已确认真实插件目录连接成功、用量图表恢复、桌面 Widget 能读取数据且系统只显示一个 QuotaView Widget；`373 pt` 主面板、连接快捷入口、“连接与灵动岛”设置页、独立灵动岛开关和灵动岛完整视觉交互仍等待运行确认 |
| 本机初审 | 初步改造已进入产品所有者手动审核；不上传、不发布，不为扩大覆盖面临时新增测试代码，只做必要构建与静态校验 |

2026-08-08：产品所有者已完成基于本地脱敏快照的官方 Codex 连接，明确将
当前未发布的 App Store 源码候选已晋升为 `1.0.0 (Build 4)`。该 Build 只晋升当前
App/Widget 候选身份，不改变公开稳定版 `0.3.1 (Build 2)`，也不代表已经
提交 App Review 或发布。产品所有者当前运行的是安装在 `/Applications` 的
Build 4 Apple Development 签名审核包；主 App 与 Widget 使用同一 Team ID
`BUUH229D5Q` 和 App Group `BUUH229D5Q.com.quotaview.shared`。旧 Demo Widget
注册已经清除，系统只保留正式 `com.quotaview.menubar.widget`，产品所有者已
确认 Widget 可以读取数据。

Build 4 的 Apple Development 签名 Archive 已生成于
`/private/tmp/QuotaView-Build4-SignedLocal-20260808/QuotaView.xcarchive`；Bundle
审计确认 App、Widget 与 Framework 均为 `arm64 + x86_64`，版本和渠道为
`1.0.0 (4)` / `appstore`，签名与沙盒 entitlement 通过。该 Archive 只用于
本机审核，不是 App Store Distribution 提交包。

规格入口：
[docs/specs/README.md](docs/specs/README.md) →
[App Store 发行适配规格](docs/design/quotaview-app-store-release-1.0.0.md)。

新 Codex 项目的可执行交接入口：
[docs/specs/APPSTORE_CODEX_PROJECT_HANDOFF.md](docs/specs/APPSTORE_CODEX_PROJECT_HANDOFF.md)。

Codex 灵动岛 App Store 沙盒迁移的从属实施规格：
[docs/design/quotaview-app-store-codex-island-plugin-bridge.md](docs/design/quotaview-app-store-codex-island-plugin-bridge.md)。

基础额度与官方 Codex 登录边界的现行从属实施规格：
[docs/design/quotaview-app-store-codex-usage-snapshot-bridge.md](docs/design/quotaview-app-store-codex-usage-snapshot-bridge.md)。

2026-08-08：OpenAI Support Case `12874203` 确认不能为 QuotaView 这类
独立第三方原生 App 批准专用 OAuth Client，也不提供通用的
ChatGPT/Codex 额度 OAuth 授权流。用户因此确认改造为：官方
Codex 拥有登录与凭证，QuotaView for Codex 插件只调用官方
`account/rateLimits/read` 与 `account/usage/read`，写入字段白名单的
`usage.json`；QuotaView 仅通过用户授权目录只读消费。主 App 的
OAuth/Keychain/私有 HTTP Provider 和 Network Client 已移除，`quotaview://`
只保留 `pair` 用途。本机官方 Codex 真实快照已通过 QuotaView
生产解码器，验证时未输出账号或用量内容。原生账户 Provider
规格现为 `Superseded / Removed`，历史文字不得再驱动当前实施。

2026-08-08：修复灵动岛在任务结束后永久停留于 `PostToolUse`“思考中”的
问题。插件 `Stop` Hook 现在使用官方 JSON 成功输出合同，并将
`SessionStart` / `Stop` 的超时从 `3` 秒放宽至 `30` 秒，使同进程的五分钟
用量刷新不会抢占结束事件合同；活动事件仍先于用量刷新写入。主 App 对
`PostToolUse`、`PostCompact`、`SubagentStop` 增加 `120` 秒无新事件安全
隐藏，不合成虚假完成状态，后续真实事件会取消兜底。真实 `Stop` 的
“完成 → 20 秒紧凑 → 完成满 120 秒隐藏”时序保持不变。插件桥测试、隔离
安装/卸载/重装、Swift 60 项和 Universal `1.0.0 (Build 3)` 无签名 Release
Bundle 审计通过；视觉与真实 Codex 交互仍等待产品所有者验收。新的本机
审核包位于
`/private/tmp/QuotaView-StopHook-Build3-20260808-1850/QuotaView.app`。

对应插件工作区现为 `1.0.0-preview.7` 候选，新增
`codex-usage-snapshot` capability、mock app-server、原始字段泄漏负向测试和
官方 app-server 真实只读验证，并包含上述 Stop 可靠性修复和面向 Codex Chat
的安装说明。Preview 7 已提交并推送到公开仓库主分支，桥接测试、隔离安装、
卸载、重装和本机真实数据诊断通过，但尚未创建固定 tag 或 GitHub Release。主 App
的 `QUOTAVIEW_CODEX_PLUGIN_DISTRIBUTION_STATUS` 因此仍为 `candidate`。公开
`v1.0.0-preview.1` 仍是历史活动事件版本，不得当作当前用量能力的发布证据。

App Store Connect 与审核材料草案：
[Review Notes](docs/release/APP_STORE_REVIEW_NOTES_DRAFT.md)、
[App Privacy](docs/release/APP_STORE_PRIVACY_ANSWERS_DRAFT.md)、
[App Store 元数据](docs/release/APP_STORE_METADATA_DRAFT.md)、
[OpenAI 授权申请](docs/release/OPENAI_AUTHORIZATION_REQUEST_DRAFT.md)、
[插件 Preview 1 Release 记录](docs/release/PLUGIN_RELEASE_V1.0.0_PREVIEW.1.md)、
[插件 Preview 3 候选记录](docs/release/PLUGIN_RELEASE_V1.0.0_PREVIEW.3_DRAFT.md)。

产品所有者本机审核入口：
[App Store 初步改造本机审核单](docs/release/LOCAL_MANUAL_REVIEW_CHECKLIST.md)。

2026-08-08：用户明确将商业模式改为 Mac App Store 付费下载，基准价格
`USD 4.99`，全部内置功能可用，不再单独付费解锁 Codex 灵动岛。当前实现已
删除 StoreKit 商品、交易状态、购买/恢复界面、`.storekit` 本地配置、相关
测试和发行门禁；配对插件后，新鲜有效事件可以直接驱动灵动岛，不依赖
OpenAI 账号或 App 内购买资格。App Store Connect 尚需接受 Paid Apps
Agreement 并配置 `USD 4.99`，完成前
`QUOTAVIEW_APP_PRICE_STATUS = pending`。本次变更前生成的 Archive 和 `.pkg`
只保留为历史导出证据，最终门禁关闭后必须重新构建。

2026-08-08：用户明确将当前交付边界收口为“完成初步改造后由产品所有者
手动审核”，Codex 不负责上传 App Store Connect、提交 App Review 或继续发布
主 App / 插件版本。本阶段复用现有自动验证证据，不为了扩大覆盖面随意新增
测试代码，也不重复执行已有充分证据的整套回归；只保留当前源码必要的构建、
静态检查和交付审计。视觉、交互、真实账号及业务状态由产品所有者运行确认，
在得到明确结论前继续标记为“等待用户验收”。付费 App 价格、Preview 7
固定 Release、公开页面、内容权利、全新插件环境和最终提交包仍是以后单独
授权的发行门禁，不阻塞本次本机初审
交付。

2026-08-08：首次使用且尚无有效 `usage.json` 时，状态栏面板会在
原有 `117 pt` 用量概览区域显示本地化“Codex 连接”入口；入口
关闭面板并精准选中设置的“连接与灵动岛”页。有效快照到达后自动
恢复用量图表，并重新遵循“周期用量概览”显示偏好。视觉和交互
等待产品所有者验收。

2026-08-06：用户正式淘汰包内 Codex App Server Runtime 生产路线，改用
全原生 Swift Account Provider。AI Usage Tracker 作为已经通过 Mac App
Store 审核的真实案例，是沙盒、OAuth PKCE、Keychain、直接 HTTPS 用量与
轻量包体的首要实践参考；CodexBar 只作为刷新并发、容错解码和 stale 快照的
次要工程参考。QuotaView 自己完成登录、Token 刷新和登出，凭证只存自有
Keychain；基础额度候选路径为 `wham/usage`，最近一天与累计 Token 候选路径
为 `wham/profiles/me`。两条非公开路径必须先通过 QuotaView 自有回调和真实
账号 Spike，不读取 `~/.codex/auth.json`、Cookie、浏览器数据或外部 Keychain，
也不使用 CLI、Runtime、WebKit 或本地会话扫描作为回退。
原生网络层会在跟随重定向之前验证 HTTPS、主机、有效端口和 URL 用户信息，
Token、刷新请求体及 Authorization 不会先发送到不同 origin 再依赖最终响应
校验补救。Access/Refresh/ID Token 还会执行大小、空白和控制字符校验，账号
ID 在进入 HTTP Header 前也必须通过有界安全检查。账号恢复、连接、重新授权
检查与断开共享单调修订号，旧 Keychain 查询或浏览器回调不能覆盖较新的断开
状态。
主动登出或账号切换还会先提高 Provider configuration revision，立即清空旧
账号在主 App、Widget 和本地诊断中的额度快照，再用新凭证刷新；旧账号数据
不会被普通网络失败的 stale 快照策略继续保留，新账号第一次返回也不会因旧
`expectedAccountScope` 被丢弃。
Release 账号 Runtime 现额外固定为 `approved-only`：OAuth Client 与 usage API
只要任一不是 `approved`，即使 Keychain 残留 Debug 凭证，账号控制器也会在
启动恢复和重新授权检查之前停止，Provider 同样不会读取凭证或发出网络请求；
仅 Debug 配置显式使用 `candidate-allowed` 继续支持真实账号 Spike。该策略已
写入最终 Info.plist，并由 readiness 与 Bundle 审计复核。

此前 Runtime Phase 0 已从固定 `rust-v0.146.1` 完成双架构、Device Code、
Keychain、真实额度和沙盒验证，但 Universal Runtime 约 434–437 MiB，与轻量
定位冲突。该结果现已归档为历史 No-Go，不再等待包体或嵌套 Runtime Archive
决策，也不得重新作为当前开发入口。完整证据仍保留在
[Runtime Phase 0 报告](docs/spikes/APPSTORE_ACCOUNT_RUNTIME_PHASE0.md)。

版本管理继续沿用：App Store 主应用使用同一 `Duoasa/QuotaView` 仓库的独立
worktree，不复制第二个 QuotaView 主应用仓库；灵动岛插件使用独立 Git 仓库
和独立版本。主应用工作区为
`/Users/sukduoasa/Documents/QuotaView-AppStore`，分支为
`codex/appstore-runtime-spike`。插件本地仓库已经创建在
`/Users/sukduoasa/Documents/QuotaView-for-Codex`，首个版本为
`1.0.0-preview.1`；本地 annotated tag `v1.0.0-preview.1` 已固定到提交
`76262d40aded1e1c5f27168214762f41b382629f`。公开仓库
`Duoasa/QuotaView-for-Codex` 已创建，`main` 与该固定 tag 已推送；GitHub
branch/tag Actions 均通过，匿名 HTTPS 固定 tag 克隆、桥接测试与官方插件
校验通过。固定 tag 的公开 Pre-release 已创建：
`https://github.com/Duoasa/QuotaView-for-Codex/releases/tag/v1.0.0-preview.1`。
确定性自定义资产文件大小
`8,363 bytes`、SHA-256
`ed03dbc8651e4dd73f8079216daf28365f8aa172a324de5f94ca02a1bd6afd55`；从
GitHub Release 回下载后大小与 SHA-256 一致，并在全新临时目录完成插件清单、
桥接测试及固定 tag 内容复验。无本地 Marketplace/插件状态的新 Codex 用户
环境安装、Hook 信任、配对、真实事件、卸载和重装验收仍待完成。

插件工作区另有未提交、未发布的 `1.0.0-preview.2` 本地候选：Hook、桥接脚本
和 Setup Skill 已改为优先使用当前 Codex 官方 `PLUGIN_ROOT` / `PLUGIN_DATA`，
并保留旧环境变量兼容；官方插件 validator、Skill validator、桥接测试、
Shell 语法与差异检查均通过。当前用户的本地 Marketplace 安装缓存已更新到
`preview.2`；两个新的 ephemeral Codex CLI 真实会话共生成 10 项连续事件，
其中第二个会话实际执行一次只读 shell 工具，成对写入归类为 `shell` 的
`PreToolUse` / `PostToolUse`，并通过 QuotaView 生产读取器的目录安全、
manifest/status、序列和完整事件顺序端到端检查。数据目录/文件权限为
`0700` / `0600`，敏感字段名扫描无命中。显式 E2E 脚本现为读取用户指定的
外部 `PLUGIN_DATA` 加入 `swift test --disable-sandbox`，避免嵌套 SwiftPM
sandbox 在受控构建环境中阻断生产读取器；同一 10 项真实事件已再次通过，
脚本不会写入 Codex 配置或事件目录。该自动化使用已审计 Hook 的信任
旁路，不等同于干净用户的手动 Hook 审阅、目录配对和视觉验收；公开安装与
App Review Notes 仍固定在 `v1.0.0-preview.1`。另已在全新的隔离 Codex
配置目录中从零添加本地候选 Marketplace，完成 `preview.2` 首次安装、启用、
卸载和重装，重装缓存与候选源码逐文件一致；公开固定 tag 安装/升级仍需在
候选发布后验证。插件仓库现已把该隔离流程固化为脚本，并新增固定 annotated
tag 的确定性资产构建/解包复验与 CI artifact workflow；使用公开
`v1.0.0-preview.1` 回归时重新得到原 `8,363 bytes` 和相同 SHA-256，证明工具
不会改变既有发布资产。workflow 不会自动创建 GitHub Release。候选的提交、
推送、新 tag、Release 和干净用户环境验收必须按
[Preview 2 候选记录](docs/release/PLUGIN_RELEASE_V1.0.0_PREVIEW.2_DRAFT.md)
另行完成。

历史记录（已于 2026-08-08 的付费下载全功能决策取代）：2026-08-06 用户接受
Git Marketplace 双通道插件桥接方案，并将 Codex
实时灵动岛确定为 StoreKit 2 非消耗型 IAP 一次性永久解锁功能。基础额度、
主面板、菜单栏和 Widget 不进入付费墙；公开插件可以在购买前安装并完成连接
检查，但只有有效 StoreKit entitlement 可以消费实时事件并展示灵动岛。
Preview 阶段
由公开 Git 仓库分发 `QuotaView for Codex` 配套插件，未来公共目录版本从
同一插件源码和协议发布；QuotaView 只通过用户选择目录的只读
security-scoped bookmark 消费插件 `PLUGIN_DATA` 中的脱敏事件。主 App 已
启用 App Sandbox 与 Network Client，只申请用户所选目录只读访问；并加入
不跟踪、不收集数据及 Required Reason API 的 `PrivacyInfo.xcprivacy`。旧
Hook 安装器、Helper、Expect、Socket、`/tmp` 队列、外部 CLI 和 App Server
链路均已从 App Store 生产目标移除。StoreKit 2 非消耗型购买、恢复购买、
交易监听和 entitlement 门禁已接入；独立插件已通过官方 manifest 验证、
本地桥接测试，并以 `quotaview@quotaview-preview` 安装启用；当前插件本地
提交及本地 annotated tag 均指向
`76262d40aded1e1c5f27168214762f41b382629f`。Release 配置不会内置未经正式
授权的 OAuth Client ID；候选公共 Client 只用于 Debug，候选 usage/profile
HTTPS 路径已经从生产 App 的代码接线上移到可审计构建配置。提交模式预检会在 OAuth
Client 或 usage API 状态不是 `approved`、IAP 未达到 `submission-ready`
（或后续版本的 `approved`）或插件状态不是 `released` 时失败。Debug Scheme 已加入只在测试环境使用的
`QuotaView.storekit`，并通过 App-hosted StoreKit 商品加载和购买交易 2 项
测试；本地测试价格不是最终售价，当前 Xcode StoreKitAgent 缺少测试证书，
因此 verified entitlement、退款和撤销仍必须在 App Store Sandbox 复验。
首个非消耗型 IAP 必须与 `1.0.0` 一起审核，Apple 不会在 App 获批前把商品
标为 `Approved`；提交门禁因此使用内部 `submission-ready` 状态，后续已获批
版本也接受 `approved`，不再形成 Archive 前要求 Apple 已批准的循环依赖。
购买流程已使用单调状态修订号保护异步 entitlement 刷新；verified 购买与
交易更新会先发布解锁或撤销状态，再调用 `finish()`。旧修订可以结束已验证
交易，但不能覆盖较新的退款、撤销或未验证交易状态；首次商品加载也纳入
购买互斥。修改后的 88 项 Swift 测试、五组发行 Shell 回归、App-hosted
StoreKit 商品/交易 2 项和 Universal Release Bundle 审计均通过。
插件桥运行时同样使用单调修订号约束异步目录读取：用户断开插件目录或 App
停止监听后，旧读取的成功或失败结果都不得重新写回连接状态或驱动灵动岛；
新修订目录可立即开始读取，不会被仍在途的旧修订阻塞。
插件重装产生新安装实例时，旧实例的游标、最近事件时间和展示状态会先被清除；
新实例尚无事件时保持等待状态，不能沿用旧实例的连接证据。
StoreKit 接入后的全新 Universal Release 与 Xcode Analyze 已再次通过；正式
App 仍为约 `27 MiB`，主 App、Widget 和 Framework 均为 `x86_64 arm64`，
Bundle 内没有 `.storekit`、`.xctest`、Runtime、CLI、Helper 或 Probe。
双语 [隐私政策草案](PRIVACY.md) 和 [支持页草案](SUPPORT.md) 已建立，通用
设置页已加入两项原生入口；Release 产物写入各自 HTTPS 公开 URL 和 `draft`
状态，只有页面合入公开分支、补齐受监控支持邮箱并把状态改为 `published`
后才会启用入口并通过提交门禁。包内同时声明
`ITSAppUsesNonExemptEncryption = NO`，对应只使用 Apple 系统 TLS、Keychain
和 CryptoKit 的现行实现。App Review Notes、App Privacy、App Store 双语
元数据、IAP 草案和插件 Release 记录已经建立。双语元数据现已加入独立自动
校验并接入普通/提交 readiness：名称、副标题、宣传文本、描述、关键词 bytes、
HTTPS URL、本地化一致性、App Name / Bundle ID、Draft 状态和占位符均会按
Apple 当前限制失败关闭；当前草案和负向 Shell 回归通过。本地 StoreKit 商品
也已修正原先超过 Apple 45 字符限制的中英文 Description，并加入 Product ID、
Reference Name、Display Name、Description、插件依赖与非法配置负向回归；
独立 IAP Review Notes 候选为 `1243 / 4000 bytes`，Product ID、基础功能
免费、插件与恢复购买说明也纳入校验；App-hosted 商品/交易 2 项复验通过。
主仓库 CI 与 PR 模板现已同时执行 Swift
测试、五组发行 Shell 回归和普通 readiness；Privacy Manifest 回归会
固定 `UserDefaults CA92.1`、用户所选目录元数据 `FileTimestamp 3B52.1`、无
跟踪/无收集声明，并拒绝未审计源码类别或最终 Bundle 清单数量漂移；OAuth
URL/ATS 回归固定完整 `quotaview://oauth/openai` 回调、唯一 `quotaview`
Scheme、`Editor` 角色和零 ATS 例外。源码配置、运行时与最终 Bundle 必须一致；
host/path 漂移时账号控制器会在读取 Keychain 前失败关闭。尚未关闭
的发布门禁是
OpenAI 对 QuotaView OAuth Client 和只读 usage API 的正式授权与真实账号验证、
App Store Connect IAP 配置、插件全新环境验收、隐私政策与支持页公开/支持邮箱、
最终提交包，以及产品所有者的视觉和交互验收。当前已加入
`scripts/check-appstore-readiness.sh` 与 `scripts/build-appstore-archive.sh`，
但后者会在这些外部门禁关闭前保持 fail-closed；通过门禁后也会在导出前调用
`scripts/check-appstore-bundle.sh --submission`，复核最终包的版本、Universal
架构、资源、禁止残留、签名和沙盒 entitlement，并在导出后调用
`scripts/check-appstore-export.sh` 验证唯一 `.pkg` 的安装包签名、Team ID、
Payload、大小和 SHA-256。导出审计会使用 `ditto` 从 component package
恢复 AppleDouble/扩展属性后，对实际 Payload 内的主 App、Widget 与 Framework
再次执行深度验签、Universal、沙盒 entitlement 和嵌入 profile 核对；最终
Archive 流程使用 `--submission`，不会只验证外层 Installer。
本机已有 Apple Distribution 证书；`build-appstore-archive.sh --signed-local`
已在不允许自动
provisioning、不导出、不上传的条件下完成签名 Archive，并通过 Universal、
签名链和沙盒 entitlement 审计。Archive 首次暴露的应用类别缺失警告已通过
声明 `public.app-category.developer-tools` 修复，复验不再出现该警告。随后在
2026-08-07 的 OAuth 完整回调与 StoreKit 生命周期加固后，当前源码再次生成
Apple Development 本地 Archive；沙盒外 `codesign --verify --deep --strict`
确认主 App、Widget 与 QuotaViewCore 有效，Team ID 均为 `BUUH229D5Q`，主 App
权限只包含 Sandbox、App Group、Network Client 和用户所选目录只读，Widget
只包含 Sandbox 与同一 App Group。该无自动 provisioning 的开发型 Archive
不含 embedded profile、没有导出，也不得冒充提交产物。随后在
不允许 provisioning 更新的条件下尝试 App Store export，准确失败于
`No profiles for 'com.quotaview.menubar' were found`。经用户明确授权后，Xcode
创建并下载主 App 的 Mac Team Store profile
`5ab922d3-9937-4cd0-882f-4e1a3de38e54`（有效期至
`2027-08-06T12:56:46Z`），将主 App、Widget 与 Framework 重新签为
Apple Distribution，并成功导出 `QuotaView.pkg`。安装包大小
`11,787,190 bytes`，SHA-256
`fbb16b30dfd26a1840c49f883f655976d8db339d1b462a2604c6586946ea15ac`；
Installer → Apple WWDR G3 → Apple Root CA 信任链、Team ID、Payload 和禁止
残留审计通过；实际解出的主 App、Widget 与 Framework 也通过 Apple
Distribution 深度验签、Universal、沙盒/App Group/只读权限和嵌入 profile
核对；Payload 只有主 App、Widget 和 QuotaViewCore 三个预期可执行文件，动态
链接仅包含 QuotaViewCore、公开系统 Framework 与 `/usr/lib`，无私有 Framework
或外部二进制依赖。源码门禁也未发现 Process/NSTask、WebKit、Sparkle、
AppleScript、辅助功能或屏幕捕获路径。该包只证明 distribution export 链路
可用；其后账号 Provider 又加入 Token 最终 origin、刷新账号范围和异常凭证
fail-closed 加固，因此该 SHA-256 不再对应当前工作区源码，不能作为当前或
最终提交包。该历史候选生成时，Release OAuth、App Store Connect IAP 和插件
全新环境状态仍未批准，因此它不是可上传的最终提交
包，也未上传 App Store Connect。

2026-08-05：用户明确授权 App Store `1.0.0` 移除额度重置功能。当前分支已
删除主面板入口、重置详情页、最终确认层、对应设置、Demo 执行器、Widget
快照字段、Probe 输出和专用资源；“下次重置”倒计时与普通 Credits 余额
继续保留为只读信息。源码残留搜索与当时 `swift test` 执行 77 项、0 失败、
普通运行中显式 live 插件 E2E 1 项跳过，提供真实目录后的单独运行通过；无签名
Universal Xcode Release 构建通过，App、Widget 与 Framework 均为
`x86_64 arm64`，产物为 `1.0.0 (Build 3)` / `appstore`，已编译资源与二进制
无额度重置入口残留。

## 0. 版本定位入口

公开发布版本的唯一索引位于：

**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**

当前公开 Latest 为：

| 项目 | 当前值 |
|---|---|
| 最新推荐版本 | `0.3.1 (Build 2)` |
| tag | `v0.3.1-build.2` |
| 发布提交 | `3119171f45163fe45d68a4f774a0488968f14fd7` |
| Release | [QuotaView 0.3.1 Build 2 — Widget Hotfix](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1-build.2) |
| 资产 | `QuotaView-v0.3.1-build.2.zip` |
| SHA-256 | `9051b60799a5a20e578c2eea4e3f3a5b3725109b553fc8580473953c0f59a1ed` |

`0.3.1 (Build 2)` 已完成 Developer ID 签名、Apple 公证、Staple、
GitHub Release、Latest 切换和 GitHub 回下载复核，是当前公开生产基线和
本轮 App Store 适配的不可移动代码基座。

2026-08-01：`0.3.1 (Build 2)` Widget 热修复已完成实现、安装验证和正式
发布。macOS
系统日志确认，公开 Build 1 的 Widget 在 Developer ID 直接分发环境中被
`SystemPolicyAppData` 拒绝读取 `group.com.quotaview.shared`。Build 2 将
App Group 迁移为团队前缀 `BUUH229D5Q.com.quotaview.shared`，符合未嵌入
provisioning profile 的公证 App 共享容器要求。`swift test` 共 `53` 项
通过，Universal Release 构建和 Developer ID 签名验证通过；App、Widget
与 Helper 均为 `x86_64 arm64`。安装后新容器写入有效快照，Widget 时间线
成功归档，内核不再出现共享快照读取拒绝；视觉结果等待产品所有者验收。
正式发布资产已完成 Apple 公证、Staple、GitHub 上传和回下载复核。

Build 2 将主面板与 Widget 的额度标题从“本周剩余”统一调整为“本周期
剩余”，英文使用两词 `Period Remaining`，以兼容 Codex 的 5 小时、7 天
及后续可变用量周期；Tooltip、VoiceOver 与实现内部命名同步使用周期语义。

### 0.3.1 Build 2 发布归档

目标发布元数据：

| 项目 | 发布值 |
|---|---|
| Marketing Version | `0.3.1` |
| Build Number | `2` |
| tag | `v0.3.1-build.2` |
| Release 标题 | `QuotaView 0.3.1 Build 2 — Widget Hotfix` |
| 最终资产名 | `QuotaView-v0.3.1-build.2.zip` |
| App Group | `BUUH229D5Q.com.quotaview.shared` |
| 最低系统版本 | macOS 14 |
| 架构 | Universal `arm64 + x86_64` |

正式发布资产：

| 项目 | 当前值 |
|---|---|
| 文件 | `dist/QuotaView-v0.3.1-build.2.zip` |
| 大小 | `11,443,325 bytes` |
| SHA-256 | `9051b60799a5a20e578c2eea4e3f3a5b3725109b553fc8580473953c0f59a1ed` |
| 签名 | `Developer ID Application: Chenchen Xu (BUUH229D5Q)`，Hardened Runtime |
| 公证 | Apple Accepted，已 Staple；Submission `0ff9bf81-3570-4243-b3be-5d076b0f888c` |

正式 ZIP 已在全新目录解压、附加隔离属性并通过
`codesign --verify --deep --strict`、`stapler validate`、`spctl`、版本、
架构、资源与真实启动烟雾测试；App、Widget 与 Helper 均包含
`x86_64 arm64`，App 与 Widget entitlement 均包含团队前缀 App Group。

GitHub Release Notes 使用以下单份英文源正文；GitHub 界面负责翻译：

```markdown
QuotaView 0.3.1 Build 2 is a focused hotfix for WidgetKit data sharing and
variable Codex quota periods.

## Fixed

- Restored Small and Medium widget data for notarized direct downloads by
  migrating the shared container to the team-prefixed App Group
  `BUUH229D5Q.com.quotaview.shared`.
- Renamed “Weekly Remaining” to “Period Remaining” so the interface works for
  5-hour, 7-day, and future variable quota periods. The Simplified Chinese
  title is now “本周期剩余”.
- Added a release packaging check that rejects a non-team-prefixed App Group
  unless the app embeds a provisioning profile.

## Requirements

- macOS 14 or later
- A Codex version with Hooks support
```

Build 2 发布检查清单：

- [x] 源码、App 与 Widget 版本统一为 `0.3.1 (Build 2)`；
- [x] App Group 迁移为 `BUUH229D5Q.com.quotaview.shared`，并加入打包门禁；
- [x] 主面板与 Widget 使用“本周期剩余” / 两词 `Period Remaining`；
- [x] `swift test` 53 项通过，0 失败；
- [x] Universal Xcode Release 构建通过；
- [x] Developer ID 本地候选签名、全新解压验签、版本、架构、资源和
  entitlement 检查通过；
- [x] 新共享容器写入有效快照，Widget 时间线成功归档，内核没有新的
  `SystemPolicyAppData` 读取拒绝；
- [ ] 产品所有者确认小号 / 中号、深色 / 浅色和中英文最终视觉；
- [x] 使用 `NOTARY_PROFILE` 生成无 `candidate` 后缀的最终资产，完成 Apple
  公证与 Staple；
- [x] 对最终 ZIP 全新解压并执行 `codesign`、`stapler`、`spctl`、版本、
  架构、资源、隔离属性和真实启动烟雾测试；
- [x] 将最终资产大小、SHA-256 和 Submission ID 同步到本文件；发布提交、
  `VERSION_HISTORY.md` 与 README 中英文版本待 Release 建立后同步；
- [ ] 创建发布提交，使用唯一 tag `v0.3.1-build.2`，上传唯一正式 ZIP，
  将 GitHub Latest 切换到 Build 2；
- [ ] 从 GitHub 回下载资产，逐字节核对并再次验签和启动测试。

2026-08-01：宣传片摄录专用的本地 `0.3.2 Demo` 已结束使用；灵动岛已
恢复为完成后 `20` 秒紧凑、
完成满 `120` 秒隐藏的正式时序。摄录 ZIP 仅作为本地产物保留，不属于当前
源码版本，也没有 tag、Release 或 GitHub Latest。恢复后 `swift test` 共
`52` 项通过、`0` 项失败；Universal Xcode Release 无签名构建通过，App、
Widget 与 Helper 均包含 `x86_64 arm64`。视觉与实机时序等待产品所有者验收。

文档职责：

- `HANDOFF.md`：当前开发状态、验证结论和发布入口；
- `VERSION_HISTORY.md`：公开版本、tag、Release、资产与撤回记录；
- `AGENTS.md`：长期产品、设计、实现和发布约束；
- `design-qa.md`：视觉验收历史。

## 1. 0.3.1 正式发布状态

### 版本定位

| 项目 | 当前值 |
|---|---|
| Marketing Version | `0.3.1` |
| Build Number | `2` |
| 开发主题 | Codex 灵动岛 + Widget 共享容器热修复 |
| 发布状态 | 正式 Release、Latest、非 Draft、非 Pre-release |
| 公开 Latest | `0.3.1 (Build 2)` |

### 已实现

- 将独立 Metal Demo 重构进 QuotaView 主 App，不再依赖 Debug 控制器；
- 使用 Codex 官方 Hooks 覆盖 `SessionStart`、`SessionEnd`、
  `UserPromptSubmit`、工具、批准、上下文压缩、子任务和 `Stop` 事件；
- 新增独立签名辅助程序 `QuotaViewActivityHook`，嵌入
  `Contents/Helpers`；
- 辅助程序只转发哈希会话标识、工作区末级名称、事件、工具类别、
  SessionStart 来源与时间，不转发提示词、命令、参数、输出或记录路径；
- 主 App 优先通过权限为 `0600`、带随机令牌的 Unix Socket 接收脱敏
  事件；当 Codex 沙盒拒绝 Unix Socket 时，Helper 自动回退到当前用户
  独占的 `/tmp` 原子文件队列，目录权限为 `0700`、事件文件为 `0600`，
  主 App 仍执行随机令牌、文件所有者、类型、大小与时效校验；
- 通过 App Server `thread/list` 匹配当前会话名称；界面不展示
  `thread.preview`；
- 实现最大态、紧凑态和隐藏三阶段状态机：完成后 20 秒紧凑，完成满
  120 秒隐藏，新事件立即重新展开；
- 保留 Demo 中已确认的 Metal 流体球、状态配色、上下文白色挤压、
  三行真实字形居中、尾部缩略和操作文案扫光；
- 新增设置页一键安装编排：检测 Codex 版本与 Hooks 功能，必要时执行
  官方 `codex features enable hooks`，更新固定路径 Helper，合并用户级
  Hook，并自动打开 Codex CLI；用户等待 CLI 首次加载完成，等待
  QuotaView 自动输入 `/hooks` 并进入 Hooks 页面后再按 `T`，随后
  QuotaView 自动识别确认结果并关闭临时 CLI；
- 设置页改为新手向单步引导，默认隐藏 Codex 版本、Hooks、本地桥接和
  诊断路径等技术信息；
- 用户点击“连接 Codex”时立即显示最大态“未连接 Codex”，不再等待安装
  或首个 Hook；完成信任、重启并收到第一条真实 `UserPromptSubmit` 后，
  自动切换为真实活动状态；
- 连接状态拆分为未安装、已安装等待重启、等待信任、等待首个事件、
  已连接和连接异常；只有当前固定 Hook 定义产生的第一条真实
  `UserPromptSubmit` 才建立“已连接”证据；
- 打开审查页时记录 Codex Desktop 进程标识，重启前丢弃设置 CLI 产生的
  事件，避免首次配置过程被误判为已连接；
- 安全确认启动器不再使用固定延迟或输入提示符单一信号，而是等待输入
  提示符出现且终端输出连续稳定 3 秒后发送 `/hooks`；审查页未出现时
  有界重试，官方“Trust all”页面出现前不转发用户按键；
- 用户实际按下 `T` 且 Codex 输出确认结果后，启动器通过权限隔离的本地
  信号通知 QuotaView；设置页自动进入“等待重启”，并提供一次
  “重新启动 Codex”操作；
- 桥接消息同时校验随机令牌与固定命令派生的安装标识，旧 Codex 进程或
  旧 Helper 的残留事件不能越过重启/信任门禁；
- Helper 固定安装到
  `~/Library/Application Support/QuotaView/Helpers/QuotaViewActivityHook`，
  后续应用移动或常规升级不改变 Hook 命令路径；已启用用户在后续启动时
  自动更新 Helper 和校正配置；
- Hook 安装保留既有配置并创建备份；配置结构无效时拒绝覆盖；QuotaView
  自动进入 Codex `/hooks` 页面，但不会代替用户按 `T` 或绕过信任；
- Helper 连接失败时同时写入统一日志和权限隔离的本地诊断日志，内容只含
  时间、错误代码与回退结果，不含会话或任务业务数据；
- App、Widget、Helper 和设置中的 Marketing Version 已更新为
  `0.3.1`，Build Number 保持 `1`。

产品与实现依据：

- [Codex 灵动岛产品文档](docs/design/quotaview-codex-activity-widget-product.md)
- [OpenAI Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [OpenAI Codex App Server](https://learn.chatgpt.com/docs/app-server)

### 当前验证

- `swift test`：52 项通过，0 失败；
- 无签名 Universal Xcode Release 构建通过；
- App、Widget Extension 与 `QuotaViewActivityHook` 均为
  `x86_64 arm64`；
- 最终 App Bundle 中 Helper 位于
  `Contents/Helpers/QuotaViewActivityHook`；
- App 为 `0.3.1 (1)`；
- `AppIcon.icns`、`Assets.car` 与 Asta Sans 字体均存在；
- `scripts/build-app.sh` 语法检查通过，并已加入 Helper 签名、Hardened
  Runtime 与 Universal 架构门禁；
- 正式发布包已使用
  `Developer ID Application: Chenchen Xu (BUUH229D5Q)` 签名并启用
  Hardened Runtime；Apple 公证状态为 `Accepted`，Submission ID 为
  `2b125886-a3dc-4734-a139-280a08302e5c`，App 已完成 Staple；
- 正式资产为 `QuotaView-v0.3.1.zip`，大小
  `11,443,295 bytes`，SHA-256
  `ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d`；
- 最终 ZIP 全新解压后通过 `codesign --verify --deep --strict`、
  `stapler validate` 与 `spctl --assess`；加入下载隔离属性后 Gatekeeper
  返回 `accepted / source=Notarized Developer ID`，真实启动烟雾测试
  持续 5 秒；
- Hook 映射、压缩恢复、事件乱序、20 秒 / 120 秒收起、Codex 环境检测、
  必要时启用 Hooks、固定路径 Helper、重复安装、卸载、既有配置保留、
  无效配置拒绝、真实 `UserPromptSubmit` 连接门禁、重启前设置 CLI 事件
  拒绝、私有启动器真实 PTY `/hooks` 输入、CLI 首次加载与输出稳定等待、
  审查页有界重试和文件队列令牌校验均有自动化测试；
- 真实 `codex exec` 临时会话已触发
  `SessionStart → UserPromptSubmit → Stop`，所有 Hook 均返回 Completed；
- 已从系统 Sandbox 日志确认旧故障是 Helper 访问 Unix Socket 被
  `deny network-outbound`，本轮文件队列回退不要求扩大 Codex 权限，也
  不改变现有 Hook 命令，因此无需重新安装或重新信任；
- 临时虚拟数据、自动展开、自动点击、截图与 UI QA 入口搜索无匹配；
- `git diff --check` 通过。

产品所有者已确认：

- 当前新手向设置流程“比较完整”，可以作为 `0.3.1` 发布候选的功能流程
  基线；
- 流程包含点击连接后立即出现“未连接 Codex”，明确引导等待 CLI 首次加载、
  等待自动输入 `/hooks` 并进入 Hooks 页面后再按 `T`，以及重启与首个
  真实 `UserPromptSubmit` 变为“已连接”。

以上确认只表示设置流程方向与完整性得到认可，不替代正式发布包的最终
实机烟雾测试，也不代表以下视觉、语言与辅助功能矩阵已经通过。

等待产品所有者验收：

- 新手向“Codex 灵动岛”设置页六种连接状态的最终布局、折叠详情、长文案
  适配和按钮交互；
- 完成后 20 秒进入紧凑态、完成满 120 秒隐藏的实机时序；
- 最大态 / 紧凑态的最终视觉、居中、截断和过渡；
- 各状态颜色、流体速度与上下文压缩效果；
- 简体中文 / English；
- Reduce Motion / Increase Contrast / VoiceOver。

### GitHub 发布完成

2026-07-30 已通过 GitHub 远端核对：

- GitHub Latest 为 `v0.3.1`，非 Draft、非 Pre-release；
- `v0.3.1` tag 精确指向
  `041c698ae9755d458fa9f111e4ac74e9711048b9`；
- Release 只有正式资产 `QuotaView-v0.3.1.zip`，大小
  `11,443,295 bytes`；
- README 中英文下载入口均指向 `v0.3.1`，Codex 灵动岛截图位于更新说明
  开头。

实际 GitHub Release 元数据：

| 项目 | 发布值 |
|---|---|
| Tag | `v0.3.1` |
| Release 标题 | `QuotaView 0.3.1 — Codex Island` |
| Release 类型 | 正式 Release、Latest、非 Draft、非 Pre-release |
| 目标提交 | `041c698ae9755d458fa9f111e4ac74e9711048b9` |
| Release URL | <https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1> |
| 上传资产 | `QuotaView-v0.3.1.zip` |
| 最终大小 / SHA-256 | `11,443,295 bytes` / `ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d` |
| 公证 | Apple Accepted，已 Staple；Submission `2b125886-a3dc-4734-a139-280a08302e5c` |

GitHub Release Notes 使用以下单份英文源正文；GitHub 界面负责翻译，不再
额外维护一份中文 Release 正文：

```markdown
QuotaView 0.3.1 introduces Codex Island, a native macOS activity surface that
shows Codex status with a live Metal-rendered fluid sphere.

## What's new

- Added expanded, compact, and hidden Codex Island states with smooth
  transitions and status-specific motion and color.
- Added live Codex lifecycle tracking through official Hooks, including tool
  use, permission requests, context compaction, subagents, completion, and
  failures.
- Added a guided one-click setup flow in Settings. QuotaView installs and
  updates its fixed-path helper, preserves existing hooks, opens the official
  `/hooks` review page, and asks for the one trust confirmation required by
  Codex.
- Added clear connection states, immediate “Codex not connected” feedback,
  automatic restart guidance, and real-event verification before reporting a
  successful connection.
- Codex Island compacts 20 seconds after completion and hides after 2 minutes;
  new activity expands it immediately.

## Privacy and security

QuotaView forwards only a hashed session identifier, the last workspace path
component, event type, coarse tool category, session source, and timestamp. It
does not collect prompts, commands, arguments, tool output, or transcript
paths. Hook trust is never bypassed.

## Requirements

- macOS 14 or later
- A Codex version with Hooks support

SHA-256:
`ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d`
```

发布检查清单：

- [x] 版本号为 `0.3.1 (Build 1)`；
- [x] `swift test` 52 项通过；
- [x] Universal App、Widget、Helper 与 Framework 均包含
  `x86_64 arm64`；
- [x] Developer ID 签名与 Hardened Runtime 已通过全新解压验证；
- [x] 产品所有者认可当前设置流程完整性；
- [x] 审查工作区提交范围；Prototype、参考文档和其他用户资料未纳入；
- [x] 产品所有者明确要求发布 0.3.1；剩余视觉矩阵仍等待逐项验收，不
  提前记录为“已通过”；
- [x] 使用 `NOTARY_PROFILE` 重新构建，完成 Apple 公证与 Staple；
- [x] 对最终 ZIP 全新解压并完成 `codesign`、`stapler`、`spctl`、版本、
  架构、资源和真实启动烟雾测试；
- [x] 更新本节最终资产大小与 SHA-256；
- [x] 创建发布提交并推送，确认 tag 精确指向该提交；
- [x] 创建 `v0.3.1` Release，上传唯一最终 ZIP，并设为 Latest；
- [x] 同步 README 中英文下载入口、`VERSION_HISTORY.md` 与本文件的公开
  Latest；
- [x] 从 GitHub 回下载资产，逐字节核对并再次执行验签和启动测试。

0.3.1 已通过 PR [#12](https://github.com/Duoasa/QuotaView/pull/12)
合并并正式发布。GitHub 回下载资产与本地最终 ZIP 逐字节一致；回下载 App
通过签名、公证、Gatekeeper 和 5 秒真实启动复核。

## 2. 0.2.1 正式发布

### 版本与目标

| 项目 | 当前值 |
|---|---|
| Marketing Version | `0.2.1` |
| Build Number | `1` |
| 最低系统版本 | macOS 14 |
| App Bundle ID | `com.quotaview.menubar` |
| Widget Bundle ID | `com.quotaview.menubar.widget` |
| App Group | `group.com.quotaview.shared` |
| 架构 | Universal `arm64 + x86_64` |
| Development Team | `BUUH229D5Q` |
| 发布状态 | 正式 Release、Latest、非 Draft、非 Pre-release |
| Git tag | `v0.2.1` |
| Release 资产 | `QuotaView-v0.2.1.zip` |
| 资产大小 | `10,907,231 bytes` |
| SHA-256 | `99e7fb951d4abd6475204c059f1e16481dac8be4c3b72e6b19889fc54737521b` |

### 关键更新

- 新增原生 WidgetKit 扩展，支持 macOS 小号与中号小组件；
- 主 App 通过 App Group 原子写入最小、脱敏且带过期时间的快照，Widget
  只读快照，不直接访问网络、凭据或 Codex App Server；
- 小组件接入真实额度、重置时间、Credits、今日 Token、累计 Token、
  订阅方案和连接状态；缺失、错误或过期时显示不可用和破折号，不伪造
  `0%`；
- 按 Figma 节点 `34:1846` 完成小号/中号、深色/浅色 Widget UI，并修复
  SwiftUI 紧行高导致 Asta Sans 字号被二次缩小的问题；
- 按 Figma 节点 `1:704` 更新状态栏菜单 UI、进度条、连接状态和局部
  Liquid Glass；
- 订阅方案统一映射为 OpenAI 官方名称，未知协议值显示破折号；
- 恢复 Apple 正式开发环境：主 App 与 Widget 使用 Automatic Signing、
  正式 App Group entitlement 和各自的显式 App ID；
- 构建脚本已覆盖嵌套 Widget Extension 的签名、版本、Bundle ID、架构、
  extension point、sandbox 与 App Group 校验。

### 产品与安全边界

- 当前功能保持只读；
- Widget 快照不得包含认证 Token、Cookie、账号标识、完整响应或历史明细；
- Widget 不得自行启动 Codex App Server；
- 额度重置仍为本地 Demo，不得调用
  `account/rateLimitResetCredit/consume`；
- Release 构建不得包含调试虚拟数据、自动展开、自动点击、截图或 UI QA
  入口。

## 3. 0.2.1 验证状态

已完成：

- `swift test`：33 项通过，0 失败；
- Apple Development Xcode Debug 构建通过，主 App 与 Widget 的开发
  Profile 均包含 `group.com.quotaview.shared`；
- 无签名 Universal Xcode Release 构建通过；
- App、`QuotaViewCore.framework` 与 Widget Extension 均为
  `x86_64 arm64`；
- App 与 Widget 均为 `0.2.1 (1)`；
- Widget Extension 包含 `Assets.car`、Asta Sans 字体和简体中文资源；
- `codesign --verify --deep --strict` 已在开发构建链路通过；
- 产品所有者已确认主 App 写入、Widget 读取和 timeline 刷新成功；
- 临时虚拟数据、真实额度消费调用和 UI QA 入口搜索无匹配。
- GitHub Actions 33 项测试通过；
- 最终 App、Framework 与 Widget 使用 Developer ID 签名并启用
  Hardened Runtime；
- Apple notarization 返回 `Accepted`，Submission ID 为
  `e211abde-be96-47eb-a5ca-50ec1df7f260`；
- App 已 Staple，`stapler validate` 与 `spctl` 均通过；
- 全新解压和 GitHub 回下载资产均通过 `codesign --verify --deep --strict`；
- GitHub 回下载 ZIP 与本地最终包逐字节一致；
- 加入下载隔离属性后 Gatekeeper 仍返回
  `accepted / source=Notarized Developer ID`；
- GitHub 回下载 App 的真实启动烟雾测试持续 5 秒，没有发现
  Framework 加载、签名或 `fatalDyldError`。

等待产品所有者验收：

- 小号 / 中号；
- 浅色 / 深色；
- 简体中文 / English；
- Increase Contrast / Reduce Motion / VoiceOver；
- 菜单与 Widget 的最终视觉、Hover、Pressed、Disabled 和键盘交互。

视觉与交互矩阵在用户明确确认前不得记录为“已通过”。

## 4. 0.2.1 发布完成状态

钥匙串中已确认存在：

- `Apple Development: Chenchen Xu (Z6X48CV8PX)`；
- `Apple Distribution: Chenchen Xu (BUUH229D5Q)`；
- `Developer ID Application: Chenchen Xu (BUUH229D5Q)`。

已完成：

1. PR [#9](https://github.com/Duoasa/QuotaView/pull/9) 经 GitHub Actions
   验证后合并；
2. 发布提交为
   `56aa71dd9f4013412f90c75e0c282a610e87d14e`；
3. `v0.2.1` tag 与正式 GitHub Release 已创建并设为 Latest；
4. `QuotaView-v0.2.1.zip` 已使用 Developer ID 签名、完成 Apple 公证与
   Staple；
5. Release Notes 只保留一份英文源正文；
6. README 中英文下载入口和产品预览图已更新；
7. GitHub 回下载、SHA-256、签名、公证、Gatekeeper 与真实启动复核完成。

正式 Release：

<https://github.com/Duoasa/QuotaView/releases/tag/v0.2.1>

此前生成的 ad-hoc `0.2.1 Build 1` ZIP 早于最终 Widget UI，不是正式发布
资产，后续不得替换当前 Release。

如 Marketing Version 保持 `0.2.1` 但需要发布热修复，必须增加 Build
Number，并为 tag 和 ZIP 加入唯一 Build 标识。

## 5. 0.2.1 实现边界

数据链路：

```text
CodexProviderAdapter
→ CodexStatusStore
→ sanitized WidgetSnapshot JSON
→ group.com.quotaview.shared
→ QuotaViewWidgetExtension
```

实现约束：

- 主 App 是唯一数据获取方；
- Widget 快照默认 15 分钟过期，timeline 最短 5 分钟重新读取；
- 主数据刷新、可用状态或语言变化时更新快照；
- 可选 Credits 或 Token 数据缺失不能覆盖有效额度状态；
- 主面板继续使用 Asta Sans，设置窗口继续使用系统字体；
- 菜单与 Widget 的详细视觉令牌以 `AGENTS.md` 和对应 Figma 节点为准；
- 不增加第二层主面板玻璃，不接入真实额度重置接口。

## 6. Git 工作区

0.3.1 源码、测试、README、灵动岛截图和产品文档已通过 PR
[#12](https://github.com/Duoasa/QuotaView/pull/12) 合并，发布 tag 指向：

```text
041c698ae9755d458fa9f111e4ac74e9711048b9
```

以下未跟踪 Prototype 与参考资料未进入 0.3.1 发布提交，所有权和后续提交
范围仍未确认，默认不得擅自纳入：

```text
Prototypes/
docs/reference/
quotaview-blurred-gradient-background-2k.png
subtract-frosted-glass-icon-transparent.png
subtract-frosted-glass-icon.png
```

不得使用 `git clean`、`git reset --hard` 或 `git checkout --` 清理用户
文件。

## 7. 发布门禁

发布前至少执行：

```bash
swift test

rg -n \
  'DEBUG-ONLY-MOCK|DEBUG MOCK|DEBUG ONLY|仅用于调试|debugResetCreditOverride|displayAvailableResetCredits' \
  Sources Tests

rg -n 'account/rateLimitResetCredit/consume' Sources Tests

git diff --check
git diff --cached --check
git status --short --branch
```

正式签名、公证和打包：

```bash
CODESIGN_IDENTITY="Developer ID Application: Chenchen Xu (BUUH229D5Q)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

发布产物至少检查：

```bash
codesign --verify --deep --strict --verbose=4 QuotaView.app
spctl --assess --type execute --verbose=4 QuotaView.app
lipo -archs QuotaView.app/Contents/MacOS/QuotaView
lipo -archs \
  QuotaView.app/Contents/PlugIns/QuotaViewWidgetExtension.appex/Contents/MacOS/QuotaViewWidgetExtension
```

仅验签不足以证明可发布。必须全新解压并进行真实启动测试；发布后还要从
GitHub 回下载再次验证。

## 8. 文档联动

0.3.1 已在同一发布任务内完成：

1. 将 `VERSION_HISTORY.md#当前最新版本` 更新为 0.3.1；
2. 在版本总览和版本详情中记录 tag、发布提交、Release URL、资产名、
   大小、SHA-256、签名、公证和验证结论；
3. 将本文件的版本入口、发布、验证与完成状态由候选状态更新为发布事实；
4. 更新 README 中英文下载入口、Codex 灵动岛重点文案和预览图；
5. 确认 GitHub Release Notes 只有一份英文源正文；
6. 确认已撤回的 `0.2.0 Build 3` 不会重新成为下载或开发基线。

README 下载入口、GitHub Latest 和
`VERSION_HISTORY.md#当前最新版本` 当前均指向 `v0.3.1-build.2`。已撤回的
`0.2.0 Build 3` 继续只保留历史记录，不得恢复为下载或开发基线。
