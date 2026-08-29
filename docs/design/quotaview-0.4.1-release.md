# QuotaView 0.4.1 发布规格

> Spec ID：`QV-RELEASE-0.4.1-001`
>
> 规格状态：`Accepted`
>
> 交付状态：`Released`
>
> 更新日期：2026-08-30
>
> 发布基线：`0.3.7 Build 1` / `v0.3.7-build.1`
>
> 目标版本：`0.4.1 Build 1` / Sparkle 内部序号 `13`

## 用户结果

将 0.4.0 开发周期中已经由产品所有者确认的灵动岛改造定版为 0.4.1：用户
可以在 AI 球与独立进度条灵动岛之间切换；AI 球展开态支持 100%、85%、75%
三档等比尺寸；进度条样式以状态烟雾表达任务近似进度，并在单步骤、多步骤、
上下文压缩、完成及中英文切换时保持稳定、可读且不误导的布局和进度语义。

## 发布范围

1. 独立进度条灵动岛、固定双语几何、左侧标题/操作与右侧状态布局；
2. 计划步骤近似进度、4 秒步骤识别窗口、执行中步骤 10%保守权重、单步骤
   50% 封顶回退与迟到计划接管；
3. 状态烟雾配色、动态透明度与尾端扩散、上下文压缩弱扩散、完成铺满/变暗/
   淡出及四周绿色呼吸辉光；
4. AI 球 100% / 85% / 75% 展开尺寸，且不影响进度条与紧凑态；
5. 设置页使用真实原生控件几何并保持右侧控件统一贴齐；
6. 英文与简体中文 README、英文 GitHub Release Notes、Developer ID、Apple
   公证、GitHub Latest 和 Stable appcast。

## 隐私与兼容边界

- Hook 只传生命周期元数据和计划状态计数，不传提示词、步骤、计划说明、
  工具参数、输出或原始 `exec` 脚本；
- 动态或无法解析的计划不得猜测，安全回退到单步骤方案；
- 保持 macOS 14+、Apple Silicon + Intel、Sparkle Stable 通道与既有本地
  Codex 连接兼容；
- 不引入多任务 Preview，不调用真实额度重置接口。

## Requirement

| ID | 要求 |
|---|---|
| `RELEASE-0.4.1-01` | App 与 Widget 为 Marketing 0.4.1、产品 Build 1、Sparkle 内部序号 13，tag 与资产分别为 `v0.4.1-build.1`、`QuotaView-v0.4.1-build.1.zip` |
| `RELEASE-0.4.1-02` | `swift test`、Universal Release、资源、版本、架构、隐私搜索和 `git diff --check` 全部通过 |
| `RELEASE-0.4.1-03` | 最终 App 使用 Developer ID 与 Hardened Runtime，Apple 公证 Accepted 并完成 Staple，ZIP 回解压后再次通过签名、Gatekeeper、版本与架构验证 |
| `RELEASE-0.4.1-04` | GitHub Release 为非 Draft、非 Pre-release、Latest；Release Notes 只有一份英文源文，README 双语下载入口指向同一正式资产 |
| `RELEASE-0.4.1-05` | Stable appcast 使用 Sparkle EdDSA 签名并在线验证；GitHub 回下载资产与本地公证包逐字节一致 |
| `RELEASE-0.4.1-06` | `HANDOFF.md`、`VERSION_HISTORY.md`、SDD 注册表和相关规格只在对应事实完成后回填，不把候选状态写成已发布 |

## 发布结果

- `swift test`：93 项通过、0 失败；新增覆盖缺失 `Stop` 的静默收敛、同轮
  迟到结束事件防回开、重启旧事件不重放和新任务取消收敛；
- Activity Hook Unix Socket 隐私检查：`exec` 包装计划只输出三个状态计数；
- PR #34 GitHub CI 通过并合并为发布提交
  `e14039eeb7021041f384b10db386a80844694b0f`；Universal Release 的 App、
  Widget、Hook 均为 `x86_64 arm64`；
- 正式包使用 `Developer ID Application: Chenchen Xu (BUUH229D5Q)` 与
  Hardened Runtime；Apple 公证 Accepted 并完成 Staple，Submission 为
  `fd08ea22-9a55-4f63-9279-f10f0663eb7a`；
- GitHub Latest 为 `v0.4.1-build.1`；正式资产
  `QuotaView-v0.4.1-build.1.zip` 大小 `13,068,004 bytes`，SHA-256 为
  `ae8cf53acc6e6473ebf33bb853b7448672b48c4e849ef4b219efd74b18a9a2a3`；
- GitHub 回下载资产与本地公证包逐字节一致；回解压后通过嵌套签名、Staple、
  Gatekeeper、版本、资源与双架构复核，并完成独立启动冒烟；
- Stable appcast 由 `gh-pages` 提交
  `e8312e45e344fbb9fcb01875ab27a65ce47506d0` 发布；线上文件 SHA-256 为
  `afcce62e375f3f35f6557308343e47349e0d895ab23489fb101b537c58abc852`，
  与本地签名 feed 逐字节一致且 EdDSA 验证通过；
- GitHub Release Notes 使用单份英文源文，README 中英文下载入口均指向
  同一正式资产；
- 产品所有者已确认当前生产 App 没有发现新的视觉问题并批准发布；
  完整深浅色、VoiceOver、Increase Contrast 与 Reduce Motion 交叉矩阵未
  单独记录为全量通过。
