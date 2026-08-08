# QuotaView Support

Status: Draft

QuotaView is a lightweight macOS menu-bar companion for viewing the official
Codex user's sanitized usage snapshot and local task activity. This page
covers QuotaView 1.0.0 for the Mac App Store.

## Contact

- Email: [SUPPORT EMAIL BEFORE PUBLICATION]
- Issue tracker: [QuotaView Issues](https://github.com/Duoasa/QuotaView/issues)

Do not include passwords, tokens, cookies, complete account responses,
prompts, source code, or other confidential information. A macOS version,
QuotaView version/build number, plugin version, and concise visible error are
normally sufficient.

## Quota data is unavailable

1. Sign in through the separately installed official Codex application.
2. Install and enable the public QuotaView for Codex plugin.
3. In QuotaView, open Settings > Codex Connection and select the plugin's
   `PLUGIN_DATA` folder using the macOS picker.
4. Ask the plugin to refresh usage, or start a Codex task and then refresh
   QuotaView.

QuotaView does not provide a separate OpenAI login or store OpenAI credentials.
If official Codex reports an authentication error, complete sign-in there and
retry. Do not send credentials or raw responses in a support request.

## Widget data is stale

Open the QuotaView menu panel and refresh once, then wait for WidgetKit to
reload its timeline. The Widget receives only a sanitized display snapshot.

## Codex Island is not connected

Codex Island is included with QuotaView and requires the public QuotaView for
Codex plugin in the separately installed Codex app. Follow Settings > Codex
Connection. QuotaView does not download, install, update, or execute the
plugin. Activity events can drive the Island independently of whether a usage
snapshot is currently available.

## Purchases

QuotaView is a paid-upfront Mac App Store download. It has no in-app purchase,
subscription, restore-purchase flow, or separate Codex Island unlock.

## Privacy

Read the [QuotaView Privacy Policy](PRIVACY.md) for the local snapshot,
activity-event, Widget, folder-permission, and official Codex boundaries.

---

# QuotaView 支持

状态：草案

QuotaView 是轻量的 macOS 菜单栏 Codex 伴侣应用，用于显示官方 Codex
用户的脱敏用量快照和本地任务活动。本页适用于 Mac App Store 版
QuotaView 1.0.0。

## 联系方式

- 邮箱：[SUPPORT EMAIL BEFORE PUBLICATION]
- Issue Tracker：[QuotaView Issues](https://github.com/Duoasa/QuotaView/issues)

请勿提供密码、Token、Cookie、完整账号响应、提示词、源代码或其他机密信息。
通常只需提供 macOS 版本、QuotaView 版本/Build Number、插件版本和精简的
可见错误说明。

## 无法读取额度数据

1. 在另行安装的官方 Codex 应用中完成登录；
2. 安装并启用公开的 QuotaView for Codex 插件；
3. 打开 QuotaView“设置 > Codex 连接”，通过 macOS 选择器选择插件的
   `PLUGIN_DATA` 目录；
4. 让插件刷新用量，或启动一次 Codex 任务后再刷新 QuotaView。

QuotaView 不提供第二套 OpenAI 登录，也不保存 OpenAI 凭证。如果官方 Codex
报告身份验证错误，请在官方 Codex 中完成登录后重试。不要向支持请求附上
凭证或原始响应。

## 小组件数据未更新

打开 QuotaView 菜单面板手动刷新一次，然后等待 WidgetKit 重新加载时间线。
小组件只接收脱敏的显示快照。

## Codex 灵动岛未连接

Codex 灵动岛已包含在 QuotaView 中，需要在另行安装的 Codex 应用中启用公开
的 QuotaView for Codex 插件。请按照“设置 > Codex 连接”操作。QuotaView
不会下载、安装、更新或执行插件。即使用量快照暂不可用，活动事件仍可独立
驱动灵动岛。

## 购买

QuotaView 是 Mac App Store 一次性付费下载，不包含 App 内购买、订阅、恢复
购买流程或单独的 Codex 灵动岛解锁。

## 隐私

有关本地快照、活动事件、Widget、目录权限和官方 Codex 边界，请阅读
[QuotaView 隐私政策](PRIVACY.md)。
