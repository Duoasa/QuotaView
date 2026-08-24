# QuotaView 用量概览规格

> 文档编号：`QV-PRODUCT-USAGE-OVERVIEW-002`
>
> 规格状态：`Accepted`
>
> 交付状态：`Released`（`0.3.5 Build 5`）

本规格覆盖主周期额度、Spark 周额度、最近一天/30 日 Token 和 30 日成本
估算。数据沿用现有 Codex App Server，不增加请求接口、凭据、权限、网页
抓取或账户写操作。Token 网格细节由
[`QV-PRODUCT-TOKEN-ACTIVITY-001`](quotaview-token-activity.md) 独占定义。

## 主额度与 Spark

- 主额度标题为“本周期剩余”；订阅方案在右上角按官方名称归一；下次重置
  合并到底部左侧，与右侧“已使用”使用相同字体、字号和颜色；面板不再提供
  单独的重置时间开关；
- 同一次 `account/rateLimits/read` 中，`codex` 映射主额度，
  `codex_bengalfox.primary` 映射稳定 ID `codex_bengalfox` 的独立 Spark 窗口；
- Spark 缺失、窗口缺失或百分比越界时只隐藏 Spark，不保留高度、不显示
  虚假零值，也不使主额度失败；
- Spark 位于主额度下方，高 `82 pt`、水平/垂直内边距 `16/12 pt`。标题与
  剩余百分比同行，不重复订阅方案；进度条复用 8 pt 几何但固定为中性色：
  深色剩余/已用为白色 `88/30%`，浅色为黑色 `62/18%`；底部显示重置和已用。

## Token 与成本

- “30 日 Tokens”使用今天及之前 29 个 UTC 自然日，只汇总实际有效桶；
  缺失日期不补造，完全不可用时显示破折号；
- “最近一天 Tokens”显示最近有效桶及其真实日期语义，不能把非今天的桶
  称为“今日”或复制到今天；
- 成本估算使用同一 30 日窗口，当前参考价为 GPT-5.6 Sol 缓存输入
  `$0.50 / 1,000,000 tokens`，公式为 `tokens / 1,000,000 × 0.50`；
- 成本标题为“成本估算（30 天）”，必须标注“估算值 · 非账单”；底部右侧
  显示窗口内最近有效桶并使用“最近一天”语义。图表固定 30 个日期位置，
  缺失值不冒充真实零，完全无数据时总额、最近一天和刻度均为破折号；
- 成本底部左右文案统一使用 Asta Sans Regular `10.5 pt` 和同一次要颜色；
  Hover 与 VoiceOver 提供本地化日期和估算值；参考价变化必须更新规格、
  文案、测试和 Build。

## 设置、顺序与布局

面板内容顺序固定为：主额度、Spark、成本、Credits、最近一天 Token、30 日
Token、累计 Token、Token 活动、额度重置入口。设置顺序与面板一致。

| 项目 | 持久化键 | 默认 |
|---|---|---|
| 30 日 Tokens | `preferences.panel.showThirtyDayTokens` | 开启 |
| 成本估算 | `preferences.panel.showEstimatedCost` | 开启 |

菜单宽度保持 `274 pt`，顶部锚定，只向下扩展。Spark 增减 `82 pt`，成本区
高 `176 pt`，普通指标行 `36 pt`；隐藏项不保留空白。主额度保留风险色，
Spark 与 Token/成本量级图不把颜色解释为健康或账单风险。

## Requirement

| ID | 要求 |
|---|---|
| `USAGE-01` | 主额度内合并重置且缺失值不伪造零 |
| `USAGE-02` | 主/Spark 独立映射、校验和失败隔离 |
| `USAGE-03` | Spark 紧凑中性视觉、无重复订阅和无空白隐藏 |
| `USAGE-04` | 最近一天与 30 日 Token 使用一致 UTC 桶 |
| `USAGE-05` | 成本公式、30 日图、“非账单”和无数据语义 |
| `USAGE-06` | 设置顺序、usage Demand、动态高度与辅助功能 |

Spark 样式已获产品所有者局部确认；完整视觉矩阵仍等待验收。发布、资产与
签名证据见 [`VERSION_HISTORY.md`](../../VERSION_HISTORY.md#035-build-5)。
