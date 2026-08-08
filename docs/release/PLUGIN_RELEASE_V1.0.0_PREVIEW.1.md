# QuotaView for Codex v1.0.0-preview.1 Release 记录与验收单

状态：`Published / Fresh Codex Environment Validation Pending`

## 固定身份

| 项目 | 当前值 |
|---|---|
| 仓库 | `https://github.com/Duoasa/QuotaView-for-Codex` |
| 默认分支 | `main` |
| tag | `v1.0.0-preview.1`（annotated） |
| tag object | `9bcd0a0303be09817802291faef7c7ed5f9314b3` |
| commit | `76262d40aded1e1c5f27168214762f41b382629f` |
| CI | branch push 与 tag push 均通过 |
| 匿名验证 | 固定 tag HTTPS clone、桥接测试、官方插件校验通过 |
| GitHub Release | `https://github.com/Duoasa/QuotaView-for-Codex/releases/tag/v1.0.0-preview.1` |
| Release 状态 | Public Pre-release；2026-08-06 13:03:46 UTC 发布 |

## 已生成的确定性资产

| 项目 | 当前值 |
|---|---|
| 文件名 | `QuotaView-for-Codex-v1.0.0-preview.1.tar.gz` |
| 当前本地路径 | `/private/tmp/QuotaView-for-Codex-v1.0.0-preview.1.tar.gz` |
| GitHub 下载地址 | `https://github.com/Duoasa/QuotaView-for-Codex/releases/download/v1.0.0-preview.1/QuotaView-for-Codex-v1.0.0-preview.1.tar.gz` |
| 大小 | `8,363 bytes` |
| SHA-256 | `ed03dbc8651e4dd73f8079216daf28365f8aa172a324de5f94ca02a1bd6afd55` |
| 内容 | 固定 tag 的源码、Marketplace、Plugin、Skill、Hooks、脚本、测试和文档；无预编译二进制 |

资产由以下命令从固定 tag 生成；连续生成两次的 SHA-256 一致：

```sh
git archive --format=tar.gz \
  --prefix=QuotaView-for-Codex-v1.0.0-preview.1/ \
  --output=/private/tmp/QuotaView-for-Codex-v1.0.0-preview.1.tar.gz \
  v1.0.0-preview.1
```

GitHub 自动生成的 Source code ZIP/tar.gz 不是上述自定义资产，不应混用其
校验值。

2026-08-06 已从 GitHub Release 回下载上述自定义资产，文件大小与 SHA-256
均与发布前固定值一致；在全新临时目录解包后，Marketplace、Plugin 与 Hooks
清单均通过校验，`tests/test-bridge.zsh` 通过，解包后的 `plugins` 内容与固定
tag 无差异。该验证不等同于修改当前用户 Codex 状态后的全新用户安装、Hook
信任、配对和真实事件端到端验证。

## 已发布的 Release 标题与正文

标题：`QuotaView for Codex 1.0.0 Preview 1`

```markdown
First public preview of the local-only Codex activity bridge for QuotaView.

## Included

- Public Codex Git Marketplace manifest and QuotaView plugin
- Setup and diagnostic Skill
- Sanitized lifecycle Hooks for SessionStart, SessionEnd, UserPromptSubmit,
  PreToolUse, PostToolUse, and Stop
- Atomic local bridge writer with bounded rotation
- Privacy, security, terms, uninstall, and troubleshooting documentation
- Automated bridge tests and plugin validation

## Privacy

The plugin makes no network requests. It writes only one-way session/turn
hashes, the final workspace folder name, a coarse tool category, lifecycle
event, timestamps, sequence, plugin version, and bridge health. It never writes
prompts, commands, full paths, file contents, tool payloads, model responses,
reasoning, account data, tokens, cookies, or credentials.

## Install

```sh
codex plugin marketplace add Duoasa/QuotaView-for-Codex --ref v1.0.0-preview.1
codex plugin add quotaview@quotaview-preview
```

Review and trust the Hooks in Codex, then use the starter prompt
"Connect the QuotaView Codex Island."

This is an independent preview plugin and is not an official OpenAI plugin.
```

## 发布前门禁

- [x] tag 与 commit 固定且公开可读；
- [x] branch/tag CI 通过；
- [x] 匿名固定 tag clone、测试和 validator 通过；
- [x] 自定义资产可重复生成，大小与 SHA-256 已记录；
- [x] 用户明确授权创建 GitHub Release；
- [x] 上传上述同一字节资产并核对 GitHub 下载后的 SHA-256；
- [x] 从 Release 资产全新解包并复验清单、桥接测试和固定 tag 内容；
- [ ] 从无本地 Marketplace/插件状态的新 Codex 环境安装；
- [ ] 完成 Hook 信任、配对、事件、诊断、卸载和重装验证；
- [ ] 验证完成后才把主 App 插件状态从 `public-tagged` 改为 `released`。
