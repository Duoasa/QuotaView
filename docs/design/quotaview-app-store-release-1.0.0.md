# QuotaView 1.0.0 App Store 发行适配规格

> 文档编号：`QV-APPSTORE-RELEASE-1.0.0-001`
>
> 规格状态：`Accepted`
>
> 交付状态：`Implementing`
>
> 用户授权日期：2026-08-05
>
> 依赖基线：QuotaView `0.3.1 (Build 2)`

## 1. 目标与版本身份

本迭代从稳定 tag `v0.3.1-build.2` 的提交
`3119171f45163fe45d68a4f774a0488968f14fd7` 建立独立 App Store 分支，
在不移动稳定 tag、不覆盖既有 GitHub Release 的前提下完成 Mac App Store
适配。

用户指定的 `QuotaView v1.0.0a` 是内部发行代号。App Store 与应用包使用：

- Marketing Version：`1.0.0`
- Build Number：`4`
- Release Channel：`appstore`
- 当前开发分支：`codex/appstore-runtime-spike`

## 2. Requirement

### AS-BASE-001：稳定基座隔离

- 生产代码以 `v0.3.1-build.2` 为唯一基座；
- App Store 工作在独立分支进行；
- 不把 `0.3.2 Preview 1` 的多任务实现静默迁入本版本；
- 不移动或覆盖既有稳定 tag、GitHub Release 与资产。

### AS-VERSION-001：App Store 版本映射

- App、Widget Extension 的 Marketing Version 均为 `1.0.0`；
- App、Widget Extension 的 Build Number 均为 `4`；
- App Bundle 记录 `appstore` 发布渠道；
- 字母 `a` 不进入 `CFBundleShortVersionString` 或 `CFBundleVersion`。

### AS-UPDATE-001：通用页版本展示

- 通用页保留 App 图标、名称、简介以及当前版本；
- 简体中文显示 `版本 1.0.0（Build 4）`；
- English 显示 `Version 1.0.0 (Build 4)`；
- 版本与 Build 必须读取当前 App Bundle，不在界面硬编码；
- 缺失 Bundle 值时显示破折号，不伪造版本；
- 删除“检查更新”按钮、自动更新占位提示和对应瞬时状态；
- 页面说明只表达应用信息与当前版本；
- App Store 负责后续自动与手动更新，本版本不包含自更新器。

### AS-RESET-001：移除额度重置操作

- App Store `1.0.0` 不显示额度重置入口、详情页、Demo 标签或最终确认层；
- 删除“额度重置入口”设置以及对应持久化偏好；
- 删除本地 Demo 操作执行器、操作可用状态和模拟执行测试；
- App、Widget 快照与 Probe 不再投影或展示可用重置次数；
- 删除重置详情源码、专用图标资源和 Xcode Target 引用；
- 保留“下次重置”时间与倒计时，它们只描述当前用量周期；
- 保留普通 Credits 余额，它不等同于额度重置次数；
- 不调用也不预留 `account/rateLimitResetCredit/consume` 的运行时入口。

### AS-ACCOUNT-001：官方 Codex 登录与脱敏插件快照

- 账号登录只在官方 Codex 中完成；QuotaView 不注册 OAuth Client、
  不接收 Token、不保存账号凭证；
- 配套插件只启动官方 `codex app-server`，调用只读的
  `account/rateLimits/read` 与 `account/usage/read`；
- 插件只写入字段白名单的 `usage.json`：方案、主周期用量/
  重置时间、普通 Credits、限制状态、累计 Token 和最新日用量；
- 不写入邮箱、账号 ID、Token、Cookie、Prompt、原始 RPC 响应、
  额度重置券库存或其他未批准字段；
- QuotaView 仅通过用户选择目录的只读 security-scoped bookmark
  消费快照，不启动子进程，不访问网络，不读取
  `~/.codex/auth.json`、Codex Keychain 或浏览器数据；
- `quotaview://pair` 只用于打开目录配对界面，不是 OAuth 回调；
- 快照缺失时主面板显示“Codex 连接”快捷入口，有效快照
  到达后自动恢复用量图表；
- 详细合同见
  [QV-APPSTORE-CODEX-USAGE-SNAPSHOT-BRIDGE-001](quotaview-app-store-codex-usage-snapshot-bridge.md)。

此前的
[QV-APPSTORE-CODEX-ACCOUNT-RUNTIME-001](quotaview-app-store-codex-account-runtime.md)
与 [Runtime Phase 0 报告](../spikes/APPSTORE_ACCOUNT_RUNTIME_PHASE0.md) 只作为
已淘汰路线的历史证据保留，不再阻塞或驱动生产开发。

### AS-SANDBOX-001：App Store 兼容性

主 App 必须启用 App Sandbox，只保留 App Group 和用户明确
选择目录的只读权限。App Store 目标不得包含 Codex 外部进程、`~/.codex`
读写、Hook 安装、Helper、Expect、Socket、全局 `/tmp` 队列、辅助功能或屏幕
录制权限。App Bundle 还必须包含与实际 API 使用一致的隐私清单；当前只允许
主 App 声明 `UserDefaults CA92.1` 与用户所选目录元数据
`FileTimestamp 3B52.1`，Widget 和 Framework 不声明或使用额外 Required
Reason API。独立源码、Manifest 与 Bundle 数量门禁会拒绝未经审计的类别
漂移。当前源码和本轮 Universal 无签名 Release 已完成上述迁移；更早的
Apple Distribution `.pkg` 只证明历史导出链路，不对应当前用量架构。由于
App Store 定价、公开页面、内容权利和产品验收门禁
尚未关闭，该候选包不是最终提交包，App Review 也尚未开始。

Codex 灵动岛的安装、授权与事件传输采用已经接受的从属规格
[QV-APPSTORE-CODEX-ISLAND-BRIDGE-001](quotaview-app-store-codex-island-plugin-bridge.md)：
先通过公开 Git Marketplace 分发 QuotaView 配套插件，后续从同一插件源码
切换到 Codex 公共目录；QuotaView 只读取用户授权的插件 `PLUGIN_DATA`，
不得继续修改 `~/.codex`、安装 Helper、控制 Terminal 或使用全局
`/tmp` / Unix Socket。该链路已经实施并完成本地自动验证，公开仓库
`Duoasa/QuotaView-for-Codex` 的活动事件版 `v1.0.0-preview.1` 继续作为历史
版本；支持 `codex-usage-snapshot` 的固定 `v1.0.0-preview.7` Pre-release
已经发布。其 mock、官方 app-server live 验证、匿名固定 tag clone、隔离
安装/卸载/重装、确定性资产、CI artifact 与公开资产回下载均通过；本机受信任
安装实例持续产生脱敏事件和用量快照，且插件源码与固定 tag 一致。

基础额度与沙盒迁移由
[QV-APPSTORE-CODEX-USAGE-SNAPSHOT-BRIDGE-001](quotaview-app-store-codex-usage-snapshot-bridge.md)
驱动。`Info.plist` 只注册唯一 `quotaview` Scheme，URL 类型标识为
`com.quotaview.menubar.pairing`、角色为 `Editor`；回调只接受严格的
`quotaview://pair`。不得存在 OpenAI OAuth/usage endpoint 配置或 ATS
例外，主 App 的 entitlement 也不得包含 Network Client。

### AS-PRICING-001：付费 App 全功能

- QuotaView 在 Mac App Store 采用付费下载模式，基准价格为 `USD 4.99`；
- 用户完成 App Store 购买并下载 App 后，可以使用全部内置功能，包括基础
  额度、菜单栏、主面板、Widget 与 Codex 实时灵动岛；
- App 内不提供 IAP、订阅、许可证、试用门槛或单独功能解锁，也不保存本地
  购买资格布尔值；购买、重新下载和家庭共享资格由 Mac App Store 处理；
- Codex 灵动岛仍需要用户安装并配对公开的 QuotaView for Codex 插件、信任
  Hooks 并授权插件 `PLUGIN_DATA` 目录只读访问；这是集成前置条件，不是付费门槛；
- QuotaView 不下载、安装或执行插件代码，只打开稳定安装说明；插件安装、
  更新、启用和 Hook 信任由 Codex 与用户完成；
- `Configs/App.xcconfig` 必须记录 `paid-upfront`、`4.99` 和可审计的价格配置状态；
  只有 App Store Connect 已完成 Paid Apps Agreement 与价格设置后，提交模式
  才允许该状态改为 `configured`；
- 详细插件边界见
  [QV-APPSTORE-CODEX-ISLAND-BRIDGE-001](quotaview-app-store-codex-island-plugin-bridge.md)。

### AS-VERIFY-001：验证与发布门禁

- 版本格式与 App/Widget 一致性测试通过；
- 中英文版本文案自动化测试通过；
- `swift test` 通过；
- Universal Xcode Release 无签名构建通过；
- App、Widget 与 Framework 保持 `x86_64 arm64`；完成灵动岛插件迁移后，
  App Store Bundle 不再包含 Activity Helper；
- 主 App 声明 App Store `Developer Tools` 类别，Archive 不得再出现缺失应用
  类别警告；
- 搜索确认不存在更新占位、自更新器、调试虚拟数据或 UI QA 入口；
- 视觉与交互结果由产品所有者运行后验收，未验收前标记为等待确认；
- App Review、App Store 发布与版本晋升需要单独授权；
- 源码、配置和最终 Bundle 必须确认无 App 自有 OAuth、Keychain
  凭证与非公开 usage endpoint；提交模式 readiness 只在脱敏快照
  live 验证、付费 App 价格、插件发布和公开页状态全部就绪后允许
  Archive/export。

## 3. 当前实施阶段

第一阶段已经实现 `AS-VERSION-001`、`AS-UPDATE-001`。第二阶段按用户
明确授权实现 `AS-RESET-001`：额度重置入口、详情、确认、设置、Demo
执行器、Widget 字段、Probe 输出和专用资源均已移除；主面板全部内容显示
时的高度由 `433 pt` 收敛为 `373 pt`。视觉结果等待产品所有者验收。

第三阶段已实施 `AS-ACCOUNT-001`、`AS-SANDBOX-001` 与
`AS-PRICING-001`：官方 Codex 登录/脱敏插件快照、App Sandbox、旧
Runtime/CLI/Helper 删除、付费下载全功能模式和只读插件桥均已落地。此前
实现的 StoreKit 非消耗型灵动岛方案已于 2026-08-08 被产品所有者明确替换；
购买状态对象、购买/恢复界面、本地 StoreKit 配置、测试和发行门禁均已删除。
插件产生的新鲜脱敏事件在协议和目录授权通过后直接驱动灵动岛；
用量快照需要用户已在官方 Codex 登录，两者均不依赖 App 内购买资格。

现行用量实施入口为
[官方 Codex 用量快照桥实施规格](quotaview-app-store-codex-usage-snapshot-bridge.md)，
插件实施入口为
[Codex 灵动岛插件桥接实施规格](quotaview-app-store-codex-island-plugin-bridge.md)。
同一 Git 插件负责用量快照与脱敏活动事件，QuotaView 仅负责验证和展示。
官方 Codex 尚未登录或用量刷新失败不得阻断已配对的灵动岛事件。

当前 `swift test` 执行 61 项、0 失败，普通运行中 1 项显式 live 插件 E2E
跳过；官方 Codex 真实快照另行通过生产读取器；付费 App、用量快照、插件、
公开页面状态门禁和普通 readiness 检查通过。App Store 双语元数据、
Review Notes、Privacy、Support 与插件发行说明已切换为 `Paid Upfront`、
`USD 4.99`、全部内置功能随下载提供且无 IAP。此前导出的签名 Archive 与
`.pkg` 早于本次价格模型变更，只作为发行链路历史证据，不是当前候选包；
最终门禁关闭后必须重新 Archive/export 并记录新哈希。

Build 4 Universal 无签名 Release 已重新构建并通过 Bundle 审计：App、Widget
与 Framework 均为 `arm64 + x86_64`，版本为 `1.0.0 (Build 4)`，发行渠道为
`appstore`，包内没有 `.storekit`、
`.xctest`、Runtime、CLI、Helper、Probe 或旧购买组件。

插件状态切换为 `released` 后，Build 4 Apple Development 签名 Archive 已
重新生成并通过同一 Bundle 审计；当前安装于 `/Applications` 的审核包使用
同一签名身份、Team ID 与 App Group，Widget 唯一注册和数据读取正常。该包
仍不是 App Store Distribution 提交包。

Archive 导出前仍由 `scripts/check-appstore-bundle.sh` 复核最终 App 的版本、
双架构、资源、隐私清单、禁止残留、签名和沙盒 entitlement；导出后由
`scripts/check-appstore-export.sh` 检查 `.pkg` 签名、Team ID、Payload、大小
和 SHA-256。readiness 提交模式要求脱敏用量快照为
`validated`、付费 App 价格状态为 `configured`、插件端到端为就绪、隐私政策
和支持页已经公开，否则失败关闭。

用户更换或断开插件数据目录时，状态层会先提高 configuration
revision、清除旧主 App/Widget 快照，再从新授权目录刷新。普通短暂
读取错误可保留最后有效快照，但目录切换不得跨插件安装沿用旧数据。

剩余门禁是 Paid Apps Agreement 与 App Store
Connect `USD 4.99` 价格配置、
Content Rights、隐私政策和支持页公开、支持邮箱、最终提交包，以及产品所有者
视觉与交互验收。
