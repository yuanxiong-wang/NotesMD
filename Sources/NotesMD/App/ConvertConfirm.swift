import AppKit

enum ConvertConfirm {
    @MainActor
    static func confirmReplace(noteName: String, current: String, after: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace this note’s body?"
        alert.informativeText = "「\(noteName)」的全文會被 Markdown 轉換後的格式覆寫。\n\nHere's what will change. Proceed?"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Replace")

        let preview = """
        Current:
        \(clip(current))

        After:
        \(clip(after))
        """
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        textView.string = preview
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.backgroundColor = .textBackgroundColor

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll

        let previous = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let response = alert.runModal()
        NSApp.setActivationPolicy(previous)
        return response == .alertSecondButtonReturn
    }

    private static func clip(_ text: String, maxLines: Int = 24, maxChars: Int = 1800) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty)" }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var omitted = false
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            omitted = true
        }
        var body = lines.joined(separator: "\n")
        if body.count > maxChars {
            body = String(body.prefix(maxChars))
            omitted = true
        }
        if omitted { body += "\n…" }
        return body
    }
}
