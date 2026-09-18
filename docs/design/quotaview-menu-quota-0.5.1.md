# 0.5.1 菜单栏额度快捷显示

Spec ID：`QV-PRODUCT-MENU-QUOTA-022` · `Accepted / Released`

2026-09-17 用户授权：以 0.5.0 Build 3 开始 0.5.1，按所提供图片的红框
采用双行用量快捷显示，进度条为单色。初始开发身份为 Build 1 / internal 30；当前 Build 9 / internal 38。

## 行为与边界

- MENU-022-01：沿用剩余额度语义，图标右侧两行按 primary、secondary 的
  稳定身份排列；每行依次为真实周期（通常 5h / 7d）、进度条、剩余百分比。
  Plus 双窗口采用以上布局；单窗口采用周期、竖向单色条、剩余百分比和可选重置倒计时横排。
  布局以真实快照是否同时具有 primary / secondary 两窗口为依据，不从订阅名
  伪造窗口。未知或仅一个窗口时沿用单行显示；恢复两个窗口时自动切回双行。
  不把 Spark 专属额度混入，不依赖数组顺序，不硬编码周期值。
- MENU-022-02：模板图片由系统自动着色，填充为实色、轨道为同色低透明度；
  无彩色风险分级、渐变或进度动画。22 pt 画布适配菜单栏，百分比数字等宽，
  0–100% 变化不改变布局宽度。进度填充与数字使用同一剩余值。
- MENU-022-03：缺失周期/额度用 — / —%，不伪造为零。已知 0% 无填充，100%
  填满；单个周期缺失不借用另一个周期的数据。刷新与失败沿用现有快照策略，
  失败原因继续由 Tooltip / VoiceOver 表达，未另开轮询或数据源。
- MENU-022-04：保留图标、额度、倒计时开关及至少一项可见约束。关闭额度后
  保留图标/倒计时组合，双窗口的倒计时按周期分别标注。设置预览和菜单栏使用同一图片生成器，中英文设置说明、
  Tooltip 和 VoiceOver 同步，明确百分比为剩余量。

## 验证

生产基线：逐文件对比 `v0.5.0-build.3`，71 个源码与配置文件完全一致。
针对周期身份、未知值/零值、模板图片与稳定宽度执行局部冒烟测试；Universal
Release 无签名构建检查 App / Widget 版本与架构。

结果：局部冒烟测试通过（包含双窗口、周单窗口、缺失窗口、已知零值、
固定宽度与模板图片渲染），Universal Release 构建通过；App / Widget 均为
0.5.1 / internal 30 / Build 1、x86_64 + arm64，AppIcon / Assets 资源存在。
`git diff --check` 通过。未运行完整回归，未启动开发 App。
证据：`dist/verification/0.5.1-build1/`，构建包路径见其中 `result.json`。
实际菜单栏深浅色、可读性、开关组合及 VoiceOver 体验等待用户验收。
不改变灵动岛已接受动效，不替换正式安装，不发布或纳入 appcast。

## 2026-09-17 Plus 虚拟数据体验

用户授权启动预览并注入 Plus 数据。临时源码位于 `/tmp/quotaview-051-plus-preview`，
使用 DEBUG 编译条件、独立 Bundle ID 与偏好域；未嵌入 Widget，未启动真实额度
轮询、更新或任务服务。运行包为 `/tmp/quotaview-051-plus-run/QuotaView Plus DEBUG.app`。
显示 5h 剩余 90%、7d 剩余 78%，菜单栏 / Tooltip / 辅助文本带 DEBUG 标识。
生产源码保持无虚拟注入；本次 Debug 构建及启动成功，视觉仍等待用户验收。

## Build 2：逐窗口重置时间

用户已授权实现此前确认的方案：默认不常驻重置时间；Tooltip / VoiceOver
始终提供各周期剩余额度和距重置时间。开启倒计时后，两个时间分别位于
对应行百分比之后；关闭额度时仍以周期标签区分两个倒计时。Pro 单窗口
继续单行。展开面板原本已使用每个窗口自己的 resetsAt，保持该实现。

菜单栏和设置预览每 30 秒本地更新时间，不发网络请求。缺失日期显示 —，
日期到达后显示待刷新 / Due，直到真实快照更新；不伪造额度重置。

验证：3 项局部冒烟检查通过，覆盖窗口对应关系、双行/单行、缺失/到期、
中英文、模板渲染和仅倒计时布局；Universal Release 构建通过。
证据位于 `dist/verification/0.5.1-build2/`。视觉验收待用户确认。

Build 2 Plus DEBUG 预览已启动：`/tmp/quotaview-051-build2-plus-run/QuotaView Plus DEBUG.app`。
虚拟 5h 剩余 90%、7d 剩余 78%，倒计时已打开，27 秒进程存活检查通过。
旧 Build 1 预览已退出；正式安装保留，生产源码无虚拟注入。

## 2026-09-17 真实数据接入

用户确认 Plus DEBUG 显示目前无问题，授权取消虚拟注入并接入真实数据。
已关闭 DEBUG 与正式版主进程，启动独立 Build 2 Release 真实数据包，
不含 Widget；正式安装保留。生产及临时预览源码无虚拟注入，真实额度
刷新成功且共享快照 available，Codex 配置指纹不变。运行记录见
`dist/verification/0.5.1-build2/real-data-launch.json`。
视觉确认仅限已查看的 Plus DEBUG 场景，真实数据及其他外观仍按实际反馈记录。

## Build 3：单窗口竖向进度条

用户授权单窗口也采用周期 + 进度条 + 百分比 + 重置时间，条为竖向。
单窗口模板画布高 22 pt，竖条 5 × 16 pt，从底部向上填充剩余额度；
周期使用真实时长，百分比按 100% 留宽，倒计时继续受现有开关控制。
关闭额度时保留周期与倒计时，图标开关独立。双窗口布局保持不变。
未知数据采用占位，不借用其他周期值；设置预览共用生产模板。
此变更取代前述单窗口仅百分比的历史行为。

2026-09-17 Build 3 验证：4 项局部冒烟通过，App / Widget Universal Release
构建及 0.5.1 / Build 3 / internal 32 身份核对通过。已启动真实数据副本
`/tmp/quotaview-051-build3-real/QuotaView.app`，旧 Build 2 主进程已退出。
本次启动后额度刷新成功；无虚拟注入，正式安装保留。视觉等待用户验收。
证据：`dist/verification/0.5.1-build3/result.json`。

## Build 4：参考相邻 CodexBar 收紧排版

依据用户提供的实际菜单栏截图调整单窗口：13 pt semibold，图标后的
视觉间距 5 pt，周期/竖条/百分比/倒计时之间 4 pt。百分比用实际宽度，
不再为 100% 预留空白；允许数字位数变化时状态项自然伸缩。双窗口不变。
此处替代 Build 3 单窗口固定百分比列与 12 pt 字号，竖条仍为 5 × 16 pt。

Build 4：4 项局部冒烟、Universal Release、App / Widget 版本核对通过。
已启动 `/tmp/quotaview-051-build4-real/QuotaView.app`，旧 Build 3 已退出，
真实数据刷新成功。用户所附 Build 3 截图反馈已用于本次调整，Build 4 视觉待验收。
证据：`dist/verification/0.5.1-build4/result.json`。

2026-09-17 用户再次要求 Plus 虚拟数据：已启动独立 Build 4 DEBUG 预览，
路径 `/tmp/quotaview-051-build4-plus-run/QuotaView Plus DEBUG.app`。
5h 剩余 90%、7d 剩余 78%，倒计时开启；无真实额度轮询或 Widget 写入，
正式生产源码无注入。真实数据开发版继续保留运行，可通过 DEBUG 标识区分。

## Build 5：单窗口上文下条

按用户最新要求替代 Build 3/4 的单窗口竖条横排：上方周期与百分比用
双窗口同款 9 pt semibold，周期左对齐、百分比右对齐，中间 8 pt；
下方横条高 4 pt，宽度等于上方两项文字加间距的总宽度。轨道从左到右
填充剩余额度。倒计时开启时仍在右侧，图标和其他开关行为保留。
双窗口保持既有显示。此节取代此前单窗口排版尺寸要求。

Build 5 验证：4 项冒烟、Universal Release、App / Widget 版本身份检查通过。
已启动 `/tmp/quotaview-051-build5-real/QuotaView.app`，旧真实数据 Build 4 已退出，
启动后的真实额度刷新成功。Plus DEBUG 对比副本保留，生产源码无虚拟注入。
视觉待用户验收；证据 `dist/verification/0.5.1-build5/result.json`。

## Build 6：恢复单周期纯文字

用户否定 Build 5 视觉效果，要求恢复最初无进度条版本。单周期采用
原生 NSStatusBarButton 文字：剩余百分比 + 可选重置倒计时，无周期标签、
无进度条，13 pt semibold 紧凑排版；设置预览同字号。单周期的周期信息
继续保留在 Tooltip / VoiceOver 中，双周期不变。删除不再使用的单窗口
图片生成器。本节替代 Build 3–5 的单周期视觉规则。

Build 6：4 项局部冒烟、Universal Release、App / Widget 版本身份检查通过。
已启动 `/tmp/quotaview-051-build6-real/QuotaView.app`，旧 Build 5 已退出，
本次真实数据刷新成功。Plus DEBUG 对比副本保留；Build 6 视觉待用户确认。
证据：`dist/verification/0.5.1-build6/result.json`。

## Build 7：单周期常规字重

用户要求字体不用半粗，改用 Regular。单周期原生状态栏与设置预览均为
13 pt regular；其他排版与双周期保持不变。

Build 7 Universal 构建、App / Widget 版本检查与启动冒烟通过。已启动
`/tmp/quotaview-051-build7-real/QuotaView.app`，旧 Build 6 已退出，
真实数据刷新成功；字重修改未重跑逻辑测试，视觉待确认。
证据：`dist/verification/0.5.1-build7/result.json`。

## Build 8：14 pt 常规体

用户将单周期文字字号调整为 14 pt，继续使用 Regular 字重。状态栏与设置
预览同步，双周期布局和真实数据逻辑保持不变。全新 Universal Release
构建与真实数据启动通过，运行包为 `/tmp/quotaview-051-build8-real/QuotaView.app`。
证据：`dist/verification/0.5.1-build8/result.json`。

## Build 9：单周期文字垂直对齐

用户提供对比截图，反馈文字偏上。原生 attributedTitle 基线下移 1.5 pt，
保留 14 pt Regular、系统着色与原图标位置。双周期无原生文字标题，布局不变。
此项是根据截图的光学校正，实际菜单栏居中观感仍等待用户确认。
Universal 构建与实际启动冒烟通过，证据见 `dist/verification/0.5.1-build9/launch.md`。
0.5.1 Build 9 已完成 244 项 Swift 测试（2 项按规则跳过）、Developer ID 签名、
Apple 公证 / Staple、Gatekeeper、GitHub Release、公开回下载和 Stable appcast 签名验证。
