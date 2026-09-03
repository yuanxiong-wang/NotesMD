import Foundation

public struct TypingTrigger: Equatable, Sendable {
    public var marker: String
    public var style: NativeParagraphStyle
}

public struct NoteHeading: Equatable, Sendable, Identifiable {
    public var level: Int
    public var text: String
    public var id: String { "\(level)-\(text)" }

    public init(level: Int, text: String) {
        self.level = level
        self.text = text
    }
}

public enum SlashKind: Equatable, Sendable {
    case paragraph(NativeParagraphStyle)
    case inline(NativeInlineStyle)
    case datetime
    case templates
    case toc
    case quickOpen
}

public struct SlashCommand: Equatable, Sendable, Identifiable {
    public var token: String
    public var title: String
    public var subtitle: String
    public var symbol: String
    public var kind: SlashKind
    public var aliases: [String]

    public var id: String { token }

    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        if token.lowercased().hasPrefix(q) || token.lowercased().contains(q) { return true }
        if title.lowercased().contains(q) { return true }
        return aliases.contains { $0.lowercased().contains(q) }
    }
}

public enum MarkdownTyping {
    public static let slashCommands: [SlashCommand] = [
        SlashCommand(token: "title", title: "Title", subtitle: "# + space", symbol: "textformat.size.larger", kind: .paragraph(.title), aliases: ["h1", "标题"]),
        SlashCommand(token: "heading", title: "Heading", subtitle: "## + space", symbol: "textformat", kind: .paragraph(.heading), aliases: ["h2", "小标题"]),
        SlashCommand(token: "subheading", title: "Subheading", subtitle: "### + space", symbol: "textformat.subscript", kind: .paragraph(.subheading), aliases: ["h3", "副标题"]),
        SlashCommand(token: "body", title: "Body", subtitle: "正文", symbol: "text.alignleft", kind: .paragraph(.body), aliases: ["正文"]),
        SlashCommand(token: "code", title: "Monostyled", subtitle: "``` + space", symbol: "chevron.left.forwardslash.chevron.right", kind: .paragraph(.monostyled), aliases: ["mono", "等宽"]),
        SlashCommand(token: "quote", title: "Block Quote", subtitle: "> + space", symbol: "text.quote", kind: .paragraph(.blockQuote), aliases: ["引用"]),
        SlashCommand(token: "bullet", title: "Bulleted List", subtitle: "- + space", symbol: "list.bullet", kind: .paragraph(.bulleted), aliases: ["ul", "list"]),
        SlashCommand(token: "number", title: "Numbered List", subtitle: "1. + space", symbol: "list.number", kind: .paragraph(.numbered), aliases: ["ol"]),
        SlashCommand(token: "dash", title: "Dashed List", subtitle: "短划线列表", symbol: "list.dash", kind: .paragraph(.dashed), aliases: ["dashed"]),
        SlashCommand(token: "todo", title: "Checklist", subtitle: "[] + space", symbol: "checklist", kind: .paragraph(.checklist), aliases: ["check", "checklist", "核对"]),
        SlashCommand(token: "bold", title: "Bold", subtitle: "⌘B", symbol: "bold", kind: .inline(.bold), aliases: ["粗体"]),
        SlashCommand(token: "italic", title: "Italic", subtitle: "⌘I", symbol: "italic", kind: .inline(.italic), aliases: ["斜体"]),
        SlashCommand(token: "link", title: "Add Link", subtitle: "⌘K", symbol: "link", kind: .inline(.link), aliases: ["链接"]),
        SlashCommand(token: "datetime", title: "Insert date & time", subtitle: "当前日期时间", symbol: "calendar", kind: .datetime, aliases: ["date", "time", "now"]),
        SlashCommand(token: "template", title: "Insert template", subtitle: "Templates / 模板 folder", symbol: "doc.badge.plus", kind: .templates, aliases: ["tpl", "模板"]),
        SlashCommand(token: "toc", title: "Table of contents", subtitle: "当前笔记目录", symbol: "list.bullet.indent", kind: .toc, aliases: ["outline", "目录"]),
        SlashCommand(token: "open", title: "Quick Open", subtitle: "⌘O", symbol: "magnifyingglass", kind: .quickOpen, aliases: ["goto", "jump"])
    ]

    /// `line` is the current line including a trailing space just typed.
    public static func triggerAfterSpace(line: String) -> TypingTrigger? {
        let trimmedEnd = line.replacingOccurrences(of: "\t", with: " ")
        guard trimmedEnd.hasSuffix(" ") else { return nil }
        let prefix = String(trimmedEnd.dropLast()).trimmingCharacters(in: .whitespaces)
        return trigger(forMarker: prefix)
    }

    public static func trigger(forMarker prefix: String) -> TypingTrigger? {
        switch prefix {
        case "#":
            return TypingTrigger(marker: "# ", style: .title)
        case "##":
            return TypingTrigger(marker: "## ", style: .heading)
        case "###", "####":
            return TypingTrigger(marker: prefix + " ", style: .subheading)
        case ">":
            return TypingTrigger(marker: "> ", style: .blockQuote)
        case "```", "···", "...":
            return TypingTrigger(marker: prefix + " ", style: .monostyled)
        case "[]", "[ ]", "- []", "- [ ]", "* []", "* [ ]", "【】", "【 】":
            return TypingTrigger(marker: prefix + " ", style: .checklist)
        case "-", "*", "+":
            return TypingTrigger(marker: prefix + " ", style: .bulleted)
        default:
            if isOrderedMarker(prefix) {
                return TypingTrigger(marker: prefix + " ", style: .numbered)
            }
            return nil
        }
    }

    public static func isCJKNoteLink(_ text: String) -> Bool {
        text.hasSuffix("》》") || text.hasSuffix("》〉") || text.hasSuffix("〉》")
    }

    public static func isSlashLine(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("/") else { return false }
        let rest = t.dropFirst()
        return !rest.contains(where: { $0.isWhitespace })
    }

    public static func slashQuery(from line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("/") else { return "" }
        return String(t.dropFirst())
    }

    public static func headings(inHTML html: String) -> [NoteHeading] {
        let tokens = HTMLTokenizer.tokenize(html)
        var result: [NoteHeading] = []
        var i = 0
        while i < tokens.count {
            if case .open(let name, _) = tokens[i], let level = headingLevel(name) {
                i += 1
                var text = ""
                while i < tokens.count {
                    if case .close(let n) = tokens[i], headingLevel(n) == level { break }
                    if case .text(let t) = tokens[i] { text += t }
                    i += 1
                }
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    result.append(NoteHeading(level: level, text: cleaned))
                }
            }
            i += 1
        }
        return result
    }

    public static func currentDateTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private static func isOrderedMarker(_ prefix: String) -> Bool {
        guard prefix.hasSuffix(".") else { return false }
        let number = prefix.dropLast()
        return !number.isEmpty && number.allSatisfy(\.isNumber)
    }

    private static func headingLevel(_ name: String) -> Int? {
        switch name {
        case "h1": return 1
        case "h2": return 2
        case "h3": return 3
        default: return nil
        }
    }
}
