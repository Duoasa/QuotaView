# QuotaView for Codex v1.0.0-preview.7 Release 记录与验收单

状态：`Published Pre-release / Fixed Tag`

发布日期：2026-08-08

## 固定身份

| 项目 | 当前值 |
|---|---|
| 插件版本 | `1.0.0-preview.7` |
| Bridge Protocol | `1` |
| Annotated tag | `v1.0.0-preview.7` |
| Tag object | `8d227d8bbc17a3341e8715b12ab51a1281d17df0` |
| Commit | `4fc63ec5b680ee62d27ffe1a458680ab023315e3` |
| GitHub Release | `https://github.com/Duoasa/QuotaView-for-Codex/releases/tag/v1.0.0-preview.7` |
| Release 类型 | Pre-release，非 Draft |

该 tag 不得移动、覆盖或重建。后续修复必须使用更高插件版本和新 tag。

## 公开资产

| 项目 | 当前值 |
|---|---|
| 文件名 | `QuotaView-for-Codex-v1.0.0-preview.7.tar.gz` |
| 大小 | `367,897 bytes` |
| SHA-256 | `095924284087b7e0b45bf7a26fdbe7b6ca441e45f212b4dd8a040a99383c5a2b` |
| 下载地址 | `https://github.com/Duoasa/QuotaView-for-Codex/releases/download/v1.0.0-preview.7/QuotaView-for-Codex-v1.0.0-preview.7.tar.gz` |

本机从固定 tag 连续构建两次得到字节一致的资产。GitHub Actions CI artifact
与本机资产大小和 SHA-256 一致；GitHub Release 公开回下载后再次逐字节一致。

## 自动与公开验证

- Bridge、JSON、Shell 语法和敏感字段泄漏负向测试通过；
- 新建隔离 `CODEX_HOME` 后完成首次安装、卸载、重装和缓存逐文件比对；
- 匿名 HTTPS 按固定 tag clone 到提交
  `4fc63ec5b680ee62d27ffe1a458680ab023315e3`；
- 匿名 clone 再次通过 Bridge 测试和隔离安装/卸载/重装；
- tag push 的 `Test plugin bridge` 工作流通过：
  `https://github.com/Duoasa/QuotaView-for-Codex/actions/runs/31259292618`；
- 固定资产 workflow_dispatch 通过：
  `https://github.com/Duoasa/QuotaView-for-Codex/actions/runs/31259388434`；
- 当前本机受信任安装实例报告协议 `1`、插件 `1.0.0-preview.7`、本地事件和
  脱敏用量快照可用，认证由官方 Codex 管理；
- 当前安装的插件源码排除 Codex 主机管理的运行时目录后，与固定 tag 逐文件
  一致；没有读取或记录本地快照内容、账号信息或凭证。

首次 tag push 的固定资产 workflow 在 checkout 后未保留 annotated tag 对象，
因而在内容构建前失败。远程 tag 对象和指向提交始终正确且未移动。默认分支以
提交 `08ac9017422c1764ebdce2449a405e7628106937` 增加显式 tag fetch，随后针对
同一固定 tag 的 workflow_dispatch 完整通过。该 CI 修复不改变 Preview 7
tag 内容或资产。

## App 对接结论

- QuotaView `1.0.0 (Build 4)` 使用 Bridge Protocol v1；
- 主 App 的 `QUOTAVIEW_CODEX_PLUGIN_DISTRIBUTION_STATUS` 可设为 `released`；
- App Review Notes 固定到 `v1.0.0-preview.7` 和同一公开 Release URL；
- Preview 1、Preview 2/3 候选记录继续保留为历史，不得覆盖本记录；
- 完整 App Store 产品视觉矩阵、价格、公开 Privacy/Support 和最终提交包仍是
  主 App 的独立发行门禁。
