# QuotaView for Codex v1.0.0-preview.2 发布候选记录

状态：`Local Candidate / Uncommitted / Unreleased / Clean-User Validation Pending`

本文件只记录下一版插件候选，不改变已经公开发布的
`v1.0.0-preview.1`，也不表示已经创建 commit、tag、GitHub Release 或提交
App Review。

## 候选身份

| 项目 | 当前值 |
|---|---|
| 仓库 | `https://github.com/Duoasa/QuotaView-for-Codex` |
| 本地工作区 | `/Users/sukduoasa/Documents/QuotaView-for-Codex` |
| 分支 | `main` |
| 基础提交 | `76262d40aded1e1c5f27168214762f41b382629f`（`v1.0.0-preview.1`） |
| 候选版本 | `1.0.0-preview.2` |
| 候选提交 | 尚未创建 |
| 候选 tag | 尚未创建；不得移动或覆盖 `v1.0.0-preview.1` |
| GitHub Release | 尚未创建 |

## 变更范围

- Hook、桥接脚本与 Setup Skill 优先使用当前 Codex 插件环境变量
  `PLUGIN_ROOT` 和 `PLUGIN_DATA`；
- 继续兼容 `CODEX_PLUGIN_ROOT`、`CODEX_PLUGIN_DATA`、
  `CLAUDE_PLUGIN_ROOT` 和 `CLAUDE_PLUGIN_DATA`，但官方变量具有更高优先级；
- 插件 manifest 不声明显式 `hooks` 字段，继续使用默认
  `hooks/hooks.json` 自动发现，以满足当前插件 ingestion validator；
- 桥接测试新增官方变量优先级与兼容变量回退覆盖；
- 插件仓库新增固定 Git tag 的确定性资产构建/解包复验脚本，以及隔离
  `CODEX_HOME` 的首次安装、卸载、重装和缓存一致性脚本；
- 新增 tag/手动调度 CI，只上传验证后的临时 workflow artifact，不自动创建、
  修改或发布 GitHub Release；
- 插件继续只写本地脱敏事件，不增加网络请求、提示词、命令、完整路径、
  Token、Cookie 或账号数据采集。

上述变量与 Hook 信任边界已按当前 OpenAI Codex 插件手册的
[Hooks](https://learn.chatgpt.com/docs/hooks) 与插件构建说明核对。非托管 Hook
仍必须由用户在 Codex 中审阅并信任，信任记录与具体 Hook 内容哈希绑定。

## 本地验证

- [x] `.codex-plugin/plugin.json`、`hooks/hooks.json` 与 Marketplace JSON
  可被 `python3 -m json.tool` 解析；
- [x] Codex `plugin-creator` ingestion validator 通过；
- [x] `quotaview-setup` Skill quick validator 通过；
- [x] `zsh tests/test-bridge.zsh` 通过；
- [x] 桥接脚本与测试脚本 `zsh -n` 通过；
- [x] `git diff --check` 通过；
- [x] 使用 Codex CLI `0.147.0-alpha.1.2` 从已配置的本地
  `quotaview-preview` Marketplace 将安装缓存从 `preview.1` 更新为
  `preview.2`，缓存内容与候选源目录逐文件一致；
- [x] 在两个新的 ephemeral Codex CLI 进程中，以只读沙盒和已审计 Hook
  自动化信任旁路运行真实会话；宿主注入官方 `PLUGIN_ROOT` / `PLUGIN_DATA`
  后，首个会话写入 `SessionStart`、`UserPromptSubmit`、`Stop`、
  `SessionEnd`，第二个会话实际执行一次只读 shell 工具并写入
  `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`Stop`、
  `SessionEnd`，共 10 项连续事件；两项工具事件均归类为 `shell`；
- [x] 真实数据目录权限为 `0700`、文件为 `0600`，敏感字段名扫描无命中；
- [x] 新增 `scripts/check-codex-plugin-e2e.sh`，上述 10 项真实事件通过
  QuotaView 生产目录安全检查、manifest/status 校验、严格 Swift 解码、序列
  游标和完整事件顺序验证，0 个 malformed event；脚本对用户显式指定的外部
  `PLUGIN_DATA` 使用 `swift test --disable-sandbox`，修复嵌套 SwiftPM sandbox
  在受控构建环境中的启动失败，并已对现有 `preview.2` 数据再次通过；
- [x] 在全新的隔离 Codex 配置目录中，从零添加本地候选 Marketplace，完成
  首次安装、启用、卸载和重装；重装缓存与候选源目录逐文件一致，不依赖当前
  用户已有 Marketplace、插件缓存或安装状态；
- [x] 上述隔离安装流程已固化为 `scripts/check-clean-install.zsh` 并再次通过；
  临时 `CODEX_HOME` 在脚本退出时清理，不读写当前用户插件、信任或数据；
- [x] `scripts/build-release-asset.zsh` 已使用公开固定
  `v1.0.0-preview.1` 回归：连续两次归档字节一致，解包后 JSON、必需文件、
  executable bit、无本地数据/符号链接及桥接测试通过，重新得到
  `8,363 bytes` 和 SHA-256
  `ed03dbc8651e4dd73f8079216daf28365f8aa172a324de5f94ca02a1bd6afd55`，与已
  发布记录完全一致；
- [x] 新增 `.github/workflows/release-asset.yml`；只接受现存 annotated tag，
  tag 必须与 manifest 版本一致，构建验证后仅上传 30 天 CI artifact；workflow
  YAML 解析、Shell 语法和 `git diff --check` 通过；
- [x] `plugin-creator` ingestion validator 与 `quotaview-setup` Skill validator
  在新增发布工具后再次通过；
- [ ] 由用户在非旁路流程中完成 Hook 审阅与信任，以及 QuotaView 系统目录
  选择器配对和灵动岛视觉验证；
- [ ] 候选发布固定 tag 后，在干净用户环境完成公开 Git Marketplace 安装与
  固定 tag 升级验证。

## 拟发布标题与正文

以下英文单源文案只作为待确认的 GitHub Pre-release 草案。安装命令中的
`v1.0.0-preview.2` 只有在新 tag、CI 和回下载复验全部通过后才可公开执行；
当前公开 README 继续固定到已经发布的 `v1.0.0-preview.1`。

拟发布标题：`QuotaView for Codex 1.0.0 Preview 2`

````markdown
Preview 2 is a compatibility and release-safety update for the QuotaView Codex
activity bridge.

### What's changed

- Prefer the current Codex plugin environment variables `PLUGIN_ROOT` and
  `PLUGIN_DATA`.
- Keep compatibility fallbacks for `CODEX_PLUGIN_ROOT`, `CODEX_PLUGIN_DATA`,
  `CLAUDE_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_DATA`.
- Validate lifecycle and tool activity Hooks against a real Codex host.
- Add deterministic tagged-source packaging and isolated
  install/uninstall/reinstall checks.

The privacy boundary is unchanged: the plugin writes a bounded local stream of
sanitized activity events. It does not collect prompt text, command text, model
output, reasoning, complete paths, files, tool payloads, account data, tokens,
cookies, or credentials, and it makes no network requests.

### Install

```sh
codex plugin marketplace add Duoasa/QuotaView-for-Codex --ref v1.0.0-preview.2
codex plugin add quotaview@quotaview-preview
```

Review and trust the plugin Hooks in Codex, then use “Connect the QuotaView
Codex Island.” QuotaView will ask you to select the plugin data folder using the
macOS system folder picker.

This is a Preview release and is not an OpenAI official plugin. It does not
change Codex approvals, Hook trust, or sandboxing. Rendering the Codex Island
requires the paid QuotaView app from the Mac App Store; every bundled QuotaView
feature is included after download. The public plugin itself contains no
license check or payment flow.
````

## 发布门禁

- [ ] 用户确认允许提交并发布插件候选；
- [x] 确定性资产、隔离安装和 tag CI 工具链准备完成；
- [ ] 创建独立 commit；
- [ ] 推送 `main`，等待 branch CI 通过；
- [ ] 创建新的 annotated tag `v1.0.0-preview.2`，不得改写旧 tag；
- [ ] 等待 tag CI 通过并完成匿名 HTTPS 固定 tag clone；
- [ ] 从固定 tag 生成确定性资产，记录大小与 SHA-256；
- [ ] 创建新的 GitHub Pre-release 并回下载复验；
- [ ] 全新 Codex 环境端到端验证完成后，才更新 App Review Notes 的固定 tag；
- [ ] 只有上述验证全部完成，主 App 插件状态才可从 `public-tagged` 改为
  `released`。
