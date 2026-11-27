# macOS 状态观察与编译边界

## Build 40 活动与观察

标题缓存按来源优先级更新，异步结果须匹配发起查询的执行身份和请求票据。子 Agent 身份和父子关系复用现有会话注册表，只有已验证的当前轮次能重放活动。多任务调度器按单调时钟安排下一次状态转换，更换截止时间、关闭功能和停止 Store 时取消旧任务。

在同一台 Mac 的 macOS 27.0.1 上，以 Build 39 的 `47de844` 和 Build 40 候选运行同一个离屏夹具。宿主使用实际 `IslandNotchSurface`，只在隔离源码副本的 SwiftUI `body` 入口计数。每场景注入 12 个事件，重复 3 轮，表中为中位数。CPU 为执行该场景的测试进程累计毫秒。

| 场景 | 折叠岛 | 展开岛 | 浮层内容 | 用量页 | CPU ms | 中断唤醒 |
|---|---:|---:|---:|---:|---:|---:|
| 空闲同值 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 10.9 → 11.8 | 12 → 12 |
| 任务标题更新 | 12 → 12 | 12 → 12 | 0 → 0 | 0 → 0 | 48.9 → 49.7 | 12 → 12 |
| 浮层跨分钟 | 12 → 0 | 12 → 0 | 12 → 12 | 0 → 0 | 45.7 → 16.1 | 12 → 12 |
| 用量页打开且跨分钟 | 12 → 0 | 12 → 0 | 12 → 12 | 0 → 0 | 62.2 → 26.0 | 12 → 13 |
| 用量数据更新 | 12 → 12 | 12 → 12 | 12 → 12 | 12 → 12 | 158.4 → 155.0 | 12 → 12 |
| 关闭浮层后跨分钟 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 11.2 → 11.4 | 12 → 12 |

各场景的 package wakeups 中位数均为零。样本支持将跨分钟刷新限制在额度浮层，无法从这组短时离屏读数推算整机续航。

| 对象 | 观察策略与依据 |
|---|---|
| IslandBoardState | 浮层时钟使用稳定的 `@Observable` 实例，由读取时间的浮层订阅。父 Board 的导航、布局和显示快照继续使用 Combine |
| IslandUsageChartCache | 保留 `@StateObject` 生命周期。缓存没有 `@Published`，按提供方、活动、累计量和 UTC 日复用图表 |
| CodexActivityRuntime | 保留 Combine 的监听启停、偏好订阅和渲染合并。分钟级变化现已在 Board 内隔离 |
| CodexStatusStore | 保留按代理、额度可见性和语言分组的 Combine 订阅，设置变化仍能触发对应的服务更新 |
| AppPreferences | 保留已有逐键发布和 `objectWillChange`。Agent 启停、代理、额度和重置服务分别依赖这些订阅 |

核对了 App 的 30 处主队列调度。打开原对话的结果通过 `@MainActor` 更新状态。其余 29 处保留原时序，涉及窗口挂载及复用、滚动布局回写、悬停与停留、重置动画、可取消超时、Combine 交付，以及 Claude 桥接消息与断连的先后顺序。逐处清单位于本机验证目录 `.build/macos-architecture/7/main-queue-remaining.txt`。重复测量入口在同目录的 `tools/measure.py` 和 `tools/compare.py`。

## Build 41 编译边界与快照

使用 Apple Swift 6.4 在 arm64、macOS 14 部署目标上编译。下表依据独立 Debug 构建的 Swift driver 参数与源码清单；数目指项目源码。

| 单元 | SwiftPM Debug | Xcode 原生 Debug |
|---|---|---|
| QuotaViewCore | Swift 6，26 文件 | 独立 framework，Swift 6，26 文件 |
| QuotaViewWidgetContract | Swift 6，1 文件 | App、Widget 各自直接按 Swift 5 编译同一份 WidgetSnapshot.swift |
| QuotaViewActivityHookSupport | Swift 6，4 文件 | App 直接按 Swift 5 编译其中 3 份，Hook helper 直接按 Swift 5 编译 4 份 |
| QuotaViewFutureContracts | Swift 6，1 文件 | 共享产品 scheme 没有该模块 |
| QuotaView、QuotaViewActivityHook | 均为 Swift 5 | 均为 Swift 5，同一 Debug scheme 还构建 Swift 5 的 Widget 扩展 |
| QuotaViewProbe、QuotaViewCoreTests | 均为 Swift 5，测试模块 85 份源码 | 产品 scheme 没有 Probe。另行检查的 QuotaViewTests 在迁移前的基线就缺少 App 与 FutureContracts 的模块依赖，未计入成功覆盖 |

原生 Release 的语言模式继承原配置。旧 schema 1 文件从独立试点恢复。生产文件存储器读取旧快照、验证毫秒时间与缺省字段后，在隔离目录写回。输出与历史夹具逐字节相同。使用同一文件入口验证到期快照和未知 schema 的拒绝路径。

## 并发审计

| 原有类型 | 处理及保证 |
|---|---|
| OpenedSocket | 改为受检查的 Sendable。两个不可变字段是 Int32 与 Data。actor 丢弃旧连接时关闭 fd，有效连接交给 FileHandle |
| DesktopIPCSocket | 保留手工保证。锁保护读写与幂等关闭，阻塞写沿用当前 I/O 超时。半帧写失败沿既有断连通路结束流。单次写超时不能推导为整帧总耗时上限 |
| SOCKS5HTTPBridge | 保留手工保证。监听、会话、定时器和启动回执均在专用串行队列处理。重复启动不会覆盖待完成回执 |
| CodexActivityUnixBridge | 保留手工保证。登记和接手路径受进程内锁保护，旧实例只清理自己的设备号和 inode。取消回调最终关闭该代 fd，原连接仍可确认 |
| CodexActivityFileBridge | 保留手工保证。独占串行队列管理交付与启动，按代次拒绝迟到确认。目录监听 fd 随 source 取消关闭，队列内重启可重入 |
| ClaudeCodeBridge | 保留手工保证。串行队列保护连接和回复状态，监听 fd 由取消回调关闭。停止时核实路径身份并允许在断开回调内停止 |
| IslandResetDustResources | 保留手工保证。SDK 的 MTLTexture 缺少 Sendable，资源在发布前建成，纹理此后仅供 shader 读取，每帧创建各自的命令缓冲 |

Swift 6 还要求私有 SOCKSBridgeSession 显式声明可跨并发上下文传递。此类型只在上层桥的队列创建和释放，两个 NWConnection 与超时计时器均在同一队列交付。加上这一处，生产源码共有七处 `@unchecked Sendable`。已覆盖的正常连接、重复启停、跨代确认和 Metal 资源复用见本机验证目录 `.build/macos-architecture/8/staging/`。跨进程抢占监听路径、整机续航以及资源准备失败后的 GPU 重试均未作实测。
