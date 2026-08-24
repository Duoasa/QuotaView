# QuotaView 应用检查与更新规格

> 文档编号：`QV-PRODUCT-APP-UPDATES-003`
>
> 规格状态：`Accepted`
>
> 交付状态：`Verifying`
>
> 首次交付：`0.3.5 Build 5`

目标是在 Developer ID 直接分发版中提供可验证、可恢复的 Stable 应用更新，
不增加账户凭据、网页抓取、遥测或静默安装。

## 产品行为

- 通用页“检查更新…”调用 Sparkle 标准界面；自动检查是独立原生设置行，
  默认关闭，用户开启后每 24 小时检查；每次安装仍需明确确认；
- 只接收 Stable 通道，不向稳定版提供 Preview/Pre-release；
- Debug、SwiftPM、非 `.app`、错误 Bundle ID、Ad Hoc/未签名或非预期 Team
  构建不创建更新器、不访问 Feed，并显示真实不可用原因；
- `QuotaViewAppDelegate` 持有唯一 `AppUpdateController`，同一实例注入两种
  Settings 入口；自动检查偏好由 Sparkle 保存，不在 `AppPreferences` 复制。

## 信任链与版本规则

- 主 App 固定使用 Sparkle `2.9.2`；Widget、Hook 和 Core 不链接 Sparkle；
- Feed 为 `https://duoasa.github.io/QuotaView/appcast.xml`，必须使用 HTTPS、
  签名 Feed 和解压前验证；ZIP 同时通过 Developer ID、Apple 公证/Staple
  与 Sparkle EdDSA；私钥只在开发者 Keychain 和加密备份中保存；
- appcast 条目提供最低 macOS 14、资产长度、EdDSA、Release Notes、用户
  可见版本和机器可读内部更新序号；不可变 Release 资产复核完成后最后发布
  Feed；
- 产品 Build 按 Marketing Version 独立计数并在版本变化后归 1；Sparkle
  `CFBundleVersion` 跨 Marketing Version 单调递增。App、Widget 和兼容
  Info.plist 的 Marketing Version、产品 Build 与内部序号必须同步。

## appcast 显式准入

- GitHub push、tag、Stable/Latest Release 或上传 ZIP 均不自动进入更新
  序列；产品所有者必须针对精确版本、产品 Build、tag 和 ZIP 明确批准；
- 该批准触发完整链路：合并、Developer ID、公证/Staple、不可变 Stable
  Release、回下载、EdDSA appcast 与文档联动；更换身份或重新打包需重新确认；
- appcast 可跳过未批准的中间版本；每个后续版本都需独立批准；
- `0.3.5 Build 5` 与 `0.3.6 Build 2` 已明确获准并完成发布，详细资产证据只
  在 [`VERSION_HISTORY.md`](../../VERSION_HISTORY.md) 保存。

## Requirement

| ID | 要求 |
|---|---|
| `APP-UPDATES-01` | 单一长生命周期控制器并注入所有设置入口 |
| `APP-UPDATES-02` | 非正式环境无网络更新并显示真实原因 |
| `APP-UPDATES-03` | 手动检查、独立自动检查行、默认关闭、24 小时周期和显式安装 |
| `APP-UPDATES-04` | HTTPS、EdDSA、Developer ID、公证、签名 Feed 和解压前验证 |
| `APP-UPDATES-05` | Stable-only、macOS 14、产品 Build 归 1 与内部序号单调递增 |
| `APP-UPDATES-06` | Sparkle 嵌套组件由内到外签名且均为 Universal |
| `APP-UPDATES-07` | 两个正式版本完成真实客户端 N → N+1 检查、下载、替换与重启 |
| `APP-UPDATES-08` | 精确版本显式准入；未批准默认排除 |

`APP-UPDATES-01...06/08` 已由 0.3.5 和 0.3.6 发布链验证；尚未从真实 0.3.5
客户端独立记录到 0.3.6 的完整安装操作，因此 `APP-UPDATES-07` 和本规格
保持 `Verifying`。这不改变两个版本各自已经 Released 的事实。
