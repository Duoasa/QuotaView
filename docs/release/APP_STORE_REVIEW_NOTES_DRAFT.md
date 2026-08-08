# QuotaView 1.0.0 App Review Notes 草案

状态：`Draft / Do Not Submit`

以下外部门禁完成后，才可移除占位符并粘贴到 App Store Connect：

- Paid Apps Agreement 生效且美国基准价格为 `USD 4.99`；
- QuotaView for Codex 固定 Release 已发布并完成公开复验；
- Privacy / Support URL 已公开，审核联系人已补齐；
- 最终 Distribution Archive 和产品所有者验收通过。

## 可粘贴英文正文

```text
QuotaView is a sandboxed, paid-upfront macOS menu-bar companion for Codex. It
does not create a QuotaView account and contains no in-app purchase.

SETUP AND CORE USAGE

1. Install and sign in to the separately installed official Codex app.
2. Install and enable the public QuotaView for Codex plugin from the fixed
   release below. Trust its hooks if Codex asks.
3. In QuotaView, open Settings > Connection & Island and select the PLUGIN_DATA
   folder using the macOS system picker.
4. Ask the plugin to refresh usage, or start a Codex task, then refresh
   QuotaView. The menu panel and Widget show the sanitized usage snapshot.

QuotaView has no OpenAI OAuth client, receives no OpenAI credentials, and does
not read browser cookies, ~/.codex/auth.json, or another app's Keychain. The
official codex app-server owns authentication and service network requests.
The plugin calls only account/rateLimits/read and account/usage/read over its
local JSONL stdio interface. Raw responses remain in process memory and are
never written to disk.

The allowlisted usage.json contains only plan name, primary used percentage,
window duration/reset time, Credits availability/balance, limit state,
lifetime tokens, and the newest daily token bucket. It excludes credentials,
email, account/workspace identifiers, reset-credit inventory, prompts, files,
responses, reasoning, and all other fields.

BUSINESS MODEL

QuotaView is a USD 4.99 paid-upfront Mac App Store download. Every bundled
feature, including Codex Island, is included. There is no subscription,
license key, trial gate, restore-purchase flow, or separate unlock.

CODEX ISLAND

Start a Codex task, submit a prompt, run a tool, and complete the response.
Sanitized local lifecycle events drive the Island independently of usage
snapshot availability. The plugin retains at most 512 events containing
one-way session/turn hashes, final workspace folder name, coarse tool category,
state, timestamps, sequence, version, and bridge health. It excludes prompts,
commands, full paths, file contents, tool I/O, responses, reasoning, account
data, tokens, cookies, and credentials.

PLUGIN

Public repository: https://github.com/Duoasa/QuotaView-for-Codex
Fixed release/tag: v1.0.0-preview.7
Installation instructions: https://github.com/Duoasa/QuotaView-for-Codex/releases/tag/v1.0.0-preview.7

QuotaView does not download, install, update, or execute the plugin. It only
receives security-scoped read access to the user-selected folder. All UI and
protocol validation code is in the submitted bundle. QuotaView has no outbound
network-client entitlement.

Privacy Policy and Support are linked from Settings > General and App Store
metadata. If any step is unclear, contact: [REVIEW CONTACT].
```

## 提交前逐项替换

- 固定插件 tag 与公开安装地址已经替换为经过复验的 `v1.0.0-preview.7`；
- `[REVIEW CONTACT]`：可在审核期间及时响应的姓名、邮箱和电话；
- Notes 必须控制在 App Store Connect 当时的字符/字节限制内；
- 审核人员如需 OpenAI/Codex 账号，应在官方 Codex 中登录，不得提供或暗示
  QuotaView 自有登录凭证。

## 审核风险

- 该架构不再依赖未获支持的第三方 OpenAI OAuth，但仍是商业 App 展示第三方
  Codex 数据；Content Rights 与 Guideline 5.2.2 仍需如实填写，Apple 可能
  要求权利或授权说明；OpenAI Support Case `12874203` 只证明不提供第三方
  OAuth，不等同于商业展示许可。
- 外部 Codex 和公开插件是审核复现依赖。QuotaView 不下载或执行插件，仅消费
  用户选择的本地数据；是否满足 Guideline 2.5.2 仍由 App Review 判断。
- 固定插件 Release、干净环境复现或官方 Codex 登录任一不可用，都应暂停提交。

## 官方参考

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple App Review preparation](https://developer.apple.com/app-store/review/)
- [Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price)
