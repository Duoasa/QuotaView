# QuotaView 0.9.9 macOS 发布

## Build 2

macOS 0.9.9 Build 2（内部 284）使用标签 `v0.9.9-build.2` 和资产 `QuotaView-v0.9.9-build.2.zip`。发布输入包含 Antigravity 直接父子会话归组和 Claude Code 并行子任务角色修复。回滚基线为 0.9.9 Build 1（内部 281）。已按本版本授权合入 main，并在合并提交的 CI 通过后部署到 Sparkle。线上更新源已用已发布客户端的公钥验签，Build 1 查询到 Build 2，Build 2 查询返回已是最新版。 [发布记录](../../VERSION_HISTORY.md#macos-099-build-2)

## Build 1

用户已批准本版本合入 main、发布 GitHub 稳定版并纳入 Sparkle 自动更新。精确版本为 0.9.9 Build 1（内部 281），标签为 `v0.9.9-build.1`，资产为 `QuotaView-v0.9.9-build.1.zip`。回滚基线为已封存的 macOS 0.9.7 Build 1。[版本历史](../../VERSION_HISTORY.md#当前最新版本)

应用内采用已定稿的四组十条公告。公开 Release 使用同内容的英文说明。Universal 包已通过 Developer ID 签名、Apple 公证、Staple、Gatekeeper 与隔离启动。GitHub 公开 ZIP 回下载一致，Sparkle 线上更新源和 ZIP 均已用内置公钥验签。
