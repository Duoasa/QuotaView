import Foundation

/// Keeps values separate from translatable copy so paths, account names and task text
/// never pass through translation or script conversion.
struct LocalizedCopy: Equatable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let template: String
    let arguments: [String]

    init(_ value: String) { template = value; arguments = [] }
    init(stringLiteral value: String) { self.init(value) }
    init(stringInterpolation: StringInterpolation) {
        template = stringInterpolation.template
        arguments = stringInterpolation.arguments
    }
    struct StringInterpolation: StringInterpolationProtocol {
        var template = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {
            template.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        mutating func appendLiteral(_ literal: String) { template += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            template += "{{\(arguments.count)}}"
            arguments.append(String(describing: value))
        }
    }
    func render(_ translated: String? = nil) -> String {
        let format = translated ?? template
        let regex = AppLocalization.placeholderPattern
        let matches = regex.matches(in: format, range: NSRange(format.startIndex..., in: format))
        var result = "", position = format.startIndex
        for match in matches {
            guard let range = Range(match.range, in: format),
                  let indexRange = Range(match.range(at: 1), in: format),
                  let index = Int(format[indexRange]), arguments.indices.contains(index) else { continue }
            result += format[position..<range.lowerBound]
            result += arguments[index]
            position = range.upperBound
        }
        result += format[position...]
        return result
    }
}

enum AppLocalization {
    static let placeholderPattern = try! NSRegularExpression(pattern: #"\{\{(\d+)\}\}"#)
    static let translations: [String: [String: String]] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "AppTranslations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return values
    }()

    // NSCache is thread-safe; convert fixed UI templates once, never interpolated user data.
    private static let traditionalTemplates: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 1024
        return cache
    }()

    static func text(chinese: LocalizedCopy, english: LocalizedCopy, language: String) -> String {
        let parts = language.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
        let identifier: String
        if parts.first == "zh" {
            identifier = !parts.contains("hans") && (parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo")) ? "zh-Hant" : "zh-Hans"
        } else { identifier = parts.first.map(String.init) ?? "en" }
        switch identifier {
        case "zh-Hans": return chinese.render()
        case "zh-Hant":
            let key = chinese.template as NSString
            if let cached = traditionalTemplates.object(forKey: key) { return chinese.render(cached as String) }
            let template = chinese.template.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? chinese.template
            traditionalTemplates.setObject(template as NSString, forKey: key)
            return chinese.render(template)
        case "en": return english.render()
        default:
            return english.render(translations[english.template]?[identifier])
        }
    }
}
