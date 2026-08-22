# QuotaView SDD 开发流程

> 文档编号：`QV-SDD-PROCESS-001`
>
> 类型：长期执行流程
>
> 状态：`Accepted`

本文件只描述稳定流程。当前版本、迭代和验证结果分别由
[规格注册表](README.md)、[HANDOFF.md](../../HANDOFF.md) 和
[VERSION_HISTORY.md](../../VERSION_HISTORY.md) 维护。

## 1. 标准流程

```text
定位事实 → 定义规格 → 授权实现 → 自动化验证 → 用户验收 → 授权发布 → 归档
```

### 1.1 定位事实

- 按注册表的默认路由读取当前上下文；
- 用 Git 实时读取分支、HEAD 和工作区，不依赖文档中的可变提交；
- 区分修复、规格变更、Prototype、生产实现、验证和发布；
- 明确生产基线、当前迭代与本轮授权范围。

### 1.2 定义规格

新增功能、用户可见行为或架构边界变化必须有唯一 Spec ID。规格至少包含：

- 问题、目标和非目标；
- 稳定 Requirement ID；
- 用户可见行为和状态转换；
- 数据、隐私、兼容性、辅助功能与失败降级；
- 可验证的验收条件和禁止回归项。

小型缺陷和文档修复可复用现有 Requirement；确实不影响规格时记录
`Spec impact: None` 及理由。

### 1.3 授权实现

- 规格进入 `Accepted` 不自动授权修改生产代码；
- 用户明确要求“实施”“修复”或“迁入生产”后，交付状态进入
  `Implementing`；
- 会改变产品方向、把 Prototype 迁入生产、改变版本身份或触发发布时必须有
  对应的明确授权；
- 实现发现规格缺口时先同步规格，不用代码静默改变语义。

### 1.4 自动化验证

按 `AGENTS.md` 执行与风险相称的代码审查、状态检查、测试、Universal
构建、版本/架构/资源检查、临时代码搜索和 `git diff --check`。验证证据
记录在当前规格或 Handoff，不在注册表重复保存。

文档-only 修改没有触碰源码、配置、资源或构建脚本时，可跳过 `swift test`
和 Universal Release，但仍检查链接、职责边界、版本一致性与 Markdown
差异。

### 1.5 用户验收

Codex 不代替产品所有者完成视觉和交互验收。没有用户结论时必须写“等待
用户验收”，不得记录为通过。Prototype 验收也不能替代生产 App 验收。

### 1.6 发布与归档

- 生产实现授权不等于发布授权；
- GitHub Release 与 Sparkle appcast 准入分别判断；
- 只有产品所有者对精确版本、产品 Build、tag 和最终 ZIP 明确批准进入自动
  更新序列时，才触发签名、公证、Stable Release、回下载、Feed 与文档联动；
- 发布完成后，Version History 保存不可变发布事实，Handoff 切换当前工作，
  规格交付状态进入 `Released`。

## 2. Prototype 边界

只有需要验证可行性或方向时才建立 Prototype，并且必须：

- 位于 `Prototypes/` 或临时目录，与生产 Target 隔离；
- 标明对应 Spec、虚拟数据和不得迁入生产的边界；
- 不修改生产版本、tag、Release 或发布历史；
- 经用户确认并授权后，按规格重新实现或迁移到生产；Demo 证据不能冒充
  生产证据。

## 3. 状态出口

| 状态 | 最小出口条件 |
|---|---|
| `Discovery` | 问题、边界和关键决策已明确 |
| `Prototype` | 隔离 Demo 有记录的结论；未进入生产 |
| `Planned` | Spec 已接受且实施范围已排序 |
| `Implementing` | 获得生产实现授权并建立 Requirement 追踪 |
| `Verifying` | 实现与自动化完成；等待剩余验收或跨版本验证 |
| `Released` | Release、tag、最终资产与要求的回下载验证均已发生 |

## 4. 评审证据

代码或 PR 应能回答：

- 对应的 Spec / Requirement，或 `Spec impact: None`；
- 范围、非目标和实现前后行为；
- 自动化结果与用户验收状态；
- 隐私、辅助功能、本地化和发布影响；
- 临时 Demo、Debug、自动操作和 QA 入口是否已清理。

只有 Demo、只有编译、缺少必要用户验收、规格与实现冲突，或提前记载尚未
发生的发布事实时，不得宣称功能或发布完成。
