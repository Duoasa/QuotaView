import AppKit
import SwiftUI

// Reuses the public Codex answer verbatim as Markdown input. Parsing and layout
// live in the detail-metrics cache, never in an animation or polling callback.
final class IslandMarkdownResultLayout {
    let text: NSAttributedString
    let height: CGFloat
    let width: CGFloat

    convenience init(source: String, width: CGFloat) {
        self.init(text: Self.render(source), width: width)
    }

    convenience init(plainText: String, width: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.lineBreakMode = .byWordWrapping
        self.init(text: NSAttributedString(string: plainText, attributes: [
            .font: NSFont.systemFont(ofSize: IslandTaskDetailMetrics.bodyFont),
            .foregroundColor: IslandTextPalette.secondary, .paragraphStyle: paragraph
        ]), width: width)
    }

    private init(text: NSAttributedString, width: CGFloat) {
        self.width = max(40, width)
        self.text = text
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: self.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        height = max(20, ceil(manager.usedRect(for: container).height))
    }

    private static func render(_ source: String) -> NSAttributedString {
        // Codex stores this citation metadata after its visible answer. Keep the
        // source intact in the trace, but do not expose its internal XML as prose.
        var visible = source
        while let start = visible.range(of: "<oai-mem-citation>") {
            let end = visible.range(of: "</oai-mem-citation>", range: start.upperBound..<visible.endIndex)?.upperBound ?? visible.endIndex
            visible.removeSubrange(start.lowerBound..<end)
        }
        let parsed = (try? AttributedString(markdown: visible,
            options: .init(interpretedSyntax: .full))) ?? AttributedString(visible)
        let result = NSMutableAttributedString(string: "")
        var previousBlock: Int?
        var previousRow: Int?
        var previousListItem: Int?
        for run in parsed.runs {
            let intents = run.presentationIntent?.components ?? []
            let block = intents.first?.identity
            let row = intents.first { intent in
                switch intent.kind { case .tableRow, .tableHeaderRow: true; default: false }
            }?.identity
            let listItem = intents.first { if case .listItem = $0.kind { return true }; return false }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 6
            paragraph.lineBreakMode = .byWordWrapping
            var size: CGFloat = IslandTaskDetailMetrics.bodyFont
            var heading = false
            var quote = false
            var bold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            var code = run.inlinePresentationIntent?.contains(.code) == true
            var prefix = ""
            for intent in intents {
                switch intent.kind {
                case .header(let level): size = level == 1 ? 16 : (level == 2 ? 14 : 13); bold = true; heading = true
                case .codeBlock: code = true
                case .blockQuote: quote = true; paragraph.headIndent += 12; paragraph.firstLineHeadIndent += 12
                case .listItem(let ordinal):
                    let ordered = intents.contains { $0.kind == .orderedList }
                    prefix = ordered ? "\(ordinal). " : "• "
                    paragraph.headIndent += 18
                default: break
                }
            }
            if block != previousBlock {
                if result.length > 0 {
                    result.append(NSAttributedString(string: row != nil && row == previousRow ? "\t" : "\n",
                        attributes: [.font: NSFont.systemFont(ofSize: IslandTaskDetailMetrics.bodyFont), .paragraphStyle: paragraph]))
                }
                if listItem?.identity == previousListItem { prefix = "" }
                previousBlock = block; previousRow = row; previousListItem = listItem?.identity
            } else { prefix = "" }
            var font = code ? NSFont.monospacedSystemFont(ofSize: 12, weight: bold ? .semibold : .regular)
                : NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            if run.inlinePresentationIntent?.contains(.emphasized) == true {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            // Opaque tones keep prose quieter than the result title, while
            // preserving the emphasis and headings in Codex's actual answer.
            let color = heading ? NSColor(white: 0.92, alpha: 1)
                : (bold ? NSColor(white: 0.85, alpha: 1)
                    : (quote ? NSColor(white: 0.56, alpha: 1) : IslandTextPalette.secondary))
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ]
            if code { attributes[.backgroundColor] = NSColor(white: 0.10, alpha: 1) }
            if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link, IslandResultLink.destination(link) != nil {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.systemBlue
            }
            result.append(NSAttributedString(string: prefix + String(parsed[run.range].characters), attributes: attributes))
        }
        // Paragraph spacing separates blocks; it must not reserve blank space
        // below the last line and force a short answer into the two-row card.
        if result.length > 0,
           let style = result.attribute(.paragraphStyle, at: result.length - 1, effectiveRange: nil) as? NSParagraphStyle,
           let trailing = style.mutableCopy() as? NSMutableParagraphStyle {
            trailing.paragraphSpacing = 0
            let range = (result.string as NSString).paragraphRange(for: NSRange(location: result.length - 1, length: 0))
            result.addAttribute(.paragraphStyle, value: trailing, range: range)
        }
        return result
    }
}

enum IslandResultLink {
    static func destination(_ url: URL) -> URL? {
        if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { return url.host == nil ? nil : url }
        // Codex local references can be absolute Markdown paths with a :line
        // suffix. Reveal the target in Finder without invoking an executable.
        guard url.isFileURL || (url.scheme == nil && url.path.hasPrefix("/")) else { return nil }
        let path = url.path.replacingOccurrences(of: #":\d+(?::\d+)?$"#, with: "", options: .regularExpression)
        return URL(fileURLWithPath: path)
    }
    static func open(_ url: URL) {
        guard let destination = destination(url) else { return }
        if destination.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        else { NSWorkspace.shared.open(destination) }
    }
}

private final class IslandResultTextView: NSTextView, NSTextViewDelegate {
    private let resultStorage: NSTextStorage
    private var renderedLayout: IslandMarkdownResultLayout?
    init() {
        // This designated initializer does not create a text system for nil.
        // Wire and retain the actual display stack, independently of the
        // temporary stack used to measure the cached result above.
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 40, height: CGFloat.greatestFiniteMagnitude))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        resultStorage = storage
        super.init(frame: .zero, textContainer: container)
        drawsBackground = false; isEditable = false; isSelectable = true
        isRichText = true; importsGraphics = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.heightTracksTextView = false
        isHorizontallyResizable = false; isVerticallyResizable = false
        linkTextAttributes = [.foregroundColor: NSColor.systemBlue, .cursor: NSCursor.pointingHand]
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ layout: IslandMarkdownResultLayout) {
        guard renderedLayout !== layout else { return }
        renderedLayout = layout
        textContainer?.containerSize = NSSize(width: layout.width, height: .greatestFiniteMagnitude)
        resultStorage.setAttributedString(layout.text)
        invalidateIntrinsicContentSize()
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { IslandResultLink.open(url) }
        else if let text = link as? String, let url = URL(string: text) { IslandResultLink.open(url) }
        return true
    }
}

struct IslandMarkdownResultView: NSViewRepresentable {
    let layout: IslandMarkdownResultLayout
    func makeNSView(context: Context) -> NSTextView { IslandResultTextView() }
    func updateNSView(_ view: NSTextView, context: Context) { (view as? IslandResultTextView)?.configure(layout) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        CGSize(width: layout.width, height: layout.height)
    }
}
