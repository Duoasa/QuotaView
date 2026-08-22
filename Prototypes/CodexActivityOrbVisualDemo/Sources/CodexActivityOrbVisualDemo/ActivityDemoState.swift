import AppKit
import simd

struct OrbRGBA: Equatable {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float

    init(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var vector: SIMD4<Float> {
        SIMD4(red, green, blue, alpha)
    }
}

struct OrbVisualConfiguration: Equatable {
    static let demoSpeedMultiplier: Float = 1.5

    let primary: OrbRGBA
    let secondary: OrbRGBA
    let accent: OrbRGBA
    let upperHighlight: OrbRGBA
    let highlight: OrbRGBA
    let speed: Float
    let warp: Float
    let ridgeAmount: Float
    let sharpness: Float
    let exposure: Float

    var effectiveSpeed: Float {
        speed * Self.demoSpeedMultiplier
    }

    func applying(to seed: [Float]) -> [Float] {
        var result = seed
        result[OrbUniformLayout.speed] = effectiveSpeed
        result[OrbUniformLayout.warp] = warp
        result[OrbUniformLayout.ridgeAmount] = ridgeAmount
        result[OrbUniformLayout.sharpness] = sharpness
        // The production island always presents a geometrically circular orb.
        // State-specific motion is restricted to the liquid inside the sphere.
        result[OrbUniformLayout.radius] = 0.535
        result[OrbUniformLayout.contourDeformation] = 0
        result[OrbUniformLayout.exposure] = exposure
        result[OrbUniformLayout.style] = 9
        result[OrbUniformLayout.glassEnabled] = 1
        result.setRGBA(primary, at: OrbUniformLayout.colorA)
        result.setRGBA(secondary, at: OrbUniformLayout.colorB)
        result.setRGBA(accent, at: OrbUniformLayout.colorC)
        result.setRGBA(upperHighlight, at: OrbUniformLayout.colorD)
        result.setRGBA(highlight, at: OrbUniformLayout.highlightColor)
        result.setRGBA(highlight, at: OrbUniformLayout.shellInner)
        result.setRGBA(accent, at: OrbUniformLayout.shellMid)
        result.setRGBA(secondary, at: OrbUniformLayout.shellEdge)
        return result
    }
}

private extension Array where Element == Float {
    mutating func setRGBA(_ color: OrbRGBA, at offset: Int) {
        self[offset] = color.red
        self[offset + 1] = color.green
        self[offset + 2] = color.blue
        self[offset + 3] = color.alpha
    }
}

enum DemoActivityState: String, CaseIterable, Identifiable {
    case disconnectedCodex
    case standby
    case thinking
    case working
    case compactingContext
    case awaitingConfirmation
    case completed
    case error
    case unavailable

    var id: Self { self }

    var pickerTitle: String {
        switch self {
        case .disconnectedCodex: "未连接"
        case .standby: "空闲"
        case .thinking: "思考"
        case .working: "工作"
        case .compactingContext: "压缩"
        case .awaitingConfirmation: "待确认"
        case .completed: "完成"
        case .error: "失败"
        case .unavailable: "未载入"
        }
    }

    var statusTitle: String {
        switch self {
        case .disconnectedCodex: "未连接 Codex"
        case .standby: "空闲"
        case .thinking: "思考中"
        case .working: "工作中"
        case .compactingContext: "正在压缩上下文"
        case .awaitingConfirmation: "待确认"
        case .completed: "已完成"
        case .error: "失败"
        case .unavailable: "未载入"
        }
    }

    var windowTitle: String {
        self == .disconnectedCodex ? "QuotaView" : "Codex · QuotaView-AppStore"
    }

    var operation: String {
        switch self {
        case .disconnectedCodex:
            "在 QuotaView 设置中连接 Codex 灵动岛"
        case .standby:
            "正在连接 Codex 会话"
        case .thinking:
            "正在分析新的任务"
        case .working:
            "正在修改项目文件"
        case .compactingContext:
            "正在整理较早消息以释放上下文空间"
        case .awaitingConfirmation:
            "有一项操作需要你的批准"
        case .completed:
            "当前任务已完成"
        case .error:
            "收到无法识别的 Codex 状态事件"
        case .unavailable:
            "Codex 灵动岛连接不可用"
        }
    }

    var expandedPanelSize: CGSize {
        switch self {
        case .standby:
            CGSize(width: 304, height: 112)
        case .completed, .error:
            CGSize(width: 374, height: 132)
        case .disconnectedCodex, .unavailable:
            CGSize(width: 390, height: 132)
        case .thinking,
             .working,
             .compactingContext,
             .awaitingConfirmation:
            CGSize(width: 444, height: 152)
        }
    }

    var accentColor: NSColor {
        switch self {
        case .disconnectedCodex:
            NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.64, alpha: 1)
        case .standby:
            NSColor(calibratedRed: 0.44, green: 0.52, blue: 0.68, alpha: 1)
        case .thinking:
            NSColor(calibratedRed: 0.55, green: 0.42, blue: 1.00, alpha: 1)
        case .working:
            NSColor(calibratedRed: 0.17, green: 0.83, blue: 0.91, alpha: 1)
        case .compactingContext:
            NSColor(calibratedWhite: 0.98, alpha: 1)
        case .awaitingConfirmation:
            NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.24, alpha: 1)
        case .completed:
            NSColor(calibratedRed: 0.22, green: 0.88, blue: 0.59, alpha: 1)
        case .error:
            NSColor(calibratedRed: 1.00, green: 0.31, blue: 0.37, alpha: 1)
        case .unavailable:
            NSColor(calibratedRed: 0.55, green: 0.57, blue: 0.61, alpha: 1)
        }
    }

    var showsOperationSweep: Bool {
        switch self {
        case .thinking, .working, .compactingContext:
            true
        case .disconnectedCodex,
             .standby,
             .awaitingConfirmation,
             .completed,
             .error,
             .unavailable:
            false
        }
    }

    var orbConfiguration: OrbVisualConfiguration {
        switch self {
        case .disconnectedCodex:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.13, 0.17, 0.24),
                secondary: OrbRGBA(0.28, 0.34, 0.44),
                accent: OrbRGBA(0.48, 0.57, 0.70),
                upperHighlight: OrbRGBA(0.68, 0.74, 0.84),
                highlight: OrbRGBA(0.86, 0.90, 0.96),
                speed: 0.24,
                warp: 1.6,
                ridgeAmount: 0.22,
                sharpness: 1.7,
                exposure: 1.45
            )
        case .standby:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.12, 0.23, 0.42),
                secondary: OrbRGBA(0.25, 0.35, 0.58),
                accent: OrbRGBA(0.44, 0.56, 0.75),
                upperHighlight: OrbRGBA(0.66, 0.76, 0.94),
                highlight: OrbRGBA(0.90, 0.94, 1.00),
                speed: 0.32,
                warp: 1.9,
                ridgeAmount: 0.28,
                sharpness: 1.8,
                exposure: 1.55
            )
        case .thinking:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.20, 0.12, 0.68),
                secondary: OrbRGBA(0.50, 0.23, 0.88),
                accent: OrbRGBA(0.34, 0.57, 1.00),
                upperHighlight: OrbRGBA(0.79, 0.48, 1.00),
                highlight: OrbRGBA(0.96, 0.91, 1.00),
                speed: 0.82,
                warp: 3.2,
                ridgeAmount: 0.50,
                sharpness: 2.2,
                exposure: 2.00
            )
        case .working:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.04, 0.30, 0.78),
                secondary: OrbRGBA(0.02, 0.65, 0.90),
                accent: OrbRGBA(0.28, 0.94, 0.84),
                upperHighlight: OrbRGBA(0.64, 1.00, 0.96),
                highlight: OrbRGBA(0.92, 1.00, 1.00),
                speed: 1.15,
                warp: 3.8,
                ridgeAmount: 0.68,
                sharpness: 2.5,
                exposure: 2.05
            )
        case .compactingContext:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.50, 0.56, 0.66),
                secondary: OrbRGBA(0.82, 0.86, 0.93),
                accent: OrbRGBA(0.98, 0.98, 1.00),
                upperHighlight: OrbRGBA(0.68, 0.76, 0.90),
                highlight: OrbRGBA(1.00, 1.00, 1.00),
                speed: 0.72,
                warp: 2.9,
                ridgeAmount: 0.62,
                sharpness: 2.6,
                exposure: 1.82
            )
        case .awaitingConfirmation:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.55, 0.21, 0.02),
                secondary: OrbRGBA(0.95, 0.46, 0.05),
                accent: OrbRGBA(1.00, 0.78, 0.22),
                upperHighlight: OrbRGBA(1.00, 0.56, 0.12),
                highlight: OrbRGBA(1.00, 0.94, 0.72),
                speed: 0.48,
                warp: 2.3,
                ridgeAmount: 0.38,
                sharpness: 2.0,
                exposure: 1.86
            )
        case .completed:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.02, 0.38, 0.22),
                secondary: OrbRGBA(0.05, 0.70, 0.40),
                accent: OrbRGBA(0.36, 0.95, 0.65),
                upperHighlight: OrbRGBA(0.54, 1.00, 0.79),
                highlight: OrbRGBA(0.90, 1.00, 0.95),
                speed: 0.36,
                warp: 1.8,
                ridgeAmount: 0.30,
                sharpness: 1.8,
                exposure: 1.70
            )
        case .error:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.55, 0.01, 0.05),
                secondary: OrbRGBA(0.92, 0.08, 0.14),
                accent: OrbRGBA(1.00, 0.36, 0.22),
                upperHighlight: OrbRGBA(1.00, 0.58, 0.18),
                highlight: OrbRGBA(1.00, 0.88, 0.82),
                speed: 0.96,
                warp: 3.9,
                ridgeAmount: 0.74,
                sharpness: 2.8,
                exposure: 1.98
            )
        case .unavailable:
            OrbVisualConfiguration(
                primary: OrbRGBA(0.23, 0.25, 0.30),
                secondary: OrbRGBA(0.36, 0.38, 0.43),
                accent: OrbRGBA(0.50, 0.53, 0.58),
                upperHighlight: OrbRGBA(0.62, 0.64, 0.68),
                highlight: OrbRGBA(0.78, 0.80, 0.84),
                speed: 0.08,
                warp: 0.8,
                ridgeAmount: 0.08,
                sharpness: 1.4,
                exposure: 1.20
            )
        }
    }
}
