import CoreGraphics
import CoreText
import Foundation
import OSLog
import SwiftUI

enum AstaSans {
    private enum Face {
        static let regular = "AstaSans-Regular"
        static let medium = "AstaSans-Medium"
        static let semiBold = "AstaSans-SemiBold"
    }

    static func regular(_ size: CGFloat) -> Font {
        font(Face.regular, size: size, fallbackWeight: .regular)
    }

    static func medium(_ size: CGFloat) -> Font {
        font(Face.medium, size: size, fallbackWeight: .medium)
    }

    static func semiBold(_ size: CGFloat) -> Font {
        font(Face.semiBold, size: size, fallbackWeight: .semibold)
    }

    private static func font(_ name: String, size: CGFloat, fallbackWeight: Font.Weight) -> Font {
        guard let font = AstaSansFontRegistrar.font(named: name, size: size) else {
            return .system(size: size, weight: fallbackWeight)
        }
        // Keep the bundled face instead of asking SwiftUI to resolve its name again.
        return Font(font)
    }
}

enum AstaSansFontRegistrar {
    private static let logger = Logger(subsystem: "com.quotaview.menubar", category: "fonts")

    // Swift's lazy static initialization serializes loading, including early view/font
    // construction. Only successfully decoded and validated faces enter this cache.
    private static let bundledFonts: [String: CTFont] = loadBundledFonts()

    static func registerBundledFonts() {
        _ = bundledFonts
    }

    static func font(named name: String, size: CGFloat) -> CTFont? {
        guard let font = bundledFonts[name] else { return nil }
        return CTFontCreateCopyWithAttributes(font, size, nil, nil)
    }

    private static func loadBundledFonts() -> [String: CTFont] {
        let fontNames = [
            "AstaSans-Regular",
            "AstaSans-Medium",
            "AstaSans-SemiBold"
        ]
        var fonts: [String: CTFont] = [:]

        for fontName in fontNames {
            guard let fontURL = Bundle.main.url(
                forResource: fontName,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else {
                logger.error("Missing bundled font: \(fontName, privacy: .public); using system font")
                continue
            }

            // Retain the actual font data. A same-name font installed by the user or
            // a stale Font Manager match must not replace the app's bundled face.
            let data: Data
            do {
                data = try Data(contentsOf: fontURL)
            } catch {
                let error = error as NSError
                logger.error("Cannot read bundled font: \(fontName, privacy: .public), domain=\(error.domain, privacy: .public), code=\(error.code); using system font")
                continue
            }
            guard let provider = CGDataProvider(data: data as CFData),
                  let graphicsFont = CGFont(provider) else {
                logger.error("Cannot decode bundled font: \(fontName, privacy: .public); using system font")
                continue
            }
            let font = CTFontCreateWithGraphicsFont(graphicsFont, 12, nil, nil)
            guard CTFontCopyPostScriptName(font) as String == fontName,
                  hasRequiredGlyphs(font) else {
                logger.error("Invalid face or missing value glyphs: \(fontName, privacy: .public); using system font")
                continue
            }

            // Registration is still needed by consumers such as WidgetKit. A failed
            // name registration does not invalidate the verified, directly loaded face.
            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
            let error = registrationError?.takeRetainedValue()
            if !registered {
                let domain = error.map { CFErrorGetDomain($0) as String } ?? "unknown"
                let code = error.map { CFErrorGetCode($0) } ?? 0
                logger.warning("Font registration failed: \(fontName, privacy: .public), domain=\(domain, privacy: .public), code=\(code); using validated bundled face directly")
            }
            fonts[fontName] = font
        }
        return fonts
    }

    private static func hasRequiredGlyphs(_ font: CTFont) -> Bool {
        // CJK text uses Core Text's normal cascade. Validate the characters that
        // must come from Asta Sans itself, including the unknown-value placeholder.
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz%$.,:+-—".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
            && glyphs.allSatisfy { $0 != 0 }
    }
}
