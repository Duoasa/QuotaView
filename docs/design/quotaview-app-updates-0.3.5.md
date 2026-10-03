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

- 关于页“检查更新…”调用 Sparkle 标准界面；自动检查是独立原生设置行，
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
- `0.3.5 Build 5`、`0.3.6 Build 2`、`0.3.7 Build 1`、`0.4.1 Build 1`、
  `0.4.2 Build 1` 与 `0.4.3 Build 1` 均已分别明确获准并
  完成发布；详细资产证据只在
  [`VERSION_HISTORY.md`](../../VERSION_HISTORY.md) 保存。

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

`APP-UPDATES-01...06/08` 已由 0.3.5、0.3.6 和 0.3.7 发布链验证；尚未从
真实旧版客户端独立记录一次完整 N → N+1 检查、下载、替换与重启，因此
`APP-UPDATES-07` 和本规格保持 `Verifying`。这不改变各版本已经 Released
的事实。

## 2026-10-04 0.7.5 发行前准备

候选为0.7.5 / 显示Build2 / 内部51，预期tag `v0.7.5-build.2`、
ZIP `QuotaView-v0.7.5-build.2.zip`。用户明确要求先验收构建，再决定是否Release；
本轮不授权正式Release或公开appcast更新。

显式Distribution配置选择正式Bundle/Widget/AppGroup，默认构建保持独立开发
身份。应用启动恢复唯一更新控制器的start调用，控制器现有Debug/开发/签名
门禁保持。appcast生成前先校验实际ZIP与源配置的版本、身份、Feed、公钥、
正式Developer ID及Staple，再访问签名钥匙。仅本次候选ZIP作为生成输入，
已有Feed提供历史条目，避免旧ZIP被本次tag前缀重新命名。

fresh正式身份Universal无签名构建、App/Widget版本与架构/资源核对通过；
现有线上Feed与回滚资产只读验证、临时负向门禁结果保存在
`.build/075-appcast-preparation/readiness.json`。已验签历史Feed另存于
`.build/075-appcast-preparation/updates/appcast.xml`，发行时配合最终签名公证ZIP。
当前无签名候选不进入Feed；正式签名、公证、回下载与Feed发布在用户具体
授权后完成。运行交付和视觉状态见Handoff当前节。

## 2026-09-11 Build 3 update admission

The owner explicitly authorized 0.4.7 Build 3 / internal 22, tag
`v0.4.7-build.3`, archive `QuotaView-v0.4.7-build.3.zip`, for main,
GitHub Stable, README and appcast. Publish after signing, notarization,
immutable archive and public-download checks. The feed will move from
19/18/17 to 22/19/18 and continue excluding withdrawn internal 21.

## 2026-09-11 Build 3 发布完成

0.4.7 Build 3 / internal 22 已通过 PR #50 合并 main，正式发布并进入 appcast。
最终发布提交、ZIP、哈希、签名、公证与公开回下载证据见
[版本历史](../../VERSION_HISTORY.md#当前最新版本)。两项 opt-in 实测已补跑通过。
main CI 首次因测试夹具 5 秒启动窗口未生成端口文件失败，同提交重跑通过；未更改断言。
Build 2 转为草稿，公开时间线不再显示；其 tag / 资产保留且继续排除在 Feed 之外。

### 2026-10-04 Build3 发行候选身份

长会话恢复作为同版本下一源码迭代，当前候选为0.7.5/显示Build3/内部52，唯一预期tag/ZIP为 `v0.7.5-build.3` / `QuotaView-v0.7.5-build.3.zip`。fresh正式身份Universal Release无签名构建与App/Widget版本、资源核对通过；实际无签名候选再次被appcast生成器在私钥访问前拒绝，未生成/发布Feed。Build2预检保留作历史证据，已验签Stable回滚基线保持。Release与该精确候选的公开appcast仍等待用户后续决定。

## 2026-10-04 Build3 正式准入授权

用户明确要求推送 GitHub、发布最新版、合并 main 并推送 appcast，精确准入为 **0.7.5 / Build3 / 内部52**，`v0.7.5-build.3` / `QuotaView-v0.7.5-build.3.zip`。这取代上文历史候选的待授权状态。按正式签名、公证/Staple、不可变资产、公开回下载、旧版公钥及签名 Feed 验证顺序执行；目标序列为52 → 49 → 38。完成证据回填版本历史。

## 2026-10-04 Build3 发布完成

0.7.5 Build3 / 内部52 已经PR #75合并main，发布为GitHub Stable / Latest，签名Feed序列为52 → 49 → 38。正式Developer ID、公证/Staple、Gatekeeper、解压启动、GitHub回下载逐字节比较、旧稳定版公钥校验ZIP及线上Feed全部通过；历史资产URL及签名保持。完整不可变资产和CI/Pages证据见[版本历史](../../VERSION_HISTORY.md#当前最新版本)。`APP-UPDATES-07`真实客户端N → N+1安装仍待独立记录，规格整体保持Verifying。
