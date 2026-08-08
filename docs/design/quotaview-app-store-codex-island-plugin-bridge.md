# QuotaView 1.0.0 App Store Codex 灵动岛插件桥接实施规格

> 文档编号：`QV-APPSTORE-CODEX-ISLAND-BRIDGE-001`
>
> 规格状态：`Accepted`
>
> 交付状态：`Implemented / Preview 7 Released`
>
> 用户确认日期：2026-08-06；付费下载全功能方案确认日期：2026-08-08
>
> 父级 Requirement：`AS-PRICING-001`、`AS-SANDBOX-001`
>
> 依赖基线：QuotaView `0.3.1 (Build 2)`
>
> 目标版本：QuotaView `1.0.0 (Build 4)` / 内部代号 `v1.0.0a`

## 1. 决策摘要

App Store 版本保留 Codex 灵动岛，但不再由 QuotaView 修改 Codex 配置、
安装 Helper、控制 Terminal 或监听全局 Socket。灵动岛事件改由一个独立的
`QuotaView for Codex` 配套插件产生，并使用 Codex 自己的插件安装、启用和
Hooks 信任流程。

插件采用双通道分发：

1. **Preview Channel**：先通过 QuotaView 自有的公开 Git Marketplace
   分发，不等待 Codex 公共插件目录审核；
2. **Directory Channel**：后续将同一插件包提交 Codex 公共目录；
3. 两个渠道必须使用相同的插件身份、桥接协议和事件合同，QuotaView 不得
   依赖插件的分发来源。

QuotaView 只通过用户明确选择的目录，以只读 security-scoped bookmark
读取插件写入 `PLUGIN_DATA` 的脱敏活动事件与用量快照。插件未安装、
未启用、未信任或不可用时，App 本身的菜单栏入口、设置与静态界面必须
继续正常工作，数据位使用稳定占位符而不伪造 0%。

QuotaView 在 Mac App Store 采用 `USD 4.99` 付费下载，Codex 实时灵动岛与
其他内置能力全部包含在 App 中。App 内不提供 IAP、订阅、许可证、试用门槛
或单独功能解锁。插件仓库保持公开；用户完成插件安装、Hooks 信任和目录配对
后，有效的新鲜事件即可驱动灵动岛，不需要额外购买资格。
用量快照则需要用户已在官方 Codex 登录。

本规格的主应用代码和桥接协议已经实施；此前 StoreKit 门禁已于 2026-08-08
删除。公开 `v1.0.0-preview.1` 仍是已验证的活动事件历史版本。
固定 `v1.0.0-preview.7` 在此基础上加入 `codex-usage-snapshot`、官方
`codex app-server` 两个只读调用、白名单 `usage.json`、泄漏负向测试和
面向 Codex Chat 的安装说明；该版本已作为公开 Pre-release 发布，并通过
mock、官方 app-server live 验证、匿名固定 tag clone、隔离安装/卸载/重装、
确定性资产、CI artifact 和公开资产回下载。当前受信任的本机安装实例持续
产生脱敏事件与用量快照，且安装源码与固定 tag 一致。App Review 的完整人工
复现与产品视觉矩阵仍待完成。更早的 Apple Distribution
`.pkg` 不对应当前源码；外部门禁关闭后必须重新生成最终提交包。

## 2. 目标与非目标

### 2.1 目标

- 在开启 App Sandbox 后保留现有 Codex 灵动岛拳头功能；
- 由 Codex 官方插件机制拥有插件安装、更新、启用和 Hook 信任；
- 让 QuotaView App 保持单一、自包含、可审计的 App Store 包；
- 保留现有事件语义、Reducer、Metal/SwiftUI 展示、完成后时序和视觉设计；
- 事件链路默认离线、本地、脱敏，不依赖远程 MCP 或 QuotaView 服务器；
- Preview 与未来公共目录版本共用一份插件源码和桥接协议；
- 付费下载 App 中直接包含灵动岛，不建立第二层购买或许可证门槛；
- 允许用户在设置中完成插件兼容性与连接检查；
- 为 App Review 提供无需内部账号即可复现的安装与测试流程。

### 2.2 非目标

- 本规格不接入任何额度重置能力；
- 不恢复已从 App Store `1.0.0` 删除的额度重置入口、设置或 Widget 字段；
- 不把插件宣传为“OpenAI 官方插件”；它是 QuotaView 官方配套插件，Codex
  公共目录只是未来的官方分发渠道；
- 不用插件绕过 Codex 的 Hook 信任、沙盒、权限或组织策略；
- 不在 QuotaView 内实现插件下载器、安装器或自更新器；
- 不使用 Accessibility、屏幕录制、OCR 或 UI 自动化推断 Codex 状态；
- 不在 App 内建立基础额度、Credits、菜单栏、Widget 或灵动岛的二次付费墙；
- 不在插件中保存购买收据、许可证或 QuotaView 账号；
- 用量快照的字段、时效、隐私和生产解码边界由
  [官方 Codex 用量快照桥规格](quotaview-app-store-codex-usage-snapshot-bridge.md)
  负责；本规格继续负责插件分发、目录配对和灵动岛事件。

## 3. 当前阻断链路与迁移边界

### 3.1 必须移除的旧安装与通信链路

当前稳定基线中与 App Store 沙盒冲突的灵动岛链路包括：

- `Configs/App.xcconfig` 中 `ENABLE_APP_SANDBOX = NO`；
- QuotaView 直接读取和修改 `~/.codex/hooks.json`；
- `CodexActivityHookInstaller` 把 App 内 Helper 复制到用户
  `Application Support`；
- 生成 `.command` 与 Expect 脚本并自动输入 `/hooks`；
- QuotaView 负责启动 Codex CLI、进入 Hooks 页面或引导信任；
- `CodexActivityUnixBridge` 使用 Unix Socket；
- `CodexActivityFileBridge` 与 Helper 使用全局 `/tmp` 队列作为回退；
- App 内包含并安装 `QuotaViewActivityHook` Helper；
- 设置页把“安装、重启、信任、连接”解释为 QuotaView 可以自动控制的
  状态。

完成迁移后，上述路径不得继续出现在 App Store 运行时、设置文案、测试或
构建产物中。历史直接分发版本的事实可以留在版本文档中，但不得迁回
App Store 分支。

### 3.2 必须保留的现有资产

以下能力属于已验证的产品实现，应尽量原样保留：

- `CodexActivityEvent` 的业务事件语义；
- `CodexActivityPrivacy` 的标识散列、工作区末级名称和工具分类规则；
- `CodexActivityReducer` 的事件到视觉状态映射；
- `CodexActivityStore` 的事件去重、完成后紧凑与隐藏时序；
- `CodexActivityIsland` 的 Metal/SwiftUI 渲染和既有视觉设计；
- `SessionStart`、`SessionEnd`、`UserPromptSubmit`、`PreToolUse`、
  `PermissionRequest`、`PostToolUse`、`PreCompact`、`PostCompact`、
  `SubagentStart`、`SubagentStop`、`Stop` 的语义覆盖；
- 完成后 `20` 秒紧凑、完成满 `120` 秒隐藏，新活动立即展开的正式时序。

迁移原则是替换“安装、授权与传输层”，不重新设计灵动岛的展示层。

## 4. 目标架构

```text
QuotaView App Store App（App Sandbox）
    │
    ├─ 打开稳定 HTTPS 设置入口
    │      ├─ 当前：Git Marketplace 安装指南
    │      └─ 未来：Codex 公共目录安装入口
    │
    ├─ 接收 quotaview://pair 配对提示
    ├─ 通过 NSOpenPanel 获得用户选择目录的只读访问权
    ├─ 保存 security-scoped bookmark 到自身容器
    └─ 读取并验证脱敏事件
                         ▲
                         │ 只读读取
QuotaView for Codex Plugin / PLUGIN_DATA
    ├─ Skill：安装说明、配对、连接诊断、隐私说明
    ├─ Hooks：生命周期事件
    ├─ Bridge Writer：脱敏、排序、原子写入、轮转
    └─ 不包含远程 MCP，不上传事件
                         ▲
                         │ 安装、启用、信任均在 Codex 中完成
                      Codex
```

### 4.1 责任边界

| 组件 | 负责 | 不负责 |
|---|---|---|
| QuotaView | 用户引导、目录授权、协议验证、事件消费、灵动岛展示 | 下载插件、修改 Codex、信任 Hooks、自有支付 |
| Codex | Marketplace 管理、插件安装/更新、Hooks 展示与信任 | QuotaView 的 App Sandbox 授权 |
| 配套插件 | 捕获并脱敏事件、写入 `PLUGIN_DATA`、连接诊断 | 绘制灵动岛、访问 QuotaView 容器、处理 App 发行资格 |
| 安装网站 | 展示当前受支持的安装渠道和隐私说明 | 向 QuotaView 下发或执行代码 |

## 5. 插件仓库与双通道分发

### 5.1 Preview Git Marketplace

预览插件使用独立仓库 `Duoasa/QuotaView-for-Codex`。本地 Git 仓库已经在
`/Users/sukduoasa/Documents/QuotaView-for-Codex` 创建并通过插件验证，本地
Marketplace 名为 `quotaview-preview`，插件安装名为
`quotaview@quotaview-preview`；本地提交与 annotated tag
`v1.0.0-preview.1` 均指向
`76262d40aded1e1c5f27168214762f41b382629f`。公开仓库
`https://github.com/Duoasa/QuotaView-for-Codex` 已创建，`main` 与该 tag 已
推送；branch/tag Actions 均成功，从匿名 HTTPS URL 按该 tag 克隆后，桥接
测试与官方插件校验再次通过。仓库同时包含 Marketplace 元数据和插件包：

```text
quotaview-codex-plugin/
├── .agents/plugins/marketplace.json
├── plugins/quotaview/
│   ├── .codex-plugin/plugin.json
│   ├── skills/
│   │   └── quotaview-setup/SKILL.md
│   ├── hooks.json
│   ├── scripts/
│   │   └── quotaview-bridge
│   └── assets/
├── README.md
├── PRIVACY.md
├── SECURITY.md
└── LICENSE
```

仓库要求：

- 公开可读，用户和 App Review 审核人员无需 GitHub 登录；
- 默认分支受保护，正式版本通过唯一 tag 发布；
- Marketplace 的生产入口固定到 tag 或 commit SHA，不跟随可变分支；
- 不包含用户数据、Token、Cookie、证书、API Key 或测试账号；
- README 明确这是 Preview 渠道、所需 Codex 版本、安装、卸载、数据范围和
  Hook 信任步骤；
- 插件包使用语义化版本，例如 `1.0.0-preview.1`；
- 每个发布 tag 记录插件包 SHA-256 和桥接协议版本。

### 5.2 稳定安装入口

QuotaView 设置页通过 Info.plist 可配置入口打开当前可审计的公开仓库：

```text
https://github.com/Duoasa/QuotaView-for-Codex
```

公开仓库创建前该链接不得被视为已上线。后续如果 `quotaview.app` 建立稳定
帮助页，只需替换 `QUOTAVIEW_CODEX_PLUGIN_GUIDE_URL`，不得通过应用更新之外
的远程配置下发可执行代码。

稳定页面：

- Preview 阶段展示添加 Git Marketplace、安装插件和信任 Hooks 的步骤；
- 公共目录发布后优先展示 Directory Channel；
- 保留 Preview 渠道的卸载、升级与迁移说明；
- 显示插件版本、协议版本、仓库、隐私政策、支持入口和已知兼容范围；
- 不让 QuotaView 下载或执行页面返回的任何代码。

### 5.3 未来公共目录切换

公共目录提交必须从已经验证的同一 Git tag 生成，不建立第二套插件实现。
以下身份从 Preview 开始冻结：

- 插件名称与 slug；
- 发布者名称；
- 插件内部标识；
- `bridgeProtocolVersion`；
- 事件 schema 与隐私字段；
- `quotaview://pair` 回调语义；
- Skill 的核心触发词与职责。

公共目录发布后：

- 新用户从稳定安装页面进入 Directory Channel；
- 已安装 Preview 的用户可以继续使用原渠道；
- App 同时接受 Preview 与 Directory 的兼容握手；
- 迁移用户最多执行“卸载预览版、安装正式版、重新信任 Hooks”；
- 如果 `PLUGIN_DATA` 位置变化，QuotaView 只要求重新授权一次目录；
- 不承诺绕过 Codex 的重新信任或 macOS 的重新授权。

### 5.4 付费 App 功能边界

- QuotaView 采用 `Paid Upfront`，App Store 基准价格为 `USD 4.99`；
- Codex 灵动岛的消费和展示代码随 App 一起提交审核并包含在下载中；
- App 内不提供 IAP、订阅、恢复购买按钮、许可证、试用门槛或单独功能解锁；
- App Store 负责首次购买、重新下载及适用的家庭共享资格，QuotaView 不自行
  维护购买 entitlement；
- 插件公开可安装，事件连接诊断和协议检查可在无用量快照时
  进行；获取用量必须在官方 Codex 登录；
- 只有插件协议、事件和只读目录授权满足要求时才消费事件；
- App 内、网站和插件不得引导用户使用外部支付解锁 QuotaView 功能；
- App Store Connect 完成 Paid Apps Agreement 与价格配置后，发行配置中的
  价格状态才能从 `pending` 改为 `configured`。

## 6. 插件功能与权限设计

### 6.1 插件类型

Preview 与公共目录候选包均采用 **Skill + Hooks**，默认不包含 MCP：

- Skill 提供真实的连接设置、状态诊断、隐私解释和故障排查价值；
- Hooks 只捕获灵动岛需要的生命周期事件；
- Bridge Writer 只向插件自己的 `PLUGIN_DATA` 写入；
- 不直接发起 HTTP；只为用量快照启动官方 `codex app-server`
  并调用两个只读 RPC；不读取 auth 文件、QuotaView 容器，不修改 `~/.codex`；
- 不改变、阻断、批准或重写 Codex 的正常工具调用。

### 6.2 Skill 工作流

插件至少提供以下明确工作流：

1. **连接 QuotaView 灵动岛**：创建握手文件并向 QuotaView 发起配对提示；
2. **检查 QuotaView 连接**：检查 `PLUGIN_DATA`、协议和最近写入，不扫描
   用户其他目录；
3. **解释 QuotaView 隐私范围**：列出会写入和明确不会写入的数据；
4. **排查无事件问题**：引导用户检查插件启用、Hooks 信任、Quotaview
   目录授权和版本兼容性；
5. **断开或卸载**：说明如何在 Codex 中禁用/卸载，并在 QuotaView 中撤销
   bookmark。

### 6.3 Hook 行为

Hook 只能观察事件并写入脱敏记录：

- 正常成功时不得向模型注入额外上下文；
- 不返回 allow、deny、ask、updatedInput 或 continuation 决策；
- 写入失败不得阻断 Codex 任务；
- 每次执行必须有严格超时和输出上限；
- 所有路径均相对插件根目录或 `PLUGIN_DATA` 解析；
- 不调用网络、Terminal UI、AppleScript、Accessibility 或 QuotaView 私有
  文件；
- 插件更新改变 Hook 内容后，接受 Codex 要求用户重新信任。
- `Stop` Hook 使用满足官方结束事件合同的 JSON 成功输出，并预留足够时间
  完成同进程的五分钟用量快照刷新；活动事件必须先于刷新写入。
- 如果 `PostToolUse`、`PostCompact` 或 `SubagentStop` 后连续 `120` 秒没有
  收到新事件或 `Stop`，QuotaView 直接隐藏陈旧过渡态，不伪造完成事件；
  真实 `Stop` 仍独占“完成 → 20 秒紧凑 → 完成满 120 秒隐藏”的正式时序。

## 7. 桥接协议 v1

### 7.1 目录结构

插件在 `PLUGIN_DATA` 中维护：

```text
PLUGIN_DATA/
├── bridge.json
├── status.json
└── events/
    ├── 000000000001.json
    ├── 000000000002.json
    └── ...
```

- `bridge.json`：插件身份、插件版本、协议版本、安装实例和能力声明；
- `status.json`：最近成功写入时间、最新序号和插件诊断状态；
- `events/`：按单调序号命名的不可变事件文件；
- 插件使用临时文件加原子 rename，QuotaView 不读取半写入文件；
- 插件负责事件轮转，QuotaView 不删除或修改插件文件；
- 默认建议最多保留最近 `512` 条或 `24` 小时，最终值在实现时通过压力测试
  固定，不能无限增长。

### 7.2 `bridge.json` 最小合同

```json
{
  "pluginId": "quotaview",
  "pluginVersion": "1.0.0-preview.1",
  "distributionChannel": "git-marketplace",
  "bridgeProtocolVersion": 1,
  "eventSchemaVersion": 1,
  "installationIdentifier": "random-per-installation-id",
  "createdAt": "2026-08-06T00:00:00Z",
  "capabilities": ["codex-activity-events"]
}
```

公共目录版本可以把 `distributionChannel` 改为 `openai-directory`，其余协议
身份保持兼容。QuotaView 不得仅因为渠道不同拒绝事件。

### 7.3 事件合同

事件文件延续当前 `CodexActivityEvent` 语义，并增加传输层序号：

```json
{
  "bridgeProtocolVersion": 1,
  "installationIdentifier": "random-per-installation-id",
  "sequence": 42,
  "activity": {
    "schemaVersion": 1,
    "event": "PreToolUse",
    "sessionHash": "sha256",
    "turnHash": "sha256-or-null",
    "workspaceName": "widget",
    "toolCategory": "fileEdit",
    "sessionStartSource": null,
    "occurredAt": "2026-08-06T00:00:00Z"
  }
}
```

必须保持：

- session、turn 等标识进入文件前完成单向散列；
- `workspaceName` 最多包含末级目录名并限制长度；
- 工具只保留 `shell`、`fileEdit`、`mcp`、`subagent`、`localTool`、
  `unknown` 粗分类；
- 不包含 prompt 正文、完整 cwd、文件路径、文件内容、命令、工具输入输出、
  模型回复、推理、账号标识或凭据；
- 时间戳必须使用 UTC ISO 8601；
- 未知 schema、超大文件、未来时间、过期事件和倒退序号必须安全忽略并记录
  有界诊断。

### 7.4 消费与重放规则

- QuotaView 把已消费的 `installationIdentifier + sequence` 游标保存在自身
  沙盒容器，不写回插件目录；
- App 启动时可以读取最新状态，但不得重播过期动画；
- 新安装实例从其第一条有效事件开始建立独立游标；
- 检测到安装实例改变时，App 必须清除旧实例游标、最近事件时间和旧展示
  状态；新实例尚无事件时不得沿用旧实例的连接状态；
- 重复事件不得重复驱动灵动岛；
- `SessionEnd` 后更早的事件不得重新展开灵动岛；
- 断线恢复只恢复当前仍具时效性的活动，历史完成事件只更新诊断状态；
- 每次目录授权、断开和运行停止都推进本地读取修订号；在途异步读取只有在
  修订号仍匹配时才能提交状态或事件，避免用户已经断开后被旧结果重新连接
  或覆盖错误状态；同一修订内合并重复轮询，但新修订读取不等待旧修订结束；
- 协议不兼容时停止消费并显示升级提示，不崩溃、不降级解析未知字段。

## 8. 配对与 App Sandbox 授权

### 8.1 配对入口

插件的“连接 QuotaView 灵动岛”Skill 可以调用系统 `open` 打开：

```text
quotaview://pair?protocol=1&plugin=quotaview&pathHint=<percent-encoded-path>
```

`pathHint` 只帮助 `NSOpenPanel` 定位到插件数据目录，不能直接授予访问权。
自定义 URL 只用于唤起和提供非敏感提示，不携带密钥，也不能被当作插件
真实性证明。QuotaView 必须校验 scheme、host、参数白名单、百分号编码和
长度，禁止把参数写入日志，并忽略未知参数。

### 8.2 用户授权

收到配对提示后：

1. QuotaView 使用经过基本校验的 `pathHint` 作为初始位置打开
   `NSOpenPanel`，但不在面板确认前读取该目录；
2. 用户明确选择插件数据目录；
3. App 获得只读 security-scoped URL；
4. App 校验 `bridge.json` 和目录安全属性；
5. App 保存 security-scoped bookmark 到自身容器；
6. App 立即释放临时访问，后续读取时按需
   `startAccessingSecurityScopedResource()` / `stopAccessing...()`；
7. 用户取消时不保存任何路径，设置状态保持“未连接”。

App entitlement 目标至少包括：

- `com.apple.security.app-sandbox = true`；
- `com.apple.security.files.user-selected.read-only = true`；
- 当前经过 provisioning 验证的 App Group。

实施时必须以 App Store provisioning profile 的实际 entitlement 为准，
不能只修改 `.entitlements` 文件后宣称完成。

### 8.3 目录安全校验

QuotaView 至少检查：

- 所选对象是目录，`bridge.json` 和事件是普通文件；
- 拒绝目录外路径、`..`、符号链接逃逸和设备文件；
- 文件所有者与当前用户一致，目录不可被其他用户任意写入；
- 单文件大小、事件总数、JSON 深度和字符串长度有上限；
- `pluginId`、协议版本、安装实例和能力声明有效；
- 日志不记录 security-scoped bookmark、完整路径或用户标识。

## 9. 用户流程与设置状态

### 9.1 首次安装

1. 用户从 Mac App Store 安装并启动 QuotaView；
2. 额度、菜单栏和 Widget 在未安装插件时正常可用；
3. 用户打开“设置 → 连接与灵动岛”，看到已包含功能和外部依赖说明；
4. 用户可以先点击“检查兼容性”，App 打开稳定 HTTPS 安装页面；
5. 用户在 Codex 中添加 QuotaView Git Marketplace；
6. 用户安装并启用 `QuotaView for Codex`；
7. 用户检查并信任插件 Hooks；
8. 用户运行“连接 QuotaView 灵动岛”Starter Prompt；
9. QuotaView 被唤起并显示系统目录选择面板；
10. 用户授权目录后，App 校验握手并显示“已配对”；
11. 用户开始一个新的 Codex 任务；
12. 第一个有效 `UserPromptSubmit` 或其他生产事件到达后，状态变为“已连接”
    并按真实事件展示灵动岛。

配对成功可以显示一次简短的“Codex 已连接”反馈，但不得把模拟业务事件
伪装成真实 Codex 活动。

### 9.2 日常启动

1. QuotaView 加载 bookmark；
2. 校验桥接协议和安装实例；
3. 从本地游标继续读取；
4. 忽略过期和已消费事件；
5. 监听新事件并交给现有 Reducer；
6. bookmark 失效时停止读取并提示“重新授权”，其他功能不受影响。

### 9.3 设置状态模型

App 只能根据已授权目录和已收到事件作出结论，不能越过沙盒读取 Codex 来
猜测安装状态。App 不维护第二套购买状态；设置页表达插件连接状态，并提供
独立的灵动岛显示偏好：

| 状态 | 含义 | 主操作 |
|---|---|---|
| `notConfigured` | 尚未配对 | 设置 Codex 灵动岛 |
| `awaitingAuthorization` | 已收到配对提示，等待用户选择目录 | 选择目录 |
| `pairedWaitingForEvent` | 握手有效，尚无真实 Hook 事件 | 打开排查指南 |
| `connected` | 最近收到有效事件 | 打开插件设置 |
| `stale` | 曾连接但长期没有新状态 | 检查 Codex 插件 |
| `reauthorizationRequired` | bookmark 无法恢复 | 重新授权 |
| `incompatible` | 协议或 schema 不兼容 | 更新 App 或插件 |
| `malformedData` | 目录或事件校验失败 | 重新配对 / 查看诊断 |

不得在没有可靠证据时显示“插件未安装”“Hooks 未信任”或“Codex 未启动”。
`pairedWaitingForEvent` 的排查说明应并列提示用户检查安装、启用、Hooks 信任
和是否已开始新任务。

### 9.4 设置操作

允许的操作：

- 查看已包含功能和插件依赖说明；
- 执行兼容性与连接检查；
- 打开稳定安装/帮助页面；
- 发起或重新发起系统目录授权；
- 删除 QuotaView 自身保存的 bookmark 和游标；
- 打开 Codex 插件管理页面或受支持的 deep link；
- 展示隐私字段、插件版本、协议版本和最近有效事件时间。
- 开启或关闭灵动岛展示；该偏好默认开启并跨启动持久化。

关闭灵动岛时，App 必须立即隐藏现有灵动岛，但继续轮询已授权目录、推进
活动游标并更新用量、连接状态和最近事件。重新开启后，只有当前 Reducer
仍处于可见展示阶段时才恢复展示；不得伪造事件、重置连接或改写插件数据。

禁止的操作：

- 自动添加 Marketplace；
- 自动安装、更新或卸载插件；
- 自动输入 `/hooks`、按键或点击信任；
- 直接编辑 Codex 配置；
- 删除插件目录或 `PLUGIN_DATA`；
- 通过 QuotaView 启动安装 Helper、Expect 或 Terminal 脚本。

## 10. 隐私、安全与审核说明

### 10.1 数据最小化

插件与 App 默认完全本地工作。隐私政策必须分别说明：

- 插件写入哪些字段；
- QuotaView 读取哪些字段；
- 数据保存位置和默认轮转期限；
- 不上传事件，也不用于分析或广告；
- 用户如何撤销授权、禁用插件和删除本地数据；
- 如果未来引入遥测，必须另行取得用户授权并更新本规格。

### 10.2 App Store 审核口径

App Review Notes 必须说明：

- QuotaView 是 `USD 4.99` 付费下载 App，Codex 灵动岛属于已包含功能；
- App 内没有 IAP、订阅、许可证、试用门槛或单独功能解锁；
- QuotaView 未安装插件时仍有完整的额度查看与 Widget 功能；
- 插件公开可安装，配对并收到有效事件后 App 展示灵动岛；
- 插件由用户在 Codex 的插件系统中安装、启用和信任；
- QuotaView 不下载或安装外部代码；
- App 只在用户选择目录后获得只读权限；
- 公开 Git 仓库、固定 tag、安装指南和审核步骤；
- 触发 `UserPromptSubmit`、工具执行、权限请求和完成状态的测试方法；
- 所有事件均为脱敏本地数据；
- 付费下载模式与无 App 内购买的审核说明。

提交 App Review 前，Preview 仓库、固定 tag、安装页面和测试说明必须全部
公开可访问。若审核人员无法复现，不得提交候选包。

### 10.3 不保证事项

Git Marketplace 是 Codex 支持的插件分发机制，但它不等同于已经通过
OpenAI 公共目录审核。采用本方案可以消除 QuotaView 自行安装 Hook/Helper
的主要沙盒冲突，不能单独保证 Apple 批准；App Sandbox、签名、provisioning、
隐私清单与外部进程清理已完成源码和无签名产物验证；最终签名 Archive 仍需
独立通过审核门禁。

审核实现必须同时满足 Apple 对 Mac 插件的容纳规则和 2.5.2 自包含规则：
QuotaView 只展示安装说明并读取用户授权的数据目录，不得自己下载、安装或
执行会改变 App 功能的插件代码。事件消费与浮窗展示代码已经随付费 App
Bundle 提交审核；插件只提供用户主动启用的本地事件输入。

## 11. 实施阶段

### Phase 0：冻结合同与拆分边界（已完成）

- 将本规格中的协议 v1 转为可测试的 Swift 数据合同；
- 固定 Preview 插件 slug、发布者、仓库和稳定安装域名；
- 固定付费下载、全功能包含和无 App 内购买的发行边界；
- 列出旧安装、通信和设置代码的删除清单；
- 确认其他 `Process` 链路不被误判为本阶段已解决；
- 在任何删除前为现有 Reducer、时序和事件映射补足回归测试。

交付门禁：协议、事件、状态、隐私字段和仓库身份全部确定。

### Phase 1：建立 Preview 插件仓库（仓库与固定 tag 已公开）

- 创建 Marketplace 和插件清单；
- 实现设置/诊断 Skill；
- 实现只写 `PLUGIN_DATA` 的 Hook Bridge Writer；
- 接入当前 Codex 插件系统稳定提供的 6 类事件：`SessionStart`、
  `SessionEnd`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`Stop`；
  其余协议状态保留，只有 Codex 提供稳定 Hook 后才增加；
- 加入原子写入、轮转、超时、大小限制和错误降级；
- 完成 README、隐私、安全、卸载和故障排查文档；
- 使用本地 Marketplace 完成安装、启用、信任和事件测试；
- 创建并推送固定 Preview annotated tag；不移动已发布 tag，也不立即改变
  QuotaView 的桥接协议。

交付门禁：公开仓库、固定 tag、branch/tag CI 和匿名 tag 克隆验证已完成；
支持的全新 Codex 环境安装、信任与真实事件验证并入 Phase 6。

### Phase 2：切换为付费 App 全功能模式（已完成）

- 删除 StoreKit 商品、交易状态、购买恢复、购买界面和消费门禁；
- 新鲜插件事件在协议与目录授权通过后直接驱动灵动岛；
- 在设置、审核说明和元数据中说明 `USD 4.99` 付费下载包含全部功能；
- 用发行脚本检查 `paid-upfront`、`4.99` 和 App Store Connect 价格状态。

交付门禁：源码、测试、配置和 Bundle 不含旧 IAP 门槛；基础额度与插件继续
相互独立。

### Phase 3：实现 App 沙盒读取与配对（代码完成，端到端待验证）

- 增加 `quotaview://pair` URL scheme 与严格参数校验；
- 使用 `NSOpenPanel` 获取目录授权；
- 保存、恢复和撤销只读 security-scoped bookmark；
- 实现 `bridge.json`、`status.json` 与事件目录验证；
- 实现游标、去重、过期过滤和目录监听；
- 用单调读取修订号使断开与停止失效全部在途目录读取，并允许新修订立即
  轮询；
- 将有效事件接入现有 `CodexActivityStore`；
- 所有异常均降级为设置状态，不影响 App 其他功能。

交付门禁：开启 App Sandbox 后，真实插件事件可以驱动现有灵动岛。

### Phase 4：替换设置与删除旧链路（已完成，等待视觉验收）

- 设置页改为“安装指南 → Codex 内安装/信任 → 配对授权”；
- 删除自动安装、重启 Codex、打开安全审查和 Expect 文案；
- 删除 `CodexActivityHookInstaller`；
- 删除旧 Unix Socket 与全局 `/tmp` File Bridge；
- 删除 App 包中的 `QuotaViewActivityHook` Helper target 和资源引用；
- 删除 Helper 安装、迁移和卸载代码；
- 删除只服务于旧链路的测试，补充新插件桥接测试；
- 搜索确保源码、测试、构建设置和产物无旧入口残留。

交付门禁：App 不再写 `~/.codex`、不安装 Helper、不控制 Terminal。

### Phase 5：App Sandbox 与签名闭环（Distribution 候选导出已完成）

- 将主 App `ENABLE_APP_SANDBOX` 改为 `YES`；
- 增加并验证 user-selected read-only entitlement；
- 保持 App/Widget App Group 与 App Store profile 一致；
- 使用 Distribution provisioning profile 导出 Apple Distribution `.pkg`；
- 检查 App、Widget、Framework entitlement、签名和嵌入 profile；
- 验证菜单栏、设置、Widget、登录启动和插件目录授权；
- 继续审计不属于灵动岛的外部 `Process` 阻断项。

交付门禁：不能只凭无签名 Release 构建通过，必须完成 App Store Archive
级别验证。当前主 App Mac Team Store profile、Apple Distribution 重签名与
`.pkg` 审计已通过；审计包含对实际 component Payload 中 App、Widget、
Framework 的深度验签、沙盒 entitlement 与嵌入 profile 核对。因 OAuth、
付费 App 价格和插件端到端验证仍未完成，最终提交包必须在全部门禁关闭后
重新生成。此前生成的包早于价格模型变更，不得作为当前提交候选。

### Phase 6：Preview 渠道与 App Review 准备（Release 已发布，端到端待完成）

- 核验公开 Marketplace 仓库、固定 tag 和 Release 资产，从全新环境执行固定
  tag 安装；
- 上线稳定安装页面；
- 从全新用户环境执行安装、信任、配对、触发、卸载和重装；
- 生成审核说明、隐私数据表和复现步骤；
- 完成 Paid Apps Agreement 和 `USD 4.99` 价格配置；
- 在审核期间保持仓库 tag 和页面步骤稳定；
- 产品所有者完成深浅色、中英文、Reduce Motion、VoiceOver 和真实 Codex
  事件的视觉/交互验收。

当前已建立
[App Review Notes](../release/APP_STORE_REVIEW_NOTES_DRAFT.md)、
[App Privacy](../release/APP_STORE_PRIVACY_ANSWERS_DRAFT.md)、
[Preview 7 插件 Release 记录与验收单](../release/PLUGIN_RELEASE_V1.0.0_PREVIEW.7.md)。其中仍有
账号、正式授权、最终价格、公开隐私政策和审核联系人占位项，不得直接提交。

### Phase 7：公共目录迁移（后续版本）

- 从已验证的同一插件 tag 准备公共目录材料；
- 提交真实 Skill + Hooks，不提交纯导流安装器；
- 完成身份、网站、支持、隐私、条款、Starter Prompts、5 个正向测试和
  3 个负向测试；
- 审核通过后发布 Directory Channel；
- 更新稳定安装页面，默认引导新用户到公共目录；
- 保持 Preview 渠道兼容窗口并发布迁移说明；
- 不要求 QuotaView 为切换分发渠道重写灵动岛。

## 12. Requirement 与验收标准

### CI-DIST-001：双通道分发

- Preview 使用公开 Git Marketplace 和固定 tag/SHA；
- Directory 使用同一源码 tag；
- App 只依赖稳定安装页面与协议，不依赖 Marketplace 名称。

### CI-PLUGIN-001：插件职责

- 插件包含真实 Skill 与 Hooks；
- 不包含不必要的 MCP 或远程服务；
- Hook 失败不阻断 Codex；
- 用户必须在 Codex 中完成信任。

### CI-PRICING-001：付费下载全功能

- Mac App Store 基准价格为 `USD 4.99`；
- 灵动岛与其他内置功能随 App 下载提供，不存在 App 内购买资格；
- 插件、网站和 App 不使用外部支付或许可证；
- 设置与审核材料完整披露插件和 Codex 依赖；
- 提交模式在 App Store Connect 价格未配置时失败关闭。

### CI-PAIR-001：显式授权

- URL scheme 不直接授予权限；
- 必须经 `NSOpenPanel` 用户选择；
- App 使用只读 security-scoped bookmark；
- 取消、撤销、失效和重新授权路径完整。

### CI-EVENT-001：事件兼容

- 11 类事件和现有 Reducer 映射保持；
- 序号、去重、时效、SessionEnd 和未知 schema 处理通过测试；
- 完成后 `20/120` 秒时序不回归。

### CI-PRIVACY-001：数据最小化

- 生产事件中无 prompt、完整路径、命令、文件内容、工具输入输出或凭据；
- 标识已散列，工作区只保留受限末级名称；
- 插件数据有明确轮转上限；
- App 与插件均不上传事件。

### CI-SANDBOX-001：沙盒边界

- 主 App 开启 App Sandbox；
- App 不修改 `~/.codex`；
- App 不复制、安装或执行外部 Helper；
- App 不使用全局 `/tmp` 或任意 Unix Socket 接收插件事件；
- App Store Archive entitlement 与 profile 验证通过。

### CI-UX-001：用户流程

- 未安装插件时核心功能正常；
- 安装、信任、配对、连接、断开、重新授权和不兼容状态可理解；
- App 不伪造无法可靠检测的“未安装”或“未信任”状态；
- 中英文、键盘和辅助功能文案完整。

### CI-MIGRATION-001：未来切换

- Preview 与 Directory 共享插件身份和协议；
- 现有 Preview 用户可以继续工作；
- 迁移最多需要重新安装、重新信任和必要时一次目录授权；
- 渠道变化不要求重写灵动岛展示层。

### CI-REVIEW-001：审核可复现

- 安装仓库、tag、网站和隐私页面公开；
- 全新审核账号能够按文档安装并触发真实事件；
- App Review Notes 明确可选依赖、数据范围和测试步骤；
- 其他 App Store 阻断项完成前不得声称可提交。

## 13. 验证矩阵

### 13.1 自动化测试

- 插件清单和 Marketplace schema 校验；
- Hook 输入缺失、未知事件、超大输入和写入失败；
- 脱敏字段白名单与敏感字段拒绝测试；
- 原子写入、序号、轮转和并发事件；
- bookmark 创建、恢复、失效和撤销；
- 付费下载配置、价格状态和旧 IAP 残留检查；
- 文件类型、symlink、越界路径、大小和 JSON 深度限制；
- Preview/Directory 握手兼容；
- 事件去重、过期过滤、SessionEnd 和重新安装实例；
- 断开目录或停止运行后，在途读取的成功/失败结果均不得回写；
- 旧修订仍在读取时，新授权目录可以立即轮询，不被旧任务占用锁；
- 插件重装后旧实例游标、最近事件与展示状态不会串入新实例；
- 现有 Reducer、视觉状态与 `20/120` 秒时序回归；
- `Stop` 缺失时过渡态不会永久停留，且后续真实活动会取消兜底隐藏；
- 未配对、插件无事件和协议不兼容时 App 核心功能不受影响。

### 13.2 构建与静态检查

至少执行：

```bash
swift test

rg -n \
  'hooks\.json|/hooks|/usr/bin/expect|Open Codex Security Review\.command|com\.quotaview\.codex-activity|CodexActivityHookInstaller|CodexActivityUnixBridge' \
  Sources Tests Configs Support QuotaView.xcodeproj

rg -n \
  'DEBUG-ONLY-MOCK|DEBUG MOCK|仅用于调试|account/rateLimitResetCredit/consume' \
  Sources Tests

git diff --check
```

旧术语搜索是否允许命中历史迁移测试或文档，必须逐项解释；生产源码、构建
产物和 App Store 运行时不得包含旧安装链路。

### 13.3 集成测试

- 全新 macOS 用户环境安装 QuotaView；
- 未安装插件启动与核心功能；
- 已包含灵动岛、无购买界面和插件兼容检查；
- 添加 Git Marketplace、安装、启用和信任；
- 配对取消、成功、撤销和重新授权；
- 11 类真实 Codex 事件；
- Codex 未运行、插件禁用、Hooks 未信任、插件升级和数据目录变化；
- App 重启、Codex 重启、系统重启和登录启动；
- Preview 到 Directory 候选包迁移；
- 离线环境和 GitHub 暂时不可用时已安装插件继续工作。

### 13.4 App Store 验证

- App Store Distribution Archive 成功；
- App 与 Widget provisioning profile、entitlement 和 App Group 一致；
- 主 App 确认 `com.apple.security.app-sandbox = true`；
- user-selected read-only entitlement 生效；
- App、Widget 和 Framework 架构、签名与资源完整；
- Privacy Manifest 与 App Store Connect 隐私答案一致；
- Paid Apps Agreement 与 `USD 4.99` 价格已配置，Review Notes 说明全部外部依赖；
- 审核指南中的仓库、tag、网页和测试步骤可从干净环境访问；
- 产品所有者完成视觉与交互验收，Codex 不代替该验收。

## 14. 回滚与故障策略

- Preview 仓库不可用时，已经安装的插件继续使用本地副本；新用户设置页
  显示服务暂不可用，QuotaView 核心功能继续工作；
- 插件版本有问题时发布更高版本和新 tag，不移动已经公开的 tag；
- 协议不兼容时 App 停止消费并提示升级，不尝试猜测解析；
- 插件写入失败只记录插件本地有界诊断，不阻断 Codex；
- bookmark 失效时只关闭灵动岛事件输入，不删除用户文件；
- App Store 购买或重新下载问题由系统处理；App 内不增加本地购买布尔值或
  许可证回退；
- 不得以回滚为由恢复修改 `hooks.json`、安装 Helper、Expect、全局 `/tmp`
  或 Unix Socket 的旧路径；
- 公共目录审核延迟或失败时继续维护 Preview Channel，不改变 App 协议。

## 15. 对外发布前待确认项

当前已经冻结：GitHub 账号 `Duoasa`、仓库名 `QuotaView-for-Codex`、插件名
`QuotaView for Codex`、slug `quotaview`、发布者 `Duoasa`、MIT 许可证、协议
v1、`512` 条本地轮转，以及 `Paid Upfront / USD 4.99 / all features included`
发行边界。

对外发布和 App Review 前仍需确认：

1. 是否继续以 GitHub 仓库作为稳定安装入口，或上线自有永久帮助页；
2. Preview 发布地区与支持邮箱；
3. 公共目录提交采用个人还是企业身份；
4. App Store Connect 的 `USD 4.99` 地区价格映射与 Family Sharing 选择。

这些事项不影响本地实现状态，但会阻塞 Preview 对外发布或 App Review。

## 16. 官方参考

- [Codex Plugins overview](https://learn.chatgpt.com/docs/plugins)
- [Package your plugin / Marketplace metadata](https://developers.openai.com/plugins/build/plugins#marketplace-metadata)
- [Plugin install deep link](https://learn.chatgpt.com/docs/reference/commands#plugin-install)
- [Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [Submit plugins](https://developers.openai.com/plugins/deploy/submission)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
