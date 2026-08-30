# QuotaView 0.4.2 Build 1 发布规格

> Spec ID：`QV-RELEASE-0.4.2-001`
>
> 状态：`Accepted / Released`
>
> 日期：2026-08-30
>
> 发布基线：`0.4.1 Build 1` / `v0.4.1-build.1`
>
> 目标版本：`0.4.2 Build 1` / Sparkle 内部序号 `14`

## 用户结果

用户可以从四种真实预览中选择进度条效果，并在单步骤、多步骤和完成时获得
更连贯的反馈；任务在工具步骤之间不再误隐藏或提前显示完成，只有真实任务
结束才进入完成态。

## 发布范围

1. 状态烟雾、晶钻前沿、液滴涌动和液态涌浪四种进度效果及设置实时预览；
2. 三个新增效果完整复用九种 Codex 状态配色，并提供克制的完成高亮；
3. 计划进度前沿减速与直接/包装计划计数解析；
4. Hook ACK、持久队列、事件去重、turn 感知终态锁与生命周期动画门控；
5. 简洁的中英文 README、单份英文 GitHub Release Notes、Developer ID、
   Apple 公证、GitHub Latest 和 Stable appcast。

## 隐私与兼容边界

- Hook 只转发生命周期元数据和计划状态计数，不传提示词、步骤正文、工具
  输入输出或原始脚本；
- 完成态只接受真实 Hook `Stop`，`SessionEnd` 只隐藏；App Server 不合成
  任务终态；
- 保持 macOS 14+、Apple Silicon + Intel、稳定单任务灵动岛和 Sparkle Stable
  通道兼容；不迁入多任务 Preview，不调用真实额度重置接口。

## Requirement

| ID | 要求 |
|---|---|
| `RELEASE-0.4.2-01` | App 与 Widget 为 Marketing 0.4.2、产品 Build 1、Sparkle 内部序号 14，tag 与资产分别为 `v0.4.2-build.1`、`QuotaView-v0.4.2-build.1.zip` |
| `RELEASE-0.4.2-02` | `swift test`、Universal Release、资源、版本、架构、隐私搜索和 `git diff --check` 全部通过 |
| `RELEASE-0.4.2-03` | 最终 App 使用 Developer ID 与 Hardened Runtime，Apple 公证 Accepted 并完成 Staple；ZIP 回解压后再次通过签名、Gatekeeper、版本与架构验证 |
| `RELEASE-0.4.2-04` | GitHub Release 为非 Draft、非 Pre-release、Latest；Release Notes 只有一份简洁英文源文，README 双语下载入口指向同一正式资产 |
| `RELEASE-0.4.2-05` | Stable appcast 使用 Sparkle EdDSA 签名并在线验证；GitHub 回下载资产与本地公证包逐字节一致 |
| `RELEASE-0.4.2-06` | `HANDOFF.md`、`VERSION_HISTORY.md`、SDD 注册表和功能规格只在对应线上事实完成后标记 `Released` |

## 发布结果

- `swift test`：103 项通过、0 失败；PR #36 GitHub CI 通过并合并为发布提交
  `6c8434950d59afd9439b2f6f50d8c8b091a40f6d`；
- Universal Release 的 App、Widget 与 Activity Hook 均为 `x86_64 arm64`，
  包内身份为 Marketing `0.4.2`、Sparkle 内部序号 `14`、产品 Build `1`；
- 正式包使用 `Developer ID Application: Chenchen Xu (BUUH229D5Q)` 与
  Hardened Runtime；Apple 公证 Accepted 并完成 Staple，Submission 为
  `5cad0ca0-7f2e-49ef-beda-34b151ed2f45`；
- GitHub Latest 为 `v0.4.2-build.1`；资产
  `QuotaView-v0.4.2-build.1.zip` 大小 `13,166,133 bytes`，SHA-256 为
  `a87f7f03da644fb014a8c90b617b99697bbb6aae72a7c35928d3386bbf2c05a3`；
- GitHub 回下载资产与本地公证包逐字节一致；回解压后通过嵌套签名、Staple、
  Gatekeeper、版本、资源、三目标双架构复核和独立启动冒烟；
- Stable appcast 由 `gh-pages` 提交
  `ead810f540261fbd3e67d17f0f0d32401606b0c0` 发布，线上 SHA-256 为
  `a8ddb8809340caed56dbf0743ab71f51bb2bae6a1a8a067676853cfd76185e8b`；
  线上文件与本地 feed 逐字节一致且 Sparkle EdDSA 验证通过；
- GitHub Release Notes 使用单份简洁英文源文，README 中英文下载入口均指向
  同一正式资产；产品所有者已批准发布。完整深浅色、多屏、VoiceOver、
  Increase Contrast 与 Reduce Motion 交叉矩阵未单独记录为全量通过。
