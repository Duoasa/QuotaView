# QuotaView Windows

QuotaView 的 Windows 灵动岛适配工程，不包含桌面小组件。当前主线是基于 dot `0.8.3-win.1` 运行包的 Electron 接入版本 `0.8.3-win.1.effects.2`，已接入 AI 球、量子噪点，以及透明背景和屏幕贴顶修复。

## 工程入口

| 目录 | 内容 |
| --- | --- |
| `windows/` | 当前可独立构建的 Electron 工程、锁文件、资源及 Hook 构建脚本，见 [构建说明](windows/README.md) |
| `ElectronEffects/` | 共用特效源码与测试；旧版运行包适配器作为历史工具保留 |
| `Prototypes/EffectsLab/` | 已验收的独立 OpenGL 特效开发台、shader 和测试 |
| `Imports/dot-0.8.3-win.1/app-review/` | 原交付包提取的后端代码与前端编译产物，保留许可证；不等同完整 React 源码 |
| `src/`、`tests/` | 早期独立 WPF 最小实现与测试 |
| `docs/` | 移植范围与交付包审阅记录 |

仓库包含构建所需代码、图片字体和依赖锁文件，不提交 Electron 二进制、原始交付压缩包、本机配置或运行日志。`windows/` 构建不依赖 `Imports/` 或旧运行包。前端基于现有 JavaScript 产物恢复并格式化，包含 React 运行库；不是 dot 未交付的原始 JSX/TSX 工程，来源和维护限制见 `windows/README.md`。

Windows x64 安装 Node.js 24.19.0 与 pnpm 11.25.0 后：

```powershell
git clone https://github.com/Duoasa/quotaview-windows.git
cd quotaview-windows/windows
pnpm install --frozen-lockfile
pnpm test
pnpm run package
```

生成 `windows/release/win-unpacked/QuotaView Windows.exe`。开发运行使用 `pnpm start`，生成单文件便携包使用 `pnpm run dist`。首次安装和打包需要网络下载公开依赖；产物未签名。

以下记录为早期 WPF 原型的说明，其功能边界不代表当前 Electron 版本。

## WPF 最小预览

另有独立 [AI 球 / 量子噪点特效开发台](Prototypes/EffectsLab/README.md)，运行 `Prototypes/EffectsLab/bin/QuotaView.EffectsLab.exe` 可切换状态与模拟进度，检查原版 shader 的 Windows 移植效果。

以最新公开发行版 **v0.7.7-build.1** 为基准，固定源码提交 `3866177cfa19db734d657ef505a4dc72c3338fba`。不是 `main` 开发版，也没有修改 macOS 仓库。来源与移植位置见 [BASELINE.json](BASELINE.json)。

## 运行

双击 `bin/QuotaView.Windows.exe`。首次查看可以运行：

```powershell
& './bin/QuotaView.Windows.exe' --expanded
```

灵动岛位于屏幕顶部中央。悬停或点击展开，移开约一秒收起；圆点按钮可固定展开。点击任务查看公开进展或完成结果。“用量”展示本地日志中最近一次额度记录。右键菜单、设置页或系统托盘均可退出。

本地构建与冒烟测试：

```powershell
./build.ps1 -Test
```

当前机器没有 .NET SDK，最小版采用 **C# / WPF / .NET Framework 4.8**，直接调用 Windows 已有编译器，无 NuGet 依赖。它是独立开发程序，不需要安装，不配置自启动。后续正式 Windows 工程可迁移到现代 .NET。

## 已实现

- 移植发行版 340/680 点宽度、60 点任务卡和顶部连续轮廓。
- 收起／展开动画、置顶、不主动抢焦点、固定展开、减少动态、系统托盘。
- 从 `CODEX_HOME` 或 `%USERPROFILE%\.codex` 只读发现最近七天内最多 24 个会话文件，列表最多显示 12 个用户会话。
- 后台每两秒按字节偏移增量读取，支持文件共享、半行写入、UTF-8 分段、日志截断；单行上限 1 MiB，初始尾部上限 8 MiB，每文件每轮最多 2 MiB。
- 真实任务开始／完成／中断、公开进展、模型、会话及轮次 Token；有明确父关系时显示子任务条。
- 简化状态球、完成描边、完成结果查看、仅当前运行生效的本地归档。
- 本地日志额度快照；数据缺失显示“—”，不会伪造为零。

## 当前边界

- 本次只做最小可运行实现；**最终目标仍是完整灵动岛**，不包含桌面小组件。
- 未实现 Windows Desktop IPC、可操作审批、完整问题卡片、实时账户查询、完整设置、Markdown 富文本及原版 Metal 特效。
- 日志中观察到的同步提问仅提示回 Codex 操作，不产生可点击的批准按钮；其他审批不能保证被日志发现。
- 额度快照可能滞后；连接提示只代表读取本地记录成功。超过十分钟没有活动更新的运行任务显示“等待更新”，不伪造完成或断线。
- 初始日志截断范围之外的任务开始不会由上下文合成，需要后续真实开始事件。仅原生来源已知的用户／子任务进入列表，未知和内部任务隐藏。
- 默认主界面中文，系统字体；多屏混合 DPI、键盘交互、视觉效果仍待实机验收。
- 无账号写操作，不读取认证文件，不展示用户消息、私有 reasoning、加密内容或代理间私信。仅在内存保留有上限的公开进展，不持久化原始会话。
- `.local/` 仅保存预览偏好与脱敏运行计数。未安装、签名、发布或推送 GitHub。

## 验证

`tests/Smoke.cs` 覆盖真实完成语义、旧轮次拒绝、公开内容过滤、Token 作用域、确认匹配、额度缺失、子任务关系、半行 UTF-8、文件截断和超长行恢复。视觉／交互由用户验收，构建通过不代表视觉通过。
