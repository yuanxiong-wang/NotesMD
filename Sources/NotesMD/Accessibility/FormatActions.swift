import AppKit
import Carbon
import NotesMDCore


enum FormatActions {
    static let formatMenuAliases = ["Format", "格式"]
    static let fontMenuAliases = ["Font", "字体"]

    static func applyParagraph(_ style: NativeParagraphStyle, activate: Bool = true) {
        if activate { NotesBridge.activate() }
        usleep(activate ? 80_000 : 30_000)
        _ = AXBridge.clickMenu(path: [formatMenuAliases, style.menuAliases])
    }

    static func selectToLineStart() {
        postKey(CGKeyCode(kVK_LeftArrow), flags: [.maskCommand, .maskShift])
    }

    static func collapseToEnd() {
        postKey(CGKeyCode(kVK_RightArrow), flags: [])
    }

    static func deleteSelection() {
        postKey(CGKeyCode(kVK_Delete), flags: [])
    }

    static func findInNote(_ text: String) {
        NotesBridge.activate()
        usleep(80_000)
        postKey(CGKeyCode(kVK_ANSI_F), flags: .maskCommand)
        usleep(120_000)
        pastePlain(text)
        usleep(180_000)
        postKey(CGKeyCode(kVK_Return), flags: [])
        usleep(80_000)
        postKey(CGKeyCode(kVK_Escape), flags: [])
    }

    static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for ch in text.utf16 {
            var char = ch
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    static func applyInline(_ style: NativeInlineStyle) {
        NotesBridge.activate()
        usleep(80_000)
        if let key = keystroke(for: style) {
            postKey(key.0, flags: key.1)
            return
        }
        if style == .link {
            postKey(CGKeyCode(kVK_ANSI_K), flags: .maskCommand)
            return
        }
        _ = AXBridge.clickMenu(path: [formatMenuAliases, fontMenuAliases, style.menuAliases])
            || AXBridge.clickMenu(path: [formatMenuAliases, style.menuAliases])
    }

    static func pasteHTML(_ html: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.backup()
        pasteboard.writeHTML(html)
        NotesBridge.activate()
        usleep(100_000)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            previous.restore(to: pasteboard)
        }
    }

    static func pastePlain(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.backup()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NotesBridge.activate()
        usleep(100_000)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            previous.restore(to: pasteboard)
        }
    }

    static func copyPlain(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func applyPlan(_ plan: MarkdownPlan) {
        switch plan {
        case .noChange:
            break
        case .applyParagraph(let style, let replacement):
            if !AXBridge.replaceSelectedText(replacement) {
                pastePlain(replacement)
                usleep(180_000)
            }
            applyParagraph(style)
        case .applyInline(let style, let replacement):
            if !AXBridge.replaceSelectedText(replacement) {
                pastePlain(replacement)
                usleep(180_000)
            }
            applyInline(style)
        case .pasteHTML(let html):
            pasteHTML(html)
        }
    }

    static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    private static func keystroke(for style: NativeInlineStyle) -> (CGKeyCode, CGEventFlags)? {
        switch style {
        case .bold: return (CGKeyCode(kVK_ANSI_B), .maskCommand)
        case .italic: return (CGKeyCode(kVK_ANSI_I), .maskCommand)
        case .underline: return (CGKeyCode(kVK_ANSI_U), .maskCommand)
        default: return nil
        }
    }
}

struct PasteboardBackup {
    var items: [[String: Data]]

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for item in items {
            pasteboard.declareTypes(item.keys.map { NSPasteboard.PasteboardType($0) }, owner: nil)
            for (type, data) in item {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
        }
    }
}

extension NSPasteboard {
    func backup() -> PasteboardBackup {
        let items: [[String: Data]] = (pasteboardItems ?? []).map { item in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return dict
        }
        return PasteboardBackup(items: items)
    }

    func writeHTML(_ html: String) {
        let document = """
        <html><head><meta charset="utf-8"></head><body>\(html)</body></html>
        """
        clearContents()
        if let data = document.data(using: .utf8) {
            setData(data, forType: .html)
        }
        let plain = NotesMarkdown.htmlToMarkdown(html)
        setString(plain, forType: .string)
        if let attr = try? NSAttributedString(
            data: document.data(using: .utf8) ?? Data(),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            let rtf = attr.rtf(from: NSRange(location: 0, length: attr.length))
            if let rtf {
                setData(rtf, forType: .rtf)
            }
        }
    }
}
