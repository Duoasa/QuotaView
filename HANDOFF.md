# QuotaView 项目 Handoff

更新日期：2026-09-11

公开版本、tag、资产、签名、公证与撤回记录的唯一事实源：
**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**。
本文件只保存当前迭代、未完成验证和下一步；分支、HEAD 与工作树状态必须
通过 Git 实时读取。

## 当前状态：0.4.7 Build 3 已发布

2026-09-11 按用户授权合并 main、发布 GitHub Stable/Latest、更新中英文 README，
并纳入 appcast。当前身份为 **0.4.7 Build 3 / internal 22 / v0.4.7-build.3**，
发布提交 `d185c9ae913c15a237ac2d223ed0a868f999f091`（PR #50）；完整资产和验证见顶部版本历史。
appcast 序列为 22 → 19 → 18。被撤回的 Build 2 已转为草稿，公开时间线不再显示，
tag 和 ZIP 保留，internal 21 继续排除。

回滚基线为 `v0.4.6-build.2` / `ae9f17d415fb1968d9ef843be771b6a5211213c7`。
本轮重新下载验证其归档哈希，未覆盖稳定回滚资产或旧 tag。
工作区：`/Users/sukduoasa/Documents/widget/.worktrees/QuotaView-0.4.7`，分支和 HEAD 以 Git 实查为准。
提交身份：`Douasa <xuchen1995@gmail.com>`。

本轮交付：
- 修复完成态 27% 百分号丢失、单行浮点边界和中英文 / Emoji 长文字越界；
  [文字边界规格](docs/design/quotaview-activity-island-turn-token-usage-0.4.5.md#6-2026-09-11-百分号与文字边界修复)。
- 代理协议菜单靠右对齐、七个设置侧栏图标改为彩色圆角矩形；
  [代理规格](docs/design/quotaview-proxy-settings-0.4.7.md)。
- 永久保留 [灵动岛内容开发台](Prototypes/IslandTextConsole/README.md)，固定入口
  `Prototypes/IslandTextConsole/Open Console.command`；源码随 Git 保存，缓存 / 本机包保持忽略。
  用户确认当前内容手动检查通过；开发台模拟数据不进入正式应用。

验证：197 项本地测试无失败，两个 opt-in 项另行通过（真实 20 秒缩小 + 100 秒隐藏、
实际安装 Codex 的 HTTP/SOCKS5 隔离账户查询）。PR CI 与 main CI 通过，Universal、
Developer ID、公证/Staple、公开回下载、签名、公钥 Feed/ZIP 验证均完成。
main 首次因测试夹具 5 秒启动等待未生成端口文件失败，同提交重跑通过；已保留失败日志。
完整辅助功能矩阵没有新增逐项验收记录，不能由当前内容检查推定全部通过。
本地验证日志与发布清单位于 `dist/verification/build3/`，不进入 Git。

后续版本必须使用新的 Build / 内部序号和唯一 tag、资产；appcast 仍需按版本单独授权。

## 0.4.6 历史工作记录

0.4.6 工作区：`/Users/sukduoasa/Documents/widget/.worktrees/QuotaView-0.4.6`。
从 0.4.5 发布源码及发布文档提交建立独立分支；已有 Kimi 预览工作区保持独立。
当前修复见 [0.4.6 Token 兼容规格](docs/design/quotaview-codex-token-compatibility-0.4.6.md)。
用户曾确认单一四步任务的实机视觉并授权发布，随后发现主任务运行时出现错误
完成回执，要求审计整条逻辑链路。审计期间暂停了发布；现已修复并获本轮视觉确认，正式发布 0.4.6。
见 [0.4.6 灵动岛逻辑审计](docs/design/quotaview-activity-logic-audit-0.4.6.md)：
9 个诊断场景已复现，涉及内部任务准入、展示归属、turn 终态、重复开始与恢复。
已按审计完成系统重构；9 个诊断场景已转为永久回归，完整测试 166 项通过。
详见 [重构验证记录](docs/design/quotaview-activity-refactor-verification-0.4.6.md)。
已完成 Universal 构建及真实主任务 / guardian / 四步计划的数据链路验证。
用户已确认本轮真实五步任务视觉无问题并要求继续发布。本次使用重构源码重新打包、公证；审计前旧 ZIP 未发布。

## 2. 历史规格与验证记录

### 0.4.6 Build 2 发布完成（2026-09-06）

用户已验收真实上下文压缩与蓝紫色思考聚簇，并明确授权作为 Build 1 的热更新
发布 GitHub、appcast 与 Apple 公证。当前生产保留原版颗粒，增强状态运动、
配色与低进度渐隐；真实任务生命周期、近似进度来源和其他特效保持原实现。

- [Release](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.6-build.2) / `v0.4.6-build.2` / 提交 `ae9f17d415fb1968d9ef843be771b6a5211213c7`。
- App / Widget：`0.4.6` / 产品 `2` / internal `19`；本地与 CI 177 项测试通过，Universal Release 通过。
- `QuotaView-v0.4.6-build.2.zip`，13,487,447 bytes，SHA-256 `5037b6318284364edd6ae7e26d4a1c4409b9ed182a425047af2af8f751f4f916`。
- Developer ID / Hardened Runtime；Apple Accepted / Staple，Submission
  `f466177a-2fea-4e61-9c11-1e405ed32bde`；最终包、解压及回下载严格签名和 Gatekeeper 通过。
- [公开 appcast](https://duoasa.github.io/QuotaView/appcast.xml) 已更新；提交 `94ae0ec0d63d4a50f77ba3a836afc98d2cb1009d`，
  SHA-256 `de8c07cc356ebf5d0c813a8e3fbd97703e879343a839a38fc30419bd4a118dce`；线上与本地一致，Feed / ZIP 内置公钥签名验证通过。
- 回下载包启动通过，运行于 `/private/tmp/quotaview-build2-public-download/extracted/QuotaView.app`；
  已退出旧验收实例并核对仅一份主应用运行，避免此前双实例视觉闪回。
- 完整发布证据及 Build 1 回滚入口见 [版本历史](VERSION_HISTORY.md#当前最新版本)。
- 剩余验证：完整外观/语言/辅助功能矩阵，以及由旧客户端实际执行的 N → N+1 安装。

### 控制台迭代历史

以下保留各阶段当时的结论；最终生产效果已按上文验收并发布。独立控制台仅在本地保留。

当前独立实验：[量子噪点 Demo 控制台](docs/design/quotaview-quantum-motion-console.md)，
位于 `Prototypes/QuantumNoiseConsole`。复用 0.4.6 原生岛体进行原版 / 候选
运动对照；仅手动 DEBUG 数据，不连接真实活动桥。最终选定的生产动效
已迁入 Build 2 并发布；控制台代码未包含在生产提交中。

全部候选状态与过渡已按临时规范重做，采用全高离散星点；压缩通过局部
重排表达。最新调整缩小星点、增强彩色状态，并将执行态改为单个轮廓起伏、
非匀速的脉冲。9 月 6 日进一步将末端改为星点逐渐稀疏、淡出的不规则边界，
弱化精确进度感；完整 175 项测试通过。
随后按反馈再次提高星点亮度与彩色饱和度，保持银白压缩与末端渐隐；
本次 9 项相关测试通过，并完成实际配色与提亮前后画面对比。
最新按用户要求恢复原版星点的细度、尺寸与疏密，移除候选十字闪芒；保留
色彩、状态运动及渐隐末端，并加入原版颗粒逐像素 GPU 对照检查。
基础闪烁分布也对齐原版，待确认色从橙红修回金黄与浅金闪点；10 项相关
检查通过，已查看实际金色呼吸画面，等待用户最终验收。
随后将待确认着色改为直接复用原版完整混色，呼吸仅调节最终亮度，避免
纯黄/偏红。用户随后澄清压缩态需要自然汇聚成簇、散开后再汇聚，而非
生硬区块；当前已移除矩形分区，改为轮廓自然变化、错峰聚散并换位的
银白星簇，保留全高底层星点。随后扩大成熟簇可见范围并提高簇核对比，
簇间曾尝试共同弧线与主次错峰。用户最新确认仅压缩态回归早期全高版
邻域自然重排，以明暗对比提效，已撤去压缩态的弧线与固定接力；当前原版
颗粒参数及其他状态保留。11 项相关检查通过，另对其他五态 34,170 个 GPU
样本作前后对照，最大密度差 1.19e-7。随后按用户新反馈，为所有状态的
起始进度保留最小可见渐隐范围，修复 1% 末端近似硬边；运动逻辑不变。
最新 12 项相关检查通过，包括低进度 30 个状态/尺寸/相位样本，等待用户验收。
已按授权观察实际控制台连续帧及完整 Demo；产品所有者最终验收仍待确认。
详细范围与采样限制见上述 Demo 规格和控制台 README。

当前开发台的临时验收约束：全高覆盖上下沿，以及清晰离散、明灭闪烁的
点点星光；禁止整体缩成中央横带或糊成光团/光圈。仅适用于
`Prototypes/QuantumNoiseConsole`，不作为项目通用或生产设计规范。
控制台阶段的历史验证见规格；当前生产验收以上文为准。

| Spec | 状态 | 结论 / 未完成项 |
|---|---|---|
| [`QV-PROTOTYPE-QUANTUM-MOTION-016`](docs/design/quotaview-quantum-motion-console.md) | `Accepted / Released` | 当前效果已获用户验收；177 项本地及 CI 测试、Universal、公证、回下载与 appcast 已验证，Build 2 正式发布 |
| [`QV-FIX-CODEX-TOKEN-COMPATIBILITY-015`](docs/design/quotaview-codex-token-compatibility-0.4.6.md) | `Accepted / Released` | 本地及 CI 166 项测试、Universal、真实五步视觉通过；PR #45 已合并，签名、公证、Latest、回下载与公开 appcast 验证完成 |
| [`QV-RELEASE-0.4.5-001`](docs/design/quotaview-0.4.5-release.md) | `Accepted / Released` | 130 项测试、Universal Developer ID、公证/Staple、GitHub Latest、回下载验证与 Stable appcast 在线 EdDSA 均已完成 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-CONFIRMATION-REMINDER-014`](docs/design/quotaview-activity-island-confirmation-reminder-0.4.5.md) | `Accepted / Released` | 真实等待确认持续满 10 秒后显示静态黄色描边与四周黄色光晕；已随 0.4.5 发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-TURN-TOKENS-013`](docs/design/quotaview-activity-island-turn-token-usage-0.4.5.md) | `Accepted / Released` | rollout 主通道的实时 Token、真实成功终态左右回执、当前额度与紧凑额度环已随 0.4.5 发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-HOVER-TRANSPARENCY-012`](docs/design/quotaview-activity-island-hover-transparency-0.4.5.md) | `Accepted / Released` | 悬停时整个灵动岛保留 20% 可见度且继续点击穿透；已随 0.4.5 发布 |
| [`QV-PRODUCT-CODEX-SOCKET-AUTOCONNECT-011`](docs/design/quotaview-codex-socket-autoconnect-0.4.5.md) | `Accepted / Released` | 只读本地任务流主通道、共享 Socket/Hook 回退及真实四步计划已验证并随 0.4.5 发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-CODEX-PLAN-010`](docs/design/quotaview-codex-plan-compatibility-0.4.4.md) | `Accepted / Superseded` | 0.4.4 未发布；原生计划、Goal、等待、真实终态和共享桥成果已由 0.4.5 继承 |
| [`QV-RELEASE-0.4.3-001`](docs/design/quotaview-0.4.3-release.md) | `Accepted / Released` | 104 项测试、Universal、Developer ID、公证/Staple、GitHub Latest、回下载启动与 Stable appcast 在线 EdDSA 均已完成 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-QUANTUM-NOISE-009`](docs/design/quotaview-quantum-noise-effect-correction.md) | `Accepted / Released` | 保留 `dropField` 持久化兼容；连续换色、增强闪灭、压缩上下文与完成反馈已随 0.4.3 发布 |
| [`QV-RELEASE-0.4.2-001`](docs/design/quotaview-0.4.2-release.md) | `Accepted / Released` | Developer ID、公证/Staple、GitHub Latest、回下载启动和 Stable appcast 在线 EdDSA 均已完成 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008`](docs/design/quotaview-activity-island-lifecycle-continuity-0.4.2.md) | `Accepted / Released` | 投递来源、ACK/队列、turn 感知终态锁与生命周期动画门控已实现；完成态只接受真实 `Stop` |
| [`QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007`](docs/design/quotaview-progress-effects-0.4.2.md) | `Accepted / Released` | 四种真实预览、细密 Drops、清晰 Slosh、状态配色适配和平滑完成反馈已随 0.4.2 发布 |
| [`QV-RELEASE-0.4.1-001`](docs/design/quotaview-0.4.1-release.md) | `Accepted / Released` | Developer ID、公证/Staple、GitHub Latest、回下载启动和 Stable appcast 在线签名核验均已完成 |
| [`QV-RELEASE-0.4.0-001`](docs/design/quotaview-0.4.0-development.md) | `Superseded / Released` | 0.4.0 只保留为大规模开发身份，不创建公开 Release；成果已由 0.4.1 Build 1 正式发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-STATE-SMOKE-006`](docs/design/quotaview-codex-activity-island-state-smoke-0.4.0.md) | `Accepted / Released` | 进度条顶层样式、计划识别、单步骤回退、完成高光分层与结束事件收敛已随 0.4.1 Build 1 发布 |
| [`QV-PRODUCT-ACTIVITY-ISLAND-SIZE-005`](docs/design/quotaview-codex-activity-island-size-0.4.0.md) | `Superseded / Released` | 0.4.1 已发布的 AI 球尺寸能力作为历史保留；0.4.5 已移除 AI 球及其展开尺寸选择器 |
| [`QV-PRODUCT-QUOTA-WINDOWS-003`](docs/design/quotaview-quota-windows-0.3.6-build.3.md) | `Accepted / Released` | 多周期额度已随 0.3.7 Build 1 发布并进入 Stable Feed |
| [`QV-PRODUCT-ACTIVITY-ISLAND-004`](docs/design/quotaview-codex-activity-island-0.3.6.md) | `Accepted / Released` | “锁定到 Codex 屏幕”已随 0.3.7 Build 1 发布；不包含多任务 Preview |
| [`QV-PRODUCT-APP-UPDATES-003`](docs/design/quotaview-app-updates-0.3.5.md) | `Accepted / Verifying` | 0.4.7 Build 3 已进入 Stable Feed，线上签名已验证；尚缺一次由旧版客户端发起的真实 N → N+1 替换与重启记录 |

### 2.0 0.4.6 Build 1 发布（2026-09-05）

- tag `v0.4.6-build.1`，发布提交 `2b071bea2f0af6fc4de042cf25084fc8524133d9`；
  [GitHub Release](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.6-build.1) 发布时为 Latest，现为 Build 2 回滚基线。
- ZIP `QuotaView-v0.4.6-build.1.zip`：`13,564,435 bytes`；SHA-256
  `00bf1a23d4424de534538871e667681ee7f27b5e475a7052e34d73cc06548174`。
- Developer ID `Chenchen Xu (BUUH229D5Q)`、Hardened Runtime；Apple Accepted
  并 Staple，Submission `456d3e31-7c35-4cca-8db1-4538abca1d6a`。
- 公开 appcast 提交 `81a16a81183cc854b97962d3a9fef613fbcc3344`，SHA-256
  `c28fb25f46501d027f58595886909f3b3663d4461bde433fd190318cd76768ca`。线上文件逐字节一致；
  Feed 和回下载 ZIP 均以应用内公钥通过 Ed25519 验证。
- 166 项测试、Universal 四目标双架构、版本/资源、签名、Staple 与 Gatekeeper
  均通过；真实五步视觉已由用户确认。回滚基线为 0.4.5 Build 1。
- 下一步：按用户新反馈迭代；等待确认/压缩的视觉组合、完整辅助功能矩阵和
  真实旧版客户端 N → N+1 替换重启仍未记录为通过。

### 2.1 0.4.5 Build 1 发布（2026-09-04）

0.4.5 在 0.4.4 未发布候选上继续开发；当前分支已提升为
`codex/0.4.5-development`，物理工作树目录保留原名以保护连续的未提交工作。
候选身份为 Marketing Version `0.4.5`、产品 Build `1`、Sparkle 内部
Build `17`。

QuotaView 现在默认以只读方式查询 `~/.codex/state_5.sqlite` 中最近活动线程的
rollout 路径，并只允许读取 `~/.codex/sessions` 内的 JSONL；数据库不可用时
才在该已知目录内做有界回退。启动只恢复仍在运行的 turn，之后每 0.25 秒读取
追加字节。单行上限 `1 MiB`、启动尾读 `16 MiB`、候选线程 `24`；不启动
Codex、不修改或写入 `~/.codex`，也不要求首次 Hook 安全确认。

当前 Codex Desktop 使用私有 stdio App Server，而独立共享 Socket 属于另一个
服务进程，不能代表 Desktop 当前任务。因而数据优先级已调整为本地任务流 >
共享 App Server > legacy Hook；共享 Socket 继续 attach-only 自动发现，
Activity Hook 与本地队列继续作为兼容回退。

本地任务流解析器只投影 task 开始/完成、Token 数值、计划状态计数、工具类别、
工作区末级名称和哈希标识；message、reply、reasoning、命令、工具输入输出、
diff 与 task 完成正文不会进入 QuotaView 模型、缓存或诊断。共享 App Server
连接继续通过 initialize capability 关闭正文类通知。设置页统一显示“本地任务
流已连接”，自动连接存在时不会显示会误卸载兼容桥的停用操作。

灵动岛在 0.4.5 收口为进度条单一样式：设置页已移除 AI 球样式、AI 球动画和
100% / 85% / 75% 展开尺寸，运行时也不再读取对应旧偏好或缩放展开几何。
旧键值原样保留以便回滚，但不会影响 0.4.5。无有效进度效果偏好时默认采用
“量子噪点”；用户已保存的合法进度效果继续生效。底层粒子球只保留为 Metal
渲染器不可用时的容错回退，不再暴露为产品选项。

产品所有者已确认真实四步计划与量子噪点进度条的视觉对应效果。当前新增悬停
透明行为：光标进入灵动岛实体表面时，整个窗口进入 80% 透明态（保留 20%
可见度），移出后恢复；窗口继续点击穿透，不阻挡后方内容。默认使用 0.14 秒
ease-out 过渡，Reduce Motion 下即时切换。产品所有者已批准该候选发布；完整
交互与辅助功能交叉矩阵不作为本次发布的已验证结论。

本次 turn Token 主通道使用 rollout 的 `token_count` 数值，Socket 通知作为
回退。QuotaView 使用线程累计总量相对 turn 起点的差值，同一 turn 只单调
增加；中途附着会恢复第一条与最新一条数值来重建基线。线程与 turn 标识进入
状态层前哈希。运行态上下两排分别共享视觉中线，左下运行详情与右下 Token
统一为 `11.5 pt`；只有同一 turn 的真实
`task_complete` 或 Socket 成功终态才显示完成回执，失败、中断、Goal 完成和
局部工具结束不会伪造成功。展开完成态改为左右布局：左侧分层显示“已完成”
和本次 Token，右侧读取主额度最新有效快照，只显示垂直居中、右对齐的大号
剩余百分比；额度不可用时显示破折号，不显示周期标题。紧凑完成态左侧保留“已完成”，右侧
显示绿/黄/红风险色额度环；圆环缩小到 `30 pt` 并与胶囊右端半圆同心。完成
量子噪点、四周辉光和描边保持紫蓝青色系；展开态和紧凑态均已移除沿边缘环绕
的高光点与线性流光，只保留固定渐变描边和外部完成辉光。岛体几何、运行态、
完成停留、悬停透明和隐藏计时均保持不变。

等待确认提醒只由真实 `awaitingConfirmation` 状态驱动：从事件时间开始持续
满 `10 s` 后，使用既有 `#FFCC00` 风险黄色显示 `1 pt` 静态完整描边与岛体
后方四周光晕；同一 turn 的重复等待通知不重置计时，离开等待、切换任务、
完成、中断、失败或隐藏时立即撤销。描边不移动，光晕复用现有呼吸节奏；
Reduce Motion 下两者保持静态。完成态仍独占紫蓝青反馈，不与提醒串色。

`swift test` 130 项通过、0 失败；测试覆盖旧 AI 球/动画/尺寸偏好被忽略、
进度条唯一几何、量子噪点默认值、悬停透明度，以及 Token 解码、累计差值、
重复通知、终态冻结、新 turn 重置、rollout 正文忽略、活动 turn 恢复、增量
尾读、格式化、本地化、VoiceOver、成功回执门控和确认提醒计时/撤销。Universal Release 无签名
构建通过，App、Core、Widget 与 Activity Hook 均为 `x86_64 arm64`；版本、
Build、资源和干净临时副本的 ad-hoc 严格校验通过。开发 ZIP SHA-256 为
`fc247a259f9f25f6f405bccbd5308ad1582667ff7bfa55ec34a77c635c99c297`。
新干净副本以 PID `80828` 启动；只读额度探针确认主数据可用，已用 `52%`、
剩余 `48%`。产品所有者已检查关键视觉路径并批准发布。

PR #42 的 GitHub CI 通过后已合并到 `main`；发布提交与 tag commit 为
`75913c07e4457b5f6451f286522799d36982ff0c`。正式资产
`QuotaView-v0.4.5-build.1.zip` 为 `13,477,643 bytes`，SHA-256 为
`d5308880d9dc096e46cdbf715db414ae79a4bc92a1dcc4f433d315a6a7bd7e5a`。
Developer ID 与 Hardened Runtime 有效；Apple 公证 Accepted 并已 Staple，
Submission 为 `67ae8361-068b-4adf-aecf-de2f2b174e07`。GitHub Release 已设为
Latest、非 Draft、非 Pre-release；回下载资产与本地公证包逐字节一致，并在
宿主环境通过嵌套签名、Staple、Gatekeeper、版本、资源和四目标双架构复核。

Stable appcast 已由 `gh-pages` 提交
`9fc9745a9464f42d890c119a13dabf87896d09a5` 发布；线上 Feed SHA-256 为
`d4e1d5a218742b743c04305c3ab29e27bbfaece1f0f4b7d7ab788b16bb6a3b01`，
与本地签名文件逐字节一致且 EdDSA 验证通过。完整交互与辅助功能交叉矩阵
不作为本次发布的已验证结论。

### 2.2 0.4.4 Build 1 未发布候选（2026-09-03）

曾从 `0.4.3 Build 1` 稳定基线建立独立工作树和
`codex/0.4.4-development` 分支。候选身份为 Marketing Version `0.4.4`、
产品 Build `1`、Sparkle 内部 Build `16`；该候选未发布，分支已提升并重命名
为 `codex/0.4.5-development`，成果由 0.4.5 继续继承。

已实现 App Server `turn/plan/updated`、`turn/completed`、
`thread/status/changed` 与 `thread/goal/updated` 的隐私安全适配；Activity
Hook schema 升级为 v3 并登记真实 `Interrupt`，同时兼容 schema v1/v2 和
legacy `tools.update_plan(...)`。原生计划优先且同一 turn 不倒退，Goal-only
不伪造步骤，中断与失败不会显示 100% 或完成高光。

真实 Codex CLI `0.152.1` 探针确认：默认配置下正式四步任务不会产生
`turn/plan/updated`；线程级启用 `tools.update_plan.enabled` 后，同一类任务
产生 9 次原生计划更新并正常完成。0.4.4 现已增加显式 opt-in 的共享 App
Server 客户端，通过 Unix WebSocket 枚举已加载任务、恢复实时订阅并只向
现有投影层转发已知原生通知；正文不落盘，线程与 turn 标识只保留哈希。

服务端双客户端探针已收到完整四步状态序列。随后运行中的 0.4.4 QuotaView
与真实 Codex 客户端连接同一共享服务，在禁用 Hook 的任务中收到 5 次原生
计划通知及同一 session/turn 的真实 `Stop`，原生数据桥的进程级端到端退出
标准已满足。`CODEX_APP_SERVER_USE_LOCAL_DAEMON=1` 已写入当前用户的
launchd 环境；当前 Codex Desktop 未在任务中重启，Desktop 发起任务的最终
用户验证需在下次启动后完成。

`swift test` 117 项通过、0 失败；Universal Release 本地开发构建通过，App、
Widget 与 Activity Hook 均为 `x86_64 arm64`，版本、Build、资源和 ad-hoc
签名校验通过。`dist/QuotaView.app` 已完成启动冒烟并保持运行，开发 ZIP 的
SHA-256 为
`573b29f81fb74707b163a62ce87aaf01a975d4da7cbc8d1114f69f1651ac176c`。
当前未执行 Developer ID、公证、发布、commit 或 push；主要功能、视觉、
交互和辅助功能验收仍等待产品所有者。

### 2.3 0.4.3 Build 1 发布（2026-09-03）

产品所有者已将 2026-08-30 固定的视觉检查点指定为 `0.4.3 Build 1`，
Sparkle 内部序号从 `14` 单调递增为 `15`，并授权合并 `main`、发布 GitHub
Release 与更新 Stable appcast。

范围包括量子噪点连续相位、细密闪灭、完成态粒子覆盖、压缩上下文灰白
可见性、粒子不透明度增强、两级不透明淡灰文字与操作流光，以及统一为
sRGB `#00FF11` 的完成描边和呼吸光晕。完整视觉与辅助功能交叉矩阵仍只由
产品所有者验收，不以自动化测试替代。

PR #40 已合并到 `main`，发布提交为
`b76c317d640e73621b6e2119e4363d0cac6ddff6`。完整 `swift test` 104 项通过、
0 失败；Universal、Developer ID、Apple 公证/Staple、GitHub Latest、远端
资产逐字节回下载、`/Applications` 启动与单一 Widget 注册均已验证。

正式资产 `QuotaView-v0.4.3-build.1.zip` 为 `13,166,345 bytes`，SHA-256
`a2b35249c3c146444207fc82d041121e790d099cc534b597775262e42160d54c`；
公证 Submission 为 `e3f5f0fa-8f36-4ed3-8b26-3b6ef1861344`。Stable appcast
由 `gh-pages` 提交 `56c02c07cebfbeb19a2684ee3dff2bce2f6bbe0c` 发布，
线上 SHA-256 为
`2e5b058592c5b823511391e54a4d873c962d787f54899c1dc1e9da034a9eb40a`，
逐字节与 EdDSA 验证通过。完整视觉与辅助功能交叉矩阵未单独记录为全量
通过。

## 3. 长期边界

- 后续版本必须由产品所有者针对精确版本重新批准，不能沿用 Build 2 的
  appcast 准入；
- 当前稳定版与回滚基线以本文第 1 节及版本历史为准；历史 tag 和资产不可覆盖；
- GitHub push、tag 或 Release 默认不进入自动更新序列；
- 稳定版只保留单任务灵动岛。多任务 Preview 的 tag、Release 和归档分支
  `codex/archive-0.3.2-preview.1-multitask-island` 仅供历史参考；
- 完整视觉、交互与辅助功能结论只能由产品所有者验收后记录。

## 4. 下一步

0.4.7 Build 3 已完成本轮修复与正式发布；下一轮按用户新反馈迭代，以下待办独立保留。

1. 更新器规格的 `APP-UPDATES-07` 保持独立待办，后续记录一次由旧版客户端
   发起的真实 N → N+1 替换与重启；
2. 完整深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 矩阵
   仍由产品所有者按需补充，不记录为本次全量通过。

## 5. 文档入口

- [长期执行与设计规范](AGENTS.md)
- [SDD 注册表](docs/specs/README.md)
- [SDD 开发流程](docs/specs/DEVELOPMENT_PROCESS.md)
- [版本历史](VERSION_HISTORY.md)
- [视觉验收记录](design-qa.md)（按需读取）
