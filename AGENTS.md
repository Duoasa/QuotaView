# QuotaView 项目执行与设计规范

本文件约束后续所有针对 QuotaView 的代码、界面和发布任务。除非用户在
当前任务中明确要求改变产品方向，否则实现应保持与当前 0.3.3 Build 3
一致。

## 规范来源与优先级

出现冲突时按以下顺序判断：

1. 用户在当前任务中的明确要求
2. 当前生产代码中的真实状态、尺寸和功能约束
3. `VERSION_HISTORY.md` 中的当前最新版本与历史发布事实
4. `HANDOFF.md` 中的当前工作区、已完成事项与下一次迭代状态
5. `docs/specs/README.md` 中登记的当前已接受规格
6. `design-qa.md`
7. Figma 节点 `1:712`、`25:1471`、`10:181`、`25:1524`
8. 本文件中的通用设计规则

`VERSION_HISTORY.md` 只负责版本身份、Release、tag、历史特性和撤回记录，
不得用其中的历史实现覆盖当前生产代码。`HANDOFF.md` 负责当前工作状态和
下一次迭代入口，不得把计划中的版本提前写成已发布。

## 会话启动与文档联动

每个新会话处理 QuotaView 任务前，按以下顺序建立上下文：

1. 阅读本文件，确认长期产品、设计、实现和发布约束；
2. 阅读 `HANDOFF.md` 第 0 节“版本定位入口”；
3. 按其中的相对链接打开
   `VERSION_HISTORY.md#当前最新版本`，确认最新推荐版本、Build Number、
   tag、Release、资产和发布提交；
4. 打开 `docs/specs/README.md`，确认当前迭代、规格状态、交付状态和对应
   Requirement ID；
5. 读取当前任务对应的唯一规格，再回到 `HANDOFF.md` 继续读取当前结论、
   验证状态、工作区边界和下一次迭代入口；
6. 仅在任务涉及视觉验收历史时读取 `design-qa.md` 或对应 Prototype 的
   Design QA；
7. 只有满足下方 CodexBar 门禁时，才读取 CodexBar 参考文档。

文档职责必须保持清晰：

- `AGENTS.md`：长期执行与设计规范；
- `HANDOFF.md`：当前生产状态、已完成事项、未完成事项、工作区和下一步；
- `VERSION_HISTORY.md`：当前最新版本指针、公开历史版本、各版本特性、
  撤回原因和替代版本；
- `docs/specs/README.md`：SDD 唯一规格索引、当前迭代和追踪矩阵；
- `docs/specs/DEVELOPMENT_PROCESS.md`：SDD 状态模型、阶段出口、对话协议和
  PR 门禁；
- `docs/design/*.md`：具体产品、架构与功能规格；
- `design-qa.md`：视觉验收历史和等待产品所有者确认的矩阵。

### 文档时态、正式边界与防陈旧规则

- 正式 SDD 文档系统只包含已经由 Git 跟踪、并在
  `docs/specs/README.md` 注册或路由的 Markdown。未跟踪的 Prototype、图片、
  外部参考或个人草稿不参与权重判断，也不得静默驱动生产实现；
- `HANDOFF.md` 不固化会随每次提交变化的 `main` HEAD。当前分支与提交必须
  通过 `git status --short --branch`、`git branch --show-current` 和
  `git rev-parse HEAD` 读取；已经发布的 tag、发布提交和资产校验值可以持久
  记录；
- 历史报告、旧版实施计划和发布规格中的“当前”“后续”“待实现”等表述，
  必须标明所指版本或时间。文档顶部的当前实施状态或校准附录优先于历史
  正文中的实施时态；
- 已发布规格若保留实施前计划，必须补充当前生产映射、已完成阶段和未实施
  阶段，不能让未来时态覆盖已经存在的代码，也不能把预留接口写成已交付；
- 当前工作调用链固定为：`AGENTS.md` → `HANDOFF.md` 版本入口 →
  `VERSION_HISTORY.md` 当前版本 → `docs/specs/README.md` → 当前唯一规格 →
  对应验证证据。任何旁路文档只能提供参考，不能越级覆盖生产事实。

## SDD 规格驱动开发门禁

QuotaView 使用 Specification-Driven Development（SDD）。规格状态、交付
状态与发布状态必须分开维护，不能把“规格已接受”“Demo 已确认”“生产实现
完成”或“正式发布”混写成同一个“已完成”。

统一规格状态为：`Draft`、`Review`、`Accepted`、`Superseded`、
`Archived`。统一交付状态为：`Discovery`、`Prototype`、`Planned`、
`Implementing`、`Verifying`、`Released`。具体定义以
`docs/specs/README.md` 为准。

所有新增功能、行为变化和架构变化必须：

1. 先在 SDD 索引中定位或创建唯一 Spec ID；
2. 使用稳定 Requirement ID 定义范围、不变量、失败/降级语义和可验证的
   验收条件；
3. 在进入生产实现前将规格状态推进到 `Accepted`，并取得与当前阶段相符的
   用户授权；
4. 需要探索时将 Prototype 隔离在 `Prototypes/` 或系统临时目录，不得把
   Demo 证据冒充生产完成证据；
5. 实现时建立“Requirement ID → 生产源码 → 自动化测试 → 产品验收”追踪；
6. 发现规格缺口或冲突时先同步规格，不得用实现细节静默改变产品语义；
7. 只有完成正式发布门禁后才能把交付状态写为 `Released`。

小型缺陷、文案或文档修复可以复用既有 Requirement ID；若确实不影响规格，
PR 必须写明 `Spec impact: None` 及理由。涉及已冻结方向、从 `Prototype`
迁入生产、改变版本号或发布，必须由用户明确授权，不得从一般性的“继续”或
“采用”中推断。

当前生产基线、当前迭代及其阶段必须以 `docs/specs/README.md`、
`HANDOFF.md`、`VERSION_HISTORY.md` 和生产配置交叉核对。`0.3.2 Preview 1`
多任务灵动岛已经独立发布并归档，但不映射到 `0.3.3` 稳定生产源码；后续
继续开发必须建立新的迭代、版本与 Build，不得直接把归档代码当作当前生产。

版本与交接文档必须双向联动：

- `HANDOFF.md` 顶部必须直接链接
  `VERSION_HISTORY.md#当前最新版本`；
- `VERSION_HISTORY.md` 必须回链 `HANDOFF.md`；
- 每次发布、撤回版本、删除 tag 或改变 GitHub Latest 时，必须同步更新
  两份文档；
- 每次改变当前迭代、规格状态或交付状态时，必须同步更新
  `docs/specs/README.md` 与 `HANDOFF.md`；
- 同步内容至少包括最新版本、Build Number、tag、发布提交、Release URL、
  资产名、大小、SHA-256、签名、公证状态、验证结论和替代版本；
- README 下载链接与 GitHub Release Notes 也必须同时核对；
- GitHub Release Notes 使用单份英文源文，由 GitHub 界面负责翻译，避免
  手写中英文正文被重复显示；
- 删除 Release 后仍在 `VERSION_HISTORY.md` 保留“已撤回”记录，说明原因
  和替代版本，防止后续恢复问题版本；
- 如果 Marketing Version 不变，新的热更新必须使用更大的 Build Number、
  唯一 tag 和带 Build Number 的 ZIP；Marketing Version 是否升级由用户
  明确决定。
- 从 `0.3.4 (Build 1)` 开始，同一 Marketing Version 的每次后续开发迭代
  都必须递增 `CURRENT_PROJECT_VERSION`，不得复用旧 Build Number；App、
  Widget 与兼容 `Info.plist` 必须在同一任务内同步。

出现版本信息冲突时：

1. 先以用户当前指令和生产代码中的
   `CFBundleShortVersionString` / `CFBundleVersion` 为准；
2. 通过 GitHub Release/tag 和最终发布提交核实已经发生的发布事实；
3. 在同一任务内修正 `VERSION_HISTORY.md` 与 `HANDOFF.md`；
4. 不得把计划、候选包或尚未完成的 Release 写成已经发布；
5. 不得把已撤回的 `0.2.0 Build 3` 重新作为开发或下载基线。

### 应用内自动更新序列准入门禁

GitHub 版本发布与 Sparkle 自动更新序列是两个独立动作。产品所有者对每个
版本保留单独的自动更新准入决定权，长期采用显式加入（opt-in）规则：

1. 产品所有者针对某个精确版本明确表示“纳入自动更新序列”或“发布到
   appcast”，即同时授权并触发该版本的完整发布链路：合并生产代码、正式
   Developer ID 签名、Apple 公证/Staple、不可变 GitHub Stable Release、
   回下载验证、签名 appcast 部署和发布文档联动；不得在合并 `main` 后停下
   等待第二次“可以发布”确认；
2. 推送代码、创建 tag、创建 GitHub Release、设为 Stable/Latest、上传正式
   ZIP 或一般性的“可以发布”，均不得自动推导为已获 appcast 准入；
3. 未获得明确准入的版本默认排除在自动更新序列之外。允许为工程验证生成
   本地 appcast Fixture，但不得上传、部署或覆盖公开 appcast；
4. 准入授权必须绑定精确的 Marketing Version、Build Number 和预期 tag / ZIP
   身份；完成门禁后把最终资产大小、SHA-256、签名和公证结果回填文档。更换
   Build、tag、资产名或在最终验证后重新打包必须重新确认；
5. 自动更新序列可以跳过中间 GitHub Release。后续获准且 Build Number 更高
   的版本可直接作为现有客户端的下一更新目标，无需补录未获准版本；
6. 在 `HANDOFF.md` 和当前更新规格中记录每个候选版本的准入状态。没有记录
   或记录为“未批准”时，一律按未获准处理；
7. 发布公开 appcast 前必须核对产品所有者授权、不可变 Release 资产、
   SHA-256、Developer ID、公证/Staple、EdDSA 和回下载验证；
8. 已发布到 appcast 后如需撤回，必须由产品所有者明确授权，并同步处理
   appcast、GitHub Release/Latest、`HANDOFF.md` 与 `VERSION_HISTORY.md`，
   不得仅删除本地文件或静默覆盖 Feed。

### 稳定版本封存与回滚基线

每次准备发布新的稳定版、Preview、Beta 或 RC 前，必须先封存当时最新的
稳定版本，作为整个新版本周期的回滚基线。封存必须使用 Git 与已经验证的
发布资产，不在仓库中复制一份容易漂移的源码目录。

封存门禁如下：

1. 确认上一稳定版具有唯一且不可移动的发布 tag，并记录 tag、完整提交
   SHA、Release URL、资产名、大小和 SHA-256；
2. 确认对应资产已经完成该稳定版要求的签名、公证、Staple、Gatekeeper、
   架构和真实启动验证；
3. 在 `VERSION_HISTORY.md#当前最新版本` 与 `HANDOFF.md` 中将其明确标记为
   当前稳定回滚基线，并记录新版本发生问题时应回退到哪个 tag 和资产；
4. 新预发布版本不得移动、覆盖或删除该稳定 tag，不得覆盖原 Release 资产；
   修复必须使用新提交、新 Build、唯一 tag 和新资产；
5. Preview、Beta 或 RC 默认不得取代稳定版的 GitHub Latest 与 README 默认
   下载入口，除非用户明确要求改变稳定渠道；
6. 新版本晋升为稳定版后，它才成为下一版本周期的稳定回滚基线；此前的
   基线继续保留在版本历史中，不删除；
7. 回滚时从已封存 tag 或已核验资产恢复，不从开发分支、未提交工作区、
   Prototype 或候选包推断稳定代码。

当前 `0.3.3` 发布流程的稳定回滚基线固定为
`v0.3.1-build.2` / `3119171f45163fe45d68a4f774a0488968f14fd7`；
`0.3.2 Preview 1` 另由不可移动 tag、GitHub Pre-release 和本地归档分支
保留，不作为稳定回滚基线。

## CodexBar 参考文档调用门禁

CodexBar 的详细设计参考位于
`docs/reference/codexbar-macos-design-reference.md`。仅在以下情况读取
该文档：

1. 用户明确要求调用、参考或学习 CodexBar 的成熟方案来重构 QuotaView
   已有模块；
2. 用户要求为 QuotaView 新增一个功能模块，需要先判断 CodexBar 是否
   已经存在可借鉴的成熟方案。

普通修复、局部 UI 调整、既有方案内的实现和未提及 CodexBar 的已有模块
重构，不得主动读取或套用该文档。

新增模块时，Codex 可以先读取该文档进行方案预检，但必须在修改代码、
配置、资源或依赖之前：

1. 明确告诉用户 CodexBar 是否已有对应的成熟方案；
2. 简要说明该方案与 QuotaView 的适配点、代价和不应照搬的部分；
3. 询问用户是否采用该方案，并等待用户明确确认。

在用户确认前不得直接开始实现新增模块。如果 CodexBar 没有对应的成熟
方案，也应先说明结论，并询问用户是否按 QuotaView 自身约束继续设计。
即使用户确认采用，CodexBar 文档也只作为实现参考，不得覆盖本文件的
优先级、QuotaView 已确定的视觉规范、业务语义、隐私边界或发布约束。

Apple、Raycast 和 Figma 的外部设计规范只用于帮助组织原生性、紧凑密度
与设计令牌，不得覆盖 QuotaView 已确定的品牌、Asta Sans、Liquid Glass、
固定面板尺寸或业务语义。

## 构建后的验收边界

- 每次构建完成后，Codex 只负责代码审查、状态切换逻辑检查、自动化测试和构建结果检查。
- Codex 不主动截图，也不代替用户进行视觉或交互验收；视觉和交互结果由用户运行应用后判断。
- 除非用户在当前任务中明确要求，否则不得为了视觉验收新增自动展开、自动点击、截图或其他 UI QA 入口。
- 如果当前任务曾临时加入 UI QA、截图或自动展开代码，必须在任务结束前移除，并通过代码搜索确认无残留。
- 在没有用户视觉验收结论时，不得把本轮视觉结果记录为“已通过”；应标记为“等待用户验收”。

## 产品视觉方向

- QuotaView 是紧凑、数据优先的原生 macOS 开发工具，不是营销页面。
- 主面板强调实时额度、状态和操作；装饰不得与数据争夺注意力。
- 视觉基调是中性、清透、克制。颜色只用于状态、用量分段和关键操作。
- 主面板允许一层具有真实桌面取样的玻璃；设置窗口使用稳定、不透明、
  可读的系统表面。
- 层级优先通过排版、间距、语义表面和细分隔线建立。不得随意增加渐变、
  光晕、投影、内层大卡片或第二层玻璃。
- 原生系统控件优先于自绘控件；只有 Figma 主面板和重置流程使用已确定的
  自定义视觉语言。

## 界面与画板尺寸

所有 Figma 尺寸都已经是生产点值，必须按 1:1 映射到 AppKit/SwiftUI，
不得再次缩放。

### 主面板概览

- 宽度固定为 `274 pt`。
- 不含 Token 活动图表的既有全部内容高度为 `433 pt`；图表开启后按所选
  时间尺度和实际行数动态增高，关闭可配置内容后按可见内容动态缩短。
- 内容宽度为 `250 pt`。
- Header：`48 pt`。
- 周期额度概览：`117 pt`。
- 指标行：每行 `36 pt`。
- 额度重置入口：`51 pt`。
- Footer：`48 pt`。
- Header 和 Footer 的常规内边距为 `12 pt`；概览水平内边距为 `16 pt`。

### 额度重置详情

- 固定为 `274 × 473 pt`，不得随内容动态改变整体尺寸。
- 内容宽度为 `250 pt`。
- Header：`48 pt`。
- 可用次数 Hero：`128 pt`。
- 详情与操作区：`249 pt`。
- Footer：`48 pt`。
- 票据单枚裁切尺寸为 `22.7907 × 16 pt`，间距 `8 pt`，最大设计宽度
  `176.744 pt`；数量过多时整体等比缩小，不裁掉真实数量。

### macOS 小组件

- 使用 WidgetKit 的系统 Small / Medium 容器；Figma 参考画板分别为
  `158 × 158 pt` 与 `338 × 158 pt`，不得自行绘制外层圆角容器。
- 系统内容边距关闭后，内部统一使用 `16 pt` 边距；Medium 左右栏间距
  `12 pt`，中间分隔线为 `0.5 × 122 pt`。
- 额度数字使用 Asta Sans Semibold `32 pt`，百分号独立使用
  Semibold `16 pt`，不能把整个 `64%` 作为同字号字符串渲染。
- 额度、说明、进度和倒计时四行使用统一 `8 pt` 垂直间距；深色外观的
  “本周期剩余”使用 Regular `11 pt`，浅色外观使用 Regular `10 pt`。
- 订阅标签文字为 Semibold `9 pt`，容器为 `4 pt` 连续圆角、
  `0.5 pt` 描边、`4 pt` 内边距；显示文本继续使用 OpenAI 官方方案名称，
  不得照搬 Figma 中的静态 `PLUS`。
- 倒计时使用 Regular `11 pt`、`10 pt` 行高；时钟必须使用最新版 Figma
  导出的 `10 × 10 pt` SVG，不得继续放大旧 `8 pt` 资源。
- Figma 行高只能控制排版占位，不能与 `minimumScaleFactor` 共同压缩
  Asta Sans 的真实字号；需要横向自适应的文字必须固定垂直理想尺寸，
  保证 `9 / 10 / 11 / 12 pt` 字号不会因较短行高被二次缩小。
- 进度条高 `8 pt`、外圆角 `4 pt`、分段接缝圆角 `2 pt`、描边
  `1 pt`，并保留黑色 `12%`、radius `30`、offset `(-3.75, -3)`
  的边界内阴影。
- Medium 右侧四个指标行各高 `28 pt`，标题和值均使用 Asta Sans
  Regular `10 pt`；前三行保留 `0.5 pt` 分隔线。

### 设置窗口

- 默认内容尺寸为 `872 × 637 pt`。
- 最小内容尺寸为 `780 × 560 pt`，内容不足时使用滚动，不压缩原生控件。
- 窗口外轮廓为 `36 pt` 连续圆角。
- Sidebar 宽 `200 pt`，四周内缩 `16 pt`，自身为 `20 pt` 连续圆角。
- Sidebar 顶部为真实交通灯按钮保留 `44 pt` 空间。
- 详情区水平内边距 `24 pt`，顶部 `26 pt`，底部 `32 pt`。

### 菜单栏项目

- 图标可见本体为 `15 × 16 pt`。
- `NSImage` 逻辑画布为 `20 × 16 pt`，图标左对齐，右侧保留 `5 pt`
  透明区。
- 系统原生图文间距约 `3 pt`，最终视觉间距约 `8 pt`。
- 不得通过 SwiftUI `HStack(spacing:)` 继续调整真实状态栏图文距离。
- 至少保留图标、剩余额度或重置倒计时中的一项，不能让应用入口消失。

## 间距与几何

- 紧凑布局优先复用现有 `3 / 6 / 8 / 9 / 12 / 16 / 18 / 24 pt`
  节奏；不要为相似组件引入只差 1–2 pt 的新间距。
- 结构分区用间距和细分隔线表达，不得为每个区域增加独立大背景。
- 圆角必须与组件高度匹配。除明确的圆形按钮、胶囊或进度轨道外，圆角
  必须小于组件高度的一半。
- 数据连接状态使用 `5 × 5 pt` 圆点，不再使用文字标签或胶囊。

现有圆角语法：

| 层级 | 圆角 |
|---|---:|
| 主面板和重置详情玻璃主体 | `21 pt` |
| Demo 与重置次数小标签 | `6 pt` |
| 进度轨道 / 分段外缘 / 分段接缝 | `6 / 4 / 2 pt` |
| 主面板 App Icon 容器 | `7.5 pt` |
| 重置入口、设置分组卡片 | `12 pt` |
| 重置按钮 | `8 pt` |
| 最终确认卡片 | `26 pt` |
| 设置 Sidebar | `20 pt` |
| 设置窗口 | `36 pt` |
| 24 pt 功能按钮 | 圆形 |

## 排版

### 主面板与重置流程

- 统一使用随应用打包的 Asta Sans：
  `AstaSans-Regular`、`AstaSans-Medium`、`AstaSans-SemiBold`。
- 不得用系统字体替换 Figma 主面板中的 Asta Sans，也不得让清透和磨砂
  模式使用不同字号。
- 数字更新应保留 `.contentTransition(.numericText())`。

当前排版梯度：

| 用途 | 字体 |
|---|---|
| 主面板/重置页标题 | Asta Sans Semibold `15 pt`，tracking `-0.15` |
| 本周期剩余数值 | Semibold `21 pt`，tracking `-0.21` |
| 重置次数 Hero | Semibold `32 pt`，tracking `-0.32` |
| 指标标题和值 | Semibold / Regular `10.5 pt` |
| 辅助标签和更新时间 | Regular `10–10.5 pt` |
| 状态、订阅、Demo 标签 | Semibold `9 pt` |
| 重置卡片辅助文案 | Regular `9 pt` |
| 警告标题 | Semibold `10.5 pt` |
| 警告正文 | Regular `10 pt` |
| 最终确认标题 | Semibold `14 pt` |
| 最终确认正文与按钮 | Regular / Medium `11.5 pt` |

### 设置窗口

- 设置窗口使用 macOS 系统字体和系统排版，不使用 Asta Sans 强行覆盖。
- 页面标题为系统 `22 pt Semibold`。
- 页面说明、设置行说明使用系统 `Callout`。
- 设置行标题使用 `Body Medium`。
- 辅助说明使用 `Footnote` 或 `Caption`。
- 通用页应用名称为系统 `28 pt Semibold`。
- 中英文切换后应保持完整含义；不得通过过度压缩、任意减小字体或硬裁切
  来适应英文长度。

## 颜色与语义

### 主面板文字

- 深色外观：主要文字 `#FFFFFF`，次要文字为白色 `75%`。
- 浅色外观：主要文字 `#3A3A3A`，次要文字 `#575757`。
- 深色分隔线为白色 `12%`；浅色分隔线为黑色 `12%`。
- 普通指标图标与文字保持单色，不得使用品牌渐变装饰。

### 用量进度

- 进度条高度 `8 pt`，已用与剩余分段之间保留 `1 pt` 间隔。
- 剩余分段位于左侧，已用分段位于右侧。
- 轨道填充为黑色 `16%`，边界为白色 `12%`、`1 pt`，保留黑色
  `12%`、radius `30`、offset `(-3.75, -3)` 的内阴影。
- 已用分段：深浅外观均为白色 `32%`。
- 剩余 50%–100%：绿色 `#00FF11`。
- 剩余 20%–49%：黄色 `#FFCC00`。
- 剩余低于 20%：红色 `#FF453A`。
- 剩余分段使用不透明状态色；风险等级变化不能改变视觉密度。
- 没有有效状态时不得显示为 0%；应使用占位符并以不可用状态表达。

### Token 活动图表

- 图表位于用量数据列表下方，默认显示最近一个月；右上角提供周、月、
  三个月和半年切换，设置中提供独立显示开关。
- 每行固定 `16` 个 `12 × 12 pt` 连续圆角方格，间距 `3 pt`；总格数补齐
  为 `16` 的整数倍，真实 UTC 日期从右下角对齐，左上角使用虚线浅底
  占位格补齐。
- 周、月和三个月使用连续 UTC 日期范围；半年从最近半年内最早的有效日桶
  开始，没有范围内有效桶时使用一个月空状态。半年只作为历史上限，不得
  把更早数据带入当前图表。
- 缺失日桶的真实日期格以统计不可用呈现，不伪造成真实零用量；补齐格不
  响应 Hover，并从辅助功能树隐藏。
- 数据格使用五级不透明单色，不使用彩色或透明度混合：深色外观按
  `16% / 32% / 48% / 64% / 80%` 白阶递增；浅色外观按
  `80% / 64% / 48% / 32% / 16%` 灰阶递增。
- 数据格 Hover `0.5 s` 后显示日期和紧凑 `K / M / B` Token 用量；不得显示
  冗长的完整数字。离开格子、切换周期或图表消失时必须取消待显示 Tooltip。
- 周期切换时面板顶部保持固定，只允许下边缘在 `0.14 s` 内收缩或扩展；
  扩展前必须先准备目标内容高度，不能让 SwiftUI 新内容先进入旧窗口高度。
- 开启“减少动态效果”后取消尺寸动画并直接设置顶部固定的目标 Frame。

### 数据可用状态

- 状态圆点只表示最近一次 Codex 数据获取是否有效，不表示额度
  ready/limited/exhausted。
- 有有效快照且最新请求无错误：显示绿色 `#00D543`。
- 无快照或最新请求失败：显示红色 `#FF453A`。
- 圆点固定为 `5 × 5 pt`，位于 Footer 更新时间右侧，间距 `8 pt`；
  不增加描边、模糊、外发光或投影。
- 圆点必须提供本地化 Tooltip 和 VoiceOver 标签，分别明确“连接可用”或
  “连接不可用”，不能让辅助功能只依赖颜色判断。
- 不可用时订阅、剩余百分比和已用百分比均显示破折号，不得伪造零值。

### 设置窗口颜色

- 根表面使用 `NSColor.windowBackgroundColor`。
- 卡片使用 `NSColor.controlBackgroundColor`。
- 文字使用 `.primary`、`.secondary`、`.tertiaryLabelColor`。
- 分隔与描边使用 `NSColor.separatorColor`。
- 选中态、Switch、焦点和 Segmented Picker 使用
  `NSColor.controlAccentColor`，跟随系统强调色。
- 设置窗口不得使用 `CodexTheme.accent` 固定染色、品牌渐变、环境光晕
  或主面板的透明玻璃背景。

## 材质、玻璃与阴影

### 主面板玻璃

- 主面板主体只允许一个覆盖整面的实时背景取样玻璃层。
- macOS 26 清透模式使用一个 `NSGlassEffectView(.clear)` 处理系统折射。
- 底部 `QuotaViewBackdropBlurView` 使用
  `NSVisualEffectView(.underWindowBackground, .withinWindow)` 提供中性
  系统材质取样，合成不透明度固定为 `60%`。
- 不得叠加 `CIGaussianBlur` 复制桌面模糊，不得使用私有光学 API，
  不得申请屏幕录制权限。
- Figma 明确标记为局部 GLASS 的重置入口与重置按钮，在 macOS 26
  使用裁切在自身边界内的 `NSGlassEffectView`；macOS 14–15 使用
  `NSVisualEffectView` 回退。局部玻璃不得扩展成第二层整面背景。
- 磨砂模式使用系统 regular glass；macOS 14–15 使用现有 material
  回退路径。
- 内容、文字、图标和按钮必须位于材质取样树之外，保持清晰。
- 主内容不得重新增加整面内层背景，否则会形成双层玻璃和双重圆角。

清透玻璃参数：

- 主体连续圆角：`21 pt`。
- 深色中性黑填充：`20%`。
- 浅色中性白填充：`26%`。
- 深色边界：白色 `8%`、`0.5 pt`。
- 浅色边界：黑色 `8%`、`0.5 pt`。
- 双向内阴影：黑色 `12%`、radius `30`，offset `(6, 3)` 和
  `(-3.75, -3)`。
- 圆角投影：黑色 `20%`、radius `15`、offset `(0, 18)`。
- 透明窗口投影预留：top `3`、left/right `18`、bottom `36 pt`。
- Figma 原始光学记录为 frost `18`、refraction `0.88`、depth `88`、
  light angle `320°`、light intensity `0.40`、dispersion `0.80`、
  splay `0.12`；这些参数只是设计记录，不得用私有 API 模拟。

### 局部阴影

- 原生 `NSPanel` 矩形阴影必须关闭。
- 重置入口卡片允许既有圆角 Core Animation `shadowPath`：
  radius `20`、offset `(0, 4)`；深色黑色 `20%`，浅色黑色 `12%`。
- 重置按钮使用红色 `16%`、radius `20`、offset `(0, 4)` 的圆角
  `shadowPath`，并保留红色 `12%`、radius `10`、offset `(-2, -2)`
  的内阴影。
- 最终确认卡片保留黑色 `32%`、radius `12`、offset `(0, 6)`。
- 不得向状态标签、普通指标行、Footer 图标或设置卡片添加新投影。

## 组件规范

### Header 与 Footer

- 主面板 Header 显示 24 pt App Icon、QuotaView 标题和退出按钮。
- 重置页 Header 显示返回按钮、页面标题和 Demo 标签。
- Header 底部分隔线为 `0.75 pt`。
- Footer 顶部分隔线为 `0.5 pt`。
- Footer 左侧显示更新时间与 `5 pt` 连接状态圆点，右侧使用 24 pt 同组
  功能按钮。
- 功能图标必须使用对应深色/浅色 Figma SVG，不得用相似 SF Symbol
  随意替换。

### 订阅方案

- 数据来自 `CodexSnapshot.planType`，不得硬编码 `PLUS`。
- 空值、`unknown` 或无有效状态时显示破折号。
- 文字位于周期额度概览右上角，使用 Asta Sans Semibold `10.5 pt` 和主文字
  颜色，不绘制标签背景。
- 显示名称必须按 OpenAI 官方名称归一：`Free`、`Go`、`Plus`、
  `Pro 5x`、`Pro 20x`、`Business`、`Enterprise`、`Edu`。
- Codex 协议中的 `prolite` 映射为 `Pro 5x`，`pro` 映射为
  `Pro 20x`；旧 `team` 与用量计费枚举映射到当前官方组织方案名称。
  未知值显示破折号，不得把原始枚举直接全大写或自行创造名称。

### 指标列表与分隔线

- 周期额度概览是独立信息区，不绘制底部分隔线；普通指标属于 `info` 内容。
- 额度重置入口属于 `interactive` 内容。
- `info` 项只在下方仍有另一个 `info` 项时显示分隔线。
- 最后一个 `info` 项不能仅因为下面存在重置入口而绘制分隔线。
- 指标值变化使用数字过渡，但布局尺寸保持稳定。

### 额度重置入口

- 只在设置允许、最新状态有效且 `availableResetCredits > 0` 时显示。
- 卡片固定内容宽 `250 pt`、高 `51 pt`、`12 pt` 连续圆角。
- 入口消失时，如果用户停留在重置页，应自动返回概览。
- 当前版本只能演示，任何界面改动都不得发送
  `account/rateLimitResetCredit/consume`。

### 最终确认

- 必须渲染在 `274 × 473 pt` 玻璃内容内部，不使用系统矩形 `.alert`。
- Scrim 按 `21 pt` 连续圆角裁切，不能覆盖透明投影预留区。
- 确认卡片宽 `250 pt`、`26 pt` 连续圆角。
- 必须同时明确：消耗一次机会、立即重置符合条件的周期、不可撤销、
  当前为演示模式且不会调用真实接口。
- 确认操作为红色破坏性样式；取消保持中性。
- Escape 取消；默认操作只能落到明确的演示确认按钮。
- 弹窗显示期间，面板保持 key window，并暂停外部点击关闭监听。

### 设置组件

- Sidebar 保留原生 `.sidebar` List 的 Hover、选中、键盘焦点和辅助功能。
- macOS 26 使用 `Glass.regular` 与 `ConcentricRectangle`；macOS 14–15
  使用现有 `.regularMaterial` 回退。
- 详情页头只显示页面标题和一行说明，不重复显示 QuotaView。
- 分组卡片为 `12 pt` 连续圆角、`0.5 pt` 系统分隔色描边。
- 设置行最小高度 `52 pt`，水平内边距 `18 pt`，垂直内边距 `11 pt`。
- 设置行使用“左侧标题/说明 + 弹性间距 + 右侧原生控件”结构。
- 所有右侧控件共享 `18 pt` 右边距与同一右边缘。
- Switch 使用 `.controlSize(.small)`，不得自绘或强制放大。
- 通用页 App Icon 使用打包后的正式 macOS 图标，显示为 `96 × 96 pt`；
  不得使用带白底的 Figma 导出图代替。
- 检查更新功能未接入时必须明确说明，不得伪造网络结果。

## 交互与动效

- 所有 12 个自定义按钮都必须保留明确的 Default、Hover、Pressed、
  Disabled 状态。
- Hover 由 `onHover` 驱动；Pressed 由
  `ButtonStyle.Configuration.isPressed` 驱动。
- 24 pt 圆形按钮 Hover 缩放到 `1.04`，Pressed 缩放到 `0.94`。
- 卡片和文字按钮 Hover 不放大，Pressed 缩放到 `0.985`。
- 重置按钮 Hover 使用红色语义遮色，Pressed 使用对应外观的深色遮色；
  两种状态都必须保持 `8 pt` 圆角。
- Disabled 状态透明度为 `55%`。
- Hover 动画为 ease-out `0.14 s`；Pressed 动画为 ease-out `0.08 s`。
- 页面路由切换为 ease-in-out `0.18 s`；确认层显示为 ease-out
  `0.14 s`。
- 开启“减少动态效果”后取消缩放和过渡动画，但保留静态 Hover/Pressed
  遮色反馈。
- 深浅外观使用各自的交互遮色，不得用单一固定遮色破坏可读性。
- 控件必须保留 `.help`、`.accessibilityLabel`，必要时添加
  `.accessibilityHint`。

## 动态内容与显示规则

- 面板高度由当前可见内容计算，不能保留已隐藏行的空白。
- 所有可见业务文字、Tooltip、辅助功能标签、时间格式和倒计时单位都由
  `AppCopy` 提供，支持简体中文和 English 即时切换。
- 外观跟随系统时禁用手动浅色/深色选择；语言跟随系统时禁用手动语言
  选择。
- 浅色、深色和跟随系统外观使用同一业务状态，不因重建视图而丢失路由
  或刷新数据。
- 清透模式每次显示时应在面板已可见并成为 key window 后重建玻璃表面，
  避免渲染成非活动磨砂样式。
- 菜单面板应锚定触发点击所在屏幕；边缘间距 `8 pt`，与菜单栏间距
  `6 pt`。
- 零重置次数显示零张票据；超过设计数量时缩放整组，不伪造固定六张。
- 数据缺失、错误、刷新中和禁用状态必须有稳定布局，不能通过闪烁、跳行
  或虚构数据维持画面。

### 临时调试数据门禁

- 用户明确要求的临时虚拟数据只能通过显式 Debug-only 注入进入应用，
  Release 构建必须继续读取真实 `CodexStatusStore` 数据。
- 所有虚拟值及其派生值必须在界面、Tooltip 和辅助功能文本中标注为
  “仅用于调试 / DEBUG”，源码使用稳定标记 `DEBUG-ONLY-MOCK`。
- 在任何 commit、PR 或 GitHub push 前必须移除运行时虚拟数据注入和界面
  调试标记，恢复由最新有效 `availableResetCredits` 独占控制重置入口、
  票据数量、按钮启用状态和重置后剩余次数。
- 推送前执行
  `rg -n 'DEBUG-ONLY-MOCK|DEBUG MOCK|仅用于调试' Sources`，生产源码必须
  无匹配。

## 可读性与辅助功能

- 17 pt 以下普通文字以 4.5:1 为最低对比目标；18 pt 或粗体文字以
  3:1 为最低目标。
- 设置窗口优先使用系统语义色，使 Dark Mode、Increase Contrast 和
  Vibrancy 自动适配。
- 不用固定黑白色或文字光晕替代语义可读性。
- 小字号仅用于紧凑标签和设计稿规定的辅助信息；关键数据必须使用
  Medium 或 Semibold。
- 不能只靠颜色表达状态；状态文字、百分比、占位符和禁用状态必须同步。
- 按钮应使用 `contentShape` 覆盖完整视觉区域，并保留键盘快捷键和焦点。
- 最终发布前由产品所有者验证深色、浅色、磨砂、清透、中英文、
  Increase Contrast、Reduce Motion、键盘焦点与 VoiceOver。

## 实现约束

- 优先复用现有 Layout、Palette、Typography、ButtonStyle 和 AppKit
  玻璃组合，不要在局部视图重复定义近似令牌。
- 新增颜色、字号、圆角、阴影或动效前，先确认现有令牌无法表达需求。
- 深浅色功能图标必须成对维护；新增资源时同步检查 Asset Catalog。
- 不得将主面板的 Figma 固定色复制到设置窗口。
- 不得将设置窗口的系统控件染色规则复制到主面板状态语义。
- 不得硬编码订阅类型、额度、重置次数、更新时间或语言。
- 不得为了视觉方便改变真实业务状态或加入自动展开、自动点击路径。
- 不得提前接入真实额度重置接口。

## 修改后的验证清单

涉及 UI、资源或显示逻辑的修改至少完成：

1. 代码审查：检查布局、状态语义、深浅色分支和本地化分支
2. 状态切换：有效、不可用、刷新中、无重置次数、禁用和确认层
3. `swift test`
4. Universal Xcode Release 无签名构建
5. 检查 `CFBundleShortVersionString`、`CFBundleVersion` 和
   `x86_64 arm64`
6. 检查 `AppIcon.icns`、`Assets.car` 和新增资源
7. `git diff --check`
8. 搜索并确认没有临时截图、自动展开、自动点击或 UI QA 入口
9. 将视觉与交互结果标记为“等待用户验收”

产品所有者的视觉验收矩阵：

- 外观：浅色 / 深色 / 跟随系统
- 材质：磨砂 / 清透
- 语言：简体中文 / English / 跟随系统
- 数据：可用 / 不可用 / 刷新中 / 无重置次数
- 交互：Hover / Pressed / Disabled / 键盘 / Escape / 外部点击
- 辅助功能：Reduce Motion / Increase Contrast / VoiceOver

涉及版本、Release、Handoff 或版本历史的修改还必须完成：

1. 对照 `Support/Info.plist` 与 `Configs/App.xcconfig` 检查 Marketing
   Version 和 Build Number；
2. 检查 `HANDOFF.md` 顶部能直接定位
   `VERSION_HISTORY.md#当前最新版本`；
3. 检查 `VERSION_HISTORY.md` 能回到 `HANDOFF.md`；
4. 核对最新 tag、Release URL、发布提交、资产名、大小和 SHA-256；
5. 检查已撤回版本不会出现在 README 下载入口或最新版本指针；
6. 检查 GitHub Release Notes 只有一份源正文；
7. 使用 `rg` 搜索过期 tag、Build Number 和资产名；
8. 运行 `git diff --check`，并确认用户未跟踪文件没有进入修改范围。

如果任务只修改 Markdown 文档且没有触碰源码、资源、配置或构建脚本，可以
不重复运行 `swift test` 和 Universal Release，但必须说明这是文档-only
修改，并完成上述文档一致性检查。

## 禁止回归

- 不增加第二层主面板玻璃或整面内层卡片。
- 不把连接状态圆点重新解释为额度充足、受限或耗尽，也不恢复旧的状态
  文字胶囊。
- 不硬编码 `PLUS`、把未知方案强行大写、固定六张重置票据或显示虚假的
  0% 数据。
- 不启用原生矩形 `NSPanel` 投影。
- 不用系统矩形 `.alert` 覆盖圆角玻璃。
- 不在设置窗口恢复品牌渐变、品牌光晕或固定强调色。
- 不用相似系统图标替换已确认的 Figma 功能资源。
- 不在没有用户结论时记录视觉验收“已通过”。
