import AppKit
import ApplicationServices

enum AXBridge {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func notesElement() -> AXUIElement? {
        guard let pid = NotesBridge.pid else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard status == .success else { return nil }
        return value
    }

    static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let values = attribute(element, kAXChildrenAttribute as String) as? [AnyObject] else {
            return []
        }
        return values.compactMap(Self.asElement)
    }

    private static func asElement(_ raw: AnyObject?) -> AXUIElement? {
        guard let raw else { return nil }
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    static func role(_ element: AXUIElement) -> String {
        stringAttribute(element, kAXRoleAttribute as String) ?? ""
    }

    static func title(_ element: AXUIElement) -> String {
        stringAttribute(element, kAXTitleAttribute as String)
            ?? stringAttribute(element, kAXDescriptionAttribute as String)
            ?? ""
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func focusedElement() -> AXUIElement? {
        guard let app = notesElement() else { return nil }
        return asElement(attribute(app, kAXFocusedUIElementAttribute as String))
    }

    static func selectedText() -> String {
        if let focused = focusedElement(),
           let text = stringAttribute(focused, kAXSelectedTextAttribute as String),
           !text.isEmpty {
            return text
        }
        return selectedTextByWalk()
    }

    static func replaceSelectedText(_ text: String) -> Bool {
        guard let focused = focusedElement() else { return false }
        let status = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return status == .success
    }

    static func selectedTextByWalk() -> String {
        guard let app = notesElement() else { return "" }
        var stack = children(app)
        var seen = 0
        while let el = stack.popLast(), seen < 400 {
            seen += 1
            if let text = stringAttribute(el, kAXSelectedTextAttribute as String), !text.isEmpty {
                return text
            }
            stack.append(contentsOf: children(el))
        }
        return ""
    }

    static func enableEnhancedAccessibility() {
        guard let app = notesElement() else { return }
        AXUIElementSetAttributeValue(
            app,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
    }

    static func isSearchField(_ element: AXUIElement) -> Bool {
        let r = role(element)
        if r == "AXSearchField" { return true }
        if r == "AXTextField" { return true }
        let t = title(element).lowercased()
        return t.contains("search") || t.contains("搜索")
    }

    static func isEditingNoteBody() -> Bool {
        guard let focused = focusedElement() else { return true }
        if isSearchField(focused) { return false }
        let r = role(focused)
        if r == "AXMenu" || r == "AXMenuItem" || r == "AXButton" { return false }
        return true
    }

    static func focusedFrame() -> CGRect? {
        guard let focused = focusedElement() else { return nil }
        return cocoaFrame(of: focused)
    }

    static func selectionBounds() -> CGRect? {
        boundsForSelectedRange(of: focusedElement())
    }

    static func caretAnchor() -> CGRect? {
        if let focused = focusedElement(), !isSearchField(focused) {
            if let bounds = boundsForSelectedRange(of: focused) {
                if bounds.width < 3 {
                    return CGRect(x: bounds.minX, y: bounds.minY, width: 14, height: max(bounds.height, 16))
                }
                return bounds
            }
        }
        if let editor = editorFrame() {
            return CGRect(x: editor.minX + 28, y: editor.maxY - 72, width: 14, height: 18)
        }
        return nil
    }

    static func editorFrame() -> CGRect? {
        guard let app = notesElement() else { return nil }
        let window: AXUIElement? = asElement(attribute(app, kAXFocusedWindowAttribute as String))
            ?? (attribute(app, kAXWindowsAttribute as String) as? [AnyObject])?.compactMap(Self.asElement).first
        guard let window else { return nil }

        var best: CGRect?
        var stack = children(window)
        var seen = 0
        while let el = stack.popLast(), seen < 280 {
            seen += 1
            let r = role(el)
            if ["AXTextArea", "AXWebArea", "AXScrollArea", "AXGroup"].contains(r),
               let frame = cocoaFrame(of: el),
               frame.width > 280, frame.height > 180 {
                let area = frame.width * frame.height
                if best == nil || area > (best!.width * best!.height) {
                    best = frame
                }
            }
            stack.append(contentsOf: children(el))
        }
        if let best { return best }
        guard let win = cocoaFrame(of: window) else { return nil }
        return CGRect(
            x: win.minX + win.width * 0.40,
            y: win.minY + 56,
            width: win.width * 0.58,
            height: max(120, win.height - 80)
        )
    }

    private static func boundsForSelectedRange(of element: AXUIElement?) -> CGRect? {
        guard let element else { return nil }
        if let rangeValue = attribute(element, kAXSelectedTextRangeAttribute as String) {
            var boundsRef: AnyObject?
            let status = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsRef
            )
            if status == .success, let rect = cgRect(from: boundsRef), rect.width >= 0, rect.height > 1 {
                return quartzToCocoa(rect)
            }
        }
        return nil
    }

    static func linePrefixToCaret() -> String? {
        guard let focused = focusedElement() else { return nil }
        guard let value = stringAttribute(focused, kAXValueAttribute as String) else { return nil }
        guard let range = cfRange(from: focused) else { return nil }
        let ns = value as NSString
        let caret = max(0, min(range.location, ns.length))
        if caret == 0 { return "" }
        let before = ns.substring(to: caret)
        if let newline = before.lastIndex(of: "\n") {
            return String(before[before.index(after: newline)...])
        }
        return before
    }

    static func cocoaFrame(of element: AXUIElement) -> CGRect? {
        guard let pos = cgPoint(from: attribute(element, kAXPositionAttribute as String)),
              let size = cgSize(from: attribute(element, kAXSizeAttribute as String)) else {
            return nil
        }
        return quartzToCocoa(CGRect(origin: pos, size: size))
    }

    private static func cfRange(from element: AXUIElement) -> CFRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute as String) else { return nil }
        var range = CFRange(location: 0, length: 0)
        let ax = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetValue(ax, .cfRange, &range) else { return nil }
        return range
    }

    private static func cgRect(from raw: AnyObject?) -> CGRect? {
        guard let raw else { return nil }
        var rect = CGRect.zero
        let ax = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetValue(ax, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func cgPoint(from raw: AnyObject?) -> CGPoint? {
        guard let raw else { return nil }
        var point = CGPoint.zero
        let ax = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetValue(ax, .cgPoint, &point) else { return nil }
        return point
    }

    private static func cgSize(from raw: AnyObject?) -> CGSize? {
        guard let raw else { return nil }
        var size = CGSize.zero
        let ax = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetValue(ax, .cgSize, &size) else { return nil }
        return size
    }

    static func quartzToCocoa(_ rect: CGRect) -> CGRect {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: rect.origin.x,
            y: height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func clickMenu(path aliases: [[String]]) -> Bool {
        guard let app = notesElement() else { return false }
        guard let menuBar = asElement(attribute(app, kAXMenuBarAttribute as String)) else {
            return false
        }
        return click(from: menuBar, remaining: aliases)
    }

    private static func click(from node: AXUIElement, remaining: [[String]]) -> Bool {
        guard let names = remaining.first else { return press(node) }
        for child in children(node) {
            let t = title(child)
            if names.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                let rest = Array(remaining.dropFirst())
                if rest.isEmpty {
                    return press(child)
                }
                let menus = children(child)
                let nextRoot = menus.first(where: { role($0) == kAXMenuRole as String }) ?? child
                if click(from: nextRoot, remaining: rest) {
                    return true
                }
            }
            if role(child) == (kAXMenuRole as String) {
                if click(from: child, remaining: remaining) {
                    return true
                }
            }
        }
        return false
    }
}
