# dot Windows 适配包审阅与接手方案

审阅日期：2026-10-21。对象为 `F:/Codex Project/新建文件夹/` 中的 12 个运行分包和 1 个合并工具包。

这是一套覆盖面较广的 Electron Windows 预览实现，可以作为后续集成的候选主线。本机隔离启动检查已通过。当前主要缺口是完整开发源码、真实客户端验收，以及接入用户已经认可的 AI 球与量子噪点着色器。

## 文件整理结果

原始下载文件保持原样。项目内新增 `Imports/dot-0.8.3-win.1/`：

| 路径 | 用途 |
| --- | --- |
| `join-kit/` | 原交接文档、清单和合并脚本的审阅副本；未执行其中脚本 |
| `verified-runtime.zip` | 校验后的合并运行包，239,424,838 字节 |
| `runtime/win-unpacked/` | 完整运行目录，展开文件合计 527,847,733 字节；入口 `QuotaView Windows.exe` |
| `app-review/` | 从 ASAR 提取的可读后端代码、前端产物和文本配置；不是完整源码工程或独立运行目录 |
| `inventory.json` | 分包、片段和合并包校验结果，以及运行目录清单 |
| `asar-inventory.json` | ASAR 内文件清单、大小和偏移 |
| `windows-smoke.json` | 本次 Windows 隔离启动结果 |
| `windows-smoke.stdout.txt`、`windows-smoke.stderr.txt` | 本次启动日志 |
| `inspect-delivery.ps1` | 本次分包校验与安全解压脚本；输出存在时拒绝覆盖 |

合并包 SHA256：`cf65a7b60e08e0167638c438ccf24ae13918ccf76f885a67faddecf9505ab614`。Helper SHA256 与随包清单一致：`ecf3afb41cb4973ccb571e803d13bfb7ad1653e7d2ac42ab3213154973818c99`。校验确认文件一致性，不等于代码签名。

## 与本地原型的关系

| 方面 | 当前本地原型 | dot 交付物 |
| --- | --- | --- |
| 基准 | v0.7.7-build.1，提交 3866177 | 包内版本 0.8.3-win.1；交接声明参考 f779531 源码快照及 v0.8.3-build.1 |
| 主程序 | C#、WPF、.NET Framework 4.8 | Electron 45、React、独立 Node SEA Hook helper |
| 数据接入 | Codex 本地日志观察 | Codex 日志和额度 app-server；Claude、DSH、Kimi 接入代码 |
| 界面范围 | 最小灵动岛及基础卡片 | 灵动岛、额度胶囊、详情、设置、用量图表、托盘、通知 |
| 特效 | 独立 OpenGL 开发台，用户已确认可用 | CSS 渐变、圆点背景和关键帧动画 |
| 开发交付 | 源码与测试保留在本地 | 本次只有运行分包，缺完整开发源码包 |

两套程序不能直接通过复制 EXE 或添加 C# 文件合并。若采用 Electron 主线，应迁移已经认可的 shader 和状态逻辑到前端 GPU 渲染层，验证 WebGL 兼容性、透明合成、DPI 和多卡片调度，并保留原开发台作为对照。

## 已有功能及边界

| 模块 | 代码中的实现 | 当前边界 |
| --- | --- | --- |
| Windows 窗口 | 无边框透明岛、胶囊、设置窗、置顶、托盘、单实例、屏幕选择 | 多屏、焦点、DPI 和视觉交互待验收 |
| 设置 | 中英文、主题、材质、尺寸、隐私、减少动态效果、通知、代理、开机启动选项 | 本次没有开启开机启动或修改真实客户端配置 |
| Codex 任务 | 有界增量读取、会话分类、子任务、计划进度、公开输出、Token、陈旧状态降级 | 真实版本兼容性待端到端验证 |
| Codex 额度 | 独立 app-server 读取账户、限额和可用统计字段 | 不具备 Desktop 审批、提问或中断权限；代码明确拒绝代答 |
| Claude | Hook 配置安装清理与备份、状态、公开 transcript、用量、持有响应通道的审批和提问回传 | Windows 真实联动未验证；新鲜度及跨轮内容需修正 |
| DSH 与 Kimi | 原生配置或插件接入、事件接收 | 无响应通道的请求保持只读；Kimi Stop 标记为完成未验证 |
| 任务进度 | 计划计算进度，非完成最高 95%，可信完成显示 100%，未知进度单独处理 | 不靠计时推断完成 |
| 额度重置 | 明确标注的演示页面 | 没有真实额度重置功能 |
| 更新与发行 | 检查 Windows 仓库发布页、完整 x64 运行目录 | 无安装器、自动安装更新或签名 |

代码入口为 `app-review/src/main.cjs`，桥接为 `src/preload.cjs`。Codex 模块为 `src/core/codex*.cjs`；其他客户端主要在 `integrations.cjs`、`hook.cjs`、`claude-data.cjs`、`dsh-plugin.mjs`；Windows 辅助逻辑在 `platform.cjs`。

Renderer 开启 context isolation、禁用 Node integration 并启用 sandbox；IPC 校验所属窗口、主 frame 和本地文档。Hook 服务监听回环地址并校验令牌。这些是已存在的隔离措施，不代表完整安全审计。

## 优先处理的问题

### 补齐可复现源码

ASAR 有后端源码，但前端只有压缩后的 `dist/renderer/app.js` 和 `app.css`。当前交付缺少 React 开发源文件、源码映射、开发用 package.json scripts、package-lock、tests、构建脚本和 CI 工作流；交接提到的独立源码 ZIP、`source-files.json`、`SHA256SUMS.txt` 也不在本次目录里。

随包声明的 92 项 Linux 测试和构建结果目前只能作为上游交接记录，无法用这份运行交付复现。应先取得与运行包同一快照的完整开发目录及构建资料。

### 接入已经认可的核心特效

球体使用 `radial-gradient`、内圈边框、模糊和 `orb-flow`；量子噪点使用两层周期圆点背景和 `quantum-shimmer` 的 `steps()` 动画。组件创建的是 `span/i/b`，没有对应的 WebGL shader 渲染代码。证据位于 `app-review/dist/renderer/app.css` 和 `app.js`。

因此这套 CSS 效果不能视为上次已通过用户评估的 Ripple Glow 与量子噪点。应移植开发台的固定轮廓、折射色带、连续相位、粒子身份和状态运动。CSS 当前完成淡出为 1.8 秒，与开发台分阶段收尾也不同。

### 接通压缩状态显示

`codex.cjs:104` 与 `codex-rollout.cjs:284` 设置 `task.compacting`。后端快照保留该字段，但前端任务卡及球体只取 `task.status`，打包前端没有读取 compacting 属性。Claude PreCompact 则映射为 working 并设置工具文案。

前端虽有“压缩上下文”翻译，但这条状态路径没有接通，也没有专属压缩态球体配色。需统一压缩、等待、错误、断开与终态的展示优先级，同时驱动文字、球体和进度特效。这是静态代码发现，尚未通过真实压缩事件复现。

### 修正 Claude 旧状态与跨轮内容

`integrations.cjs` 在收到事件时将连接置为 connected，快照和刷新中未看到与 Codex 相同的活动过期降级。客户端退出或事件流中断后，卡片可能持续显示旧活动状态。

新轮次会立即读取 transcript 尾部；`claude-data.cjs:105` 起的提取逻辑按文件最后一条用户消息划分，没有严格关联刚收到的新轮次。文件尚未更新时，旧文本、Token，甚至旧中断标记可能影响新任务。交接文档已承认旧活动状态和旧文本问题，应补 freshness、轮次边界、事件时序和回归用例。

### 完成打包收尾

ASAR 额外包含约 37.3 MB 的 `dist/helper-build/node-v24.19.0-win-x64.zip`，以及 blob、构建配置等中间产物。正常启动使用 `resources/helper/quotaview-hook.exe`；取得构建脚本后可以收紧打包白名单，保留运行 helper、许可证及必要清单。

EXE 的 Windows 属性仍显示 Electron 45.0.0，符合交接中跳过资源编辑的说明。正式发行还需要产品图标与版本资源、安装卸载流程、签名决策和更新发布流程。

## 本次验证结果

| 验证 | 结果 |
| --- | --- |
| 12 个压缩分包、12 个原始片段的哈希及片段长度 | 全部与清单一致 |
| 合并运行包哈希及长度 | 一致 |
| Helper EXE 哈希 | 与 helper-manifest 一致 |
| Windows x64 隔离启动 | 退出码 0，报告为 `ok: true` |
| 页面加载及 React 挂载 | island、capsule、settings 全部通过 |
| 预加载与 IPC 桥接 | 通过，contextIsolation 为 true，nodeIntegration 为 false |
| 92 项上游测试 | 交接记录声明通过，本次缺测试源码，未复跑 |
| Helper 实际运行、真实客户端、安装卸载、视觉和多屏交互 | 本次未验证 |

本次使用包内 `--smoke-test` 隔离路径，建立临时用户数据目录，在启动实际数据服务之前退出，没有开启 Hooks 或真实账户联动。报告的 rendererErrors 为空，但 stderr 有 Windows 网络变化检测警告和 Electron console-message 参数弃用警告；此次未阻止启动，应在兼容性处理中跟进。

## 建议接手顺序

1. 补齐完整源码，将版本和源文件清单与本运行包对应起来。
2. 在 Windows 复现构建及测试，验证 helper，再优先验收默认只读 Codex 路径。其他客户端用独立测试配置逐项验证。
3. 修正压缩状态、Claude 新鲜度及轮次边界，统一展示状态模型。
4. 将已认可的 AI 球和量子噪点接入 Electron GPU 渲染层，保留特效调试入口。
5. 完成灵动岛人工验收，再精简资源、补产品元数据和安装包。

本次没有合并业务代码或修改 dot 的打包源码。现有 WPF 程序和已认可的特效开发台继续保留。后续主线选择以完整源码可复现及 Windows 实际验收为依据。
