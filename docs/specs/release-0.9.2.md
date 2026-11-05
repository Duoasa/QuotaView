# QuotaView 0.9.2 发布

Spec ID：`QV-RELEASE-0.9.2-001` · Accepted / Verifying · 2026-11-05

用户要求“定为0.9.2，代码推送合并到main，更新release和appcast，release简要说明更新”。按新 Marketing Version 的 Build 计数规则，本次身份冻结为 **0.9.2 Build 1 / 内部 158**，tag `v0.9.2-build.1`，资产 `QuotaView-v0.9.2-build.1.zip`。授权包含此身份的源码合并、Universal Developer ID 签名、Apple 公证/Staple、GitHub Stable/Latest、公开回下载及签名 appcast 发布；无需重复申请同范围许可。

## 范围

相对公开 0.9.1 Build 16，仅包含鼠标跨屏跟随，DSH 支持的工具审批、会话标题/模型与最终回答同步。公告与简短英文 Release 说明均按此增量；README 同步下载入口和能力说明，保留现有中英产品图。内部 158 加入正式公告名单，与 102/149 独立确认一次；开发包仍不自动展示。自动检查更新默认开启、24 小时周期，用户已有偏好优先，下载/安装仍需确认。

回滚基线 `v0.9.1-build.16` / `f1bf0a3de597a56ffa0b6f2567cd38dda540c528`，ZIP 大小 31512845，SHA-256 `6947280fe65f1c037f08ca56ab1f770a8ce09fc90bb0a34142d3bd03d3225f85`；旧 tag 与资产不可覆盖。保留 Windows 0.8.3-win.13 和独立更新通道、正式安装和用户数据，不消耗真实重置卡。

## 验证与交付

需要完整 Swift 测试、44 项契约、PR 与精确 main CI；冻结生产输入；Universal 架构/正式 App 与 Widget 身份、默认更新策略、签名/公证/Staple/Gatekeeper、隔离解压启动；公开资产字节一致与内置公钥 EdDSA 验签；签名 appcast、历史条目与 Windows feed 保留。源码发布与实际交互验收分开，用户已确认鼠标跟随体验，DSH 未扩大为全部客户端现场验收。

证据目录 `dist/verification/0.9.2-build1-release/`。当前为发布准备，成功后更新 [版本历史](../../VERSION_HISTORY.md#当前最新版本)、[Handoff](../../HANDOFF.md) 和本节状态，不将候选包宣称为已发布。
