# QuotaView 0.9.3 发布

Spec ID：`QV-RELEASE-0.9.3-001` · Released / User Acceptance Pending · 2026-11-13

用户要求「版本定为0.9.3，推送合并发布release，appcast」，并要求 README 支持列表的 Agent 图标统一圆角矩形底，已有的不重复加底。按版本规则，身份冻结为 **0.9.3 Build 1 / 内部 189**，tag `v0.9.3-build.1`，资产 `QuotaView-v0.9.3-build.1.zip`。授权覆盖此身份的源码推送合并、Universal Developer ID 签名、公证/Staple、GitHub Stable/Latest、回下载与签名 appcast 发布，无需重复申请同范围许可。

## 范围与边界

相对公开 0.9.2 Build 1，包含已实现的重置卡粒子消散/提前递补/空状态与性能优化、二次确认红色光晕、设置页固定右下角柔和红色玻璃退出按钮与 680 pt 最小高度、刷子清理图标、五条多语言增量公告。清理只移除灵动岛卡片，原任务与聊天保留；Codex 重置须用户明确确认，验证不消耗真实卡；Claude 原命令入口不扩展为真实按钮重置。

中英 README 同步版本/下载/更新说明与 Agent 图标。Codex、Claude、Gemini 已有圆角底，保持原图；DSH、Cursor、OpenCode、Copilot、Devin 复用官方矢量标志加白色圆角底，Kimi 原黑底图标裁成圆角，不叠底。仅 README 专用资产，应用品牌图标不变。

内部 189 加入正式公告名单，与 102/149/158 各自独立确认；开发身份不自动展示。默认更新检查开启、24 小时周期，尊重已有偏好，下载和安装需确认。Windows 独立版本/渠道、正式安装和用户数据保持。

## 回滚与验收

回滚基线 `v0.9.2-build.1` / `ebddc6056b62e6b96b121ee2e7179a0c38740aec`；公开 ZIP 大小 31,629,798，SHA-256 `d77f6935a127c96e3ee69120cedd659861935187375f569c99bcdd56caa86d4c`，已回下载匹配历史验证记录；旧 tag/资产不得覆盖。

完整 Swift 测试、契约夹具、PR 与精确 main CI、Universal 架构与正式身份、签名/公证/Staple/Gatekeeper、隔离解压启动、公开回下载与内置公钥 EdDSA 验签、appcast 历史条目保留及线上签名核验均须完成。实际视觉由用户验收；构建/测试不扩展为全设备视觉通过。

证据目录 `dist/verification/0.9.3-build1-release/`。源码经 PR #142 合入 main，PR/main CI、签名公证、Stable/Latest Release、公开 ZIP 回下载与线上签名 appcast 均核验完成；本地/PR/main 各 805 项测试、7 跳过、0 失败，44 项契约通过。完整不可变事实见 [版本历史](../../VERSION_HISTORY.md#当前最新版本)，运行与交接见 [Handoff](../../HANDOFF.md)。
