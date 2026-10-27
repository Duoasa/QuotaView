# Electron 共享动效

当前应用通过 `windows/scripts/build.cjs` 构建，复用本目录的球体、烟雾、量子噪点和波浪 WebGL2 渲染器。新逻辑与验收状态见 [Windows 构建说明](../windows/README.md)。`build.cjs` 是旧 ASAR 适配器，不参与当前分发；以下为历史接入记录，不代表本轮 Windows 实机验收。

## 历史接入

已将用户认可的 `Prototypes/EffectsLab` AI 球与量子噪点接入 dot 0.8.3-win.1 的实际 React 组件。输出版本为 `0.8.3-win.1.effects.2`。

effects.2 修复整窗灰色矩形底：岛和胶囊关闭原生 Acrylic 后重新设置透明背景，组件内部背景仍由 CSS 绘制（不提供原生桌面背景模糊）。定位改为所选屏幕 bounds 顶部，移除工作区顶部的 8 DIP 偏移。隔离启动检查确认实际窗口贴顶，GPU 与 React 检查通过；背景色读取 API 不包含 alpha，桌面透明效果仍以实际显示为准。

运行：`bin/QuotaView.ElectronEffects/QuotaView Windows.exe`。AI 球用于任务卡、收起状态和其他原球体位置；量子噪点在设置的特效选项中选择。新用户配置默认选择 quantum，已有设置不被强制覆盖。烟雾与波浪选项保持原实现。

## 实现

- `src/model.js`：从已验收 C# 模型迁移的连续相位、0.42 秒状态过渡、粒子位移、进度前沿及完成时序。真实任务和轮次标识关联模型，展开收起不重置同一任务的时钟；已有完成任务重新挂载时不会重播收尾。
- `src/runtime.js`：每个窗口共用一个 WebGL2 图集，绘制后合成到组件 canvas，避免每张卡片创建独立 WebGL 上下文。球体使用两倍采样；屏幕外和隐藏窗口停止调度；减少动态效果显示静态结果。
- `src/assets.js`：构建时由原开发台参数和 shader 自动生成，仅转换到 GLSL ES 300 并补精度声明；不重新设计原特效公式。
- `src/effects.css`：移除对应的 CSS 简化球体、噪点背景、透明度和宽度动画，保留文字与卡片布局。
- `build.cjs`：读取经校验的原始 ASAR，针对已知组件入口做唯一匹配替换，新增上述模块，输出独立运行目录。原包和独立特效开发台不变。源码包暂缺并不阻碍这次接入；取得完整 React 工程后可把相同组件直接移入源码，替代产物适配步骤。

压缩状态消费 `task.compacting`，同时识别 Claude 现有 `Compacting context` 工具标记。等待、终态和未知状态优先；Kimi 等未验证完成不驱动成功动画。非完成进度最高 95%，未知进度不伪造实际进度。

完成过程沿用铺满、短暂提亮、变暗、淡出和绿色描边。减少动态效果开启时立即显示收尾，重新开启动画不会重播已经结束的粒子效果。

## 构建与检查

从项目根目录运行：

```powershell
./ElectronEffects/build.ps1 -Test
```

构建需要 Node.js，不需要下载 npm 包。请先退出该输出目录的运行程序。输入依赖已经整理好的 `Imports/dot-0.8.3-win.1/runtime/win-unpacked/` 与 `Prototypes/EffectsLab/`；不接受其他版本的未知打包结构，匹配失败会中止。

2026-10-21 已通过 8 组模型回归测试，覆盖快速状态中断、进度边界、减少动态效果、完成一次性收尾、压缩优先级、帧率一致性、长时间精度和九种配色。

Windows 隔离启动及真实 React 组件 GPU 检查通过，结果保存在 `gpu-smoke.json`：

- island、capsule、settings 页面及预加载桥接成功。
- WebGL2 shader 编译并输出实际像素。
- AI 球和量子噪点 React 组件均成功挂载。
- 进度改变、压缩态配色、完成淡出及组件卸载清理通过。
- 一个 WebGL 上下文，特效错误为空。

测试使用独立临时用户目录，不连接真实 Agent；只做功能检查，不生成截图或替代用户视觉验收。正常运行路径仍使用 dot 的真实数据服务。原交付中的 Claude 新鲜度、真实 Hook 和安装器等其他问题不属于这次特效变更。

`effects-build-manifest.json` 位于输出目录，记录原 ASAR、接入后 ASAR 和各变更文件的哈希。输出目录保留的原交接文件描述 dot 基线；本文件和 effects-build-manifest 描述本次增量。
