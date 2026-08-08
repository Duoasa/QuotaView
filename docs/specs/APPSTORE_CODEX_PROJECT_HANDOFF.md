# QuotaView App Store Codex 项目交接入口

> 文档编号：`QV-HANDOFF-APPSTORE-001`
>
> 更新日期：2026-08-08
>
> 适用版本：QuotaView `1.0.0 (Build 4)` / 内部代号 `v1.0.0a`

## 1. 新项目工作区

新 Codex 项目只打开以下独立 Git worktree：

```text
/Users/sukduoasa/Documents/QuotaView-AppStore
```

目标开发分支：

```text
codex/appstore-runtime-spike
```

该工作树与 GitHub 直接分发工作区共享 `Duoasa/QuotaView` 仓库和 Git 历史，
但拥有独立文件目录、分支、构建产物和上下文。不要复制第二个 QuotaView 主
应用仓库，也不要把其他工作区的未跟踪原型、参考资料或图片带入本项目。

## 2. 新任务启动顺序

按顺序完整阅读：

1. `AGENTS.md`；
2. `HANDOFF.md`；
3. `VERSION_HISTORY.md#当前最新版本`；
4. `docs/specs/README.md`；
5. `docs/design/quotaview-app-store-release-1.0.0.md`；
6. `docs/design/quotaview-app-store-codex-usage-snapshot-bridge.md`；
7. 处理灵动岛时阅读
   `docs/design/quotaview-app-store-codex-island-plugin-bridge.md`；
8. 仅在审计已否决历史路线时阅读
   `docs/design/quotaview-app-store-native-account-provider.md`、
   `docs/design/quotaview-app-store-codex-account-runtime.md` 和
   `docs/spikes/APPSTORE_ACCOUNT_RUNTIME_PHASE0.md`；
9. 准备发行或审核时阅读 `docs/release/` 下的 Review Notes、Privacy、
   Metadata、Support 与插件 Release 草案。

上述文档共同替代旧对话上下文。文档与代码不一致时按 `AGENTS.md` 的优先级
审计，不得把计划或候选包写成已经发布。

## 3. 当前产品与技术结论

2026-08-08，产品所有者明确将商业模式从“免费 App + Codex 灵动岛非消耗型
IAP”改为：

- Mac App Store 付费下载；
- 基准价格 `USD 4.99`；
- 全部内置功能随 App 下载提供；
- 无 IAP、订阅、许可证、试用门槛或单独功能解锁。

原 StoreKit 商品、购买状态、购买/恢复界面、交易监听、本地 `.storekit`
配置、对应测试和发行门禁均已从当前实现删除。Codex 灵动岛只要求公开插件
安装、Hooks 信任和只读目录配对；有效的新鲜插件事件可以直接驱动灵动岛，
不依赖 OpenAI 账号，也不依赖第二次购买。

当前已交付的 App Store 改造包括：

- App 与 Widget 为 `1.0.0 (Build 4)`，发行渠道为 `appstore`；
- 通用页只显示 Bundle 版本，不含自更新器或检查更新占位；
- 额度重置入口、详情、确认、设置、Demo 执行器、Widget 字段与专用资源已移除；
- OpenAI Support Case `12874203` 已确认不为独立第三方原生 App 提供专用
  ChatGPT/Codex OAuth 或个人额度授权流；QuotaView 已移除自有 OAuth、
  Keychain 凭证、`wham` 和账号网络 Provider；
- 用量改由公开伴侣插件调用官方本机 `codex app-server` 的
  `account/rateLimits/read` 与 `account/usage/read`，只写字段白名单
  `usage.json`；登录、凭证和服务网络均由官方 Codex 负责；
- 旧 Codex App Server、外部 CLI、Runtime、Activity Helper、Hook 安装器、
  Expect、Socket 与全局 `/tmp` 队列已从 App Store 目标删除；
- 主 App 启用 App Sandbox、App Group 与用户所选目录只读权限，不包含
  Network Client；
- App Bundle 使用 Privacy Manifest，并对 Required Reason API 设置独立源码、
  Manifest 与 Bundle 门禁；
- 用量和 Codex 灵动岛统一通过只读 security-scoped bookmark 插件桥；协议
  v1 校验 manifest、字段白名单、文件类型、所有者、权限、大小、时效、
  安装 ID 与活动单调序列；
- “连接与灵动岛”设置页提供默认开启、跨启动持久化的独立显示开关；关闭后
  立即隐藏灵动岛，但后台继续消费用量、连接状态和活动事件；
- 断开、停止和插件重装时，旧异步读取、游标与展示状态不能跨修订或安装实例
  重新写回；
- 公开插件仓库 `Duoasa/QuotaView-for-Codex` 的旧固定 tag
  `v1.0.0-preview.1` 已发布；支持用量快照的 `preview.7` 候选已提交到公开
  仓库主分支，并通过 mock/live 与隔离安装/卸载/重装验证，但尚未创建固定
  tag 或 GitHub Release，不能写成固定发布版本；
- 双语 Privacy、Support、App Store Metadata 与 Review Notes 已切换为
  `Paid Upfront / USD 4.99 / all features included / no IAP`；
- readiness、Bundle 与导出脚本已将 OAuth 门禁替换为脱敏用量快照门禁，并
  明确拒绝 Network Client、OpenAI 凭证配置和非公开用量端点；不上传产物。

包内 Runtime Phase 0 只作为历史 No-Go 证据保留。其约 436 MiB 的 Universal
Runtime 路线已经淘汰，不得恢复为生产入口。2026-08-08 之前生成的签名
Archive 和 Apple Distribution `.pkg` 也早于商业模式变更，只证明历史导出
链路，不再对应当前源码或最终提交内容。

## 4. 当前验证状态

- `swift test`：61 项、0 失败，1 项显式 live 插件 E2E 在普通运行中跳过；
- App Store gate status Shell 回归：通过，包含 `paid-upfront`、`4.99` 与
  `pending/configured` 价格门禁；
- 官方 `codex app-server` 真实只读联调已通过；验证输出不打印账号或用量内容；
- 源码、测试、配置和 Xcode 工程已移除 StoreKit 购买运行时及本地商品配置；
- 本轮用量快照架构修改后的 Universal 无签名 Release 已构建并通过 Bundle
  审计；App、Widget、Framework 均为 `arm64 + x86_64`，版本
  `1.0.0 (Build 4)`，无 `.storekit`、`.xctest`、Runtime、
  CLI、Helper 或 Probe；
- 历史签名 Archive、Apple Distribution `.pkg` 和插件公开资产验证仍可作为
  发行链路证据；最终签名包必须在外部门禁关闭后重新生成；
- 视觉与交互验收：Widget 数据显示与唯一注册已由产品所有者确认；其余矩阵
  等待产品所有者运行确认。

本次交接已重新执行并通过：

```bash
swift test
zsh Tests/ReleaseScripts/test-appstore-gate-statuses.zsh
zsh Tests/ReleaseScripts/test-appstore-metadata.zsh
zsh Tests/ReleaseScripts/test-appstore-privacy-manifest.zsh
zsh Tests/ReleaseScripts/test-appstore-url-security.zsh
scripts/check-appstore-readiness.sh
git diff --check
```

本机交互仍应从 Xcode 的 `QuotaView` Scheme / `My Mac` Run，视觉结果由产品
所有者确认。

本轮 Apple Development 签名 Archive：

```text
/private/tmp/QuotaView-Build4-SignedLocal-20260808/QuotaView.xcarchive
```

## 5. 当前真实阻断

- App Store Connect 尚未确认 Paid Apps Agreement，也未把 App 基准价格配置
  为 `USD 4.99`；因此 `QUOTAVIEW_APP_PRICE_STATUS` 必须保持 `pending`；
- 支持脱敏用量快照的插件 `preview.7` 尚未发布固定 tag/Release；发布后还需
  在全新 Codex 用户环境验证官方登录、安装、Hook 信任、配对、真实用量、
  真实事件、诊断、卸载和重装；
- App Review 对“付费第三方 App + 外部官方 Codex + 公开插件 + 本地脱敏
  数据”的 Content Rights 与 2.5.2/5.2.2 判断仍是外部审核风险；
- Privacy Policy 与 Support URL 尚需公开，支持邮箱和审核联系人仍待确认；
- 新的付费全功能设置页、主面板、Codex 连接快捷入口和 Codex 灵动岛仍等待产品
  所有者实机视觉与交互验收；
- 所有门禁关闭后还需重新生成最终 Archive/`.pkg`，记录签名、entitlement、
  包体和 SHA-256，再由产品所有者单独授权上传与提交审核。

这些是后续工作的真实起点。不得因为规格已接受或本地测试通过就声称可以
提交 App Review。

## 6. 下一项任务

1. 发布并固定支持 `usage.json` 的插件版本，在干净环境完成端到端复验；
2. 在 App Store Connect 接受 Paid Apps Agreement，并将 QuotaView 基准价格
   设置为 `USD 4.99`；实际配置完成后才把价格状态改为 `configured`；
3. 完成 Content Rights 和审核风险材料，公开 Privacy / Support 页面；
4. 由产品所有者完成浅/深色、中英文、无快照、用量可用/错误、插件各状态及
   灵动岛交互验收；
5. 价格、用量快照、插件和公开页面门禁全部关闭后，重新生成最终
   Archive/`.pkg` 并审计；上传和 App Review 提交仍需单独授权。

任何外部门禁失败时，不得回退到 `auth.json`、Cookie、CLI、Runtime、网页
解析、Helper 或下载后执行代码。

## 7. 可直接粘贴给新 Codex 项目的首条指令

```text
这是 QuotaView App Store 1.0.0 的独立开发项目。先完整阅读 AGENTS.md、
HANDOFF.md、VERSION_HISTORY.md#当前最新版本、docs/specs/README.md、
docs/design/quotaview-app-store-release-1.0.0.md、
docs/design/quotaview-app-store-native-account-provider.md 和灵动岛插件桥规格。
当前商业模式是 Mac App Store 付费下载，基准价格 USD 4.99，全部功能包含，
没有 IAP、订阅或单独功能锁。OpenAI Support 已否决第三方原生 OAuth 路线；
当前实现由公开伴侣插件调用官方 codex app-server，只向 QuotaView 提供本地
脱敏 usage.json 和活动事件，QuotaView 自身无 OpenAI 凭证与 Network Client。
下一步只处理插件固定 Release、App Store Connect 价格与内容权利、公开页面、
最终提交包和产品验收。不得恢复 StoreKit 灵动岛门禁、自有 OAuth、wham、
auth.json、Cookie、Runtime、WebKit、Helper、网页解析或下载执行代码；不得
改动 0.3.1 Build 2 稳定发布事实，不得在外部门禁未关闭时声称可提交审核。
```

## 8. 版本控制边界

- 当前工作分支只用于 Spike 与 App Store 适配；
- 不移动 `v0.3.1-build.2`，不覆盖 GitHub Release 或现有资产；
- 不自动 push、建 PR、发布 tag、上传 App Store Connect 或提交 App Review；
- 共享修复必须记录来源提交和合并方向，禁止整仓覆盖；
- 灵动岛插件使用独立仓库，QuotaView 主应用保持单一主仓库。
