# Agent 连接与任务接入

Spec ID：`QV-PRODUCT-AGENT-INTEGRATIONS-001` · `Accepted / Verifying` · 2026-10-09。

## 授权与目标

用户要求修复设置停留在用量页的问题；连接页采用 VibeIsland 的 Agent 列表，新增 DSH 和 Kimi Code，并明确允许参考 VibeIsland 的多 Agent 接入。沿用本轮查看实际效果的开发运行授权，不包含发布、推送或版本身份变化。

随后要求兼容基于 DSH 的定制客户端（例如本机 Scoder、DeepViewer），只做兼容，统一显示 DSH。多目录修订随后按用户“启动”要求进入 14:26 开发运行包。

连接页以四行列表呈现 Codex、Claude Code、DSH、Kimi Code，统一名称、圆角矩形真实品牌图标、连接状态与开关；展开箭头位于固定宽度最左列，状态固定列宽，名称可展开该来源的实际设置。图标来源与尺寸见[来源图标记录](../design/quotaview-provider-icons.md#agent-连接列表2026-10-09)。移除连接页独立预览；套餐、额度、Tokens、成本统计仍属于用量页。继续现有 QuotaView 中性开关与中英文文案。

## 参考与适配

- [VibeIsland 项目](https://github.com/vibeislandapp/vibe-island)以公开说明、社区内容为主；[更新记录](https://vibeisland.app/changelog/)记录 DSH 原生插件及 Kimi Hooks 接入。只读核对本机已安装适配器的事件接口与配置形式，未复制应用代码、图标或品牌资产。
- DSH：按本机 `@deepseek-ai/dsh 0.1.7-rc.2` 的公开 TypeScript 接口实现原创 `session/event` 插件，注册至现有 profile 的 `cordis.patch.yml`。不使用 Claude 兼容 Hooks 推断 DSH 原生事件。
- Kimi：按 [Kimi Code 官方 Hooks](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html) 实现 `~/.kimi-code/config.toml` 的 `[[hooks]]`；本机客户端为 2.1.1。兼容 `tool_call_id` 与 `tool_use_id` 字段，不将官方客户端内的审批接口替换为自动决定。
- CodexBar 参考预检：Provider 独立生命周期、迟到结果隔离及明确缺失值的做法适用。任务事件接口由各 Agent 决定，UI 采用用户指定的 VibeIsland 列表，不迁移参考项目的轮询和套餐布局。

## 行为与边界

| 来源 | 当前实现 |
|---|---|
| Codex | 保留原生任务流及补充 Hook；新增总开关，停用停止任务观察并撤下卡片，恢复后重新连接 |
| Claude Code | 保留现有 Hook、可交互审批及独立用量采集；展开后提供原有设置 |
| DSH | 插件发送开始、工具、权限提醒、压缩、完成/失败/中断、公开会话标题和模型；累计事件中实际提供的 Token；明确的 `origin=subagent` 父子关系进入已有子任务展示 |
| Kimi Code | Hook 发送开始、工具、权限提醒、压缩、完成/失败/中断、标题和模型；若提供明确非 `main` 的 `agent_id`，隔离到子任务，避免子任务完成覆盖主任务 |

- DSH / Kimi 首次默认关闭。启用写入本渠道配置后显示“等待会话”，只有接收到有效事件才显示“已连接”。配置失败显示原因与重试，即使开关已关闭也不隐藏清理失败。
- 配置状态与实时在线心跳不同：“已连接”表示本次运行已收到有效事件，不能据此推断客户端仍在线。
- DSH / Kimi 权限仅提醒，用户在原客户端确认；不展示可响应按钮。终止、失败和完成按来源实际发出的生命周期事件映射。Kimi `Stop` 是可被其他 Hook 阻止的预结束通知，不能据此宣称所有 Hook 决策之后的强一致完成。
- 本次不增加 DSH / Kimi 的套餐额度窗口、30 日历史统计、成本估算和完整回答同步，没有来源的数值不伪造为零。完整回答在原客户端查看。
- DSH/Kimi 新接入未经过真实会话端到端验收；事件契约之外的旧版客户端、跨设备配置、断线期间的历史重放和失联回收不作为已验证能力。

## 配置、隐私与资源不变量

- 各 Provider 独立私有 socket、认证令牌、支持目录和开关；会话标识以 Provider 为命名空间后哈希。DSH 额外纳入规范化数据目录的 SHA-256，父子身份、轮次和工具调用沿用同一命名空间；复制的 session ID 不会跨客户端覆盖。配置注入目录哈希，事件不传递原始目录，不增加定制客户端 Provider、名称或图标。
- 配置修改移入 utility 任务，按修订串行执行；旧任务不能发布新状态。停用停止监听并撤下其任务，不继续读取事件。
- 只增删本渠道标记块；保留用户及 VibeIsland 等其他工具的配置。修改前保存内容寻址备份，写前核对文件版本，原子替换单文件；保留原权限。多 profile 不构成文件系统事务，任一写入失败显示错误，重试会收敛全部 profile。
- 转发公开会话标题、模型、工具名、有限标识、生命周期及 DSH 实际 token 数；不转发提示词、工具参数/输出、完整回答、账户凭据和完整工作目录。数据只走本机私有 socket。
- 插件异步写入、有限队列 256、连接超时 750 ms，错误不阻塞 DSH；Kimi Helper 不输出审批决定，连接/写入/回执各至多 250 ms。无新增周期性轮询或 GPU 预览。队列溢出丢弃最旧事件，不承诺离线历史完整性。
- Runtime 最多记录 512 会话，子任务展示复用现有 128 上限。DSH 按来源 epoch/seq 去重。

### DSH 定制客户端与多目录

- 只读核对本机运行 Scoder 的 `resource-locator.ts` 和独立 DeepViewer 对应源码：二者均将 `DSH_HOME` 设置为各自 `userData/harness-home`，沿用 DSH profile 与原生事件接口。兼容入口由目录结构判断，不硬编码品牌白名单，不合并用户数据。
- 默认目录 `~/.dsh` 与非空 `$DSH_HOME` 并行支持。启动、启用、重新检查或修改自定义目录时，扫描当前用户 `Application Support/<应用目录>/{harness-home,harness,.dsh}/profiles/<profile>`；不递归搜用户目录或会话。只接入包含 `cordis.yml` 和有效 `package.json.dsh.profile`、属于当前用户的 profile，跳过备份/迁移/归档/快照路径并对符号链接规范化、去重。
- 连接列表保持单一 DSH 行。展开后显示配置目录数量、重新检查和添加目录；非标准位置可选择数据根目录、profiles、具体 profile 或包含 harness-home 的应用数据目录。自定义目录最多 32 项，可移除；仍符合自动发现条件的目录由自动发现管理。
- 插件落在各个 profile 的可写 `cordis.patch.yml`。本渠道私有安装清单最多记住 512 个配置路径，先记录写入意图，确保部分失败后仍可停用清理。停用/移除只清理本渠道标记块；不可访问的路径保留在清单，待再次检查时清理。不删除客户端原有插件、配置、会话或缓存。
- 新配置需重启对应客户端使其加载（支持 live patch 的客户端也可能自行加载）。没有进程扫描、周期轮询或自动重启客户端。原生事件 API 不兼容的旧版/深度改造版尚不承诺支持。

## 设置导航修复

静态壁纸采用 `scaledToFill`，单纯裁切不保证命中区域随视口缩小。装饰图片明确禁用命中，容器设置视口内的 contentShape，导航提高层级。只读采样发现部分主线程时间等待 Metal drawable，未证明全局死锁，未把该观察冒充此次点击问题的唯一根因。

## 验收记录

- Swift Debug arm64 编译及 DSH JavaScript 语法检查；运行包身份、源码指纹、实际加载路径的结果见 [Handoff](../../HANDOFF.md)。
- 未新增/运行测试或 UI 自动化；未消耗真实审批/额度操作。
- 多目录修订：四个相关 Swift 文件定向 Swift 5 类型检查与 Node 插件语法检查通过，`git diff --check` 通过；证据 `.build/dsh-custom-clients-20261009/`。随后按用户“启动”授权完成 Debug arm64 增量编译并替换运行；14:26 / PID 53217，234 项输入、完整运行包及实际加载路径匹配。已核对 9 个根目录的 13 个 profile 注册标记、命名空间、原有其他配置、权限和备份；证据 `.build/dsh-custom-runtime-20261009/`。未重启兼容客户端或启动真实任务，真实会话并行与启停仍待验收。
- 用户验收：页面切换、列表布局、开关启停、重启 DSH/Kimi 后真实任务与权限提醒。未记录“视觉通过”或“真实会话联动通过”。
