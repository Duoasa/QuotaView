# QuotaView 35 项审计修复 · 2026-10-06

文档编号：`QV-FIX-AUDIT-20261006-001` · 状态：`Accepted / Verifying`

## 范围与基线

按原始 `QuotaView_Audit_AI_Playbook_2026-10-05.md` 的35个ID实施；保留原风险分类，
不把性能热点、条件性风险或合成反例都称为实机故障。报告为117036字节、1523行，
SHA-256 `eb2f1fc5265af32e06397c78b5e31c266496355cc3d790886e37f24b79559dcd`；
源码基线 `db3aca3623bcf0313a987679c4972f857853ce23`。

本轮授权包含定向反例、隔离基准/冒烟、共享树整合验证、最小开发编译与运行，以及当前任务的
源码推送/合并与对应CI。公开稳定版仍为0.7.7 Build1/内部57；本轮沿用其开发身份，
不发布新资产或appcast。用户未提交Handoff/Prototype、正式安装与账户数据保留。

本轮约束：普通确认只有原生owner/epoch/nonce能力证明后可应答；partial items 缺席不代表
异步问题已结束；未知flags不是running；SessionEnd不是成功100%；显示截断不改变
原始审批载荷。macOS系统权限仍由系统弹窗处理，未扩大权限或代答。

## 逐项实施与证据

以下“通过”仅指列出的定向或隔离检查。最终共享树、运行包、GitHub提交另节记录；
真实视觉/交互与未运行平台场景按“边界”保留。

| ID | 原文行 | 负责 | 修改 | 证据 | 边界 |
|---|---:|---|---|---|---|
| QV-AUD-001 | 133 | 整合 | Store 的 resolved projection 直接接入生产 LiveStore；SessionEnd、goal 与来源失效不再二次猜测 | AuditUIProjectionTests | 来源恢复、真实生命周期与空计划；真实展示由用户验收 |
| QV-AUD-002 | 177 | B | 无 turn 的 SessionEnd 按当前轮时间与身份准入，拒绝旧轮迟到结束 | AuditLifecycleSessionEndTests | 协议没有 process incarnation；没有虚构进程身份 |
| QV-AUD-003 | 210 | 整合 | 应答相关内容修订生成新 UUID 并清草稿；纯能力升级保留 UUID 与草稿 | AuditUIRequestLifecycleTests / DesktopRequestLifecycleSmokeTests | owner/epoch/nonce 仍独立校验，旧提交不得写入新修订 |
| QV-AUD-004 | 245 | 整合 | 选择绑定请求 UUID，删除前置请求不移走当前编辑项 | AuditUIRequestLifecycleTests | 被选请求消失时才选择邻项 |
| QV-AUD-005 | 277 | A | 共享 single-flight 初始化与 generation 清理，单调用取消不停止其他调用 | AuditTransportLifecycleTests | 取消调用在共享初始化结束后返回；未验证真实账户并发频率 |
| QV-AUD-006 | 309 | B | await stop 后重新核对 generation、stopped、enabled、需求与 publication ownership | AuditRefreshTransitionGateTests | 生产交错频率未测 |
| QV-AUD-007 | 341 | A | foreign owner 广播先验证发现与新 follow，不提前撤销健康账本 | AuditTransportDesktopTests | 真实 Desktop 替换时序待平台验收 |
| QV-AUD-008 | 373 | 整合 | entry/context 共用有界计账；换轮/关闭/reset释放；pending 自持原始请求上下文 | AuditUIContentBudgetTests / AuditUIAccountingBenchTests | 2 MiB 是保留公开内容预算，不是进程 RSS 上限 |
| QV-AUD-009 | 408 | 整合 | 65,536 Character 实际截断与 sourceTruncated 标记一致 | AuditUIContentBudgetTests | 原始应答/审批数据不按显示正文截断 |
| QV-AUD-010 | 439 | A | 单 permit、64 KiB reader、消费 ACK 与内核背压限制输入队列 | AuditTransportLifecycleTests | 短合成 RSS 样本不证明进程级内存上限；超时会明确断开 |
| QV-AUD-011 | 471 | 整合 | 相同显示直接返回，变化比较使用一次 ID 字典，保留独立展示时钟 | AuditUIBoardUpdateTests / IslandBoardNavigationTests | 128/1000/4096 卡测量不是帧率或视觉验收 |
| QV-AUD-012 | 503 | A | WebSocket cursor + threshold compaction，只复制目标 payload | AuditTransportWebSocketTests | 确定性复制计数，不声称实际 UI 延迟收益 |
| QV-AUD-013 | 533 | A | ledger 缓存历史/当前项索引；presentation-only patch 复用投影 | AuditTransportProjectionTests | permission/turn/answer 修改仍失效；大容器 COW 未测 |
| QV-AUD-014 | 565 | B | 每行单 envelope 解码；恢复按256 KiB/128行/5 ms切片，批间检查取消 | AuditRolloutRecoverySliceTests | 5 ms 是软预算，单行同步解码仍有1 MiB硬上限 |
| QV-AUD-015 | 598 | 整合 | entry/context 增量 UTF-8 计账与逐出，避免每个 delta 全局重算 | AuditUIAccountingBenchTests | 计账动作与 delta 数相等；整个 ingress 仍含任务查找/文本成本 |
| QV-AUD-016 | 629 | 整合 | 外部 schema.pattern 不在主线程求值，使用原生处理回退 | AuditUIRequestLifecycleTests | 不支持的 schema 不扩大为可处理能力 |
| QV-AUD-017 | 661 | A | unfinished socket 有单一 FD 所有者、总截止、取消 shutdown 与 worker close | AuditTransportSharedSocketTests | 总 FD 为观测，需按连接归属证明关闭；未做长时/多平台矩阵 |
| QV-AUD-018 | 693 | 整合 | 未知/unbundled 身份独立 defaults/socket/queue；flock与inode约束清理；foreign queue保留；诊断日志同身份隔离 | AuditUIChannelIsolationTests / AuditLifecyclePrivacyRuleTests | stable/dev073 兼容原命名空间；未知身份不自动安装 Hook |
| QV-AUD-019 | 726 | B | Core/Hook 共用 counts-only PlanProgressParser，保留 transport 适配 | AuditRolloutPlanCompatibilityTests | JS 重复属性拒绝；JSON重复键沿用Foundation字典语义 |
| QV-AUD-020 | 760 | C | 拆出四个活的共享叶子，移除三个无调用的旧控制器体 | ArchitectureTests / source manifest | 渲染器、几何、Metal/Orb及永久开发台保持；无包大小/能耗结论 |
| QV-AUD-021 | 796 | 整合 | 生产 Runtime 使用 decoded public envelope，避免 forward Data 序列化与 Live 重解码 | AuditUIProjectionTests | 计数仅证明此 envelope 路径，兼容 Data API 保留 |
| QV-AUD-022 | 830 | C | 永久开发台 prepare 仅保留 host entry adapter，删除失配字符串补丁 | prepare source parity manifest | 不做开发台视觉验收 |
| QV-AUD-023 | 860 | C | 补齐 native FutureContracts/WidgetContract/HookSupport 模块与全部测试 membership | AuditBuildGraphTests / native build-for-testing | lexical declarations 不等于实际执行计数 |
| QV-AUD-024 | 893 | C | 文档以 native App bundle 为启动入口；native 测试验证实际包资源 | AuditBuildResourceTests / CodexActivityTextRenderingTests | SwiftPM 字体仅布局；不声称 SwiftPM App 资源完整 |
| QV-AUD-025 | 926 | C | CI 增加无签名 native Debug Test graph 与 Release App/Widget build 和资源清单 | AuditBuildGraphTests / CI native job | 本地构建不代替 exact PR/main 提交 CI |
| QV-AUD-026 | 958 | C | 文档明确 Xcode26/macOS26 SDK/Swift6，运行系统仍macOS14 | toolchain / graph checks | 未实测 Xcode26.0 最低版本、Intel/macOS14完整运行 |
| QV-AUD-027 | 992 | C | 签名/验证先 staging，非覆盖 sealed产物；Feed绑定公开下载字节并原子更新 | Tests/BuildScripts/AuditBuildReleaseSmoke.py | 20项为合成夹具；正式密码签名、公证与渠道需未来精确发布授权 |
| QV-AUD-028 | 1030 | C | 忽略取消的 provider 与确定性 entered/release gate；全量状态序列断言 | ArchitectureTests / AuditRefreshTransitionGateTests / AppBehaviorTests | publication gate mutant 能抓住旧成功；未声称全部并发穷举 |
| QV-AUD-029 | 1061 | 整合 | 应用生成缺省文案CN/EN，服务原文保持原样 | AuditUIIntegrationBoundaryTests | 服务正文不自行翻译 |
| QV-AUD-030 | 1096 | A + 整合 | partial items 缺席不结算异步问题；完整缺席或精确已答才结算；知识有界 | AuditTransportDesktopTests / AuditUIIntegrationBoundaryTests / DesktopWaitReconciliationSmokeTests | 同步 pending 权威独立；执行续行不替异步问题作答 |
| QV-AUD-031 | 1128 | A + 整合 | Shared flags 为 known-wait/known-running/unavailable 三态，未知不清等待 | AuditTransportProjectionTests / AuditUIIntegrationBoundaryTests | 只 known [] 清自身来源，其他来源等待保留 |
| QV-AUD-032 | 1158 | A + 整合 | 原始 wire Int64/string RPC ID贯穿生命周期，不经Double显示值定位 | AuditTransportProjectionTests / AuditUIIntegrationBoundaryTests | 2^53、2^53+1、Int64.max与字符串独立；epoch隔离仍有效 |
| QV-AUD-033 | 1190 | A | 验证私有socket父目录/路径/UID、peer UID与握手前后inode | AuditTransportSharedSocketTests | 不防恶意同UID进程；不安全/链接路径会明确禁用socket观察 |
| QV-AUD-034 | 1221 | B | 1024项有界头部LRU按dev/ino/size/纳秒mtime/ctime失效，共用于发现与消费 | AuditRolloutMetadataCacheTests | 无sleep的调度等价计数；仍做stat，不声称实际磁盘/能耗改善 |
| QV-AUD-035 | 1254 | B | 纯分类/hash/path规则下沉轻量Support；Hook保留独立净化wire | AuditLifecyclePrivacyRuleTests | 13类真实临时helper wire已隔离验证；不把Core/RPC/UI引入Hook |

## 整合反例与修订

- 原生产接线的001/008/009隔离基线：6项测试、26个失败断言；保留在本地证据目录。
- 002/006原始反例合计22个失败断言，019兼容反例6个失败断言；修复后的B隔离36项0失败。
- A最终23项新增定向测试与相关旧测试通过；各子集有重叠，不相加为独立测试总数。
- C初轮12项、最终20项发行封装/Feed夹具均使用mock；prepare保持生产源码（entry adapter除外）逐字节一致。
- 第一次共享树验证发现旧测试将socket直接放到/tmp，不满足033私有来源策略；改成独立
  canonical 0700父目录，保留断言和超时，11项相关测试通过。
- 原观察请求与owner请求的净化无关字段不同，不应成为内容修订。应答字段指纹修正后，
  能力升级保留UUID/草稿，真正修订仍清空；19项相关测试通过。
- 执行续行与未回答异步问题的生命周期独立：续行只退休owner绑定的匿名执行等待；
  问题只由完整集合缺席或精确已答结算，不能用aggregate flags或点击猜测结果。
- hosted测试禁用生产runtime，并使用PID隔离defaults；测试主体使用临时目录/合成数据。
- 018最后检查发现未知bundle的诊断日志仍落入稳定队列目录；现有case补断言产生1个失败，
  一行统一ChannelIdentity后SwiftPM三项及native三项隔离+一项资源复验通过。

## 测量解释

011在128/1000/4096张历史完成卡下测无变化早退与单卡变化；无变化没有onChange，变化
保留任务计数和完成提示语义。015的1/100/1000任务×50/200 delta样本按真实receive入口测量，
计账动作增量等于delta数；800步固定种子随机操作与独立慢速oracle逐事件一致，并覆盖
200条逐出、Unicode、换轮/关闭/reset、context-only及跨任务2MiB逐出。

014恢复矩阵为1/4/24候选×1/8/16MiB长文件；多候选含一个最新健康小文件，测试其优先处理。
034静止24文件的调度等价循环只进行24次头部读取/解码，追加/替换inode/截断/同长重写/reset
均失效。传输背压高水位65,536字节，帧payload复制量与payload长度一致。

这些都是本机Debug合成负载和计数，不宣称生产FPS、进程RSS硬上限、能耗、完整IPC延迟或
单行同步JSON可抢占。各组原始测量及源码manifest保存在 `.build/audit-20261006/`；
可复现测试源码进入仓库，本地日志与派生产物不提交。

## 最终共享树与交付

共享树SwiftPM已执行743项、6跳过、0失败（92.668秒，`integration-swift-tests-final.log`）。
明确跳过为120秒实时时钟、4项选择真实Codex CLI的隔离Hook/API、1项真实Codex代理场景；
本轮真实临时Hook wire已启用并通过，不属于这些跳过。44项NativeQuestionBridge合同夹具与
12项合成发布脚本夹具也通过。该快照后C复核仍在补脚本/CI/scheme缺口，后续定向检查另记。

原生build-for-testing已成功。读取生成xctestrun发现TestAction继承Launch环境会忽略自身的
runtime禁用变量；修正继承设置并确认实际变量进入生成产物后再做最终native执行。
因此首轮native失败日志不能作为运行隔离证明或最终通过。

最终native执行为746项、740通过、6跳过、0失败（97.906秒）；真实xctestrun环境已确认
runtime禁用与nonexistent Codex CLI生效，真实临时Hook wire另以显式路径启用。native资源测试
通过。发现集合为native746 / SwiftPM745，唯一差异为native-only包资源case，无碰撞或过滤。
C最后增加两项图断言，SwiftPM对当前图/字体增量11项通过；最后018日志namespace修订另有
SwiftPM3项及native4项通过，后者包括包资源。计数有重叠，不相加为独立测试总数。

合成发行场景最终20项全部通过；两个图mutant和缺HookSupport资源mutant产生预期失败；
44项原生提问合同夹具0失败/0真实动作。当前源码通过diff whitespace、shell/Python语法及链接检查。

最终开发包复用本轮最小native Debug编译产物，身份com.quotaview.development073 /
0.7.7 / 内部57，PID 26198。
195份source/resource输入、42项二进制/资源及实际加载的App debug dylib/Core/HookSupport
路径核对一致。旧正式主进程57506与首个开发进程20534已正常退出，正式安装字节不变。
只读运行日志证明native连接和当前任务snapshot_admitted / authoritative / owner_input；未代答。
证据位于本地development-launch.json、native-test-summary.json及test-inventory-comparison.json。

当前任务源码推送/PR与main exact SHA的CI继续按门禁执行，外部结论以当前PR与提交检查记录
及本地delivery记录为准，不将上述本地验证当成远端CI。
首次失败日志保留，不能用旧isolated通过替代最终结果。GitHub合入后将main SHA交给云端审查，
不在本机再次启动第二轮审计。真实显示与应答效果仍待用户验收。
