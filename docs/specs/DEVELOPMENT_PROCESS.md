# QuotaView SDD 开发流程

> 文档编号：`QV-SDD-PROCESS-001`
>
> 状态：`Accepted`

当前版本、当前工作和规格状态分别由 `VERSION_HISTORY.md`、`HANDOFF.md` 和
本目录的注册表维护。本文件只定义稳定流程。

## 标准流程

```text
定位事实 → 定义规格 → 授权实现 → 自动化验证 → 用户验收 → 授权发布 → 归档
```

1. **定位事实**：按注册表路由读取上下文；用 Git 实时核对分支、HEAD 与
   工作树；区分修复、Prototype、生产实现和发布。
2. **定义规格**：新增功能、用户可见行为或架构边界变化必须定义唯一 Spec
   ID、稳定 Requirement、目标/非目标、状态、隐私、降级和验收条件。
3. **授权实现**：`Accepted` 不自动授权生产修改；用户明确要求实施后才进入
   `Implementing`。Prototype 迁入、产品方向、版本身份和发布分别需要明确
   授权。
4. **自动化验证**：按 `AGENTS.md` 做与风险相称的测试、Universal Build、
   版本/架构/资源检查、临时代码搜索和 `git diff --check`。文档-only 任务可
   跳过构建，但必须检查链接、职责和版本一致性。
5. **用户验收**：视觉、交互和辅助功能结论由产品所有者给出；没有结论时
   记录“等待验收”。Prototype 结论不能替代生产 App 结论。
6. **发布与归档**：实现授权不等于发布授权。精确版本获准后才执行签名、
   公证、Release、回下载和 appcast；完成后把不可变证据写入 Version History，
   Handoff 只保留当前影响。

## 状态出口

| 状态 | 最小出口条件 |
|---|---|
| `Discovery` | 问题、边界和关键决策明确 |
| `Prototype` | 隔离 Demo 有记录结论，尚未进入生产 |
| `Planned` | Spec 已接受且实施范围已排序 |
| `Implementing` | 已获生产实现授权并可追踪 Requirement |
| `Verifying` | 实现与自动化完成，仍有验收或跨版本验证 |
| `Released` | tag、Release、最终资产及要求的回下载验证已发生 |

## Prototype 与证据边界

- Prototype 位于 `Prototypes/` 或临时目录，与生产 Target、版本和发布历史
  隔离；经用户确认并授权后，按生产规格实现或迁移。
- PR 必须能说明 Spec/Requirement（或 `Spec impact: None`）、范围、验证、
  用户验收、隐私/辅助功能/发布影响，以及临时 Demo 和 QA 入口是否清理。
- 只有 Demo、只有编译、规格与实现冲突，或提前记录未发生的发布事实时，
  不得宣称完成。
