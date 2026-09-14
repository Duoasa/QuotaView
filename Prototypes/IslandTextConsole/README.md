# Island Text Console

长期保留的独立内容验收控制台，每次重建复用当前工作区的生产灵动岛视图。
整个预览为 **仅用于调试 / DEBUG** 模拟数据；不启动真实 AppDelegate、账户查询、
活动桥、Hook、更新器或 Widget，不写生产偏好或共享快照。

双击本目录的 **Open Console.command** 打开已保存的版本；首次无归档时自动构建。
需要 macOS 14+，重新构建还需 Xcode / Swift 和 Python 3。

生产代码修改后，从项目根目录执行；新版启动成功后会自动关闭旧开发台：

```sh
zsh 'Prototypes/IslandTextConsole/Open Console.command' --rebuild
```

只检查保存包、不打开窗口：

```sh
zsh 'Prototypes/IslandTextConsole/Open Console.command' --verify-only
```

源码和入口已随 0.5.0 Build 3 合并 GitHub main；`dist/IslandTextConsole.zip`、`SHA256SUMS` 和来源哈希
保存在本项目的忽略目录。归档是本机架构、ad-hoc 签名，其他架构应在当地重建。
启动器校验归档后解包运行，临时目录被清理也不会丢失入口或保存包。
`.build` 与 `dist` 均可由源码重建，不提交二进制。不要把固定 `/tmp` 路径用作长期入口。
普通打开不会自动重建；每次打开归档中的新实例，确认启动成功后自动退出旧开发台。
旧实例中的手动输入随退出结束；新版本未成功启动时保留旧实例。此操作只针对独立开发台。
标题中的版本与 Build 来自构建时的生产 Info.plist。

- 默认完成态 **27%**；只显示一个灵动岛，用「展开 / 缩略」手动切换，保持生产字号与尺寸。
- 主应用与开发台共用不透明纯黑岛体，完成特效淡出后仍保持黑色；展开 / 缩略一致，保留完成描边与外侧辉光。
- 预览独立显示在控制窗口所在屏幕的系统状态栏下方；控制窗口保留操作与模拟数据。
  最终位置沿用生产灵动岛：按屏幕可用区域居中，可见表面顶部距状态栏下缘 16 pt。
  「呼出」从状态栏后的细小胶囊向下长大，0.82 秒内通过非线性弹簧响应回稳到最大展开态；
  高度先拉伸、宽度随后回弹，形成果冻形变。隐藏时禁用尺寸选择。
  「隐藏」先用 0.28 秒从当前展开态缩到缩略态，再用 0.28 秒收起淡出；
  已在缩略态时直接执行后半段。隐藏途中呼出会取消收起序列，从当前位置继续弹出。
  手动大小过渡以顶部居中为锚点；缩略 → 展开复用呼出的 0.82 秒非线性弹簧与宽高错峰果冻回弹，
  保持当前可见位置与透明度。展开 → 缩略为 0.28 秒，短暂加速后逐渐减速，起止速度为零，
  宽高单调接近目标，不回弹、不越界。
  主要展开时逻辑几何首次到位后保持稳定，末端通过共同容器的 frame / bounds 变换，让外壳、
  文字、图标及特效一起回弹；文字参与视觉缩放，不反复排版或截断。
  旧文字起步用 0.08 秒淡出，布局在不可见时切换；呼出 / 展开延迟 0.12 秒后用 0.14 秒淡入，
  让内容参与可见回弹。缩略内容在外壳到位后淡入，隐藏不再补显文字。快速切换从当前画面接续。
  该套动效已按用户要求接入 0.5.0 开发版，开发台与生产共用 `CodexActivityIslandMotion.swift`。
- 九种状态、中英文、0–100% 额度滑块与步进器、25/26/27/28/99/100 等快捷值。
- 可编辑任务标题、操作、状态、Token 数值和文字，检查长内容、混排与 Emoji。
- 额度缺失、Token 缺失预设；无有效 Token 时不伪造成功回执，遵守生产呈现规则。
- 四种特效直接使用当前工作区 LONG-020 稳定性修复代码；确认提醒、暂停特效、
  Reduce Motion 和悬停透明模拟保留；背景直接取真实桌面。暂停特效不阻止尺寸与进出动画；
  Reduce Motion 使尺寸与进出立即到位。完全隐藏、窗口不可见或关闭时停止动画工作。
- 20 秒手动启动的完整状态演示；停止 / Escape 或任意手动输入可中止。
  演示最终停在已完成 / 100% 额度，完成后不会自行关闭预览。
- 可将控制窗口拖到另一块屏幕，顶部预览随屏幕移动；手动控制会中止 Demo。
  这是独立开发台，不运行真实任务的完成 / 缩小 / 隐藏计时器。

`prepare.py` 将生产 Sources 复制到被忽略的 `.build/Workspace`，仅更换 @main，
并使 `ActivityIslandContentView` 在这个隔离副本中可供宿主调用。隔离副本另将 shader 资源查找指向标准 App Resources。没有复制旧版
渲染器或添加生产调试入口。`.build/source-manifest.json` 记录全部生产源码与开发台哈希、
渲染器可见性替换及宿主适配；四种特效所在的 `CodexActivityStateSmoke.swift` 在构建前校验逐字节一致。
独立 Bundle ID `com.quotaview.island-text-console`，无 App Group 权限
或 Widget 扩展，开发产物只作本机 ad-hoc 签名。

2026-09-11：用户确认当前灵动岛内容手动检查通过，并要求长期保留本控制台。
这项验收不代表所有辅助功能组合或真实完成/隐藏计时已验证，也不构成发布授权。

2026-09-13：增加单实例尺寸切换与手动呼出 / 隐藏；构建、归档签名、来源哈希和过渡边界检查通过，
新版已启动，该轮动画观感等待用户验收。
后续按用户新要求加入缩略 → 展开的果冻回弹，反向保持无回弹，并修复回弹牵动文字布局的问题。
前轮 236 项完整回归无失败（2 项跳过），10 项动画回归与实际 AppKit 文字布局检查通过。
用户随后指出独立文字过渡存在错层感，本轮改为错峰淡出 / 淡入；按要求仅构建与冒烟，主要由用户手动检查。
最新方案经用户同意：稳定文字排版，外壳与内容共同视觉回弹，淡入仅作辅助；继续仅构建与冒烟。
开发台动效随后已构建进 0.5.0 Build 2 / internal 28 并启动真实应用，开发台已关闭以便检查实际配合。
2026-09-13 用户已确认真实 Build 2 的正常动效并要求冻结。随后代码审计修复呼出途中隐藏时
尺寸反向增大、回弹悬停区域偏差；正常五条路径与确认版逐帧一致。完整回归 240 项（239 通过、
1 跳过、0 失败），实际 AppKit 3 项及 Universal 通过，详见[审计记录](../../docs/design/quotaview-island-motion-0.5.0.md#2026-09-13-动效冻结与代码审计)。
2026-09-13 当前保存包与主应用均为 **0.5.0 Build 3 / internal 29**，已同步重建并启动；
包含两处审计修复和纯黑底色，旧实例已退出。AppKit 4 项、归档签名及 57 项生产来源一致性核验通过。
证据为 `dist/verification/0.5.0-build3/`（项目根目录）；版本定位统一见 [Handoff](../../HANDOFF.md)。
此前 Build 2 开发台启动记录保留在 `dist/verification/console-audit-fixes-launch/`。
过渡边界检查：编译生产 `Sources/QuotaView/CodexActivityIslandMotion.swift`、本目录的
`ConsoleMotion.swift` 与 `tests/main.swift` 后运行生成程序；生产状态刷新回归见 `ActivityIslandMotionTests`。
实际渲染器检查由 `prepare.py` 将 `tests/RendererTextLayoutTests.swift` 放入隔离测试目标，
重建后执行 `swift test --package-path Prototypes/IslandTextConsole/.build/Workspace --scratch-path Prototypes/IslandTextConsole/.build/SwiftBuild --filter RendererTextLayoutTests`。
该检查不打开窗口，测量工作态与完成回执的文字排版尺寸固定、屏幕几何与共同容器变换一致。
