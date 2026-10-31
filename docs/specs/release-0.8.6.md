# QuotaView 0.8.6 发布

Spec ID：`QV-RELEASE-0.8.6-001` · `Released / User Acceptance Pending` · 2026-10-30。

用户授权打包 0.8.6、默认开启更新检查、推送合并 main、发布新 Release 和 appcast；暂停排查后已明确恢复。最终身份为 **0.8.6 Build 21 / 内部 102**，tag `v0.8.6-build.21`，资产 `QuotaView-v0.8.6-build.21.zip`。授权覆盖完整签名、公证、合并、Stable/Latest、回下载和签名 Feed 发布链；公开 README 保持不变，Release 使用简短英文说明。

范围：紧凑设置与可分组折叠的更新公告窗口、待确认卡片特效、默认自动检查更新，以及 Codex 记录归档后目录不可读误报修复。公告在本次内部 102 首次启动时展示，关闭后不重复，并保留设置手动入口；第二个版本待其身份确定后配置。保留已有偏好，不自动安装更新、不使用真实重置卡、不替换正式安装、不改变 Windows 通道。

回滚基线 `v0.8.5-build.1` 与既有 ZIP 均保留。测试包括归档/删除后持续轮询与重新检查、真实不可读恢复；发布检查含完整测试、44 项契约、开发运行包、PR/main CI、Universal 正式身份、签名、公证/Staple、Gatekeeper、解压启动、公开 ZIP 回下载和签名 Feed 验证。视觉及真实升级体验由用户验收，不以自动化结果替代。

最终不可变发布事实回填 [版本历史](../../VERSION_HISTORY.md#当前最新版本)，当前状态见 [Handoff](../../HANDOFF.md)。

发布链已完成；727 项测试（6 跳过、0 失败）和 44 项契约通过。GitHub Stable/Latest、签名 Feed 及公开 ZIP 均已核验；完整事实见版本历史，开发运行状态见 Handoff。
