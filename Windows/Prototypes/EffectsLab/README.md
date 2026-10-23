# QuotaView Windows 特效开发台

独立 Windows 窗口，集中预览 AI 球与量子噪点进度条。所有状态和进度都是明确标注的本地模拟输入，不读取账户、日志或网络，不影响现有 WPF 灵动岛。

## 启动

双击 `bin/QuotaView.EffectsLab.exe`。需要 Windows x64、.NET Framework 4.8，以及支持 OpenGL 3.3 或更高版本的显卡驱动。开发台不提供低保真替代效果；驱动或 shader 出错时会明确显示原因。

构建及模型检查：

```powershell
& './Prototypes/EffectsLab/build.ps1' -Test
```

从仓库根目录执行；重新构建前关闭开发台。没有 NuGet 或 SDK 下载依赖，使用 Windows 自带的 Framework 编译器。运行 `QuotaView.EffectsLab.exe --smoke` 可执行启动 GPU 检查后自动退出。

## 操作

- 顶部切换思考、执行、压缩上下文、待确认、完成、错误、待机、未连接、不可用。
- 滑块设置 0–95% 模拟进度；0%、1%、50%、95% 为边界观察快捷键。粒子运动不会增加任务进度。
- “完成 / 重播”显式触发完成：铺满 → 微亮 → 变暗 → 淡出 → 绿色描边呼吸。重复按下可重播；正常状态不会靠计时进入 100%。
- “暂停”冻结当前帧；“重置”重置运动时钟；速度支持 0.5×、1×、1.5×、2×。
- “减少动态效果”冻结持续运动，状态立即切换；完成立即呈现静态收尾。
- 上方独立效果区用于观察细节；下方卡片使用 24 DIP 球体与 68 DIP 高度观察组合效果。字体和卡片是开发台示例，不是完整灵动岛 UI。
- 最小化停止渲染定时器；关闭窗口释放 GL 上下文和纹理。

## 源码基准与移植范围

固定基准：[v0.7.7-build.1](https://github.com/Duoasa/QuotaView/releases/tag/v0.7.7-build.1)，提交 `3866177cfa19db734d657ef505a4dc72c3338fba`，MIT © 2026 Duoasa。

`reference/` 保留该版本原始 `CodexActivityRippleGlow.swift`、`CodexActivityRippleGlowShader.txt`（在本地以 `.metal` 保存）及 `CodexActivityStateSmoke.swift`，用于核对。

- **AI 球**：移植发行版默认 Ripple Glow style 9 的流体色带、玻璃折射、色散、高光、轮廓覆盖，以及九种状态配色；保留半径 0.535、固定轮廓和 2 倍离屏渲染。保留 0.42 秒状态插值；速度采用连续相位积分，快速切换从当前颜色继续。
- **量子噪点**：移植 `dropField` 分支，保留粒子 hash、2.35 单位粒子网格、进度前沿消散、状态运动及配色。双精度累计位移、1/120 秒子步、256 周期时钟过渡，避免切换状态时重置粒子。
- **完成收尾**：使用发行版 0.42 秒铺满、0.80 秒开始淡出、1.16 秒开始描边等时序。描边是 Windows 开发台的独立 GLSL 实现，尚未做原生 macOS 描边逐像素对照。
- **Windows 适配**：Metal 转为 GLSL；WinForms 负责开发控件，原生 OpenGL 负责 GPU 渲染。噪点分辨率按 DIP 输入，便于在 Windows 缩放下观察。色彩空间、DPI 与不同显卡输出仍需人工对照。

这不是完整 Windows 发行版，也还没有把 GPU 表面接入 WPF 透明灵动岛。后续可复用 `EffectsModel`、状态参数和 shader；WPF 的透明窗口合成需要单独选择和验证 Direct3D/共享纹理等接入方式。

## 文件分工与验证

- `src/EffectsModel.cs`：连续时钟、状态过渡、进度和完成时序；不依赖 UI。
- `src/ReleaseProfiles.cs`：从固定发行版提取的参数。
- `src/NativeGL.cs`：Windows 上下文、shader、纹理与离屏渲染资源。
- `src/LabWindow.cs`：开发控制项、两个独立预览与卡片组合。
- `shaders/`：GLSL 程序。
- `tests/ModelTests.cs`：状态中断连续性、帧率一致性、完成边界、暂停及减少动态效果。

启动时执行少量 GPU 像素读回检查，验证 shader 有输出、响应时间和进度，以及减少动态效果下的完成结果。只保存文字回执，不生成截图。这些是功能检查，**不代表视觉验收通过**。

本地诊断在 `.local/gpu-smoke.txt`、`.local/status.txt`，错误在 `.local/error.txt`（历史错误可能保留，应结合时间和当前状态判断）。
