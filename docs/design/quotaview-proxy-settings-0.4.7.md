# 0.4.7 自定义代理

Spec ID: `QV-PRODUCT-PROXY-017`  
状态：Accepted / Withdrawn；2026-09-10 用户反馈显示 bug，已撤回稳定发布，Latest / README / appcast 恢复 0.4.6 Build 2。根因待排查；下文为原实现与发布历史。
已撤回身份：0.4.7 Build 2 / internal 21；Preview 1 / internal 20 保留为历史。
完整发布证据见 [版本历史](../../VERSION_HISTORY.md#当前最新版本)。

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
- Preview 阶段不加入 appcast；2026-09-10 用户明确授权正式 Build 2、main、README 与 appcast。用户代理反馈可用，完整视觉/辅助功能验收仍待完成。

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


## 正式发布验证（2026-09-10）

0.4.7 Build 2 / internal 21 已合并 main 并正式发布。完整本地 190 项通过（0 跳过）；
main CI 190 项、0 失败、2 个可选测试跳过，本机已运行对应真实 CLI 和真实 120 秒测试。
15 项完成收起专项审查未复现永久停留，未更改生产计时；窗口层为代码审查，未自动 UI 验收。
正式包完成 Universal、签名、公证/Staple、公开回下载、Gatekeeper 与内置公钥 Feed/ZIP 验证。
发行包以 `dist/QuotaView-v0.4.7-build.2.zip` 为准；上述 9 月 8 日记录为 Preview 阶段事实。

## 2026-09-11 设置视觉修正

复用 R6；用户要求代理协议选项与其他行的右侧控件对齐，并参考所附 macOS
系统设置截图，为设置侧栏更换彩色圆角矩形图标。协议菜单保留原生 Picker，
其 160 pt 控件区域改为靠右放置，保持设置行统一 18 pt 右边距；HTTP / SOCKS5
选项及禁用逻辑不变。七个侧栏图标使用 20 pt 圆角底和白色 SF Symbols，
按页面用途配置系统蓝、紫、灰及外观深色底；保留原生 List 的选中、键盘及
本地化文字，图标作为装饰不重复播报。无新增业务模块或代理行为变化。

验收条件：默认/最小窗口宽度、中英文、启用/禁用代理、选中/未选中侧栏、
深浅色及 Increase Contrast 保持布局与可读性。新增视觉效果等待用户确认。

本轮验证：197 项 Swift 测试，0 失败、2 项可选跳过；Universal Release 构建通过，
版本为 0.4.7 Build 3 / internal 22，App、Core 和 Widget 双架构及图标资源已检查。
未新增生产调试入口；`git diff --check` 通过。

## 2026-09-11 Build 3 release authorization

After opening Build 3, the owner explicitly requested main, GitHub, README
and appcast publication for `v0.4.7-build.3` / internal 22. Complete artifact
verification before publication; move withdrawn Build 2 to draft only after
Build 3 is verified live, retaining the old tag and asset for investigation.
