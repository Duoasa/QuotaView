import AppKit
import CoreText
import MetalKit
import QuartzCore
import simd

enum ActivityStatusSemanticSource: Equatable {
    case codex
    case derived

    var displayName: String {
        switch self {
        case .codex:
            "Codex 官方状态"
        case .derived:
            "QuotaView 派生状态"
        }
    }
}

enum ActivityState: Int, CaseIterable {
    case standby
    case thinking
    case working
    case compactingContext
    case awaitingConfirmation
    case completed
    case error
    case unavailable

    var title: String {
        switch self {
        case .standby: "待命"
        case .thinking: "思考中"
        case .working: "工作中"
        case .compactingContext: "正在压缩上下文"
        case .awaitingConfirmation: "待确认"
        case .completed: "已完成"
        case .error: "出错"
        case .unavailable: "不可用"
        }
    }

    var englishTitle: String {
        switch self {
        case .standby: "Standby"
        case .thinking: "Thinking"
        case .working: "Working"
        case .compactingContext: "Compacting Context"
        case .awaitingConfirmation: "Awaiting Confirmation"
        case .completed: "Completed"
        case .error: "Error"
        case .unavailable: "Unavailable"
        }
    }

    var visibleStatusTitle: String {
        switch self {
        case .standby:
            "空闲"
        case .thinking:
            "思考中"
        case .working:
            "工作中"
        case .compactingContext:
            "正在压缩上下文"
        case .awaitingConfirmation:
            "等待批准"
        case .completed:
            "已完成"
        case .error:
            "失败"
        case .unavailable:
            "未载入"
        }
    }

    var statusSemanticSource: ActivityStatusSemanticSource {
        switch self {
        case .thinking, .working, .compactingContext:
            .derived
        case .standby,
             .awaitingConfirmation,
             .completed,
             .error,
             .unavailable:
            .codex
        }
    }

    var officialStatusIdentifier: String {
        switch self {
        case .standby:
            "idle"
        case .thinking, .working, .compactingContext:
            "active · inProgress"
        case .awaitingConfirmation:
            "active · waitingOnApproval"
        case .completed:
            "completed"
        case .error:
            "failed"
        case .unavailable:
            "notLoaded"
        }
    }

    var currentOperation: String {
        switch self {
        case .standby:
            "等待新的任务"
        case .thinking:
            "正在分析状态映射与界面文案"
        case .working:
            "正在构建 CodexActivityMetalDemo"
        case .compactingContext:
            "正在整理较早消息以释放上下文空间"
        case .awaitingConfirmation:
            "启动新版 Metal Demo 需要你的批准"
        case .completed:
            "文字排版与状态映射校验通过"
        case .error:
            "Swift 测试在构建阶段终止"
        case .unavailable:
            "正在连接 Codex App Server"
        }
    }

    var showsOperationSweep: Bool {
        switch self {
        case .thinking,
             .working,
             .compactingContext,
             .unavailable:
            true
        case .standby,
             .awaitingConfirmation,
             .completed,
             .error:
            false
        }
    }

    var shortcut: String {
        String(rawValue + 1)
    }

    var windowSize: NSSize {
        switch self {
        case .standby:
            NSSize(width: 304, height: 112)
        case .completed, .error:
            NSSize(width: 374, height: 132)
        case .unavailable:
            NSSize(width: 390, height: 132)
        case .thinking,
             .working,
             .compactingContext,
             .awaitingConfirmation:
            NSSize(width: 444, height: 152)
        }
    }

    var accentColor: NSColor {
        switch self {
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

    var orbStyle: OrbStyle {
        switch self {
        case .standby:
            OrbStyle(
                primary: rgba(0.12, 0.23, 0.42),
                secondary: rgba(0.25, 0.35, 0.58),
                accent: rgba(0.44, 0.56, 0.75),
                speed: 0.045,
                speedFloor: 0.28,
                motionCycle: 16.0,
                tempo: 0.58,
                response: 1.25,
                energy: 0.50,
                turbulence: 0.12,
                pulse: 0.05,
                desaturation: 0.18,
                volume: 0.44,
                refraction: 0.50
            )
        case .thinking:
            OrbStyle(
                primary: rgba(0.20, 0.12, 0.68),
                secondary: rgba(0.50, 0.23, 0.88),
                accent: rgba(0.34, 0.57, 1.00),
                speed: 0.14,
                speedFloor: 0.22,
                motionCycle: 11.0,
                tempo: 0.82,
                response: 1.55,
                energy: 0.86,
                turbulence: 0.34,
                pulse: 0.18,
                desaturation: 0,
                volume: 0.76,
                refraction: 0.74
            )
        case .working:
            OrbStyle(
                primary: rgba(0.04, 0.30, 0.78),
                secondary: rgba(0.02, 0.65, 0.90),
                accent: rgba(0.28, 0.94, 0.84),
                speed: 0.24,
                speedFloor: 0.18,
                motionCycle: 8.5,
                tempo: 1.05,
                response: 1.85,
                energy: 1.02,
                turbulence: 0.58,
                pulse: 0.22,
                desaturation: 0,
                volume: 0.94,
                refraction: 0.84
            )
        case .compactingContext:
            OrbStyle(
                primary: rgba(0.50, 0.56, 0.66),
                secondary: rgba(0.82, 0.86, 0.93),
                accent: rgba(1.00, 1.00, 1.00),
                speed: 0.16,
                speedFloor: 0.20,
                motionCycle: 9.5,
                tempo: 0.90,
                response: 1.80,
                energy: 1.02,
                turbulence: 0.48,
                pulse: 0.30,
                desaturation: 0.12,
                volume: 0.94,
                refraction: 0.90,
                compression: 1
            )
        case .awaitingConfirmation:
            OrbStyle(
                primary: rgba(0.55, 0.21, 0.02),
                secondary: rgba(0.95, 0.46, 0.05),
                accent: rgba(1.00, 0.78, 0.22),
                speed: 0.075,
                speedFloor: 0.18,
                motionCycle: 12.0,
                tempo: 0.72,
                response: 1.45,
                energy: 0.92,
                turbulence: 0.20,
                pulse: 0.46,
                desaturation: 0,
                volume: 0.68,
                refraction: 0.82
            )
        case .completed:
            OrbStyle(
                primary: rgba(0.02, 0.38, 0.22),
                secondary: rgba(0.05, 0.70, 0.40),
                accent: rgba(0.36, 0.95, 0.65),
                speed: 0.055,
                speedFloor: 0.20,
                motionCycle: 13.0,
                tempo: 0.55,
                response: 1.20,
                energy: 0.82,
                turbulence: 0.12,
                pulse: 0.12,
                desaturation: 0,
                volume: 0.62,
                refraction: 0.68
            )
        case .error:
            OrbStyle(
                primary: rgba(0.55, 0.01, 0.05),
                secondary: rgba(0.92, 0.08, 0.14),
                accent: rgba(1.00, 0.36, 0.22),
                speed: 0.13,
                speedFloor: 0.22,
                motionCycle: 8.0,
                tempo: 0.92,
                response: 2.10,
                energy: 0.96,
                turbulence: 0.62,
                pulse: 0.28,
                desaturation: 0,
                volume: 0.82,
                refraction: 0.62
            )
        case .unavailable:
            OrbStyle(
                primary: rgba(0.23, 0.25, 0.30),
                secondary: rgba(0.36, 0.38, 0.43),
                accent: rgba(0.50, 0.53, 0.58),
                speed: 0.015,
                speedFloor: 0.15,
                motionCycle: 18.0,
                tempo: 0.28,
                response: 1.00,
                energy: 0.36,
                turbulence: 0.03,
                pulse: 0,
                desaturation: 0.88,
                volume: 0.24,
                refraction: 0.18
            )
        }
    }
}

struct DemoTask: Equatable, Identifiable {
    let id: Int
    var name: String
    var state: ActivityState
}

func taskAttentionCount(_ tasks: [DemoTask]) -> Int {
    tasks.filter {
        $0.state == .awaitingConfirmation || $0.state == .error
    }.count
}

func backgroundTaskTitleShowsSweep(
    state: ActivityState,
    isPrimary: Bool
) -> Bool {
    guard !isPrimary else { return false }
    return state == .thinking || state == .working
}

enum TaskRailMetrics {
    static let visibleRowCount = 3
    static let headerFontSize: CGFloat = 10.5
    static let headerItemGap: CGFloat = 6
    static let leadingPadding: CGFloat = 12
    static let trailingPadding: CGFloat = 24
    static let topPadding: CGFloat = 12
    static let headerHeight: CGFloat = 14
    static let headerToRowsGap: CGFloat = 8
    static let rowHeight: CGFloat = 20
    static let rowStep: CGFloat = 23
    static let viewportHeight: CGFloat = 66
    static let rowsToFooterGap: CGFloat = 8
    static let footerHeight: CGFloat = 12
    static let bottomPadding: CGFloat = 12
    static let markerLeading: CGFloat = 10
    static let markerDotSize: CGFloat = 5
    static let markerToNameGap: CGFloat = 9
    static let selectedMarkerWidth: CGFloat = 5
    static let selectedMarkerHeight: CGFloat = 12
    static let selectedMarkerCornerRadius: CGFloat = 2.5
    static let selectionGlassLeading: CGFloat = 4
    static let selectionGlassTrailing: CGFloat = 24
    static let selectionGlassHeight: CGFloat = 20
    static let selectionGlassCornerRadius: CGFloat = 6
    static let selectionGlassTintAlpha: CGFloat = 0.10
    static let selectionMorphDuration: CFTimeInterval = 0.8
    static let selectionExpandedKeyTime: NSNumber = 0.22
    static let selectionCollapseKeyTime: NSNumber = 0.74
    static let scrollDuration: CFTimeInterval = 0.5
    static let inactiveScale: CGFloat = 0.96

    static var rowGap: CGFloat {
        rowStep - rowHeight
    }

    static var viewportY: CGFloat {
        bottomPadding + footerHeight + rowsToFooterGap
    }

    static var requiredHeight: CGFloat {
        topPadding
            + headerHeight
            + headerToRowsGap
            + viewportHeight
            + rowsToFooterGap
            + footerHeight
            + bottomPadding
    }

    static func showsPagination(taskCount: Int) -> Bool {
        taskCount > visibleRowCount
    }

    static func visibleRowsHeight(taskCount: Int) -> CGFloat {
        let visibleCount = min(
            max(taskCount, 0),
            visibleRowCount
        )
        guard visibleCount > 0 else { return 0 }
        return CGFloat(visibleCount) * rowStep - rowGap
    }

    static func viewportHeight(taskCount: Int) -> CGFloat {
        showsPagination(taskCount: taskCount)
            ? viewportHeight
            : visibleRowsHeight(taskCount: taskCount)
    }

    static func viewportY(
        containerHeight: CGFloat,
        taskCount: Int
    ) -> CGFloat {
        if showsPagination(taskCount: taskCount) {
            return viewportY
        }
        return max(
            0,
            (containerHeight - viewportHeight(taskCount: taskCount)) / 2
        )
    }
}

func taskRailSelectionGlassFrame(
    markerFrame: NSRect,
    containerWidth: CGFloat
) -> NSRect {
    return NSRect(
        x: TaskRailMetrics.selectionGlassLeading,
        y:
            markerFrame.midY
            - TaskRailMetrics.selectionGlassHeight / 2,
        width: max(
            0,
            containerWidth
                - TaskRailMetrics.selectionGlassLeading
                - TaskRailMetrics.selectionGlassTrailing
        ),
        height: TaskRailMetrics.selectionGlassHeight
    )
}

struct TaskRailHeaderLayout: Equatable {
    let taskFrame: NSRect
    let counterFrame: NSRect
}

func centeredTaskRailHeaderLayout(
    containerWidth: CGFloat,
    y: CGFloat,
    height: CGFloat,
    taskWidth: CGFloat,
    counterWidth: CGFloat,
    gap: CGFloat = TaskRailMetrics.headerItemGap
) -> TaskRailHeaderLayout {
    let groupWidth = taskWidth + gap + counterWidth
    let leading = max(0, (containerWidth - groupWidth) / 2)
    return TaskRailHeaderLayout(
        taskFrame: NSRect(
            x: leading,
            y: y,
            width: taskWidth,
            height: height
        ),
        counterFrame: NSRect(
            x: leading + taskWidth + gap,
            y: y,
            width: counterWidth,
            height: height
        )
    )
}

func railWindowStart(
    for tasks: [DemoTask],
    primaryID: Int,
    limit: Int = TaskRailMetrics.visibleRowCount
) -> Int {
    guard limit > 0,
          tasks.count > limit,
          let primaryIndex = tasks.firstIndex(where: { $0.id == primaryID })
    else {
        return 0
    }

    let maximumStart = tasks.count - limit
    return min(
        max(0, primaryIndex - limit + 1),
        maximumStart
    )
}

func visibleRailTasks(
    from tasks: [DemoTask],
    primaryID: Int,
    limit: Int = TaskRailMetrics.visibleRowCount
) -> [DemoTask] {
    guard limit > 0 else { return [] }
    let start = railWindowStart(
        for: tasks,
        primaryID: primaryID,
        limit: limit
    )
    return Array(tasks.dropFirst(start).prefix(limit))
}

let demoIslandAnchorGap: CGFloat = 12

func anchoredIslandFrame(
    size: NSSize,
    anchorFrame: NSRect,
    gap: CGFloat = demoIslandAnchorGap
) -> NSRect {
    NSRect(
        x: anchorFrame.midX - size.width / 2,
        y: anchorFrame.maxY + gap,
        width: size.width,
        height: size.height
    )
}

struct CompactIslandLayoutMetrics: Equatable {
    let statusWidth: CGFloat
    let titleWidth: CGFloat
    let countWidth: CGFloat
    let countLeadingGap: CGFloat
    let surfaceSize: NSSize

    var marqueeLeading: CGFloat {
        IslandPresentationMode.compactTextLeading
            + statusWidth
            + IslandPresentationMode.compactSeparatorWidth
    }
}

enum IslandPresentationMode: Int, CaseIterable {
    case expanded
    case compact

    static let panelInset: CGFloat = 10
    static let compactSurfaceHeight: CGFloat = 52
    static let compactOrbInset: CGFloat = 12
    static let compactTextGap: CGFloat = 14
    static let compactTitleFontSize: CGFloat = 14
    static let compactTextMeasurementPadding: CGFloat = 2
    static let compactSeparatorWidth: CGFloat = 12
    static let compactTitleMinimumWidth: CGFloat = 44
    static let compactTitleMaximumWidth: CGFloat = 128
    static let compactCountWidth: CGFloat = 54
    static let compactCountTrailing: CGFloat = 12
    static let compactCountLeadingGap: CGFloat = 12
    static let multiTaskMainCardPanelSize = NSSize(
        width: 496,
        height: 152
    )
    static let taskRailWidth: CGFloat = 144
    static let shadowRadius: CGFloat = 7
    static let shadowVerticalOffset: CGFloat = -2

    static var requiredShadowInset: CGFloat {
        shadowRadius + abs(shadowVerticalOffset)
    }

    static var compactOrbDiameter: CGFloat {
        compactSurfaceHeight - compactOrbInset * 2
    }

    static var compactOrbLeading: CGFloat {
        compactOrbInset
    }

    static var compactTextLeading: CGFloat {
        compactOrbLeading + compactOrbDiameter + compactTextGap
    }

    static var compactOrbCanvasSide: CGFloat {
        compactOrbDiameter / CGFloat(orbSphereRadius)
    }

    static func compactLayoutMetrics(
        statusTitle: String,
        taskTitle: String,
        taskCount: Int
    ) -> CompactIslandLayoutMetrics {
        let statusFont = demoFont(
            "AstaSans-SemiBold",
            size: compactTitleFontSize,
            fallbackWeight: .semibold
        )
        let titleFont = demoFont(
            "AstaSans-SemiBold",
            size: compactTitleFontSize,
            fallbackWeight: .semibold
        )
        let statusWidth = ceil(
            singleLineTypographicWidth(
                text: statusTitle,
                font: statusFont
            )
        ) + compactTextMeasurementPadding
        let titleTextWidth = ceil(
            singleLineTypographicWidth(
                text: taskTitle,
                font: titleFont
            )
        ) + compactTextMeasurementPadding
        let titleWidth = min(
            compactTitleMaximumWidth,
            max(
                compactTitleMinimumWidth,
                titleTextWidth + CompactMarqueeMetrics.edgeInset * 2
            )
        )
        let countWidth = taskCount > 1 ? compactCountWidth : 0
        let countLeadingGap = taskCount > 1
            ? compactCountLeadingGap
            : 0
        let surfaceWidth = compactTextLeading
            + statusWidth
            + compactSeparatorWidth
            + titleWidth
            + countLeadingGap
            + countWidth
            + compactCountTrailing

        return CompactIslandLayoutMetrics(
            statusWidth: statusWidth,
            titleWidth: titleWidth,
            countWidth: countWidth,
            countLeadingGap: countLeadingGap,
            surfaceSize: NSSize(
                width: surfaceWidth,
                height: compactSurfaceHeight
            )
        )
    }

    var title: String {
        switch self {
        case .expanded: "最大态"
        case .compact: "紧凑态"
        }
    }

    var transitionDuration: TimeInterval {
        switch self {
        case .expanded: 0.30
        case .compact: 0.28
        }
    }

    func panelSize(for state: ActivityState) -> NSSize {
        panelSize(for: state, taskCount: 1, taskTitle: "")
    }

    func panelSize(
        for state: ActivityState,
        taskCount: Int,
        taskTitle: String = ""
    ) -> NSSize {
        switch self {
        case .expanded:
            return taskCount > 1
                ? Self.multiTaskMainCardPanelSize
                : state.windowSize
        case .compact:
            let metrics = Self.compactLayoutMetrics(
                statusTitle: state.visibleStatusTitle,
                taskTitle: taskTitle,
                taskCount: taskCount
            )
            return NSSize(
                width:
                    metrics.surfaceSize.width
                    + Self.panelInset * 2,
                height:
                    metrics.surfaceSize.height
                    + Self.panelInset * 2
            )
        }
    }
}

func compactDetailExpansionEnabled(
    presentationMode: IslandPresentationMode,
    taskCount: Int
) -> Bool {
    presentationMode == .compact && taskCount > 1
}

func normalizedExpansionProgress(
    surfaceHeight: CGFloat,
    expandedSurfaceHeight: CGFloat
) -> CGFloat {
    let compactHeight =
        IslandPresentationMode.compactSurfaceHeight
    let range = max(
        expandedSurfaceHeight - compactHeight,
        1
    )
    return min(
        max((surfaceHeight - compactHeight) / range, 0),
        1
    )
}

func interpolate(
    from start: CGFloat,
    to end: CGFloat,
    progress: CGFloat
) -> CGFloat {
    start + (end - start) * progress
}

enum SingleLineHorizontalAlignment: Equatable {
    case leading
    case center
}

struct SingleLineInkPlacement {
    var baselineOrigin: CGPoint
}

func singleLineInkPlacement(
    in bounds: NSRect,
    imageBounds: CGRect,
    alignment: SingleLineHorizontalAlignment
) -> SingleLineInkPlacement {
    let baselineX: CGFloat
    switch alignment {
    case .leading:
        baselineX = bounds.minX
    case .center:
        baselineX = bounds.midX - imageBounds.midX
    }

    return SingleLineInkPlacement(
        baselineOrigin: CGPoint(
            x: baselineX,
            y: bounds.midY - imageBounds.midY
        )
    )
}

func makeTruncatedSingleLine(
    text: String,
    font: NSFont,
    color: NSColor,
    maximumWidth: CGFloat
) -> CTLine {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let source = NSAttributedString(
        string: text,
        attributes: attributes
    )
    let sourceLine = CTLineCreateWithAttributedString(source)
    let sourceWidth = CGFloat(
        CTLineGetTypographicBounds(
            sourceLine,
            nil,
            nil,
            nil
        )
    )

    guard sourceWidth > maximumWidth else {
        return sourceLine
    }

    let token = NSAttributedString(
        string: "…",
        attributes: attributes
    )
    let tokenLine = CTLineCreateWithAttributedString(token)
    return CTLineCreateTruncatedLine(
        sourceLine,
        Double(max(0, maximumWidth)),
        .end,
        tokenLine
    ) ?? tokenLine
}

func drawCenteredSingleLine(
    text: String,
    font: NSFont,
    color: NSColor,
    in bounds: NSRect,
    alignment: SingleLineHorizontalAlignment,
    context: CGContext
) {
    guard !text.isEmpty,
          bounds.width > 0,
          bounds.height > 0
    else {
        return
    }

    let line = makeTruncatedSingleLine(
        text: text,
        font: font,
        color: color,
        maximumWidth: bounds.width
    )
    let imageBounds = CTLineGetImageBounds(line, nil)
    guard !imageBounds.isNull,
          imageBounds.width > 0,
          imageBounds.height > 0
    else {
        return
    }

    let placement = singleLineInkPlacement(
        in: bounds,
        imageBounds: imageBounds,
        alignment: alignment
    )

    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = placement.baselineOrigin
    CTLineDraw(line, context)
    context.restoreGState()
}

final class SingleLineTextMaskLayer: CALayer {
    var text = "" {
        didSet {
            setNeedsDisplay()
        }
    }

    var textFont = NSFont.systemFont(ofSize: 13) {
        didSet {
            setNeedsDisplay()
        }
    }

    var textAlignment = SingleLineHorizontalAlignment.leading {
        didSet {
            setNeedsDisplay()
        }
    }

    override func draw(in context: CGContext) {
        drawCenteredSingleLine(
            text: text,
            font: textFont,
            color: .white,
            in: bounds,
            alignment: textAlignment,
            context: context
        )
    }
}

final class CenteredSingleLineTextView: NSView {
    private static let shimmerAnimationKey =
        "operation-highlight-sweep"
    private static let shimmerDuration: CFTimeInterval = 2.6

    private let shimmerLayer = CAGradientLayer()
    private let shimmerMaskLayer = SingleLineTextMaskLayer()
    private var reduceMotion = false

    var stringValue = "" {
        didSet {
            needsDisplay = true
            updateShimmerMask()
            restartShimmerIfNeeded()
        }
    }

    var font = NSFont.systemFont(ofSize: 13) {
        didSet {
            needsDisplay = true
            updateShimmerMask()
        }
    }

    var textColor = NSColor.labelColor {
        didSet {
            needsDisplay = true
        }
    }

    var horizontalAlignment = SingleLineHorizontalAlignment.leading {
        didSet {
            needsDisplay = true
            updateShimmerMask()
        }
    }

    var shimmerEnabled = false {
        didSet {
            updateShimmerPlayback()
        }
    }

    var isShimmerAnimationActive: Bool {
        shimmerLayer.animation(
            forKey: Self.shimmerAnimationKey
        ) != nil
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    convenience init() {
        self.init(frame: .zero)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext
        else {
            return
        }

        drawCenteredSingleLine(
            text: stringValue,
            font: font,
            color: textColor,
            in: bounds,
            alignment: horizontalAlignment,
            context: context
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        shimmerLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.white.withAlphaComponent(0.92).cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor
        ]
        shimmerLayer.locations = [
            -0.58,
            -0.42,
            -0.26,
            -0.10,
            0.06
        ]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.mask = shimmerMaskLayer
        shimmerLayer.isHidden = true
        layer?.addSublayer(shimmerLayer)
        updateShimmerMask()
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerLayer.frame = bounds
        shimmerMaskLayer.frame = shimmerLayer.bounds
        let contentsScale =
            window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        shimmerLayer.contentsScale = contentsScale
        shimmerMaskLayer.contentsScale = contentsScale
        CATransaction.commit()
        shimmerMaskLayer.setNeedsDisplay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        updateShimmerPlayback()
    }

    private func updateShimmerMask() {
        shimmerMaskLayer.text = stringValue
        shimmerMaskLayer.textFont = font
        shimmerMaskLayer.textAlignment = horizontalAlignment
    }

    private func restartShimmerIfNeeded() {
        guard shimmerEnabled, !reduceMotion else {
            return
        }

        shimmerLayer.removeAnimation(
            forKey: Self.shimmerAnimationKey
        )
        addShimmerAnimation()
    }

    private func updateShimmerPlayback() {
        let shouldAnimate = shimmerEnabled && !reduceMotion
        shimmerLayer.isHidden = !shouldAnimate

        if shouldAnimate {
            if !isShimmerAnimationActive {
                addShimmerAnimation()
            }
        } else {
            shimmerLayer.removeAnimation(
                forKey: Self.shimmerAnimationKey
            )
        }
    }

    private func addShimmerAnimation() {
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [
            -0.58,
            -0.42,
            -0.26,
            -0.10,
            0.06
        ]
        animation.toValue = [
            0.94,
            1.10,
            1.26,
            1.42,
            1.58
        ]
        animation.duration = Self.shimmerDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(
            name: .easeInEaseOut
        )
        shimmerLayer.add(
            animation,
            forKey: Self.shimmerAnimationKey
        )
    }
}

enum CompactMarqueeMetrics {
    static let edgeInset: CGFloat = 8
    static let repeatGap: CGFloat = 28
    static let minimumCycleDuration: CFTimeInterval = 5.6
    static let pointsPerSecond: CGFloat = 24

    static func needsScrolling(
        textWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> Bool {
        textWidth > max(0, viewportWidth - edgeInset * 2)
    }

    static func cycleDuration(
        textWidth: CGFloat
    ) -> CFTimeInterval {
        max(
            minimumCycleDuration,
            CFTimeInterval(
                (textWidth + repeatGap) / pointsPerSecond
            )
        )
    }
}

func singleLineTypographicWidth(
    text: String,
    font: NSFont
) -> CGFloat {
    let attributed = NSAttributedString(
        string: text,
        attributes: [.font: font]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    return CGFloat(
        CTLineGetTypographicBounds(
            line,
            nil,
            nil,
            nil
        )
    )
}

final class CompactMarqueeTextView: NSView {
    private static let animationKey = "compact-title-marquee"

    private let contentView = NSView()
    private let primaryLabel = CenteredSingleLineTextView()
    private let repeatedLabel = CenteredSingleLineTextView()
    private let edgeFadeMask = CAGradientLayer()
    private var reduceMotion = false
    private var active = false
    private var animationSignature = ""

    var stringValue = "" {
        didSet {
            primaryLabel.stringValue = stringValue
            repeatedLabel.stringValue = stringValue
            animationSignature = ""
            needsLayout = true
        }
    }

    var font = NSFont.systemFont(ofSize: 13) {
        didSet {
            primaryLabel.font = font
            repeatedLabel.font = font
            animationSignature = ""
            needsLayout = true
        }
    }

    var textColor = NSColor.labelColor {
        didSet {
            primaryLabel.textColor = textColor
            repeatedLabel.textColor = textColor
        }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = true

        contentView.wantsLayer = true
        addSubview(contentView)

        primaryLabel.horizontalAlignment = .leading
        repeatedLabel.horizontalAlignment = .leading
        contentView.addSubview(primaryLabel)
        contentView.addSubview(repeatedLabel)

        edgeFadeMask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        edgeFadeMask.locations = [0, 0.08, 0.92, 1]
        edgeFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let textWidth = ceil(
            singleLineTypographicWidth(
                text: stringValue,
                font: font
            )
        ) + 2
        let availableWidth = max(
            0,
            bounds.width - CompactMarqueeMetrics.edgeInset * 2
        )
        let shouldScroll =
            active
            && !reduceMotion
            && CompactMarqueeMetrics.needsScrolling(
                textWidth: textWidth,
                viewportWidth: bounds.width
            )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFadeMask.frame = bounds

        if shouldScroll {
            let cycleWidth = textWidth
                + CompactMarqueeMetrics.repeatGap
            contentView.frame = NSRect(
                x: CompactMarqueeMetrics.edgeInset,
                y: 0,
                width: cycleWidth + textWidth,
                height: bounds.height
            )
            primaryLabel.frame = NSRect(
                x: 0,
                y: 0,
                width: textWidth,
                height: bounds.height
            )
            repeatedLabel.frame = NSRect(
                x: cycleWidth,
                y: 0,
                width: textWidth,
                height: bounds.height
            )
            repeatedLabel.isHidden = false
            layer?.mask = edgeFadeMask
        } else {
            contentView.frame = NSRect(
                x: CompactMarqueeMetrics.edgeInset,
                y: 0,
                width: availableWidth,
                height: bounds.height
            )
            primaryLabel.frame = contentView.bounds
            repeatedLabel.isHidden = true
            layer?.mask = nil
        }
        CATransaction.commit()

        updateAnimation(
            shouldScroll: shouldScroll,
            textWidth: textWidth
        )
    }

    func setReduceMotion(_ enabled: Bool) {
        guard reduceMotion != enabled else { return }
        reduceMotion = enabled
        animationSignature = ""
        needsLayout = true
    }

    func setActive(_ enabled: Bool) {
        guard active != enabled else { return }
        active = enabled
        animationSignature = ""
        needsLayout = true
    }

    private func updateAnimation(
        shouldScroll: Bool,
        textWidth: CGFloat
    ) {
        let signature = [
            stringValue,
            String(format: "%.2f", bounds.width),
            shouldScroll ? "scroll" : "static"
        ].joined(separator: "|")

        guard signature != animationSignature else { return }
        animationSignature = signature
        contentView.layer?.removeAnimation(
            forKey: Self.animationKey
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.layer?.setAffineTransform(.identity)
        CATransaction.commit()

        guard shouldScroll,
              let layer = contentView.layer
        else {
            return
        }

        let distance = textWidth + CompactMarqueeMetrics.repeatGap
        let animation = CABasicAnimation(
            keyPath: "transform.translation.x"
        )
        animation.fromValue = 0
        animation.toValue = -distance
        animation.duration = CompactMarqueeMetrics.cycleDuration(
            textWidth: textWidth
        )
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(animation, forKey: Self.animationKey)
    }
}

struct ExpandedTextLayout {
    var kickerY: CGFloat
    var titleY: CGFloat
    var detailY: CGFloat
    var statusDotY: CGFloat
}

let expandedSupportingLineHeight: CGFloat = 18
let expandedStatusLineHeight: CGFloat = 26
let expandedTextRowGap: CGFloat = 4
let expandedStatusDotSide: CGFloat = 6

func centeredExpandedTextLayout(
    surfaceHeight: CGFloat
) -> ExpandedTextLayout {
    let stackHeight =
        expandedSupportingLineHeight * 2
        + expandedStatusLineHeight
        + expandedTextRowGap * 2
    let stackBottom = (surfaceHeight - stackHeight) / 2
    let detailY = stackBottom
    let titleY =
        detailY
        + expandedSupportingLineHeight
        + expandedTextRowGap
    let kickerY =
        titleY
        + expandedStatusLineHeight
        + expandedTextRowGap

    return ExpandedTextLayout(
        kickerY: kickerY,
        titleY: titleY,
        detailY: detailY,
        statusDotY:
            kickerY
            + (expandedSupportingLineHeight - expandedStatusDotSide) / 2
    )
}

func rgba(
    _ red: Float,
    _ green: Float,
    _ blue: Float,
    _ alpha: Float = 1
) -> SIMD4<Float> {
    SIMD4<Float>(red, green, blue, alpha)
}

struct OrbStyle {
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
    var speed: Float
    var speedFloor: Float
    var motionCycle: Float
    var tempo: Float
    var response: Float
    var energy: Float
    var turbulence: Float
    var pulse: Float
    var desaturation: Float
    var volume: Float
    var refraction: Float
    var compression: Float = 0

    mutating func approach(
        _ target: OrbStyle,
        factor: Float
    ) {
        primary += (target.primary - primary) * factor
        secondary += (target.secondary - secondary) * factor
        accent += (target.accent - accent) * factor
        speed += (target.speed - speed) * factor
        speedFloor += (target.speedFloor - speedFloor) * factor
        motionCycle += (target.motionCycle - motionCycle) * factor
        tempo += (target.tempo - tempo) * factor
        response += (target.response - response) * factor
        energy += (target.energy - energy) * factor
        turbulence += (target.turbulence - turbulence) * factor
        pulse += (target.pulse - pulse) * factor
        desaturation += (target.desaturation - desaturation) * factor
        volume += (target.volume - volume) * factor
        refraction += (target.refraction - refraction) * factor
        compression += (target.compression - compression) * factor
    }
}

func motionSpeedMultiplier(
    elapsed: Float,
    speedFloor: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let cyclePosition =
        max(elapsed, 0)
        .truncatingRemainder(dividingBy: safeCycle)
        / safeCycle
    let envelope =
        0.5
        - 0.5 * cos(cyclePosition * 2 * .pi)
    let clampedFloor = min(max(speedFloor, 0), 1)
    return clampedFloor + (1 - clampedFloor) * envelope
}

func contextCompressionPulse(
    elapsed: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let cyclePosition =
        max(elapsed, 0)
        .truncatingRemainder(dividingBy: safeCycle)
        / safeCycle
    return 0.5 - 0.5 * cos(cyclePosition * 2 * .pi)
}

func contextCompressionBounce(
    elapsed: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let phase =
        max(elapsed, 0)
        .truncatingRemainder(dividingBy: safeCycle)
        / safeCycle

    func raisedCosinePulse(
        center: Float,
        halfWidth: Float
    ) -> Float {
        let distance = abs(phase - center)
        guard distance < halfWidth else { return 0 }
        return 0.5 + 0.5 * cos(.pi * distance / halfWidth)
    }

    let primary = raisedCosinePulse(
        center: 0.34,
        halfWidth: 0.20
    )
    let rebound =
        raisedCosinePulse(
            center: 0.64,
            halfWidth: 0.14
        ) * 0.46
    return max(primary, rebound)
}

struct OrbUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var motionPhase: Float

    var energy: Float
    var turbulence: Float
    var pulse: Float
    var desaturation: Float

    var volume: Float
    var refraction: Float
    var tempo: Float
    var motionEnergy: Float

    var compression: Float
    var compressionPulse: Float
    var compressionBounce: Float
    var reserved1: Float

    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
}

let orbMotionSpeedScale: Float = 16.0
let orbRotationPhaseGain: Float = 1.45
let orbFluidPhaseGain: Float = 2.80
let orbSurfacePhaseGain: Float = 2.20
let contextCompressionCycle: Float = 3.2
let orbSphereRadius: Float = 0.535

private let orbShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct OrbUniforms {
    float2 resolution;
    float time;
    float motionPhase;

    float energy;
    float turbulence;
    float pulse;
    float desaturation;

    float volume;
    float refraction;
    float tempo;
    float motionEnergy;

    float compression;
    float compressionPulse;
    float compressionBounce;
    float reserved1;

    float4 primary;
    float4 secondary;
    float4 accent;
};

vertex VertexOut orbVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + float2(1.0, 0.0)), u.x),
        mix(hash21(i + float2(0.0, 1.0)), hash21(i + 1.0), u.x),
        u.y
    );
}

float softBand(float distance, float width) {
    float normalized = distance / max(width, 0.0001);
    return exp(-normalized * normalized);
}

float2 rotate2D(float2 value, float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return float2(
        value.x * cosine - value.y * sine,
        value.x * sine + value.y * cosine
    );
}

float3 rotateVolume(float3 value, float time) {
    value.xz = rotate2D(value.xz, time * 0.31 + 0.42);
    value.xy = rotate2D(value.xy, -time * 0.23 - 0.18);
    value.yz = rotate2D(value.yz, time * 0.17 + 0.28);
    return value;
}

float fluidField(
    float3 point,
    float time,
    float turbulence
) {
    float3 warped = point;
    warped.x += sin(point.y * 3.2 + time * 1.10) *
        (0.10 + turbulence * 0.10);
    warped.y += sin(point.z * 3.8 - time * 0.84) *
        (0.09 + turbulence * 0.12);
    warped.z += cos(point.x * 4.1 + time * 0.72) *
        (0.08 + turbulence * 0.11);

    float broad =
        sin(warped.x * 3.8 + time * 0.55) +
        sin(warped.y * 4.4 - time * 0.47) +
        sin(warped.z * 4.0 + time * 0.38);
    float detail =
        sin((warped.x + warped.y) * 7.2 - time * 0.92) +
        cos((warped.y - warped.z) * 6.1 + time * 0.68);

    return broad * 0.30 + detail * 0.13;
}

fragment float4 orbFragment(
    VertexOut in [[stage_in]],
    constant OrbUniforms &u [[buffer(0)]]
) {
    float2 p = (in.uv - 0.5) * 2.0;
    p.x *= u.resolution.x / max(u.resolution.y, 1.0);

    float rotationTime =
        u.motionPhase * \(orbRotationPhaseGain);
    float fluidTime =
        u.motionPhase * \(orbFluidPhaseGain);
    float surfaceTime =
        u.motionPhase * \(orbSurfacePhaseGain);
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float compressionAmount =
        u.compression *
        (
            0.20 +
            u.compressionPulse * 0.62 +
            u.compressionBounce * 0.28
        );
    float wholeSphereCompression =
        u.compression * u.compressionBounce;
    float directionalPressure =
        0.5 +
        0.5 * cos(angle * 2.0 + u.time * 0.42);
    float animatedTurbulence =
        u.turbulence * (0.84 + u.motionEnergy * 0.20);
    float breathing =
        sin(u.time * u.tempo) *
        (0.006 + u.pulse * 0.010);
    float sphereRadius =
        \(orbSphereRadius) +
        breathing -
        compressionAmount *
        (0.034 + directionalPressure * 0.018) -
        wholeSphereCompression * 0.050;
    float sphereDistance = abs(radius - sphereRadius);

    if (radius > sphereRadius + 0.18) {
        return float4(0.0);
    }

    float3 primary = u.primary.rgb;
    float3 secondary = u.secondary.rgb;
    float3 accent = u.accent.rgb;

    float normalizedRadius = radius / max(sphereRadius, 0.001);
    float inside = 1.0 - step(1.0, normalizedRadius);
    float zExtent = sqrt(max(0.0, 1.0 - normalizedRadius * normalizedRadius));
    float3 normal = normalize(float3(
        p / max(sphereRadius, 0.001),
        zExtent
    ));

    float fresnel = pow(
        saturate(1.0 - max(normal.z, 0.0)),
        2.25
    );
    float rim = smoothstep(0.10, 0.96, fresnel);
    float3 keyLight = normalize(float3(-0.48, 0.64, 0.82));
    float specular = pow(
        saturate(dot(normal, keyLight)),
        38.0
    );

    float3 volumeColor = float3(0.0);
    float volumeAlpha = 0.0;
    constexpr int sampleCount = 20;

    for (int index = 0; index < sampleCount; ++index) {
        float samplePosition =
            (float(index) + 0.5) / float(sampleCount);
        float sampleZ = mix(
            -zExtent,
            zExtent,
            samplePosition
        );
        float3 samplePoint = float3(
            p / max(sphereRadius, 0.001),
            sampleZ
        );
        float inwardScale =
            1.0 +
            compressionAmount *
            (
                0.18 +
                0.16 *
                (1.0 - abs(sampleZ))
            );
        samplePoint.xy *= inwardScale;
        samplePoint.z *=
            1.0 + compressionAmount * 0.12;
        samplePoint = rotateVolume(
            samplePoint,
            rotationTime *
                (0.72 + animatedTurbulence * 0.42)
        );

        float field = fluidField(
            samplePoint * (1.16 + animatedTurbulence * 0.22),
            fluidTime,
            animatedTurbulence
        );
        float ribbon = exp(
            -abs(field) * (5.6 - u.volume * 1.8)
        );
        float filament = exp(
            -abs(
                field +
                sin(
                    samplePoint.x * 6.0 -
                    samplePoint.z * 4.0 +
                    fluidTime
                ) * 0.20
            ) * 12.0
        );
        float depthFade =
            0.46 +
            0.54 * sin(samplePosition * M_PI_F);
        float density =
            (ribbon * 0.62 + filament * 0.52) *
            depthFade *
            (0.018 + u.volume * 0.020) *
            (1.0 + compressionAmount * 0.46);

        float colorPhase = fract(
            samplePosition * 0.78 +
            field * 0.15 +
            angle / (2.0 * M_PI_F) -
            fluidTime * 0.035
        );
        float3 sampleColor =
            colorPhase < 0.5
            ? mix(primary, secondary, colorPhase * 2.0)
            : mix(
                secondary,
                accent,
                (colorPhase - 0.5) * 2.0
            );

        float remaining = 1.0 - volumeAlpha;
        volumeColor +=
            remaining *
            sampleColor *
            density *
            (1.65 + u.energy * 1.12);
        volumeAlpha += remaining * density;
    }

    volumeColor *= inside;
    volumeAlpha *= inside;

    float normalizedX = p.x / max(sphereRadius, 0.001);
    float normalizedY = p.y / max(sphereRadius, 0.001);
    float projectedWaveA =
        normalizedY -
        sin(
            normalizedX * (4.2 + animatedTurbulence * 1.8) +
            surfaceTime * 1.55 +
            zExtent * 2.1
        ) * (0.17 + animatedTurbulence * 0.08);
    float projectedWaveB =
        normalizedX +
        cos(
            normalizedY * (4.8 + animatedTurbulence * 1.2) -
            surfaceTime * 1.12 -
            zExtent * 1.7
        ) * (0.15 + animatedTurbulence * 0.07);
    float projectedRibbonA = softBand(
        projectedWaveA,
        0.065 + animatedTurbulence * 0.020
    );
    float projectedRibbonB = softBand(
        projectedWaveB,
        0.080 + animatedTurbulence * 0.018
    );
    float projectedRibbon =
        inside *
        (projectedRibbonA * 0.72 + projectedRibbonB * 0.44) *
        (0.38 + zExtent * 0.62);
    float inwardFront = mix(
        0.92,
        0.18,
        u.compressionPulse
    );
    float inwardBand =
        exp(
            -abs(normalizedRadius - inwardFront) *
            (16.0 + u.compressionPulse * 8.0)
        ) *
        inside *
        u.compression;
    float compressedCore =
        exp(-normalizedRadius * 5.2) *
        inside *
        u.compression *
        u.compressionPulse;
    projectedRibbon +=
        inwardBand *
        (0.36 + u.compressionPulse * 0.28);
    float projectedPhase =
        0.5 +
        0.5 * sin(
            angle * 2.4 -
            surfaceTime * 1.3 +
            zExtent * 3.4
        );
    float3 projectedColor = mix(
        mix(primary, secondary, projectedPhase),
        accent,
        saturate(
            projectedRibbonB * 0.44 +
            inwardBand * 0.72 +
            compressedCore * 0.26
        )
    );

    float chromaRed = softBand(
        abs(radius - sphereRadius - 0.006 * u.refraction),
        0.012 + u.refraction * 0.005
    );
    float chromaGreen = softBand(
        abs(radius - sphereRadius),
        0.011
    );
    float chromaBlue = softBand(
        abs(radius - sphereRadius + 0.008 * u.refraction),
        0.014 + u.refraction * 0.004
    );
    float3 chromaticRim = float3(
        chromaRed,
        chromaGreen,
        chromaBlue
    );
    chromaticRim *= mix(
        primary,
        accent,
        0.5 +
            0.5 *
            sin(angle * 2.0 - surfaceTime * 1.2)
    );

    float caustic =
        pow(
            max(
                0.0,
                0.5 +
                0.5 *
                cos(
                    angle * 1.4 -
                    surfaceTime * 1.8 -
                    0.7
                )
            ),
            18.0
        ) *
        softBand(sphereDistance, 0.026);
    float halo = exp(
        -sphereDistance * (12.0 - u.energy * 1.8)
    );

    float glassTint = inside * (
        0.035 +
        rim * 0.14 +
        specular * 0.24
    );
    float3 glassColor =
        mix(primary, accent, fresnel) * glassTint +
        float3(0.72, 0.86, 1.0) * specular * 0.54;

    float3 color =
        volumeColor * (1.18 + u.volume * 0.74) +
        projectedColor *
            projectedRibbon *
            (0.32 + u.volume * 0.64) +
        mix(primary, secondary, projectedPhase) *
            inside *
            zExtent *
            0.035 *
            u.volume +
        glassColor +
        chromaticRim * (0.34 + u.refraction * 0.50) +
        accent * caustic * (0.60 + u.energy * 0.72) +
        mix(secondary, accent, 0.76) *
            (
                inwardBand * 0.34 +
                compressedCore * 0.24
            ) +
        mix(primary, secondary, 0.5) *
            halo *
            0.075 *
            u.energy;

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    color = mix(color, float3(luma), saturate(u.desaturation));

    float alpha =
        volumeAlpha * (0.82 + u.volume * 0.42) +
        projectedRibbon * (0.18 + u.volume * 0.28) +
        inwardBand * 0.12 +
        compressedCore * 0.08 +
        rim * inside * (0.24 + u.refraction * 0.30) +
        specular * inside * 0.48 +
        max(max(chromaRed, chromaGreen), chromaBlue) * 0.64 +
        halo * 0.10 * u.energy;

    alpha *= 1.0 - smoothstep(
        sphereRadius + 0.12,
        sphereRadius + 0.18,
        radius
    );
    color *=
        0.94 +
        0.06 *
        sin(u.time * u.tempo * 0.78) *
        u.pulse;

    return float4(
        max(color, 0.0),
        saturate(alpha)
    );
}
"""

private final class OrbRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()

    private var currentStyle: OrbStyle
    private var targetStyle: OrbStyle
    private var activeState: ActivityState
    private var reduceMotion = false
    private var stateElapsed: Float = 0
    private var motionPhase: Float = 0

    init?(
        view: MTKView,
        initialState: ActivityState
    ) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.wantsLayer = true
        view.layer?.isOpaque = false

        do {
            let library = try device.makeLibrary(
                source: orbShaderSource,
                options: nil
            )
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(
                name: "orbVertex"
            )
            descriptor.fragmentFunction = library.makeFunction(
                name: "orbFragment"
            )
            descriptor.colorAttachments[0].pixelFormat =
                view.colorPixelFormat

            if let attachment = descriptor.colorAttachments[0] {
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor =
                    .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor =
                    .oneMinusSourceAlpha
            }

            pipelineState = try device.makeRenderPipelineState(
                descriptor: descriptor
            )
        } catch {
            fputs(
                "Unable to compile Metal shader: \\(error)\\n",
                stderr
            )
            return nil
        }

        self.commandQueue = commandQueue
        currentStyle = initialState.orbStyle
        targetStyle = initialState.orbStyle
        activeState = initialState
        super.init()
        view.delegate = self
    }

    func setState(_ state: ActivityState) {
        if state != activeState {
            activeState = state
            stateElapsed = 0
        }
        targetStyle = state.orbStyle
        if reduceMotion {
            currentStyle = targetStyle
        }
    }

    func setReduceMotion(
        _ enabled: Bool,
        in view: MTKView
    ) {
        guard reduceMotion != enabled else { return }
        reduceMotion = enabled
        if enabled {
            currentStyle = targetStyle
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.needsDisplay = true
        } else {
            stateElapsed = 0
            lastFrameTime = CACurrentMediaTime()
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        }
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor =
                view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              )
        else {
            return
        }

        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastFrameTime, 1.0 / 15.0))
        lastFrameTime = now

        if reduceMotion {
            currentStyle = targetStyle
        } else {
            let transitionFactor = min(
                1,
                delta * max(0.4, targetStyle.response)
            )
            currentStyle.approach(
                targetStyle,
                factor: transitionFactor
            )

            stateElapsed += delta
            let speedMultiplier = motionSpeedMultiplier(
                elapsed: stateElapsed,
                speedFloor: currentStyle.speedFloor,
                cycle: currentStyle.motionCycle
            )
            motionPhase +=
                delta
                * currentStyle.speed
                * speedMultiplier
                * orbMotionSpeedScale
            if motionPhase > 4096 {
                motionPhase.formTruncatingRemainder(
                    dividingBy: 4096
                )
            }
        }

        let motionEnergy = reduceMotion
            ? Float(0)
            : motionSpeedMultiplier(
                elapsed: stateElapsed,
                speedFloor: 0,
                cycle: currentStyle.motionCycle
            )
        let compressionPulse = reduceMotion
            ? Float(0.72)
            : contextCompressionPulse(
                elapsed: stateElapsed,
                cycle: contextCompressionCycle
            )
        let compressionBounce = reduceMotion
            ? Float(0.68)
            : contextCompressionBounce(
                elapsed: stateElapsed,
                cycle: contextCompressionCycle
            )

        var uniforms = OrbUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            time: reduceMotion
                ? 0.35
                : Float(now - startTime),
            motionPhase: motionPhase,
            energy: currentStyle.energy,
            turbulence: reduceMotion
                ? 0.04
                : currentStyle.turbulence,
            pulse: reduceMotion ? 0 : currentStyle.pulse,
            desaturation: currentStyle.desaturation,
            volume: currentStyle.volume,
            refraction: currentStyle.refraction,
            tempo: reduceMotion ? 0 : currentStyle.tempo,
            motionEnergy: motionEnergy,
            compression: currentStyle.compression,
            compressionPulse: compressionPulse,
            compressionBounce: compressionBounce,
            reserved1: 0,
            primary: currentStyle.primary,
            secondary: currentStyle.secondary,
            accent: currentStyle.accent
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<OrbUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private final class MetalOrbView: MTKView {
    private var orbRenderer: OrbRenderer?

    init(
        frame: NSRect,
        initialState: ActivityState
    ) {
        super.init(
            frame: frame,
            device: MTLCreateSystemDefaultDevice()
        )
        orbRenderer = OrbRenderer(
            view: self,
            initialState: initialState
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setState(_ state: ActivityState) {
        orbRenderer?.setState(state)
        if isPaused {
            needsDisplay = true
        }
    }

    func setReduceMotion(_ enabled: Bool) {
        orbRenderer?.setReduceMotion(enabled, in: self)
    }

    func redrawIfPaused() {
        if isPaused {
            needsDisplay = true
        }
    }
}

private final class IslandSurfaceView: NSView {
    private let materialView = NSVisualEffectView()
    private let tintView = NSView()

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 34
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        addSubview(materialView)

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.72)
            .cgColor
        tintView.layer?.borderColor = NSColor.white
            .withAlphaComponent(0.10)
            .cgColor
        tintView.layer?.borderWidth = 0.5
        addSubview(tintView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let radius = min(34, bounds.height / 2)
        layer?.cornerRadius = radius
        materialView.frame = bounds
        tintView.frame = bounds
        tintView.layer?.cornerRadius = radius
        tintView.layer?.cornerCurve = .continuous
    }
}

private final class RailTaskRowView: NSView {
    private let statusDot = NSView()
    private let nameLabel = CenteredSingleLineTextView()
    private var primary = false
    private var reduceMotion = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius =
            TaskRailMetrics.markerDotSize / 2
        addSubview(statusDot)

        nameLabel.font = demoFont(
            "AstaSans-Medium",
            size: 10.5,
            fallbackWeight: .medium
        )
        addSubview(nameLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let markerSize = TaskRailMetrics.markerDotSize
        let nameLeading = TaskRailMetrics.markerLeading
            + markerSize
            + TaskRailMetrics.markerToNameGap
        statusDot.frame = NSRect(
            x: TaskRailMetrics.markerLeading,
            y: (bounds.height - markerSize) / 2,
            width: markerSize,
            height: markerSize
        )
        nameLabel.frame = NSRect(
            x: nameLeading,
            y: 0,
            width: max(
                0,
                bounds.width
                    - nameLeading
                    - TaskRailMetrics.trailingPadding
            ),
            height: bounds.height
        )
    }

    func configure(
        task: DemoTask,
        isPrimary: Bool,
        animated: Bool
    ) {
        nameLabel.stringValue = task.name
        nameLabel.textColor = NSColor.white.withAlphaComponent(
            isPrimary ? 0.96 : 0.56
        )
        nameLabel.shimmerEnabled = backgroundTaskTitleShowsSweep(
            state: task.state,
            isPrimary: isPrimary
        )
        nameLabel.setReduceMotion(reduceMotion)
        statusDot.layer?.backgroundColor = task.state.accentColor.cgColor
        statusDot.isHidden = isPrimary

        let primaryChanged = primary != isPrimary
        primary = isPrimary
        let targetAlpha: CGFloat = isPrimary ? 1 : 0.76
        let targetScale: CGFloat = isPrimary
            ? 1
            : TaskRailMetrics.inactiveScale

        if animated, primaryChanged {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = TaskRailMetrics.scrollDuration
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                animator().alphaValue = targetAlpha
            }

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = isPrimary
                ? TaskRailMetrics.inactiveScale
                : 1
            scale.toValue = targetScale
            scale.duration = TaskRailMetrics.scrollDuration
            scale.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                0.72,
                0.22,
                1
            )

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.setAffineTransform(
                CGAffineTransform(
                    scaleX: targetScale,
                    y: targetScale
                )
            )
            CATransaction.commit()
            layer?.add(scale, forKey: "wheel-emphasis")
        } else {
            alphaValue = targetAlpha
            layer?.removeAnimation(forKey: "wheel-emphasis")
            layer?.setAffineTransform(
                CGAffineTransform(
                    scaleX: targetScale,
                    y: targetScale
                )
            )
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(
            "\(task.name)，\(task.state.visibleStatusTitle)"
                + (isPrimary ? "，当前主任务" : "，后台任务")
        )
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        nameLabel.setReduceMotion(enabled)
    }

    func stopActivitySweep() {
        nameLabel.shimmerEnabled = false
    }
}

private final class TaskRailSelectionMorphView: NSView {
    private static let linePathAnimationKey = "selection-line-path"
    private static let lineOpacityAnimationKey = "selection-line-opacity"

    private var glassSurface: NSView!
    private var fallbackGlassView: NSVisualEffectView?
    private let glassContentView = NSView()
    private let fallbackTintView = NSView()
    private let lineLayer = CAShapeLayer()
    private var morphGeneration = 0

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        clipsToBounds = false

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .clear
            glassView.cornerRadius = TaskRailMetrics
                .selectionGlassCornerRadius
            glassView.wantsLayer = true
            glassContentView.autoresizingMask = [.width, .height]
            glassView.contentView = glassContentView
            glassSurface = glassView
        } else {
            let materialView = NSVisualEffectView()
            materialView.material = .underWindowBackground
            materialView.blendingMode = .withinWindow
            materialView.state = .active
            materialView.wantsLayer = true
            materialView.layer?.masksToBounds = true
            fallbackGlassView = materialView
            glassSurface = materialView

            fallbackTintView.wantsLayer = true
            fallbackTintView.autoresizingMask = [.width, .height]
            materialView.addSubview(fallbackTintView)
        }

        glassSurface.alphaValue = 0
        addSubview(glassSurface)

        lineLayer.fillColor = NSColor.white.cgColor
        layer?.addSublayer(lineLayer)

        setAccessibilityHidden(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.frame = bounds
        CATransaction.commit()
    }

    func setLine(
        frame: NSRect,
        accentColor: NSColor,
        cancelAnimations: Bool = false
    ) {
        if cancelAnimations {
            removeMorphAnimations()
        }
        let path = selectionLinePath(for: frame)
        setGlassFrame(
            frame,
            cornerRadius: TaskRailMetrics.selectedMarkerCornerRadius,
            alpha: 0
        )
        setGlassTint(accentColor)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.path = path
        lineLayer.fillColor = accentColor.cgColor
        lineLayer.opacity = frame.isEmpty ? 0 : 1
        CATransaction.commit()
        isHidden = frame.isEmpty
    }

    func animate(
        from oldLineFrame: NSRect,
        to newLineFrame: NSRect,
        oldAccentColor: NSColor,
        newAccentColor: NSColor
    ) {
        guard !oldLineFrame.isEmpty,
              !newLineFrame.isEmpty
        else {
            setLine(
                frame: newLineFrame,
                accentColor: newAccentColor,
                cancelAnimations: true
            )
            return
        }

        let oldGlassFrame = taskRailSelectionGlassFrame(
            markerFrame: oldLineFrame,
            containerWidth: bounds.width
        )
        let newGlassFrame = taskRailSelectionGlassFrame(
            markerFrame: newLineFrame,
            containerWidth: bounds.width
        )
        let keyTimes: [NSNumber] = [
            0,
            TaskRailMetrics.selectionExpandedKeyTime,
            TaskRailMetrics.selectionCollapseKeyTime,
            1
        ]

        removeMorphAnimations()
        morphGeneration += 1
        let generation = morphGeneration
        setGlassFrame(
            oldLineFrame,
            cornerRadius: TaskRailMetrics.selectedMarkerCornerRadius,
            alpha: 0
        )
        setGlassTint(oldAccentColor)
        isHidden = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.path = selectionLinePath(for: newLineFrame)
        lineLayer.fillColor = newAccentColor.cgColor
        lineLayer.opacity = 1
        CATransaction.commit()

        let linePathAnimation = CAKeyframeAnimation(keyPath: "path")
        linePathAnimation.values = [
            selectionLinePath(for: oldLineFrame),
            selectionLinePath(for: oldLineFrame),
            selectionLinePath(for: newLineFrame),
            selectionLinePath(for: newLineFrame)
        ]
        linePathAnimation.keyTimes = keyTimes
        linePathAnimation.duration = TaskRailMetrics.selectionMorphDuration
        lineLayer.add(
            linePathAnimation,
            forKey: Self.linePathAnimationKey
        )

        let lineOpacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        lineOpacityAnimation.values = [1, 0, 0, 1]
        lineOpacityAnimation.keyTimes = keyTimes
        lineOpacityAnimation.duration = TaskRailMetrics.selectionMorphDuration
        lineLayer.add(
            lineOpacityAnimation,
            forKey: Self.lineOpacityAnimationKey
        )

        let expandDuration = TaskRailMetrics.selectionMorphDuration
            * TaskRailMetrics.selectionExpandedKeyTime.doubleValue
        let travelDuration = TaskRailMetrics.selectionMorphDuration
            * (
                TaskRailMetrics.selectionCollapseKeyTime.doubleValue
                    - TaskRailMetrics.selectionExpandedKeyTime.doubleValue
            )
        let collapseDuration = TaskRailMetrics.selectionMorphDuration
            * (1 - TaskRailMetrics.selectionCollapseKeyTime.doubleValue)

        animateGlass(
            to: oldGlassFrame,
            cornerRadius: TaskRailMetrics.selectionGlassCornerRadius,
            alpha: 1,
            duration: expandDuration
        ) { [weak self] in
            guard let self,
                  self.morphGeneration == generation
            else { return }
            self.setGlassTint(newAccentColor)
            self.animateGlass(
                to: newGlassFrame,
                cornerRadius: TaskRailMetrics.selectionGlassCornerRadius,
                alpha: 1,
                duration: travelDuration
            ) { [weak self] in
                guard let self,
                      self.morphGeneration == generation
                else { return }
                self.animateGlass(
                    to: newLineFrame,
                    cornerRadius: TaskRailMetrics
                        .selectedMarkerCornerRadius,
                    alpha: 0,
                    duration: collapseDuration
                )
            }
        }
    }

    private func selectionLinePath(for frame: NSRect) -> CGPath {
        return CGPath(
            roundedRect: frame,
            cornerWidth: TaskRailMetrics.selectedMarkerCornerRadius,
            cornerHeight: TaskRailMetrics.selectedMarkerCornerRadius,
            transform: nil
        )
    }

    private func removeMorphAnimations() {
        morphGeneration += 1
        glassSurface.layer?.removeAllAnimations()
        lineLayer.removeAnimation(forKey: Self.linePathAnimationKey)
        lineLayer.removeAnimation(forKey: Self.lineOpacityAnimationKey)
    }

    private func setGlassTint(_ accentColor: NSColor) {
        let tint = accentColor.withAlphaComponent(
            TaskRailMetrics.selectionGlassTintAlpha
        )
        if #available(macOS 26.0, *),
           let glassView = glassSurface as? NSGlassEffectView {
            glassView.tintColor = tint
        } else {
            fallbackTintView.layer?.backgroundColor = tint.cgColor
        }
    }

    private func setGlassFrame(
        _ frame: NSRect,
        cornerRadius: CGFloat,
        alpha: CGFloat
    ) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        glassSurface.frame = frame
        glassSurface.alphaValue = alpha
        setGlassCornerRadius(cornerRadius)
        glassContentView.frame = glassSurface.bounds
        fallbackTintView.frame = glassSurface.bounds
        NSAnimationContext.endGrouping()
    }

    private func setGlassCornerRadius(_ radius: CGFloat) {
        if #available(macOS 26.0, *),
           let glassView = glassSurface as? NSGlassEffectView {
            glassView.cornerRadius = radius
        } else {
            fallbackGlassView?.layer?.cornerRadius = radius
        }
    }

    private func animateGlass(
        to frame: NSRect,
        cornerRadius: CGFloat,
        alpha: CGFloat,
        duration: CFTimeInterval,
        completion: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                0.72,
                0.22,
                1
            )
            glassSurface.animator().frame = frame
            glassSurface.animator().alphaValue = alpha
            if #available(macOS 26.0, *),
               let glassView = glassSurface as? NSGlassEffectView {
                glassView.animator().cornerRadius = cornerRadius
            } else {
                fallbackGlassView?.layer?.cornerRadius = cornerRadius
            }
        } completionHandler: {
            completion?()
        }
    }
}

private final class TaskRailView: NSView {
    private let positionLabel = CenteredSingleLineTextView()
    private let typeLabel = CenteredSingleLineTextView()
    private let rowsViewport = NSView()
    private let rowsContentView = NSView()
    private let rows = (0..<4).map { _ in RailTaskRowView() }
    private let selectionMorphView = TaskRailSelectionMorphView()
    private let viewportMask = CAGradientLayer()
    private let overflowLabel = CenteredSingleLineTextView()
    private var currentTasks: [DemoTask] = []
    private var totalTaskCount = 0
    private var currentPrimaryID = 0
    private var currentSelectionAccent = NSColor.white
    private var windowStart = 0
    private var hasConfiguredRows = false
    private var reduceMotion = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        positionLabel.font = demoFont(
            "AstaSans-SemiBold",
            size: TaskRailMetrics.headerFontSize,
            fallbackWeight: .semibold
        )
        positionLabel.textColor = NSColor.white.withAlphaComponent(0.90)
        positionLabel.horizontalAlignment = .center
        addSubview(positionLabel)

        typeLabel.font = demoFont(
            "AstaSans-Medium",
            size: TaskRailMetrics.headerFontSize,
            fallbackWeight: .medium
        )
        typeLabel.textColor = NSColor.white.withAlphaComponent(0.44)
        typeLabel.horizontalAlignment = .center
        typeLabel.stringValue = "任务"
        addSubview(typeLabel)

        // Keep the native glass above the island surface but below task glyphs.
        // Text behind NSGlassEffectView is sampled and refracted; task content
        // remains a crisp foreground layer while the glass travels beneath it.
        addSubview(selectionMorphView)

        rowsViewport.wantsLayer = true
        rowsViewport.layer?.masksToBounds = true
        rowsViewport.layer?.mask = viewportMask
        addSubview(rowsViewport)

        rowsContentView.wantsLayer = true
        rowsViewport.addSubview(rowsContentView)
        rows.forEach(rowsContentView.addSubview)

        viewportMask.colors = [
            NSColor.black.withAlphaComponent(0.62).cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.black.withAlphaComponent(0.62).cgColor
        ]
        viewportMask.locations = [0, 0.18, 0.82, 1]
        viewportMask.startPoint = CGPoint(x: 0.5, y: 0)
        viewportMask.endPoint = CGPoint(x: 0.5, y: 1)

        overflowLabel.font = demoFont(
            "AstaSans-Medium",
            size: 9.5,
            fallbackWeight: .medium
        )
        overflowLabel.textColor = NSColor.white.withAlphaComponent(0.48)
        overflowLabel.horizontalAlignment = .center
        addSubview(overflowLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        selectionMorphView.frame = bounds

        let showsPagination = TaskRailMetrics.showsPagination(
            taskCount: totalTaskCount
        )
        let headerY = bounds.height
            - TaskRailMetrics.topPadding
            - TaskRailMetrics.headerHeight
        let headerLayout = centeredTaskRailHeaderLayout(
            containerWidth: bounds.width,
            y: headerY,
            height: TaskRailMetrics.headerHeight,
            taskWidth: ceil(
                singleLineTypographicWidth(
                    text: typeLabel.stringValue,
                    font: typeLabel.font
                )
            ) + 2,
            counterWidth: ceil(
                singleLineTypographicWidth(
                    text: positionLabel.stringValue,
                    font: positionLabel.font
                )
            ) + 2
        )
        typeLabel.frame = headerLayout.taskFrame
        positionLabel.frame = headerLayout.counterFrame
        typeLabel.isHidden = !showsPagination
        positionLabel.isHidden = !showsPagination

        let viewportHeight = TaskRailMetrics.viewportHeight(
            taskCount: totalTaskCount
        )

        rowsViewport.frame = NSRect(
            x: 0,
            y: TaskRailMetrics.viewportY(
                containerHeight: bounds.height,
                taskCount: totalTaskCount
            ),
            width: bounds.width,
            height: viewportHeight
        )
        viewportMask.frame = rowsViewport.bounds
        rowsViewport.layer?.mask = showsPagination
            ? viewportMask
            : nil

        let contentHeight = max(
            viewportHeight,
            CGFloat(currentTasks.count) * TaskRailMetrics.rowStep
                - TaskRailMetrics.rowGap
        )
        rowsContentView.frame = NSRect(
            x: 0,
            y:
                viewportHeight
                - contentHeight
                + CGFloat(windowStart) * TaskRailMetrics.rowStep,
            width: rowsViewport.bounds.width,
            height: contentHeight
        )

        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: 0,
                y:
                    contentHeight
                    - TaskRailMetrics.rowHeight
                    - CGFloat(index) * TaskRailMetrics.rowStep,
                width: rowsContentView.bounds.width,
                height: TaskRailMetrics.rowHeight
            )
        }

        selectionMorphView.setLine(
            frame: selectionLineFrame(),
            accentColor: currentSelectionAccent
        )
        overflowLabel.frame = NSRect(
            x: TaskRailMetrics.leadingPadding,
            y: TaskRailMetrics.bottomPadding,
            width: max(
                0,
                bounds.width
                    - TaskRailMetrics.leadingPadding
                    - TaskRailMetrics.trailingPadding
            ),
            height: TaskRailMetrics.footerHeight
        )
        overflowLabel.isHidden = !showsPagination
    }

    func configure(
        tasks: [DemoTask],
        primaryID: Int,
        animated: Bool
    ) {
        layoutSubtreeIfNeeded()
        let oldContentY = rowsContentView.frame.minY
        let oldSelectionFrame = selectionLineFrame()
        let oldSelectionAccent = currentSelectionAccent
        let shouldAnimate = animated && hasConfiguredRows

        let primaryIndex = tasks.firstIndex {
            $0.id == primaryID
        } ?? 0
        currentTasks = Array(tasks.prefix(rows.count))
        totalTaskCount = tasks.count
        currentPrimaryID = primaryID
        windowStart = railWindowStart(
            for: tasks,
            primaryID: primaryID
        )
        positionLabel.stringValue = "\(primaryIndex + 1) / \(tasks.count)"

        for (index, row) in rows.enumerated() {
            guard currentTasks.indices.contains(index) else {
                row.stopActivitySweep()
                row.isHidden = true
                row.setAccessibilityHidden(true)
                continue
            }
            let task = currentTasks[index]
            row.isHidden = false
            row.setAccessibilityHidden(
                index < windowStart
                    || index >= windowStart
                        + TaskRailMetrics.visibleRowCount
            )
            row.configure(
                task: task,
                isPrimary: task.id == primaryID,
                animated: shouldAnimate
            )
        }

        let visibleCount = min(
            TaskRailMetrics.visibleRowCount,
            tasks.count
        )
        let hiddenBefore = windowStart
        let hiddenAfter = max(
            0,
            tasks.count - windowStart - visibleCount
        )
        switch (hiddenBefore, hiddenAfter) {
        case (0, 0):
            overflowLabel.stringValue = ""
        case (let before, 0):
            overflowLabel.stringValue = "前 \(before)"
        case (0, let after):
            overflowLabel.stringValue = "后 \(after)"
        case (let before, let after):
            overflowLabel.stringValue = "前 \(before) · 后 \(after)"
        }

        currentSelectionAccent = tasks[primaryIndex]
            .state
            .accentColor

        needsLayout = true
        layoutSubtreeIfNeeded()
        let newSelectionFrame = selectionLineFrame()

        if shouldAnimate {
            animateWheelShift(
                from: oldContentY,
                to: rowsContentView.frame.minY
            )
            selectionMorphView.animate(
                from: oldSelectionFrame,
                to: newSelectionFrame,
                oldAccentColor: oldSelectionAccent,
                newAccentColor: currentSelectionAccent
            )
        } else {
            selectionMorphView.setLine(
                frame: newSelectionFrame,
                accentColor: currentSelectionAccent,
                cancelAnimations: true
            )
        }
        hasConfiguredRows = true

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "任务列表，共 \(tasks.count) 个任务，"
                + "当前第 \(primaryIndex + 1) 个"
        )
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        rows.forEach { $0.setReduceMotion(enabled) }
    }

    private func selectionLineFrame() -> NSRect {
        guard let primaryIndex = currentTasks.firstIndex(
            where: { $0.id == currentPrimaryID }
        ) else {
            return .zero
        }

        let slot = primaryIndex - windowStart
        let rowY =
            rowsViewport.frame.minY
            + rowsViewport.bounds.height
            - TaskRailMetrics.rowHeight
            - CGFloat(slot) * TaskRailMetrics.rowStep
        return NSRect(
            x: TaskRailMetrics.markerLeading,
            y:
                rowY
                + (
                    TaskRailMetrics.rowHeight
                    - TaskRailMetrics.selectedMarkerHeight
                ) / 2,
            width: TaskRailMetrics.selectedMarkerWidth,
            height: TaskRailMetrics.selectedMarkerHeight
        )
    }

    private func animateWheelShift(
        from oldY: CGFloat,
        to newY: CGFloat
    ) {
        let delta = oldY - newY
        guard abs(delta) > 0.1,
              let layer = rowsContentView.layer
        else {
            return
        }

        layer.removeAnimation(forKey: "wheel-scroll")
        let direction: CGFloat = delta >= 0 ? 1 : -1

        let translation = CAKeyframeAnimation(
            keyPath: "transform.translation.y"
        )
        translation.values = [
            delta,
            delta,
            -direction * 1.4,
            0
        ]
        translation.keyTimes = [
            0,
            TaskRailMetrics.selectionExpandedKeyTime,
            0.88,
            1
        ]

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.74, 0.74, 0.94, 1]
        opacity.keyTimes = [
            0,
            TaskRailMetrics.selectionExpandedKeyTime,
            0.88,
            1
        ]

        let group = CAAnimationGroup()
        group.animations = [translation, opacity]
        group.duration = TaskRailMetrics.selectionMorphDuration
        group.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.22,
            0.72,
            0.22,
            1
        )
        layer.add(group, forKey: "wheel-scroll")
    }

}

private final class CompactDetailHitView: NSView {
    var onActivate: (() -> Void)?

    var interactionEnabled = false {
        didSet {
            isHidden = !interactionEnabled
            setAccessibilityEnabled(interactionEnabled)
            window?.invalidateCursorRects(for: self)
        }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("展开任务详情")
        setAccessibilityHelp("将灵动岛从紧凑态切换到最大态")
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard interactionEnabled else {
            super.mouseDown(with: event)
            return
        }
        onActivate?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard interactionEnabled else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func accessibilityPerformPress() -> Bool {
        guard interactionEnabled else { return false }
        onActivate?()
        return true
    }
}

private final class IslandContentView: NSView {
    private let shadowHost = NSView()
    private let surface = IslandSurfaceView()
    private let orbView: MetalOrbView
    private let primaryTextHost = NSView()
    private let kickerLabel = CenteredSingleLineTextView()
    private let titleLabel = CenteredSingleLineTextView()
    private let compactStatusLabel = CenteredSingleLineTextView()
    private let compactSeparatorLabel = CenteredSingleLineTextView()
    private let compactTitleMarquee = CompactMarqueeTextView()
    private let detailLabel = CenteredSingleLineTextView()
    private let statusDot = NSView()
    private let taskRailView = TaskRailView()
    private let compactCountLabel = CenteredSingleLineTextView()
    private let compactDetailHitView = CompactDetailHitView()

    var onCompactDetailClick: (() -> Void)?

    private var state: ActivityState
    private var tasks: [DemoTask]
    private var primaryID: Int
    private var presentationMode: IslandPresentationMode = .expanded
    private var reduceMotion = false

    override var isOpaque: Bool { false }

    init(
        initialTasks: [DemoTask],
        primaryID: Int
    ) {
        let initialTask = initialTasks.first {
            $0.id == primaryID
        } ?? initialTasks[0]
        tasks = initialTasks
        self.primaryID = initialTask.id
        state = initialTask.state
        orbView = MetalOrbView(
            frame: .zero,
            initialState: initialTask.state
        )
        super.init(frame: .zero)

        wantsLayer = true

        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.42
        shadowHost.layer?.shadowRadius =
            IslandPresentationMode.shadowRadius
        shadowHost.layer?.shadowOffset = CGSize(
            width: 0,
            height: IslandPresentationMode.shadowVerticalOffset
        )
        addSubview(shadowHost)

        shadowHost.addSubview(surface)
        surface.addSubview(orbView)

        primaryTextHost.wantsLayer = true
        surface.addSubview(primaryTextHost)

        kickerLabel.font = demoFont(
            "AstaSans-SemiBold",
            size: 11.5,
            fallbackWeight: .semibold
        )
        kickerLabel.textColor = NSColor.white.withAlphaComponent(0.46)
        primaryTextHost.addSubview(kickerLabel)

        titleLabel.font = demoFont(
            "AstaSans-SemiBold",
            size: 18,
            fallbackWeight: .semibold
        )
        titleLabel.textColor = .white
        primaryTextHost.addSubview(titleLabel)

        compactStatusLabel.font = demoFont(
            "AstaSans-SemiBold",
            size: IslandPresentationMode.compactTitleFontSize,
            fallbackWeight: .semibold
        )
        compactStatusLabel.textColor = .white
        primaryTextHost.addSubview(compactStatusLabel)

        compactSeparatorLabel.font = demoFont(
            "AstaSans-Medium",
            size: IslandPresentationMode.compactTitleFontSize,
            fallbackWeight: .medium
        )
        compactSeparatorLabel.textColor = NSColor.white
            .withAlphaComponent(0.58)
        compactSeparatorLabel.horizontalAlignment = .center
        compactSeparatorLabel.stringValue = "·"
        primaryTextHost.addSubview(compactSeparatorLabel)

        compactTitleMarquee.font = demoFont(
            "AstaSans-SemiBold",
            size: IslandPresentationMode.compactTitleFontSize,
            fallbackWeight: .semibold
        )
        compactTitleMarquee.textColor = .white
        primaryTextHost.addSubview(compactTitleMarquee)

        detailLabel.font = demoFont(
            "AstaSans-Regular",
            size: 11.5,
            fallbackWeight: .regular
        )
        primaryTextHost.addSubview(detailLabel)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3
        primaryTextHost.addSubview(statusDot)

        surface.addSubview(taskRailView)

        compactCountLabel.font = demoFont(
            "AstaSans-SemiBold",
            size: 10.5,
            fallbackWeight: .semibold
        )
        compactCountLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        compactCountLabel.horizontalAlignment = .center
        surface.addSubview(compactCountLabel)

        compactDetailHitView.onActivate = { [weak self] in
            self?.onCompactDetailClick?()
        }
        surface.addSubview(compactDetailHitView)

        compactCountLabel.stringValue = compactTaskCountText(initialTasks)
        applyPrimaryTask(initialTask)
        taskRailView.configure(
            tasks: initialTasks,
            primaryID: initialTask.id,
            animated: false
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let expansionProgress = currentExpansionProgress()
        let expandedSurfaceSize = mainExpandedSurfaceSize()
        let compactMetrics = IslandPresentationMode.compactLayoutMetrics(
            statusTitle: state.visibleStatusTitle,
            taskTitle: compactTitleMarquee.stringValue,
            taskCount: tasks.count
        )
        let mainSurfaceSize = NSSize(
            width: interpolate(
                from: compactMetrics.surfaceSize.width,
                to: expandedSurfaceSize.width,
                progress: expansionProgress
            ),
            height: interpolate(
                from: compactMetrics.surfaceSize.height,
                to: expandedSurfaceSize.height,
                progress: expansionProgress
            )
        )
        let mainCardFrame = NSRect(
            x: IslandPresentationMode.panelInset,
            y: IslandPresentationMode.panelInset,
            width: mainSurfaceSize.width,
            height: mainSurfaceSize.height
        )
        shadowHost.frame = mainCardFrame
        surface.frame = shadowHost.bounds

        let surfaceBounds = surface.bounds
        shadowHost.layer?.shadowPath = CGPath(
            roundedRect: shadowHost.bounds,
            cornerWidth: min(34, shadowHost.bounds.height / 2),
            cornerHeight: min(34, shadowHost.bounds.height / 2),
            transform: nil
        )

        let expandedOrbSide = max(
            IslandPresentationMode.compactOrbCanvasSide,
            min(
                124,
                max(68, expandedSurfaceSize.height - 10)
            )
        )
        let orbCanvasSide = interpolate(
            from: IslandPresentationMode.compactOrbCanvasSide,
            to: expandedOrbSide,
            progress: expansionProgress
        )
        let compactOrbCanvasLeading =
            IslandPresentationMode.compactOrbLeading
            - (
                IslandPresentationMode.compactOrbCanvasSide
                - IslandPresentationMode.compactOrbDiameter
            ) / 2
        let orbX = interpolate(
            from: compactOrbCanvasLeading,
            to: 4,
            progress: expansionProgress
        )
        orbView.frame = NSRect(
            x: orbX,
            y: (surfaceBounds.height - orbCanvasSide) / 2,
            width: orbCanvasSide,
            height: orbCanvasSide
        )
        orbView.redrawIfPaused()

        let compactTextStart =
            IslandPresentationMode.compactOrbLeading
            + IslandPresentationMode.compactOrbDiameter
            + IslandPresentationMode.compactTextGap
        let expandedTextStart = 4 + expandedOrbSide + 2
        let textStart = interpolate(
            from: compactTextStart,
            to: expandedTextStart,
            progress: expansionProgress
        )
        let railReservation = tasks.count > 1
            ? IslandPresentationMode.taskRailWidth * expansionProgress
            : 0
        let primaryWidth = max(
            0,
            surfaceBounds.width - railReservation
        )
        primaryTextHost.frame = NSRect(
            x: 0,
            y: 0,
            width: primaryWidth,
            height: surfaceBounds.height
        )
        let textWidth = max(
            0,
            primaryWidth - textStart - 18
        )
        let supportingAlpha = min(
            max((expansionProgress - 0.42) / 0.58, 0),
            1
        )
        let expandedTitleAlpha = min(
            max((expansionProgress - 0.18) / 0.82, 0),
            1
        )
        let compactContentAlpha = min(
            max((0.58 - expansionProgress) / 0.58, 0),
            1
        )
        let expandedTextLayout = centeredExpandedTextLayout(
            surfaceHeight: surfaceBounds.height
        )

        kickerLabel.alphaValue = supportingAlpha
        detailLabel.alphaValue = supportingAlpha
        statusDot.alphaValue = supportingAlpha
        titleLabel.alphaValue = expandedTitleAlpha
        compactStatusLabel.alphaValue = compactContentAlpha
        compactSeparatorLabel.alphaValue = compactContentAlpha
        compactTitleMarquee.alphaValue = compactContentAlpha
        taskRailView.alphaValue = tasks.count > 1
            ? supportingAlpha
            : 0
        compactCountLabel.alphaValue = tasks.count > 1
            ? compactContentAlpha
            : 0

        kickerLabel.frame = NSRect(
            x: textStart + 12,
            y: expandedTextLayout.kickerY,
            width: max(0, textWidth - 12),
            height: expandedSupportingLineHeight
        )
        statusDot.frame = NSRect(
            x: textStart,
            y: expandedTextLayout.statusDotY,
            width: expandedStatusDotSide,
            height: expandedStatusDotSide
        )
        let centeredStatusY =
            (surfaceBounds.height - expandedStatusLineHeight) / 2
        titleLabel.frame = NSRect(
            x: textStart,
            y: interpolate(
                from: centeredStatusY,
                to: expandedTextLayout.titleY,
                progress: expansionProgress
            ),
            width: textWidth,
            height: expandedStatusLineHeight
        )
        compactStatusLabel.frame = NSRect(
            x: IslandPresentationMode.compactTextLeading,
            y: 0,
            width: compactMetrics.statusWidth,
            height: surfaceBounds.height
        )
        compactSeparatorLabel.frame = NSRect(
            x: IslandPresentationMode.compactTextLeading
                + compactMetrics.statusWidth,
            y: 0,
            width: IslandPresentationMode.compactSeparatorWidth,
            height: surfaceBounds.height
        )
        let compactCountX = max(
            0,
            surfaceBounds.width
                - IslandPresentationMode.compactCountTrailing
                - compactMetrics.countWidth
        )
        compactTitleMarquee.frame = NSRect(
            x: compactMetrics.marqueeLeading,
            y: 0,
            width: max(
                0,
                compactCountX
                    - compactMetrics.countLeadingGap
                    - compactMetrics.marqueeLeading
            ),
            height: surfaceBounds.height
        )
        detailLabel.frame = NSRect(
            x: textStart,
            y: expandedTextLayout.detailY,
            width: textWidth,
            height: expandedSupportingLineHeight
        )
        taskRailView.frame = NSRect(
            x: max(
                0,
                surfaceBounds.width
                    - IslandPresentationMode.taskRailWidth
            ),
            y: 0,
            width: IslandPresentationMode.taskRailWidth,
            height: surfaceBounds.height
        )
        compactCountLabel.frame = NSRect(
            x: compactCountX,
            y: 0,
            width: compactMetrics.countWidth,
            height: surfaceBounds.height
        )
        let compactDetailHitX = max(
            0,
            compactCountX
                - IslandPresentationMode.compactCountLeadingGap / 2
        )
        compactDetailHitView.frame = NSRect(
            x: compactDetailHitX,
            y: 0,
            width: max(0, surfaceBounds.maxX - compactDetailHitX),
            height: surfaceBounds.height
        )
        shadowHost.layer?.shadowOpacity = Float(
            interpolate(
                from: 0.30,
                to: 0.42,
                progress: expansionProgress
            )
        )

    }

    func updateTasks(
        _ tasks: [DemoTask],
        primaryID: Int,
        animateSwitch: Bool
    ) {
        guard let nextTask = tasks.first(where: { $0.id == primaryID })
            ?? tasks.first
        else {
            return
        }

        let primaryChanged = self.primaryID != nextTask.id
        self.tasks = tasks
        self.primaryID = nextTask.id
        compactCountLabel.stringValue = compactTaskCountText(tasks)
        updateCompactDetailInteraction()

        applyPrimaryTask(nextTask)
        taskRailView.configure(
            tasks: tasks,
            primaryID: nextTask.id,
            animated: animateSwitch && primaryChanged && !reduceMotion
        )
        needsLayout = true
    }

    private func applyPrimaryTask(_ task: DemoTask) {
        state = task.state
        kickerLabel.stringValue = task.name
        titleLabel.stringValue = task.state.visibleStatusTitle
        compactStatusLabel.stringValue = task.state.visibleStatusTitle
        compactTitleMarquee.stringValue = task.name
        detailLabel.stringValue = task.state.currentOperation
        detailLabel.textColor = NSColor.white.withAlphaComponent(
            task.state.showsOperationSweep ? 0.42 : 0.64
        )
        detailLabel.shimmerEnabled = task.state.showsOperationSweep
        statusDot.layer?.backgroundColor = task.state.accentColor.cgColor
        orbView.setState(task.state)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "共 \(tasks.count) 个任务，当前主任务：\(task.name)，"
                + "状态：\(task.state.visibleStatusTitle)，"
                + "当前操作：\(task.state.currentOperation)"
        )
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        orbView.setReduceMotion(enabled)
        detailLabel.setReduceMotion(enabled)
        compactTitleMarquee.setReduceMotion(enabled)
        taskRailView.setReduceMotion(enabled)
    }

    func setPresentationMode(_ mode: IslandPresentationMode) {
        presentationMode = mode
        compactTitleMarquee.setActive(mode == .compact)
        updateCompactDetailInteraction()
        needsLayout = true
        setAccessibilityValue(mode.title)
    }

    private func updateCompactDetailInteraction() {
        compactDetailHitView.interactionEnabled =
            compactDetailExpansionEnabled(
                presentationMode: presentationMode,
                taskCount: tasks.count
            )
    }

    private func mainExpandedSurfaceSize() -> NSSize {
        let panelSize = tasks.count > 1
            ? IslandPresentationMode.multiTaskMainCardPanelSize
            : state.windowSize
        return NSSize(
            width: panelSize.width - IslandPresentationMode.panelInset * 2,
            height: panelSize.height - IslandPresentationMode.panelInset * 2
        )
    }

    private func currentExpansionProgress() -> CGFloat {
        let compactPanelHeight =
            IslandPresentationMode.compactSurfaceHeight
            + IslandPresentationMode.panelInset * 2
        let expandedHeight = IslandPresentationMode.expanded.panelSize(
            for: state,
            taskCount: tasks.count
        ).height
        let range = max(expandedHeight - compactPanelHeight, 1)
        return min(
            max((bounds.height - compactPanelHeight) / range, 0),
            1
        )
    }

    private func compactTaskCountText(_ tasks: [DemoTask]) -> String {
        "共\(tasks.count)项"
    }
}

private final class ActivityIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class IslandPanelController {
    private let panel: ActivityIslandPanel
    private let content: IslandContentView
    private weak var anchorWindow: NSWindow?
    private var reduceMotion = false
    private var presentationMode: IslandPresentationMode = .expanded

    var onCompactDetailClick: (() -> Void)?

    init(
        initialTasks: [DemoTask],
        primaryID: Int
    ) {
        let initialTask = initialTasks.first {
            $0.id == primaryID
        } ?? initialTasks[0]
        let initialSize = IslandPresentationMode.expanded.panelSize(
            for: initialTask.state,
            taskCount: initialTasks.count
        )
        content = IslandContentView(
            initialTasks: initialTasks,
            primaryID: initialTask.id
        )
        panel = ActivityIslandPanel(
            contentRect: NSRect(
                origin: .zero,
                size: initialSize
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.contentView = content

        content.onCompactDetailClick = { [weak self] in
            self?.onCompactDetailClick?()
        }

        panel.setContentSize(initialSize)
    }

    func attach(to window: NSWindow) {
        if let anchorWindow, anchorWindow !== window {
            anchorWindow.removeChildWindow(panel)
        }
        anchorWindow = window
        positionPanel(
            size: panel.frame.size,
            animated: false
        )
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    func update(
        tasks: [DemoTask],
        primaryID: Int,
        presentationMode: IslandPresentationMode,
        reduceMotion: Bool,
        animateSwitch: Bool
    ) {
        guard let primaryTask = tasks.first(where: { $0.id == primaryID })
            ?? tasks.first
        else {
            return
        }
        self.reduceMotion = reduceMotion
        let modeChanged = self.presentationMode != presentationMode
        self.presentationMode = presentationMode
        content.setReduceMotion(reduceMotion)
        content.setPresentationMode(presentationMode)
        content.updateTasks(
            tasks,
            primaryID: primaryTask.id,
            animateSwitch: animateSwitch
        )
        let duration: TimeInterval
        if modeChanged {
            duration = presentationMode.transitionDuration
        } else {
            duration = 0.44
        }
        positionPanel(
            size: presentationMode.panelSize(
                for: primaryTask.state,
                taskCount: tasks.count,
                taskTitle: primaryTask.name
            ),
            animated: !reduceMotion,
            duration: duration
        )
        if anchorWindow != nil {
            panel.orderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func positionPanel(
        size: NSSize,
        animated: Bool,
        duration: TimeInterval = 0.44
    ) {
        let targetFrame: NSRect
        if let anchorWindow {
            targetFrame = anchoredIslandFrame(
                size: size,
                anchorFrame: anchorWindow.frame
            )
        } else {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                return
            }
            let visibleFrame = screen.visibleFrame
            targetFrame = NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height - 6,
                width: size.width,
                height: size.height
            )
        }

        guard animated, panel.isVisible else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            panel.animator().setFrame(targetFrame, display: true)
        }
    }
}

@MainActor
private final class TaskEditorRowView: NSView, NSTextFieldDelegate {
    let index: Int

    var onNameChange: ((Int, String) -> Void)?
    var onStateChange: ((Int, ActivityState) -> Void)?
    var onSelect: ((Int) -> Void)?

    private let indexLabel: NSTextField
    private let nameField = NSTextField()
    private let statePopup = NSPopUpButton()
    private let selectButton = NSButton()

    override var isOpaque: Bool { false }

    init(index: Int) {
        self.index = index
        indexLabel = NSTextField(labelWithString: "\(index + 1)")
        super.init(frame: .zero)

        indexLabel.font = .monospacedDigitSystemFont(
            ofSize: 11,
            weight: .semibold
        )
        indexLabel.textColor = .secondaryLabelColor
        indexLabel.alignment = .center

        nameField.placeholderString = "输入任务名称"
        nameField.font = .systemFont(ofSize: 12)
        nameField.delegate = self
        nameField.setAccessibilityLabel("任务 \(index + 1) 名称")

        statePopup.addItems(withTitles: ActivityState.allCases.map(\.title))
        for (itemIndex, item) in statePopup.itemArray.enumerated() {
            item.tag = ActivityState.allCases[itemIndex].rawValue
        }
        statePopup.controlSize = .small
        statePopup.target = self
        statePopup.action = #selector(stateChanged(_:))
        statePopup.setAccessibilityLabel("任务 \(index + 1) 状态")

        selectButton.title = "切换"
        selectButton.bezelStyle = .rounded
        selectButton.controlSize = .small
        selectButton.target = self
        selectButton.action = #selector(selectPressed(_:))
        selectButton.setAccessibilityLabel("切换到任务 \(index + 1)")

        let stack = NSStackView(
            views: [
                indexLabel,
                nameField,
                statePopup,
                selectButton
            ]
        )
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 22),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            statePopup.widthAnchor.constraint(equalToConstant: 150),
            selectButton.widthAnchor.constraint(equalToConstant: 72)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        task: DemoTask,
        isPrimary: Bool,
        isEnabled: Bool
    ) {
        if nameField.currentEditor() == nil {
            nameField.stringValue = task.name
        }
        statePopup.selectItem(withTag: task.state.rawValue)
        nameField.isEnabled = isEnabled
        statePopup.isEnabled = isEnabled
        selectButton.isEnabled = isEnabled
        alphaValue = isEnabled ? 1 : 0.34

        selectButton.state = isPrimary ? .on : .off
        selectButton.title = isPrimary ? "主任务" : "切换"
        selectButton.bezelColor = isPrimary
            ? task.state.accentColor.withAlphaComponent(0.78)
            : nil
    }

    func controlTextDidChange(_ notification: Notification) {
        onNameChange?(index, nameField.stringValue)
    }

    @objc
    private func stateChanged(_ sender: NSPopUpButton) {
        guard let state = ActivityState(
            rawValue: sender.selectedTag()
        ) else {
            return
        }
        onStateChange?(index, state)
    }

    @objc
    private func selectPressed(_ sender: NSButton) {
        onSelect?(index)
    }
}

@MainActor
private final class DemoCoordinator: NSObject, NSWindowDelegate {
    private let demoWindowTitle = "灵动岛多任务 · 视觉与动效实验"
    private let island: IslandPanelController
    private let controlWindow: NSWindow
    private let taskCountControl: NSSegmentedControl
    private let reduceMotionCheckbox: NSButton
    private let presentationControl: NSSegmentedControl
    private let summaryLabel = NSTextField(labelWithString: "")

    private var taskRows: [TaskEditorRowView] = []
    private var allTasks: [DemoTask]
    private var taskCount = 3
    private var primaryID = 0

    override init() {
        let initialTasks = [
            DemoTask(
                id: 0,
                name: "灵动岛多任务视觉方案",
                state: .thinking
            ),
            DemoTask(
                id: 1,
                name: "修复 Widget 数据同步",
                state: .working
            ),
            DemoTask(
                id: 2,
                name: "发布前确认与验收",
                state: .awaitingConfirmation
            ),
            DemoTask(
                id: 3,
                name: "整理版本交接文档",
                state: .completed
            )
        ]
        allTasks = initialTasks
        island = IslandPanelController(
            initialTasks: Array(initialTasks.prefix(3)),
            primaryID: 0
        )

        controlWindow = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 720,
                height: 430
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable
            ],
            backing: .buffered,
            defer: false
        )

        taskCountControl = NSSegmentedControl(
            labels: ["1", "2", "3", "4"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        taskCountControl.selectedSegment = 2

        reduceMotionCheckbox = NSButton(
            checkboxWithTitle: "减少动态",
            target: nil,
            action: nil
        )
        presentationControl = NSSegmentedControl(
            labels: IslandPresentationMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        presentationControl.selectedSegment =
            IslandPresentationMode.expanded.rawValue

        super.init()

        island.onCompactDetailClick = { [weak self] in
            self?.expandCompactDetail()
        }

        configureControlWindow()
        island.attach(to: controlWindow)
        refreshControls()
        updateIsland(animateSwitch: false)
    }

    private func configureControlWindow() {
        controlWindow.title = demoWindowTitle
        controlWindow.isReleasedWhenClosed = false
        controlWindow.delegate = self
        controlWindow.center()
        controlWindow.setFrameOrigin(
            NSPoint(
                x: controlWindow.frame.origin.x,
                y: max(70, controlWindow.frame.origin.y - 150)
            )
        )

        let root = NSView(frame: controlWindow.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        controlWindow.contentView = root

        let title = NSTextField(
            labelWithString: "Codex 活动岛 · 多任务视觉实验"
        )
        title.font = demoFont(
            "AstaSans-SemiBold",
            size: 20,
            fallbackWeight: .semibold
        )

        let subtitle = NSTextField(
            wrappingLabelWithString:
                "纯模拟数据：编辑 1–4 个任务并独立选择状态，点击“切换”观察主任务内容、右侧滚轮任务列与 Metal 球同步更新。"
        )
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        let countTitle = NSTextField(labelWithString: "任务数量")
        countTitle.font = .systemFont(ofSize: 12, weight: .medium)
        let countRow = NSStackView(
            views: [
                countTitle,
                taskCountControl,
                NSView()
            ]
        )
        countRow.orientation = .horizontal
        countRow.alignment = .centerY
        countRow.spacing = 12

        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8
        for index in 0..<4 {
            let row = TaskEditorRowView(index: index)
            row.onNameChange = { [weak self] index, name in
                self?.updateTaskName(at: index, name: name)
            }
            row.onStateChange = { [weak self] index, state in
                self?.updateTaskState(at: index, state: state)
            }
            row.onSelect = { [weak self] index in
                self?.selectPrimaryTask(at: index)
            }
            taskRows.append(row)
            rowsStack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }

        reduceMotionCheckbox.state =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? .on
                : .off
        reduceMotionCheckbox.target = self
        reduceMotionCheckbox.action = #selector(optionsChanged(_:))

        presentationControl.target = self
        presentationControl.action = #selector(optionsChanged(_:))
        presentationControl.toolTip = "切换灵动岛最大态与紧凑态"

        taskCountControl.target = self
        taskCountControl.action = #selector(taskCountChanged(_:))
        taskCountControl.setAccessibilityLabel("模拟任务数量")

        summaryLabel.font = demoFont(
            "AstaSans-Medium",
            size: 11.5,
            fallbackWeight: .medium
        )
        summaryLabel.textColor = .secondaryLabelColor

        let optionsRow = NSStackView(
            views: [
                reduceMotionCheckbox,
                presentationControl,
                NSView(),
                summaryLabel
            ]
        )
        optionsRow.orientation = .horizontal
        optionsRow.alignment = .centerY
        optionsRow.spacing = 14

        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(
            views: [
                title,
                subtitle,
                countRow,
                rowsStack,
                separator,
                optionsRow
            ]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        countRow.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        optionsRow.translatesAutoresizingMaskIntoConstraints = false
        presentationControl.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 24
            ),
            stack.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -24
            ),
            stack.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: 24
            ),
            countRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            taskCountControl.widthAnchor.constraint(equalToConstant: 168),
            rowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            optionsRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presentationControl.widthAnchor.constraint(equalToConstant: 144)
        ])

        controlWindow.makeKeyAndOrderFront(nil)
    }

    @objc
    private func taskCountChanged(_ sender: NSSegmentedControl) {
        taskCount = sender.selectedSegment + 1
        let previousPrimary = primaryID
        if primaryID >= taskCount {
            primaryID = max(0, taskCount - 1)
        }
        refreshControls()
        updateIsland(animateSwitch: previousPrimary != primaryID)
    }

    @objc
    private func optionsChanged(_ sender: Any?) {
        updateIsland(animateSwitch: false)
    }

    private func expandCompactDetail() {
        guard presentationControl.selectedSegment
                == IslandPresentationMode.compact.rawValue
        else {
            return
        }
        presentationControl.selectedSegment =
            IslandPresentationMode.expanded.rawValue
        updateIsland(animateSwitch: false)
    }

    private func updateTaskName(at index: Int, name: String) {
        guard allTasks.indices.contains(index) else { return }
        allTasks[index].name = name
        refreshSummary()
        updateIsland(animateSwitch: false)
    }

    private func updateTaskState(
        at index: Int,
        state: ActivityState
    ) {
        guard allTasks.indices.contains(index) else { return }
        allTasks[index].state = state
        refreshControls()
        updateIsland(animateSwitch: false)
    }

    private func selectPrimaryTask(at index: Int) {
        guard index < taskCount else { return }
        primaryID = allTasks[index].id
        refreshControls()
        updateIsland(animateSwitch: true)
    }

    private func visibleTasks() -> [DemoTask] {
        Array(allTasks.prefix(taskCount)).enumerated().map {
            index, task in
            var task = task
            if task.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty {
                task.name = "未命名任务 \(index + 1)"
            }
            return task
        }
    }

    private func refreshControls() {
        for (index, row) in taskRows.enumerated() {
            row.configure(
                task: allTasks[index],
                isPrimary: allTasks[index].id == primaryID,
                isEnabled: index < taskCount
            )
        }
        refreshSummary()
    }

    private func refreshSummary() {
        let tasks = visibleTasks()
        let primaryTask = tasks.first {
            $0.id == primaryID
        } ?? tasks[0]
        let attention = taskAttentionCount(tasks)
        summaryLabel.stringValue =
            "当前：\(primaryTask.state.visibleStatusTitle)"
            + (attention > 0 ? " · \(attention) 个待处理" : "")
    }

    private func updateIsland(animateSwitch: Bool) {
        let tasks = visibleTasks()
        island.update(
            tasks: tasks,
            primaryID: primaryID,
            presentationMode: IslandPresentationMode(
                rawValue: presentationControl.selectedSegment
            ) ?? .expanded,
            reduceMotion: reduceMotionCheckbox.state == .on,
            animateSwitch: animateSwitch
        )
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

private func registerProjectFonts() {
    var directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()

    for _ in 0..<8 {
        let fontsDirectory = directory
            .appendingPathComponent("Resources/Fonts")
        if FileManager.default.fileExists(
            atPath: fontsDirectory.path
        ) {
            for name in [
                "AstaSans-Regular",
                "AstaSans-Medium",
                "AstaSans-SemiBold"
            ] {
                let url = fontsDirectory
                    .appendingPathComponent(name)
                    .appendingPathExtension("ttf")
                CTFontManagerRegisterFontsForURL(
                    url as CFURL,
                    .process,
                    nil
                )
            }
            return
        }
        directory.deleteLastPathComponent()
    }
}

private func demoFont(
    _ name: String,
    size: CGFloat,
    fallbackWeight: NSFont.Weight
) -> NSFont {
    NSFont(name: name, size: size)
        ?? NSFont.systemFont(
            ofSize: size,
            weight: fallbackWeight
        )
}

@MainActor
private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: DemoCoordinator?

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        registerProjectFonts()
        configureMainMenu()
        coordinator = DemoCoordinator()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出多任务 Demo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}

@main
private enum CodexActivityMultiTaskDemo {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = DemoAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
