# 灵动岛内容检查控制台

Spec ID: `QV-PROTOTYPE-ISLAND-TEXT-018`
状态：Accepted / Verifying（本地交付，未发布）。2026-09-11 用户要求提供并长期保留控制台，随后确认“目前手动检查通过”。

复用现有量子噪点控制台的隔离构建方式，直接使用当前修复后的生产视图和渲染器。
新增原型位于 `Prototypes/IslandTextConsole`，不修改旧的 QuantumNoiseConsole。

- R1：展开态与紧凑态并列，使用生产尺寸、字体、布局；默认完成额度 27%。
- R2：九种状态、中英文、0–100% 额度、任务/操作/状态/Token 文案可手动调节；
  提供额度缺失、Token 缺失、长文字/Emoji 与数字边界预设。
- R3：四种已有特效、暂停、减少动态效果、确认提醒、明暗背景、悬停透明模拟。
- R4：手动启动 20 秒完整状态演示；停止、Escape、手动改值和关窗均取消演示。
- R5：模拟数据有可见 DEBUG 标识及辅助功能说明；独立 Bundle ID、不启动真实
  AppDelegate 或服务，不写生产偏好、账户、Widget 共享数据或注册生产插件。
- R6：只在隔离副本暴露已有私有内容视图，不改生产渲染，不嵌入生产 QA 入口。

构建和使用说明见 [控制台 README](../../Prototypes/IslandTextConsole/README.md)。
当前灵动岛内容手动检查已由用户确认通过；不推导完整辅助功能矩阵或真实生命周期计时均通过。
本轮没有发布授权，Stable / appcast 保持 0.4.6。

验证：独立 arm64 Debug 控制台构建、ad-hoc 严格签名和启动通过；无 stderr，
Bundle ID 为 `com.quotaview.island-text-console`，不包含 Widget 或 App Group。
已打开供用户手动验收。生产视图哈希由 `.build/source-manifest.json` 校验，
隔离副本仅将私有视图改为模块可见，真实绘制修复未被替换。

长期维护：源码、启动器、构建脚本与说明纳入本地版本管理。`Open Console.command`
校验项目内保存的 ZIP 后解包启动；`--rebuild` 从当前生产源码重建，`--verify-only`
只验证保存包。版本和 Build 从生产 Info.plist 读取；不依赖历史临时目录，
生成缓存与归档保持 Git 忽略。后续维护约束见目录内 AGENTS.md。

长期保存验证：从项目入口 `--verify-only` 校验归档 SHA-256、解包与严格签名通过；
版本、生产渲染文件哈希、字体和 shader 资源以及无 Widget / App Group 边界均已检查。
