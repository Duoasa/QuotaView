# Windows 更新通道

固定地址：`https://raw.githubusercontent.com/Duoasa/QuotaView/main/Windows/updates/appcast.xml`。macOS 继续使用原 Sparkle feed 和原密钥。Windows 不读取 GitHub 全局 Latest，也不会安装 macOS ZIP。

首个正式版 [QuotaView 0.8.3-win · Windows](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-win.10) 已发布，并以包内版本 `0.8.3-win.10` 加入此通道。公开名称为 `0.8.3-win`；包名、更新版本和 tag 保留 `.10`，使现有版本比较与签名校验兼容。仅有旧版 GitHub Releases 检查器的 Windows 包需要手动换到本版一次，之后使用此通道；已运行 `0.8.3-win.10` 时不会重复提示安装同一版本。

## 应用内行为

设置的自动检查在启动和每 24 小时执行，关闭后停止定时检查；手动检查始终可用。下载和重启安装均需用户点击。下载可取消，错误可重试；重启前验证包、安装目录可写和辅助进程就绪。跟随应用的系统 / 直连 / 自定义代理设置。

更新采用 Windows x64 standalone ZIP，版本格式 `0.8.3-win.10`，文件名 `QuotaView-Windows-0.8.3-win.10-x64.zip`，GitHub tag `v0.8.3-win.10`。Feed 每项携带平台、架构、包类型、版本、长度、SHA-256 和 RSA-PSS/SHA-256 签名。签名覆盖这些关键字段及完整下载地址；应用内嵌公钥。仅接受本仓库确定的 Release 路径和 GitHub 下载 CDN 的 HTTPS 重定向。损坏、过大、降级、非 Windows、错误架构、路径越界和链接条目不能安装。

下载、备份和更新结果在 `%LOCALAPPDATA%/QuotaView/Updates/<job>/`。辅助进程使用独立运行时，等待原进程退出，再获得应用单实例锁并替换经过验证的文件；替换失败恢复备份。设置与账户仍在原 `%APPDATA%/QuotaView WebView2`，不会被 ZIP 覆盖。安装目录不变，因此 Hook 和自启动路径保留。程序崩溃或掉电不属于事务回滚保证；若因此无法启动，可从该 job 的 `backup/` 恢复相应文件。备份保留供恢复，确认更新成功后可手动删除旧 job。

## 构建与签名

1. 修改 `Windows/version.json`，执行 `./build.ps1 -Action test` 和 `./build.ps1 -Action publish`。CI 也保存构建 ZIP，但不会自动公开发布或写 appcast。
2. 确认精确版本和 Windows appcast 准入授权，遵循[发布规则](../../docs/workflow/RELEASE.md)。macOS Developer ID、公证和 Sparkle 签名不适用于 Windows；Windows 使用下面的独立签名。
3. 在签名机器运行 PowerShell 7.4+：

```powershell
# 从 Windows/ 执行；只生成本地待核验文件，不发布
./updates/New-Appcast.ps1 -Archive ./webview2/release/QuotaView-Windows-0.8.3-win.10-x64.zip `
  -Version 0.8.3-win.10 -OutputPath ./webview2/build/appcast-candidate.xml
dotnet run --project ./webview2/tests/updates/Updates.Tests.csproj -c Release -- `
  --verify-package ./webview2/build/appcast-candidate.xml ./webview2/release/QuotaView-Windows-0.8.3-win.10-x64.zip
```

4. 在 `Duoasa/QuotaView` 创建对应不可变 tag 和 Release，名称注明 Windows；通过 GitHub API 显式 `make_latest: "false"`，不改变 macOS Latest。上传该原始 ZIP，公开回下载再次检查长度、SHA-256 和签名。
5. 只有获准版本才将验证后的 candidate 内容更新到 `Windows/updates/appcast.xml` 并合入 main。同步 Windows README、Handoff、版本历史和实际资产证据；不编辑 macOS appcast。Feed 可以跳过中间版本，不能覆盖旧 Release 资产。

私钥默认位于签名机器的 `%APPDATA%/QuotaViewBuild/windows-update-signing.dpapi`，使用 Windows DPAPI CurrentUser 加密；本仓库只有 `public-key.pem`。新克隆无需私钥即可构建和验证更新。私钥的备份与机器迁移需维护者管理，DPAPI 文件不能直接在另一 Windows 账户下使用；不要通过 Issue、聊天或 Git 传递。`-InitializeKey` 仅适用于首次建立通道，发现公钥或私钥已存在会拒绝覆盖。CI 当前不持有签名私钥。

包完整性签名不等于 Authenticode 代码签名；当前 Windows 发行包仍可能出现 Windows SmartScreen 提示。
