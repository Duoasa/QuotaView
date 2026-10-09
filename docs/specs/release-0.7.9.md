# QuotaView 0.7.9 发布

Spec ID：`QV-RELEASE-079-001` · 状态：`Authorized / Preparing`

## 身份与授权

- 用户于 2026-10-09 明确要求 0.7.9 发布前测试、打包、签名、公证、GitHub 合并 main 和 appcast。
- 本次身份：`0.7.9 / 显示 Build 1 / Sparkle 内部 59`；tag `v0.7.9-build.1`；资产 `QuotaView-v0.7.9-build.1.zip`。
- 用户确认沿用仍可恢复的 Sparkle 加密离线备份；要求等新封面到位再正式发布，随后提供 `4.jpg`。原图已保存为 `Resources/QuotaView-0.7.9-Cover.jpg`，用于双语 README 和英文 Release。
- Stable / Latest 与 appcast 均已授权；在产物、公证、公开回下载与 Feed 检查完成前不记为已发布。
- 上一稳定版 `v0.7.7-build.1` 保留不变；完整回滚事实见[版本历史](../../VERSION_HISTORY.md#当前最新版本)。

## 范围

扩大 Agent 支持至 Codex、Claude Code、DSH、Kimi Code，含 DSH 定制客户端目录兼容；增加展开宽度、实时特效预览等个性化选项，优化窄宽用量图表、hover 与设置。README 删除 0.7.5 之前的旧版本介绍，保留历史记录在版本历史。

本轮新增功能规格：[展开宽度](island-expanded-width.md)、[实时预览](settings-live-effect-preview.md)。运行包维持独立开发 Bundle ID，正式发行采用 Distribution 配置。

## 发布前证据

- 首轮 695 项测试发现实时预览 Metal 子视图圆角裁切断言失败；恢复子视图裁切后复跑 695 项，0 失败、6 项环境条件跳过。
- 新增 4 项隔离冒烟：宽度默认值/持久化/非法值、物理刘海与屏幕边界、页面与独立尺寸、三种实时预览的帧率/分辨率/离屏停播，全部通过。
- Native Question Bridge 44 项隔离契约检查通过，真实动作数 0。任务展示基准 P95 5.59 ms、最大 6.16 ms；该值不是 GPU 或真实交互耗时。
- 开发包已于 18:44 更新并启动，PID 33365；234 项输入、13 个资源、完整包与动态库加载路径匹配，实际版本 `0.7.9 / 1 / 59`。
- 显式启用所有本机夹具后，699 项通过、无跳过，覆盖 Codex Hook、HTTP/SOCKS5 与 20 + 100 秒真实收起时序。
- 补充 DSH/Kimi 接入夹具发现 DSH 未消费 ACK 导致事件队列逐条等待 750 ms 超时；加入 socket.resume() 并新增自动回归测试。修复后 24 个 DSH 事件、两份客户端命名空间、11 个 Kimi 事件及隐私/无审批输出检查通过。首次公证候选包被替代，不发布；以修复后的重新构建、完整测试和最新 CI 为准。
- 深浅色、中英文、键盘/Escape/外部点击、Reduce Motion、Increase Contrast、VoiceOver、带刘海实机，以及 DSH/Kimi 真实会话端到端交互仍由用户验收；本轮自动化不替代视觉或全设备结论。

本地原始证据：`dist/verification/0.7.9-build1-release/`；开发运行证据：`.build/079-development-runtime-20261009/`。
