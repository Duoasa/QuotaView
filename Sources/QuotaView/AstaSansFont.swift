import CoreText
import Foundation
import SwiftUI

enum AstaSans {
    private enum Face {
        static let regular = "AstaSans-Regular"
        static let medium = "AstaSans-Medium"
        static let semiBold = "AstaSans-SemiBold"
    }

    static func regular(_ size: CGFloat) -> Font {
        .custom(Face.regular, size: size)
    }

    static func medium(_ size: CGFloat) -> Font {
        .custom(Face.medium, size: size)
    }

    static func semiBold(_ size: CGFloat) -> Font {
        .custom(Face.semiBold, size: size)
    }
}

enum AstaSansFontRegistrar {
    private static var hasRegisteredFonts = false

    static func registerBundledFonts() {
        guard !hasRegisteredFonts else { return }
        hasRegisteredFonts = true

        let fontNames = [
            "AstaSans-Regular",
            "AstaSans-Medium",
            "AstaSans-SemiBold"
        ]

        for fontName in fontNames {
            guard let fontURL = Bundle.main.url(
                forResource: fontName,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else {
                assertionFailure("Missing bundled font: \(fontName)")
                continue
            }

            CTFontManagerRegisterFontsForURL(
                fontURL as CFURL,
                .process,
                nil
            )
        }
    }
}
