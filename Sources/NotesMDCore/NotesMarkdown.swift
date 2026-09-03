import Foundation

public enum NotesMarkdown {
    public static func looksLikeMarkdown(_ text: String) -> Bool {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return false }

        let lines = sample.split(separator: "\n", omittingEmptySubsequences: false)
        var score = 0
        for line in lines.prefix(80) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") || t.hasPrefix("## ") || t.hasPrefix("### ") { score += 2 }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { score += 1 }
            if t.hasPrefix("> ") { score += 1 }
            if t.hasPrefix("```") { score += 2 }
            if t.hasPrefix("- [") { score += 2 }
            if t.range(of: #"^\d+\. "#, options: .regularExpression) != nil { score += 1 }
            if t.contains("**") || t.contains("~~") || t.contains("`") { score += 1 }
            if t.contains("](") { score += 1 }
            if t.hasPrefix("|") && t.hasSuffix("|") { score += 1 }
        }
        return score >= 2
    }

    public static func markdownToHTML(_ markdown: String) -> String {
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var html: [String] = []
        var i = 0
        var inCode = false
        var codeLines: [String] = []
        var listKind: ListKind?
        var listItems: [String] = []

        func flushList() {
            guard let kind = listKind else { return }
            html.append(kind.openTag)
            for item in listItems {
                html.append("<li>\(renderInline(item))</li>")
            }
            html.append(kind.closeTag)
            listKind = nil
            listItems.removeAll()
        }

        func flushCode() {
            let body = codeLines.map(escapeHTML).joined(separator: "\n")
            html.append("<div><pre>\(body)</pre></div>")
            codeLines.removeAll()
        }

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushList()
                    inCode = true
                }
                i += 1
                continue
            }

            if inCode {
                codeLines.append(line)
                i += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") && line.contains("|") {
                flushList()
                let (tableHTML, consumed) = parseTable(lines, start: i)
                html.append(tableHTML)
                i += consumed
                continue
            }

            if line.trimmingCharacters(in: .whitespaces) == "---"
                || line.trimmingCharacters(in: .whitespaces) == "***"
                || line.trimmingCharacters(in: .whitespaces) == "___" {
                flushList()
                html.append("<div><hr></div>")
                i += 1
                continue
            }

            if let heading = parseHeading(line) {
                flushList()
                html.append("<div><h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)></div>")
                i += 1
                continue
            }

            if let quote = stripPrefix(line, "> ") ?? stripPrefix(line, ">") {
                flushList()
                html.append("<blockquote>\(renderInline(quote.trimmingCharacters(in: .whitespaces)))</blockquote>")
                i += 1
                continue
            }

            if let item = parseListItem(line) {
                if listKind != item.kind {
                    flushList()
                    listKind = item.kind
                }
                listItems.append(item.text)
                i += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushList()
                html.append("<div><br></div>")
                i += 1
                continue
            }

            flushList()
            html.append("<div>\(renderInline(line))</div>")
            i += 1
        }

        if inCode { flushCode() }
        flushList()
        return html.joined()
    }

    public static func htmlToMarkdown(_ html: String) -> String {
        let tokens = HTMLTokenizer.tokenize(html)
        return HTMLMarkdownRenderer.render(tokens)
    }

    public static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    public static func unescapeHTML(_ text: String) -> String {
        var result = text
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]
        for (from, to) in named {
            result = result.replacingOccurrences(of: from, with: to)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: result),
                   let value = Int(result[range]),
                   let scalar = UnicodeScalar(value) {
                    let full = Range(match.range, in: result)!
                    result.replaceSubrange(full, with: String(Character(scalar)))
                }
            }
        }
        return result
    }

    private enum ListKind: Equatable {
        case ul
        case ol
        case task

        var openTag: String {
            switch self {
            case .ul, .task: return "<ul>"
            case .ol: return "<ol>"
            }
        }

        var closeTag: String {
            switch self {
            case .ul, .task: return "</ul>"
            case .ol: return "</ol>"
            }
        }
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...3).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseListItem(_ line: String) -> (kind: ListKind, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let rest = stripPrefix(trimmed, "- [ ] ") ?? stripPrefix(trimmed, "* [ ] ") {
            return (.task, "☐ " + rest)
        }
        if let rest = stripPrefix(trimmed, "- [x] ") ?? stripPrefix(trimmed, "- [X] ")
            ?? stripPrefix(trimmed, "* [x] ") ?? stripPrefix(trimmed, "* [X] ") {
            return (.task, "☑ " + rest)
        }
        if let rest = stripPrefix(trimmed, "- ") ?? stripPrefix(trimmed, "* ") ?? stripPrefix(trimmed, "+ ") {
            if rest.hasPrefix("*") { return nil }
            return (.ul, rest)
        }
        if let dot = trimmed.firstIndex(of: "."),
           trimmed[..<dot].allSatisfy({ $0.isNumber }),
           !trimmed[..<dot].isEmpty {
            let after = trimmed[trimmed.index(after: dot)...]
            if after.hasPrefix(" ") {
                return (.ol, String(after.dropFirst()))
            }
        }
        return nil
    }

    private static func stripPrefix(_ line: String, _ prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func parseTable(_ lines: [String], start: Int) -> (String, Int) {
        var rows: [[String]] = []
        var i = start
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") {
                if t.replacingOccurrences(of: "|", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) {
                    i += 1
                    continue
                }
                let cells = t.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty || true }
                let trimmedCells = Array(cells.drop(while: { $0.isEmpty }))
                    .reversed()
                    .drop(while: { $0.isEmpty })
                    .reversed()
                rows.append(Array(trimmedCells))
                i += 1
            } else {
                break
            }
        }
        guard !rows.isEmpty else { return ("", 1) }
        var html = "<table>"
        for (index, row) in rows.enumerated() {
            html += "<tr>"
            let tag = index == 0 ? "th" : "td"
            for cell in row {
                html += "<\(tag)>\(renderInline(cell))</\(tag)>"
            }
            html += "</tr>"
        }
        html += "</table>"
        return (html, i - start)
    }

    static func renderInline(_ text: String) -> String {
        var s = escapeHTML(text)
        s = replaceImages(s)
        s = replaceLinks(s)
        s = replaceCodeTicks(s)
        s = replaceWrapped(s, "**", "**", open: "<b>", close: "</b>")
        s = replaceWrapped(s, "__", "__", open: "<b>", close: "</b>")
        s = replaceWrapped(s, "~~", "~~", open: "<strike>", close: "</strike>")
        s = replaceWrapped(s, "==", "==", open: "<mark>", close: "</mark>")
        s = replaceEm(s, "*")
        s = replaceEm(s, "_")
        return s
    }

    private static func replaceCodeTicks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "`([^`]+)`") else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let inner = ns.substring(with: match.range(at: 1))
            result += "<code>\(inner)</code>"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func replaceLinks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?<!!)\\[([^\\]]+)\\]\\(([^\\)]+)\\)") else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let label = ns.substring(with: match.range(at: 1))
            let url = ns.substring(with: match.range(at: 2))
            result += "<a href=\"\(url)\">\(label)</a>"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func replaceImages(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)") else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let alt = ns.substring(with: match.range(at: 1))
            let url = ns.substring(with: match.range(at: 2))
            result += "<img src=\"\(url)\" alt=\"\(alt)\">"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func replaceWrapped(_ text: String, _ left: String, _ right: String, open: String, close: String) -> String {
        guard left != "`" else { return text }
        var result = text
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let start = result[searchStart...].range(of: left) {
            let afterStart = start.upperBound
            guard afterStart < result.endIndex,
                  let end = result[afterStart...].range(of: right),
                  start.upperBound != end.lowerBound else {
                searchStart = start.upperBound
                continue
            }
            let inner = result[start.upperBound..<end.lowerBound]
            let replacement = "\(open)\(inner)\(close)"
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: replacement)
            searchStart = result.index(start.lowerBound, offsetBy: replacement.count)
        }
        return result
    }

    private static func replaceEm(_ text: String, _ token: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\w)\\" + token + "([^\\s" + token + "][^" + token + "]*?)\\" + token + "(?!\\w)") else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let inner = ns.substring(with: match.range(at: 1))
            result += "<i>\(inner)</i>"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
