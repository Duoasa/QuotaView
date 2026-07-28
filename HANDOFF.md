# QuotaView 项目 Handoff

更新日期：2026-07-29
工作区：`/Users/sukduoasa/Documents/widget`
当前分支：`agent/fix-release-runtime-build-4`
当前基线：`origin/main` 的 `e8e8dad6e1accca431722289cd28c0f1df10ebe0`
分支上游：`origin/main`
远程：`https://github.com/Duoasa/QuotaView.git`

## 1. 当前结论

QuotaView 0.2.0 Build 3 已完成 UI 细节迭代并发布，但从 GitHub 下载后会在
界面初始化前崩溃。崩溃报告确认：打包脚本对无 Team ID 的 ad-hoc App 和
`QuotaViewCore.framework` 强制启用 Hardened Runtime，导致 macOS Library
Validation 拒绝加载内嵌 Framework。Build 3 必须在 Build 4 验证发布后从
GitHub 删除。

当前正在准备 **0.2.0 Build 4 运行时热修复**，候选包含：

- 保留 Build 3 的全部 UI1/UI2 细节、状态栏图标与真实重置额度数据改动；
- 仅在使用 Developer ID Application 或 Apple Development 身份时启用
  Hardened Runtime；
- 回退到 ad-hoc 签名时关闭 Hardened Runtime，保证内嵌
  `QuotaViewCore.framework` 可以被 `dyld` 加载；
- 在打包脚本中断言可信签名必须包含 runtime 标志、ad-hoc 签名不得包含；
- 将 Build Number 更新为 `4`，生成独立资产
  `QuotaView-v0.2.0-build.4.zip`；
- 更新中英文 README 和贡献规范，不再把 ad-hoc 回退描述为 Hardened
  Runtime 构建。

28 项测试、`git diff --check`、Universal Release 打包、ZIP 解包验签和
真实启动烟雾测试均已通过。Build 4 从 ZIP 全新解压后的进程持续存活
3 秒并由测试脚本正常终止；没有出现 Build 3 的 `fatalDyldError`。
当前候选仍有以下发布门禁：

- Marketing Version 为 `0.2.0`，Build Number 已更新为 `4`；
- 尚未形成最终干净 commit；
- 尚未完成 PR 合并、tag 和 GitHub Release。
- Build 4 发布并回下载验证后，尚需删除 Build 3 Release 与 tag。

产品所有者已明确授权发布本次 GitHub 热更新。完整视觉验收矩阵没有单独
记录，因此不得把矩阵状态写成“已通过”；发布授权本身不等同于逐项视觉
验收结论。

下一位接手者的首要任务：

1. 精确暂存 Build 4 修复文件，排除用户未跟踪参考文件；
2. 推送发布分支并通过 PR 合并到 `main`；
3. 使用唯一 tag `v0.2.0-build.4`，不得移动或覆盖现有 `v0.2.0`；
4. 发布并回下载验证 Build 4 ZIP；
5. 最后删除损坏的 Build 3 Release 和 `v0.2.0-build.3` tag。

## 2. Build 4 正式 Release 记录

- Release：`v0.2.0-build.4`
- Release 名称：
  `QuotaView 0.2.0 (Build 4) — Launch Reliability Hotfix`
- 状态：正式 Release，非 Draft，非 Pre-release
- 发布时间：以 GitHub Release 页面为准
- Release URL：
  `https://github.com/Duoasa/QuotaView/releases/tag/v0.2.0-build.4`
- Tag commit：以 `v0.2.0-build.4` 为准
- Marketing Version：`0.2.0`
- Build Number：`4`
- Bundle Identifier：`com.quotaview.menubar`
- 最低系统版本：macOS 14
- 架构：Universal `arm64 + x86_64`
- Release 资产：`QuotaView-v0.2.0-build.4.zip`
- 资产大小：`8,032,585 B`
- SHA-256：
  `ab59fe031f6bf6693115968c5a0dc3ca4ea7051e5fefdab2b5cb293f8361aca0`
- 签名：ad-hoc，不启用 Hardened Runtime
- 公证：未完成

本地 `dist/QuotaView-v0.2.0-build.4.zip` 已完成 ZIP 解包、deep + strict
验签和真实启动烟雾测试。App 与 Framework 的签名标志均为
`flags=0x2(adhoc)`，不包含 `runtime`。

Release Notes 必须明确说明未使用 Developer ID、未公证以及可能出现的
Gatekeeper 首次启动限制。不得把 Build 4 描述成 Developer ID 公证发行版。

## 3. 0.2.0 Build 4 发布改动

### Figma 来源

实现以 QuotaView Figma 文件 Page UI 中的 UI1/UI2 为准，已读取：

- 深色概览：`1:712`
- 浅色概览：`25:1471`
- 深色重置详情：`10:181`
- 浅色重置详情：`25:1524`

本轮没有调用 CodexBar 参考文档；这些都是 QuotaView 既有模块的 UI
细节迭代。

### 组件样式与交互

- 24 pt 功能按钮继续使用 Figma SVG，保留圆形按钮 Hover `1.04`、
  Pressed `0.94` 和 Disabled `55%`；
- 浅色返回、退出、刷新、打开 Codex 和设置 SVG 已同步 UI2 最新默认态；
- 重置入口卡片保持 `234 × 51 pt`、`12 pt` 连续圆角，更新为 UI1/UI2
  对应的半透明填充、边界、背景模糊、内阴影和圆角外投影；
- 重置按钮保持 `234 × 32 pt`，圆角更新为 `8 pt`，使用红色语义填充、
  边界、内阴影和圆角外投影；
- 重置按钮 Hover 使用红色语义遮色，Pressed 使用外观对应的深色遮色，
  Reduce Motion 下不缩放；
- 订阅类型 Tag 使用 `80%` 白色填充、`6 pt` 连续圆角，并按深浅外观
  使用不同描边；
- Codex 数据连接状态标签保持 `18 pt` 高、`6 pt` 连续圆角，使用状态色
  `20%`、`3.75 pt` 受边界约束的背景模糊、黑色内阴影和 `0.5 pt`
  描边；
- 浅色可用文字色为 `#008B22`，深色继续为 `#00FF3F`；
- 状态标签仍只表示最新 Codex 数据获取是否有效，不表示额度充足、受限或
  耗尽。

连接状态标签不得恢复为 `12 pt` 圆角。对 `18 pt` 高度使用达到或超过
半高的圆角会被 SwiftUI 钳制为近似胶囊，从而再次出现橄榄球形。

### 状态栏图标

实际差异文件：

```text
Resources/Assets.xcassets/QuotaViewMenuIcon.imageset/QuotaView.svg
```

用户提供的源文件：

```text
/Users/sukduoasa/Desktop/QuotaView Source/bar icon.svg
```

仓库 SVG 已与源文件逐字节比对一致。新 SVG 画布为 `182 × 200`，
`viewBox` 为 `0 0 182 200`，继续使用单色 Template Image 和保留矢量
表示。

状态栏代码未改变：

- 可见图标尺寸：`15 × 16 pt`；
- `NSImage` 逻辑画布：`20 × 16 pt`；
- 图标左对齐，右侧保留 `5 pt` 透明区；
- 使用原生状态栏图文间距和系统自动着色。

### 真实额度数据恢复

临时 3 次额度注入已经完整移除。当前数据链路为：

```text
CodexProviderAdapter
→ CurrentCodexPresentation.availableResetCredits
→ CodexStatusStore.hasAvailableResetCredit
→ 重置入口 / 票据数量 / 按钮状态 / 重置后剩余次数
```

已确认生产源码和测试中不存在 `DEBUG-ONLY-MOCK`、`DEBUG MOCK`、
“仅用于调试”、`debugResetCreditOverride` 或
`displayAvailableResetCredits`。

这里的“真实数据”只指读取官方本机 `codex app-server` 返回的实时额度
数据。额度重置写操作仍保持 Demo，不调用
`account/rateLimitResetCredit/consume`。

### Build 3 启动失败与 Build 4 修复

Build 3 从 GitHub 下载后可以通过 Gatekeeper 手动授权，但启动时会在状态栏
项目建立之前退出。系统崩溃报告为 `DYLD / Library missing`，实际原因不是
Framework 文件缺失，而是：

```text
QuotaView.app
  ad-hoc + Hardened Runtime，无 Team ID
QuotaViewCore.framework
  ad-hoc + Hardened Runtime，无 Team ID
→ Library Validation 拒绝加载内嵌 Framework
```

`codesign --verify --deep --strict` 只能确认签名与 Bundle 完整性，不能证明
`dyld` 能在 Hardened Runtime 下加载动态 Framework，因此 Build 3 的发布
前检查出现了假阴性。

Build 4 将签名策略改为：

- Developer ID Application / Apple Development：保留 Hardened Runtime
  与时间戳；
- ad-hoc 回退：不启用 Hardened Runtime、不使用时间戳；
- 打包时解析最终 App 签名标志，发现签名模式与 runtime 标志不一致立即
  失败。

从 Build 4 ZIP 全新解压的 App 已在沙箱外直接启动，进程持续存活 3 秒，
随后由烟雾测试脚本正常终止。该测试没有产生 `fatalDyldError`。

### 已完成验证

- `swift test`：28 项通过，0 失败；
- Universal Release 构建与 ad-hoc 打包：成功；
- App 架构：`x86_64 arm64`；
- Framework 架构：`x86_64 arm64`；
- 构建内版本：`0.2.0 (4)`；
- `git diff --check`：通过；
- 更新的 SVG 均通过 XML 校验；
- `Assets.car`、`AppIcon.icns` 和三款 Asta Sans 字体均存在；
- 更新的 Figma SVG 保留矢量表示；
- 未发现真实 reset consume 调用；
- 未新增截图、自动展开、自动点击或 UI QA 入口。
- ZIP 解包后 App 与 Framework 均为 `flags=0x2(adhoc)`，不含 runtime；
- ZIP 解包后 `codesign --verify --deep --strict` 通过；
- ZIP 解包后的 App 真实启动并持续存活 3 秒，没有 DYLD 加载失败。

最终发布候选：

```text
dist/QuotaView-v0.2.0-build.4.zip
```

- 大小：`8,032,585 B`
- SHA-256：
  `ab59fe031f6bf6693115968c5a0dc3ca4ea7051e5fefdab2b5cb293f8361aca0`
- 签名：ad-hoc，不启用 Hardened Runtime
- 公证：未执行
- ZIP 解包后 deep + strict 验签和启动烟雾测试：通过

旧 `dist/QuotaView-v0.2.0.zip` 仍为 `8,021,537 B`，SHA-256 仍为
`f14936120a1b884a95ca4e5150b70ababd5e40c1566ac78c0f26e716cb746bb0`，
未被覆盖。

视觉与交互验收状态：**未记录完整矩阵；产品所有者已授权发布热更新**。

## 4. Xcode 误报记录

替换图标后，Xcode 编辑器曾在
`Sources/QuotaViewCore/CodexModels.swift` 中显示：

```text
Cannot find type 'SanitizedErrorSummary' in scope
```

这不是当前编译错误。

已核实：

- `SanitizedErrorSummary` 正确定义于
  `Sources/QuotaViewCore/DomainModels.swift`；
- 定义为 `public struct`；
- `DomainModels.swift` 与 `CodexModels.swift` 都属于
  `QuotaViewCore` target；
- Xcode 项目的 Sources Build Phase 同时包含两个文件；
- 完整 Debug Clean Build 最终为 `BUILD SUCCEEDED`；
- Release Build 同样成功。

该红线属于 Xcode/SourceKit 未刷新的编辑器索引诊断。不要通过复制类型、
移动类型或在 `CodexModels.swift` 内新增重复定义来规避。

如果再次出现：

1. 确保打开的是 `QuotaView.xcodeproj`，不是单独打开 Swift 文件；
2. 执行 `Product → Clean Build Folder`（`Shift + Command + K`）；
3. 关闭并重新打开 Xcode，等待索引完成；
4. 必要时从 Xcode Settings 的 Locations 页面只清理 QuotaView 的
   Derived Data；
5. 以 Report Navigator（`Command + 9`）中的真实 Build 结果为准。

此前控制台出现的：

```text
com.apple.linkd.autoShortcut
NSXPCDecoder validateAllowedClass
decode: bad range
```

属于应用启动后的 macOS 系统运行时日志，不是 Swift 编译错误，也不是
新 SVG 的 Asset Catalog 错误。

## 5. 0.2.0 架构基线

0.2.0 已完成：

- 通用 Domain Model；
- Codex Provider Adapter；
- 静态 Provider Registry；
- Data Demand Planner；
- generation/revision/account-aware Refresh Coordinator；
- 当前 UI 专用 `CurrentCodexPresentation`；
- App Server 启动/请求 timeout；
- stdout 单行 1 MB 上限和有界诊断；
- 可选 Usage 失败隔离；
- Token 区域关闭后的请求裁剪；
- Demo/Unavailable 写操作边界；
- History、Chart、Display Preferences、Notification 契约；
- Foundation-only Widget Contract；
- Apple App Group、Widget Bundle ID、Development Team 空配置预留。

独立的 Future Contracts 和 Widget Contract 当前不会链接进生产 App，
不会创建后台任务或 `.appex`。

详细文档：

- `docs/design/quotaview-core-architecture-evolution.md`
- `docs/design/quotaview-core-refactor-0.2.0-report.md`
- `docs/design/quotaview-widgetkit-solution.md`

## 6. 产品与安全边界

- 默认只读；
- 只通过本机官方 `codex app-server` 获取数据；
- 不抓取网页；
- 不读取、复制或保存 `~/.codex` 登录凭据；
- 不输出 Token 或认证材料；
- 当前额度重置只允许本地 Demo；
- 生产代码不得发送
  `account/rateLimitResetCredit/consume`；
- 非 Demo 操作由当前 Executor 拒绝；
- Provider 刷新流程不能隐式触发账户操作；
- Apple Developer 配置仍只保留空占位，不猜测 Team ID 或 App Group。

未来允许的产品定位：

> 默认只读；用户对具体官方账户操作单独授权后才允许执行。

真实写操作接入时必须区分手动一次授权和自动规则授权，并补齐幂等、过期、
审计、失败恢复和安全降级。

## 7. 当前设置与 UI

首次安装默认值：

- 外观：跟随系统；
- 玻璃质感：清透；
- 语言：跟随系统语言。

有效的既有设置不会被默认值覆盖。未知的旧玻璃枚举值迁移为清透。

当前 UI 继续遵循：

- 主面板完整尺寸 `258 × 431 pt`；
- 隐藏设置项后动态缩短；
- 重置详情固定 `258 × 473 pt`；
- 设置窗口默认内容尺寸 `872 × 637 pt`；
- 主面板只允许一层实时系统玻璃；
- 主面板与重置页使用 Asta Sans；
- 设置窗口使用系统字体、语义色和原生控件；
- 额度重置继续为 Demo。

本轮只调整第 3 节列出的组件表面、图标和交互令牌，没有改变面板尺寸、
业务字段含义、设置窗口结构、数据请求范围或重置写操作边界。连接状态
标签的最终生产圆角为 `6 pt`，不是 Figma 初次读取到的 `12 pt`。

## 8. 当前代码结构

```text
Sources/
├── QuotaView/
│   ├── QuotaViewApp.swift
│   ├── AppPreferences.swift
│   ├── CodexStatusStore.swift
│   ├── CurrentCodexPresentation.swift
│   ├── MenuBarPanelController.swift
│   ├── MenuBarView.swift
│   ├── QuotaViewFigmaMenu.swift
│   ├── QuotaViewFigmaResetMenu.swift
│   ├── SettingsView.swift
│   └── CodexTheme.swift
├── QuotaViewCore/
│   ├── DomainModels.swift
│   ├── ProviderArchitecture.swift
│   ├── RefreshCoordinator.swift
│   ├── AccountOperations.swift
│   ├── CodexProviderAdapter.swift
│   ├── CodexAppServerClient.swift
│   ├── CodexExecutableLocator.swift
│   └── CodexModels.swift
├── QuotaViewFutureContracts/
│   └── FutureCapabilityContracts.swift
├── QuotaViewWidgetContract/
│   └── WidgetSnapshot.swift
└── QuotaViewProbe/
    └── main.swift

Tests/QuotaViewCoreTests/
├── AppBehaviorTests.swift
├── ArchitectureTests.swift
├── CodexAppServerClientTests.swift
├── CodexModelsTests.swift
└── WidgetContractTests.swift
```

## 9. 当前 Git 工作区

检查时状态：

```text
## agent/fix-release-runtime-build-4...origin/main
 M AGENTS.md
 M CONTRIBUTING.md
 M Configs/App.xcconfig
 M HANDOFF.md
 M README.md
 M README.zh-CN.md
 M Support/Info.plist
 M design-qa.md
 M scripts/build-app.sh
?? docs/reference/
?? quotaview-blurred-gradient-background-2k.png
?? subtract-frosted-glass-icon-transparent.png
?? subtract-frosted-glass-icon.png
```

已跟踪且属于 0.2.0 Build 4 发布候选的修改：

- `AGENTS.md`
- `CONTRIBUTING.md`
- `Configs/App.xcconfig`
- `HANDOFF.md`
- `README.md`
- `README.zh-CN.md`
- `Support/Info.plist`
- `design-qa.md`
- `scripts/build-app.sh`

未跟踪且不得擅自加入、删除或清理：

- `docs/reference/`
- `quotaview-blurred-gradient-background-2k.png`
- `subtract-frosted-glass-icon-transparent.png`
- `subtract-frosted-glass-icon.png`

这些未跟踪内容不属于 0.2.0 Build 4 发布候选。不要执行 `git clean`、
reset、checkout 或批量删除，也不要在宽范围 `git add .` 中误加入。

`Sources/QuotaView/QuotaViewApp.swift`、`CodexStatusStore.swift`、
`MenuBarView.swift` 和测试文件已恢复为 HEAD 状态，说明临时虚拟额度实现
没有留在候选差异中。

## 10. 建议后续动作

### 视觉验收

至少检查：

- 外观：浅色 / 深色 / 跟随系统；
- 材质：磨砂 / 清透；
- 语言：简体中文 / English / 跟随系统；
- 数据：可用 / 不可用 / 刷新中 / 真实零重置次数；
- 组件：五个浅色功能按钮、订阅 Tag、连接状态标签、重置入口和重置按钮；
- 交互：Default / Hover / Pressed / Disabled / Reduce Motion；
- 状态栏：仅图标、图标加文字、选中态及不同屏幕缩放；
- 键盘与辅助功能：焦点、Escape、VoiceOver、Increase Contrast。

不得在没有产品所有者结论时把视觉结果记录为“已通过”。

### 0.2.0 Build 4 发布

`v0.2.0` 已对应 0.2.0 Build 1 正式发布。Marketing Version 保持
`0.2.0` 时，Build 4 必须使用新的 tag 和资产名，不得覆盖原 tag、原 ZIP
或原 Release。发布顺序：

1. 确认 `CFBundleShortVersionString` 为 `0.2.0`、`CFBundleVersion`
   为 `4`；
2. 再次确认生产源码没有任何虚拟额度或 DEBUG 标记；
3. 精确暂存第 9 节列出的候选文件；
4. 检查 staged diff，确认未加入四项用户未跟踪内容；
5. 创建最终 commit，并从该 commit 运行 `swift test`；
6. 构建 `arm64 + x86_64` Universal Release；
7. 检查版本号、`AppIcon.icns`、`Assets.car`、全部更新 SVG 和 Asta Sans；
8. 生成唯一资产 `QuotaView-v0.2.0-build.4.zip`，完成签名、ZIP 解包
   验签、真实启动烟雾测试和 SHA-256；
9. 推送发布分支，创建 PR 并等待 CI；
10. PR 合并到 `main` 后创建新 tag `v0.2.0-build.4`；
11. 推送 tag，创建新的 GitHub Release 并上传 Build 4 ZIP；
12. 从 GitHub 回下载资产，复核大小、SHA-256、签名标志和真实启动；
13. Build 4 验证完成后删除损坏的 Build 3 Release 和
    `v0.2.0-build.3` tag。

Apple Developer 审批完成前，如果继续使用 ad-hoc 签名，Release Notes
必须明确说明未公证和 Gatekeeper 限制。

`scripts/build-app.sh` 已将 Build Number 写入产物名称；Build 4
生成 `QuotaView-v0.2.0-build.4.zip`，不会覆盖现有
`dist/QuotaView-v0.2.0.zip`。

### 0.2.0 Build 4 Release Notes 要点

建议标题：

```text
QuotaView 0.2.0 (Build 4) — Launch Reliability Hotfix
```

正文至少说明：

- 按 UI1/UI2 精修按钮、重置入口、重置按钮、订阅 Tag 和连接状态标签；
- 更新浅色功能图标和菜单栏图标；
- 修复连接状态标签的橄榄球形轮廓；
- 保留 Universal Apple Silicon / Intel 和 macOS 14+ 支持；
- 重置额度显示来自真实 Codex 数据，不包含调试虚拟值；
- 额度重置操作仍为本地 Demo，不调用真实 consume 接口；
- 修复 Build 3 下载包因 ad-hoc Hardened Runtime Library Validation
  导致内嵌 Framework 无法加载的问题；
- Build 4 的 ad-hoc 回退不启用 Hardened Runtime，Developer ID /
  Apple Development 签名仍启用；
- 最终 ZIP SHA-256；
- 实际签名与公证状态。

## 11. 常用验证命令

### 测试

```bash
swift test
```

### Universal Release

```bash
xcodebuild -quiet \
  -project QuotaView.xcodeproj \
  -scheme QuotaView \
  -configuration Release \
  -derivedDataPath /private/tmp/quotaview-release-handoff \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build
```

### 图标资源检查

```bash
xmllint --noout \
  Resources/Assets.xcassets/QuotaViewMenuIcon.imageset/QuotaView.svg \
  Resources/Assets.xcassets/QuotaViewFigmaBackLight.imageset/QuotaViewFigmaBackLight.svg \
  Resources/Assets.xcassets/QuotaViewFigmaOpenCodexLight.imageset/QuotaViewFigmaOpenCodexLight.svg \
  Resources/Assets.xcassets/QuotaViewFigmaPowerLight.imageset/QuotaViewFigmaPowerLight.svg \
  Resources/Assets.xcassets/QuotaViewFigmaSettingsLight.imageset/QuotaViewFigmaSettingsLight.svg \
  Resources/Assets.xcassets/QuotaViewFigmaSyncLight.imageset/QuotaViewFigmaSyncLight.svg

jq empty \
  Resources/Assets.xcassets/QuotaViewMenuIcon.imageset/Contents.json

assetutil --info \
  /private/tmp/quotaview-release-handoff/Build/Products/Release/QuotaView.app/Contents/Resources/Assets.car
```

### 发布门禁检查

```bash
rg -n \
  'DEBUG-ONLY-MOCK|DEBUG MOCK|DEBUG ONLY|仅用于调试|debugResetCreditOverride|displayAvailableResetCredits' \
  Sources Tests

rg -n 'account/rateLimitResetCredit/consume' Sources Tests

/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  Support/Info.plist

/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  Support/Info.plist

lipo -archs \
  /private/tmp/quotaview-release-handoff/Build/Products/Release/QuotaView.app/Contents/MacOS/QuotaView
```

前两个 `rg` 命令在当前产品边界下必须没有匹配；发布版本应显示
`0.2.0`、Build Number `4` 和 `x86_64 arm64`。

### 工作区检查

```bash
git status --short --branch
git diff --check
git diff --name-only
git diff --cached --check
git diff --cached --name-only
```

## 12. 新会话开始时

1. 阅读根目录 `AGENTS.md` 和本文件；
2. 运行 `git status --short --branch`；
3. 确认 `main` 与 `origin/main` 的 ahead/behind；
4. 不清理用户未跟踪文件；
5. 保持 Build 3 已实现的 UI 和状态栏图标，不把 Build 4 运行时修复描述为
   新的视觉验收；
6. 确认连接状态标签继续使用 `18 pt` 高、`6 pt` 圆角；
7. 确认重置额度只来自真实 `availableResetCredits`；
8. 不因 SourceKit 红线复制或移动 Domain 类型；
9. 修改后至少运行 `swift test`；
10. UI、资源或发布改动必须运行 Universal Xcode Release；
11. 用户确认前视觉状态保持“等待用户验收”；
12. 不接入真实额度重置 consume 接口；
13. 使用唯一的 `v0.2.0-build.4` tag 和带 Build Number 的 ZIP，不覆盖
    `v0.2.0` tag 或 Build 1 Release 资产；
14. 不把 ad-hoc 签名描述成 Developer ID 公证发布；
15. Build 4 发布并回下载验证后，再删除 Build 3 Release 与 tag。
