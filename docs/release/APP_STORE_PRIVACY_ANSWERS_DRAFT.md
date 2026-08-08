# QuotaView 1.0.0 App Privacy 答案草案

状态：`Draft / Revalidate Before Publish`

## 当前建议答案

在当前代码和服务边界不变的前提下，App Store Connect 建议选择：

| 问题 | 建议答案 | 依据 |
|---|---|---|
| Tracking | `No` | 无广告、归因、数据经纪、跟踪域名或跨 App/网站关联 |
| Data Collection | `No, we do not collect data from this app` | QuotaView 无后端、遥测、分析或第三方 SDK；提交 App 本身无网络客户端权限；所有快照和事件留在用户 Mac |
| Privacy Policy URL | `https://github.com/Duoasa/QuotaView/blob/main/PRIVACY.md` | 本地 [PRIVACY.md](../../PRIVACY.md) 已改为官方 Codex + 本地插件快照边界；提交前仍需补邮箱并公开 |
| Privacy Choices URL | `[OPTIONAL PUBLIC URL]` | 可链接到断开目录、清除本地状态和卸载插件说明 |

此处的 `No` 只适用于当前提交包和开发者的数据处理：QuotaView 不接收或
持久化服务器端数据。用户另行安装的官方 Codex 应用依据 OpenAI 自身条款
登录和联网；伴侣插件通过官方本地 `codex app-server` 取得只读结果，只把
白名单脱敏快照写到用户本机。提交前仍应按 App Store Connect 当时的问题
措辞复核；一旦加入任何后端、遥测、崩溃上报、第三方 SDK 或远程日志，必须
重新回答。

## 数据流清单

| 数据 | 位置/处理方 | 用途 | 保存与共享 |
|---|---|---|---|
| OpenAI 凭证 | 官方 Codex | 官方登录、刷新和服务访问 | QuotaView App、Widget、插件文件和 QuotaView 开发者均不接收 |
| 官方 Codex 原始 RPC 响应 | 官方 `codex app-server` 与插件进程内存 | 生成白名单快照 | 不落盘、不写日志、不发送给 QuotaView 服务器 |
| 脱敏 `usage.json` | 用户选择的本地 `PLUGIN_DATA` | 面板、菜单栏、Widget | 只含方案、主周期、Credits、触顶及有限 Token 汇总；不含身份或凭证 |
| Codex 活动事件 | 同一本地目录和 App 本地状态 | Codex 灵动岛 | 最多 512 条脱敏事件；不上传 |
| 目录 bookmark | App 沙盒容器 | 恢复用户授予的只读权限 | 不同步，可在设置中断开 |
| Widget 显示快照 | App Group | Widget 时间线 | 最小显示投影，不含凭证、原始响应或插件事件文件 |
| 偏好与刷新时间 | App 容器 / App Group | 界面和刷新调度 | 仅本机，不用于分析或广告 |

## Privacy Manifest 对照

当前 [PrivacyInfo.xcprivacy](../../Support/PrivacyInfo.xcprivacy) 声明：

- `NSPrivacyTracking = false`；
- 无 Tracking Domains；
- `NSPrivacyCollectedDataTypes` 为空；
- UserDefaults 使用理由 `CA92.1`；
- 文件时间戳使用理由 `3B52.1`。

`CA92.1` 只覆盖主 App 自身偏好和本地诊断；`3B52.1` 只覆盖用户通过系统
目录选择器明确授权后，对插件目录中文件元数据的安全校验。提交前必须扫描
主 App、Widget 和 Framework，并确认最终清单、App Privacy、公开政策和真实
行为一致。

配置状态保持 `draft` 时，“通用”设置页中的政策入口显示待发布。只有公开
URL 可访问、支持邮箱补齐，并把 `QUOTAVIEW_PRIVACY_POLICY_STATUS` 改为
`published` 后，提交门禁才可通过。发布正文还必须移除 Draft/草案状态行和
占位符。

## 公开政策必须包含

- QuotaView 是独立第三方 Codex 伴侣，不隶属于 OpenAI；
- QuotaView 无自有 OpenAI OAuth、不接收或保存 OpenAI 凭证；
- 官方 Codex 负责登录、凭证生命周期和网络请求；
- 插件只写白名单用量快照及最多 512 条脱敏活动事件；
- Widget 只接收最小显示快照；
- 用户选择目录、断开、清除和卸载方式；
- 付费 App 由 Mac App Store 处理，无 IAP；
- 无广告、跟踪、遥测和自有账号服务器；
- 支持邮箱、生效日期和政策变更方式。

## 必须改答的触发条件

- 加入 Sentry、PostHog、Firebase、登录 SDK 或任何遥测；
- 将用量、错误、账号标识、IP、事件或诊断发送到开发者后端；
- QuotaView App 恢复网络客户端权限或自有 OpenAI 登录；
- 插件把原始响应、凭证、账号身份或完整活动内容写入文件；
- 将上述数据写入 Widget/App Group；
- 引入广告、营销归因或跨产品关联。

## 官方参考

- [Apple App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Privacy reference](https://developer.apple.com/help/app-store-connect/reference/app-privacy/)
- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
