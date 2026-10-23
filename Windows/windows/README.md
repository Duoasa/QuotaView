# 历史 Electron 构建说明

当前主线已迁移至 [.NET + WebView2](../webview2/README.md)，请从仓库根目录运行 `./build.ps1`。以下内容保留作为旧 Electron 发行版维护参考。

# Windows 构建与维护

## 环境与命令

运行目标为 Windows 10 22H2 / Windows 11 x64，需系统 .NET Framework 4.8。原生 Acrylic/Mica 需要 Windows 11 22H2+；较旧版本、关闭透明效果或高对比度模式使用纯色回退。ARM64 目前未建立构建与验收矩阵。

开发环境：Node.js **24.19.0 x64**、pnpm **11.25.0**。依赖版本以 `pnpm-lock.yaml` 为准；Electron 固定为 44.9.2，保留发布冷静期检查。正常构建不需要 .NET SDK、NuGet 或第二套 Node 运行时；辅助程序用系统 Framework 的 `csc.exe` 编译。

```powershell
pnpm install --frozen-lockfile
pnpm run build
pnpm run build:helper
pnpm test
pnpm run test:renderer
pnpm start
```

`test:renderer` 需要 Chrome，可用环境变量 `QV_CHROME` 指定可执行文件。它创建独立临时配置并使用合成数据，不读取真实账户。`pnpm test` 中 5 个原生辅助程序测试只在 Windows 运行，其他平台会明确跳过。

```powershell
pnpm run package  # release/win-unpacked/，整个目录一起分发
pnpm run dist     # 未签名 NSIS 安装包和单文件便携包
pnpm run size     # 实测大小和预算检查，保存 release/size-report.json
pnpm run smoke    # 开发 Electron 的隔离启动、桥接和 GPU 检查
```

也可对打包 EXE 使用 `--smoke-test --smoke-report=<绝对路径>`。发布的 `0.8.3-win.1.effects.2` x64 预览版见[GitHub Pre-release](https://github.com/Duoasa/quotaview-windows/releases/tag/v0.8.3-win.1.effects.2)；未签名，未自动安装，Windows 实机验收待完成。CI 使用 `--publish never` 并关闭证书自动发现，保存构建产物供检查。

## 代码组织与复用

- `src/core/`：现有额度、任务观察、集成与配置管理；`shared/task-state.js` 统一事件、界面和动效的进度语义。
- `renderer/app.js`、`common.js`、`tasks.js`、`usage.js`、`settings.js`：按职责拆分的可编辑界面模块。代码从原交付产物恢复，**不是未交付的原始 JSX/TSX**。已恢复模块边界、组件名、React API 及主要工具函数名，局部变量仍有历史缩写。
- `renderer/vendor/react-runtime.js`：隔离保存原交付中的 React / React DOM，许可证保留。没有同时引入第二份框架。
- `../ElectronEffects/src/`：复用已认可的球体/量子模型，烟雾与波浪从原有 StateSmoke 算法移植到 GLSL。同一窗口只有一个 WebGL 上下文，设置预览降至 24 fps / DPR 1，普通窗口最高 60 fps / DPR 2。
- `native/QuotaViewHelper.cs`：.NET Framework Hook 传输与 user32 前台矩形检测。只报告矩形和 PID，不读取窗口标题或内容。
- `scripts/build-helper.cjs`：编译、辅助程序自检、SHA-256 清单与 1 MiB 上限；没有 Node SEA / postject。
- `assets/`：复用图标、字体等资源；删除重置演示资源和已由实时渲染替代的动效预览 PNG。原型、Imports、测试、SDK、构建缓存不进入安装包。

## 行为边界

- 重置演示页及开关已删除；真实额度的重置倒计时继续保留。桌面小组件不进入 Windows 构建。
- Codex 额度连接使用独立只读 App Server；审批与问题回答使用单独的桌面 follower 连接。Windows 原生宿主校验同一命名管道的服务端用户与 Codex 包身份，发现原会话 owner 后订阅 v11 状态；只向该 owner 提交当前请求，不接管或重启会话。中断仍在 Codex 处理。
- Claude 只有本次连接的实时 PermissionRequest 可以响应；超时、错误 ID 或失去连接时不产生批准决定。
- Claude 新轮次预览要求匹配当前提示 ID，或明确的新时间戳。在缺乏可信边界时保留空预览，避免旧答案/中断污染新任务；真实 Claude 版本的日志顺序仍需实机验证。
- 代理覆盖更新检查和 QuotaView 启动的 Codex 额度子进程。系统模式通过 Electron 解析代理/PAC；本地鉴权 CONNECT 桥接支持 HTTP/HTTPS、SOCKS5、SOCKS4a。手动代理不接受嵌入账号密码，HTTP 普通请求不经该桥接转发。其他 Agent 进程保持自己的代理配置。
- 长时间无新事件的观察任务显示未知；不会合成完成。可响应审批不会因为观察超时而消失。

## 安装与卸载

NSIS 采用当前用户安装，不删除应用数据。明确卸载时调用 `--cleanup-integrations`，依据已有安装记录移除 QuotaView 所有的 Hook，恢复原状态栏并保留其他配置和备份；清理失败中止卸载。升级不会执行集成卸载。便携版删除前可在“连接”页逐一关闭集成，或关闭应用后手动执行上述清理参数。

便携版辅助程序保存在用户数据目录下的内容哈希子目录，确保临时解包目录消失后 Hook 路径仍有效。旧辅助程序不盲目删除，避免破坏仍引用它的配置；本轮优先消除新增完整 Node 副本。

## 验证与大小

[Windows CI](../.github/workflows/windows.yml) 依次执行锁文件安装、辅助程序编译、协议与配置保留测试、页面/GPU 冒烟、NSIS/便携打包、打包程序启动以及大小检查。

大小预算：辅助程序 ≤1 MiB、ASAR ≤32 MiB、每个分发 EXE ≤220 MiB、展开应用 ≤400 MiB。这些是阻止回退的预算，**不是本轮实测产物大小**。真实数值由 CI `size-report.json` 记录。保留 Electron 意味着仍有 Chromium 的固定体积成本。

本轮证据与待验收项目见 [移植检查表](../docs/WINDOWS-PORT-CHECKLIST.md)。自动检查不替代 Windows 真机、显卡、账户、长时间运行或视觉验收。
