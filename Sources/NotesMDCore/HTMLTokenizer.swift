import Foundation

enum HTMLToken: Equatable {
    case open(name: String, attrs: [String: String])
    case close(name: String)
    case text(String)
}

enum HTMLTokenizer {
    static func tokenize(_ html: String) -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        var i = html.startIndex
        var textBuffer = ""

        func flushText() {
            if !textBuffer.isEmpty {
                tokens.append(.text(NotesMarkdown.unescapeHTML(textBuffer)))
                textBuffer.removeAll(keepingCapacity: true)
            }
        }

        while i < html.endIndex {
            if html[i] == "<" {
                if let end = html[i...].firstIndex(of: ">") {
                    let raw = String(html[html.index(after: i)..<end])
                    flushText()
                    if raw.hasPrefix("!--") {
                        i = html.index(after: end)
                        continue
                    }
                    if raw.hasPrefix("!"), raw.uppercased().hasPrefix("!DOCTYPE") {
                        i = html.index(after: end)
                        continue
                    }
                    if raw.hasPrefix("/") {
                        tokens.append(.close(name: tagName(String(raw.dropFirst())).lowercased()))
                    } else {
                        let selfClosing = raw.hasSuffix("/")
                        let body = selfClosing ? String(raw.dropLast()) : raw
                        let (name, attrs) = parseOpenTag(body)
                        tokens.append(.open(name: name.lowercased(), attrs: attrs))
                        if selfClosing || isVoid(name) {
                            tokens.append(.close(name: name.lowercased()))
                        }
                    }
                    i = html.index(after: end)
                    continue
                }
            }
            textBuffer.append(html[i])
            i = html.index(after: i)
        }
        flushText()
        return tokens
    }

    private static func isVoid(_ name: String) -> Bool {
        ["br", "hr", "img", "meta", "input", "link"].contains(name.lowercased())
    }

    private static func tagName(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? raw
    }

    private static func parseOpenTag(_ raw: String) -> (String, [String: String]) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) else {
            return (trimmed, [:])
        }
        let name = String(trimmed[..<firstSpace])
        let rest = String(trimmed[firstSpace...])
        var attrs: [String: String] = [:]
        var remaining = rest.trimmingCharacters(in: .whitespaces)
        while !remaining.isEmpty {
            guard let eq = remaining.firstIndex(of: "=") else { break }
            let key = remaining[..<eq].trimmingCharacters(in: .whitespaces)
            var valuePart = remaining[remaining.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value: String
            if valuePart.hasPrefix("\"") || valuePart.hasPrefix("'") {
                let quote = valuePart.first!
                valuePart.removeFirst()
                if let close = valuePart.firstIndex(of: quote) {
                    value = String(valuePart[..<close])
                    remaining = String(valuePart[valuePart.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    value = String(valuePart)
                    remaining = ""
                }
            } else if let space = valuePart.firstIndex(where: { $0.isWhitespace }) {
                value = String(valuePart[..<space])
                remaining = String(valuePart[space...]).trimmingCharacters(in: .whitespaces)
            } else {
                value = String(valuePart)
                remaining = ""
            }
            if !key.isEmpty {
                attrs[key.lowercased()] = NotesMarkdown.unescapeHTML(value)
            }
        }
        return (name, attrs)
    }
}

enum HTMLMarkdownRenderer {
    static func render(_ tokens: [HTMLToken]) -> String {
        var out = ""
        var index = 0
        var listStack: [String] = []
        var listItemOpen = false
        var skipDepth = 0

        func skipUntilClose(_ name: String) {
            var depth = 1
            while index < tokens.count && depth > 0 {
                switch tokens[index] {
                case .open(let n, _) where n == name: depth += 1
                case .close(let n) where n == name: depth -= 1
                default: break
                }
                index += 1
            }
        }

        while index < tokens.count {
            let token = tokens[index]
            index += 1
            if skipDepth > 0 {
                if case .close = token { skipDepth -= 1 }
                continue
            }

            switch token {
            case .open(let name, let attrs):
                switch name {
                case "script", "style", "head":
                    skipUntilClose(name)
                case "h1":
                    out += headingPrefix(1)
                case "h2":
                    out += headingPrefix(2)
                case "h3":
                    out += headingPrefix(3)
                case "h4":
                    out += headingPrefix(4)
                case "p", "div":
                    if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                case "br":
                    out += "\n"
                case "hr":
                    out += "\n---\n"
                case "ul":
                    listStack.append("ul")
                    if !out.hasSuffix("\n") { out += "\n" }
                case "ol":
                    listStack.append("ol")
                    if !out.hasSuffix("\n") { out += "\n" }
                case "li":
                    listItemOpen = true
                    if listStack.last == "ol" {
                        out += "1. "
                    } else {
                        out += "- "
                    }
                case "blockquote":
                    if !out.hasSuffix("\n") { out += "\n" }
                    out += "> "
                case "pre", "code":
                    if name == "pre" {
                        out += "\n```\n"
                    } else if !inPre(tokens, index: index - 1) {
                        out += "`"
                    }
                case "b", "strong":
                    out += "**"
                case "i", "em":
                    out += "*"
                case "u":
                    break
                case "strike", "s", "del":
                    out += "~~"
                case "mark":
                    out += "=="
                case "a":
                    out += "["
                    _ = attrs
                case "img":
                    let alt = attrs["alt"] ?? ""
                    let src = attrs["src"] ?? ""
                    out += "![\(alt)](\(src))"
                case "table":
                    if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                    let (md, next) = markdownTable(from: tokens, insideStart: index)
                    out += md
                    if !out.hasSuffix("\n") { out += "\n" }
                    index = next
                case "tr", "th", "td", "thead", "tbody", "tfoot", "caption", "colgroup", "col":
                    break
                case "html", "body", "span", "font", "object":
                    break
                default:
                    break
                }
            case .close(let name):
                switch name {
                case "h1", "h2", "h3", "h4", "p":
                    out += "\n"
                case "div":
                    if !out.hasSuffix("\n") { out += "\n" }
                case "ul", "ol":
                    if !listStack.isEmpty { listStack.removeLast() }
                    if !out.hasSuffix("\n") { out += "\n" }
                case "li":
                    listItemOpen = false
                    if !out.hasSuffix("\n") { out += "\n" }
                case "blockquote":
                    out += "\n"
                case "pre":
                    if !out.hasSuffix("\n") { out += "\n" }
                    out += "```\n"
                case "code":
                    if !out.hasSuffix("```\n") {
                        out += "`"
                    }
                case "b", "strong":
                    out += "**"
                case "i", "em":
                    out += "*"
                case "strike", "s", "del":
                    out += "~~"
                case "mark":
                    out += "=="
                case "a":
                    out += "]"
                    if let href = hrefBeforeClose(tokens, closeIndex: index - 1) {
                        out += "(\(href))"
                    }
                default:
                    break
                }
            case .text(let text):
                let cleaned = text.replacingOccurrences(of: "\u{00a0}", with: " ")
                if listItemOpen || !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out += cleaned
                }
            }
        }

        return tidy(out)
    }

    /// Consume a Notes/HTML table as a GFM table, flattening cell internals to one line.
    private static func markdownTable(from tokens: [HTMLToken], insideStart: Int) -> (String, Int) {
        var i = insideStart
        var depth = 1
        var rows: [[String]] = []
        var currentRow: [String]?
        var caption = ""

        while i < tokens.count && depth > 0 {
            switch tokens[i] {
            case .open(let name, _) where name == "table":
                depth += 1
                i += 1
            case .close(let name) where name == "table":
                depth -= 1
                i += 1
            case .open(let name, _) where name == "tr" && depth == 1:
                currentRow = []
                i += 1
            case .close(let name) where name == "tr" && depth == 1:
                if let row = currentRow { rows.append(row) }
                currentRow = nil
                i += 1
            case .open(let name, _) where (name == "td" || name == "th") && depth == 1:
                let (inner, next) = sliceUntilClose(tokens, openAt: i)
                if currentRow == nil { currentRow = [] }
                currentRow?.append(cellMarkdown(inner))
                i = next
            case .open(let name, _) where name == "caption" && depth == 1:
                let (inner, next) = sliceUntilClose(tokens, openAt: i)
                caption = cellMarkdown(inner)
                i = next
            default:
                i += 1
            }
        }

        var lines: [String] = []
        if !caption.isEmpty {
            lines.append(caption)
        }
        lines.append(contentsOf: gfmLines(from: rows))
        return (lines.joined(separator: "\n"), i)
    }

    private static func sliceUntilClose(_ tokens: [HTMLToken], openAt: Int) -> ([HTMLToken], Int) {
        guard case .open(let openName, _) = tokens[openAt] else {
            return ([], openAt + 1)
        }
        var i = openAt + 1
        var depth = 1
        var inner: [HTMLToken] = []
        while i < tokens.count && depth > 0 {
            switch tokens[i] {
            case .open(let name, _) where name == openName:
                depth += 1
                inner.append(tokens[i])
            case .close(let name) where name == openName:
                depth -= 1
                if depth > 0 { inner.append(tokens[i]) }
            default:
                inner.append(tokens[i])
            }
            i += 1
        }
        return (inner, i)
    }

    private static func cellMarkdown(_ tokens: [HTMLToken]) -> String {
        var out = ""
        for (offset, token) in tokens.enumerated() {
            switch token {
            case .text(let text):
                out += text
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
            case .open(let name, let attrs):
                switch name {
                case "br":
                    out += " "
                case "b", "strong":
                    out += "**"
                case "i", "em":
                    out += "*"
                case "code":
                    out += "`"
                case "strike", "s", "del":
                    out += "~~"
                case "mark":
                    out += "=="
                case "a":
                    out += "["
                case "img":
                    let alt = attrs["alt"] ?? ""
                    let src = attrs["src"] ?? ""
                    out += "![\(alt)](\(src))"
                default:
                    out += " "
                }
            case .close(let name):
                switch name {
                case "b", "strong":
                    out += "**"
                case "i", "em":
                    out += "*"
                case "code":
                    out += "`"
                case "strike", "s", "del":
                    out += "~~"
                case "mark":
                    out += "=="
                case "a":
                    out += "]"
                    if let href = hrefBeforeClose(tokens, closeIndex: offset) {
                        out += "(\(href))"
                    }
                default:
                    break
                }
            }
        }
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func gfmLines(from rows: [[String]]) -> [String] {
        guard !rows.isEmpty else { return [] }
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return [] }
        func padded(_ row: [String]) -> [String] {
            row + Array(repeating: "", count: max(0, width - row.count))
        }
        var lines: [String] = []
        for (index, row) in rows.enumerated() {
            let cells = padded(row)
            lines.append("| " + cells.joined(separator: " | ") + " |")
            if index == 0 {
                lines.append("| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |")
            }
        }
        return lines
    }

    private static func headingPrefix(_ level: Int) -> String {
        let marks = String(repeating: "#", count: level)
        return (marks + " ")
    }

    private static func inPre(_ tokens: [HTMLToken], index: Int) -> Bool {
        var depth = 0
        for token in tokens.prefix(index) {
            if case .open(let n, _) = token, n == "pre" { depth += 1 }
            if case .close(let n) = token, n == "pre" { depth -= 1 }
        }
        return depth > 0
    }

    private static func hrefBeforeClose(_ tokens: [HTMLToken], closeIndex: Int) -> String? {
        var depth = 0
        var i = closeIndex
        while i >= 0 {
            switch tokens[i] {
            case .close(let n) where n == "a":
                depth += 1
            case .open(let n, let attrs) where n == "a":
                depth -= 1
                if depth == 0 { return attrs["href"] }
            default:
                break
            }
            i -= 1
        }
        return nil
    }

    private static func tidy(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }

        var result: [String] = []
        var blank = 0
        for line in lines {
            if line.isEmpty {
                blank += 1
                if blank <= 2 { result.append("") }
            } else {
                blank = 0
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }
}
