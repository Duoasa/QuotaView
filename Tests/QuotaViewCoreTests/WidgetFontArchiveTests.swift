import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import QuotaView

final class WidgetFontArchiveTests: XCTestCase {
    private var fontsURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
    }

    func testBundledFacesRetainFileDescriptorAfterResizingAndReconstruction() throws {
        for name in ["AstaSans-Regular", "AstaSans-Medium", "AstaSans-SemiBold"] {
            let url = fontsURL.appendingPathComponent(name + ".ttf")
            let base = try XCTUnwrap(AstaSansFontRegistrar.fileBackedFont(at: url, expectedName: name))
            // Reproduce the old descriptor limitation without relying on a system
            // font installation or registering fonts in the test process.
            let bytes = try Data(contentsOf: url)
            let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
            let graphics = try XCTUnwrap(CGFont(provider))
            let oldFont = CTFontCreateWithGraphicsFont(graphics, 12, nil, nil)
            XCTAssertNil(CTFontCopyAttribute(oldFont, kCTFontURLAttribute))

            for size: CGFloat in [9, 12, 16, 32] {
                let resized = CTFontCreateCopyWithAttributes(base, size, nil, nil)
                let descriptor = CTFontCopyFontDescriptor(resized)
                let source = try XCTUnwrap(CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL)
                XCTAssertEqual(source.standardizedFileURL, url.standardizedFileURL)
                let reconstructed = CTFontCreateWithFontDescriptor(descriptor, size, nil)
                XCTAssertEqual(CTFontCopyPostScriptName(reconstructed) as String, name)
                XCTAssertEqual(CTFontGetSize(reconstructed), size)
                let chars = Array("0123456789%$—".utf16)
                var glyphs = [CGGlyph](repeating: 0, count: chars.count)
                XCTAssertTrue(CTFontGetGlyphsForCharacters(reconstructed, chars, &glyphs, chars.count))
                XCTAssertFalse(glyphs.contains(0))
            }
        }
    }

    func testInvalidOrMismatchedFontDoesNotEscapeSystemFallback() throws {
        let url = fontsURL.appendingPathComponent("AstaSans-Regular.ttf")
        XCTAssertNil(AstaSansFontRegistrar.fileBackedFont(at: url, expectedName: "AstaSans-SemiBold"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let corrupt = directory.appendingPathComponent("AstaSans-Regular.ttf")
        XCTAssertNil(AstaSansFontRegistrar.fileBackedFont(at: corrupt, expectedName: "AstaSans-Regular"))
        try Data("invalid font".utf8).write(to: corrupt)
        XCTAssertNil(AstaSansFontRegistrar.fileBackedFont(at: corrupt, expectedName: "AstaSans-Regular"))
    }
}
