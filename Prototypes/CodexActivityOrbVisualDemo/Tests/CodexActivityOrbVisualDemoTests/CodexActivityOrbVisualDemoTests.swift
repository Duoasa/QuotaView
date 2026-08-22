import XCTest
@testable import CodexActivityOrbVisualDemo

final class CodexActivityOrbVisualDemoTests: XCTestCase {
    func testUniformSeedMatchesGeneratedMetalLayout() {
        XCTAssertEqual(orbUniformSeed.count, OrbUniformLayout.floatCount)
        XCTAssertEqual(OrbUniformLayout.floatCount, 128)
        XCTAssertEqual(orbUniformSeed[OrbUniformLayout.speed], 0.82, accuracy: 0.0001)
        XCTAssertEqual(orbUniformSeed[OrbUniformLayout.radius], 0.72, accuracy: 0.0001)
        XCTAssertEqual(orbUniformSeed[OrbUniformLayout.style], 9, accuracy: 0.0001)
        XCTAssertEqual(orbUniformSeed[OrbUniformLayout.glassEnabled], 1, accuracy: 0.0001)
    }

    func testShaderResourceContainsRequiredEntryPoints() throws {
        let source = try OrbShaderResources.source()
        XCTAssertTrue(source.contains("vertex vs_mainOutput vs_main"))
        XCTAssertTrue(source.contains("fragment fs_mainOutput fs_main"))
        XCTAssertTrue(source.contains("glsSiriFluid"))
    }

    func testDemoModesMatchSingleIslandGeometry() {
        XCTAssertEqual(
            OrbPresentation.expanded.panelSize(for: .thinking),
            CGSize(width: 444, height: 152)
        )
        XCTAssertEqual(
            OrbPresentation.expanded.orbCanvasSide(for: .thinking),
            122
        )
        XCTAssertEqual(
            OrbPresentation.expanded.orbCanvasSide(for: .standby),
            82
        )
        XCTAssertEqual(
            OrbPresentation.compact.panelSize(for: .thinking),
            CGSize(width: 270, height: 72)
        )
        XCTAssertEqual(
            OrbPresentation.compact.surfaceSize(for: .thinking),
            CGSize(width: 250, height: 52)
        )
        XCTAssertEqual(OrbPresentation.compactOrbDiameter, 28)
        XCTAssertEqual(OrbPresentation.compactTextGap, 14)
        XCTAssertEqual(
            OrbPresentation.compactOrbCanvasSide
                * OrbPresentation.productionOrbSphereRadius,
            28,
            accuracy: 0.0001
        )
    }

    func testAllProductionVisualStatesAreRepresented() {
        XCTAssertEqual(DemoActivityState.allCases.count, 9)
        XCTAssertEqual(DemoActivityState.thinking.statusTitle, "思考中")
        XCTAssertEqual(DemoActivityState.working.statusTitle, "工作中")
        XCTAssertEqual(
            DemoActivityState.compactingContext.statusTitle,
            "正在压缩上下文"
        )
        XCTAssertTrue(DemoActivityState.thinking.showsOperationSweep)
        XCTAssertTrue(DemoActivityState.working.showsOperationSweep)
        XCTAssertTrue(DemoActivityState.compactingContext.showsOperationSweep)
        XCTAssertFalse(DemoActivityState.awaitingConfirmation.showsOperationSweep)
    }

    func testEveryStateProducesACompleteStyleNineUniformSet() {
        for state in DemoActivityState.allCases {
            let uniforms = state.orbConfiguration.applying(to: orbUniformSeed)
            XCTAssertEqual(uniforms.count, OrbUniformLayout.floatCount)
            XCTAssertEqual(uniforms[OrbUniformLayout.style], 9)
            XCTAssertEqual(uniforms[OrbUniformLayout.glassEnabled], 1)
            XCTAssertEqual(
                uniforms[OrbUniformLayout.radius],
                0.535,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                uniforms[OrbUniformLayout.contourDeformation],
                0,
                accuracy: 0.0001
            )
            XCTAssertGreaterThan(uniforms[OrbUniformLayout.speed], 0)
            XCTAssertEqual(
                uniforms[OrbUniformLayout.speed],
                state.orbConfiguration.speed * 1.5,
                accuracy: 0.0001
            )
        }
        XCTAssertGreaterThan(
            DemoActivityState.working.orbConfiguration.speed,
            DemoActivityState.thinking.orbConfiguration.speed
        )
        XCTAssertLessThan(
            DemoActivityState.unavailable.orbConfiguration.speed,
            DemoActivityState.standby.orbConfiguration.speed
        )
    }
}
