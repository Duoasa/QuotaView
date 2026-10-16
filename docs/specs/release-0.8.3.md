# QuotaView 0.8.3 发布

编号：QV-RELEASE-0.8.3-001 · 状态：Accepted / Verifying

2026-10-16 用户明确要求用最新开发代码封装 0.8.3、推送合并 main、更新 README 和 appcast。精确身份为 0.8.3 Build 1 / 内部 75，tag `v0.8.3-build.1`，资产 `QuotaView-v0.8.3-build.1.zip`。GitHub Stable/Latest 与签名自动更新准入已批准；按发布规则继续完成整条链路。

范围为 macOS 27 深色玻璃兼容、下部玻璃与悬浮胶囊统一浅色/深色/自动外观、设置重分组、图标/文案微调，以及 Widget 自定义字体文件 descriptor 修复。小组件本机 Medium 已由用户确认恢复，其余系统/尺寸/外观矩阵不宣称已验收。真实额度重置保持演示。

完成条件：完整测试及问答契约、PR/main CI；Universal arm64+x86_64、Developer ID、公证/Staple/Gatekeeper；冻结输入与源提交一致、资源/解压启动/动态库；不可变 Release 资产公开回下载和 EdDSA；保留历史项的签名 appcast 部署、在线字节/更新目标；中英文 README、Handoff、注册表与版本历史同步。

回滚基线 `v0.8.2-build.2` / `d16307f4666f75b94a40cdb3933777a028d8fa8a`，25,070,922 bytes，SHA-256 `49945e73487f40ec945e7db88ecc4c6d2ecf35c053bd60e1772be2805ebfcb4c`。保持旧 tag/资产/签名不变。

证据 `dist/verification/0.8.3-build1-release/`；不可变发布事实完成后进入[版本历史](../../VERSION_HISTORY.md#当前最新版本)，运行包见[Handoff](../../HANDOFF.md)。
