# QuotaView 项目 Handoff

更新日期：2026-07-30

工作区：`/Users/sukduoasa/Documents/widget`

当前分支：`codex/0.2.1-native-widget`

当前提交与生产基线：`8a76b5725b616091e2841a8eae232f58168d6674`

远程：`https://github.com/Duoasa/QuotaView.git`

## 0. 版本定位入口

公开发布版本的唯一索引位于：

**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**

当前公开 Latest 仍为：

| 项目 | 当前值 |
|---|---|
| 最新推荐版本 | `0.2.0 (Build 4)` |
| tag | `v0.2.0-build.4` |
| 发布提交 | `8a76b5725b616091e2841a8eae232f58168d6674` |
| Release | [QuotaView 0.2.0 (Build 4)](https://github.com/Duoasa/QuotaView/releases/tag/v0.2.0-build.4) |

当前待发布版本为 `0.2.1 (Build 1)`。它尚未创建 tag、GitHub Release，
也尚未替换 GitHub Latest，因此不得写成已经发布。

文档职责：

- `HANDOFF.md`：当前开发状态、验证结论和发布入口；
- `VERSION_HISTORY.md`：公开版本、tag、Release、资产与撤回记录；
- `AGENTS.md`：长期产品、设计、实现和发布约束；
- `design-qa.md`：视觉验收历史。

## 1. 0.2.1 发布候选

### 版本与目标

| 项目 | 当前值 |
|---|---|
| Marketing Version | `0.2.1` |
| Build Number | `1` |
| 最低系统版本 | macOS 14 |
| App Bundle ID | `com.quotaview.menubar` |
| Widget Bundle ID | `com.quotaview.menubar.widget` |
| App Group | `group.com.quotaview.shared` |
| 架构 | Universal `arm64 + x86_64` |
| Development Team | `BUUH229D5Q` |
| 发布状态 | 发布准备中，尚未发布 |

### 关键更新

- 新增原生 WidgetKit 扩展，支持 macOS 小号与中号小组件；
- 主 App 通过 App Group 原子写入最小、脱敏且带过期时间的快照，Widget
  只读快照，不直接访问网络、凭据或 Codex App Server；
- 小组件接入真实额度、重置时间、Credits、今日 Token、累计 Token、
  订阅方案和连接状态；缺失、错误或过期时显示不可用和破折号，不伪造
  `0%`；
- 按 Figma 节点 `34:1846` 完成小号/中号、深色/浅色 Widget UI，并修复
  SwiftUI 紧行高导致 Asta Sans 字号被二次缩小的问题；
- 按 Figma 节点 `1:704` 更新状态栏菜单 UI、进度条、连接状态和局部
  Liquid Glass；
- 订阅方案统一映射为 OpenAI 官方名称，未知协议值显示破折号；
- 恢复 Apple 正式开发环境：主 App 与 Widget 使用 Automatic Signing、
  正式 App Group entitlement 和各自的显式 App ID；
- 构建脚本已覆盖嵌套 Widget Extension 的签名、版本、Bundle ID、架构、
  extension point、sandbox 与 App Group 校验。

### 产品与安全边界

- 当前功能保持只读；
- Widget 快照不得包含认证 Token、Cookie、账号标识、完整响应或历史明细；
- Widget 不得自行启动 Codex App Server；
- 额度重置仍为本地 Demo，不得调用
  `account/rateLimitResetCredit/consume`；
- Release 构建不得包含调试虚拟数据、自动展开、自动点击、截图或 UI QA
  入口。

## 2. 当前验证状态

已完成：

- `swift test`：33 项通过，0 失败；
- Apple Development Xcode Debug 构建通过，主 App 与 Widget 的开发
  Profile 均包含 `group.com.quotaview.shared`；
- 无签名 Universal Xcode Release 构建通过；
- App、`QuotaViewCore.framework` 与 Widget Extension 均为
  `x86_64 arm64`；
- App 与 Widget 均为 `0.2.1 (1)`；
- Widget Extension 包含 `Assets.car`、Asta Sans 字体和简体中文资源；
- `codesign --verify --deep --strict` 已在开发构建链路通过；
- 产品所有者已确认主 App 写入、Widget 读取和 timeline 刷新成功；
- 临时虚拟数据、真实额度消费调用和 UI QA 入口搜索无匹配。

等待产品所有者验收：

- 小号 / 中号；
- 浅色 / 深色；
- 简体中文 / English；
- Increase Contrast / Reduce Motion / VoiceOver；
- 菜单与 Widget 的最终视觉、Hover、Pressed、Disabled 和键盘交互。

视觉与交互矩阵在用户明确确认前不得记录为“已通过”。

## 3. 发布准备状态

钥匙串中已确认存在：

- `Apple Development: Chenchen Xu (Z6X48CV8PX)`；
- `Apple Distribution: Chenchen Xu (BUUH229D5Q)`；
- `Developer ID Application: Chenchen Xu (BUUH229D5Q)`。

正式发布前仍需完成：

1. 完成产品所有者视觉与交互验收；
2. 使用当前源码重新执行 Universal Release；
3. 使用 `Developer ID Application: Chenchen Xu (BUUH229D5Q)` 签名；
4. 提交 Apple notarization、等待成功并 staple；
5. 对全新解压的 App 执行 `codesign`、`spctl` 和真实启动烟雾测试；
6. 生成唯一的 `0.2.1` 发布 ZIP，并记录文件名、大小与 SHA-256；
7. 核对 App、Framework、Widget 的签名、Team ID、版本、架构和
   entitlement；
8. 创建发布提交、唯一 tag 和 GitHub Release，再设为 Latest；
9. 同步更新 `VERSION_HISTORY.md`、本文件、README 下载链接和 Release
   Notes；
10. 从 GitHub 回下载资产，复核 SHA-256、签名、公证与启动结果。

此前生成的 ad-hoc `0.2.1 Build 1` ZIP 早于最终 Widget UI，不得作为正式
发布资产。正式 ZIP 的名称、大小和 SHA-256 必须以重新构建后的结果为准。

建议发布 tag 和资产名：

```text
tag: v0.2.1
asset: QuotaView-v0.2.1.zip
```

如 Marketing Version 保持 `0.2.1` 但需要发布热修复，必须增加 Build
Number，并为 tag 和 ZIP 加入唯一 Build 标识。

## 4. 当前实现边界

数据链路：

```text
CodexProviderAdapter
→ CodexStatusStore
→ sanitized WidgetSnapshot JSON
→ group.com.quotaview.shared
→ QuotaViewWidgetExtension
```

实现约束：

- 主 App 是唯一数据获取方；
- Widget 快照默认 15 分钟过期，timeline 最短 5 分钟重新读取；
- 主数据刷新、可用状态或语言变化时更新快照；
- 可选 Credits 或 Token 数据缺失不能覆盖有效额度状态；
- 主面板继续使用 Asta Sans，设置窗口继续使用系统字体；
- 菜单与 Widget 的详细视觉令牌以 `AGENTS.md` 和对应 Figma 节点为准；
- 不增加第二层主面板玻璃，不接入真实额度重置接口。

## 5. Git 工作区

当前分支尚未形成新的提交；`HEAD` 与 `origin/main` 均为：

```text
8a76b5725b616091e2841a8eae232f58168d6674
```

工作区包含本次 0.2.1 的源码、配置、测试、资源和文档修改。提交前必须逐
文件确认范围，不得使用宽范围 `git add .`。

以下未跟踪参考资料不属于 0.2.1 发布资产，不得擅自纳入提交：

```text
docs/reference/
quotaview-blurred-gradient-background-2k.png
subtract-frosted-glass-icon-transparent.png
subtract-frosted-glass-icon.png
```

不得使用 `git clean`、`git reset --hard` 或 `git checkout --` 清理用户
文件。

## 6. 发布门禁

发布前至少执行：

```bash
swift test

rg -n \
  'DEBUG-ONLY-MOCK|DEBUG MOCK|DEBUG ONLY|仅用于调试|debugResetCreditOverride|displayAvailableResetCredits' \
  Sources Tests

rg -n 'account/rateLimitResetCredit/consume' Sources Tests

git diff --check
git diff --cached --check
git status --short --branch
```

正式签名、公证和打包：

```bash
CODESIGN_IDENTITY="Developer ID Application: Chenchen Xu (BUUH229D5Q)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

发布产物至少检查：

```bash
codesign --verify --deep --strict --verbose=4 QuotaView.app
spctl --assess --type execute --verbose=4 QuotaView.app
lipo -archs QuotaView.app/Contents/MacOS/QuotaView
lipo -archs \
  QuotaView.app/Contents/PlugIns/QuotaViewWidgetExtension.appex/Contents/MacOS/QuotaViewWidgetExtension
```

仅验签不足以证明可发布。必须全新解压并进行真实启动测试；发布后还要从
GitHub 回下载再次验证。

## 7. 文档联动

0.2.1 正式发布后，在同一任务内完成：

1. 将 `VERSION_HISTORY.md#当前最新版本` 更新为 0.2.1；
2. 在版本总览和版本详情中记录 tag、发布提交、Release URL、资产名、
   大小、SHA-256、签名、公证和验证结论；
3. 将本文件第 0、1、2、3 节由候选状态更新为发布事实；
4. 更新 README 下载入口；
5. 确认 GitHub Release Notes 只有一份英文源正文；
6. 确认已撤回的 `0.2.0 Build 3` 不会重新成为下载或开发基线。

在 tag、Release 和 GitHub Latest 实际完成前，
`VERSION_HISTORY.md#当前最新版本` 必须继续指向 `0.2.0 (Build 4)`。
