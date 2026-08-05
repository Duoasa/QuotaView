# QuotaView 1.0.0 App Store Codex 灵动岛插件桥接实施规格

> 文档编号：`QV-APPSTORE-CODEX-ISLAND-BRIDGE-001`
>
> 规格状态：`Accepted`
>
> 交付状态：`Planned`
>
> 用户确认日期：2026-08-06
>
> 父级 Requirement：`AS-SANDBOX-001`
>
> 依赖基线：QuotaView `0.3.1 (Build 2)`
>
> 目标版本：QuotaView `1.0.0 (Build 1)` / 内部代号 `v1.0.0a`

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
读取插件写入 `PLUGIN_DATA` 的脱敏事件。插件未安装、未启用、未信任或
不可用时，额度查看、菜单栏、设置与 Widget 必须继续正常工作。

本规格已经固化产品与架构方向，但尚未授权开始源码改造。实施时仍应按
下方阶段逐项完成、验证和记录。

## 2. 目标与非目标

### 2.1 目标

- 在开启 App Sandbox 后保留现有 Codex 灵动岛拳头功能；
- 由 Codex 官方插件机制拥有插件安装、更新、启用和 Hook 信任；
- 让 QuotaView App 保持单一、自包含、可审计的 App Store 包；
- 保留现有事件语义、Reducer、Metal/SwiftUI 展示、完成后时序和视觉设计；
- 事件链路默认离线、本地、脱敏，不依赖远程 MCP 或 QuotaView 服务器；
- Preview 与未来公共目录版本共用一份插件源码和桥接协议；
- 为 App Review 提供无需内部账号即可复现的安装与测试流程。

### 2.2 非目标

- 本规格不接入任何额度重置能力；
- 不恢复已从 App Store `1.0.0` 删除的额度重置入口、设置或 Widget 字段；
- 不把插件宣传为“OpenAI 官方插件”；它是 QuotaView 官方配套插件，Codex
  公共目录只是未来的官方分发渠道；
- 不用插件绕过 Codex 的 Hook 信任、沙盒、权限或组织策略；
- 不在 QuotaView 内实现插件下载器、安装器或自更新器；
- 不使用 Accessibility、屏幕录制、OCR 或 UI 自动化推断 Codex 状态；
- 不在本规格中解决额度数据获取和线程标题所依赖的其他
  `CodexAppServerClient` / `Process` 链路；该链路仍是独立的 App Store
  阻断项，必须另行整改。

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
| QuotaView | 用户引导、目录授权、协议验证、事件消费、灵动岛展示 | 下载插件、修改 Codex、信任 Hooks |
| Codex | Marketplace 管理、插件安装/更新、Hooks 展示与信任 | QuotaView 的 App Sandbox 授权 |
| 配套插件 | 捕获并脱敏事件、写入 `PLUGIN_DATA`、连接诊断 | 绘制灵动岛、访问 QuotaView 容器 |
| 安装网站 | 展示当前受支持的安装渠道和隐私说明 | 向 QuotaView 下发或执行代码 |

## 5. 插件仓库与双通道分发

### 5.1 Preview Git Marketplace

预览插件应托管在 QuotaView 所有的公开 GitHub 仓库。建议单仓库同时包含
Marketplace 元数据和插件包：

```text
quotaview-codex-plugin/
├── .agents/plugins/marketplace.json
├── plugins/quotaview/
│   ├── .codex-plugin/plugin.json
│   ├── skills/
│   │   └── quotaview-setup/SKILL.md
│   ├── hooks/
│   │   └── hooks.json
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

QuotaView 设置页不直接硬编码 GitHub 仓库或公共目录地址，而只打开一个
稳定 HTTPS 页面。目标地址暂定：

```text
https://quotaview.app/codex-plugin
```

该域名和路径必须在实施前确认所有权并真实上线。如果最终使用其他域名，
只替换为用户确认的永久 HTTPS 地址，不得使用短链或不可审计重定向服务。

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

## 6. 插件功能与权限设计

### 6.1 插件类型

Preview 与公共目录候选包均采用 **Skill + Hooks**，默认不包含 MCP：

- Skill 提供真实的连接设置、状态诊断、隐私解释和故障排查价值；
- Hooks 只捕获灵动岛需要的生命周期事件；
- Bridge Writer 只向插件自己的 `PLUGIN_DATA` 写入；
- 不访问网络，不读取 QuotaView 容器，不修改 `~/.codex`；
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
- 重复事件不得重复驱动灵动岛；
- `SessionEnd` 后更早的事件不得重新展开灵动岛；
- 断线恢复只恢复当前仍具时效性的活动，历史完成事件只更新诊断状态；
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
3. 用户打开“设置 → Codex 灵动岛”；
4. 点击“设置 Codex 灵动岛”，App 打开稳定 HTTPS 安装页面；
5. 用户在 Codex 中添加 QuotaView Git Marketplace；
6. 用户安装并启用 `QuotaView for Codex`；
7. 用户检查并信任插件 Hooks；
8. 用户运行“连接 QuotaView 灵动岛”Starter Prompt；
9. QuotaView 被唤起并显示系统目录选择面板；
10. 用户授权目录后，App 校验握手并显示“等待第一个 Codex 事件”；
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
猜测安装状态。建议状态：

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

- 打开稳定安装/帮助页面；
- 发起或重新发起系统目录授权；
- 删除 QuotaView 自身保存的 bookmark 和游标；
- 打开 Codex 插件管理页面或受支持的 deep link；
- 展示隐私字段、插件版本、协议版本和最近有效事件时间。

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

- Codex 灵动岛是可选的本地 Codex 集成；
- QuotaView 未安装插件时仍有完整的额度查看与 Widget 功能；
- 插件由用户在 Codex 的插件系统中安装、启用和信任；
- QuotaView 不下载或安装外部代码；
- App 只在用户选择目录后获得只读权限；
- 公开 Git 仓库、固定 tag、安装指南和审核步骤；
- 触发 `UserPromptSubmit`、工具执行、权限请求和完成状态的测试方法；
- 所有事件均为脱敏本地数据。

提交 App Review 前，Preview 仓库、固定 tag、安装页面和测试说明必须全部
公开可访问。若审核人员无法复现，不得提交候选包。

### 10.3 不保证事项

Git Marketplace 是 Codex 支持的插件分发机制，但它不等同于已经通过
OpenAI 公共目录审核。采用本方案可以消除 QuotaView 自行安装 Hook/Helper
的主要沙盒冲突，不能单独保证 Apple 批准；App Sandbox、签名、provisioning、
隐私清单、其他外部进程和最终 Archive 仍需独立通过审核门禁。

## 11. 实施阶段

### Phase 0：冻结合同与拆分边界

- 将本规格中的协议 v1 转为可测试的 Swift 数据合同；
- 固定 Preview 插件 slug、发布者、仓库和稳定安装域名；
- 列出旧安装、通信和设置代码的删除清单；
- 确认其他 `Process` 链路不被误判为本阶段已解决；
- 在任何删除前为现有 Reducer、时序和事件映射补足回归测试。

交付门禁：协议、事件、状态、隐私字段和仓库身份全部确定。

### Phase 1：建立 Preview 插件仓库

- 创建 Marketplace 和插件清单；
- 实现设置/诊断 Skill；
- 实现只写 `PLUGIN_DATA` 的 Hook Bridge Writer；
- 加入 11 类现有生命周期事件；
- 加入原子写入、轮转、超时、大小限制和错误降级；
- 完成 README、隐私、安全、卸载和故障排查文档；
- 使用本地 Marketplace 完成安装、启用、信任和事件测试；
- 发布固定 Preview tag，不立即改 QuotaView 生产设置入口。

交付门禁：插件在支持的 Codex 版本中独立通过完整测试。

### Phase 2：实现 App 沙盒读取与配对

- 增加 `quotaview://pair` URL scheme 与严格参数校验；
- 使用 `NSOpenPanel` 获取目录授权；
- 保存、恢复和撤销只读 security-scoped bookmark；
- 实现 `bridge.json`、`status.json` 与事件目录验证；
- 实现游标、去重、过期过滤和目录监听；
- 将有效事件接入现有 `CodexActivityStore`；
- 所有异常均降级为设置状态，不影响 App 其他功能。

交付门禁：开启 App Sandbox 后，真实插件事件可以驱动现有灵动岛。

### Phase 3：替换设置与删除旧链路

- 设置页改为“安装指南 → Codex 内安装/信任 → 配对授权”；
- 删除自动安装、重启 Codex、打开安全审查和 Expect 文案；
- 删除 `CodexActivityHookInstaller`；
- 删除旧 Unix Socket 与全局 `/tmp` File Bridge；
- 删除 App 包中的 `QuotaViewActivityHook` Helper target 和资源引用；
- 删除 Helper 安装、迁移和卸载代码；
- 删除只服务于旧链路的测试，补充新插件桥接测试；
- 搜索确保源码、测试、构建设置和产物无旧入口残留。

交付门禁：App 不再写 `~/.codex`、不安装 Helper、不控制 Terminal。

### Phase 4：App Sandbox 与签名闭环

- 将主 App `ENABLE_APP_SANDBOX` 改为 `YES`；
- 增加并验证 user-selected read-only entitlement；
- 保持 App/Widget App Group 与 App Store profile 一致；
- 使用 Distribution provisioning profile 生成 Archive；
- 检查 App、Widget、Framework entitlement 和嵌入 profile；
- 验证菜单栏、设置、Widget、登录启动和插件目录授权；
- 继续审计不属于灵动岛的外部 `Process` 阻断项。

交付门禁：不能只凭无签名 Release 构建通过，必须完成 App Store Archive
级别验证。

### Phase 5：Preview 渠道与 App Review 准备

- 发布公开 Marketplace 仓库和固定 tag；
- 上线稳定安装页面；
- 从全新用户环境执行安装、信任、配对、触发、卸载和重装；
- 生成审核说明、隐私数据表和复现步骤；
- 在审核期间保持仓库 tag 和页面步骤稳定；
- 产品所有者完成深浅色、中英文、Reduce Motion、VoiceOver 和真实 Codex
  事件的视觉/交互验收。

### Phase 6：公共目录迁移

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
- 文件类型、symlink、越界路径、大小和 JSON 深度限制；
- Preview/Directory 握手兼容；
- 事件去重、过期过滤、SessionEnd 和重新安装实例；
- 现有 Reducer、视觉状态与 `20/120` 秒时序回归；
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
- 审核指南中的仓库、tag、网页和测试步骤可从干净环境访问；
- 产品所有者完成视觉与交互验收，Codex 不代替该验收。

## 14. 回滚与故障策略

- Preview 仓库不可用时，已经安装的插件继续使用本地副本；新用户设置页
  显示服务暂不可用，QuotaView 核心功能继续工作；
- 插件版本有问题时发布更高版本和新 tag，不移动已经公开的 tag；
- 协议不兼容时 App 停止消费并提示升级，不尝试猜测解析；
- 插件写入失败只记录插件本地有界诊断，不阻断 Codex；
- bookmark 失效时只关闭灵动岛事件输入，不删除用户文件；
- 不得以回滚为由恢复修改 `hooks.json`、安装 Helper、Expect、全局 `/tmp`
  或 Unix Socket 的旧路径；
- 公共目录审核延迟或失败时继续维护 Preview Channel，不改变 App 协议。

## 15. 实施前待确认项

进入 Phase 1 前，产品所有者需要确认：

1. GitHub 仓库所属账号/组织及最终仓库 URL；
2. 插件正式名称、slug 和发布者显示名称；
3. 稳定安装页面的最终域名及所有权；
4. 插件许可证；
5. Preview 发布地区与支持邮箱；
6. 是否按建议采用 `512` 条或 `24` 小时的本地事件轮转上限；
7. 公共目录提交采用个人还是企业身份。

这些事项不影响本规格的架构接受状态，但会阻塞 Preview 对外发布。

## 16. 官方参考

- [Codex Plugins overview](https://learn.chatgpt.com/docs/plugins)
- [Package your plugin / Marketplace metadata](https://developers.openai.com/plugins/build/plugins#marketplace-metadata)
- [Plugin install deep link](https://learn.chatgpt.com/docs/reference/commands#plugin-install)
- [Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [Submit plugins](https://developers.openai.com/plugins/deploy/submission)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
