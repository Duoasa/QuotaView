# QuotaView App Store Codex 项目交接入口

> 文档编号：`QV-HANDOFF-APPSTORE-001`
>
> 更新日期：2026-08-06
>
> 适用版本：QuotaView `1.0.0 (Build 1)` / 内部代号 `v1.0.0a`

## 1. 新项目工作区

新 Codex 项目只打开以下独立 Git worktree：

```text
/Users/sukduoasa/Documents/QuotaView-AppStore
```

目标开发分支：

```text
codex/appstore-runtime-spike
```

该工作树与 GitHub 直接分发工作区共享同一个 `Duoasa/QuotaView` 仓库和 Git
历史，但拥有独立文件目录、分支、终端、构建产物和 Codex 上下文。不要复制
第二个 QuotaView 主应用仓库，也不要把原工作区中的未跟踪原型、参考资料或
图片带入新项目。

## 2. 新任务启动顺序

新 Codex 项目开始工作前，按顺序完整阅读：

1. `AGENTS.md`；
2. `HANDOFF.md`；
3. `VERSION_HISTORY.md#当前最新版本`；
4. `docs/specs/README.md`；
5. `docs/design/quotaview-app-store-release-1.0.0.md`；
6. `docs/design/quotaview-app-store-codex-account-runtime.md`；
7. 仅在处理灵动岛时阅读
   `docs/design/quotaview-app-store-codex-island-plugin-bridge.md`。

上述文档共同替代旧对话上下文。若文档与代码不一致，以 `AGENTS.md` 规定的
优先级审计，不得把计划状态写成已经交付。

## 3. 已交付到检查点的内容

- App 与 Widget 已映射为 `1.0.0 (Build 1)`，发行渠道为 `appstore`；
- 设置通用页仅显示从 Bundle 读取的当前版本，不含“检查更新”占位或自更新器；
- App Store 分支已移除额度重置入口、详情、确认、设置、Demo 执行器、Core
  映射、Widget 字段、Probe 输出与专用资源；
- 基础额度、Credits、Widget 与菜单栏被明确设计为不依赖灵动岛插件；
- OpenAI 账户方案已固化为包内固定 Runtime、Device Code、Keychain、独立
  Runtime Home 与严格 RPC 白名单；
- 灵动岛已固化为可选 Git Marketplace 插件桥接方案，未来可迁移公共目录。

交接前自动验证结果：

- `swift test`：53 项通过，0 失败；
- Universal Xcode Release 无签名构建：通过；
- App、Widget、Framework 与 Activity Helper：`arm64 + x86_64`；
- App 产物：`1.0.0 (Build 1)` / `appstore`；
- `AppIcon.icns` 与 `Assets.car`：存在；
- 视觉与交互验收：仍等待产品所有者运行确认。

## 4. 当前尚未解决的阻断

- `ENABLE_APP_SANDBOX` 仍为 `NO`，当前构建不能提交 App Review；
- 额度仍沿用外部 Codex 可执行文件定位和 App Server 启动链路；
- 旧灵动岛仍包含 Hook 安装、Helper、Terminal/Expect、本地 Socket 与外部
  Codex 控制链路；
- 包内 OpenAI Runtime、Device Code、Keychain 与 App Store Archive 尚未
  完成技术验证；
- Git Marketplace 灵动岛插件仓库尚未创建。

这些是后续工作的真实起点。不得因为规格已经接受就声称沙盒阻断已解决。

## 5. 新项目第一项任务

只执行账户 Runtime 规格的 `Phase 0：Runtime 技术 Spike`，暂不重写正式
Provider、登录 UI 或灵动岛：

1. 固定一个可审计的 OpenAI Codex 上游版本和许可证信息；
2. 验证能否构建 `arm64` 与 `x86_64` Runtime，并合成为 Universal；
3. 在最小沙盒宿主中验证 Runtime 可启动、继承沙盒并在 App 退出后回收；
4. 验证 ChatGPT Device Code 登录、Keychain 恢复、退出登录；
5. 验证 `account/rateLimits/read`，并对同一账号与现有基线额度做一致性比较；
6. 验证 App Store Archive 的签名、entitlement、包体与上游 License；
7. 输出 Spike 结论、失败证据、风险、Go/No-Go 与下一阶段拆分。

Spike 全部通过前，不删除当前基线 Provider，不开始正式登录 UI，不开启
生产 App Sandbox，也不宣称 App Store 阻断已经解除。

## 6. 可直接粘贴给新 Codex 项目的首条指令

```text
这是 QuotaView App Store 1.0.0 的独立开发项目。先完整阅读 AGENTS.md、
HANDOFF.md、VERSION_HISTORY.md#当前最新版本、docs/specs/README.md、
docs/design/quotaview-app-store-release-1.0.0.md 和
docs/design/quotaview-app-store-codex-account-runtime.md，建立真实上下文。
当前只执行 Account Runtime 规格 Phase 0 技术 Spike：先列验证矩阵和最小
改动边界，再进行实现与验证。不要开始正式 Provider/登录 UI 迁移，不要改动
0.3.1 Build 2 稳定发布事实，不要把基础额度依赖到灵动岛插件，也不要执行
发布、push 或 App Store 提交。完成后给出证据化的 Go/No-Go 结论。
```

## 7. 版本控制边界

- 当前工作分支只用于 Spike 与 App Store 适配；
- 不移动 `v0.3.1-build.2`，不覆盖 GitHub Release 或现有资产；
- 不创建 `appstore/main`，直到首个架构验证完成并由产品所有者确认；
- 不自动 push、建 PR、发布 tag 或提交 App Review；
- 共享修复必须记录来源提交和合并方向，禁止整仓覆盖；
- 灵动岛插件以后使用独立仓库，QuotaView 主应用仍保持单一主仓库。
