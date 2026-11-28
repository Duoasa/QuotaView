# QuotaView 版本历史

本页索引已发布的版本。开发构建与待验收项见[开发交接](HANDOFF.md#工作区与版本定位)。各次发布的资产、签名、公证、回下载及撤回记录保存在[完整版本历史](docs/archive/2026-11-26/VERSION_HISTORY.md)。

## 当前最新版本

| 平台 | 稳定版 | 回滚入口 |
|---|---|---|
| macOS | [0.9.9 Build 2](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.9-build.2)，内部 284，2026-11-28 发布（UTC） | [0.9.9 Build 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.9-build.1)，内部 281 |
| Windows | [0.8.3-win.13](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-win.13)，使用独立签名 appcast | [Windows 首个正式版与回滚记录](docs/archive/2026-11-26/VERSION_HISTORY.md#windows-083-win首个正式版--windows-回滚基线) |

### macOS 0.9.9 Build 2

| 项目 | 发布证据 |
|---|---|
| 版本 | [0.9.9 Build 2](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.9-build.2)，内部 284，2026-11-28 发布（UTC） |
| 源码 | `v0.9.9-build.2`，提交 `90193c8581f1d4ca8e84d6c39089c1daec239736`，[发布 PR](https://github.com/Duoasa/QuotaView/pull/161)。324 个冻结构建输入均与标签一致。合并提交 `30c1a7ce55fc23354392500330feeb21f1919f5f` 的 [main CI](https://github.com/Duoasa/QuotaView/actions/runs/46126079874) 通过 |
| 资产 | [QuotaView-v0.9.9-build.2.zip](https://github.com/Duoasa/QuotaView/releases/download/v0.9.9-build.2/QuotaView-v0.9.9-build.2.zip)，34,538,949 字节，SHA-256 `4d97029ec21d65e51da4d5b68101b6c1558ad3dc9058b5841aeaa0b7ab9dc8e9`，公开回下载逐字节一致 |
| 验证 | XCTest 899 项，888 项通过，11 项按条件跳过，0 项失败。44 项问答契约通过。[PR CI](https://github.com/Duoasa/QuotaView/actions/runs/46124470892) |
| 兼容性 | macOS 14+。App、Widget、Core、Hook 和 Sparkle 均包含 Intel 与 Apple 芯片架构。解压包隔离启动 15 秒，已核对实际加载路径 |
| 签名与公证 | Developer ID Application: Chenchen Xu (BUUH229D5Q)。Apple Accepted，公证 ID `7ee99f51-435b-4a66-8f22-ed52d2fb185f`。公开包通过签名、Staple、Gatekeeper 和 EdDSA 检查 |
| 更新渠道 | GitHub 与 [Sparkle](https://duoasa.github.io/QuotaView/appcast.xml) 已发布。更新序列为 284 / 281 / 238。正式 Build 1 的 Sparkle 查询选中 284，Build 2 查询返回已是最新版。两次查询均使用隔离副本 |
| 更新源验证 | 线上 Feed 与其指向的 ZIP 均通过 Build 1 和 Build 2 的内置公钥验签。Feed SHA-256 `b84c8eb142185740c622852742d1a7d30408d112e8c56c2f3ea2ebbb3f84dede`，[Pages 部署](https://github.com/Duoasa/QuotaView/actions/runs/46126640555)，提交 `13338bc6ccdefed75f94a13f2d8c5461ffd1f0ce` |
| ZIP EdDSA | `BSZnhcganMEhJByY3j+j8l7jACmcavTOAnnz+uGtU0lT5bIQR5GBrQBWW5G0xIDEpZArCX34wCAWfvwH993RDw==` |
| 回滚 | [0.9.9 Build 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.9-build.1)，内部 281，标签 `v0.9.9-build.1`，发布提交 `b0afb04f4cdb4b6621f6c962a68ce9afd2f9983f`。原 ZIP 已再次回下载核对 |

### macOS 0.9.9 Build 1

| 项目 | 发布证据 |
|---|---|
| 版本 | 0.9.9 Build 1（内部 281），[GitHub Stable Release](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.9-build.1) |
| 源码 | `v0.9.9-build.1`，发布提交 `b0afb04f4cdb4b6621f6c962a68ce9afd2f9983f`，[PR #158](https://github.com/Duoasa/QuotaView/pull/158)；322 个冻结构建输入已核对 |
| 资产 | [QuotaView-v0.9.9-build.1.zip](https://github.com/Duoasa/QuotaView/releases/download/v0.9.9-build.1/QuotaView-v0.9.9-build.1.zip)，34,493,734 字节，SHA-256 `694a215b967a5f065855e8cddb5f545260cbb4636cfeaec7a72e584ce861fdb0`；公开回下载逐字节一致 |
| 兼容性 | macOS 14+，App、Widget、Core、Hook、Sparkle 均为 arm64 和 x86_64。隔离启动 15 秒并核对解压包的动态库路径 |
| 签名与公证 | Developer ID Application: Chenchen Xu (BUUH229D5Q)；Apple Accepted，公证 ID `667f8f4d-99ba-4d8a-8e0c-cb42819a4d89`。本地与回下载包的签名、公证票据和 Gatekeeper 检查通过 |
| 验证 | 隔离 XCTest 共 896 项，跳过 11，失败 0；44 项问答契约通过。[PR CI](https://github.com/Duoasa/QuotaView/actions/runs/46004893009)、[发布 main CI](https://github.com/Duoasa/QuotaView/actions/runs/46005533474) 通过 |
| 自动更新 | [线上签名 appcast](https://duoasa.github.io/QuotaView/appcast.xml)，序列 281 / 238 / 189。ZIP 和线上 Feed 均通过 EdDSA 验签。[Pages 部署](https://github.com/Duoasa/QuotaView/actions/runs/46006673608)，提交 `cbf59fd7da2a097f80ae4cdf3ceb713dfc7ff410` |
| Feed SHA-256 | `3e5546310a13ec2912f0d77b0b8f0118881e54d7380373f1565c477b69396c7a` |
| ZIP EdDSA | `u3uwreHrH73szHrmqaCZKQimAW2i7nR0bRzH+BKqRKKqwmMwKRbgDrccgurEYxSuvjOBqEpDCMKECQ4WUYZlCw==` |
| 回滚 | [0.9.7 Build 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.7-build.1)，内部 238，标签 `v0.9.7-build.1`。本次再次回下载并核对原 ZIP 的 SHA-256 |

### macOS 0.9.7 Build 1


发布标签 `v0.9.7-build.1`，提交 `8109feb4dffaf6087692aa77e8ff412adcc7892e`，ZIP 的 SHA-256 为 `8d16a373952774a9b205b24b5c460e167d22c9f4c57ee0adfbce94d04988cb91`。发布时已核验公证、Universal 架构、解压启动与公开下载。[完整发布证据](docs/archive/2026-11-26/VERSION_HISTORY.md#macos-097-build-1)

<a id="macos-093-build-1上一-macos-稳定版--回滚基线"></a>

### macOS 0.9.3 Build 1（历史版本）

发布标签 `v0.9.3-build.1`，提交 `f0ee1ceb4372ba1b4a9e1df3b38f842a17d37985`。作为 0.9.7 的回滚版本，其公开 ZIP 已回下载并核对原始摘要。[回滚版本证据](docs/archive/2026-11-26/VERSION_HISTORY.md#macos-093-build-1上一-macos-稳定版--回滚基线)

### Windows 0.8.3-win.13

Windows 版本沿用独立渠道。归档保存其发布资产、签名及当时的 Windows CI 记录。[Windows 发布证据](docs/archive/2026-11-26/VERSION_HISTORY.md#windows-083-win13)

## 历史规格引用

- <a id="041-build-1"></a>[0.4.1 Build 1](docs/archive/2026-11-26/VERSION_HISTORY.md#041-build-1)
- <a id="037-build-1"></a>[0.3.7 Build 1](docs/archive/2026-11-26/VERSION_HISTORY.md#037-build-1)
- <a id="036-build-2"></a>[0.3.6 Build 2](docs/archive/2026-11-26/VERSION_HISTORY.md#036-build-2)
- <a id="035-build-5"></a>[0.3.5 Build 5](docs/archive/2026-11-26/VERSION_HISTORY.md#035-build-5)
- <a id="032-build-1-preview-1"></a>[0.3.2 Build 1 Preview 1](docs/archive/2026-11-26/VERSION_HISTORY.md#032-build-1-preview-1)
- <a id="031-build-2"></a>[0.3.1 Build 2](docs/archive/2026-11-26/VERSION_HISTORY.md#031-build-2)
