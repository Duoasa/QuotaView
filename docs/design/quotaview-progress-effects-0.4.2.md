# QuotaView 0.4.2 进度条效果库规格

> Spec ID：`QV-PRODUCT-ACTIVITY-ISLAND-PROGRESS-EFFECTS-007`
>
> 状态：`Accepted / Verifying`
>
> 日期：2026-08-30
>
> 生产基线：`0.4.1 Build 1` / `v0.4.1-build.1`
>
> 本地候选：`0.4.2 Build 1`；Sparkle 内部更新序号 `14`

本规格受 [`PROGRESS_EFFECT_ADAPTATION.md`](../specs/PROGRESS_EFFECT_ADAPTATION.md)
约束，只扩展进度条灵动岛内部效果与设置选择，不改变 0.4.1 已发布的进度
语义、窗口、排版、生命周期、完成高光或 AI 球。

## 决策

保留现有“状态烟雾”作为默认效果，在 `.progressBar` 顶层样式内新增一个
持久化的进度效果选择：状态烟雾、晶钻前沿、液滴涌动、液态涌浪。设置页
使用四个 `88 × 88 pt` 圆角方形 Metal 实时预览，预览与生产岛体共用同一
shader、状态 Profile 和进度映射，只降低预览刷新率。

参考编辑器当前要求登录，因此本轮以三个 URL 中明确的 `diamond`、`drops`
与 `slosh` 样式名、60% 进度和动态参数作为形态事实，并以产品所有者提供的
截图校准粒度；不复制 MetalForge 代码或资源。URL 预设色不再作为运行时
颜色来源：产品所有者在第一轮视觉验收中明确要求三个新效果在每一种 Codex
状态下精确复用“状态烟雾”的状态 Profile 颜色。

## 目标

- 进度条灵动岛提供四种可持久化选择，新安装和旧用户继续默认状态烟雾；
- 三种新增效果清楚表达同一个单调前沿，并响应全部活动状态；
- 设置页圆角方形预览使用真实渲染器、固定 60% 工作态样本，不使用图片；
- 切换效果立即更新当前灵动岛，不重建任务状态或改变窗口尺寸；
- Reduce Motion、Metal 降级、隐藏暂停和完成反馈继续成立。

## 非目标

- 不修改近似进度算法、事件解析或单任务生命周期；
- 不新增灵动岛窗口，不改变 `402 × 68 pt` 展开尺寸、文字位置或紧凑态；
- 不修改 AI 球动画、三档尺寸、Widget、菜单面板或额度业务；
- 不接入 MetalForge 代码、资源、账号或网络依赖；
- 不把功能规格中的本地候选证据解释为发布事实；正式发布由
  [`QV-RELEASE-0.4.2-001`](quotaview-0.4.2-release.md) 独立验收。

## 效果登记

| ID | 名称 | 参考与进度载体 | 结束动作 |
|---|---|---|---|
| `stateSmoke` | 状态烟雾 / State Smoke | 0.4.1 生产效果；烟雾前沿的位置与扩散尾迹 | 沿用完整铺满、变暗、淡出 |
| `diamondFront` | 晶钻前沿 / Diamond Front | MetalForge `style=diamond`；按前沿依次点亮错列菱形，末端集中珊瑚色高光 | 菱形队列补齐后降低能量并淡出 |
| `dropField` | 液滴涌动 / Drop Field | MetalForge `style=drops`；使用约 1–2 可见像素的高密度荧光微粒，以粒子占用率在前沿前逐步稀疏表达进度，不绘制大颗粒水滴轮廓 | 微粒场补齐并沉降后淡出 |
| `sloshFlow` | 液态涌浪 / Liquid Slosh | MetalForge `style=slosh`；深蓝液体覆盖区在进度末端形成带滞后的弹性波面与回波 | 液面推满全宽、回波收敛后淡出 |

三个新增效果与状态烟雾逐状态共用完全相同的背景色、深色、中间色和高光
色，只改变几何密度、速度、扰动与能量的视觉用法；失败保持红色不稳定语义，
等待确认使用克制的橙色脉冲，压缩上下文降低运动，未连接与不可用停止主要
运动，完成仍交还 0.4.1 的纯绿色描边和四周呼吸辉光。

## Requirement

| ID | Requirement |
|---|---|
| `PROGRESS-EFFECTS-01` | `.progressBar` 内新增稳定枚举 `stateSmoke / diamondFront / dropField / sloshFlow`，偏好独立持久化；缺失或未知值回退 `stateSmoke` |
| `PROGRESS-EFFECTS-02` | 旧 `smokeProgress` 迁移和现有 `progressBar` 用户继续看到状态烟雾；不得改写 AI 球动画偏好 |
| `PROGRESS-EFFECTS-03` | 四种效果共用现有 0%、1%识别期、计划/单步骤推进、95%封顶、100%完成和不倒退投影 |
| `PROGRESS-EFFECTS-03A` | 非 Reduce Motion 下，进度前沿向新目标值的指数追赶系数由 `7.0` 降为 `3.5`，视觉速度减半、达到同等接近程度的时间约翻倍；不得改变真实百分比、单调性或完成时序 |
| `PROGRESS-EFFECTS-04` | 晶钻、液滴和涌浪只在当前前沿内激活，局部脉冲与液面回波不得造成进度回退或循环播放的感知；液滴使用像素级高密度微粒并在到达前沿前通过占用率变稀，不得恢复大颗粒轮廓 |
| `PROGRESS-EFFECTS-05` | 三个新效果对每一种 Codex 状态都必须精确复用状态烟雾的背景、深色、中间色和高光色；不可用状态停止主要运动，失败为红色，等待确认为橙色提示 |
| `PROGRESS-EFFECTS-05A` | 液态涌浪的液体主体、波峰与两级回波在 60% 设置预览和生产岛体中必须清楚可辨，同时继续位于文字下层且不得过曝 |
| `PROGRESS-EFFECTS-06` | 普通运行态继续从可见进度左端 50% 增强到末端 100%，完成瞬态可完整铺满；文字不新增阴影、底板或发光 |
| `PROGRESS-EFFECTS-07` | 完成事件只播放一次共用填充、变暗和淡出时序，再显示既有绿色描边与四周呼吸辉光；晶钻、液滴和涌浪在填充走满后增加约 `0.30 s`、峰值强度不高于 `14%` 的局部细节高亮，状态烟雾保持原样，Reduce Motion 不播放该脉冲；离开完成态清除残留 |
| `PROGRESS-EFFECTS-08` | 设置仅在顶层样式为进度条时显示四个圆角方形真实预览；按钮具备选中、Hover、Pressed、键盘、Tooltip 与 VoiceOver 状态 |
| `PROGRESS-EFFECTS-09` | 预览固定使用工作态 60% 进度、`88 × 88 pt` 连续圆角、30 FPS；窗口移除后停止渲染，Reduce Motion 为静态帧 |
| `PROGRESS-EFFECTS-10` | 切换效果不得改变展开/紧凑尺寸、文字几何、任务状态、AI 球设置或窗口数量 |
| `PROGRESS-EFFECTS-11` | Metal 不可用时继续显示原生岛体和文字，不创建替代窗口或伪造进度 |
| `PROGRESS-EFFECTS-12` | 候选身份统一为 Marketing `0.4.2`、产品 Build `1`、Sparkle 内部序号 `14`；只有发布规格全部门禁通过后才能进入 Stable appcast |

## 性能与降级预算

- 生产岛体仍只创建一个 Metal 进度渲染器，切换通过一个整数 uniform 完成；
- shader 保持固定次数循环，不分配纹理、不读取网络或文件；
- 设置页最多四个 30 FPS 预览，离开窗口立即暂停；Reduce Motion 只重绘
  状态或选择变化；
- Metal 初始化失败时复用现有原生背景、文字和无效果降级路径。

## 验证与验收

自动化至少覆盖：四种枚举默认值与持久化、未知值回退、旧偏好迁移、四种
效果 uniform 标识和 Profile 状态差异、60% 预览契约、进度投影、完成时序、
Reduce Motion、窗口几何与 AI 球隔离。随后运行相关定向测试、`swift test`、
Universal Release 无签名构建、版本/架构/资源检查、临时代码搜索和
`git diff --check`。

深浅色、简中/英文、四种效果的展开/紧凑态、状态切换、Reduce Motion、
Increase Contrast、VoiceOver、长时间观感及对 MetalForge 参考的视觉相似度
均等待产品所有者在本地候选 App 中手动验收和调整，不由自动化宣称通过。

## 第一轮工程证据与当前反馈

- 四种效果偏好、未知值回退、旧偏好迁移、状态 Profile、60% 预览契约和
  Metal shader 编译已进入 `AppBehaviorTests`；
- `swift test`：94 项通过、0 失败；
- Universal Xcode Release 本地 ad-hoc 构建通过，App、Widget 与 Activity
  Hook 均为 `x86_64 arm64`；包内身份为 Marketing `0.4.2`、内部序号
  `14`、产品 Build `1`；
- `AppIcon.icns`、`Assets.car` 与严格深层签名检查通过；本地归档
  `QuotaView-v0.4.2-build.1.zip` 的 SHA-256 为
  `db514d711ebe8dccfe3be7fd8a3302bcc00f80cf8aa1f0f18c90364f9e33cfa9`；
- 尚未完成产品所有者视觉、交互与参考相似度验收；本地候选未 commit、
  push、公证或发布。

第一轮产品所有者验收确认两项未通过：液滴颗粒过大，未形成截图中的细密
噪点感；液态涌浪可视性过低。另明确三个新效果的状态颜色必须以状态烟雾为
唯一参照，不按 URL 预设色独立着色。当时规格因此回到 `Implementing`，上方
第一轮自动化和归档证据不代表本次调整后的候选结果；第二轮工程验证完成后
已重新进入 `Verifying`。

## 第二轮工程证据

- Drops 已由 `5.5` 行大颗粒轮廓改为 `2.35` 渲染像素单元的高密度微粒，
  前沿前 `12.5%` 区间通过粒子占用率从密集逐步稀疏，末端不越过当前进度；
- Slosh 液体主体密度下限从 `0.22` 提高到 `0.50`，同步增强 caustic、波峰
  与两级回波，但仍受共用文字区透明度和当前前沿裁切；
- 自动化遍历九种 Codex 视觉状态和四种效果，确认三个新增效果的完整状态
  Profile 与状态烟雾精确相等；Metal shader 生产管线编译通过；
- `swift test`：94 项通过、0 失败；Universal Xcode Release 本地 ad-hoc
  构建通过，App、Widget 与 Activity Hook 均为 `x86_64 arm64`；
- 包内身份保持 Marketing `0.4.2`、内部序号 `14`、产品 Build `1`，资源和
  严格深层签名检查通过；新归档 SHA-256 为
  `243efc3d60c21a6d7bcc2a814c3cbcc23ce08854c7cd0f01175584a672d864d4`；
- 产品所有者已确认当前候选完成度满足发布；完整深浅色、多屏、VoiceOver、
  Increase Contrast 与 Reduce Motion 交叉矩阵未单独记录为全量通过。正式
  签名、公证、GitHub Release 与 appcast 证据由发布规格记录。
