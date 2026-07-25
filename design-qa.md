# Codex Pulse 额度刷新设计验收

final result: passed

## 对比基准

- Source visual truth:
  `/Users/sukduoasa/.codex/visualizations/2026/07/25/019f9a49-53c8-71e2-bc9a-f46fd89d53c6/codex-pulse-qa/source-selected-design.png`
- Implementation overview:
  `/Users/sukduoasa/.codex/visualizations/2026/07/25/019f9a49-53c8-71e2-bc9a-f46fd89d53c6/codex-pulse-qa/implementation-overview.png`
- Implementation detail:
  `/Users/sukduoasa/.codex/visualizations/2026/07/25/019f9a49-53c8-71e2-bc9a-f46fd89d53c6/codex-pulse-qa/implementation-detail.png`
- Implementation confirmation:
  `/Users/sukduoasa/.codex/visualizations/2026/07/25/019f9a49-53c8-71e2-bc9a-f46fd89d53c6/codex-pulse-qa/implementation-confirmation.png`
- Combined comparison:
  `/Users/sukduoasa/.codex/visualizations/2026/07/25/019f9a49-53c8-71e2-bc9a-f46fd89d53c6/codex-pulse-qa/comparison-source-and-implementation.png`

## 视口与归一化

- 设计稿：1541 × 1020 px，包含三个并排的概念状态。
- 实现截图：每张 740 × 1020 px，对应 370 × 510 pt 的 Retina 局部截图；其中应用内容宽度约 344 pt，其余为弹窗阴影和少量桌面背景。
- 对比图：3881 × 1068 px。设计稿与三个实现状态统一按 1020 px 高度排列，没有拉伸或改变纵横比。
- 状态：深色外观、真实账户数据、概览页、已勾选风险确认的二级页、最终确认弹窗。
- 动态用量数值与设计稿不同属于预期：实现读取真实 Codex 数据，设计稿使用固定示例值。

## 全局对比结论

- 信息层级与选定方案一致：普通数据保持为紧凑列表，额度刷新次数从列表移出并成为独立底部入口。
- 二级页以可用次数作为视觉主角，并保留当前额度、三条风险说明、确认勾选、主按钮和剩余次数预告。
- 最终确认使用原生 macOS 弹窗。确认按钮采用系统的 destructive 语义红色，而不是概念稿中的紫色；这是为了强化不可撤销风险，属于有意调整。
- 实现保留了现有 Codex Pulse 品牌头部、状态徽章和退出入口，属于对既有产品结构的保留。

## 必检表面

- 字体与排版：使用系统 SwiftUI 字体，标题、主数字、正文和辅助文字层级清晰；没有可见截断。
- 间距与布局：344 pt 菜单栏窗口内保持一致边距；入口点击区域、复选框和主按钮均具有清晰可点击尺寸。
- 颜色与视觉变量：延续深灰材质、紫蓝强调色、绿色可用状态；确认弹窗使用系统危险操作颜色。
- 图像与图标：界面没有位图插画需求；所有功能图标使用原生 SF Symbols，清晰且与现有应用一致。
- 文案与内容：明确区分“同步数据”和“额度刷新”；演示模式、消耗次数、不可撤销与不会调用真实接口均有明确说明。

## 交互检查

- 菜单栏入口可以打开概览页。
- “额度刷新”独立入口可以进入二级页。
- 未勾选风险说明时主按钮禁用；勾选后按钮启用。
- 点击主按钮可以打开最终确认弹窗。
- 取消弹窗不会改变真实次数；返回按钮可以回到概览页。
- 代码检查确认当前没有发送
  `account/rateLimitResetCredit/consume`，确认处理器只更新本地演示提示。

## 对比历史

### 第一次对比

- [P2] 二级页底部同时显示内容区演示说明和底栏不消耗说明，在紧凑宽度下发生拥挤。
- 修正：移除内容区重复说明，将状态合并为底栏单行
  “演示模式 · 不消耗次数”。

### 第二次对比

- 修正后的二级页和确认弹窗没有文本重叠、裁切或隐藏主操作。
- 没有剩余 P0、P1 或 P2 问题。

## 聚焦区域

- 二级页截图用于检查风险说明、勾选状态、按钮可用状态和底栏。
- 确认弹窗截图用于检查标题、不可撤销文案、演示模式说明以及取消/确认操作。
- 以上区域在独立截图中均可完整阅读，因此不需要额外放大裁切。

## 后续优化

- P3：正式接入真实接口时，为成功、无可重置窗口、无次数和重复请求分别增加明确结果状态。
- P3：正式分发前补充键盘焦点顺序和 VoiceOver 实机检查。
