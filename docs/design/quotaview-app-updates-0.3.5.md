# QuotaView 0.3.5 应用检查与更新规格

> 文档编号：`QV-PRODUCT-APP-UPDATES-003`
>
> 规格状态：`Accepted`
>
> 交付状态：`Verifying`
>
> 目标版本：`0.3.5 (Build 5)`

## 1. 目标

为 Developer ID 直接分发的 QuotaView 增加可验证、可恢复的应用内更新能力，
复用当前 GitHub Release 的签名、公证 ZIP，不增加账户凭据、网页抓取或用户
数据采集。首个带更新能力的版本仍由用户手动安装；从该版本开始，后续稳定
版本可在应用内完成检查、下载、验证、替换与重启。

实现参考 CodexBar 已验证的 Sparkle 生命周期和发布门禁，但不复制其多提供
商设置、菜单卡片、OAuth、Cookie、Keychain 凭据或自定义更新窗口。

## 2. 产品行为

- 通用页“检查更新…”调用 Sparkle 标准用户界面，不再显示占位文案；
- 自动检查使用独立的原生设置卡片行：左侧显示标题和当前可用状态说明，
  右侧使用小号系统 Switch；默认关闭，开启后每 24 小时检查一次；
- 不允许静默下载或安装，每次安装均需用户明确确认；
- 只接收 Stable 通道，不把 GitHub Pre-release 或 0.3.2 Preview 提供给
  稳定版；
- 不启用系统画像、JavaScript 或额外遥测；
- Debug、SwiftPM、非 `.app`、错误 Bundle ID、Ad Hoc/未签名和非预期 Team
  ID 构建不创建更新器、不请求更新源，并在设置中说明当前构建不可更新。

## 3. 更新信任链

- Sparkle 固定为 `2.9.2`，只链接主 App Target；Widget、Hook 与 Core 不得
  引入更新依赖；
- Appcast 使用 HTTPS，目标地址为
  `https://duoasa.github.io/QuotaView/appcast.xml`；
- 更新 ZIP 必须同时通过 Developer ID、Apple 公证/Staple 和 Sparkle EdDSA
  签名；
- 启用解压前验证和签名 Feed；公钥进入 Info.plist，私钥只进入开发者
  Keychain，并在发布前完成加密离线备份；
- Appcast 条目必须提供全局递增的 Build Number、用户可读版本、最低
  `macOS 14`、资产长度、EdDSA 签名和 Release Notes；
- Appcast 只能在不可变 GitHub Release 资产可下载且已复核后最后发布。

### 3.1 自动更新序列准入

- GitHub Stable Release 与公开 Sparkle appcast 的成员资格彼此独立；
- 只有产品所有者针对精确版本、Build、tag 和最终 ZIP 明确批准后，该版本
  才能进入自动更新序列；
- 未明确批准的所有 GitHub 推送、tag、Stable/Latest Release 和正式资产默认
  不进入 appcast；本地 Fixture 验证不构成发布授权；
- appcast 可跳过未批准的中间版本。客户端以更高 Build Number 判断更新，
  因而可从较早获准版本直接升级到之后获准的版本；
- 产品所有者已于 `2026-08-11` 明确批准 `0.3.5 Build 5` 进入自动更新序列，
  准入身份固定为 tag `v0.3.5-build.5` 与资产
  `QuotaView-v0.3.5-build.5.zip`；最终资产 SHA-256、Developer ID、Apple
  公证/Staple、回下载和 Feed 签名门禁完成前仍不得公开部署 appcast。

## 4. 版本规则

`CFBundleVersion` 从 `0.3.5 Build 4` 起全局单调递增，不再随 Marketing
Version 重置。后续示例为 `0.3.5 Build 5`、`0.3.6 Build 6`。应用、Widget、
兼容 Info.plist、tag、ZIP、Handoff 和版本历史必须使用同一个 Build Number。

## 5. 架构

`QuotaViewAppDelegate` 持有唯一的 `AppUpdateController`。控制器先验证运行
环境，只有正式签名环境才创建并启动 `SPUStandardUpdaterController`；同一
实例注入 SwiftUI Settings Scene 与菜单栏控制器创建的设置窗口。Sparkle
自行持久化自动检查偏好，`AppPreferences` 不复制该值。

## 6. Requirement 与验收条件

| Requirement ID | 要求 | 验收证据 |
|---|---|---|
| `APP-UPDATES-01` | 单一长生命周期 Sparkle 控制器并注入两处设置入口 | 生命周期代码审查、编译 |
| `APP-UPDATES-02` | Debug、非 App 和非预期签名环境无网络更新 | 纯环境模型测试、Ad Hoc 构建检查 |
| `APP-UPDATES-03` | 手动检查、独立原生设置行、默认关闭的 24 小时自动检查、显式安装 | 设置行为测试、Info.plist 校验 |
| `APP-UPDATES-04` | HTTPS、EdDSA、签名 Feed、解压前验证、无画像/JS | 配置与 Appcast 校验 |
| `APP-UPDATES-05` | Stable-only、最低系统版本和全局递增 Build | Appcast Fixture、版本门禁 |
| `APP-UPDATES-06` | Sparkle 嵌套组件由内到外签名且均为 Universal | 发布脚本、codesign、lipo |
| `APP-UPDATES-07` | 两个真实签名公证版本完成 N → N+1 更新 | 发布前端到端验证记录 |
| `APP-UPDATES-08` | 产品所有者按精确版本显式批准 appcast；未批准默认排除 | Handoff 准入记录、发布前授权核对 |

## 7. 发布边界

本规格授权生产实现与本地验证，不等同于授权创建 GitHub Release、切换
Latest 或发布 Appcast。未完成正式签名、公证、EdDSA 私钥离线备份及两个
版本端到端测试前，交付状态不得改为 `Released`，公开 Latest 继续保持
`0.3.3 Build 3`。

即使上述工程门禁全部通过，也只有产品所有者明确指定的版本可以发布到
公开 appcast。发布 GitHub Stable/Latest 本身不构成自动更新序列授权。

## 8. 当前验证记录

- `swift test`：64 项通过，0 失败；
- `0.3.5 Build 5` Universal Xcode Release 无签名构建通过；App、Widget、Hook、Core、
  Sparkle framework 及其 Installer、Downloader、Autoupdate、Updater
  组件均包含 `x86_64 arm64`；
- Build 5 的自动检查开关已复用 `NativeSettingsCard` / `NativeSettingsRow`，
  形成左文右控件的独立设置栏；产品视觉验收待完成；
- Build 5 的 Ad Hoc 发布脚本完成 Sparkle 嵌套组件内到外签名、ZIP 解压与
  严格验签；
- 临时 `0.3.5 Build 5` ZIP（SHA-256
  `4b8bf53c38f2144fa6f67ebafc8df9a7af4a4285b71b5cf76cb65ef7148f8028`）
  成功生成并验证签名 appcast；版本、最低 macOS 14、稳定资产 URL、ZIP
  EdDSA 与 Feed EdDSA 字段通过；该 Ad Hoc 资产仅为 Fixture，不得发布；
- 设置视觉/交互、Developer ID 正式包、公证、私钥加密离线备份、公开 Feed
  与真实 N → N+1 更新仍未完成，当前结论保持 `Verifying`。
