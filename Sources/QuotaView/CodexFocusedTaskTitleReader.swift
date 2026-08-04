import ApplicationServices
import Foundation

enum CodexActivityFocusTrackingStatus: Equatable {
    case disabled
    case permissionRequired
    case tracking
}

/// Reads only the title of the active Codex task. The traversal is bounded to
/// the top portion of the focused window and never reads document text,
/// prompts, responses, controls outside that region, or editable values.
struct CodexFocusedTaskTitleReader: Sendable {
    private static let maximumTraversalDepth = 8
    private static let maximumVisitedElements = 120

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccess() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func currentTaskTitle(
        processIdentifier: pid_t,
        matching knownTitles: [String]
    ) -> String? {
        guard isTrusted else { return nil }

        let normalizedKnownTitles = Set(
            knownTitles.compactMap(Self.normalizedTitle)
        )
        guard !normalizedKnownTitles.isEmpty else { return nil }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard let focusedWindow = elementAttribute(
            application,
            attribute: kAXFocusedWindowAttribute as CFString
        ),
        let windowFrame = frame(of: focusedWindow)
        else {
            return nil
        }

        // Codex keeps its sidebar on the leading edge. Limit inspection to
        // the main content header where the verified current-task button is
        // exposed, and read title strings only from matching AXButton nodes.
        let sidebarExclusion = min(
            max(windowFrame.width * 0.22, 220),
            320
        )
        let titleRegion = CGRect(
            x: windowFrame.minX + sidebarExclusion,
            y: windowFrame.minY,
            width: max(0, windowFrame.width - sidebarExclusion),
            height: min(180, windowFrame.height)
        )

        var budget = Self.maximumVisitedElements
        var matches = Set<String>()
        collectMatchingButtonTitles(
            in: focusedWindow,
            titleRegion: titleRegion,
            knownTitles: normalizedKnownTitles,
            depth: 0,
            budget: &budget,
            matches: &matches
        )
        return matches.count == 1 ? matches.first : nil
    }

    private func collectMatchingButtonTitles(
        in element: AXUIElement,
        titleRegion: CGRect,
        knownTitles: Set<String>,
        depth: Int,
        budget: inout Int,
        matches: inout Set<String>
    ) {
        guard depth <= Self.maximumTraversalDepth,
              budget > 0,
              matches.count < 2
        else {
            return
        }
        budget -= 1

        if let elementFrame = frame(of: element),
           !elementFrame.intersects(titleRegion)
        {
            return
        }

        if stringAttribute(
            element,
            attribute: kAXRoleAttribute as CFString
        ) == (kAXButtonRole as String),
        let elementFrame = frame(of: element),
        elementFrame.intersects(titleRegion),
        let title = stringAttribute(
            element,
            attribute: kAXTitleAttribute as CFString
        ),
        let normalized = Self.normalizedTitle(title),
        knownTitles.contains(normalized)
        {
            matches.insert(normalized)
            return
        }

        for child in elementArrayAttribute(
            element,
            attribute: kAXChildrenAttribute as CFString
        ) {
            collectMatchingButtonTitles(
                in: child,
                titleRegion: titleRegion,
                knownTitles: knownTitles,
                depth: depth + 1,
                budget: &budget,
                matches: &matches
            )
            if matches.count > 1 || budget == 0 {
                return
            }
        }
    }

    private func elementAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func elementArrayAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success,
        let array = value as? [Any]
        else {
            return []
        }

        return array.compactMap { item in
            let item = item as CFTypeRef
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(item, to: AXUIElement.self)
        }
    }

    private func stringAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success
        else {
            return nil
        }
        return value as? String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            unsafeBitCast(positionValue, to: AXValue.self),
            .cgPoint,
            &position
        ),
        AXValueGetValue(
            unsafeBitCast(sizeValue, to: AXValue.self),
            .cgSize,
            &size
        )
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func normalizedTitle(_ title: String) -> String? {
        let normalized = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty,
              normalized != "ChatGPT",
              normalized != "Codex"
        else {
            return nil
        }
        return String(normalized.prefix(120))
    }
}
