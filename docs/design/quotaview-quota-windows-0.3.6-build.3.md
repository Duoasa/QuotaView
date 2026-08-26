# QuotaView 多周期额度展示规格

> 文档编号：`QV-PRODUCT-QUOTA-WINDOWS-003`
>
> 规格状态：`Accepted`
>
> 交付状态：`Verifying`
>
> 生产基线：`0.3.6 Build 2`
>
> 最终发布候选：`0.3.7 Build 1`；Sparkle 内部更新序号 `11`

## 决策

QuotaView 必须完整保留 Codex `codex` 限额中的 `primary` 与 `secondary`
窗口，并在主面板按周期从短到长分别显示。每个有效窗口复用现有主额度的
百分比、风险色进度条、下次重置与已使用样式；订阅方案只在第一项显示。

展示标题由接口返回的 `windowDurationMins` 决定，不根据订阅名称猜测：

- `300` 分钟显示“5 小时额度剩余 / 5-Hour Limit Remaining”；
- `10,080` 分钟显示“周额度剩余 / Weekly Limit Remaining”；
- 其他完整天数或小时数显示实际时长；无法识别时回退“本周期剩余 /
  Period Remaining”。

Spark 继续作为 `codex_bengalfox` 的独立中性窗口，位于全部 Codex 主窗口
之后，不重复订阅方案。

## 边界与不变量

- `primary` 继续是建立有效快照的必需窗口；缺失或越界仍使本次主状态
  不可用。
- `secondary` 是可选窗口；缺失、缺少百分比或百分比越界时只隐藏该窗口，
  不伪造 `0%`，也不使 `primary` 或 Spark 失败。
- `primary`、`secondary`、Spark 分别使用稳定实体 ID，刷新、排序和数值变化
  不得改变行身份。
- 面板固定宽 `274 pt`、顶部锚定。每增加一个 Codex 主窗口增加现有主额度
  高度 `117 pt`；隐藏项不保留空白。
- 无有效快照时保留现有单个不可用摘要的稳定布局，并显示破折号。
- 菜单栏、Widget 和额度重置演示继续投影协议 `primary`，本迭代不改变
  这些既有契约，也不新增设置开关、接口、权限、凭据或账户写操作。
- 不根据 Plus、Pro 5x、Pro 20x 等方案名称硬编码周期或额度值。

## Requirement

| ID | 要求 |
|---|---|
| `QUOTA-WINDOWS-01` | 领域层独立映射 `primary` 与 `secondary`，使用稳定 ID |
| `QUOTA-WINDOWS-02` | 展示层按实际时长从短到长输出全部有效 Codex 窗口 |
| `QUOTA-WINDOWS-03` | 每个窗口显示自己的剩余、已用、重置时间和时长语义标题 |
| `QUOTA-WINDOWS-04` | 第二窗口缺失或无效时局部降级，不影响其他额度 |
| `QUOTA-WINDOWS-05` | 面板高度按窗口数量增长，Spark 顺序和样式保持不变 |
| `QUOTA-WINDOWS-06` | 旧 primary 投影、菜单栏、Widget、重置演示与隐私边界不回归 |

## 验证

- 自动化覆盖只有 primary、primary + secondary、无效 secondary、
  primary + secondary + Spark，以及展示排序；
- 运行 `swift test` 和 Universal Xcode Release 无签名构建；
- 核对 App、Widget 的 Marketing Version、内部更新序号和产品 Build；
- 搜索临时 Mock/UI QA 入口并执行 `git diff --check`；
- 深浅色、中英文、单/双主窗口、Spark 有无及顶部锚定由产品所有者手动
  验收，完成前交付状态保持 `Verifying`。

## 非目标

- 不修改 OpenAI 限额规则，不承诺某一订阅恒定拥有某个周期；
- 不扩展 Widget 共享快照为多窗口；
- 不新增额度窗口显隐开关或手动排序；
- 本规格不改变既有发布机制；0.3.7 Build 1 是否发布仅由精确版本准入决定。

## 当前验证记录

- 候选合并验证 `swift test`：72 项通过、0 失败；覆盖双周期映射、局部降级、与
  Spark 并存以及短周期优先排序；
- Universal Xcode Release 无签名构建通过；App、Widget、Activity Hook 与
  Core 均为 `x86_64 arm64`；
- App 与 Widget 候选身份均为 Marketing Version `0.3.7`、Sparkle 内部序号
  `11`、产品 Build `1`；`Assets.car`、`AppIcon.icns` 与波澜光晕资源存在；
- 视觉与交互结果等待产品所有者在真实账户的单/双窗口数据下验收；尚未
  完整签名发布链执行中。
