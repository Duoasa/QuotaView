# Island Text Console

长期保留的独立内容验收控制台，每次重建复用当前工作区的生产灵动岛视图。
整个预览为 **仅用于调试 / DEBUG** 模拟数据；不启动真实 AppDelegate、账户查询、
活动桥、Hook、更新器或 Widget，不写生产偏好或共享快照。

双击本目录的 **Open Console.command** 打开已保存的版本；首次无归档时自动构建。
需要 macOS 14+，重新构建还需 Xcode / Swift 和 Python 3。

生产代码修改后，先正常关闭旧控制台，再从项目根目录执行：

```sh
zsh 'Prototypes/IslandTextConsole/Open Console.command' --rebuild
```

只检查保存包、不打开窗口：

```sh
zsh 'Prototypes/IslandTextConsole/Open Console.command' --verify-only
```

源码和入口随 Build 3 纳入 GitHub 版本管理；`dist/IslandTextConsole.zip`、`SHA256SUMS` 和来源哈希
保存在本项目的忽略目录。归档是本机架构、ad-hoc 签名，其他架构应在当地重建。
启动器校验归档后解包运行，临时目录被清理也不会丢失入口或保存包。
`.build` 与 `dist` 均可由源码重建，不提交二进制。不要把固定 `/tmp` 路径用作长期入口。
普通打开不会自动重建，也不会关闭已有窗口；标题中的版本与 Build 来自构建时的生产 Info.plist。

- 默认完成态 **27%**；展开 / 缩略同时显示，保持生产字号与尺寸。
- 九种状态、中英文、0–100% 额度滑块与步进器、25/26/27/28/99/100 等快捷值。
- 可编辑任务标题、操作、状态、Token 数值和文字，检查长内容、混排与 Emoji。
- 额度缺失、Token 缺失预设；无有效 Token 时不伪造成功回执，遵守生产呈现规则。
- 四种特效、确认提醒、暂停、Reduce Motion、亮暗预览底和悬停透明模拟。
- 20 秒手动启动的完整状态演示；停止 / Escape 或任意手动输入可中止。
  演示最终停在已完成 / 100% 额度，完成后不会自行关闭预览。
- 可将窗口拖到另一块屏幕验证显示倍率；这是手动内容控制台，不冒充真实
  完成 / 缩小 / 隐藏计时验证。

`prepare.py` 将生产 Sources 复制到被忽略的 `.build/Workspace`，仅更换 @main，
并使 `ActivityIslandContentView` 在这个隔离副本中可供宿主调用。隔离副本另将 shader 资源查找指向标准 App Resources。没有复制旧版
渲染器或添加生产调试入口。`.build/source-manifest.json` 记录生产文件哈希和唯一
可见性替换；独立 Bundle ID `com.quotaview.island-text-console`，无 App Group 权限
或 Widget 扩展，开发产物只作本机 ad-hoc 签名。

2026-09-11：用户确认当前灵动岛内容手动检查通过，并要求长期保留本控制台。
这项验收不代表所有辅助功能组合或真实完成/隐藏计时已验证，也不构成发布授权。
