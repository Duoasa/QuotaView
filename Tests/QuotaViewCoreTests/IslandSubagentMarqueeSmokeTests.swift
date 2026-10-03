import AppKit
import CoreText
import XCTest
@testable import QuotaView

final class IslandSubagentMarqueeSmokeTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let window: NSWindow
        let container: NSView
        let host: IslandScrollingTextHost
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        init(width: CGFloat) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 24),
                styleMask: .borderless, backing: .buffered, defer: false)
            container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 24))
            host = IslandScrollingTextHost(frame: container.bounds)
            window.contentView = container
            container.addSubview(host)
        }
        func configure(_ text: NSAttributedString, visible: Bool = true, reduceMotion: Bool = false,
                       streamIdentity: String? = nil) {
            host.configure(attributedText: text, font: font, visible: visible, reduceMotion: reduceMotion,
                streamIdentity: streamIdentity)
        }
    }

    @MainActor
    private func rich(_ text: String, color: NSColor = .white) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: color
        ])
    }

    @MainActor
    private func avatarMarker(_ image: NSImage, font: NSFont) -> NSAttributedString {
        let marker = "\u{2003}"
        let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
            NSAttributedString(string: marker, attributes: [.font: font])), nil, nil, nil)
        return NSAttributedString(string: marker, attributes: [
            .font: font, .kern: 14 - width, .islandInlineImage: image
        ])
    }

    @MainActor
    private func avatarImage() -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
    }

    @MainActor
    func testOverflowUsesExistingNegativeOneWayLoopAndRepeatedCopy() throws {
        let fixture = Fixture(width: 70)
        fixture.configure(rich("🤖 Source audit · 6.1 Sol · Working · 11s  🐻 Model audit · 6 Luna · Waiting · 12s"))
        let animation = try XCTUnwrap(fixture.host.scrollAnimation)
        let values = try XCTUnwrap(animation.values as? [NSNumber]).map(\.doubleValue)
        XCTAssertEqual(values.count, 5)
        XCTAssertEqual(values[0], 0)
        XCTAssertEqual(values[1], 0)
        XCTAssertLessThan(values[2], 0)
        XCTAssertEqual(values[2], values[3])
        XCTAssertLessThan(values[4], values[3])
        XCTAssertEqual(values, values.sorted(by: >), "Movement must never reverse")
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertEqual(animation.calculationMode, .linear)
        XCTAssertGreaterThan(fixture.host.scrollDistance, 0)
        XCTAssertNil(fixture.host.shimmerAnimation, "Rich role colors must remain independently readable")
    }

    @MainActor
    func testFittingRichContentDoesNotScroll() {
        let fixture = Fixture(width: 500)
        fixture.configure(rich("🤖 Audit · 6 Luna · Thinking · 11s"))
        XCTAssertNil(fixture.host.scrollAnimation)
        XCTAssertEqual(fixture.host.scrollDistance, 0)
    }

    @MainActor
    func testVisibilityReducedMotionAndStopRemoveRichAnimations() throws {
        let fixture = Fixture(width: 40)
        let text = rich("🤖 Source audit · 6.1 Sol · Working · 11s")
        fixture.configure(text)
        XCTAssertNotNil(fixture.host.scrollAnimation)
        fixture.configure(text, visible: false)
        XCTAssertNil(fixture.host.scrollAnimation)
        fixture.configure(text, reduceMotion: true)
        XCTAssertNil(fixture.host.scrollAnimation)
        fixture.configure(text)
        XCTAssertNotNil(fixture.host.scrollAnimation)
        fixture.host.stop()
        XCTAssertNil(fixture.host.scrollAnimation)
        fixture.configure(text)
        fixture.host.removeFromSuperview()
        XCTAssertNil(fixture.host.scrollAnimation, "Detached hosts cannot retain their infinite animation")
    }

    @MainActor
    func testHiddenAncestorStopsAndUnhideResumesRichMarquee() {
        let fixture = Fixture(width: 40)
        fixture.configure(rich("🤖 Source audit · 6.1 Sol · Working · 11s"))
        XCTAssertNotNil(fixture.host.scrollAnimation)
        fixture.container.isHidden = true
        XCTAssertNil(fixture.host.scrollAnimation)
        fixture.container.isHidden = false
        XCTAssertNotNil(fixture.host.scrollAnimation)
    }

    @MainActor
    func testCompatibleSemanticAndColorUpdatesPreserveAnimationPhase() throws {
        let fixture = Fixture(width: 70)
        let before = rich("🤖 Alpha · 11s", color: .white)
        let after = rich("🤖 Bravo · 12s", color: .gray.withAlphaComponent(0.3))
        XCTAssertEqual(IslandScrollingTextHost.width(of: before), IslandScrollingTextHost.width(of: after))
        fixture.configure(before)
        let animation = try XCTUnwrap(fixture.host.scrollAnimation)
        fixture.configure(after)
        let updated = try XCTUnwrap(fixture.host.scrollAnimation)
        XCTAssertEqual(updated.beginTime, animation.beginTime, "A seconds tick must not restart the rich lane")
        XCTAssertEqual(updated.duration, animation.duration)
        XCTAssertEqual(updated.values as? [NSNumber], animation.values as? [NSNumber])
        let rendered = try XCTUnwrap(fixture.host.renderedAttributedText)
        XCTAssertEqual(rendered.string, after.string)
        let color = try XCTUnwrap(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(color.alphaComponent, 1)
        XCTAssertEqual(color.usingColorSpace(.sRGB)?.redComponent, NSColor.gray.usingColorSpace(.sRGB)?.redComponent)
    }

    @MainActor
    func testWidthChangesRebuildLoopGeometryWithoutChangingDirection() throws {
        let fixture = Fixture(width: 40)
        fixture.configure(rich("🤖 Alpha · 11s"))
        let before = try XCTUnwrap(fixture.host.scrollAnimation)
        let oldValues = try XCTUnwrap(before.values as? [NSNumber])
        fixture.configure(rich("🤖 Longer agent name · 12s"))
        let after = try XCTUnwrap(fixture.host.scrollAnimation)
        let newValues = try XCTUnwrap(after.values as? [NSNumber])
        XCTAssertLessThan(newValues[2].doubleValue, oldValues[2].doubleValue)
        XCTAssertLessThan(newValues.last!.doubleValue, oldValues.last!.doubleValue)
        XCTAssertGreaterThan(after.duration, before.duration)
    }

    @MainActor
    func testStableStreamKeepsClockAcrossWidthUpdatesAndNewMembershipRestartsIt() throws {
        let fixture = Fixture(width: 40)
        fixture.configure(rich("🤖 Alpha · Thinking · 11s"), streamIdentity: "alpha")
        let before = try XCTUnwrap(fixture.host.scrollAnimation)
        fixture.configure(rich("🤖 Alpha · Checking sources · 12s"), streamIdentity: "alpha")
        let changed = try XCTUnwrap(fixture.host.scrollAnimation)
        XCTAssertEqual(changed.beginTime, before.beginTime,
            "Status width updates must not postpone the stream's initial pause")
        XCTAssertGreaterThan(changed.duration, before.duration)
        XCTAssertNotEqual(changed.values as? [NSNumber], before.values as? [NSNumber],
            "New loop geometry must still reflect the updated content width")
        fixture.configure(rich("🤖 Alpha · Checking sources · 12s"), streamIdentity: "alpha,beta")
        let newStream = try XCTUnwrap(fixture.host.scrollAnimation)
        XCTAssertNotEqual(newStream.beginTime, changed.beginTime,
            "Replacing child membership creates a new stream with its own initial pause")
    }

    @MainActor
    func testInlineImageUsesUTF16CoreTextOffsetAndSharesRepeatedTrack() throws {
        let fixture = Fixture(width: 40)
        let image = avatarImage()
        let text = NSMutableAttributedString(attributedString: rich("🤖 "))
        text.append(avatarMarker(image, font: fixture.font))
        text.append(rich(" Alpha · 11s"))
        fixture.configure(text)
        let rendered = try XCTUnwrap(fixture.host.renderedAttributedText)
        let marker = (rendered.string as NSString).range(of: "\u{2003}")
        let expectedX = CTLineGetOffsetForStringIndex(CTLineCreateWithAttributedString(rendered), marker.location, nil)
        let frame = try XCTUnwrap(fixture.host.inlineImageFrames.first)
        XCTAssertEqual(fixture.host.inlineImageFrames.count, 1)
        XCTAssertEqual(frame.minX, expectedX, accuracy: 0.01)
        XCTAssertEqual(frame.size, CGSize(width: 14, height: 14))
        XCTAssertEqual(frame.midY, fixture.host.richTextBaseline + fixture.host.richTextCapHeight / 2,
            accuracy: 0.01, "The avatar and glyph cap-height must use one explicit visual centre")
        XCTAssertTrue(fixture.host.inlineImagesHaveContents)
        XCTAssertTrue(fixture.host.repeatedInlineImagesVisible)
        XCTAssertNotNil(fixture.host.scrollAnimation)
        fixture.host.setFrameSize(NSSize(width: 500, height: 24))
        fixture.host.layout()
        XCTAssertFalse(fixture.host.repeatedInlineImagesVisible)
        XCTAssertNil(fixture.host.scrollAnimation)
    }

    @MainActor
    func testNativeSystemFontUsesOneBaselineWithoutClippingFourteenPointAvatars() throws {
        let fixture = Fixture(width: 500)
        let font = NSFont.systemFont(ofSize: 11)
        let text = NSMutableAttributedString(attributedString: avatarMarker(avatarImage(), font: font))
        text.append(NSAttributedString(string: " Huygens 工作中 · <1m", attributes: [.font: font, .foregroundColor: NSColor.white]))
        let height = IslandScrollingTextHost.height(for: text, font: font)
        XCTAssertEqual(height, 14, "An invisible avatar marker must not increase the body font to 14pt")
        fixture.host.setFrameSize(NSSize(width: 500, height: height))
        fixture.host.configure(attributedText: text, font: font, visible: true, reduceMotion: false)
        let frame = try XCTUnwrap(fixture.host.visibleInlineImageFrames.first)
        XCTAssertEqual(frame.minY, 0, accuracy: 0.01)
        XCTAssertEqual(frame.maxY, height, accuracy: 0.01)
        XCTAssertEqual(frame.midY, fixture.host.richTextBaseline + font.capHeight / 2, accuracy: 0.01)
        let baseline = fixture.host.richTextBaseline
        fixture.host.setFrameSize(NSSize(width: 300, height: height))
        fixture.host.layout()
        XCTAssertEqual(fixture.host.richTextBaseline, baseline,
            "A viewport width change must not change the lane's baseline")
    }

    @MainActor
    func testStaticTruncationRemovesCutOffAvatarsAndKeepsEllipsis() throws {
        let fixture = Fixture(width: 65)
        let text = NSMutableAttributedString(attributedString: avatarMarker(avatarImage(), font: fixture.font))
        text.append(rich(" Alpha · 11s    "))
        text.append(avatarMarker(avatarImage(), font: fixture.font))
        text.append(rich(" Bravo · 12s"))
        fixture.configure(text)
        XCTAssertEqual(fixture.host.visibleInlineImageFrames.count, 2)
        XCTAssertTrue(fixture.host.repeatedInlineImagesVisible)
        for settings in [(visible: true, reduceMotion: true), (visible: false, reduceMotion: false)] {
            fixture.configure(text, visible: settings.visible, reduceMotion: settings.reduceMotion)
            XCTAssertNil(fixture.host.scrollAnimation)
            XCTAssertTrue(fixture.host.richLineTruncated)
            XCTAssertEqual(fixture.host.visibleInlineImageFrames.count, 1,
                "An avatar removed from the truncated line cannot overlay its ellipsis")
            XCTAssertFalse(fixture.host.repeatedInlineImagesVisible)
            let line = try XCTUnwrap(fixture.host.renderedRichLine)
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            let ellipsisGlyph = CTFontGetGlyphWithName(fixture.font as CTFont, "ellipsis" as CFString)
            XCTAssertTrue(runs.contains { run in
                var glyphs = Array(repeating: CGGlyph(0), count: CTRunGetGlyphCount(run))
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                return glyphs.contains(ellipsisGlyph)
            }, "A static overflow must retain its visible ellipsis")
        }
        fixture.configure(text)
        XCTAssertFalse(fixture.host.richLineTruncated)
        XCTAssertEqual(fixture.host.visibleInlineImageFrames.count, 2)
        XCTAssertNotNil(fixture.host.scrollAnimation)
    }

    @MainActor
    func testOrdinaryTextAndShimmerInterfaceStillWorksAfterRichConfiguration() throws {
        let fixture = Fixture(width: 40)
        fixture.configure(rich("🤖 Source audit · 6.1 Sol · Working · 11s"))
        fixture.host.configure(text: "Thinking about the next step", font: fixture.font,
            color: IslandTextPalette.detail, visible: true, reduceMotion: false, shimmer: true)
        XCTAssertNotNil(fixture.host.scrollAnimation)
        XCTAssertNotNil(fixture.host.shimmerAnimation)
        XCTAssertTrue(fixture.host.shimmerColorAlphas.allSatisfy { $0 == 1 })
        fixture.host.configure(text: "Short", font: fixture.font,
            color: .white, visible: true, reduceMotion: true, shimmer: true)
        XCTAssertNil(fixture.host.scrollAnimation)
        XCTAssertNil(fixture.host.shimmerAnimation)
        XCTAssertEqual(fixture.host.renderedAttributedText?.string, "Short")
    }
}
