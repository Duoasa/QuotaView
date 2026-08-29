# QuotaView 0.4.0 大版本开发规格

> Spec ID：`QV-RELEASE-0.4.0-001`
>
> 规格状态：`Superseded`
>
> 交付状态：`Verifying`
>
> 更新日期：2026-08-29
>
> 稳定生产基线：`0.3.7 Build 1` / `v0.3.7-build.1`
>
> 当前开发身份：`0.4.0 Build 1` / Sparkle 内部序号 `12`

> 后继发布规格：
> [`QV-RELEASE-0.4.1-001`](quotaview-0.4.1-release.md)。0.4.0 仅作为本轮
> 大规模开发的历史身份，不创建公开 Release；产品所有者已将满意的实现
> 定版为 0.4.1 Build 1。

## 决策

产品所有者明确决定：下一次大规模升级直接使用 Marketing Version `0.4.0`，
不继续沿用 `0.3.x`。Marketing Version 变化后产品可见 Build 归 `1`；Sparkle
内部更新序号必须跨版本递增，因此本轮从 `12` 开始。

该决定本身只授权建立 0.4.0 开发身份，不代表任意功能、架构变更、Prototype
迁入、GitHub 发布或 Stable appcast 已获授权。产品所有者随后已单独接受并
授权纵向切片：
[`QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005`](quotaview-codex-activity-island-size-0.4.0.md)。
产品所有者随后要求在真实灵动岛中实现独立的进度条样式：恢复最初烟雾前沿，
无计划与新任务初始前沿为 0%；有计划时从 0% 绑定隐私化近似进度；展开态
文字靠左、紧凑态状态文字位于灵动岛正中心，对应
[`QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006`](quotaview-codex-activity-island-state-smoke-0.4.0.md)。
进度条与 AI 球现在是并列的顶层样式；100% / 85% / 75% 只作用于 AI 球，
进度条保持原始展开尺寸。
这些授权只覆盖各自规格，不自动扩展为 0.4.0 的完整范围。

## 已确认基线

- 当前公开稳定版为 `0.3.7 Build 1`，tag 为 `v0.3.7-build.1`；
- 0.3.7 已包含多周期额度完整展示、稳定单任务 Codex 灵动岛、多屏锁定、
  Token 活动、用量概览和应用内更新能力；
- 0.3.2 多任务灵动岛仍是独立 Preview，不属于 0.3.7 稳定源码，也不会因
  版本升级自动迁入 0.4.0；
- 0.3.7 的公开 Release、Latest、签名 appcast 和回滚资产保持不变。

## 当前目标

1. 建立准确且可验证的 `0.4.0 Build 1` 开发身份；
2. 从 0.3.7 稳定生产行为出发定义本次大版本的用户结果、功能边界和阶段；
3. 将后续实现拆成可独立验证、可回滚的纵向切片；
4. 在具体 Requirement 获得接受和实现授权前，不提前改变生产行为。

## 已接受的纵向切片

| Spec | 状态 | 范围 |
|---|---|---|
| `QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006` | `Accepted / Verifying` | 进度条已从 AI 球动画中拆为并列顶层样式；旧偏好迁移、结构化近似进度、扩散尾迹和完成反馈已通过定向测试，等待产品所有者验收 |
| `QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005` | `Accepted / Verifying` | 三档只作用于 AI 球展开态；进度条与紧凑态保持原尺寸，等待产品所有者验收 |

## 当前非目标

- 不把 `0.4.0 Build 1` 写成已发布、已签名、已公证或已进入 appcast；
- 不创建 tag、Release、发布资产或改变 README 下载入口；
- 不自动迁入多任务 Preview 或其他 Prototype；
- 不在产品所有者给出范围前猜测 0.4.0 的功能清单或目标架构；
- 不改变 0.3.7 稳定版的不可移动 tag、资产和回滚证据。

## Requirement

### QV-040-VERSION-01 — 开发版本身份

App、Widget 和兼容 Info.plist 必须使用：

- Marketing Version：`0.4.0`；
- 产品可见 Build：`1`；
- Sparkle 内部更新序号：`12`。

### QV-040-SCOPE-02 — 大版本范围门禁

开始具体生产功能或架构变更前，必须由产品所有者确认：主要用户结果、功能
范围、非目标、必须保持的 0.3.7 行为，以及阶段优先级。确认内容应补充到本
规格或拆分为已注册的子规格。

### QV-040-COMPAT-03 — 稳定行为保护

除非新的已接受 Requirement 明确改变，0.3.7 的数据语义、隐私边界、稳定
单任务灵动岛、应用更新准入规则、缺失与错误降级以及 macOS 14 最低系统
要求继续作为 0.4.0 的兼容基线。

### QV-040-RELEASE-04 — 发布隔离

开发分支、构建和普通 GitHub push 不得自动创建 0.4.0 Release 或把它加入
Stable appcast。发布与自动更新准入必须针对精确版本和资产另行授权。

## 待产品所有者定义

1. 除已接受的灵动岛尺寸切片外，0.4.0 最重要的整体用户结果是什么；
2. 本次升级还包含哪些主要功能或架构变化；
3. 哪些 0.3.7 行为必须原样保留；
4. 哪些内容明确不进入 0.4.0；
5. 已接受切片之后的阶段优先级是什么。

## 验证与出口

当前已验证：

- App 与 Widget 的 Xcode Release Build Settings 均为 Marketing `0.4.0`、
  Sparkle 内部序号 `12`、产品 Build `1`；
- 尺寸切片在状态烟雾截图修正前曾完成 `swift test` 78 项、0 失败；本次
  进度条样式拆分按产品所有者要求运行 `swift test --filter StateSmoke`，
  9 项通过、0 失败，并另跑 3 项样式默认值、持久化和尺寸边界测试；完成态
  烟雾淡出、绿色呼吸外沿时间契约和 Reduce Motion 静态落点均已纳入定向
  测试，未补跑全量测试；
- App 与 Widget Info.plist 语法检查通过；
- 尺寸切片和独立进度条样式均已通过 Universal Xcode Release 构建；
  App、Widget 和 Activity Hook 均为 `x86_64 arm64`；
- `git diff --check`、临时 Debug 标记和真实额度消费调用搜索通过；
- README、GitHub Latest 与 `VERSION_HISTORY.md` 继续指向 0.3.7 Build 1。

尚未执行：

- 0.4.0 Developer ID 签名、公证、GitHub 发布、Stable appcast 准入和视觉
  验收；当前本地产物仅为 ad-hoc 验证构建，不构成发布。

Discovery 阶段的出口条件：

- App、Widget 和兼容 Info.plist 的三组版本身份一致；
- `HANDOFF.md` 与 SDD 注册表指向本规格；
- 公开 Latest、README 下载入口和 `VERSION_HISTORY.md` 仍保持 0.3.7；
- 产品所有者确认主要用户结果、范围、非目标和第一阶段；
- 规格进入 `Accepted`，并单独获得生产实现授权。

## 停止条件

未由产品所有者确认并登记为已接受子规格的范围，停止于 Discovery 文档，
不实施推测性的功能、架构迁移或 Prototype 合并。已接受的纵向切片可以在其
自身边界与验收条件内独立实现和验证。
