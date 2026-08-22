# QuotaView 0.3.5 应用检查与更新规格

> 文档编号：`QV-PRODUCT-APP-UPDATES-003`
>
> 规格状态：`Accepted`
>
> 交付状态：`Verifying`（Build 5 已正式发布并上线 Feed；真实 N → N+1 待后续 Build）
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
- Appcast 条目必须提供全局递增的机器可读内部更新序号、用户可读的
  Marketing Version 与产品 Build、最低 `macOS 14`、资产长度、EdDSA
  签名和 Release Notes；
- Appcast 只能在不可变 GitHub Release 资产可下载且已复核后最后发布。

### 3.1 自动更新序列准入

- GitHub Stable Release 与公开 Sparkle appcast 的成员资格彼此独立；
- 产品所有者针对精确版本、Build、tag 和 ZIP 身份明确批准后，该批准即授权
  并触发正式签名、公证、Stable Release、回下载、公开 appcast 和文档联动；
  不得在代码合并后等待第二次发布确认；
- 未明确批准的所有 GitHub 推送、tag、Stable/Latest Release 和正式资产默认
  不进入 appcast；本地 Fixture 验证不构成发布授权；
- appcast 可跳过未批准的中间版本。客户端以更高 `CFBundleVersion` 内部
  更新序号判断更新，因而可从较早获准版本直接升级到之后获准的版本；
- 产品所有者已于 `2026-08-11` 明确批准 `0.3.5 Build 5` 进入自动更新序列，
  准入身份固定为 tag `v0.3.5-build.5` 与资产
  `QuotaView-v0.3.5-build.5.zip`；最终资产 SHA-256、Developer ID、Apple
  公证/Staple、回下载、Feed 签名和线上复核门禁均已完成。后续版本必须
  重新获得精确准入，不得沿用本次授权。

## 4. 版本规则

产品可见 Build Number 按 Marketing Version 独立计数：Marketing Version
变化时归 `Build 1`，同一 Marketing Version 内的后续迭代依次递增。因此
`0.3.5 Build 5` 的下一 Marketing Version 为 `0.3.6 Build 1`。

Sparkle 的[官方升级说明](https://sparkle-project.org/documentation/upgrading/)
要求 `CFBundleVersion` / `sparkle:version` 使用递增的机器可读版本，因此
两者继续作为跨 Marketing Version 单调递增的内部更新序号；从
`0.3.5 Build 5` 到 `0.3.6 Build 1` 时内部序号由 `5` 增至 `6`。产品可见
Build 由 `QuotaViewDisplayBuildNumber` / `QUOTAVIEW_DISPLAY_BUILD_NUMBER`
维护，设置界面、tag、ZIP、Handoff 与版本历史使用该值。App、Widget 与
兼容 Info.plist 必须同时同步 Marketing Version、产品 Build 和内部更新序号。

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
| `APP-UPDATES-05` | Stable-only、最低系统版本、按 Marketing Version 重置的产品 Build 与全局递增的内部更新序号 | Appcast Fixture、版本门禁 |
| `APP-UPDATES-06` | Sparkle 嵌套组件由内到外签名且均为 Universal | 发布脚本、codesign、lipo |
| `APP-UPDATES-07` | 两个真实签名公证版本完成 N → N+1 更新 | 发布前端到端验证记录 |
| `APP-UPDATES-08` | 产品所有者按精确版本显式批准后自动执行完整 Release 与 appcast 链路；未批准默认排除 | Handoff 当前准入状态、Version History 最终 Release 与 Feed 证据 |

## 7. 发布边界

本规格的默认授权边界仍以 3.1 的显式准入为准。产品所有者已明确批准
`0.3.5 Build 5` 进入自动更新序列，因此本版已完成 Developer ID、Apple
公证/Staple、GitHub Stable/Latest、回下载、公开 appcast 和文档联动。

Build 5 是首个包含更新器的正式版本，无法单独完成两个正式版本之间的
N → N+1 验收。因此 `APP-UPDATES-07` 和本规格交付状态保持 `Verifying`，
直到后续获准且内部更新序号更高的版本完成真实应用内更新；这不影响
Build 5 版本本身已经 `Released`。后续 GitHub Stable/Latest 仍不自动获得
appcast 准入。

## 8. 当前验证记录

- `swift test`：64 项通过，0 失败；PR #22 GitHub CI 通过；
- `0.3.5 Build 5` Universal 正式构建通过；App、Widget、Hook、Core、
  Sparkle framework 及其 Installer、Downloader、Autoupdate、Updater
  组件均包含 `x86_64 arm64`；
- Build 5 的自动检查开关已复用 `NativeSettingsCard` / `NativeSettingsRow`，
  形成左文右控件的独立设置栏；产品视觉验收待完成；
- Developer ID 正式 ZIP 为 `QuotaView-v0.3.5-build.5.zip`，大小
  `12,747,358 bytes`，SHA-256
  `d8524ddf5739501bd797cdd082cc8738a7775d8b994fe99033068af8f821b2e1`；
- Apple notarization `Accepted` 并 Staple，Submission
  `88796026-3227-405a-9e1b-900af973c527`；GitHub Release 回下载与本地正式
  ZIP 逐字节一致，并重新通过签名、Gatekeeper、版本、架构与资源复核；
- Sparkle 私钥完成 AES-256 iCloud 加密备份与恢复一致性验证，恢复密码只存
  macOS Keychain；
- 公开 appcast 已部署到 `https://duoasa.github.io/QuotaView/appcast.xml`，
  SHA-256 为
  `ee46651f1b45fe03cf4e4967543d3b5dd18a644aff956fd5396ea90bd36e2f50`；线上
  文件与本地签名 Feed 逐字节一致，Feed EdDSA 验证通过；
- 设置完整视觉/辅助功能矩阵与真实 N → N+1 更新仍未完成，因此规格结论
  保持 `Verifying`；Build 5 版本发布事实为 `Released`。
