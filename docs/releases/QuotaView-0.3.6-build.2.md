# QuotaView 0.3.6 Build 2 — Customizable Codex Island

[Download QuotaView-v0.3.6-build.2.zip](https://github.com/Duoasa/QuotaView/releases/download/v0.3.6-build.2/QuotaView-v0.3.6-build.2.zip)

![QuotaView 0.3.6 Codex Island settings](https://raw.githubusercontent.com/Duoasa/QuotaView/v0.3.6-build.2/Resources/QuotaView-0.3.6-Codex-Island-Settings.png)

QuotaView 0.3.6 upgrades the stable single-task Codex Island with animation and
event timing controls, without changing its local-only privacy boundary.

## Highlights

- **Independent visibility control:** Show or hide the Codex Island without
  disconnecting the local Codex activity bridge.
- **Two live orb styles:** Choose the existing **Particle Orb** or the new
  **Ripple Glow** from production-rendered previews. Changes take effect
  immediately.
- **State-aware Ripple Glow:** The new orb covers all nine existing Codex task
  states, preserves a circular silhouette, and uses smooth color and speed
  transitions.
- **Custom event timing:** Set **Compact After Completion** from 5–60 seconds
  and **Hide After Compacting** from 5–120 seconds in five-second steps, with
  visible ticks and the current value.
- **Accessible and resilient:** Reduce Motion remains supported. Ripple Glow
  falls back to Particle Orb if Metal initialization is unavailable, and its
  pipeline is cached to avoid repeated shader compilation.
- **Stable scope:** This release continues to use one single-task island. The
  separate multi-task Preview experiment is not included.

The universal build supports Apple Silicon and Intel Macs running macOS 14 or
later. It is signed with the QuotaView Developer ID, notarized by Apple, and
stapled for offline Gatekeeper verification.

Users on the signed 0.3.5 Build 5 release can receive this version through the
Stable in-app update channel.

---

# QuotaView 0.3.6 Build 2 — 可自定义 Codex 灵动岛

[下载 QuotaView-v0.3.6-build.2.zip](https://github.com/Duoasa/QuotaView/releases/download/v0.3.6-build.2/QuotaView-v0.3.6-build.2.zip)

QuotaView 0.3.6 为稳定的单任务 Codex 灵动岛加入动画和事件时间自定义，同时
保持仅限本地的数据与隐私边界。

## 主要更新

- **独立显示控制：**可手动显示或隐藏 Codex 灵动岛，不会断开 Codex 本地
  活动连接；
- **两种实时光球：**可在生产渲染预览中选择既有的**粒子球**或新的
  **波澜光晕**，切换后立即生效；
- **状态化波澜光晕：**新光球适配现有九种 Codex 任务状态，保持圆形轮廓，
  并平滑过渡颜色和速度；
- **自定义事件时间：****完成后缩小**支持 5–60 秒，**缩小后隐藏**支持
  5–120 秒，均以 5 秒为档位，并显示刻度与当前值；
- **辅助功能与降级：**继续支持 Reduce Motion；Metal 初始化不可用时自动
  回退粒子球，并缓存波澜光晕 Pipeline，避免重复编译着色器；
- **稳定范围：**本版继续采用单任务灵动岛，不包含独立的多任务 Preview
  实验。

Universal 构建支持 macOS 14 或更高版本的 Apple 芯片与 Intel Mac，使用
QuotaView Developer ID 签名，已通过 Apple 公证并完成 Staple，可离线通过
Gatekeeper 验证。

已安装正式签名版 0.3.5 Build 5 的用户可以通过应用内 Stable 更新通道升级
到此版本。
