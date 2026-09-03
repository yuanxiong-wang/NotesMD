import Foundation

public enum NativeParagraphStyle: String, CaseIterable, Sendable, Identifiable {
    case title
    case heading
    case subheading
    case body
    case monostyled
    case bulleted
    case dashed
    case numbered
    case checklist
    case blockQuote

    public var id: String { rawValue }

    public var englishMenuName: String {
        switch self {
        case .title: return "Title"
        case .heading: return "Heading"
        case .subheading: return "Subheading"
        case .body: return "Body"
        case .monostyled: return "Monostyled"
        case .bulleted: return "Bulleted List"
        case .dashed: return "Dashed List"
        case .numbered: return "Numbered List"
        case .checklist: return "Checklist"
        case .blockQuote: return "Block Quote"
        }
    }

    public var chineseMenuName: String {
        switch self {
        case .title: return "标题"
        case .heading: return "小标题"
        case .subheading: return "副标题"
        case .body: return "正文"
        case .monostyled: return "等宽样式"
        case .bulleted: return "项目符号列表"
        case .dashed: return "短划线列表"
        case .numbered: return "编号列表"
        case .checklist: return "核对清单"
        case .blockQuote: return "块引用"
        }
    }

    public var menuAliases: [String] {
        [englishMenuName, chineseMenuName]
    }
}

public enum NativeInlineStyle: String, CaseIterable, Sendable, Identifiable {
    case bold
    case italic
    case underline
    case strikethrough
    case highlight
    case link

    public var id: String { rawValue }

    public var englishMenuName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .highlight: return "Highlight"
        case .link: return "Add Link…"
        }
    }

    public var chineseMenuName: String {
        switch self {
        case .bold: return "粗体"
        case .italic: return "斜体"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .highlight: return "高亮标记"
        case .link: return "添加链接…"
        }
    }

    public var menuAliases: [String] {
        switch self {
        case .link:
            return ["Add Link…", "Add Link...", "Add Link", "添加链接…", "添加链接..."]
        default:
            return [englishMenuName, chineseMenuName]
        }
    }
}

public enum MarkdownPlan: Sendable, Equatable {
    case applyParagraph(NativeParagraphStyle, replacement: String)
    case applyInline(NativeInlineStyle, replacement: String)
    case pasteHTML(String)
    case noChange
}

public enum MarkdownPlanner {
    public static func plan(for selection: String) -> MarkdownPlan {
        let text = selection.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noChange }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if nonEmpty.count == 1, let line = nonEmpty.first {
            if let planned = planSingleLine(line) {
                return planned
            }
        }

        if NotesMarkdown.looksLikeMarkdown(text) {
            return .pasteHTML(NotesMarkdown.markdownToHTML(text))
        }

        return .noChange
    }

    private static func planSingleLine(_ line: String) -> MarkdownPlan? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let rest = stripPrefix(trimmed, "# ") {
            return .applyParagraph(.title, replacement: rest)
        }
        if let rest = stripPrefix(trimmed, "## ") {
            return .applyParagraph(.heading, replacement: rest)
        }
        if let rest = stripPrefix(trimmed, "### ") {
            return .applyParagraph(.subheading, replacement: rest)
        }
        if let rest = stripPrefix(trimmed, "#### ") {
            return .applyParagraph(.subheading, replacement: rest)
        }
        if let rest = stripPrefix(trimmed, "> ") {
            return .applyParagraph(.blockQuote, replacement: rest)
        }
        if let rest = stripTask(trimmed) {
            return .applyParagraph(.checklist, replacement: rest)
        }
        if let rest = stripPrefix(trimmed, "- "), !rest.hasPrefix("[") {
            return .applyParagraph(.bulleted, replacement: rest)
        }
        if let rest = stripPrefix(trimmed, "* "), !rest.hasPrefix("*") {
            return .applyParagraph(.bulleted, replacement: rest)
        }
        if let rest = stripPrefix(trimmed, "+ ") {
            return .applyParagraph(.bulleted, replacement: rest)
        }
        if let rest = stripOrdered(trimmed) {
            return .applyParagraph(.numbered, replacement: rest)
        }

        if trimmed.hasPrefix("`") && trimmed.hasSuffix("`") && trimmed.count >= 3 && !trimmed.dropFirst().dropLast().contains("`") {
            let inner = String(trimmed.dropFirst().dropLast())
            return .applyParagraph(.monostyled, replacement: inner)
        }

        if let (style, inner) = unwrapInline(trimmed) {
            return .applyInline(style, replacement: inner)
        }

        if NotesMarkdown.looksLikeMarkdown(trimmed) {
            return .pasteHTML(NotesMarkdown.markdownToHTML(trimmed))
        }

        return nil
    }

    private static func stripPrefix(_ line: String, _ prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func stripTask(_ line: String) -> String? {
        let patterns = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] "]
        for prefix in patterns {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func stripOrdered(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        guard !number.isEmpty, number.allSatisfy({ $0.isNumber }) else { return nil }
        let after = line[line.index(after: dot)...]
        guard after.hasPrefix(" ") else { return nil }
        return String(after.dropFirst())
    }

    private static func unwrapInline(_ line: String) -> (NativeInlineStyle, String)? {
        if let inner = unwrap(line, "~~") {
            return (.strikethrough, inner)
        }
        if let inner = unwrap(line, "**") {
            return (.bold, inner)
        }
        if let inner = unwrap(line, "__") {
            return (.bold, inner)
        }
        if let inner = unwrap(line, "==") {
            return (.highlight, inner)
        }
        if line.hasPrefix("*"), line.hasSuffix("*"), line.count >= 3, !line.hasPrefix("**") {
            return (.italic, String(line.dropFirst().dropLast()))
        }
        if line.hasPrefix("_"), line.hasSuffix("_"), line.count >= 3, !line.hasPrefix("__") {
            return (.italic, String(line.dropFirst().dropLast()))
        }
        return nil
    }

    private static func unwrap(_ line: String, _ token: String) -> String? {
        guard line.hasPrefix(token), line.hasSuffix(token), line.count >= token.count * 2 + 1 else {
            return nil
        }
        let inner = String(line.dropFirst(token.count).dropLast(token.count))
        guard !inner.contains(token) else { return nil }
        return inner
    }
}
