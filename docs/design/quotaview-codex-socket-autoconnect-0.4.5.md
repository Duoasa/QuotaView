# QuotaView 0.4.5 Codex 本地任务流自动连接

> Spec ID：`QV-PRODUCT-CODEX-SOCKET-AUTOCONNECT-011`
>
> 状态：`Accepted / Publishing`
>
> 目标版本：`0.4.5 Build 1`（Sparkle 内部 Build `17`）

## 1. 决策

QuotaView 启动后只读跟随 Codex 自己维护的本地任务 rollout。该通道直接覆盖
Codex Desktop 当前任务，不要求安装、信任或触发 Activity Hook，也不依赖
Desktop 是否连接共享 App Server Socket。共享 Socket 与 Hook/本地队列继续
并行存在，分别作为结构化通知和旧宿主的兼容回退。

本轮从未发布的 0.4.4 共享桥候选继续演进，发布基线为
`0.4.3 Build 1`。产品所有者已完成关键路径检查并批准 0.4.5 发布；正式
签名、公证、GitHub Release 与 Stable appcast 由 0.4.5 发布规格统一收口。

## 2. 目标与非目标

目标：

- Codex 已有任务目录时无需首次配置即可自动连接；新任务或旧任务继续运行时
  自动进入增量尾读。
- 数据源优先级为本地任务流、共享 App Server、legacy Hook；低优先级事件不能
  覆盖同一 turn 已确认的高优先级计划进度。
- 本地任务流只投影开始、完成、Token 数值、计划状态计数与工具类别；Socket
  继续主动关闭正文、推理、命令输出、工具结果和 diff 通知。
- rollout 暂不可用时共享 Socket 与 Hook 仍可工作；重新发现不得重放旧完成、
  重复累计 Token 或倒退同一 turn 的进度。

非目标：

- 不静默写入 `~/.codex`、不安装 LaunchAgent 或新 helper、不修改 launchd
  环境、不主动退出或重启 Codex。
- 不移除现有 Activity Hook、Unix 事件桥或权限隔离队列。
- 不把提示词、回复、命令、工具输入输出、diff、推理或会话正文保存在
  QuotaView 模型、缓存或诊断中；解析器只输出允许的脱敏投影。
- 不把官方仍标记为实验性的 App Server 传输描述为稳定生产接口。

### 2.1 灵动岛样式收口

0.4.5 的灵动岛只保留进度条产品形态：移除“AI 球 / 进度条”顶层选择器、
AI 球动画选择器，以及只服务于 AI 球的 100% / 85% / 75% 展开尺寸选择器。
运行时控制器不再读取这三项旧偏好，展开与紧凑几何统一走进度条布局。旧键值
保留在 `UserDefaults` 中作为回滚输入，但不再写回、迁移或影响当前运行结果。

进度条首次安装或偏好无效时默认使用“量子噪点（Quantum Noise）”；用户已经
明确保存的四种进度效果选择继续保留。底层粒子球仅作为 Metal 进度效果不可用
时的容错渲染器，不再作为可选择的产品样式。

## 3. 状态与降级

```text
disabled       -> 环境明确关闭本地任务流读取
discovering    -> 等待 ~/.codex 的任务状态目录出现
connected      -> 数据库定位 + 活动 turn 有界恢复 + JSONL 增量尾读
rollout 不可用 -> Socket/Hook 继续保留兼容能力
```

本地任务流绝不启动 Codex 进程、不修改 Codex 数据，也不写 `~/.codex`；开发
与故障排查可通过 `QUOTAVIEW_DISABLE_LOCAL_ROLLOUT=1` 完全关闭。共享 Socket
仍保持 0.4.5 既有 attach-only 行为，只有宿主显式提供
`CODEX_APP_SERVER_USE_LOCAL_DAEMON=1` 时才允许启动共享服务。

## 4. Requirement

| ID | Requirement |
|---|---|
| `SOCKET-AUTO-01` | 默认启用本地任务流自动发现；Codex 已有 sessions 目录时无需 Hook 或共享 Socket 即进入 ready 状态 |
| `SOCKET-AUTO-02` | 本地任务流不可用时不安装 Hook、不写 Codex 配置、不启动服务；保持有界重试并让既有 Socket/Hook 独立回退 |
| `SOCKET-AUTO-03` | 显式共享 daemon 环境继续允许复用 0.4.4 的启动与重连路径，QuotaView 退出不得终止共享服务 |
| `SOCKET-AUTO-04` | initialize 使用 per-connection opt-out，关闭正文、推理、命令输出、工具结果、diff 和 Hook run 通知；不得关闭计划与真实终态 |
| `SOCKET-AUTO-05` | 设置页在本地任务流可用时显示自动连接，不要求 Hook 安全确认，并禁用会误卸载兼容桥的“停用”操作 |
| `SOCKET-AUTO-06` | 本地任务流与 Socket 汇总为自动连接能力；两者均不可用时才重新检查 Hook，Hook 可用不能伪装成自动连接 |
| `SOCKET-AUTO-07` | 版本为 0.4.5 Build 1 / internal 17；发布前保持 0.4.3 线上事实不变，获批后由 `QV-RELEASE-0.4.5-001` 更新 GitHub Latest 与 Stable appcast |
| `SOCKET-AUTO-08` | 完成单元测试、Universal ad-hoc 构建、资源/架构/签名检查和一次真实启动连接冒烟；视觉验收仍由产品所有者完成 |
| `SOCKET-AUTO-09` | 灵动岛只保留进度条形态；设置页移除 AI 球样式、AI 球动画和 AI 球展开尺寸，旧偏好不得继续控制运行时布局 |
| `SOCKET-AUTO-10` | 新安装或无有效偏好时默认使用量子噪点；已保存的合法进度效果继续生效，底层粒子球只保留为渲染不可用回退 |
| `SOCKET-AUTO-11` | 默认只读查询 `state_5.sqlite` 的线程标识、rollout 路径与 cwd，并拒绝 `sessions` 根目录外路径；数据库不可用时只在已知 sessions 根目录内做有界回退 |
| `SOCKET-AUTO-12` | 启动只恢复尚未出现终态的最近活动 turn；运行时只读取追加字节，旧完成不得重放，单行、尾读字节与候选线程数量均必须有上限 |
| `SOCKET-AUTO-13` | rollout 主通道只保留任务生命周期、计划状态计数、Token 数值、工具类别、工作区末级名称和哈希标识；不得把任何正文写入模型、缓存或诊断 |

## 5. 隐私与安全

- 线程与 turn 标识进入 QuotaView 状态层前转换为 SHA-256 哈希；数据库与单行
  解析中的原始值不进入长期对象。
- rollout 读取是本地、只读、增量的；解析时会解码 JSON 行，但 message、
  reasoning、工具正文和 task 完成正文等字段一律忽略并立即释放。
- Decoder 最多处理 `1 MiB` 单行、`100` 个计划步骤、`16 MiB` 启动尾读与
  `24` 个最近候选线程。
- 仅连接当前用户的本地 Unix Socket；不开放 TCP listener，不接收远程连接。

## 6. 验证

1. 配置测试覆盖本地任务流默认自动发现、显式关闭，以及 Socket 的显式 daemon
   启动权限。
2. 协议测试确认正文类通知被 opt-out，计划、开始和真实完成通知仍被保留。
3. 原有计划单调性、Goal、等待、中断、失败、旧 schema 与 Hook 测试全部通过。
4. Universal 构建核对 App、Core、Widget、Activity Hook 的 `arm64 x86_64`、
   版本、资源和签名。
5. 真实启动时，在不调用 Hook 安装流程的情况下定位当前 Codex Desktop 的
   rollout，并确认活动 turn 的 Token 与真实完成事件进入脱敏投影；不截图、
   不自动展开。
6. 深浅色、中英文、交互和辅助功能显示结果标记为“等待用户验收”。
7. 偏好与几何测试确认旧 AI 球、动画和尺寸值原样保留但被忽略；无有效进度
   效果时解析为量子噪点，展开与紧凑尺寸只使用进度条几何。

## 7. 当前验证（2026-09-04）

- `swift test`：128 项通过，0 失败；新增覆盖 rollout 正文忽略、标识哈希、
  Token 数值、直接/exec 包装计划计数、活动 turn 启动恢复、历史完成抑制和
  增量完成尾读；原有 Socket、Hook、Goal、等待和终态测试保持通过。
- Universal Release 无签名构建通过；App、Core、Widget 与 Activity Hook 均为
  `x86_64 arm64`，版本/Build/资源正确，干净临时副本的 ad-hoc 严格校验通过。
- 新构建以 PID `26046` 从
  `/private/tmp/quotaview-0.4.5-smoke.OOOPFj/QuotaView.app` 启动并保持运行；
  脱敏诊断已记录 `source=startupReplay`、`activity_source=localRollout` 的当前
  活动 turn 恢复证据。开发 ZIP SHA-256 为
  `585b0b9e7cfcd756dec4dbc257351f27b4295c0305d6248e5b369ce6d3252606`。
- 工作树位于 FileProvider 管理目录，`dist/QuotaView.app` 在构建脚本完成严格
  校验后会被系统重新附加空 FinderInfo；因此启动冒烟使用无该元数据的临时
  副本，ZIP 与构建脚本内的解包校验保持通过。
- 通过共享 App Server 的真实四步计划、量子噪点进度条、运行与完成信息、
  等待确认提醒等关键路径已由产品所有者检查并批准发布；完整辅助功能交叉矩阵
  不作为本次发布的已验证结论。
