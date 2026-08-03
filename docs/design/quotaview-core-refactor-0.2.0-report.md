# QuotaView 0.2.0 底层重构实施报告

> 文档编号：`QV-EVIDENCE-CORE-0.2.0-001`
>
> 文档类型：SDD 历史实施与验证证据
>
> 规格状态：`Archived`
>
> 交付状态：`Released`
>
> 状态：0.2.0 代码与无签名 Universal Release 验证完成；本文不再驱动
> 当前实现
>
> 日期：2026-07-28
> 执行依据：
> [`quotaview-core-architecture-evolution.md`](./quotaview-core-architecture-evolution.md)

## 1. 本版范围

0.2.0 完成执行指导中的 Phase 1、Phase 2，并补齐 Phase 0 的自动化行为
基线。另行完成不依赖 Apple Developer 审批的 Widget Contract 纯逻辑
预留，但没有创建 Widget Extension。

本版保持：

- 当前菜单栏、主面板、重置 Demo、设置窗口和本地化入口；
- 现有设置 key 和显示逻辑；
- 首次安装默认跟随系统外观、使用清透玻璃并跟随系统语言；
- 已保存的有效外观、玻璃与语言选择保持不变；
- 每 60 秒刷新与手动刷新；
- 只从官方本地 Codex App Server 读取；
- 主面板和设置窗口现有视觉实现。

本版不包含：

- SQLite History、数据详情页和新图表 UI；
- 第二 Provider、模型或 Agent 的真实 Adapter；
- 系统通知权限与通知调度；
- App Group、Widget Extension、entitlement 或签名配置；
- 真实手动/自动账户操作；
- 任何额度 consume 调用。

## 2. 已落地架构

### 2.1 Domain 与 Provider

- 引入 Provider、Entity、Metric 命名空间 ID；
- 分离数据可用性、额度风险和服务健康状态；
- 引入 Snapshot、当前 Sample 和官方历史 Observation；
- 引入 MetricDefinition、单位、语义和允许聚合；
- 使用 `CodexProviderAdapter` 将 App Server 数据映射到通用 Domain；
- 增加静态 Provider Registry，拒绝重复 Provider ID；
- 模型和 Agent 使用通用 `UsageEntity` 预留，不读取凭据。

### 2.2 刷新与进程

- `RefreshCoordinator` 管理 generation、配置 revision、启用 revision 和
  账户范围；
- replace、coalesce、禁用、stop 和旧结果拒绝已实现；
- 多个 coalesce 调用者共享同一结果，不重复采集；
- App 退出先停止轮询、Provider 与 App Server；
- App Server 使用启动/普通请求两套 timeout；
- stdout 单行硬上限为 1 MB，stderr 诊断有界；
- 缺失主额度窗口不再解释为 0；
- 可选 usage 失败或超时不污染主额度结果。

### 2.3 Presentation 与设置

- 当前 UI 只消费 `CurrentCodexPresentation`；
- Store 由 Provider 状态投影到当前 UI DTO；
- 可选 Credits、Tokens 和重置次数缺失时保留不可用语义；
- “近日 Token”和“累计 Token”都关闭时，不请求
  `account/usage/read`；
- 重新开启任一 Token 区域会更新 Demand 并刷新；
- 原生外观和语言开关首次启动均默认跟随系统；
- 玻璃质感首次启动默认清透，旧的未知材质值也迁移为清透；
- 其他现有显示、菜单栏、外观、材质和语言设置继续使用原 key。

### 2.4 写操作边界

- 产品定位实现为“默认只读”；
- 当前操作能力固定为 `demoOnly`；
- Demo Executor 只生成 `isSimulation = true` 的本地结果；
- 手动授权和自动规则授权使用不同值类型；
- 非 Demo 授权由当前执行器拒绝；
- Provider 刷新不持有操作 Executor，不能产生账户副作用。

### 2.5 后续能力预留

- History Store、Chart Descriptor、Display Preferences 使用稳定 ID；
- Notification Event、状态和 Scheduler 只有协议与 Disabled 实现；
- History/Chart/Notification 预留位于独立模块，不随当前 App 链接；
- Widget Contract 是独立 Foundation-only Swift target；
- Widget 快照具备 schema、过期、字段、16 KB 目标和 64 KB 硬上限；
- `QUOTAVIEW_APP_GROUP_ID` 与 `QUOTAVIEW_WIDGET_BUNDLE_ID` 已预留；
- `DEVELOPMENT_TEAM` 继续留空，不猜测审批中的 Apple Team ID。

所有未实现模块当前都没有后台任务、磁盘写入、系统权限申请或网络行为。

## 3. 自动化验证

`swift test`：

- 28 项测试通过，0 失败；
- 覆盖 Domain 映射、缺失值、超界数据和历史桶；
- 覆盖 replace、coalesce、禁用、稳定账户切换和静态 Registry；
- 覆盖慢响应、可选 usage 失败/超时和超长输出；
- 覆盖设置默认值、旧材质 key、Token Demand 和 Demo 边界；
- 覆盖 Widget schema、过期、大小和敏感字段扫描。

Universal Release：

- Xcode Release 无签名构建成功；
- App：`x86_64 arm64`；
- `QuotaViewCore.framework`：`x86_64 arm64`；
- `CFBundleShortVersionString`：`0.2.0`；
- `CFBundleVersion`：`1`；
- `AppIcon.icns`、`Assets.car` 和三款 Asta Sans 字体存在；
- 无 `.appex`，符合当前 Apple 审批阶段；
- `plutil`、构建脚本语法和 `git diff --check` 通过；
- 生产源码未发现真实额度 consume、截图、自动展开、自动点击或 UI QA
  入口。

## 4. 体积对比

比较对象均为同一机器、同一 Xcode、无签名、Universal Release：

| 指标 | 0.1.5 Build 6 基线 | 0.2.0 Build 1 | 变化 |
|---|---:|---:|---:|
| `.app` 未压缩大小 | 16,076 KiB | 17,388 KiB | +8.16% |
| ZIP | 7,629,478 B | 7,990,649 B | +4.73% |
| App 主可执行文件 | 3,747,544 B | 3,907,464 B | +4.27% |
| Core Framework 可执行文件 | 759,264 B | 1,945,216 B | +156.20% |

说明：

- App 与 ZIP 均未超过 15% 回归门禁；
- 资源目录大小未变化；
- Core 增量来自 Domain、Provider、协调器和安全契约；
- 没有新增第三方依赖、WebKit、数据库或 Extension；
- Widget Contract 未链接进当前 `.app`。

## 5. 尚待产品所有者验收

当前已有 QuotaView 实例在运行，为避免打断使用，没有另起 0.2.0 实例做
15 分钟资源采样。因此以下结果不作虚假声明：

- 首次面板打开耗时；
- 空闲 15 分钟 CPU、唤醒次数和常驻内存；
- 真实安装环境的一次成功/失败刷新资源回收；
- 浅色、深色、磨砂、清透、中英文和辅助功能视觉/交互。

视觉与交互状态：**等待用户验收**。

签名、公证、ZIP 发布和真实 Widget 共享容器验证也不属于本次无签名代码
验收结果。
