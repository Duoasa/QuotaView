# QuotaView 0.4.3 Build 1 发布规格

> Spec ID：`QV-RELEASE-0.4.3-001`
>
> 状态：`Accepted / Released`
>
> 日期：2026-09-03
>
> 发布基线：`0.4.2 Build 1` / `v0.4.2-build.1`
>
> 目标版本：`0.4.3 Build 1` / Sparkle 内部序号 `15`

## 用户结果

量子噪点在 Codex 状态换色时保持连续相位，不再产生纵向跳动；压缩上下文、
闪灭与完成段更清晰。进度条文字层级和完成辉光也更统一、易读。

## 发布范围

1. 量子噪点连续相位、细密闪灭、压缩上下文灰白可见性及完成态粒子覆盖；
2. 进度条任务标题与状态文字的两级不透明淡灰，以及增强后的操作流光；
3. 完成描边与呼吸光晕统一绿色基准，呼吸只改变外部光晕半径；
4. 简洁的中英文 README 与单份英文 GitHub Release Notes；
5. Universal Developer ID 构建、Apple 公证、GitHub Latest 与 Stable appcast。

## 不变边界

- 保持单任务灵动岛、进度估算、任务生命周期、AI 球和四种进度效果选择；
- 保持 `dropField` 持久化兼容，不改变用户现有样式偏好；
- 保持 macOS 14+、Apple Silicon + Intel、App Group 与 WidgetKit 契约；
- 不迁入多任务 Preview，不调用真实额度重置接口。

## Requirement

| ID | 要求 |
|---|---|
| `RELEASE-0.4.3-01` | App 与 Widget 为 Marketing 0.4.3、产品 Build 1、Sparkle 内部序号 15，tag 与资产分别为 `v0.4.3-build.1`、`QuotaView-v0.4.3-build.1.zip` |
| `RELEASE-0.4.3-02` | 完整 `swift test`、Universal Release、资源、版本、架构、隐私搜索和 `git diff --check` 全部通过 |
| `RELEASE-0.4.3-03` | 最终 App 使用 Developer ID 与 Hardened Runtime，Apple 公证 Accepted 并完成 Staple；ZIP 回解压后再次通过签名、Gatekeeper、版本与架构验证 |
| `RELEASE-0.4.3-04` | GitHub Release 为非 Draft、非 Pre-release、Latest；Release Notes 只有一份简洁英文源文，README 双语下载入口指向同一正式资产 |
| `RELEASE-0.4.3-05` | Stable appcast 使用 Sparkle EdDSA 签名并在线验证；GitHub 回下载资产与本地公证包逐字节一致 |
| `RELEASE-0.4.3-06` | `HANDOFF.md`、`VERSION_HISTORY.md`、SDD 注册表和功能规格只在对应线上事实完成后标记 `Released` |

## 发布结果

- PR #40 GitHub CI 通过并合并到 `main`；发布提交为
  `b76c317d640e73621b6e2119e4363d0cac6ddff6`；
- 完整 `swift test` 104 项通过、0 失败；Universal App、Widget 与 Activity
  Hook 均为 `x86_64 arm64`；
- Developer ID 与 Hardened Runtime 验证通过；Apple 公证 Accepted 并完成
  Staple，Submission `e3f5f0fa-8f36-4ed3-8b26-3b6ef1861344`；
- 正式资产 `QuotaView-v0.4.3-build.1.zip` 为 `13,166,345 bytes`，SHA-256
  `a2b35249c3c146444207fc82d041121e790d099cc534b597775262e42160d54c`；
- GitHub Release 为 Latest、非 Draft、非 Pre-release；回下载文件与本地
  公证包逐字节一致，并从 `/Applications/QuotaView.app` 完成启动冒烟；
- Stable appcast 由 `gh-pages` 提交
  `56c02c07cebfbeb19a2684ee3dff2bce2f6bbe0c` 发布，线上 SHA-256 为
  `2e5b058592c5b823511391e54a4d873c962d787f54899c1dc1e9da034a9eb40a`，
  逐字节与 Sparkle EdDSA 验证通过；
- 完整视觉与辅助功能交叉矩阵仍由产品所有者按需验收。
