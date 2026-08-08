# QuotaView App Store 初步改造本机审核单

> 适用版本：QuotaView `1.0.0 (Build 4)` / `appstore`
>
> 代码基座：`0.3.1 (Build 2)` / `v0.3.1-build.2`
>
> 更新日期：2026-08-08
>
> 当前阶段：初步改造完成，等待产品所有者手动审核与修改

## 1. 本轮交付边界

本轮只交付可在本机运行和审查的初步改造，不执行以下外部操作：

- 不上传 App Store Connect；
- 不提交 App Review；
- 不发布新的主 App 或插件版本；
- 不自动 push、建 PR、创建 tag 或 Release；
- 不把本机审核候选写成最终提交包或已发布版本。

已有自动验证证据继续作为代码与构建基础。本轮不为了扩大覆盖面临时新增
测试代码，也不重复执行已经有充分证据的整套回归；交付前只做当前源码所需
的构建与静态检查。新增界面、视觉、交互和真实业务状态由产品所有者运行后
手动审核。

## 2. 推荐审核方式

使用 Xcode 打开：

```text
/Users/sukduoasa/Documents/QuotaView-AppStore/QuotaView.xcodeproj
```

选择 `QuotaView` Scheme、`My Mac`，然后 Run。该 Debug Scheme 会：

- 直接提供全部内置功能，不挂载 StoreKit 商品或购买门禁；
- 使用“官方 Codex + 公开伴侣插件 + 用户所选目录只读”数据链路；
- 保持 App Sandbox、App Group 和用户所选目录只读权限；
- 不包含 Network Client，不启动 `codex` CLI/app-server、Shell、Runtime、
  Helper、Terminal、Git 或其他子进程；用户点击“打开 Codex”时只通过
  `NSWorkspace` 打开官方 GUI App。

当前源码已经生成新的 Universal 无签名 Release 审核构建：

```text
/private/tmp/QuotaView-Build4-20260808/QuotaView.app
```

该 App 来自本地脱敏快照架构的当前源码，为 `1.0.0 (Build 4)` / `appstore`，
包含 `arm64 + x86_64`。它使用无签名构建配置验证编译结果；实际交互审核仍
建议按上方步骤从 Xcode Run，由 Xcode 完成本机开发签名。这不是 Distribution
Archive，也不是上传候选。

QuotaView 已移除候选 OAuth Client、`quotaview://oauth/openai`、Keychain
账号凭证和 `wham` 接口。Debug 与 Release 使用同一脱敏本地快照边界，不得
以 Debug 配置恢复旧登录或非公开 HTTP 路线。

## 3. 手动审核顺序

### A. 基线与主功能

- 菜单栏入口正常，主面板宽度保持 `274 pt`；
- 全部当前内容显示时高度为 `373 pt`；
- 基础额度、Credits、最近一天 Token、累计 Token、方案和更新时间布局稳定；
- 不再出现额度重置入口、详情页、确认层、设置开关或可用重置次数；
- 无有效数据时显示破折号或不可用状态，不显示虚假的 `0%`；
- Small / Medium Widget 能读取主 App 写入的脱敏快照。

### B. 官方 Codex 用量连接

- 首次使用且没有有效用量快照时，用量概览区域显示“连接官方 Codex”快捷
  入口，而不是空图表；
- 点击快捷入口后状态栏面板关闭，设置窗口打开并选中“连接与灵动岛”，不产生
  重复窗口；
- 设置页明确提示在另行安装的官方 Codex 中登录，并可打开官方 Codex；
- 选择插件 `PLUGIN_DATA` 后，已配对但无快照时显示等待官方 Codex 登录或刷新；
- 有效 `usage.json` 到达后，快捷入口自动替换为原用量图表；关闭“周期用量
  概览”时，连接后继续遵循该显示偏好；
- 重启 App 后可从 security-scoped bookmark 重新读取同一安装实例快照；
- 断开目录后旧主面板、Widget、活动游标和诊断状态立即清除；
- 快照过期、Schema 不兼容、安装 ID 不匹配、字段越界或包含 `email` 等未知
  字段时拒绝使用，不伪造可用状态；
- Token、Cookie、邮箱、账号/工作区 ID、原始 RPC 响应、额度重置券和错误
  正文不出现在快照、Widget 或可见日志中；
- QuotaView 不读取 `~/.codex/auth.json`、Cookie 或其他 App Keychain，也不
  使用 OAuth、`wham`、WebKit、网页解析、Runtime 或 CLI 回退。

### C. Codex 灵动岛功能边界

- 额度、Credits、菜单栏、Widget 和 Codex 灵动岛全部包含在 QuotaView 中；
- 设置页不再出现购买、恢复购买、交易验证或锁定状态；
- Xcode 与 TestFlight 构建无需开发者购买即可测试全部功能；
- 灵动岛只依赖公开插件、Hooks 信任、目录授权和有效事件；
- 用量快照不可用时，插件活动事件仍可独立驱动灵动岛。
- “连接与灵动岛”页的灵动岛开关默认开启；关闭后现有灵动岛立即隐藏，
  最近用量、连接状态和最近事件继续更新；重新开启后新活动可再次展示。

### D. QuotaView for Codex 插件桥

- 安装指南只打开公开 HTTPS 页面，QuotaView 不下载、安装或执行插件；
- 在官方 Codex 内完成插件安装、启用和 Hooks 信任；
- 由插件调用官方 `codex app-server` 的两个只读方法刷新 `usage.json`，确认
  原始响应不落盘，插件不直接发送 HTTP；
- 在目录选择面板中手动授权插件 `PLUGIN_DATA`，QuotaView 只保存只读
  security-scoped bookmark；
- 检查未配置、等待目录授权、已配对等待事件、已连接、stale、需要重新授权、
  协议不兼容和数据异常状态；
- 断开后 App 只删除自身 bookmark 与游标，不删除插件目录或修改 Codex；
- 收到真实插件事件时，检查灵动岛最大态、紧凑态和隐藏；
- 完成后 `20` 秒紧凑、`120` 秒隐藏，新活动立即重新展开。

当前本机可用于配对的插件数据目录为：

```text
/Users/sukduoasa/.codex/plugins/data/quotaview-quotaview-preview
```

目录可能随 Codex 的插件安装实例变化；应以插件实际提供的 `PLUGIN_DATA`
为准，不在 App 中硬编码该路径。

### E. 通用页与沙盒边界

- 通用页显示 Bundle 中的 `1.0.0 (Build 4)`，没有检查更新或 Sparkle；
- 隐私政策和支持页在状态仍为 `draft` 时保持禁用并显示真实说明；
- App 不申请辅助功能、屏幕录制或用户目录广泛访问权限；
- 主 App 只具有 Sandbox、App Group 和用户所选目录只读权限，不具有
  Network Client；
- Widget 只具有 Sandbox 与同一 App Group。

## 4. 视觉与交互矩阵

以下项目在产品所有者明确确认前统一保持“等待用户验收”：

- 外观：浅色 / 深色 / 跟随系统；
- 材质：磨砂 / 清透；
- 语言：简体中文 / English / 跟随系统；
- 用量连接：未配对 / 等待官方 Codex 登录或刷新 / 有效 / stale / 不兼容 /
  目录重新授权 / 错误；
- 付费模式：设置页无 IAP 或功能锁，全部内置功能可直接使用；
- 插件：未配置 / 等待授权 / 等待事件 / 已连接 / stale / 重新授权 /
  不兼容 / 数据异常；
- 交互：Hover / Pressed / Disabled / 键盘 / Escape / 外部点击；
- 辅助功能：Reduce Motion / Increase Contrast / VoiceOver；
- Widget：Small / Medium、浅色 / 深色、中英文、有效 / stale / 不可用。

## 5. 当前不属于本机初审完成条件的事项

以下事项保留为正式提交前门禁，不阻塞本轮把初步改造交给产品所有者审核：

- 第三方内容权利与品牌展示评估，以及 Apple 要求时可提供的来源和架构说明；
- Paid Apps Agreement 生效，并在 App Store Connect 将美国基准价格配置为
  `USD 4.99`，复核其他地区自动换算价格；
- 隐私政策、支持页和受监控支持邮箱正式公开；
- 发布支持用量快照的固定插件 Release，并从全新 Codex 用户环境完成官方
  登录、插件安装、Hooks 信任、配对、真实用量、真实事件、卸载和重装；
- 所有外部门禁关闭后重新生成最终 Distribution `.pkg`；
- 经产品所有者单独授权后上传并提交 App Review。

## 6. 审核反馈格式

产品所有者可以按以下格式回传问题，后续只针对确认项修改：

```text
页面/状态：
当前表现：
期望表现：
语言与外观：
是否阻塞继续审核：
截图或复现步骤：
```
