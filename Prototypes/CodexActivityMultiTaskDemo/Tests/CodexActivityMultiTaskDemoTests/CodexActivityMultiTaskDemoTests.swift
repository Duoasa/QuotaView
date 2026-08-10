import AppKit
import XCTest
@testable import CodexActivityMultiTaskDemo

final class CodexActivityMultiTaskDemoTests: XCTestCase {
    func testStateSetMatchesConfirmedProductVocabulary() {
        XCTAssertEqual(
            ActivityState.allCases.map(\.title),
            [
                "待命",
                "思考中",
                "工作中",
                "正在压缩上下文",
                "待确认",
                "已完成",
                "出错",
                "不可用"
            ]
        )
        XCTAssertEqual(
            ActivityState.allCases.map(\.englishTitle),
            [
                "Standby",
                "Thinking",
                "Working",
                "Compacting Context",
                "Awaiting Confirmation",
                "Completed",
                "Error",
                "Unavailable"
            ]
        )
    }

    func testVisibleStatusLabelsMixOfficialAndDerivedSemantics() {
        XCTAssertEqual(
            ActivityState.allCases.map(\.visibleStatusTitle),
            [
                "空闲",
                "思考中",
                "工作中",
                "正在压缩上下文",
                "等待批准",
                "已完成",
                "失败",
                "未载入"
            ]
        )
        XCTAssertEqual(
            Set(ActivityState.allCases.map(\.visibleStatusTitle)).count,
            ActivityState.allCases.count
        )
        XCTAssertEqual(
            ActivityState.allCases.map(\.statusSemanticSource),
            [
                .codex,
                .derived,
                .derived,
                .derived,
                .codex,
                .codex,
                .codex,
                .codex
            ]
        )
        XCTAssertEqual(
            ActivityState.allCases.map(\.officialStatusIdentifier),
            [
                "idle",
                "active · inProgress",
                "active · inProgress",
                "active · inProgress",
                "active · waitingOnApproval",
                "completed",
                "failed",
                "notLoaded"
            ]
        )
    }

    func testCurrentOperationDoesNotRepeatVisibleStatus() {
        for state in ActivityState.allCases {
            XCTAssertFalse(state.currentOperation.isEmpty)
            XCTAssertNotEqual(
                state.currentOperation,
                state.visibleStatusTitle
            )
        }
    }

    func testOperationSweepOnlyRunsForContinuingWork() {
        XCTAssertEqual(
            ActivityState.allCases.map(\.showsOperationSweep),
            [
                false,
                true,
                true,
                true,
                false,
                false,
                false,
                true
            ]
        )
    }

    func testIslandLabelsUseSingleLineTailTruncation() {
        let maximumWidth: CGFloat = 80
        let line = makeTruncatedSingleLine(
            text: "一个用于验证尾部缩略的超长 Codex 窗口名称",
            font: NSFont.systemFont(ofSize: 14),
            color: .white,
            maximumWidth: maximumWidth
        )
        let width = CGFloat(
            CTLineGetTypographicBounds(
                line,
                nil,
                nil,
                nil
            )
        )

        XCTAssertLessThanOrEqual(
            width,
            maximumWidth + 0.5
        )
    }

    func testCompactPresentationUsesAdaptiveWidthMetrics() {
        XCTAssertEqual(IslandPresentationMode.compactSurfaceHeight, 52)
        XCTAssertEqual(
            IslandPresentationMode.compactOrbInset,
            12
        )
        XCTAssertEqual(
            IslandPresentationMode.compactOrbDiameter,
            28
        )
        XCTAssertEqual(
            IslandPresentationMode.compactOrbLeading,
            12
        )
        XCTAssertEqual(
            IslandPresentationMode.compactTextGap,
            14
        )
        XCTAssertEqual(
            IslandPresentationMode.compactTitleFontSize,
            14
        )
        XCTAssertEqual(
            IslandPresentationMode.compactTextMeasurementPadding,
            2
        )
        XCTAssertEqual(IslandPresentationMode.compactSeparatorWidth, 12)
        XCTAssertEqual(IslandPresentationMode.compactTitleMinimumWidth, 44)
        XCTAssertEqual(IslandPresentationMode.compactTitleMaximumWidth, 128)
        XCTAssertEqual(IslandPresentationMode.compactCountWidth, 54)
        XCTAssertEqual(IslandPresentationMode.compactCountTrailing, 12)
        XCTAssertEqual(IslandPresentationMode.compactCountLeadingGap, 12)
        XCTAssertEqual(
            IslandPresentationMode.compactOrbCanvasSide
                * CGFloat(orbSphereRadius),
            28,
            accuracy: 0.0001
        )
        XCTAssertLessThanOrEqual(
            IslandPresentationMode.requiredShadowInset,
            IslandPresentationMode.panelInset,
            "Rounded shadow must fit inside the transparent panel reserve"
        )
        XCTAssertEqual(
            IslandPresentationMode.compactTextLeading,
            54,
            accuracy: 0.0001
        )

        let short = IslandPresentationMode.compactLayoutMetrics(
            statusTitle: "已完成",
            taskTitle: "文档",
            taskCount: 4
        )
        let longStatus = IslandPresentationMode.compactLayoutMetrics(
            statusTitle: "正在压缩上下文",
            taskTitle: "文档",
            taskCount: 4
        )
        let longTitle = IslandPresentationMode.compactLayoutMetrics(
            statusTitle: "已完成",
            taskTitle: "用于验证紧凑态跑马灯的很长任务标题",
            taskCount: 4
        )
        let singleTask = IslandPresentationMode.compactLayoutMetrics(
            statusTitle: "已完成",
            taskTitle: "文档",
            taskCount: 1
        )

        XCTAssertLessThan(short.surfaceSize.width, 300)
        XCTAssertLessThan(short.statusWidth, longStatus.statusWidth)
        XCTAssertLessThan(short.titleWidth, longTitle.titleWidth)
        XCTAssertEqual(
            longTitle.titleWidth,
            IslandPresentationMode.compactTitleMaximumWidth
        )
        XCTAssertEqual(short.countWidth, 54)
        XCTAssertEqual(short.countLeadingGap, 12)
        XCTAssertEqual(singleTask.countWidth, 0)
        XCTAssertEqual(singleTask.countLeadingGap, 0)
        XCTAssertLessThan(singleTask.surfaceSize.width, short.surfaceSize.width)
        XCTAssertEqual(
            short.surfaceSize.width,
            short.marqueeLeading
                + short.titleWidth
                + short.countLeadingGap
                + short.countWidth
                + IslandPresentationMode.compactCountTrailing,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IslandPresentationMode.compact.panelSize(
                for: .completed,
                taskCount: 4,
                taskTitle: "文档"
            ),
            NSSize(
                width: short.surfaceSize.width
                    + IslandPresentationMode.panelInset * 2,
                height: 72
            )
        )

        for state in ActivityState.allCases {
            XCTAssertEqual(
                IslandPresentationMode.expanded.panelSize(for: state),
                state.windowSize
            )
        }

        XCTAssertEqual(
            IslandPresentationMode.compact.transitionDuration,
            0.28,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IslandPresentationMode.expanded.transitionDuration,
            0.30,
            accuracy: 0.0001
        )
    }

    func testCompactTaskCountExpandsMultiTaskDetailOnly() {
        XCTAssertTrue(
            compactDetailExpansionEnabled(
                presentationMode: .compact,
                taskCount: 3
            )
        )
        XCTAssertFalse(
            compactDetailExpansionEnabled(
                presentationMode: .compact,
                taskCount: 1
            )
        )
        XCTAssertFalse(
            compactDetailExpansionEnabled(
                presentationMode: .expanded,
                taskCount: 3
            )
        )
    }

    func testCompactStatusRegionFitsEveryVisibleState() {
        let font = NSFont(
            name: "AstaSans-SemiBold",
            size: IslandPresentationMode.compactTitleFontSize
        ) ?? NSFont.systemFont(
            ofSize: IslandPresentationMode.compactTitleFontSize,
            weight: .semibold
        )

        for state in ActivityState.allCases {
            let metrics = IslandPresentationMode.compactLayoutMetrics(
                statusTitle: state.visibleStatusTitle,
                taskTitle: "文档",
                taskCount: 4
            )
            XCTAssertLessThanOrEqual(
                singleLineTypographicWidth(
                    text: state.visibleStatusTitle,
                    font: font
                ) + IslandPresentationMode.compactTextMeasurementPadding,
                metrics.statusWidth,
                "Compact status must remain complete: \(state.visibleStatusTitle)"
            )
        }
    }

    func testCompactMarqueeOnlyRunsWhenTitleOverflows() {
        XCTAssertFalse(
            CompactMarqueeMetrics.needsScrolling(
                textWidth: 100,
                viewportWidth: 128
            )
        )
        XCTAssertTrue(
            CompactMarqueeMetrics.needsScrolling(
                textWidth: 120,
                viewportWidth: 128
            )
        )
        XCTAssertGreaterThanOrEqual(
            CompactMarqueeMetrics.cycleDuration(textWidth: 120),
            CompactMarqueeMetrics.minimumCycleDuration
        )
    }

    func testExpansionProgressIsContinuousAndClamped() {
        let compactHeight =
            IslandPresentationMode.compactSurfaceHeight
        let expandedHeight: CGFloat = 132

        XCTAssertEqual(
            normalizedExpansionProgress(
                surfaceHeight: compactHeight,
                expandedSurfaceHeight: expandedHeight
            ),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            normalizedExpansionProgress(
                surfaceHeight:
                    (compactHeight + expandedHeight) / 2,
                expandedSurfaceHeight: expandedHeight
            ),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            normalizedExpansionProgress(
                surfaceHeight: expandedHeight,
                expandedSurfaceHeight: expandedHeight
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            normalizedExpansionProgress(
                surfaceHeight: 0,
                expandedSurfaceHeight: expandedHeight
            ),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            normalizedExpansionProgress(
                surfaceHeight: 999,
                expandedSurfaceHeight: expandedHeight
            ),
            1,
            accuracy: 0.0001
        )
    }

    func testExpandedTextGroupIsVerticallyCentered() {
        for state in ActivityState.allCases {
            let surfaceHeight =
                state.windowSize.height
                - IslandPresentationMode.panelInset * 2
            let layout = centeredExpandedTextLayout(
                surfaceHeight: surfaceHeight
            )
            let groupBottom = layout.detailY
            let groupTop =
                layout.kickerY + expandedSupportingLineHeight

            XCTAssertEqual(
                (groupBottom + groupTop) / 2,
                surfaceHeight / 2,
                accuracy: 0.0001,
                "\(state.englishTitle) text group is not centered"
            )
            XCTAssertEqual(
                layout.titleY
                    - (
                        layout.detailY
                            + expandedSupportingLineHeight
                    ),
                expandedTextRowGap,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                layout.kickerY
                    - (
                        layout.titleY
                            + expandedStatusLineHeight
                    ),
                expandedTextRowGap,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                layout.statusDotY + expandedStatusDotSide / 2,
                layout.kickerY + expandedSupportingLineHeight / 2,
                accuracy: 0.0001
            )
        }
    }

    func testInkPlacementCentersVisibleGlyphBoundsInEveryLineBox() {
        let samples: [(imageBounds: CGRect, height: CGFloat)] = [
            (
                CGRect(x: 0.5, y: -1.3, width: 170, height: 10.9),
                expandedSupportingLineHeight
            ),
            (
                CGRect(x: 0.7, y: -1.9, width: 35, height: 16.8),
                expandedStatusLineHeight
            ),
            (
                CGRect(x: 0.9, y: -1.5, width: 26, height: 13.1),
                IslandPresentationMode.compactSurfaceHeight
            )
        ]

        for sample in samples {
            let bounds = NSRect(
                x: 0,
                y: 0,
                width: 200,
                height: sample.height
            )
            let placement = singleLineInkPlacement(
                in: bounds,
                imageBounds: sample.imageBounds,
                alignment: .leading
            )

            XCTAssertEqual(
                placement.baselineOrigin.y
                    + sample.imageBounds.midY,
                bounds.midY,
                accuracy: 0.0001
            )
        }
    }

    func testCenteredLabelUsesInkBasedCenteringContract() {
        let label = CenteredSingleLineTextView()

        XCTAssertFalse(label.isFlipped)
        XCTAssertEqual(
            label.horizontalAlignment,
            .leading
        )
    }

    func testOperationSweepRespectsReduceMotion() {
        let label = CenteredSingleLineTextView()
        label.stringValue = "正在验证文字高光扫过效果"
        label.shimmerEnabled = true

        XCTAssertTrue(label.isShimmerAnimationActive)

        label.setReduceMotion(true)
        XCTAssertFalse(label.isShimmerAnimationActive)

        label.setReduceMotion(false)
        XCTAssertTrue(label.isShimmerAnimationActive)
    }

    func testMotionPacingIsDistinctAndBounded() {
        let standby = ActivityState.standby.orbStyle
        let thinking = ActivityState.thinking.orbStyle
        let working = ActivityState.working.orbStyle
        let compacting = ActivityState.compactingContext.orbStyle
        let awaiting = ActivityState.awaitingConfirmation.orbStyle
        let completed = ActivityState.completed.orbStyle
        let error = ActivityState.error.orbStyle
        let unavailable = ActivityState.unavailable.orbStyle

        XCTAssertLessThan(unavailable.speed, standby.speed)
        XCTAssertLessThan(standby.speed, completed.speed)
        XCTAssertLessThan(completed.speed, awaiting.speed)
        XCTAssertLessThan(awaiting.speed, error.speed)
        XCTAssertLessThan(error.speed, thinking.speed)
        XCTAssertLessThan(thinking.speed, compacting.speed)
        XCTAssertLessThan(compacting.speed, working.speed)

        XCTAssertEqual(
            Set(ActivityState.allCases.map { $0.orbStyle.speed }).count,
            ActivityState.allCases.count
        )
        XCTAssertLessThanOrEqual(working.speed, 0.24)
    }

    func testEveryStateStartsGentlyBeforeReachingPeakSpeed() {
        XCTAssertEqual(orbMotionSpeedScale, 16)

        for state in ActivityState.allCases {
            let style = state.orbStyle
            let initialSpeed =
                style.speed
                * style.speedFloor
                * orbMotionSpeedScale
            let peakSpeed =
                style.speed
                * orbMotionSpeedScale

            XCTAssertGreaterThan(style.speedFloor, 0)
            XCTAssertLessThanOrEqual(style.speedFloor, 0.28)
            XCTAssertLessThan(
                initialSpeed,
                peakSpeed * 0.3,
                "\(state.englishTitle) starts too quickly"
            )
        }
    }

    func testActiveStatesKeepVisibleInternalFlowAtLowSpeed() {
        let activeStates: [ActivityState] = [
            .thinking,
            .working,
            .compactingContext,
            .awaitingConfirmation,
            .error
        ]

        XCTAssertGreaterThan(orbFluidPhaseGain, orbSurfacePhaseGain)
        XCTAssertGreaterThan(orbSurfacePhaseGain, orbRotationPhaseGain)

        for state in activeStates {
            let style = state.orbStyle
            let initialFluidSpeed =
                style.speed
                * style.speedFloor
                * orbMotionSpeedScale
                * orbFluidPhaseGain

            XCTAssertGreaterThanOrEqual(
                initialFluidSpeed,
                0.035,
                "\(state.englishTitle) fluid motion is imperceptible"
            )
        }

        let workingPeak =
            ActivityState.working.orbStyle.speed
            * orbMotionSpeedScale
            * orbFluidPhaseGain
        XCTAssertLessThanOrEqual(workingPeak, 11)
    }

    func testMotionCyclesMatchStateIntensity() {
        let styles = ActivityState.allCases.map(\.orbStyle)

        XCTAssertGreaterThanOrEqual(
            styles.map(\.motionCycle).min() ?? 0,
            8
        )
        XCTAssertLessThanOrEqual(
            styles.map(\.motionCycle).max() ?? 0,
            18
        )
        XCTAssertLessThan(
            ActivityState.working.orbStyle.motionCycle,
            ActivityState.thinking.orbStyle.motionCycle
        )
        XCTAssertLessThan(
            ActivityState.thinking.orbStyle.motionCycle,
            ActivityState.standby.orbStyle.motionCycle
        )
        XCTAssertEqual(
            ActivityState.unavailable.orbStyle.motionCycle,
            styles.map(\.motionCycle).max()
        )
    }

    func testContextCompressionPulseMovesInwardThenReleases() {
        let cycle = contextCompressionCycle
        let samples: [Float] = [
            0,
            cycle * 0.25,
            cycle * 0.5,
            cycle * 0.75,
            cycle
        ].map {
            contextCompressionPulse(
                elapsed: $0,
                cycle: cycle
            )
        }

        XCTAssertEqual(samples[0], 0, accuracy: 0.0001)
        XCTAssertEqual(samples[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[3], 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[4], 0, accuracy: 0.0001)
    }

    func testWholeSphereCompressionUsesPrimaryAndReboundBeats() {
        let cycle = contextCompressionCycle
        let idle = contextCompressionBounce(
            elapsed: 0,
            cycle: cycle
        )
        let primary = contextCompressionBounce(
            elapsed: cycle * 0.34,
            cycle: cycle
        )
        let rebound = contextCompressionBounce(
            elapsed: cycle * 0.64,
            cycle: cycle
        )
        let completed = contextCompressionBounce(
            elapsed: cycle,
            cycle: cycle
        )

        XCTAssertEqual(idle, 0, accuracy: 0.0001)
        XCTAssertEqual(primary, 1, accuracy: 0.0001)
        XCTAssertEqual(rebound, 0.46, accuracy: 0.0001)
        XCTAssertEqual(completed, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(primary, rebound)
    }

    func testCompressionIsExclusiveToContextCompactionState() {
        XCTAssertEqual(
            ActivityState.compactingContext.orbStyle.compression,
            1
        )

        for state in ActivityState.allCases
        where state != .compactingContext {
            XCTAssertEqual(
                state.orbStyle.compression,
                0,
                "\(state.englishTitle) unexpectedly compresses"
            )
        }
    }

    func testMotionEnvelopeMovesSlowFastSlowWithoutCorners() {
        let floor: Float = 0.2
        let cycle: Float = 10
        let samples: [Float] = [
            0,
            cycle * 0.125,
            cycle * 0.25,
            cycle * 0.375,
            cycle * 0.5,
            cycle * 0.625,
            cycle * 0.75,
            cycle * 0.875,
            cycle
        ].map {
            motionSpeedMultiplier(
                elapsed: $0,
                speedFloor: floor,
                cycle: cycle
            )
        }

        XCTAssertEqual(samples[0], floor, accuracy: 0.0001)
        XCTAssertEqual(samples[4], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[8], floor, accuracy: 0.0001)

        for index in 1...4 {
            XCTAssertGreaterThan(samples[index], samples[index - 1])
        }
        for index in 5...8 {
            XCTAssertLessThan(samples[index], samples[index - 1])
        }

        let epsilon: Float = 0.001
        let startSlope =
            motionSpeedMultiplier(
                elapsed: epsilon,
                speedFloor: floor,
                cycle: cycle
            )
            - motionSpeedMultiplier(
                elapsed: 0,
                speedFloor: floor,
                cycle: cycle
            )
        let endSlope =
            motionSpeedMultiplier(
                elapsed: cycle,
                speedFloor: floor,
                cycle: cycle
            )
            - motionSpeedMultiplier(
                elapsed: cycle - epsilon,
                speedFloor: floor,
                cycle: cycle
            )
        XCTAssertEqual(startSlope, 0, accuracy: 0.0001)
        XCTAssertEqual(endSlope, 0, accuracy: 0.0001)
    }

    func testBreathingTempoReflectsStateUrgency() {
        let tempos = ActivityState.allCases.map { $0.orbStyle.tempo }

        XCTAssertEqual(
            tempos.min(),
            ActivityState.unavailable.orbStyle.tempo
        )
        XCTAssertEqual(
            tempos.max(),
            ActivityState.working.orbStyle.tempo
        )
        XCTAssertLessThan(
            ActivityState.standby.orbStyle.tempo,
            ActivityState.thinking.orbStyle.tempo
        )
        XCTAssertLessThan(
            ActivityState.completed.orbStyle.tempo,
            ActivityState.awaitingConfirmation.orbStyle.tempo
        )
        XCTAssertLessThanOrEqual(tempos.max() ?? 0, 1.05)
    }

    func testThemeColorsMatchStateSemantics() {
        let thinking = ActivityState.thinking.orbStyle.accent
        XCTAssertGreaterThan(thinking.z, thinking.y)
        XCTAssertGreaterThan(thinking.y, thinking.x)

        let working = ActivityState.working.orbStyle.accent
        XCTAssertGreaterThan(working.y, working.x)
        XCTAssertGreaterThan(working.z, working.x)

        let compacting =
            ActivityState.compactingContext.orbStyle
        XCTAssertGreaterThan(compacting.accent.x, 0.95)
        XCTAssertEqual(
            compacting.accent.x,
            compacting.accent.y,
            accuracy: 0.001
        )
        XCTAssertEqual(
            compacting.accent.y,
            compacting.accent.z,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            abs(
                compacting.secondary.x -
                compacting.secondary.z
            ),
            0.12
        )

        let awaiting = ActivityState.awaitingConfirmation.orbStyle.accent
        XCTAssertGreaterThan(awaiting.x, awaiting.y)
        XCTAssertGreaterThan(awaiting.y, awaiting.z)

        let completed = ActivityState.completed.orbStyle.accent
        XCTAssertGreaterThan(completed.y, completed.x)
        XCTAssertGreaterThan(completed.y, completed.z)

        let error = ActivityState.error.orbStyle.secondary
        XCTAssertGreaterThan(error.x, error.y * 4)
        XCTAssertGreaterThan(error.x, error.z * 4)

        let unavailable = ActivityState.unavailable.orbStyle.accent
        XCTAssertLessThan(abs(unavailable.x - unavailable.y), 0.06)
        XCTAssertLessThan(abs(unavailable.y - unavailable.z), 0.06)
        XCTAssertGreaterThan(
            ActivityState.unavailable.orbStyle.desaturation,
            0.8
        )
    }

    func testActiveStatesUseExpandedIslandWhileStandbyIsCompact() {
        let standby = ActivityState.standby.windowSize
        let thinking = ActivityState.thinking.windowSize
        let working = ActivityState.working.windowSize
        let compacting =
            ActivityState.compactingContext.windowSize
        let awaiting = ActivityState.awaitingConfirmation.windowSize

        XCTAssertLessThan(standby.width, thinking.width)
        XCTAssertLessThan(standby.height, thinking.height)
        XCTAssertEqual(thinking, working)
        XCTAssertEqual(working, compacting)
        XCTAssertEqual(compacting, awaiting)
    }

    func testMetalUniformLayoutMatchesShaderContract() {
        XCTAssertEqual(MemoryLayout<OrbUniforms>.stride, 112)
        XCTAssertEqual(MemoryLayout<OrbUniforms>.alignment, 16)
    }

    func testMultiTaskExpandedPanelUsesFixedSingleIslandSize() {
        XCTAssertEqual(
            IslandPresentationMode.multiTaskMainCardPanelSize,
            NSSize(width: 496, height: 152)
        )
        XCTAssertEqual(IslandPresentationMode.taskRailWidth, 144)
        XCTAssertEqual(
            IslandPresentationMode.multiTaskMainCardPanelSize.width
                - IslandPresentationMode.panelInset * 2
                - IslandPresentationMode.taskRailWidth,
            332,
            "The fixed panel must reallocate width instead of growing"
        )

        for taskCount in 2...4 {
            XCTAssertEqual(
                IslandPresentationMode.expanded.panelSize(
                    for: .working,
                    taskCount: taskCount
                ),
                NSSize(width: 496, height: 152)
            )
        }
    }

    func testSingleTaskExpandedPanelKeepsExistingStateSize() {
        for state in ActivityState.allCases {
            XCTAssertEqual(
                IslandPresentationMode.expanded.panelSize(
                    for: state,
                    taskCount: 1
                ),
                state.windowSize
            )
        }
    }

    func testRailKeepsSelectedTaskVisibleWhenOverflowing() {
        let tasks = (0..<5).map {
            DemoTask(id: $0, name: "Task \($0)", state: .working)
        }
        let railTasks = visibleRailTasks(
            from: tasks,
            primaryID: 4
        )

        XCTAssertEqual(railTasks.map(\.id), [2, 3, 4])
        XCTAssertEqual(
            railWindowStart(for: tasks, primaryID: 4),
            2
        )
    }

    func testFourTaskRailScrollsAsOneOrderedWindow() {
        let tasks = (0..<4).map {
            DemoTask(id: $0, name: "Task \($0)", state: .working)
        }

        XCTAssertEqual(
            visibleRailTasks(
                from: tasks,
                primaryID: 2
            ).map(\.id),
            [0, 1, 2]
        )
        XCTAssertEqual(
            visibleRailTasks(
                from: tasks,
                primaryID: 3
            ).map(\.id),
            [1, 2, 3]
        )
    }

    func testWheelRailUsesThreeRowsAndCompactMotion() {
        XCTAssertEqual(TaskRailMetrics.visibleRowCount, 3)
        XCTAssertEqual(TaskRailMetrics.headerFontSize, 10.5)
        XCTAssertEqual(TaskRailMetrics.headerItemGap, 6)
        XCTAssertEqual(TaskRailMetrics.leadingPadding, 12)
        XCTAssertEqual(TaskRailMetrics.trailingPadding, 24)
        XCTAssertEqual(TaskRailMetrics.topPadding, 12)
        XCTAssertEqual(TaskRailMetrics.headerHeight, 14)
        XCTAssertEqual(TaskRailMetrics.headerToRowsGap, 8)
        XCTAssertEqual(TaskRailMetrics.rowHeight, 20)
        XCTAssertEqual(TaskRailMetrics.rowStep, 23)
        XCTAssertEqual(TaskRailMetrics.rowGap, 3)
        XCTAssertEqual(TaskRailMetrics.viewportHeight, 66)
        XCTAssertEqual(TaskRailMetrics.rowsToFooterGap, 8)
        XCTAssertEqual(TaskRailMetrics.footerHeight, 12)
        XCTAssertEqual(TaskRailMetrics.bottomPadding, 12)
        XCTAssertEqual(TaskRailMetrics.viewportY, 32)
        XCTAssertEqual(TaskRailMetrics.requiredHeight, 132)
        XCTAssertEqual(TaskRailMetrics.markerLeading, 10)
        XCTAssertEqual(TaskRailMetrics.markerDotSize, 5)
        XCTAssertEqual(TaskRailMetrics.markerToNameGap, 9)
        XCTAssertEqual(TaskRailMetrics.selectedMarkerWidth, 5)
        XCTAssertEqual(TaskRailMetrics.selectedMarkerHeight, 12)
        XCTAssertEqual(TaskRailMetrics.selectedMarkerCornerRadius, 2.5)
        XCTAssertEqual(TaskRailMetrics.selectionGlassLeading, 4)
        XCTAssertEqual(TaskRailMetrics.selectionGlassTrailing, 24)
        XCTAssertEqual(TaskRailMetrics.selectionGlassHeight, 20)
        XCTAssertEqual(TaskRailMetrics.selectionGlassCornerRadius, 6)
        XCTAssertEqual(
            TaskRailMetrics.markerLeading
                + TaskRailMetrics.markerDotSize
                + TaskRailMetrics.markerToNameGap,
            24
        )
        XCTAssertEqual(TaskRailMetrics.selectionGlassTintAlpha, 0.10)
        XCTAssertEqual(
            TaskRailMetrics.selectionMorphDuration,
            0.8,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TaskRailMetrics.scrollDuration,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TaskRailMetrics.inactiveScale,
            0.96,
            accuracy: 0.0001
        )
    }

    func testSelectedMarkerExpandsIntoTheFullTaskRowGlass() {
        let markerFrame = NSRect(x: 10, y: 44, width: 5, height: 12)
        let glassFrame = taskRailSelectionGlassFrame(
            markerFrame: markerFrame,
            containerWidth: 144
        )

        XCTAssertEqual(
            glassFrame,
            NSRect(x: 4, y: 40, width: 116, height: 20)
        )
        XCTAssertEqual(TaskRailMetrics.selectionExpandedKeyTime, 0.22)
        XCTAssertEqual(TaskRailMetrics.selectionCollapseKeyTime, 0.74)
    }

    func testTaskRailPaginationChromeOnlyAppearsAfterThreeTasks() {
        for taskCount in 1...3 {
            XCTAssertFalse(
                TaskRailMetrics.showsPagination(taskCount: taskCount)
            )
        }
        XCTAssertTrue(TaskRailMetrics.showsPagination(taskCount: 4))

        XCTAssertEqual(TaskRailMetrics.visibleRowsHeight(taskCount: 1), 20)
        XCTAssertEqual(TaskRailMetrics.visibleRowsHeight(taskCount: 2), 43)
        XCTAssertEqual(TaskRailMetrics.visibleRowsHeight(taskCount: 3), 66)
        XCTAssertEqual(TaskRailMetrics.viewportHeight(taskCount: 4), 66)
        XCTAssertEqual(
            TaskRailMetrics.viewportY(
                containerHeight: 132,
                taskCount: 1
            ),
            56,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TaskRailMetrics.viewportY(
                containerHeight: 132,
                taskCount: 3
            ),
            33,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TaskRailMetrics.viewportY(
                containerHeight: 132,
                taskCount: 4
            ),
            32,
            accuracy: 0.0001
        )
    }

    func testTaskRailHeaderUsesTaskThenCounterWithSixPointGap() {
        let layout = centeredTaskRailHeaderLayout(
            containerWidth: 144,
            y: 106,
            height: 14,
            taskWidth: 24,
            counterWidth: 30
        )

        XCTAssertEqual(layout.taskFrame.minX, 42)
        XCTAssertEqual(
            layout.counterFrame.minX - layout.taskFrame.maxX,
            6,
            accuracy: 0.0001
        )
        XCTAssertEqual(layout.counterFrame.maxX, 102)
        XCTAssertEqual(
            (layout.taskFrame.minX + layout.counterFrame.maxX) / 2,
            72,
            accuracy: 0.0001
        )
    }

    func testAttentionCountIncludesApprovalAndErrorOnly() {
        let tasks = [
            DemoTask(id: 0, name: "A", state: .working),
            DemoTask(id: 1, name: "B", state: .awaitingConfirmation),
            DemoTask(id: 2, name: "C", state: .error),
            DemoTask(id: 3, name: "D", state: .completed)
        ]

        XCTAssertEqual(taskAttentionCount(tasks), 2)
    }

    func testOnlyUnselectedThinkingAndWorkingTasksUseTitleSweep() {
        XCTAssertTrue(
            backgroundTaskTitleShowsSweep(
                state: .thinking,
                isPrimary: false
            )
        )
        XCTAssertTrue(
            backgroundTaskTitleShowsSweep(
                state: .working,
                isPrimary: false
            )
        )
        XCTAssertFalse(
            backgroundTaskTitleShowsSweep(
                state: .thinking,
                isPrimary: true
            )
        )

        for state in ActivityState.allCases where
            state != .thinking && state != .working {
            XCTAssertFalse(
                backgroundTaskTitleShowsSweep(
                    state: state,
                    isPrimary: false
                )
            )
        }
    }

    func testIslandFrameIsCenteredAboveControlWindow() {
        let anchor = NSRect(
            x: 200,
            y: 120,
            width: 720,
            height: 430
        )
        let islandSize = IslandPresentationMode.multiTaskMainCardPanelSize
        let frame = anchoredIslandFrame(
            size: islandSize,
            anchorFrame: anchor
        )

        XCTAssertEqual(frame.midX, anchor.midX)
        XCTAssertEqual(
            frame.minY,
            anchor.maxY + demoIslandAnchorGap
        )
        XCTAssertEqual(frame.size, islandSize)
    }
}
