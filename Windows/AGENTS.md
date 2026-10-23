# Windows 维护范围

本目录是 QuotaView 的完整 Windows 工程；未来 PR、Issue、发布和更新统一使用 `Duoasa/QuotaView`。迁移来源为 `Duoasa/quotaview-windows` 的 `cfc5490`，旧仓库只保留历史。

- 应用代码在 `webview2/`、`windows/` 和共享 `ElectronEffects/`。构建入口 `./build.ps1`，从本目录执行；不要修改 macOS Target 来实现 Windows 功能。
- Windows 只保留纯色灵动岛与胶囊、AI 球和量子噪点；无桌面小组件。当前支持边界以 `webview2/README.md` 为准。
- Windows 开发版本单独递增 `version.json` 的 `-win.N`。根目录的 macOS Marketing Version、内部序号及 macOS appcast 不随 Windows 修改而改变。
- Windows 更新仅使用 `updates/appcast.xml`。已有精确版本准入规则继续适用；代码推送与空通道创建不等于某个版本获准进入自动更新。不要自动创建正式 Release 或将 Windows 设为全仓库 Latest。
- 私钥不得提交或包含在运行包中，签名工具默认使用仓库外的当前用户 DPAPI 加密文件。公钥可随源码发布；不能在日常构建时重新生成。
- 使用 `xuchen1995@gmail.com` 提交。本地验证、开发运行包更新与用户验收分别记录，不能把编译通过当成视觉或真实审批通过。
