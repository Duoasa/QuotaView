# 0.4.7 自定义代理

Spec ID: `QV-PRODUCT-PROXY-017`  
状态：Accepted / Released（仅 Preview）；2026-09-08 用户授权沿用 0.4.6 架构实现并发布预览。
预览身份：0.4.7 Preview 1 / Build 1 / internal 20；基线：0.4.6 Build 2 / internal 19。

## 范围与 Requirement

- R1：设置增加代理页面，默认关闭。HTTP / SOCKS5，服务器地址与端口；不支持账号密码、PAC、订阅、代理内核或系统代理修改。
- R2：编辑为草稿，保存后生效。拒绝凭据、路径、查询、非法主机和不在 1–65535 的端口。恢复默认关闭自定义代理并恢复初始字段和原有连接行为。
- R3：代理只传给 QuotaView 自己管理的额度查询 Codex 子进程，包含额度和账户 Token 历史。灵动岛本地记录、共享活动通道、用户独立 Codex、更新器和系统设置不改变。
- R4：连接测试以相同客户端配置查询并校验真实额度响应；独立测试客户端不发布业务快照。编辑、取消、恢复默认使旧测试结果失效。失败不得伪造成功或零额度。
- R5：配置保存后替换查询协调器和客户端，取消旧请求；配置修订守卫阻止旧结果回写。关闭代理保留 0.4.6 原有继承环境行为，不承诺强制直连。
- R6：中英文、系统原生设置组件、键盘和辅助功能；视觉与交互由用户验收。

## 架构与状态

`AppPreferences → CodexStatusStore → RefreshCoordinator → CodexProviderAdapter → CodexAppServerClient → 自有子进程`。
代理配置为一次保存的不可分割值，子进程环境在客户端创建时固定。HTTP 启用后覆盖大小写 HTTP_PROXY / HTTPS_PROXY / ALL_PROXY，使用固定的本机绕过列表，避免旧环境代理冲突。SOCKS5 使用 `SOCKS5HTTPBridge`：仅监听 `127.0.0.1` 临时端口，将 HTTP CONNECT 或 HTTP 请求转换为 SOCKS5 无认证握手，再双向转发；目标域名交由代理解析。向 Codex 子进程传入的是本机转接层的 HTTP 地址。关闭后不修改继承环境。

桥接层最多 16 个连接，HTTP 头最多 64 KiB，每次转发最多 32 KiB；监听启动 5 秒超时、握手 10 秒超时、空闲 60 秒关闭。配置替换、取消或客户端停止时关闭监听和连接。HTTPS 保持端到端 TLS，不解密、不关闭证书验证；不记录请求头或正文。

连接测试：idle → testing → success / failed；编辑或取消返回 idle。错误展示固定的本地化分类，不展示子进程原始 stderr、凭据或账户内容。测试只请求额度，不消耗重置次数。

## 验证

- 配置验证、保存与恢复、默认兼容、环境传递、过期结果丢弃。
- 模拟 HTTP 与 SOCKS5 服务验证请求确实穿过代理；成功、拒绝、超时、断开、恢复和切换。
- 实际安装 Codex CLI 配合隔离临时配置和虚拟身份的网络验证；不读取或修改用户 auth.json/config.toml。
- swift test；Universal Xcode Release 无签名构建；版本、架构、图标和资源；git diff --check；临时生产注入检查。
- 用户已授权发布 GitHub Preview，标签 v0.4.7-preview.1；不加入 appcast，不替换稳定 Latest。用户验收及真实代理反馈待完成。

## 实现依据

按用户决定独立扩展 0.4.6 的现有架构。CodexBar 比较已完成，不引入其代码或依赖。当前 Codex CLI 0.153.4 的模拟测试表明：仅传入 socks5h 环境变量时未出现 SOCKS5 握手，混合协议 fixture 仍收到了 HTTP 请求，因此不能把返回额度当作 SOCKS5 支持的证据。新增本机转接层后，用握手记录及有效额度响应共同证明代理生效。并未采用猜测的共享 daemon 配置或复制用户凭据。

## 验证结果（2026-09-08）

| 检查 | 结论 |
|---|---|
| 全套 Swift 测试 | 186 项通过，0 失败；包含原有 177 项与新增 9 项；真实 CLI 测试显式启用，未跳过 |
| HTTP / SOCKS5 | 实际网络穿过两种模拟代理；额度响应正确；SOCKS5 记录到真实无认证握手与代理端域名 |
| 实际安装 Codex CLI | 0.153.4；独立临时 HOME/CODEX_HOME 与虚拟账户，两种代理均通过 HTTPS 取得有效额度；仅测试进程信任临时 CA，系统信任未修改 |
| 异常与恢复 | 两种协议的断开、认证要求、403、超时；不可用端口；恢复成功；保存和恢复默认后的业务客户端重建与旧结果丢弃 |
| 连接测试生命周期 | 只发布测试状态，不发布业务快照；无效响应被拒绝；取消后不回写旧成功；SOCKS5 转接层同步生命周期 |
| 资源边界 | 超大请求头被关闭；停止后监听端口无法再连接；无临时生产 mock、截图、自动展开或点击入口 |
| Universal Release | 无签名构建通过；App / Widget 均为 0.4.7 / 产品 Build 1 / internal 20；App、Widget、Hook 均含 x86_64 与 arm64 |
| 打包资源 | AppIcon.icns、App/Widget Assets.car、Widget、Hook 完整；git diff --check 通过 |
| 预览发布 | [v0.4.7-preview.1](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.7-preview.1) / 75982b6；Developer ID、Apple Accepted / Staple；公开下载逐字节一致，签名、票据和 Gatekeeper 通过；Latest / appcast 保持 0.4.6 Build 2 |
| 人工验收 | 等待用户确认页面、交互、中英文、辅助功能及其真实代理环境；模拟测试不代表已覆盖所有代理服务实现 |

发布包：`dist/QuotaView-v0.4.7-preview.1.zip`；不可变发布事实见 [版本历史](../../VERSION_HISTORY.md#当前最新版本)。
开发产物：`dist/QuotaView.app`（用户当前运行实例保持原状）；分发验收以公证 ZIP 为准。完整日志：`dist/verification/swift-tests.log`、`dist/verification/universal-build.log`（本地产物，不进入 Git）。

复现测试：

```sh
QUOTAVIEW_RUN_CODEX_PROXY_TESTS=1 swift test
```

真实 CLI 测试要求机器已安装 Codex；普通 CI 未显式启用时仅跳过该项，其他模拟网络测试仍运行。模拟服务仅绑定本机、只接受 fixture 域名、不向外网转发。

本轮测试夹具曾因 Foundation 的同步 waitUntilExit 在异步测试线程阻塞，已移除该同步等待；此问题不属于生产代理代码。HTTPS 夹具使用独立 CA 与服务器叶证书，保留正常证书链校验。

