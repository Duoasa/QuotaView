# Native Question Bridge Contract

独立、可运行的纯 Python 标准库合同夹具。运行：

```sh
cd Prototypes/NativeQuestionBridgeContract
python3 smoke.py
```

`policy.py` 只产生 `apiSend` 或 `pureDismiss` 模拟意图。所有转移使用不可变 state；`smoke.py` 的 fake adapter 只把意图写入内存列表。没有网络、AX、TCC、外部应用读取、真实用户数据、权限申请或生产代码导入；不会启动、控制或回答 Codex。Python bytecode 缓存也关闭。本目录未加入生产 Target，生产 `Sources` / `Tests` 与现有原型保持不变。专用 CI 步骤只运行本目录的全 synthetic `smoke.py`，不接入生产应用或执行平台操作。

## 证明范围

该夹具验证合同的 fail-closed 分支与模拟 happy path，**不证明真实 AX 树能够提取原生身份、完整问题组或草稿版本，不证明实际 Codex 存在关闭 lease/CAS API，也不证明原生提示已关闭**。当前所需 AX 精确身份与事务性排他证明缺失；没有这些证明时，合同返回 handoff。用户可在 Codex 手动关闭，不能把近似文字、窗口标题、深链、AX 属性名或通用 Escape 当作身份及关闭能力。

已观察到的原生所选问题组可以把同一轮次后来出现的题追加进来，跨多个 agentMessage/source。身份因此是 process incarnation / build / owner / epoch / hostId / conversation（原生 threadId）/ turn / entityKey / selectedQuestionKey.itemId、selection generation、**完整有序成员集**；每个成员包含 source、index、规范 native question ID 与原问题哈希。原生选中键明确为 `{hostId, threadId, entityKey, itemId}`；`selected_item` 保存实际选中的 itemId，必须精确等于完整成员集中的规范 native question ID，不从文字或 generation 推导；synthetic 默认选首个成员，真实 adapter 必须读取实际原生选中键。单一 sourceItemID 不是整个所选组的身份。新增题、顺序、内容或 generation 改变后旧关闭许可失效。resource-revoked descriptor 不构成 fresh proof。同 host、同 conversation 的新权威、轮次或选中组观察撤销该线程的旧 eligible 记录，使未执行的旧发送意图不能借旧 capability 的 fresh 标记执行；其它 host/线程和旧 reservation/unknown 账本保留。

答案提交优先且仅使用模拟 API 通路。先按稳定 hostId / conversation / turn / native member identity reservation 再一次发送，selected item、selection generation、成员追加或 owner/epoch 换代不能清除旧成员 reservation；切换其它已证明 host 仅使用该 host 的独立命名空间，返回原 host 时旧 unknown reservation 仍保留；完整组中已精确接受的成员不再次提交。重复 Confirm 与重复执行都不能再次发；ACK 仅证明 delivered，精确接受证明才证明 answered。超时/断连为 unknown，禁止自动重试、改用 AX 发送或在重新观察后抹掉 reservation。这里没有 AX 选项、输入、确认或 Skip 路由。原生异步选择可能约 180 ms 后自动发送，故不能通过“先 AX 选择再确认”或固定 sleep 推断可安全提交一次。

纯 Dismiss 必须另外证明权限明确启用且已授予、精确当前组、所有成员 accepted、完整 native drafts 等于 accepted baseline、没有更新 revision/编辑/待自动发送、精确 element generation，以及版本核实的纯关闭语义。名字为 Dismiss 的 Skip 或发送属性也会被拒绝。API capability 与 AX permission 相互独立；没有 AX 权限不提升或撤销原生 API 的提交能力。

## TOCTOU 与未来实现前提

`SyntheticCASGrant` **只是 synthetic native authority 的合同前提**，不是实际 lease API；其模拟 guard 一次比较并消费 scope、membership、element generation、draft revision 与 baseline，才能进行 fake compare-and-dismiss。`FakeAdapter` 的 race fixture 在最后一次读后更新草稿，模拟事务拒绝关闭且保留 unknown，不重新按关闭。

真实 read/press 之间的 TOCTOU 不能由两次读、事件静默、约 180 ms 等待或普通本地锁绝对消除。生产自动关闭需要**同原生组的事务性 lease/CAS 或等价 native exclusive guard**，并在原生执行端原子比较及关闭；本地 reducer 的校验不是该事务。当前 installed 并无已证明可用的此类能力。若提取或执行端无法满足它，应只允许用户手动 close，不能把 fake grant 接入真实 AX adapter，也不能用布尔字段冒充原生权威。

动作返回成功仍不等于 rendererClosed。只有同 scope、导航未改变、更新且完整的精确观察，证明目标 selected group 消失，并证明其它未答/并行 scope 保留，才能记录 closed。只有已执行的本组 Dismiss 有资格接受该结果证明；错线程、旧观察、仅 ACK、只读权限撤销或组内部分回答不会制造关闭事实。

## 冒烟覆盖

44 项 unittest case，全部 synthetic；参数化 case 另覆盖逐项 scope、成员与语义变化：

- 默认 disabled、denied、revoked；不自动申请权限。
- 一次 API reservation、ACK / accepted / rendererClosed 分离、unknown 不重试或换路。
- process / incarnation / build / owner / epoch / hostId / conversation / turn / entityKey / selected item 与完整 ordered members 精确相等；缺失或非字符串 host/item、组外或非规范 selected item、非字符串 source/hash 拒绝。
- 跨 source 的整组选题、后来新增题、同文字新身份、旧组与新组隔离。
- 多题部分回答、错误成员或原问题哈希、重复答案与不完整答案。
- 草稿 baseline、完整度、revision、编辑及 pending autoSend。
- element generation、导航、连接与 resource scope 撤销；动作前再次校验。
- pureDismiss、Skip 属性复用、未知语义及可能发送答案的语义。
- 无 lease、过期或不匹配 grant；unknown 不重复 press。
- read/press race 的 fake transactional 拒绝；假时钟推进 180 ms 不产生 AX 选择/输入/发送。
- 同 scope 新关闭证明、其它未答/并行 scope 保留、原记录不被关闭结果覆盖。

运行结果仅代表上述合同夹具，不代表生产集成、系统权限验收、视觉或真实交互验收。
