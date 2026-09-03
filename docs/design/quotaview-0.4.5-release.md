# QuotaView 0.4.5 Build 1 发布规格

> Spec ID：`QV-RELEASE-0.4.5-001`
>
> 状态：`Accepted / Publishing`
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
- 开发验证为 `swift test` 130 项通过、0 失败，Universal 无签名构建、
  ad-hoc 严格签名校验和干净副本启动通过；
- Developer ID、公证、Release、回下载与 Stable appcast 正在执行；
- 完整发布事实将在远端验证完成后写回本规格、`VERSION_HISTORY.md` 与
  `HANDOFF.md`。
