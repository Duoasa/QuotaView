# QuotaView App 图标试装

## 公告直接读取 PNG：0.9.1 Build 2（2026-11-01）

用户反馈公告图标毛边，要求直接使用 PNG。新增 `Sources/QuotaView/Resources/QuotaViewAppIcon.png`，与当前原始 PNG 逐字节一致，SHA-256 仍为 `17ce2d1a3520204f193e614033413fe77f1300cd970b9ff76d2d3c88398f225a`；Xcode 与 SwiftPM 将其作为独立资源原样复制。公告从包内 URL 直接解码 PNG，不经资产目录/ICNS 的表示选择，使用原色、高质量插值和现有 64 pt 尺寸，移除额外阴影；不修改原图像素、高光、其他入口或窗口尺寸。

0.9.1 Build 2 / 内部 135 已增量构建并更新运行。3 项公告策略冒烟、运行包 PNG 原图一致性及 AppKit 解码 1024×1024/透明通道检查通过；254 个生产输入、资源和实际加载路径核验通过。证据 `.build/announcement-png-091b2-runtime/`。实际视觉由用户验收，未执行 UI 自动检查。以后更新原始图标时需同步此独立 PNG。

## 设置图标渲染修正：0.8.7 Build 22（2026-11-01）

用户澄清原始 PNG 的高光应保留，需消除设置页中的两条突兀横线。关于页改为优先加载原始 `QuotaViewAppIcon` PNG，避免优先经过仅携带较小表示的 ICNS；尺寸仍为 96 pt。15 项图标资源与已合并 Build 16 逐字节一致，原图 SHA-256 不变。图像试修结果未采用，用户原图未改动；实际显示由用户检查。运行证据 `.build/settings-native-frost-087b22-runtime/`。

## 当前素材：0.8.7 Build 16（2026-10-31）

采用用户新文件 `QV-icon-iOS-Solid@1x.png`，SHA-256：`17ce2d1a3520204f193e614033413fe77f1300cd970b9ff76d2d3c88398f225a`。全部图标尺寸、开发包与 Dock 预览已更新；保留关于布局，不操作窗口。证据 `.build/app-icon-087b16-runtime/`。已通过 [PR #122](https://github.com/Duoasa/QuotaView/pull/122) 合入 main `57864ea`，PR/main CI 均通过，239 输入与合并源码一致；未发布。独立 Dock 预览已按用户后续要求清理，当前运行身份见 Handoff。

## 前序素材：0.8.7 Build 15（2026-10-31）

采用用户新文件 `QV-icon-iOS-Default-1024-2@1x.png`，SHA-256：`1037ca849834759b8d9eecc079e6bd4f6a25ee93fff083aa704530d9587fe1e7`。全部图标尺寸、开发包与 Dock 预览已更新；保留关于布局，不操作窗口。证据 `.build/app-icon-087b15-runtime/`，仅本地。

## 前序素材：0.8.7 Build 14（2026-10-31）

按用户要求仅替换最新同名 PNG，SHA-256：`b735ba8269551902562182620eaf71bd6d0dd208b6d95d4a68ad7905273084ba`。完整尺寸、开发包及 Dock 预览已更新，保留关于页布局，不执行窗口操作；证据 `.build/app-icon-087b14-runtime/`。仅本地。

## 前序素材：0.8.7 Build 13（2026-10-31）

用户再次更新同名 PNG，已按最新文件重新生成 AppIcon 和应用内图标；新 SHA-256：`e953220e1a178b1e79ee28399ee5f564a51cd0f376f071a5c737b90c211096e7`。保留关于页 96 pt 图标及信息布局，开发包更新为 Build 13 / 内部 115，并启动使用同一编译图标资源的独立 Dock 预览。证据 `.build/app-icon-087b13-runtime/` 与 `.build/current-dock-icon-preview.json`。用户表示已看到效果，停止进一步窗口操作；未推送或发布。

## 前序素材：0.8.7 Build 11（2026-10-31）

按用户最新提供的 `QV-icon-iOS-Default-1024@1x.png` 替换全部 AppIcon 尺寸和两处应用内图标资源。1024 px 主资源与原图逐字节一致，SHA-256：`1b0ba7c51e7255ea7829ae7cab83e4f14355eb135cf29b60e27e179e95542765`。保留 Build 10 的纯色居中关于布局，未额外修改原图高光或造型。Build 11 / 内部 113 已完成增量构建、运行包更新和编译图标 16–1024 px 核对；证据 `.build/app-icon-087b11-runtime/`。本地试装，视觉由用户验收，未推送或发布。

## 初始素材记录（Build 9）

状态：本地开发预览，视觉等待用户验收。2026-10-31，0.8.7 Build 9 / 内部 111。

用户提供 `QV-icon-1024@1x.png` 并要求替换 App icon 查看效果。采用原始 1024 × 1024 透明 PNG，保留原有造型、颜色与透明边缘；未重新生成设计。原图 SHA-256：`0e5d7667e80a26e437012d0fa9aa08cdf8d1a41aa7608175b85b7162f6043160`。

从原图生成 AppIcon 的十个 macOS 槽位（16–1024 px），同步应用内 App 图标备用资源 `QuotaViewAppIcon` 与旧菜单的 `QuotaViewFigmaAppIcon`。设置与公告沿用现有 `AppIcon.icns` 读取路径。产品名称及菜单栏单色符号保持现有定义。

已完成 Debug arm64 增量构建，编译图标尺寸、ICNS 更新、239 输入、完整运行包和加载路径核验；开发包已重启。证据 `.build/app-icon-087b9-runtime/`；原素材保存在其中的 `original-assets/`，旧运行包备份见 `runtime-result.json`。未运行无关功能测试或 UI 自动验收，实际效果由用户查看。本次只在本地开发版试装，未提交、推送或发布，正式安装未替换。
