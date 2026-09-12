# QuotaView 发布与回滚规则

仅在版本身份、打包、签名、公证、发布、自动更新准入或撤回任务中读取。
以下规则从原 AGENTS.md 迁入，保留逐版本授权和不可变资产约束。
已有会话授权在同一范围内继续有效；规则本身不授权任何发布或凭据操作。
准备和只读核验可以持续完成，需要授权的操作以当前会话及工具权限为准。

发布事实：[版本历史](../../VERSION_HISTORY.md#当前最新版本)。
开发最新版及待验收项：[Handoff](../../HANDOFF.md)。
产物检查：[验证规则](VALIDATION.md#发布与产物)。

## 版本身份与文档联动

版本与交接文档必须双向联动，但不得复制整段历史：

- `HANDOFF.md` 顶部必须直接链接
  `VERSION_HISTORY.md#当前最新版本`；
- `VERSION_HISTORY.md` 必须回链 `HANDOFF.md`；
- 每次发布、撤回版本、删除 tag 或改变 GitHub Latest 时，必须在
  `VERSION_HISTORY.md` 记录完整不可变证据，并在 `HANDOFF.md` 更新当前
  版本指针、回滚入口和对当前开发的影响；
- 每次改变当前迭代、规格状态或交付状态时，必须同步更新
  `docs/specs/README.md` 与 `HANDOFF.md`；
- 完整的版本、Build、tag、发布提交、Release URL、资产名、大小、SHA-256、
  签名、公证、验证和替代版本只在 `VERSION_HISTORY.md` 保存；Handoff 只保留
  当前稳定版的最小定位信息和活跃迭代所需的增量事实；
- README 下载链接与 GitHub Release Notes 也必须同时核对；
- GitHub Release Notes 使用单份英文源文，由 GitHub 界面负责翻译，避免
  手写中英文正文被重复显示；
- 删除 Release 后仍在 `VERSION_HISTORY.md` 保留“已撤回”记录，说明原因
  和替代版本，防止后续恢复问题版本；
- 产品可见 Build Number 按 Marketing Version 独立计数：Marketing Version
  变化时重置为 `Build 1`；Marketing Version 不变时，每次后续开发迭代都
  必须递增，不得复用旧 Build Number。每个构建使用唯一 tag 和带 Build
  Number 的 ZIP；Marketing Version 是否升级由用户明确决定。
- Sparkle 使用的 `CFBundleVersion` / `CURRENT_PROJECT_VERSION` 是机器可读的
  内部更新序号，必须跨 Marketing Version 单调递增，不能随产品可见 Build
  归 1。产品可见 Build 使用 `QuotaViewDisplayBuildNumber` /
  `QUOTAVIEW_DISPLAY_BUILD_NUMBER`；设置界面、tag、ZIP、Handoff 与版本历史
  均使用产品可见 Build。App、Widget 和兼容 `Info.plist` 中的 Marketing
  Version、内部更新序号与产品 Build 必须在同一任务内同步。

出现版本信息冲突时：

1. 先以用户当前指令和生产代码中的 `CFBundleShortVersionString`、
   `QuotaViewDisplayBuildNumber` 与 `CFBundleVersion` 为准；
2. 通过 GitHub Release/tag 和最终发布提交核实已经发生的发布事实；
3. 在同一任务内修正 `VERSION_HISTORY.md` 与 `HANDOFF.md`；
4. 不得把计划、候选包或尚未完成的 Release 写成已经发布；
5. 不得把已撤回的 `0.2.0 Build 3` 重新作为开发或下载基线。

### 应用内自动更新序列准入门禁

GitHub 版本发布与 Sparkle 自动更新序列是两个独立动作。产品所有者对每个
版本保留单独的自动更新准入决定权，长期采用显式加入（opt-in）规则：

1. 产品所有者针对某个精确版本明确表示“纳入自动更新序列”或“发布到
   appcast”，即同时授权并触发该版本的完整发布链路：合并生产代码、正式
   Developer ID 签名、Apple 公证/Staple、不可变 GitHub Stable Release、
   回下载验证、签名 appcast 部署和发布文档联动；不得在合并 `main` 后停下
   等待第二次“可以发布”确认；
2. 推送代码、创建 tag、创建 GitHub Release、设为 Stable/Latest、上传正式
   ZIP 或一般性的“可以发布”，均不得自动推导为已获 appcast 准入；
3. 未获得明确准入的版本默认排除在自动更新序列之外。允许为工程验证生成
   本地 appcast Fixture，但不得上传、部署或覆盖公开 appcast；
4. 准入授权必须绑定精确的 Marketing Version、Build Number 和预期 tag / ZIP
   身份；完成门禁后把最终资产大小、SHA-256、签名和公证结果回填文档。更换
   Build、tag、资产名或在最终验证后重新打包必须重新确认；
5. 自动更新序列可以跳过中间 GitHub Release。后续获准且内部更新序号更高
   的版本可直接作为现有客户端的下一更新目标，无需补录未获准版本；产品
   可见 Build 只用于版本身份，不参与 Sparkle 新旧判断；
6. 在 `HANDOFF.md` 和当前更新规格中记录每个候选版本的准入状态。没有记录
   或记录为“未批准”时，一律按未获准处理；
7. 发布公开 appcast 前必须核对产品所有者授权、不可变 Release 资产、
   SHA-256、Developer ID、公证/Staple、EdDSA 和回下载验证；
8. 已发布到 appcast 后如需撤回，必须由产品所有者明确授权，并同步处理
   appcast、GitHub Release/Latest、`HANDOFF.md` 与 `VERSION_HISTORY.md`，
   不得仅删除本地文件或静默覆盖 Feed。

### 稳定版本封存与回滚基线

每次准备发布新的稳定版、Preview、Beta 或 RC 前，必须先封存当时最新的
稳定版本，作为整个新版本周期的回滚基线。封存必须使用 Git 与已经验证的
发布资产，不在仓库中复制一份容易漂移的源码目录。

封存门禁如下：

1. 确认上一稳定版具有唯一且不可移动的发布 tag，并记录 tag、完整提交
   SHA、Release URL、资产名、大小和 SHA-256；
2. 确认对应资产已经完成该稳定版要求的签名、公证、Staple、Gatekeeper、
   架构和真实启动验证；
3. 在 `VERSION_HISTORY.md#当前最新版本` 保存完整回滚资产事实，在
   `HANDOFF.md` 保留当前回滚 tag / commit 的最小入口；
4. 新预发布版本不得移动、覆盖或删除该稳定 tag，不得覆盖原 Release 资产；
   修复必须使用新提交、新 Build、唯一 tag 和新资产；
5. Preview、Beta 或 RC 默认不得取代稳定版的 GitHub Latest 与 README 默认
   下载入口，除非用户明确要求改变稳定渠道；
6. 新版本晋升为稳定版后，它才成为下一版本周期的稳定回滚基线；此前的
   基线继续保留在版本历史中，不删除；
7. 回滚时从已封存 tag 或已核验资产恢复，不从开发分支、未提交工作区、
   Prototype 或候选包推断稳定代码。

当前回滚基线不得在本长期规范中硬编码；以
`VERSION_HISTORY.md#当前最新版本` 为唯一事实源。Preview、Beta 或 RC 不得
自动成为稳定回滚基线。
