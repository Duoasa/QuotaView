# QuotaView 0.9.1 发布

Spec ID：`QV-RELEASE-0.9.1-001` · `Released / User Acceptance Pending` · 2026-11-02。

用户明确要求正式发布 0.9.1、更新双语 README 与全部产品图、使用 CN/EN 封面及新产品图标、推送并合并 main、默认开启自动更新检查、发布 Release 和 appcast；Release 说明先介绍新品牌视觉，再简短介绍更新内容。

本次身份按当前 Build 15 顺延并冻结为 **0.9.1 Build 16 / 内部 149**，tag `v0.9.1-build.16`，资产 `QuotaView-v0.9.1-build.16.zip`。本轮授权覆盖此身份的源码合并、Developer ID 签名、Apple 公证/Staple、Stable/Latest Release、公开回下载核验和签名 appcast 部署。若最终验证后需更换此发布身份或重打包，按发布规则处理；不沿用到其他版本。

## 发布内容

- QuotaView 保留现有名称，以蓝色终端图标、Agent 标识、任务卡片和新版产品图介绍新的品牌视觉。
- 双语 README 全部产品配图使用用户提供的 `Desktop/0.8.1` 目录原图：CN/EN 各一张封面、中英文各五张功能图。文件夹名不作为当前版本号。字节与来源清单见 `docs/media/readme/0.9.1/assets.json`；README 开头图标与当前应用原始 PNG 相同。
- 包含新版设置、六语言、扩展 Agent 预览接入及 Devin Desktop/CLI 模型/Token 补读、重置保护与一周内到期列表、完成卡片中性背景和首批性能优化。
- 正式自动检查更新默认 true，24 小时周期；已有用户偏好优先，用户可关闭，下载/安装仍需确认。最终正式包须核对 `SUEnableAutomaticChecks`、`SUAutomaticallyUpdate` 和 `SUAllowsAutomaticUpdates`。
- 本版内部 149 作为第二个正式公告版本加入精确名单，与 102 各自确认一次；开发身份不会自动弹出正式公告。
- GitHub Release 使用单份简短英文正文，由 GitHub 提供界面翻译；README 为中英文两份。

## 边界与验证

保留 Windows 0.8.3-win.13 及其独立更新通道、用户偏好和正式安装。禁止真实额度重置；Devin 等预览接入仍依赖客户端版本/本地数据，未将隔离夹具等同于朋友实测通过。CPU/GPU/耗电的整机收益未量化，发布文案不写微基准百分比。

回滚基线为 `v0.8.6-build.21` / `3b737073d8a33b8362448d497141772629c3d989`，已发布资产不可覆盖。验证包含完整 Swift 测试、44 项契约、PR 与精确 main CI、冻结生产输入、双语图片与链接、开发运行包、Universal 架构、正式身份、签名/公证/Staple/Gatekeeper、解压启动、公开 ZIP 回下载、内置公钥验签及在线 appcast 历史条目保留。

已完成源码合并、PR/main CI、签名公证、Stable / Latest Release、公开 ZIP 回下载及签名 appcast 上线核验。完整 786 测试（7 跳过、0 失败）、44 契约及修正后 14 项 Devin 专项通过；首次 CI 夹具读写锁竞争仅调整测试连接等待，生产输入与原公证包保持一致。最终包默认检查/手动安装策略已核对，12 张原图及图标来源字节一致。不可变事实见 [版本历史](../../VERSION_HISTORY.md#当前最新版本)，开发运行结果见 [Handoff](../../HANDOFF.md)。证据目录 `dist/verification/0.9.1-build16-release/`；视觉、朋友真实 Devin 环境及真实升级体验由用户验收。
