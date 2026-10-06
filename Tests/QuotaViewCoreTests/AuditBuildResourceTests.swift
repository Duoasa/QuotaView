#if !SWIFT_PACKAGE
import AppKit
import XCTest
@testable import QuotaView

@MainActor
final class AuditBuildResourceTests: XCTestCase {
    func testHostedAppResolvesPackagedResourcesWithoutSourceTree() throws {
        AstaSansFontRegistrar.registerBundledFonts()
        for name in ["AstaSans-Regular", "AstaSans-Medium", "AstaSans-SemiBold"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"))
            XCTAssertNotNil(NSFont(name: name, size: 14))
        }
        for (name, ext) in [("CodexProviderIcon", "png"), ("CodexActivityRippleGlowShader", "txt"), ("QuotaViewFeedbackQQ", "jpg"), ("Assets", "car")] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: ext))
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
        }
        for index in 0..<28 {
            XCTAssertNotNil(Bundle.main.url(forResource: "CodexSubagentAvatar-\(index)", withExtension: "png", subdirectory: "CodexAgentAvatars"))
        }
    }
}
#endif
