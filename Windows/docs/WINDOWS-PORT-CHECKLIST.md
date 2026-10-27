# Windows 移植检查表 · 2026-10-22

## 本轮实现

| 范围 | 修改 | 验证依据 |
| --- | --- | --- |
| 界面 | 移除重置演示导航、设置开关、素材；保留真实重置倒计时 | 页面遍历与源码检查 |
| 设置 | Windows 导航、最小化/最大化/关闭、深浅主题、高对比度与键盘焦点 | Chromium 页面挂载和设置更新测试；视觉待验收 |
| 材质 | Win11 22H2+ Acrylic/Mica；按界面边界裁剪；关闭透明或不支持时纯色回退 | 几何/能力测试；实际 DWM 待验收 |
| 动效 | 球、烟雾、量子、波浪共用 WebGL2，复用原 shader 参数 | 实际 GLSL 编译、像素响应、完成收尾、组件卸载检查 |
| 进度 | 同一 0–95% 运行进度，真实完成到 100%；计划调整不倒退 | 模型与边界测试 |
| Claude | 新轮次不继承旧答案、中断和 token；过期观察显示未知 | 临时 transcript fixture |
| 网络 | 更新和独立 Codex 额度进程使用统一代理配置 | 本地 HTTP CONNECT / SOCKS5 / PAC 路由测试 |
| 辅助程序 | Framework 4.8 小 EXE 替代 Node SEA；user32 替代常驻 PowerShell | C#5 / net48 参考程序集编译及 Windows 原生协议测试通过 |
| 集成清理 | 只移除所属 Hook；恢复原状态栏；保留其他设置和备份 | 临时用户配置安装/重配/卸载测试 |
| 打包 | 白名单、NSIS/portable、独立 helper、自检与大小报告 | Windows CI 构建、打包启动与大小检查通过 |

## 本地证据

在 macOS 独立 checkout 中：

- `pnpm install --frozen-lockfile --ignore-scripts` 成功；未跳过依赖发布时间策略。
- `pnpm test`：22 项通过，5 项 Windows 原生执行测试明确跳过。
- `pnpm run build` 成功。
- `pnpm run test:renderer`：island / capsule / settings 挂载；7 个设置分类遍历；球体和三种进度 shader 像素验证；实时预览选择、深浅色与减少动态更新；预览卸载检查通过。使用隔离 Chrome 与软件 WebGL，不代表 Windows GPU 性能。
- 辅助程序使用临时 .NET SDK 与 net48 参考程序集、C#5 编译检查，零错误、零警告。没有在 macOS 执行 Windows helper。

## Windows CI 已通过

已添加 `.github/workflows/windows.yml`，触发方式包括 push、pull_request 和手动运行。代码提交 `aa2d322` 的 [Windows CI](https://github.com/Duoasa/quotaview-windows/actions/runs/39729392168) 已通过以下步骤：27 项测试全部通过、无跳过。后续提交仅更新验证文档；实际结果以对应提交的 GitHub Actions 记录为准。

1. 锁文件依赖安装与 Framework 系统编译器构建。
2. 全部 JS 测试及 5 项 Windows helper 测试：协议最小字段、审批相关性、超时不批准、原命令/Unicode 转发。
3. Chrome 页面/GPU 冒烟与打包 Electron 的独立用户目录启动。
4. 未签名 NSIS 与便携包构建。
5. `size-report.json`、`packaged-smoke.json`、helper 清单与 EXE 上传为 CI artifact，不创建 Release。

首次 Windows CI 实测（字节数来自 `size-report.json`）：

| 产物 | 字节 | 大小 |
| --- | ---: | ---: |
| NSIS 安装包 | 119440759 | 113.9 MiB |
| 便携包 | 119120904 | 113.6 MiB |
| 展开应用 | 400947945 | 382.4 MiB |
| app.asar | 15052940 | 14.4 MiB |
| 原生辅助程序 | 20480 | 20 KiB |

## 首个完整移植预览版

`v0.8.3-win.1.effects.2` [Pre-release](https://github.com/Duoasa/quotaview-windows/releases/tag/v0.8.3-win.1.effects.2) 使用 `main` 提交 `f2046a7718d3636b12d2453bbd88df3380a16c7d` 的 [Windows x64 CI](https://github.com/Duoasa/quotaview-windows/actions/runs/39730000641) 产物；27 项测试全部通过、无跳过，打包启动报告确认 `win32 / x64 / packaged: true`。便携包 119120903 字节，安装包 119440757 字节；两者未签名。附件包含 `SHA256SUMS.txt` 与 `validation-report.json`。发布预览版不代表下列实机验收已完成。

## 实机验收待办

- Windows 10 纯色回退、Windows 11 22H2+ Acrylic/Mica、关闭系统透明效果、高对比度。
- 100/125/150/200% DPI、负坐标副屏、跨屏移动、顶部任务栏、显示器热插拔；裁剪区域无黑边/漏点击。
- 设置最大化与还原、键盘操作、中文/英文、系统深浅色切换；球体与三种动效视觉对照。
- 集成 Codex、Claude、DSH、Kimi 的真实客户端版本；Claude transcript 顺序、实时审批、取消/重连、退出后 fail-open。
- 用户代理/PAC 环境下真实 Codex 额度刷新与认证刷新；关闭代理不遗留继承环境变量。
- NSIS 安装/升级/卸载、便携目录迁移、自启动；第三方 Hooks 和原状态栏无损保留。
- Intel/AMD/NVIDIA、远程桌面、无硬件加速、休眠唤醒、长时间运行的 CPU/GPU/内存与日志体积。

Codex Desktop 的 Windows 私有审批/问题/中断传输未建立可验证所有权协议，当前明确不支持。该项不能以只读额度 App Server 冒充实现，也不能标记为与 macOS 完全一致。
