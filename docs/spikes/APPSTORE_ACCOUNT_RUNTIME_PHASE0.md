# App Store Codex Account Runtime Phase 0 Spike 报告

> 文档编号：`QV-SPIKE-APPSTORE-ACCOUNT-RUNTIME-P0-001`
>
> 执行日期：2026-08-06
>
> 分支：`codex/appstore-runtime-spike`
>
> 稳定基座：`0.3.1 (Build 2)` / `v0.3.1-build.2` / `3119171f45163fe45d68a4f774a0488968f14fd7`

> [!NOTE]
> 本报告是已执行的历史技术证据。产品所有者已于 2026-08-06 选择轻量原生
> Swift Account Provider，当前实施规格为
> [`QV-APPSTORE-NATIVE-ACCOUNT-PROVIDER-001`](../design/quotaview-app-store-native-account-provider.md)。
> 本报告中的 Runtime Go / No-Go 条件不再阻塞现行路线，也不得被解释为仍在
> 等待接受约 436 MiB 包体。

## 1. 结论

包内 Codex App Server Runtime 的核心技术路径可行：固定上游版本可以从源码
构建为 `arm64 + x86_64`，在最小沙盒宿主内完成官方 Device Code 登录、
Keychain 恢复、额度读取、登出和进程回收。

对包内 Runtime 路线而言，Phase 0 总门禁结论为 **No-Go**，不得据此进入
Runtime Provider 或 Runtime 登录 UI 改造。
尚未通过的硬门禁为：

1. 当前机器没有有效的 Mac App Distribution 签名身份；现有 3 个 profile
   均是带设备列表的 Mac Team 开发 profile，不是 App Store Distribution
   profile，无法验证真实 Archive、嵌套签名和 profile entitlement；
2. Codex App Server 官方仍标记为实验性接口，生产 `clientInfo.name`、第三方
   客户端登记与服务许可口径尚未获得 OpenAI 确认；
3. Universal Runtime 对包体影响很大，必须先决定是否接受，或与 OpenAI
   评估可否提供只包含账户与额度能力的更小受支持 Runtime。

本 Spike 没有替换生产 Provider、没有实现正式登录 UI、没有开启主 App
Sandbox，也没有修改 Codex Island 链路。直接分发稳定版本和 tag 不受影响。

## 2. 固定上游与构建输入

| 项目 | 固定值 / 结论 |
|---|---|
| OpenAI Codex tag | `rust-v0.146.1` |
| tag object | `abb1de9be901ab658fec7bbbc4a1fa2e85512be3`，annotated、未签名 |
| commit | `79b4f03d35962b005b007a015113b38930711665` |
| Rust | `1.95.0` |
| rusty_v8 | `149.2.0`，两架构归档、binding 与官方 SHA-256 manifest 均通过 |
| License | Apache License 2.0，SHA-256 `d17f227e4df5da1600391338865ce0f3055211760a36688f816941d58232d8dc` |
| 原始 `Cargo.lock` SHA-256 | `828175f2781fe6c83e3396194f1b00d7fab6b2a27017ea0daa896456c4079d77` |
| 规范化 `Cargo.lock` SHA-256 | `15fce946a48df656e1f2496e7be9eab722c053fd6f8ba1fec1077931cb0c6a64` |

该 tag 的 `Cargo.toml` 已是 `0.146.1`，但 `Cargo.lock` 中有 132 个 workspace
包仍使用开发占位版本 `0.0.0`。上游 Release workflow 未使用 `--locked`；
Cargo 首次解析只会把这 132 行版本改为 `0.146.1`，没有依赖名、来源或校验值
变化。构建脚本先校验原始锁文件哈希和占位数量，再做唯一允许的确定性替换，
校验规范化哈希后恢复 `--locked` 构建。

初次完整构建耗时：arm64 `11m56s`，x86_64 `10m52s`。源码构建保留分离
dSYM，复制到捆绑输出的二进制按上游 macOS Release 流程执行
`strip -S -x`。再次执行脚本时，固定 V8 资产直接通过本地哈希校验，两个
Cargo target 分别在 1.75 秒和 1.02 秒内完成；剥离后输出哈希保持一致。

## 3. Spike 工件

| 工件 | 用途 |
|---|---|
| `Tools/AppStoreRuntimeSpike/RuntimeProbe.swift` | 最小 JSONL 客户端、Device Code、Keychain 恢复、额度、登出与进程回收探针 |
| `Tools/AppStoreRuntimeSpike/Host.entitlements` | 沙盒宿主：App Sandbox + Network Client |
| `Tools/AppStoreRuntimeSpike/Runtime.entitlements` | 嵌套 Runtime：App Sandbox + Inherit |
| `scripts/build-appstore-runtime-from-source.sh` | 固定提交、工具链、锁文件和 V8 校验的双架构源码构建 |
| `scripts/prepare-appstore-runtime-spike.sh` | Universal 合成、最小宿主构建、嵌套签名与严格校验 |

探针使用独立 Runtime Home，禁用启动更新、历史持久化和 shell 环境继承；
Runtime 只收到独立 `CODEX_HOME` / `HOME`、私有临时目录、系统 PATH 与 locale。
探针只发送 `initialize`、`initialized`、`account/read`、
`account/login/start`、`account/rateLimits/read` 和 `account/logout`。

输出仅保留登录类型、方案枚举和额度窗口的数字字段；不输出 Token、邮箱、
账号 ID 或原始 RPC。额度重置 Credits 字段明确忽略，不会进入 App Store 数据
模型。Device Code 只在交互期间显示，本报告不保存 URL、短码或账号标识。

## 4. 验证矩阵

| 门禁 | 结果 | 证据摘要 |
|---|---|---|
| 固定 commit 源码构建 | Pass | 两架构均以 Rust 1.95.0、规范化锁文件和校验后的 V8 完成 Release 构建 |
| Universal Runtime | Pass | `lipo` 为 `x86_64 arm64` |
| 最小沙盒继承 | Pass（ad hoc Spike） | 宿主只有 Sandbox + Network；Runtime 只有 Sandbox + Inherit；deep strict 校验通过 |
| arm64 启动与回收 | Pass | `initialize=ok`、退出状态 0、`orphan_process=false` |
| Rosetta x86_64 启动与回收 | Pass | 冷启动使用 60 秒上限后通过；退出状态 0、无孤儿进程 |
| Device Code | Pass | 用户启用 ChatGPT 安全设置中的设备代码授权后，官方流程登录成功 |
| Keychain 恢复 | Pass | App 重启及 arm64 / x86_64 均恢复同一独立 Runtime Home 的 ChatGPT 登录 |
| 真实额度一致性 | Pass | App Server 与 0.3.1 Build 2 基线读取到同一主窗口和重置时间；用量随真实消耗正常变化 |
| 登出与清理 | Pass | `account/logout` 后立即及再次启动均为 signed out；外部 Codex 登录不受影响 |
| QuotaView 回归 | Pass | `swift test` 53 项、0 失败；Universal Xcode Release 无签名构建通过 |
| App Store Distribution Archive | **Blocked** | 当前 Keychain 中 `0 valid identities found`；现有 3 个 Mac Team profile 均带 `ProvisionedDevices`，不是 App Store Distribution profile |
| OpenAI 客户端登记 / 许可 | **Pending** | 生产客户端名称、第三方分发和 App Review 口径需要 OpenAI 书面确认 |

方案枚举在协议中返回 `prolite`；进入产品层时必须继续按现有规则显示为
`Pro 5x`，不能直接显示原始枚举。

## 5. 登录与协议发现

第一次 Device Code 尝试在浏览器端返回 400。原因是账号尚未启用设备代码
授权；用户按官方提示在 ChatGPT 安全设置中启用后，重新生成的短码登录成功。
企业或受管工作区仍可能由管理员策略禁止，因此正式 UI 必须把该错误作为明确
的受支持状态，不得回退为读取 `auth.json` 或复制 Token。

另一个必要的状态机约束是：当前上游先发送 `account/login/completed`，随后
才重新加载认证并发送 `account/updated`。如果在 completed 后立即读取额度，
可能短暂得到 `authentication required`。探针已经改为等待
`account/updated.authMode == chatgpt` 后再调用额度接口。

## 6. 签名、沙盒与 Archive 发现

从官方 Release 下载的精确资产在本机可读到 OpenAI TeamIdentifier，但
`codesign --verify --strict` 报告签名无效，`spctl` 也返回代码签名内部错误；
因此不能把上游签名直接带入 App。将 Runtime 重新签名为仅
`app-sandbox + inherit` 后，账户 RPC 在 arm64 和 x86_64 均正常，说明这些
账户路径不依赖上游资产中的 JIT / unsigned-executable-memory 例外。

这只证明 ad hoc 最小沙盒 Spike。真实 App Store 结论必须来自同一 Archive
中的 App、Widget 和嵌套 Runtime，并逐项对照 provisioning profile。当前主
App 仍是 `ENABLE_APP_SANDBOX = NO`，符合 Phase 0 不提前改生产配置的边界。

另外，位于文件同步工作区内的临时 `.app` 会被重新附加 FinderInfo xattr，
导致签名失败；Spike 构建输出必须放在 `/private/tmp` 或其他非文件同步目录。
正式 Xcode Archive 的 DerivedData / Archive 路径也应避开文件同步目录。

## 7. 包体影响

官方已剥离的两架构可执行文件分别约 211 MiB 与 227 MiB，合成并重新签名后
Universal Runtime 为 `457,697,872` bytes（约 436.5 MiB），SHA-256：
`b38180e4975cb535a16f9b4f93a54d54fde80964d6ab1678f76e97494ac26d09`。

本机源码构建并剥离后的结果为：

| 架构 | bytes | SHA-256 |
|---|---:|---|
| arm64 | `219,492,760` | `0232ec260c5e39b7407be8e1ebddfa7536b07be81c37a5868a14c705223e2d13` |
| x86_64 | `235,176,728` | `2fe3142544355a4c748122f7e77477426c0fac35d5651c48f00b94294eb67c2e` |
| Universal（ad hoc Spike 签名） | `455,295,408` | `069e9a35cf97460bd5adbf7b8572a4e1d29918911814885a336b186674dccf59` |

剥离后的源码 Universal 宿主已再次通过 arm64 和 Rosetta x86_64 沙盒运行，
两次均为退出状态 0 且无孤儿进程。

当前不含 Runtime 的无签名 QuotaView Release App 约 26.3 MiB；使用官方
Release Runtime 的最小宿主约 436.9 MiB，未计算正式 App 资源和 App Store
处理前就扩大约 16.6 倍。上游 Runtime 直接依赖 V8 / code-mode，是主要体积
来源。该体积不会影响技术正确性，但会显著影响下载、更新、审核和用户预期，
必须作为进入 Phase 1 前的产品与架构决策。

## 8. Go / No-Go 条件

继续 Phase 1 前必须同时满足：

1. 安装有效的 Mac App Distribution 证书和 App Store provisioning
   profiles，用最小宿主生成真实 Archive，验证嵌套 Runtime 的签名、Sandbox
   Inherit、Network Client、Keychain 和双架构运行；
2. 向 OpenAI 确认生产 `clientInfo.name` 登记、实验性 App Server 的第三方
   分发许可、账号数据用途和 App Review 支持口径；
3. 产品所有者明确接受约 436.5 MiB 的 Universal Runtime，或确定受支持的
   减包方案；
4. 上述结果通过后，才可以开始 Phase 1 provider 注入和 Runtime supervisor，
   仍不得同步启动 Phase 2 登录 UI。

## 9. 官方参考

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex authentication and credential storage](https://learn.chatgpt.com/docs/auth)
- [OpenAI Codex open source repository](https://github.com/openai/codex)
- [Apple: Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
