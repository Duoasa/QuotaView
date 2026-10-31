# QuotaView 0.8.5 发布

Spec ID：`QV-RELEASE-0.8.5-001` · `Released / User Acceptance Pending` · 2026-10-27。

用户明确要求版本 0.8.5、接入真实 Codex 重置且不使用其重置卡、推送 GitHub、合并 main 并更新 appcast。按新 Marketing Version 的 Build 归一规则，本次身份为 **0.8.5 Build 1 / 内部 81**，tag `v0.8.5-build.1`，不可变资产 `QuotaView-v0.8.5-build.1.zip`。本次身份已获 macOS Stable/Latest 与签名 appcast 完整发布链授权；不覆盖已有资产、不改 Windows 独立通道、不替换本机正式安装。

范围：灵动岛 Codex 手动重置；重置说明深色玻璃、额度行对齐、操作区深浅适配；设置任务特效前移。保留 main 的短屏高度修复和 Windows 工程。真实重置契约见 [Codex 手动额度重置](codex-quota-reset.md)。

上一 macOS 稳定版 `v0.8.3-build.1` 是本次回滚基线；先回下载核对其版本历史记录，保留 tag 和资产。发布顺序：隔离测试与必要完整检查 → 开发包更新 → 源码提交与冻结输入 → Universal Developer ID 签名、公证/Staple及解压验证 → PR/main CI → 不可变 Release与回下载 → 签名 macOS appcast及线上核对 → 发布文档回填。

验证不会调用真实消费接口；真实扣卡端到端及视觉由用户验收。具体提交、检查、包哈希、公证与渠道事实只在 [版本历史](../../VERSION_HISTORY.md#当前最新版本)记录，当前开发状态见 [Handoff](../../HANDOFF.md)。

2026-10-27：源码经 PR #105 合入 main，PR/main CI 成功；722 项测试（6 跳过、0 失败）及 44 项审批契约通过。Universal 包签名、公证/Staple、解压启动与公开回下载验签完成；GitHub Stable / Latest、签名 appcast 和中英文 README 已更新。真实消费仅在隔离夹具验证，没有使用用户重置卡；真实扣卡与视觉仍待用户验收。完整发布证据见版本历史，开发包状态见 Handoff。
