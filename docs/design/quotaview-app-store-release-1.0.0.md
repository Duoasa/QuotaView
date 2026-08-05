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
- Build Number：`1`
- Release Channel：`appstore`
- 开发分支：`codex/app-store-v1.0.0a`

## 2. Requirement

### AS-BASE-001：稳定基座隔离

- 生产代码以 `v0.3.1-build.2` 为唯一基座；
- App Store 工作在独立分支进行；
- 不把 `0.3.2 Preview 1` 的多任务实现静默迁入本版本；
- 不移动或覆盖既有稳定 tag、GitHub Release 与资产。

### AS-VERSION-001：App Store 版本映射

- App、Widget Extension 的 Marketing Version 均为 `1.0.0`；
- App、Widget Extension 的 Build Number 均为 `1`；
- App Bundle 记录 `appstore` 发布渠道；
- 字母 `a` 不进入 `CFBundleShortVersionString` 或 `CFBundleVersion`。

### AS-UPDATE-001：通用页版本展示

- 通用页保留 App 图标、名称、简介以及当前版本；
- 简体中文显示 `版本 1.0.0（Build 1）`；
- English 显示 `Version 1.0.0 (Build 1)`；
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

### AS-ACCOUNT-001：内置 Codex 账户 Runtime

- 基础额度、Credits、菜单栏与 Widget 不得依赖 Codex 插件；
- App Store 版本在 App Bundle 中嵌入固定版本、Universal、签名并继承沙盒的
  OpenAI Codex App Server Runtime；
- 用户通过官方 ChatGPT Device Code 明确登录，凭证由 Runtime 保存在
  macOS Keychain；
- QuotaView 不建立自身账号服务器，不保存邮箱，不把 Token 写入 Swift 状态、
  UserDefaults、App Group、日志或 Widget；
- Runtime 使用 QuotaView 沙盒容器内的独立 Home，不读取外部 `~/.codex`、
  项目、Prompt、线程或工具输出；
- 额度继续使用官方 `account/rateLimits/read`，可选 Usage 使用
  `account/usage/read`；
- App Server 客户端使用严格 RPC 白名单，不启用 Thread、Turn、Command、
  Process、插件、Marketplace、配置、实验性 API 或额度消费方法；
- Runtime 不自更新、不加载外部扩展，App 退出后不得残留进程；
- 详细包装、登录、隐私、刷新、审核、仓库和实施门禁见
  [QV-APPSTORE-CODEX-ACCOUNT-RUNTIME-001](quotaview-app-store-codex-account-runtime.md)。

### AS-SANDBOX-001：App Store 兼容性

后续阶段必须审计并解决 App Sandbox、Codex 外部进程、`~/.codex` Hook、
Helper 安装、本地 Socket、Widget App Group 与辅助功能权限的审核边界。
完成该审计前不得声称当前构建可提交 App Review。

Codex 灵动岛的安装、授权与事件传输采用已经接受的从属规格
[QV-APPSTORE-CODEX-ISLAND-BRIDGE-001](quotaview-app-store-codex-island-plugin-bridge.md)：
先通过公开 Git Marketplace 分发 QuotaView 配套插件，后续从同一插件源码
切换到 Codex 公共目录；QuotaView 只读取用户授权的插件 `PLUGIN_DATA`，
不得继续修改 `~/.codex`、安装 Helper、控制 Terminal 或使用全局
`/tmp` / Unix Socket。该规格当前为 `Planned`，尚未开始源码实施，也不代表
其他 Codex 外部 `Process` 阻断项已经解决。

基础额度的外部 `codex app-server` 启动、账号和沙盒迁移采用已经接受的
从属规格
[QV-APPSTORE-CODEX-ACCOUNT-RUNTIME-001](quotaview-app-store-codex-account-runtime.md)：
保留当前官方 App Server 协议和额度业务层，改为包内签名 Runtime、独立
ChatGPT Device Code 登录、Keychain 凭证和严格 RPC 白名单。该规格当前为
`Planned`，必须先通过 Runtime、登录、Keychain、额度一致性、双架构和
App Store Archive 技术 Spike，不能仅凭规格接受状态声称阻断已经解决。

### AS-VERIFY-001：验证与发布门禁

- 版本格式与 App/Widget 一致性测试通过；
- 中英文版本文案自动化测试通过；
- `swift test` 通过；
- Universal Xcode Release 无签名构建通过；
- App、Widget、Framework 与 Helper 保持 `x86_64 arm64`；
- 搜索确认不存在更新占位、自更新器、调试虚拟数据或 UI QA 入口；
- 视觉与交互结果由产品所有者运行后验收，未验收前标记为等待确认；
- App Review、App Store 发布与版本晋升需要单独授权。

## 3. 当前实施阶段

第一阶段已经实现 `AS-VERSION-001`、`AS-UPDATE-001`。第二阶段按用户
明确授权实现 `AS-RESET-001`：额度重置入口、详情、确认、设置、Demo
执行器、Widget 字段、Probe 输出和专用资源均已移除；主面板全部内容显示
时的高度由 `433 pt` 收敛为 `373 pt`。全量 `swift test` 共 53 项通过，
无签名 Universal Xcode Release 构建通过；App、Widget、Framework 与
Helper 均为 `x86_64 arm64`，产物版本为 `1.0.0 (Build 1)`、发行渠道为
`appstore`，已编译资源及二进制中无额度重置入口残留。视觉结果等待产品
所有者验收。

`AS-SANDBOX-001` 作为下一阶段，本阶段未改变权限、数据链路或 Codex 行为。
2026-08-06 已接受并固化 Codex 灵动岛的 Git Marketplace 双通道插件桥接
方案，实施入口见
[Codex 灵动岛插件桥接实施规格](quotaview-app-store-codex-island-plugin-bridge.md)。
同日接受基础额度的包内 Codex Account Runtime 与最小账户登录方向，实施
入口见
[Codex 账户 Runtime 实施规格](quotaview-app-store-codex-account-runtime.md)。
账户 Runtime 与灵动岛插件并列实施：前者拥有登录、额度和 Widget，后者只
拥有脱敏活动事件与灵动岛；二者不得形成基础功能依赖。
