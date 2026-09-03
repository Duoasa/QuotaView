# QuotaView 0.4.5 Build 1 发布规格

> Spec ID：`QV-RELEASE-0.4.5-001`
>
> 状态：`Accepted / Released`
>
> 日期：2026-09-04
>
> 发布基线：`0.4.3 Build 1` / `v0.4.3-build.1`
>
> 目标版本：`0.4.5 Build 1` / Sparkle 内部序号 `17`

## 用户结果

新版 Codex 安装 QuotaView 后无需配置 Hook 即可读取实时任务状态；灵动岛
同时增加本次 turn Token、完成额度回执、悬停透明与长时间等待确认提醒。

## 发布范围

1. 只读本地任务流主通道，以及共享 App Server 与签名 Hook 兼容回退；
2. 原生计划状态、真实任务终态、本次 turn Token 与隐私安全投影；
3. 量子噪点单一样式、运行态排版、完成态回执和额度环；
4. 80% Hover 透明态、黄色等待确认提醒与紫蓝青完成反馈；
5. 中英文 README、0.4.5 产品图与单份英文 GitHub Release Notes；
6. Universal Developer ID 构建、Apple 公证、GitHub Latest 与 Stable appcast。

## 不变边界

- 保持单任务灵动岛、macOS 14+、Apple Silicon + Intel、App Group 与
  WidgetKit 契约；
- 本地任务桥只读，不启动 Codex，不修改 `~/.codex`，不保存任务正文；
- Activity Hook 只作为旧环境兼容回退，不删除用户已有 Hook 配置；
- 不迁入多任务 Preview，不调用真实额度重置接口。

## Requirement

| ID | 要求 |
|---|---|
| `RELEASE-0.4.5-01` | App 与 Widget 为 Marketing 0.4.5、产品 Build 1、Sparkle 内部序号 17，tag 与资产分别为 `v0.4.5-build.1`、`QuotaView-v0.4.5-build.1.zip` |
| `RELEASE-0.4.5-02` | 完整 `swift test`、Universal Release、资源、版本、架构、隐私搜索和 `git diff --check` 全部通过 |
| `RELEASE-0.4.5-03` | 最终 App 使用 Developer ID 与 Hardened Runtime，Apple 公证 Accepted 并完成 Staple；ZIP 回解压后再次通过签名、Gatekeeper、版本与架构验证 |
| `RELEASE-0.4.5-04` | GitHub Release 为非 Draft、非 Pre-release、Latest；Release Notes 只有一份英文源文，README 双语下载入口指向同一正式资产并显示 0.4.5 产品图 |
| `RELEASE-0.4.5-05` | Stable appcast 使用 Sparkle EdDSA 签名并在线验证；GitHub 回下载资产与本地公证包逐字节一致 |
| `RELEASE-0.4.5-06` | `HANDOFF.md`、`VERSION_HISTORY.md`、SDD 注册表和功能规格只在对应线上事实完成后标记 `Released` |

## 当前状态

- 产品所有者已批准 0.4.5 Build 1 发布；
- `swift test` 130 项通过、0 失败；PR #42 CI 通过并合并到 `main`，发布提交
  与 tag commit 为 `75913c07e4457b5f6451f286522799d36982ff0c`；
- Universal Developer ID Release 构建通过；App、Core、Widget 与 Activity
  Hook 均为 `x86_64 arm64`，版本为 Marketing `0.4.5`、内部 `17`、产品
  Build `1`；
- 正式资产 `QuotaView-v0.4.5-build.1.zip` 为 `13,477,643 bytes`，SHA-256
  `d5308880d9dc096e46cdbf715db414ae79a4bc92a1dcc4f433d315a6a7bd7e5a`；
- Developer ID 证书 SHA-1 为
  `E52D0A9C7C377AF77C484155CC0CFCFB27D949D3`，Apple 公证 Accepted 并已
  Staple；Submission `67ae8361-068b-4adf-aecf-de2f2b174e07`；
- GitHub Release 已发布为 Latest、非 Draft、非 Pre-release；回下载资产与
  本地公证包逐字节一致，并在宿主环境通过嵌套签名、Staple、Gatekeeper、
  版本、资源与四目标双架构复核；
- 中英文 README 已使用 `Resources/QuotaView-0.4.5-Activity-Bridge.png`，
  下载入口指向正式资产；Release Notes 以
  `docs/releases/QuotaView-0.4.5-build.1.md` 为单份英文源文；
- Stable appcast 由 `gh-pages` 提交
  `9fc9745a9464f42d890c119a13dabf87896d09a5` 发布，线上 Feed SHA-256 为
  `d4e1d5a218742b743c04305c3ab29e27bbfaece1f0f4b7d7ab788b16bb6a3b01`；
  线上文件与本地签名文件逐字节一致且 EdDSA 验证通过；
- 完整深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 交叉
  矩阵未单独记录为全量通过。
