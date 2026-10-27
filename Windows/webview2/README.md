# WebView2 主线

## 构建与运行

要求 Windows x64、.NET 10 SDK、Node.js 24、pnpm 11.25.0、WebView2 Evergreen Runtime。Node.js 仅用于构建和测试。`pnpm-lock.yaml` 与 `packages.lock.json` 锁定依赖；无隐藏开发目录或本机绝对路径依赖。

在主仓库的 `Windows/` 目录执行 `./build.ps1 -Action build|run|test|publish`。`publish` 默认生成包含 .NET 的 `webview2/release/standalone/` 和 `QuotaView-Windows-<version>-x64.zip`；`-FrameworkDependent` 需要用户安装 .NET 10 Desktop Runtime。两者均共享系统 WebView2 Runtime，不把整个 Chromium 引擎复制进包中。

WebView2 Runtime 官方安装入口：https://developer.microsoft.com/microsoft-edge/webview2/

如果 SDK 安装在自定义目录，应将其加入 PATH，并设置 DOTNET_ROOT；正常安装 SDK 无须额外配置。

## 运行时结构

.NET WinForms 管理窗口、屏幕 DPI、顶部定位、透明裁剪、托盘、文件、子进程、TCP / TLS 与系统代理。两个前台覆盖窗口承载灵动岛和用量胶囊，设置使用可缩放的独立窗口。

已有 JavaScript 业务模块经过 esbuild 编译，在独立的后台 WebView2 中运行。`runtime/electron.js` 是为旧应用控制器保留的接口适配层，不加载 Electron；文件、进程和网络 API 调用转交 .NET。React 与 GLSL 保留原有实现。原 Framework 辅助程序已合并到 .NET 主程序的无界面命令模式，因此不再要求 .NET Framework 4.8。

后台文档限定在打包的私有域名，只有它可访问原生 host object。可见界面关闭 host object，只开放列举的消息 API；导航、iframe、浏览器权限、下载和直接外部网络访问被禁用。外部链接与配置操作由原生端校验并执行。

## 动效与界面

运行时仅加载 AI 球、量子噪点及其完成描边 shader。焦点任务卡片显示量子噪点进度条，其余卡片显示 AI 球；默认聚焦首张卡片，点击卡片转移焦点，关闭详情仍保留焦点。同一任务保留动画时钟。进度由真实任务计划提供，没有计划时只显示状态场，不制造百分比。历史原型中的其他 shader 不进入主线运行时。

按产品要求，应用明确启用两种核心动态状态效果，因此 Windows 的系统减少动态效果不会把它们静止；窗口和界面过渡继续遵循系统偏好。渲染器仍支持显式静态模式供无障碍集成和测试使用，最小化 / 隐藏时暂停。

设置项与 mac v0.8.3-build.1 对齐，保留 Windows 原生标题栏操作；灵动岛与胶囊统一使用不透明纯色，不提供玻璃模式。旧玻璃偏好自动转为纯色。充值卡使用 mac 项目的 MIT 素材，仅展示，既不可键盘聚焦也没有点击跳转。

## 数据与配置

- 首次启用使用独立偏好目录 `%APPDATA%/QuotaView WebView2`，不会自动覆盖旧 Electron 偏好。
- 浏览器缓存和日志在 `%LOCALAPPDATA%/QuotaView WebView2`。应用日志不记录任务正文、认证令牌或 Cookie。
- 自动发现本机 Codex，并连接桌面的实时审批与问题队列。其他客户端 Hook 的安装 / 卸载通过连接页操作；保留其他工具已有的 Hook 配置。
- Hook 引用当前应用的绝对路径。移动或删除运行目录前，在连接页解除相应 Hook；移动后重新配置。
- 用量账户统计和本地记录不叠加。成本按可识别模型估算，不是订阅账单；缺失日期不会当成零值。

## 验证

`-Action test` 依次运行：

1. 真正的 WebView2 渲染测试：shader 像素、连续帧变化、状态过渡和卸载；悬停、离开、固定、待确认；用量布局、充值卡不可交互、活动模式及所有设置页。
2. .NET 适配层测试：Unicode 文件、原子配置与锁、TOML / YAML、持续子进程 stdin、TCP 半关闭、HTTP CONNECT 和 Hook 往返。
3. 共享 Node 业务 / 协议 / 设置回归测试，调用新的 .NET 无界面辅助模式。

测试使用隔离目录和明确标记的演示数据，正常启动不生成演示任务。报告和界面截图位于 `webview2/build/`，不会进入源码提交或运行包。`--validation-report=<绝对路径>` 可额外执行本机真实读取并保存不含任务内容的诊断报告；普通运行不要传入此测试参数。

已在 Windows / WebView2 上检查 150% DPI、带负坐标的副屏、顶部贴合和原生窗口裁剪。未配置的第三方客户端未在本机完成真实会话验收，现有协议由隔离测试覆盖。

本轮界面调整：灵动岛与胶囊固定为深色纯色；任务卡片悬停时 Agent 图标替换为归档按钮。归档仅隐藏当前回合，保留原客户端会话；新回合会重新显示。Token 活动采用 53 周 × 7 行，每周与累计总量用向上填充的方格柱表示。

## 隔离审批验证

`-Action test` 还会运行 `--approval-test`：Claude 原生 Hook → 真实界面按钮 → 原生回执，覆盖允许、拒绝、取消、问题回答和过期请求；Codex 原生 Hook → 待确认 → 自动展开 → 工具结束清除。模拟项目及客户端配置位于独立目录，卡片中的命令不会执行。`webview2/build/approval-report.json` 保存结果。

可执行文件加 `--approval-demo` 可手动体验 Claude 审批卡片，`--approval-demo-dir=<目录>` 指定项目根目录。正常模式不产生模拟请求。Codex 仅接通 Hook 时为只读请求；连接兼容的 Desktop owner 后支持原会话审批与问题回复。

## 当前正式版 0.8.3-win（包内版本 0.8.3-win.10）

[首个 Windows 正式版](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-win.10) 复用已验证的 `0.8.3-win.10` 原包，公开名称为 `0.8.3-win`。包名、tag 和更新身份保留 `.10`，首个签名条目加入独立 Windows 通道。资产、哈希及 CI 记录见[版本历史](../../VERSION_HISTORY.md#当前最新版本)。

Windows 工程迁入 `Duoasa/QuotaView/Windows`。版本身份统一来自 `version.json`；新增独立 Windows appcast、RSA-PSS/SHA-256 校验、用户触发下载与取消、重启安装及文件写入失败回滚。配置目录与安装路径保持不变。原生更新测试覆盖 30 项状态/校验/回滚场景；实际效果由用户验收。发布和签名说明见 [Windows 更新](../updates/README.md)。

`-Action test` 还运行 `tests/updates/Updates.Tests.csproj`。发布包签名 fixture 的核验入口：`dotnet run --project webview2/tests/updates/Updates.Tests.csproj -c Release -- --verify-package <appcast.xml> <package.zip>`（在 `Windows/` 执行）。测试只写临时目录，不安装到真实应用。

## 本地开发版 0.8.3-win.9

- 接入 Codex Windows Desktop 的命名管道 follower：当前请求自动显示，批准、拒绝、同步与异步问题提交给原会话 owner。额度 App Server 保持独立只读。
- 只接受当前连接、当前 owner 和当前请求；提交前重新同步，旧请求、重复提交和断线不能继续操作。超时不自动重试决定。
- 支持命令、文件与权限请求；MCP 空表单支持确认，外部验证及复杂表单留在原客户端。非兼容版本降级为只读。
- 已通过原生冒烟、适配器、原有审批测试及 46 项回归；本机真实桌面已连接，用户确认异步问题已通过灵动岛回到原聊天。后续 MCP 小范围适配仅编译，未追加交互验收。
- 已知未核实项：一次真实拒绝测试用户表示点击拒绝，但命令仍执行；桌面日志记录该请求收到 accept。依用户要求停止进一步核对，不能将此项记为真实拒绝验收通过。
- 本批审批接入基于 main 的 34bb9d4；提交邮箱为 xuchen1995@gmail.com。
