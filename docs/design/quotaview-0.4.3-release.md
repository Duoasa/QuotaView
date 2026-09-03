# QuotaView 0.4.3 Build 1 发布规格

> Spec ID：`QV-RELEASE-0.4.3-001`
>
> 状态：`Accepted / Verifying`
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

## 当前状态

- 产品所有者已指定 `0.4.3 Build 1` 并授权 GitHub、Release 与 appcast 发布；
- 候选版本、文档与发布说明正在准备；
- 完整 `swift test` 104 项通过、0 失败；签名、公证、远端合并、Release 和
  appcast 证据尚待完成。
