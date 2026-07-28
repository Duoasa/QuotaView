# QuotaView 项目 Handoff

更新日期：2026-07-28
工作区：`/Users/sukduoasa/Documents/widget`
当前分支：`codex/optimize-github-page`
当前 HEAD：`332e6eb96503053947c533b673ae9bf5d7e839c5`
远程：`https://github.com/Duoasa/QuotaView.git`

## 1. 当前发布状态

### GitHub 已发布版本

- GitHub 最新 Release / Tag：`v0.1.5`
- Release 对应版本：`0.1.5 Build 6`
- Tag commit：`c98a6ee8bf16eaa7459c5db62507cae9edde8576`
- 本地已发布 ZIP：`dist/QuotaView-v0.1.5.zip`
- 本地 ZIP SHA-256：
  `979e68c07a9183b45350d7270b7e86c227a792f273a84035454d4443cd97ad74`
- 签名：Apple Development，Hardened Runtime 已开启
- 公证：未完成

不要移动或覆盖已有的 `v0.1.5` tag。

### 待发布版本

- 建议 GitHub Tag：`v0.2.0`
- Marketing Version：`0.2.0`
- Build Number：`1`
- Bundle Identifier：`com.quotaview.menubar`
- 最低系统版本：macOS 14
- 架构：Universal `arm64 + x86_64`
- 预计发布文件：`dist/QuotaView-v0.2.0.zip`
- 当前状态：源码和无签名 Release 验证完成，尚未提交、签名、公证、生成
  正式 ZIP 或创建 GitHub Release

公开仓库的 README 在 Release 创建前仍应把 `v0.1.5` 描述为当前下载
版本。上传并公开 `v0.2.0` 后，再将下载文件名、当前版本和签名说明同步
切换到 0.2.0。

## 2. 0.2.0 范围

0.2.0 是底层架构重构版本，保持现有产品定位和整体 UI，不以新增大型
可见功能为目标。

已完成：

- Domain、Provider Adapter、静态 Provider Registry；
- Refresh Coordinator、generation/revision/account scope 防旧结果覆盖；
- 当前 UI 使用独立 `CurrentCodexPresentation`；
- 现有菜单栏、主面板、设置、刷新、本地化和重置 Demo 全部重新接入；
- App Server 启动/请求超时、1 MB 单行上限和有界诊断；
- 可选 Usage 请求失败时不污染必需额度数据；
- Token 区域全部关闭时不再请求 Usage 数据；
- History、Chart、Display Preferences、Notification 的无副作用契约；
- 独立 Foundation-only Widget Contract；
- Apple App Group、Widget Bundle ID 和 Development Team 空配置预留；
- 28 项自动化测试；
- 版本更新为 `0.2.0 (1)`。

本版明确不包含：

- 第二个 Provider 的真实实现；
- SQLite History 和新图表 UI；
- 系统通知权限和调度；
- Widget Extension、App Group entitlement；
- Developer ID 签名和 Apple 公证；
- 真实手动或自动账户写操作；
- 真实额度重置调用。

详细实施记录：

- `docs/design/quotaview-core-architecture-evolution.md`
- `docs/design/quotaview-core-refactor-0.2.0-report.md`
- `docs/design/quotaview-widgetkit-solution.md`

## 3. 产品与安全边界

- 默认只读，只通过本机官方 `codex app-server` 读取数据；
- 不抓取网页；
- 不读取、复制或保存 `~/.codex` 登录凭据；
- 不输出 Token、认证材料或直接联系/支付信息；
- UserDefaults 只保存显示偏好、简短诊断和最近刷新信息；
- Provider 刷新层不持有账户操作 Executor；
- 当前操作能力固定为 `demoOnly`；
- 非 Demo 授权由当前执行器拒绝；
- 生产源码不得出现
  `account/rateLimitResetCredit/consume`；
- Apple Developer 审批完成前，不猜测 Team ID、App Group 或签名配置。

未来允许的产品定位是：

> 默认只读；用户对具体操作单独授权后，才允许调用官方账户操作。

真实操作接入时仍必须区分手动一次授权与自动规则授权，并增加幂等、过期、
审计、安全降级和失败恢复，不能通过 Provider 读取流程隐式触发。

## 4. 当前设置与 UI

首次安装默认值：

- 外观：跟随系统；
- 玻璃质感：清透；
- 语言：跟随系统语言。

已经保存的有效外观、磨砂/清透和语言选择不会被新默认值覆盖。未知的旧版
玻璃枚举值会迁移为清透。

UI 约束继续以根目录 `AGENTS.md`、生产代码和现有设计文档为准：

- 主面板完整显示尺寸 `258 × 431 pt`，隐藏内容后动态缩短；
- 重置详情固定为 `258 × 473 pt`；
- 设置窗口默认内容尺寸 `872 × 637 pt`；
- 主面板只保留一层实时背景取样的系统玻璃；
- 主面板与重置流程继续使用 Asta Sans；
- 设置窗口继续使用系统字体、系统语义色和原生控件；
- 当前 UI 视觉效果不因底层重构主动改变；
- 额度重置继续是 Demo，不调用真实接口。

视觉和交互验收状态：**等待产品所有者验收**。

发布前至少覆盖：

- 浅色 / 深色 / 跟随系统；
- 磨砂 / 清透；
- 简体中文 / English / 跟随系统；
- 可用 / 不可用 / 刷新中 / 无重置次数；
- Hover / Pressed / Disabled / 键盘 / Escape / 外部点击；
- Reduce Motion / Increase Contrast / VoiceOver。

## 5. 当前代码结构

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

`QuotaViewFutureContracts` 和 `QuotaViewWidgetContract` 当前是 SwiftPM 独立
target，不链接进生产 App。当前 `.app` 内没有 `.appex`。

## 6. 已完成验证

最后一次代码验证日期：2026-07-28。

### 自动化测试

```bash
swift test
```

结果：

- 28 项测试通过；
- 0 失败；
- 覆盖 Provider 映射、缺失值、超界值、历史桶；
- 覆盖 replace、coalesce、禁用和账户切换；
- 覆盖 App Server 延迟、可选请求失败/超时、超长输出；
- 覆盖设置默认值和已保存设置保持；
- 覆盖 Demo 写操作边界；
- 覆盖 Widget schema、过期、大小和敏感字段扫描。

### Universal Release

已执行无签名构建：

```bash
xcodebuild -quiet \
  -project QuotaView.xcodeproj \
  -scheme QuotaView \
  -configuration Release \
  -derivedDataPath /private/tmp/quotaview-release-native-defaults \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build
```

结果：

- Xcode Release 构建成功；
- App：`x86_64 arm64`；
- `QuotaViewCore.framework`：`x86_64 arm64`；
- 版本：`0.2.0 (1)`；
- `AppIcon.icns`、`Assets.car`、三款 Asta Sans 字体存在；
- 无 Widget Extension；
- `git diff --check` 通过；
- 未发现真实额度 consume、截图、自动展开、自动点击或 UI QA 入口。

同机无签名 Universal 基线体积：

| 指标 | 0.1.5 Build 6 | 0.2.0 Build 1 | 变化 |
|---|---:|---:|---:|
| `.app` | 16,076 KiB | 17,388 KiB | +8.16% |
| ZIP | 7,629,478 B | 7,990,649 B | +4.73% |
| App 主可执行文件 | 3,747,544 B | 3,907,464 B | +4.27% |

随后已从合并后的 `main` 使用 ad-hoc Hardened Runtime 签名生成
`dist/QuotaView-v0.2.0.zip`。脚本会在打包前后核对 ZIP SHA-256，并对
ZIP 解包结果执行 deep + strict 验签。正式 SHA-256 以最终上传资产为准。

尚未完成：

- 真实运行环境首次打开耗时；
- 空闲 15 分钟 CPU、唤醒次数和常驻内存；
- 视觉与交互验收；
- Developer ID 签名；
- 公证和 Staple。

## 7. 签名和打包

`scripts/build-app.sh` 会：

1. 构建 Universal Release；
2. 验证 App 和所有内嵌 framework 都包含 `arm64 + x86_64`；
3. 验证版本、Build Number、AppIcon 和 Assets；
4. 优先选择 Developer ID Application；
5. 没有 Developer ID 时选择 Apple Development；
6. 没有任何身份时使用 ad-hoc；
7. 对 framework 和 App 启用 Hardened Runtime 并签名；
8. 在提供 `NOTARY_PROFILE` 时提交公证并 Staple；
9. 生成并解包验证 ZIP。

普通打包：

```bash
./scripts/build-app.sh
```

正式公开分发建议只使用：

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

Apple Developer 账号仍在审批时，不得把 Apple Development 或 ad-hoc
签名描述成可公开分发的 Developer ID 签名。若审批前必须发布测试版，
应标记为 GitHub Pre-release，并在 Release Notes 中明确说明未公证及
Gatekeeper 限制。

脚本成功后预期生成：

```text
dist/QuotaView.app
dist/QuotaView-v0.2.0.zip
```

## 8. 正式 ZIP 验证

```bash
verify_dir="$(mktemp -d /private/tmp/quotaview-verify.XXXXXX)"
/usr/bin/ditto -x -k \
  dist/QuotaView-v0.2.0.zip \
  "${verify_dir}"

codesign --verify --deep --strict --verbose=4 \
  "${verify_dir}/QuotaView.app"
codesign -dv --verbose=4 \
  "${verify_dir}/QuotaView.app"
lipo -archs \
  "${verify_dir}/QuotaView.app/Contents/MacOS/QuotaView"
/usr/libexec/PlistBuddy \
  -c "Print :CFBundleShortVersionString" \
  "${verify_dir}/QuotaView.app/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Print :CFBundleVersion" \
  "${verify_dir}/QuotaView.app/Contents/Info.plist"
shasum -a 256 dist/QuotaView-v0.2.0.zip
```

Developer ID + 公证发布还必须通过：

```bash
spctl --assess --type execute --verbose=4 \
  "${verify_dir}/QuotaView.app"
xcrun stapler validate \
  "${verify_dir}/QuotaView.app"
```

预期版本输出为 `0.2.0` 和 `1`，架构输出必须同时包含 `x86_64 arm64`。
正式 SHA-256 只能从最终上传的 ZIP 计算，不能沿用无签名验证包的值。

## 9. GitHub 发布门禁

仓库当前只有 `.github/workflows/ci.yml`，没有自动签名、打包或创建 Release
的 workflow。CI 在 push 到 `main`、Pull Request 和手动触发时运行
`swift test`。0.2.0 发布按人工流程执行。

### 提交和 PR 前

1. 产品所有者完成视觉与交互验收；
2. 确认 14 个已暂存 Asset `Contents.json` 改动是否属于 0.2.0；
3. 确认两个未跟踪 PNG 是否发布；它们当前没有被代码引用；
4. 将 0.2.0 源码、新模块、测试、README、设计文档和本文件纳入提交；
5. 不提交 `/private/tmp` 验证产物；
6. 不覆盖 `dist/QuotaView-v0.1.5.zip`；
7. 再次运行 `swift test`、Universal Release 和 `git diff --check`；
8. 检查提交中不存在凭据、Team ID、notary profile 名或私钥材料；
9. 推送当前分支并创建面向 `main` 的 PR；
10. 等待 GitHub CI 通过并完成代码审查。

### 合并后

1. 准备发布收口提交，将 README 下载版本从 `v0.1.5` 更新为
   `v0.2.0`；
2. 等待收口提交进入远程 `main` 且 CI 通过，记录最终 commit SHA；
3. 从这个最终 commit 构建正式包，不使用其他工作区状态；
4. 正式版完成 Developer ID 签名、公证和 Staple；审批前发布的
   Pre-release 使用 ad-hoc Hardened Runtime 并完成 ZIP 解包验签；
5. 产品所有者运行最终解包 App，完成发布候选验收；
6. 计算最终 ZIP SHA-256；
7. 在同一个最终 commit 创建 annotated tag `v0.2.0`；
8. 推送 tag；
9. 创建 GitHub Release 并上传 `QuotaView-v0.2.0.zip`；
10. 在 Release Notes 中记录 SHA-256、macOS 要求、签名/公证状态和
   重置 Demo 边界；
11. 下载 GitHub 上的发布资产，再做一次 SHA-256 与解包启动抽查。

不要在 PR 未合并或 CI 未通过时提前打 `v0.2.0` tag。

## 10. GitHub Release Notes 草案

建议标题：

```text
QuotaView 0.2.0 — Core Architecture Update
```

建议正文：

```markdown
QuotaView 0.2.0 rebuilds the app's data foundation while preserving the
existing compact macOS interface.

Highlights:

- Provider-based domain and refresh architecture
- Safer refresh coordination and stale-result rejection
- More resilient Codex App Server timeouts and bounded output handling
- Existing menu bar, panel, settings, localization, and reset demo retained
- Native defaults: follow system appearance, clear glass, and follow system language
- Contracts reserved for future charts, history, notifications, providers, and widgets
- Read-only by default; no live quota-reset or account-write request
- Universal support for Apple Silicon and Intel Macs

Requirements:

- macOS 14 or later
- ChatGPT or Codex installed and signed in

Quota reset remains a local demo in this release and does not call the
official consume endpoint.

SHA-256:

`<FINAL_ZIP_SHA256>`
```

如果正式包尚未完成 Developer ID 公证，必须在正文开头增加醒目的
“Pre-release / Not notarized”说明，不得使用暗示已通过 Gatekeeper 的表述。

## 11. 当前 Git 工作区

- 0.2.0 核心源码、测试、双语 README 和设计文档已通过 PR #3 合并；
- 发布产物移动后验签强化已通过 PR #4 合并；
- GitHub Actions 两次均通过；
- 当前仅有发布签名说明的收口改动等待合并；
- `subtract-frosted-glass-icon.png` 与
  `subtract-frosted-glass-icon-transparent.png` 未跟踪且未被代码引用；
- `docs/reference/` 保持未跟踪，不属于本次发布范围；
- `dist/` 已生成 ad-hoc Hardened Runtime 签名、未公证的
  `QuotaView-v0.2.0.zip` Pre-release 候选；
- 视觉与交互状态仍为“等待用户验收”。

在明确提交范围前，不要执行 reset、checkout、clean、删除文件或覆盖
发布资产。

## 12. 新会话开始时

1. 阅读根目录 `AGENTS.md` 和本文件；
2. 运行 `git status --short --branch`；
3. 核对当前分支、HEAD、上游和 Release 目标；
4. 不清理用户已有暂存或未跟踪文件；
5. UI 规范以生产代码、`AGENTS.md` 和设计文档为准；
6. 修改后至少运行 `swift test`；
7. UI、资源或发布改动还要运行 Universal Xcode Release；
8. 视觉结果在用户确认前保持“等待用户验收”；
9. 不提前接入真实额度重置；
10. 不把 Apple Development 或 ad-hoc 签名写成 Developer ID 公证发布。
