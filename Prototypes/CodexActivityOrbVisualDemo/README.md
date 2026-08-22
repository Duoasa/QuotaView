# QuotaView 当前单灵动岛状态 Demo

这是 `QV-PRODUCT-ACTIVITY-ISLAND-004` 的隔离 Prototype。产品所有者已
确认该效果，并以“波澜光晕”迁入 `0.3.6 Build 2` 的生产灵动岛动画选项；
本目录继续作为独立调参与回归证据。

## 边界

- 外壳同步复用生产 `ActivityIslandContentView` 的 AppKit/CoreText 排版、
  展开/紧凑几何、阴影、材质和操作文字效果，不包含或读取多任务实验；
- 覆盖未连接、空闲、思考、工作、压缩上下文、待确认、完成、失败和未载入
  九种生产视觉状态；
- 只把生产 `orbView` 替换为新 Metal 动画；各状态可改变球内配色、速度、
  扰动和锐度，但统一锁定生产半径 `0.535` 与圆形外轮廓，状态切换时平滑
  过渡；
- 使用纯模拟展示环境，不连接 Hook、Socket、Codex 数据或账户；
- Demo 本身不连接或修改生产 Target、设置、Release 或 appcast；
- Demo 中的背景和尺寸控件只用于手动观察，不是已确认的生产设置；
- 着色器来自产品所有者提供的 SwiftUI 参考代码，使用 `style = 9` 的玻璃
  流体波带参数；定稿速度为参考动画的 `1.5×`。

## 冒烟测试

```bash
swift test --package-path Prototypes/CodexActivityOrbVisualDemo
swift run --package-path Prototypes/CodexActivityOrbVisualDemo \
  CodexActivityOrbVisualDemo --smoke-test
```

第二条命令会在不打开窗口的情况下完成：Metal 设备创建、着色器运行时编译、
顶点/片段函数解析、渲染管线创建，以及九种状态各一次 `128 × 128` 离屏
绘制。

## 手动调试

```bash
swift run --package-path Prototypes/CodexActivityOrbVisualDemo
```

窗口提供：

- 九种当前运行状态的手动切换；
- 展开态与紧凑态尺寸切换；
- 中性、深色和浅色三种观察背景；
- 动画暂停与重新开始；
- Metal 初始化失败时的可见错误信息。

Demo 视觉、圆形轮廓和动画节奏已由产品所有者确认。设置页及生产灵动岛的
集成效果仍需在 Build 2 中单独验收；Demo 冒烟通过不代表集成验收。
