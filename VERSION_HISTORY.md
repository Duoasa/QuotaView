# QuotaView 版本历史

本文件是 QuotaView 的版本索引和历史发布记录。当前开发状态、未完成事项与
下一次迭代入口请阅读 [HANDOFF.md](HANDOFF.md)，当前规格与交付阶段请阅读
[SDD 规格索引](docs/specs/README.md)。

记录范围为已创建 GitHub Release/tag 的公开版本，以及已经撤回但需要保留
故障背景的 Build 3；未形成独立 Release 的内部构建不单独列为历史版本。

## 当前最新版本

> Codex 版本定位入口：读取 `HANDOFF.md` 时，必须先核对本节，再继续处理
> 当前迭代。除非用户明确指定旧版本，否则一律以这里标记的最新版本作为
> 产品与发布基线。

| 项目 | 当前值 |
|---|---|
| 最新推荐版本 | `0.4.2 (Build 1)` |
| Git tag | `v0.4.2-build.1` |
| Tag commit | `6c8434950d59afd9439b2f6f50d8c8b091a40f6d` |
| GitHub Release | [QuotaView 0.4.2 Build 1 — More Progress Styles, Steadier Activity](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.2-build.1) |
| Release 资产 | `QuotaView-v0.4.2-build.1.zip` |
| 资产大小 | `13,166,133 bytes` |
| SHA-256 | `a87f7f03da644fb014a8c90b617b99697bbb6aae72a7c35928d3386bbf2c05a3` |
| 最低系统版本 | macOS 14 |
| 架构 | Universal `arm64 + x86_64` |
| 签名 | `Developer ID Application: Chenchen Xu (BUUH229D5Q)`，证书 SHA-1 `E52D0A9C7C377AF77C484155CC0CFCFB27D949D3`，启用 Hardened Runtime |
| 公证 | Apple Accepted，已 Staple；Submission `5cad0ca0-7f2e-49ef-beda-34b151ed2f45` |
| 发布状态 | 正式 Release、Latest、非 Draft、非 Pre-release |
| 自动更新 Feed | [公开 appcast](https://duoasa.github.io/QuotaView/appcast.xml)；`gh-pages` 提交 `ead810f540261fbd3e67d17f0f0d32401606b0c0`；Feed SHA-256 `a8ddb8809340caed56dbf0743ab71f51bb2bae6a1a8a067676853cfd76185e8b`；线上文件逐字节一致且 EdDSA 验证通过 |

上一稳定回滚基线：

| 项目 | 封存值 |
|---|---|
| 版本 | `0.4.1 (Build 1)` |
| tag / commit | `v0.4.1-build.1` / `e14039eeb7021041f384b10db386a80844694b0f` |
| Release | [QuotaView 0.4.1 Build 1 — A Progress-Aware Codex Island](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.1-build.1) |
| 资产 / SHA-256 | `QuotaView-v0.4.1-build.1.zip` / `ae8cf53acc6e6473ebf33bb853b7448672b48c4e849ef4b219efd74b18a9a2a3` |
| 状态 | 不可移动历史正式版；发生 0.4.2 回滚时使用该 tag 与已核验资产 |

当前公开预览版：

| 项目 | 当前值 |
|---|---|
| 最新预览版本 | `0.3.2 (Build 1) Preview 1` |
| Git tag | `v0.3.2-preview.1` |
| Tag commit | `f835bcd46a3d0197e9dc09e0b5a25a6d5d69521c` |
| GitHub Release | [QuotaView 0.3.2 Preview 1 — Multi-task Codex Island](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.2-preview.1) |
| Release 资产 | `QuotaView-v0.3.2-preview.1.zip` |
| 资产大小 | `11,543,516 bytes` |
| SHA-256 | `e39b0d004c2ce2d7d739f5b1f1dc9037335c63d2ee6d663d8129327433f13587` |
| 最低系统版本 | macOS 14 |
| 架构 | Universal `arm64 + x86_64` |
| 签名 | `Developer ID Application: Chenchen Xu (BUUH229D5Q)`，启用 Hardened Runtime |
| 公证 | Apple Accepted，已 Staple；Submission `47c6d413-465f-4632-b7d2-1e48ed03f9a0` |
| 发布状态 | GitHub Pre-release、非 Draft、非 Latest |

> 当前生产版本为 `0.4.2 (Build 1)`。本版增加四种进度条效果与真实设置
> 预览，并修正多步骤任务中的误隐藏、提前完成和空闲动画；不迁入多任务
> Preview。
> 正式签名、公证/Staple、GitHub Release/Latest、回下载和公开签名 appcast
> 均已完成；详细证据见本文件的 `0.4.2 (Build 1)` 章节。

> 未发布开发版本不在本历史文件登记；当前迭代身份与验证状态只以
> [HANDOFF.md](HANDOFF.md) 为准，不得把候选版本提前写成已发布。

> “Codex 灵动岛多任务适配”已作为 `0.3.2 Preview 1` 发布，交付状态为
> `Released`。响应速度、当前任务跟随、任务切换与收展节奏仍是公开已知
> 不足，因此该版本不晋升为稳定版；其实现不包含在 0.4.2 稳定版中。
> GitHub Pre-release、tag 和本地归档分支继续保留供社区测试和后续开发
> 参照。当前状态以
> [SDD 当前规格](docs/specs/README.md#当前规格) 为准。

## 版本总览

| 版本 | 日期（Asia/Shanghai） | 状态 | 核心定位 |
|---|---|---|---|
| `0.4.2 (Build 1)` | 2026-08-30 | **当前最新** | 四种进度效果、真实设置预览与可靠的任务连续性 |
| `0.4.1 (Build 1)` | 2026-08-30 | 历史正式版 / 0.4.2 回滚基线 | 独立进度条灵动岛、近似进度、AI 球三档尺寸与完成高光 |
| `0.3.7 (Build 1)` | 2026-08-26 | 历史正式版 | 多周期额度完整展示与灵动岛多屏锁定 |
| `0.3.6 (Build 2)` | 2026-08-23 | 历史正式版 | 单任务 Codex 灵动岛动画、显示与事件时间个性化 |
| `0.3.5 (Build 5)` | 2026-08-11 | 历史正式版 | Spark 与 30 日用量概览、半年 Token 活动、Stable 应用更新检查 |
| `0.3.3 (Build 3)` | 2026-08-11 | 历史正式版 | Token 活动统计、单色方格图与顶部固定动态面板 |
| `0.3.2 (Build 1) Preview 1` | 2026-08-05 | **当前预览版** | Codex 灵动岛多任务支持与可选当前任务跟随 |
| `0.3.1 (Build 2)` | 2026-08-01 | 历史正式版 / 0.3.3 回滚基线 | Widget 共享容器热修复与可变额度周期文案 |
| `0.3.1 (Build 1)` | 2026-07-30 | 历史正式版 | Codex 灵动岛实时任务状态与官方 Hooks 连接 |
| `0.2.1 (Build 1)` | 2026-07-30 | 历史正式版 | 原生 WidgetKit 小组件与 Developer ID 公证分发 |
| `0.2.0 (Build 4)` | 2026-07-29 | 历史正式版 | UI 热更新与下载版启动可靠性修复 |
| `0.2.0 (Build 3)` | 2026-07-29 | **已撤回并删除** | UI1/UI2 组件细节迭代；发布包存在 Framework 加载故障 |
| `0.2.0` | 2026-07-28 | 历史正式版 | 核心架构重构后的首个正式版本 |
| `0.1.5 (Build 6)` | 2026-07-27 | 历史正式版 | 原生菜单面板、玻璃外观、设置窗口和状态标签热修复 |
| `0.1.3` | 2026-07-26 | 历史正式版 | 设置、外观、语言、图标和发布流程完善 |
| `0.1.0` | 2026-07-26 | 首个公开版本 | Codex 额度、Credits、Token 与重置时间基础能力 |

## 0.4.2 (Build 1)

Tag：`v0.4.2-build.1`

状态：当前最新正式 Release、GitHub Latest、非 Draft、非 Pre-release；
已进入公开 Stable appcast。

发布提交：
`6c8434950d59afd9439b2f6f50d8c8b091a40f6d`

主要特性：

- 进度条灵动岛提供状态烟雾、晶钻前沿、液滴涌动和液态涌浪四种选择，
  设置页使用圆角方形真实预览；
- 三个新增效果完整复用九种 Codex 状态配色；Drops 使用细密微粒，Slosh
  提高液体主体与回波可视性；
- 计划进度前沿衔接速度减半，三个新增效果在走满后提供克制的短暂高亮，
  Reduce Motion 保持静态；
- Activity Hook 支持直接与包装计划计数，并以 ACK、持久队列和事件去重
  提高结束事件投递可靠性；
- 局部工具步骤、事件沉默和 App Server 状态不再制造完成或隐藏；只有真实
  Hook `Stop` 进入完成态，`SessionEnd` 立即隐藏；
- Product Build 为 1，Sparkle 内部更新序号为 14。

验证与发布资产：

- `swift test`：103 项通过、0 失败；PR #36 GitHub CI 通过并合并到 `main`；
- Universal Release 构建通过；App、Widget 与 Activity Hook 均为
  `x86_64 arm64`；版本为 Marketing `0.4.2`、内部 `14`、产品 Build `1`；
- 文件名：`QuotaView-v0.4.2-build.1.zip`
- 大小：`13,166,133 bytes`
- SHA-256：
  `a87f7f03da644fb014a8c90b617b99697bbb6aae72a7c35928d3386bbf2c05a3`
- Developer ID：`Developer ID Application: Chenchen Xu (BUUH229D5Q)`，
  证书 SHA-1 `E52D0A9C7C377AF77C484155CC0CFCFB27D949D3`，启用
  Hardened Runtime；
- Apple 公证：Accepted，已 Staple；Submission
  `5cad0ca0-7f2e-49ef-beda-34b151ed2f45`；
- GitHub 回下载资产与本地公证包逐字节一致；重新解压后通过嵌套
  `codesign --deep --strict`、Staple、Gatekeeper、版本、资源与三目标双架构
  复核，并完成独立启动冒烟；
- GitHub Release Notes 使用
  `docs/releases/QuotaView-0.4.2-build.1.md` 的单份简洁英文源文；
- 公开 Feed：`https://duoasa.github.io/QuotaView/appcast.xml`；`gh-pages`
  提交 `ead810f540261fbd3e67d17f0f0d32401606b0c0`；Feed SHA-256
  `a8ddb8809340caed56dbf0743ab71f51bb2bae6a1a8a067676853cfd76185e8b`；
  线上文件与本地签名文件逐字节一致，Feed EdDSA 验证通过；
- 产品所有者已批准当前结果发布；完整深浅色、多屏、VoiceOver、Increase
  Contrast 与 Reduce Motion 交叉矩阵未单独记录为全量通过。

Release：
[QuotaView 0.4.2 Build 1 — More Progress Styles, Steadier Activity](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.2-build.1)

## 0.4.1 (Build 1)

Tag：`v0.4.1-build.1`

状态：历史正式 Release、0.4.2 的封存回滚基线、非 Draft、非 Pre-release；
已由 0.4.2 Build 1 替代。

发布提交：
`e14039eeb7021041f384b10db386a80844694b0f`

主要特性：

- 在既有 AI 球之外增加独立进度条灵动岛；展开态使用左侧对话标题与状态
  详情、右侧当前状态的紧凑双栏排版，全部简中/英文状态使用固定几何；
- 结构化计划按完成步骤与进行中步骤的保守权重估算进度，先在 1% 等待
  4 秒识别步骤；无计划时平滑接入封顶 50% 的单步骤生命周期估算，迟到计划
  可接管且不倒退，真实结束事件才确认 100%；
- 状态烟雾以低亮度冷灰白、低饱和亮青蓝等语义色表达工作状态，透明度随
  当前烟雾宽度从左端 50% 拉伸到前沿 100%；上下文压缩降低速度与扩散，
  其他活动状态使用周期变速扩散；
- 完成时烟雾铺满、变暗并淡出，露出原生岛体；岛体上层保留稳定 `1 pt`、
  sRGB `#00FF11` 绿色描边，下层四周呼吸辉光不再由矩形窗口边界截断；
- AI 球展开态支持 100%、85%、75% 三档整体等比缩放，尺寸偏好不影响
  进度条样式或紧凑态；
- Activity Hook 支持直接与 `exec` 包装的计划事件，只传步骤状态计数，不传
  原始脚本、步骤文本、计划说明、工具参数或输出；缺失/迟到结束事件不再让
  无任务岛体持续显示；
- Product Build 为 1，Sparkle 内部更新序号为 13。

验证与发布资产：

- `swift test`：93 项通过、0 失败；PR #34 GitHub CI 通过并合并到 `main`；
- Universal Release 构建通过；App、Widget 与 Activity Hook 均为
  `x86_64 arm64`；版本为 Marketing `0.4.1`、内部 `13`、产品 Build `1`；
- 文件名：`QuotaView-v0.4.1-build.1.zip`
- 大小：`13,068,004 bytes`
- SHA-256：
  `ae8cf53acc6e6473ebf33bb853b7448672b48c4e849ef4b219efd74b18a9a2a3`
- Developer ID：`Developer ID Application: Chenchen Xu (BUUH229D5Q)`，
  证书 SHA-1 `E52D0A9C7C377AF77C484155CC0CFCFB27D949D3`，启用
  Hardened Runtime；
- Apple 公证：Accepted，已 Staple；Submission
  `fd08ea22-9a55-4f63-9279-f10f0663eb7a`；
- GitHub 回下载资产与本地公证包逐字节一致；重新解压后通过嵌套
  `codesign --deep --strict`、Staple、Gatekeeper、版本、资源与架构复核，
  回下载正式包完成独立启动冒烟；
- GitHub Release Notes 使用
  `docs/releases/QuotaView-0.4.1-build.1.md` 的单份英文源文；
- 公开 Feed：`https://duoasa.github.io/QuotaView/appcast.xml`；`gh-pages`
  提交 `e8312e45e344fbb9fcb01875ab27a65ce47506d0`；Feed SHA-256
  `afcce62e375f3f35f6557308343e47349e0d895ab23489fb101b537c58abc852`；
  线上文件与本地签名文件逐字节一致，Feed EdDSA 验证通过；
- 产品所有者已确认当前生产 App 未发现新的视觉问题并批准继续发布；完整
  深浅色、多屏、VoiceOver、Increase Contrast 与 Reduce Motion 交叉矩阵
  未形成独立记录，不由发布事实自动视为全量通过。

Release：
[QuotaView 0.4.1 Build 1 — A Progress-Aware Codex Island](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.1-build.1)

## 0.3.7 (Build 1)

Tag：`v0.3.7-build.1`

状态：历史正式 Release、0.4.1 的封存回滚基线、非 Draft、非 Pre-release；
已由 0.4.1 Build 1 替代。

发布提交：
`6f6f30a58141deff45a5b2c67546421cba06ad70`

主要特性：

- 将 Codex `primary` 与 `secondary` 额度窗口独立建模、使用稳定行 ID，并按
  实际周期从短到长显示；5 小时与周额度可以同时完整呈现；
- 额度标题由真实 `windowDurationMins` 生成，不根据订阅方案猜测；次窗口
  缺失或无效时局部隐藏，不伪造 `0%`；
- Spark 继续作为独立中性额度显示在核心窗口之后，保留自己的用量与重置
  时间，不重复显示订阅方案；
- 设置页增加单一“锁定到 Codex 屏幕”开关：开启时跟随最大可见 Codex
  窗口所在屏幕，关闭时跟随热区；跨屏使用最大交集，不可定位时自动回退；
- 屏幕定位只读取 Codex PID、可见窗口与显示器几何，不读取标题、内容或
  像素，不新增辅助功能或屏幕录制权限；
- 保留稳定单任务灵动岛、粒子球/波澜光晕、收起时间自定义和 Reduce Motion；
  产品 Build 为 1，Sparkle 内部更新序号为 11。

验证与发布资产：

- `swift test`：72 项通过、0 失败；PR #31 GitHub CI 通过并合并到 `main`；
- Universal Release 构建通过；App、Widget 与 Activity Hook 均为
  `x86_64 arm64`；版本为 Marketing `0.3.7`、内部 `11`、产品 Build `1`；
- 文件名：`QuotaView-v0.3.7-build.1.zip`
- 大小：`12,927,829 bytes`
- SHA-256：
  `42e815cbb12f18112e3423c48f6392232ef25c061cfa9ba96d19012ddaa7b5c4`
- Developer ID：`Developer ID Application: Chenchen Xu (BUUH229D5Q)`，
  证书 SHA-1 `E52D0A9C7C377AF77C484155CC0CFCFB27D949D3`，启用
  Hardened Runtime；
- Apple 公证：Accepted，已 Staple；Submission
  `04654ab7-29ea-4bda-a131-3363f58fb840`；
- GitHub 回下载资产与本地公证包逐字节一致；重新解压后通过嵌套
  `codesign --deep --strict`、Staple、Gatekeeper、版本、资源与架构复核，
  本地包和线上回下载包均完成独立启动冒烟；
- GitHub Release Notes 使用
  `docs/releases/QuotaView-0.3.7-build.1.md` 的单份英文源文；
- 公开 Feed：`https://duoasa.github.io/QuotaView/appcast.xml`；`gh-pages`
  提交 `bcff201229d9ce5499f984c0176c6686b4d29d60`；Feed SHA-256
  `3e79e1cee579ab87eb84b766374e36de62d9115d4dc75fed22c56b8e1e4a3488`；
  线上文件与本地签名文件逐字节一致，Feed EdDSA 验证通过；
- 完整深浅色、跨屏、VoiceOver/Increase Contrast/Reduce Motion 矩阵和真实
  0.3.6 → 0.3.7 应用内替换重启流程尚未形成独立记录，不由发布事实自动
  视为通过。

Release：
[QuotaView 0.3.7 Build 1 — Multiple Quota Windows and a Screen-Aware Codex Island](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.7-build.1)

## 0.3.6 (Build 2)

Tag：`v0.3.6-build.2`

状态：历史正式 Release、0.3.7 的封存回滚基线、非 Draft、非 Pre-release；
已由 0.3.7 Build 1 替代。

发布提交：
`ab033001a194b78e2ec80f31e1f334ea1cae0021`

主要特性：

- 在设置页新增独立“显示灵动岛”开关；关闭只隐藏窗口，Codex Hook、Socket
  和本地状态连接继续工作；
- 为稳定单任务灵动岛提供“粒子球”和“波澜光晕”两种生产渲染预览，选择
  后即时切换；
- “波澜光晕”覆盖现有九种任务状态，保持固定圆形轮廓和连续状态过渡，
  Metal 不可用时回退“粒子球”；
- “完成后缩小”支持 5...60 秒，“缩小后隐藏”支持 5...120 秒，均以
  5 秒为档位并显示刻度与当前值；
- 保留 Reduce Motion、单一 NSPanel 和现有本地隐私边界；不包含独立的
  多任务 Preview 实验；
- 产品 Build 为 2，Sparkle 内部更新序号为 7，可被 0.3.5 Build 5 的
  Stable 更新器识别为新版本；
- 产品截图：`Resources/QuotaView-0.3.6-Codex-Island-Settings.png`；中英文
  README 的 0.3.6 更新介绍与 GitHub Release 正文共同引用该图。

验证与发布资产：

- `swift test`：66 项通过、0 失败；PR #27 与签名修复 PR #28 GitHub CI
  均通过；
- 文件名：`QuotaView-v0.3.6-build.2.zip`
- 大小：`12,861,638 bytes`
- SHA-256：
  `b90e05ee724f8adf7856be469476f8b2224304a981c8869e4200aee4ce525bae`
- App、Widget 和 Hook 均为 Universal `x86_64 arm64`；App 为
  Marketing Version `0.3.6`、内部版本 `7`、产品 Build `2`；
- Developer ID：`Developer ID Application: Chenchen Xu (BUUH229D5Q)`，
  证书 SHA-1 `E52D0A9C7C377AF77C484155CC0CFCFB27D949D3`，启用
  Hardened Runtime；
- Apple 公证：Accepted，已 Staple；Submission
  `ff3fef0b-d92f-47cd-8798-3cb388aa2d9e`；
- GitHub 回下载正式资产与本地公证包逐字节一致；从 ZIP 全新解压后重新
  通过 `codesign --deep --strict`、Staple、Gatekeeper、版本、架构与资源
  复核；
- 公开 Feed：`https://duoasa.github.io/QuotaView/appcast.xml`；`gh-pages`
  提交 `421486caac313e04795e429ac36ab14df9d918fd`；Feed SHA-256
  `06a9007a3814192deb6469490dadb2b0ca540b3ea6c836a7a623c0107c94a211`；
  线上文件与本地签名文件逐字节一致，Feed EdDSA 验证通过；
- 真实 0.3.5 → 0.3.6 应用内安装操作和完整视觉/辅助功能交叉矩阵尚未形成
  独立验收记录，因此更新器规格继续保持 `Accepted / Verifying`；不影响
  本版已经正式发布。

Release：
[QuotaView 0.3.6 Build 2 — Customizable Codex Island](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.6-build.2)

## 0.3.5 (Build 5)

Tag：`v0.3.5-build.5`

状态：历史正式 Release、0.3.6 的封存回滚基线、首个包含更新器的稳定
版本、非 Draft、非 Pre-release；已由 0.3.6 Build 2 替代。

发布提交：
`58e676a8317d907107af3d1731ab11a0ded52684`

主要特性：

- 在主周期额度下方增加独立建模、固定中性色的 Spark 周额度；无有效数据时
  自动隐藏，不重复显示订阅方案；
- 将主周期下次重置合并到额度图表，并移除重复的独立面板开关；
- 新增最近一天、30 日 Tokens 与 30 日成本估算，成本明确标注为本地估算值、
  非账单；
- Token 活动最长范围调整为最近半年，同时保留每行 16 格、左上占位补齐和
  真实日期右下对齐；
- 统一摘要、Token 活动和成本图的“最近一天”日期语义；
- 接入 Sparkle 2.9.2 Stable 更新检查、手动检查入口和默认关闭的 24 小时
  自动检查；Debug、Ad Hoc、非 App 或非预期签名环境不访问 Feed；
- 本版的产品 Build 与 Sparkle 内部更新序号均为 5；后续从 `0.3.6` 起两者
  分离：产品 Build 随 Marketing Version 归 1，内部更新序号继续递增；
- 产品截图：`Resources/QuotaView-0.3.5-Overview.png`；中英文 README 的
  0.3.5 更新介绍和 GitHub Release 正文共同引用该图，Release 使用不可变
  提交 `c060168976930c39dca4af616567fa51eb75d3be` 的 raw URL。

验证与发布资产：

- `swift test`：64 项通过、0 失败；PR #22 GitHub CI 通过；
- 文件名：`QuotaView-v0.3.5-build.5.zip`
- 大小：`12,747,358 bytes`
- SHA-256：
  `d8524ddf5739501bd797cdd082cc8738a7775d8b994fe99033068af8f821b2e1`
- App、Widget、Hook、Core、Sparkle framework 及其 Installer、Downloader、
  Autoupdate、Updater 组件均为 Universal `x86_64 arm64`；App 与 Widget 为
  `0.3.5 (5)`；
- Developer ID：`Developer ID Application: Chenchen Xu (BUUH229D5Q)`，
  启用 Hardened Runtime；
- Apple 公证：Accepted，已 Staple；Submission
  `88796026-3227-405a-9e1b-900af973c527`；
- GitHub 回下载正式资产与本地公证包逐字节一致，并重新通过 `codesign`、
  Staple、Gatekeeper、版本、架构和资源复核；
- 公开 Feed：`https://duoasa.github.io/QuotaView/appcast.xml`；`gh-pages`
  提交 `9048dd67c746e145be75dd86870bc888d5eef499`；Feed SHA-256
  `ee46651f1b45fe03cf4e4967543d3b5dd18a644aff956fd5396ea90bd36e2f50`；
  线上文件与本地签名文件逐字节一致，Feed EdDSA 验证通过；
- Sparkle 私钥已使用 AES-256 加密备份到 iCloud Drive，备份 SHA-256
  `f48ba844884312cffc29b5316d2a624b0e38ee4caf4f9e064e3abb82f126f89d`，
  恢复密码仅存于 macOS Keychain；
- Build 5 是首个包含更新器的版本，必须手动安装；真实 N → N+1 更新验收
  留待后续获准的正式 Build 完成；完整视觉与辅助功能交叉矩阵未记录为全量
  通过。

Release：
[QuotaView 0.3.5 Build 5 — Usage Overview and App Updates](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.5-build.5)

## 0.3.3 (Build 3)

Tag：`v0.3.3`

状态：历史正式 Release、`0.3.5` 的封存回滚基线、非 Draft、非 Pre-release。

发布提交：
`a93a81af4f90610a57783ceb16a744f07e216c6a`

主要特性：

- 在状态栏菜单的用量数据列表下方新增每日 Token 活动图表；
- 默认显示最近一个月，并支持最近一周、三个月和全部可用历史；
- 每行固定 16 个圆角方格，以左上虚线占位格补齐完整网格，真实日期从
  右下角对齐；
- 深色外观使用 `16% → 80%` 不透明白阶，浅色外观使用
  `80% → 16%` 不透明灰阶；占位格保留低透明度；
- Hover 0.5 秒后显示日期和紧凑 `K / M / B` Token 用量；
- 切换周期时固定菜单顶部，只由下边缘平滑收缩或扩展；
- 设置中提供 Token 活动图表显示/隐藏开关；
- 保留 0.3.1 稳定单任务 Codex 灵动岛；不包含 0.3.2 Preview 的实验性
  多任务生产实现。

验证与发布资产：

- `swift test`：57 项通过、0 失败；GitHub PR #20 CI 通过；
- 文件名：`QuotaView-v0.3.3-build.3.zip`
- 大小：`11,566,058 bytes`
- SHA-256：
  `ec96964d72d8c37f95cf08170fef83697df83183e36e6be8e23c84e04aa95e12`
- App、Widget Extension、`QuotaViewActivityHook` 与 Core 均为 Universal
  `x86_64 arm64`，App 与 Widget 为 `0.3.3 (3)`；
- Developer ID：`Developer ID Application: Chenchen Xu (BUUH229D5Q)`，
  启用 Hardened Runtime；
- Apple 公证：Accepted，已 Staple；Submission
  `2dd7f885-db01-4ec1-a4d3-fbd8156ab616`；
- GitHub 回下载资产与本地公证包逐字节一致；重新通过 `codesign`、
  `stapler`、`spctl`、隔离属性、版本、架构、资源和真实启动烟雾测试；
- 产品所有者已手动确认图表观感、单色阶梯、0.5 秒 Tooltip 方向，以及
  周期切换时面板顶部固定、上下收展无跳动。

Release：
[QuotaView 0.3.3 — Token Activity](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.3)

## 0.3.2 (Build 1) Preview 1

Tag：`v0.3.2-preview.1`

状态：当前公开预览版、非 Draft、非 Latest；`0.3.6 (Build 2)` 是
推荐稳定版与 GitHub Latest。

发布提交：
`f835bcd46a3d0197e9dc09e0b5a25a6d5d69521c`

主要特性：

- 在一个固定 Codex 灵动岛内同时跟踪多个会话，并分别维护状态、生命周期、
  完成与清理；
- 新增三行任务列、连续滑动窗口、任务总数和紧凑态多任务摘要；
- 使用稳定优先级仲裁主任务，减少普通后台事件对当前任务的无必要抢占；
- 新增可选的当前 Codex 任务跟随，通过有界、只读的辅助功能标题匹配实现，
  无法高置信度匹配时安全自动降级；
- 保留实时 Metal 状态表面、原生玻璃切换、最大态/紧凑态、Reduce Motion
  和辅助功能操作。

预览版已知不足：

- 事件到灵动岛的响应速度仍可能受 Hook 传递、本机调度和当前任务状态影响；
- 当前任务跟随基于标题，标题未解析、重复、快速变化或 Codex UI 调整时
  可能滞后或未命中；
- 任务切换、长标题跑马灯及最大态/紧凑态切换节奏仍需继续优化。

发布资产：

- 文件名：`QuotaView-v0.3.2-preview.1.zip`
- 大小：`11,543,516 bytes`
- SHA-256：
  `e39b0d004c2ce2d7d739f5b1f1dc9037335c63d2ee6d663d8129327433f13587`
- App、Widget Extension 与 `QuotaViewActivityHook` 均为 Universal
  `x86_64 arm64`，App 与 Widget 为 `0.3.2 (1)`、渠道 `preview`
- Developer ID 签名：`Developer ID Application: Chenchen Xu
  (BUUH229D5Q)`，启用 Hardened Runtime
- Apple 公证：Accepted，已 Staple；Submission
  `47c6d413-465f-4632-b7d2-1e48ed03f9a0`
- GitHub 回下载资产与本地正式包逐字节一致，并再次通过 `codesign`、
  `stapler` 与 `spctl` 验证

Release：
[QuotaView 0.3.2 Preview 1 — Multi-task Codex Island](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.2-preview.1)

## 0.3.1 (Build 2)

Tag：`v0.3.1-build.2`

状态：历史正式 Release、`0.3.3` 的封存回滚基线、非 Draft、非 Pre-release。

发布提交：
`3119171f45163fe45d68a4f774a0488968f14fd7`

主要变更：

- 将 App 与 Widget Extension 的共享容器迁移为团队前缀 App Group
  `BUUH229D5Q.com.quotaview.shared`，恢复 Developer ID 公证下载版的小号
  与中号 Widget 数据；
- 将主面板、Widget、Tooltip 与辅助功能文案中的“本周剩余”统一调整为
  “本周期剩余” / `Period Remaining`，兼容 5 小时、7 天和后续可变周期；
- 新增发布打包门禁：未嵌入 provisioning profile 时，拒绝使用非团队
  前缀 App Group 的直接分发包。

发布资产：

- 文件名：`QuotaView-v0.3.1-build.2.zip`
- 大小：`11,443,325 bytes`
- SHA-256：
  `9051b60799a5a20e578c2eea4e3f3a5b3725109b553fc8580473953c0f59a1ed`
- App、Widget Extension 与 `QuotaViewActivityHook` 均为 Universal
  `x86_64 arm64`
- App、Widget 与 Helper 均为 `0.3.1 (2)`
- Developer ID 签名：`Developer ID Application: Chenchen Xu
  (BUUH229D5Q)`，启用 Hardened Runtime
- Apple 公证：Accepted，已 Staple；Submission
  `0ff9bf81-3570-4243-b3be-5d076b0f888c`
- GitHub 回下载资产与本地正式包逐字节一致；隔离属性下通过
  `codesign`、`stapler`、`spctl` 与真实启动烟雾测试

Release：
[QuotaView 0.3.1 Build 2 — Widget Hotfix](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1-build.2)

## 0.3.1 (Build 1)

Tag：`v0.3.1`

状态：历史正式 Release，已由 `0.3.1 (Build 2)` 取代。

发布提交：
`041c698ae9755d458fa9f111e4ac74e9711048b9`

主要特性：

- 新增 Codex 灵动岛，以位于菜单栏下方的原生非激活浮层实时展示 Codex
  任务状态；
- 使用 Metal 流体球、状态配色和动效表达思考、工作、工具调用、权限确认、
  上下文压缩、子任务、完成与失败；
- 实现最大态、紧凑态和隐藏状态：任务完成 20 秒后紧凑，完成满 120 秒后
  隐藏，新活动立即重新展开；
- 使用 Codex 官方 Hooks 获取生命周期事件，并通过独立签名的
  `QuotaViewActivityHook` 在本机转发最小、脱敏的事件元数据；
- 新增新手向一键连接流程，自动检测 Hooks 支持、维护固定路径 Helper、
  保留现有 Hooks，并打开官方 `/hooks` 信任审查页；
- 只有 Codex 完成信任、重启并产生第一条真实 `UserPromptSubmit` 后，
  QuotaView 才会报告连接成功；
- README 中英文版本重点介绍 Codex 灵动岛，并加入任务完成状态预览图；
- 保留额度菜单、WidgetKit 小组件和只读账户边界；额度重置继续为本地
  Demo。

隐私与安全：

- Helper 只转发哈希会话标识、工作区路径最后一级、事件类型、粗粒度工具
  类别、SessionStart 来源和时间；
- 不转发提示词、命令、参数、工具输出、模型内容或会话记录路径；
- 本地桥接使用随机令牌、文件所有者与时效校验；不会绕过 Codex 官方
  Hook 信任确认；
- Prototype、CodexBar 参考文档和其他用户参考图片未进入发布提交。

发布资产：

- 文件名：`QuotaView-v0.3.1.zip`
- 大小：`11,443,295 bytes`
- SHA-256：
  `ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d`
- App、`QuotaViewCore.framework`、Widget Extension 与
  `QuotaViewActivityHook` 均为 Universal `x86_64 arm64`
- App、Widget 与 Helper 均为 `0.3.1 (1)`

签名与公证：

- App、Widget、Framework 与 Helper 使用
  `Developer ID Application: Chenchen Xu (BUUH229D5Q)`；
- Team ID 为 `BUUH229D5Q`，启用 Hardened Runtime 和可信时间戳；
- Apple notarization 状态为 `Accepted`，Submission ID：
  `2b125886-a3dc-4734-a139-280a08302e5c`；
- 公证票据已 Staple，`spctl` 返回
  `accepted / source=Notarized Developer ID`。

验证记录：

- 本地与 GitHub Actions 的 52 项测试均通过；
- 最终 ZIP 全新解压后通过 `codesign --verify --deep --strict`、
  `stapler validate` 与 `spctl --assess`；
- 加入下载隔离属性后 Gatekeeper 仍正常接受；
- GitHub 回下载资产与本地最终 ZIP 逐字节一致；
- GitHub 回下载 App 的真实启动烟雾测试持续 5 秒，没有 Framework、
  Helper、签名或 `fatalDyldError`；
- 最终视觉、语言与辅助功能矩阵仍等待产品所有者逐项验收，不提前记录为
  “已通过”。

## 0.2.1 (Build 1)

Tag：`v0.2.1`

状态：历史正式 Release，已由 0.3.1 取代为推荐下载版本。

发布提交：
`56aa71dd9f4013412f90c75e0c282a610e87d14e`

主要特性：

- 新增原生 WidgetKit 扩展，支持 macOS 小号与中号小组件；
- 小组件展示本周额度、重置时间、Credits、今日与累计 Token、订阅方案和
  连接状态；
- 主 App 通过正式 App Group 写入最小、脱敏且会过期的快照，Widget
  不访问网络、认证凭据或 Codex App Server；
- 更新菜单面板、进度条、连接状态与局部 Liquid Glass 细节；
- 订阅类型统一映射到 OpenAI 官方方案名称，未知值和不可用状态使用
  破折号，不伪造数据；
- README 中英文版本使用新的产品预览图，并同步 0.2.1 下载入口与更新
  说明；
- 继续保持只读边界；额度重置仍为本地 Demo，不调用真实消费接口。

发布资产：

- 文件名：`QuotaView-v0.2.1.zip`
- 大小：`10,907,231 bytes`
- SHA-256：
  `99e7fb951d4abd6475204c059f1e16481dac8be4c3b72e6b19889fc54737521b`
- App、`QuotaViewCore.framework` 与 Widget Extension 均为 Universal
  `x86_64 arm64`
- App 与 Widget 均为 `0.2.1 (1)`

签名与公证：

- App 与 Widget 均使用
  `Developer ID Application: Chenchen Xu (BUUH229D5Q)`；
- Team ID 为 `BUUH229D5Q`，启用 Hardened Runtime 和可信时间戳；
- Apple notarization 状态为 `Accepted`，Submission ID：
  `e211abde-be96-47eb-a5ca-50ec1df7f260`；
- 公证票据已 Staple，`spctl` 返回
  `accepted / source=Notarized Developer ID`。

验证记录：

- 本地与 GitHub Actions 的 33 项测试均通过；
- 无签名 Universal Xcode Release 构建通过；
- 最终 ZIP 全新解压后通过 `codesign --verify --deep --strict`、
  `stapler validate` 与 `spctl --assess`；
- 为解压 App 加入下载隔离属性后，Gatekeeper 仍正常接受；
- 本地最终包与 GitHub 回下载资产逐字节一致；
- GitHub 回下载 App 的真实启动烟雾测试持续 5 秒，没有
  `fatalDyldError`、Framework 加载或签名错误；
- 最终视觉与交互矩阵仍等待产品所有者验收，不在本记录中提前标记通过。

## 0.2.0 (Build 4)

Tag：`v0.2.0-build.4`

状态：历史正式 Release，已由 0.2.1 取代为推荐下载版本。

主要特性：

- 包含 Build 3 完成的 UI1/UI2 组件精修：
  - 功能按钮；
  - 额度重置入口卡片；
  - 重置按钮；
  - 订阅类型 Tag；
  - Codex 数据连接状态标签；
  - 浅色功能图标和菜单栏图标。
- 连接状态标签固定为 `18 pt` 高、`6 pt` 连续圆角，不再退化为
  橄榄球形。
- 重置额度只读取真实
  `CurrentCodexPresentation.availableResetCredits`，不包含调试虚拟数据。
- 额度重置操作仍为本地 Demo，不调用真实
  `account/rateLimitResetCredit/consume`。
- 修复 GitHub 下载版在菜单栏项目建立前退出的问题：
  - Build 3 将无 Team ID 的 ad-hoc 签名与 Hardened Runtime 组合；
  - macOS Library Validation 因此拒绝加载
    `QuotaViewCore.framework`；
  - Build 4 的 ad-hoc 回退不再启用 Hardened Runtime；
  - Developer ID Application 与 Apple Development 身份仍保留
    Hardened Runtime。
- 打包脚本新增签名模式断言，避免再次生成“验签通过但运行时无法加载
  Framework”的发布包。
- GitHub Release Notes 只保留一份英文源文，由 GitHub 的界面翻译功能
  负责本地化，避免中英文正文重复显示。

验证记录：

- 本地与 GitHub Actions 的 28 项测试均通过；
- App 与 `QuotaViewCore.framework` 均为 Universal
  `x86_64 arm64`；
- ZIP 全新解包后通过 `codesign --verify --deep --strict`；
- 从 GitHub 回下载的 ZIP 与本地发布包逐字节一致；
- GitHub 回下载 App 的真实启动烟雾测试持续 3 秒，没有新增
  `fatalDyldError`。

## 0.2.0 (Build 3)

原 tag：`v0.2.0-build.3`

状态：已撤回；GitHub Release、远端 tag 和本地 tag 均已删除，不得作为
下载、开发或发布基线。

完成的功能：

- 按 Figma Page UI 的 UI1/UI2 精修按钮、重置入口、重置按钮、订阅 Tag
  和连接状态标签；
- 更新浅色功能图标和菜单栏图标；
- 修复连接状态标签的橄榄球形轮廓；
- 移除 3 次调试重置额度，恢复真实 Codex 数据链路。

撤回原因：

- 发布脚本使用 `--sign - --options runtime`；
- App 与内嵌 Framework 均没有 Team ID；
- `codesign --verify --deep --strict` 可以通过，但下载后运行时
  `dyld` 仍会因 Library Validation 拒绝 Framework；
- 进程在 `applicationDidFinishLaunching` 前退出，因此状态栏没有任何
  显示。

这些功能和修复均已由 Build 4 继承，不应恢复 Build 3。

## 0.2.0

Tag：`v0.2.0`

状态：历史正式 Release，已由 Build 4 取代为推荐下载版本。

核心特性：

- 引入标准化 Domain Model 与静态 Provider Registry，为未来官方数据源
  预留边界，但不加入动态插件运行时；
- 引入 generation、revision 和账户感知的刷新协调器，拒绝旧请求覆盖
  新状态；
- Codex App Server 增加有界输出、独立启动/请求超时、取消处理与可选
  usage 失败隔离；
- 同时关闭两个 Token 区域时不再请求 Token 用量；
- 增加历史、图表、通知和未来 WidgetKit 的轻量契约，不启用新的后台任务；
- 保留双语界面、菜单面板、设置窗口和本地额度重置 Demo；
- 默认只读，不包含真实额度重置或账户写操作。

历史资产：

- `QuotaView-v0.2.0.zip`
- SHA-256：
  `f14936120a1b884a95ca4e5150b70ababd5e40c1566ac78c0f26e716cb746bb0`

## 0.1.5 (Build 6)

Tag：`v0.1.5`

状态：历史正式 Release。

核心特性：

- 使用原生 `NSStatusItem` 和自定义动态高度面板重构菜单栏体验；
- 新增实时订阅名称、周剩余百分比、可用状态和可配置指标；
- 新增清透/磨砂玻璃与深浅外观适配；
- macOS 26 使用原生 Liquid Glass，macOS 14–15 使用 Material 回退；
- 重构设置窗口，包含菜单栏、面板内容、外观、语言和通用页面；
- 新增额度概览、重置时间、Credits、每日/累计 Token、重置入口的独立
  显示开关；
- 重构额度重置详情页和面板内确认流程，同时保持 Demo 安全边界；
- 完成简体中文与 English 界面；
- 打包 Asta Sans 与新的界面资源；
- Build 6 修复 Available/Unavailable 状态标签：
  - 固定 `18 pt` 高；
  - `6 pt` 连续圆角；
  - 移除状态色模糊外溢。

历史资产：

- `QuotaView-v0.1.5.zip`
- SHA-256：
  `979e68c07a9183b45350d7270b7e86c227a792f273a84035454d4443cd97ad74`

## 0.1.3

Tag：`v0.1.3`

状态：历史正式 Release。

核心特性：

- 新增原生设置窗口及菜单栏/Popover 显示选项；
- 新增跟随系统、浅色和深色外观；
- 新增跟随系统、简体中文和 English 语言选项；
- 新增磨砂/清透玻璃，以及 macOS 14–15 Material 回退；
- 新增正式 App Icon 和 Template 菜单栏图标；
- 改进额度重置详情与确认流程，继续保持 Demo 模式；
- 改进 Universal 发布打包与签名检查。

历史资产：

- `QuotaView-v0.1.3.zip`
- SHA-256：
  `3e704f939eeea7980b1c2f94978b89495e1c0501c999fef744828e5a40e5c10b`

## 0.1.0

Tag：`v0.1.0`

状态：首个公开 Release。

核心特性：

- 读取本机已登录 Codex 账户的当前额度和剩余百分比；
- 显示下次额度重置倒计时；
- 分离套餐额度与 Credits 余额；
- 显示可用重置次数，并提供安全 Demo 交互；
- 显示近期每日与累计 Token 用量；
- 自动刷新，并提供离线和错误状态；
- 支持 Apple Silicon 与 Intel 的 Universal macOS App。

历史资产：

- `QuotaView-v0.1.0.zip`
- SHA-256：
  `5a4412794f78fc8a340b9fbb7c9eca7908cc5395dcd21fcb6fce8f39998b88fe`
