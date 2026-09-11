import AppKit
import CoreText
import QuotaViewCore
import XCTest
@testable import QuotaView

@MainActor
final class CodexActivityTextRenderingTests: XCTestCase {
    func testPercentSurvivesLegacy27WidthRounding() throws {
        let valueFont = try astaFont(size: 28)
        let symbolFont = try astaFont(size: 14)
        let valueWidth = attributed("27", font: valueFont).size().width
        let symbolWidth = attributed("%", font: symbolFont).size().width
        let legacyWidth = (valueWidth + symbolWidth) - valueWidth

        // The original right-column subtraction loses a few floating-point bits.
        XCTAssertLessThan(legacyWidth, naturalWidth("%", font: symbolFont))
        assertUntruncated("%", font: symbolFont, width: legacyWidth)
    }

    func testAllQuotaValuesReserveCompleteSymbolAcrossDisplayScales() throws {
        let fontPairs = [
            (try astaFont(size: 28), try astaFont(size: 14)),
            (NSFont.systemFont(ofSize: 28, weight: .semibold),
             NSFont.systemFont(ofSize: 14, weight: .semibold))
        ]
        // Repeat transition boundaries as well as covering every possible value.
        let values: [Int?] = (0...100).map { $0 } + [nil, 27, 25, 100, 9, nil, 0]
        for (valueFont, symbolFont) in fontPairs {
            for scale: CGFloat in [1, 1.25, 1.5, 2, 3] {
                for value in values {
                    let text = value.map(String.init) ?? "—"
                    let symbol = value == nil ? "" : "%"
                    let widths = CodexActivityIslandProgressBarGeometry
                        .completionQuotaTextWidths(
                            value: text, symbol: symbol,
                            valueFont: valueFont, symbolFont: symbolFont,
                            backingScaleFactor: scale
                        )
                    XCTAssertGreaterThanOrEqual(widths.value, naturalWidth(text, font: valueFont))
                    XCTAssertGreaterThanOrEqual(widths.symbol, naturalWidth(symbol, font: symbolFont))
                    XCTAssertLessThanOrEqual(widths.value + widths.symbol, 128)
                    XCTAssertEqual(widths.symbol * scale, (widths.symbol * scale).rounded(), accuracy: 1e-10)
                    assertUntruncated(text, font: valueFont, width: widths.value)
                    assertUntruncated(symbol, font: symbolFont, width: widths.symbol)
                    let ink = CTLineGetImageBounds(
                        CTLineCreateWithAttributedString(attributed(text, font: valueFont)), nil
                    )
                    XCTAssertLessThanOrEqual(ink.maxX, widths.value)
                }
            }
        }
    }

    func testEveryIslandTextRoleToleratesOnlyRoundingAtExactFit() throws {
        var samples: [(String, CGFloat, Bool)] = [
            ("QuotaView — 修复 27% / cafe\u{301} 👩🏽‍💻", 12.5, true), // task title
            ("读取文件 / Running tool → 检查结果", 11.5, false), // operation and shimmer
            ("%", 14, true), ("100", 28, true), ("—", 28, true)
        ]
        for language in AppPreferences.Language.allCases {
            let copy = CodexActivityCopy(language: language)
            for state in CodexActivityVisualState.allCases {
                samples.append((copy.statusTitle(for: state), 15, true)) // expanded status
                samples.append((copy.statusTitle(for: state), 14, true)) // compact status
            }
            samples.append((copy.statusTitle(for: .completed), 16, true))
            for count: Int64 in [0, 999, 12_800, 783_800, 1_000_000, 9_000_000_000] {
                samples.append((copy.tokenUsageTitle(totalTokens: count), 11.5, false))
                samples.append((copy.completionTokenUsageDetail(totalTokens: count), 11, false))
            }
        }
        for value in 0...100 { samples.append((String(value), 11.5, false)) } // quota ring
        samples.append(("—", 11.5, false))

        for (text, size, bold) in samples {
            let fonts = [
                try astaFont(size: size, bold: bold),
                NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            ]
            for font in fonts {
                let width = naturalWidth(text, font: font)
                XCTAssertEqual(activitySingleLineWidth(text: text, font: font), width)
                assertUntruncated(text, font: font, width: width)
                assertUntruncated(text, font: font, width: width.nextDown)
                assertUntruncated(text, font: font, width: width - width.ulp * 4)
            }
        }
    }

    func testRealOverflowStillTruncatesLongTitlesOperationsAndTokens() throws {
        for font in [try astaFont(size: 11.5, bold: false), NSFont.systemFont(ofSize: 11.5)] {
            for (text, width): (String, CGFloat) in [
                (String(repeating: "长任务标题 / 👩🏽‍💻 cafe\u{301} ", count: 20), 184),
                (String(repeating: "Running tool → 正在执行步骤 ", count: 20), 210),
                ("This turn 999999999999999999999 tokens", 138)
            ] {
                let source = CTLineCreateWithAttributedString(attributed(text, font: font))
                let result = activityTruncatedLine(text: text, font: font, color: .white, maximumWidth: width)
                XCTAssertNotEqual(glyphs(result), glyphs(source))
                XCTAssertFalse(glyphs(result).isEmpty)
                XCTAssertLessThanOrEqual(CTLineGetTypographicBounds(result, nil, nil, nil), width + 1e-10)
            }
        }
        // A fraction of a real pixel must still count as overflow, unlike ULP noise.
        let font = try astaFont(size: 14)
        let source = CTLineCreateWithAttributedString(attributed("%", font: font))
        let result = activityTruncatedLine(
            text: "%", font: font, color: .white,
            maximumWidth: naturalWidth("%", font: font) - 0.25
        )
        XCTAssertNotEqual(glyphs(result), glyphs(source))
    }

    func testCompactQuotaNumbersFitInsideTheRing() throws {
        let fonts = [try astaFont(size: 11.5, bold: false), NSFont.systemFont(ofSize: 11.5)]
        let diameter = CodexActivityIslandProgressBarGeometry.compactQuotaRingDiameter
        let stroke = CodexActivityIslandProgressBarGeometry.compactQuotaRingLineWidth
        for font in fonts {
            for text in (0...100).map(String.init) + ["—"] {
                let source = CTLineCreateWithAttributedString(attributed(text, font: font))
                let ink = CTLineGetImageBounds(source, nil)
                XCTAssertLessThanOrEqual(ink.width, diameter - 2 * stroke)
                XCTAssertLessThanOrEqual(ink.height, diameter - 2 * stroke)
                assertUntruncated(text, font: font, width: diameter)
            }
        }
    }

    func testEmptyTextDoesNotCreateAnEllipsis() throws {
        let font = try astaFont(size: 14)
        for width: CGFloat in [0, 0.5, 128] {
            let line = activityTruncatedLine(text: "", font: font, color: .white, maximumWidth: width)
            XCTAssertTrue(glyphs(line).isEmpty)
        }
    }

    func testVeryNarrowLabelsDoNotDrawPartOfAnEllipsis() throws {
        let font = try astaFont(size: 14)
        for width in [CGFloat.zero, 0.5, naturalWidth("…", font: font) - 0.25] {
            let line = activityTruncatedLine(
                text: "Working 工作中", font: font, color: .white, maximumWidth: width
            )
            XCTAssertTrue(glyphs(line).isEmpty)
        }
    }

    private func astaFont(size: CGFloat, bold: Bool = true) throws -> NSFont {
        let name = bold ? "AstaSans-SemiBold" : "AstaSans-Regular"
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/Fonts/\(name).ttf")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return try XCTUnwrap(NSFont(name: name, size: size))
    }

    private func attributed(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font])
    }

    private func naturalWidth(_ text: String, font: NSFont) -> CGFloat {
        CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(attributed(text, font: font)),
            nil, nil, nil
        )
    }

    private func glyphs(_ line: CTLine) -> [CGGlyph] {
        (CTLineGetGlyphRuns(line) as! [CTRun]).flatMap { run in
            var result = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &result)
            return result
        }
    }

    private func assertUntruncated(
        _ text: String, font: NSFont, width: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let source = CTLineCreateWithAttributedString(attributed(text, font: font))
        let rendered = activityTruncatedLine(
            text: text, font: font, color: .white, maximumWidth: width
        )
        XCTAssertEqual(glyphs(rendered), glyphs(source), text, file: file, line: line)
    }
}
