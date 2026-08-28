# QuotaView 0.4.0 大版本开发规格

> Spec ID：`QV-RELEASE-0.4.0-001`
>
> 规格状态：`Draft`
>
> 交付状态：`Discovery`
>
> 更新日期：2026-08-29
>
> 稳定生产基线：`0.3.7 Build 1` / `v0.3.7-build.1`
>
> 当前开发身份：`0.4.0 Build 1` / Sparkle 内部序号 `12`

## 决策

产品所有者明确决定：下一次大规模升级直接使用 Marketing Version `0.4.0`，
不继续沿用 `0.3.x`。Marketing Version 变化后产品可见 Build 归 `1`；Sparkle
内部更新序号必须跨版本递增，因此本轮从 `12` 开始。

该决定只授权建立 0.4.0 开发身份，不代表具体功能、架构变更、Prototype
迁入、GitHub 发布或 Stable appcast 已获授权。

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

1. 0.4.0 最重要的用户结果是什么；
2. 本次升级包含哪些主要功能或架构变化；
3. 哪些 0.3.7 行为必须原样保留；
4. 哪些内容明确不进入 0.4.0；
5. 第一阶段应交付的最小完整纵向切片是什么。

## 验证与出口

当前已验证：

- App 与 Widget 的 Xcode Release Build Settings 均为 Marketing `0.4.0`、
  Sparkle 内部序号 `12`、产品 Build `1`；
- `swift test`：72 项通过、0 失败；
- App 与 Widget Info.plist 语法检查通过；
- `git diff --check`、临时 Debug 标记和真实额度消费调用搜索通过；
- README、GitHub Latest 与 `VERSION_HISTORY.md` 继续指向 0.3.7 Build 1。

尚未执行：

- 0.4.0 Universal Release 构建、签名、公证、发布资产和视觉验收；这些工作
  在具体功能范围确认并实现前没有完成条件。

Discovery 阶段的出口条件：

- App、Widget 和兼容 Info.plist 的三组版本身份一致；
- `HANDOFF.md` 与 SDD 注册表指向本规格；
- 公开 Latest、README 下载入口和 `VERSION_HISTORY.md` 仍保持 0.3.7；
- 产品所有者确认主要用户结果、范围、非目标和第一阶段；
- 规格进入 `Accepted`，并单独获得生产实现授权。

## 停止条件

在范围尚未确认时，停止于版本身份和 Discovery 文档，不实施推测性的功能、
架构迁移或 Prototype 合并。
