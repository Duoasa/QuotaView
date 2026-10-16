# QuotaView WidgetKit 契约

> 文档编号：`QV-DESIGN-WIDGET-001`
>
> 规格状态：`Accepted`
>
> 交付状态：`Released`（0.2.1 首发；0.3.1 Build 2 修复共享容器）
>
> 平台：macOS 14+

本文只在修改 Widget Target、共享快照、App Group 或 Widget 布局时读取。
版本和发布事实以生产配置与 `VERSION_HISTORY.md` 为准。

## 架构与边界

```text
官方 Provider → 主应用 → 脱敏快照 → App Group JSON → Widget Extension
```

- 主应用负责采集、可用性判断、投影、原子写入和内容变化后的 Timeline
  重载；Extension 只解码快照、判断过期并渲染；
- Widget 不调用 Provider、不访问凭据/Keychain/网络/历史库、不执行账户写
  操作，也不依赖主应用内存；`widgetURL` 不携带账户、Token 或授权；
- `QuotaViewWidgetContract` 只依赖 Foundation；Extension 使用
  `APPLICATION_EXTENSION_API_ONLY = YES`，不链接 `QuotaViewCore` 的进程或
  RPC 实现；
- 当前只提供 Small 与 Medium Usage Widget，不提供 Large、交互写操作、
  Provider 选择、历史/费用专用 Widget 或 Widget 直接刷新。

## 生产映射

| 项目 | 当前值 |
|---|---|
| Team | `BUUH229D5Q` |
| App Bundle ID | `com.quotaview.menubar` |
| Widget Bundle ID | `com.quotaview.menubar.widget` |
| App Group | `BUUH229D5Q.com.quotaview.shared` |
| Contract | `Sources/QuotaViewWidgetContract/WidgetSnapshot.swift` |
| 主应用 Writer | `Sources/QuotaView/QuotaViewWidgetSnapshotWriter.swift` |
| Extension | `Sources/QuotaViewWidget/QuotaViewWidget.swift` |
| 配置 | `Configs/App.xcconfig`、`Configs/Widget.xcconfig`、`Support/*.entitlements` |

主应用与 Extension 必须使用同一 Team 与 App Group entitlement；主应用保持
非 Sandbox，Extension 保持 Sandbox。不得为共享容器顺便改变该发布权限模型。

## 快照契约

Schema 1 顶层字段为：`schemaVersion`、`generatedAt`、`expiresAt`、
`updatedAt`、`localeIdentifier`、`availability` 和可选 `provider`。
Provider 只包含显示名、归一方案、主额度窗口、最多三个辅助指标和可选重置
次数，不编码完整 ProviderSnapshot。

- `availability` 只有 available/unavailable；最新请求失败、Provider 关闭或
  从未成功时写 unavailable 且 provider 为空，即使内存有旧快照也不冒充当前；
- 缺失字段保持空，不伪造零；Extension 对过期、文件不存在、损坏和未知
  schema 均显示稳定不可用状态；
- 快照寿命 15 分钟，Timeline 最短重读间隔 5 分钟；Widget 外观跟随系统，
  语言使用快照中主应用解析后的 locale；
- JSON 目标小于 16 KiB，硬上限 64 KiB；过滤账户、组织 ID、凭据、原始
  RPC、Prompt、路径、授权、完整历史和不显示字段；
- 写入 `QuotaViewWidgetSnapshot.json` 使用原子替换；只在影响显示的内容
  签名变化时请求 Timeline reload，不因倒计时每秒变化重复写入。

新增可选字段可保持 schema；删除、改名、单位或语义变化必须升级 schema，
并在主 App 与 Extension 同一版本中协调。

## 显示契约

- 支持 Small/Medium，使用 WidgetKit 系统容器和外观，不复刻主面板 Liquid
  Glass；系统内容边距关闭后内部统一 16 pt；
- Small 显示主周期剩余、订阅、进度和重置；Medium 右侧增加 Credits、最近
  一天、30 日/累计等当前可用指标；不存在的指标使用不可用语义；
- 布局、Asta Sans 字号、进度条几何、订阅映射和颜色必须遵守 `AGENTS.md`
  的 Widget 章节；文本支持中英文并提供 VoiceOver；
- 首次使用、过期、损坏、未知 schema 与 App Group 不可用都使用稳定空态，
  不崩溃、不显示旧数据为当前值。

## Requirement

| ID | 要求 |
|---|---|
| `WIDGET-01` | 单向脱敏快照；Extension 无采集、凭据、网络和写操作 |
| `WIDGET-02` | App/Extension 同 Team、App Group、版本与 Universal 架构 |
| `WIDGET-03` | Schema、大小、过期、损坏和未知版本安全降级 |
| `WIDGET-04` | 原子写入、稳定内容签名和受控 Timeline 重载 |
| `WIDGET-05` | Small/Medium 几何、本地化、VoiceOver 与不可用语义 |

真实共享容器、Developer ID、公证/Staple 和回下载验证已在 0.3.1 Build 2
完成；证据见 [`VERSION_HISTORY.md`](../../VERSION_HISTORY.md#031-build-2)。

## macOS 27 字体归档兼容（2026-10-15）

`WIDGET-05` / `Accepted / Verifying`：WidgetKit 将视图交给独立系统进程渲染，传入字体必须保留可重建的来源信息。Widget 扩展使用随包 Asta Sans 文件的 Core Text descriptor，校验 PostScript 名、准确来源 URL 与必要字形；复制到目标字号后仍保留 URL。缺失、损坏或错误字重文件降级系统字体。主应用继续使用经过验证的内存字体，不按名字选取用户安装字体。

本机 macOS 27 日志确认正式 Build 2 的时间线生成成功，而 NotificationCenter 解码 timeline 和 placeholder 报 `CodablePlatformFont.invalidFont`、继发 `badTimelineData`。旧内存字体三种字重均缺少 `kCTFontURLAttribute`；文件 descriptor 保留地址。本机证据不代表所有设备或全新安装均复现。

0.8.2 Build 10 / 内部 74 已更新开发包；正式 `/Applications/QuotaView.app` 未替换。字体来源与重建检查不能证明 WidgetKit 宿主实际渲染通过；需安装含修复的扩展后，由用户检查 Small/Medium、占位/不可用/有效值、浅深色和系统桌面样式。运行与测试证据 `.build/widget-font-20261015/`，合入结果见 [Handoff](../../HANDOFF.md)。

后续实机验收：用户授权本机签名安装 0.8.2 Build 10 后，系统重新加载对应扩展及字体，03:10:13 新时间线读取成功，用户明确“显示了”。本机 Medium 桌面恢复已确认；其他机器、Small 与不同外观/数据状态未据此宣布通过。旧安装完整备份，未公证或公开发布，签名/运行证据同上。PR #100 源码已合入 main，PR/main CI 均通过，具体提交与证据见 Handoff。
