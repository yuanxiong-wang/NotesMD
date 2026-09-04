import Foundation
import NotesMDCore

@main
enum NotesMDCheck {
    static func main() {
        var failed = 0

        func expect(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok {
                print("ok   \(name)")
            } else {
                failed += 1
                print("FAIL \(name) \(detail)")
            }
        }

        let headings = NotesMarkdown.markdownToHTML("# Title\n## Heading\n### Sub")
        expect("headings html", headings.contains("<h1>Title</h1>") && headings.contains("<h2>Heading</h2>"))

        let inline = NotesMarkdown.markdownToHTML("Hello **world** and *it*")
        expect("inline html", inline.contains("<b>world</b>") && inline.contains("<i>it</i>"), inline)

        let list = NotesMarkdown.markdownToHTML("- one\n- two\n\nSee [Notes](https://example.com)")
        expect("list/link html", list.contains("<ul>") && list.contains("<li>one</li>") && list.contains("<a href=\"https://example.com\">Notes</a>"), list)

        let md = NotesMarkdown.htmlToMarkdown("<div><h1>Title</h1></div><div>Hello <b>world</b> and <i>it</i></div>")
        expect("html to md", md.contains("# Title") && md.contains("**world**") && md.contains("*it*"), md)

        expect("looks like md", NotesMarkdown.looksLikeMarkdown("## Hello\n- item"))
        expect("not md", !NotesMarkdown.looksLikeMarkdown("just a sentence"))

        expect("plan heading", MarkdownPlanner.plan(for: "## Hello") == .applyParagraph(.heading, replacement: "Hello"))
        expect("plan bold", MarkdownPlanner.plan(for: "**Hello**") == .applyInline(.bold, replacement: "Hello"))

        if case .pasteHTML(let html) = MarkdownPlanner.plan(for: "# Title\n\n**bold**\n") {
            expect("plan document", html.contains("<h1>Title</h1>") && html.contains("<b>bold</b>"))
        } else {
            expect("plan document", false)
        }

        let escaped = NotesMarkdown.markdownToHTML("use <script>alert(1)</script>")
        expect("escape html", !escaped.contains("<script>") && escaped.contains("&lt;script&gt;"), escaped)

        expect("type title", MarkdownTyping.triggerAfterSpace(line: "# ")?.style == .title)
        expect("type heading", MarkdownTyping.triggerAfterSpace(line: "## ")?.style == .heading)
        expect("type quote", MarkdownTyping.triggerAfterSpace(line: "> ")?.style == .blockQuote)
        expect("type check", MarkdownTyping.triggerAfterSpace(line: "[] ")?.style == .checklist)
        expect("type cjk check", MarkdownTyping.triggerAfterSpace(line: "【】 ")?.style == .checklist)
        expect("type code dots", MarkdownTyping.triggerAfterSpace(line: "··· ")?.style == .monostyled)
        expect("type ordered", MarkdownTyping.triggerAfterSpace(line: "1. ")?.style == .numbered)
        expect("type skip sentence", MarkdownTyping.triggerAfterSpace(line: "hello ") == nil)
        expect("cjk link", MarkdownTyping.isCJKNoteLink("见》》"))
        expect("slash line", MarkdownTyping.isSlashLine("/title"))
        expect("not slash", !MarkdownTyping.isSlashLine("see /title"))

        let outline = MarkdownTyping.headings(inHTML: "<div><h1>A</h1></div><div><h2>B</h2></div>")
        expect("toc", outline.map(\.text) == ["A", "B"] && outline.map(\.level) == [1, 2], "\(outline)")

        let tableMD = """
        | Name | Qty |
        | --- | --- |
        | Apples | 3 |
        | Pears | 2 |
        """
        let tableHTML = NotesMarkdown.markdownToHTML(tableMD)
        expect("md table html", tableHTML.contains("<table>") && tableHTML.contains("<th>Name</th>") && tableHTML.contains("<td>Apples</td>"), tableHTML)
        let tableBack = NotesMarkdown.htmlToMarkdown(tableHTML)
        expect("table round-trip header", tableBack.contains("| Name | Qty |"), tableBack)
        expect("table round-trip sep", tableBack.contains("| --- | --- |"), tableBack)
        expect("table round-trip rows", tableBack.contains("| Apples | 3 |") && tableBack.contains("| Pears | 2 |"), tableBack)

        let notesTable = """
        <div><table>
        <tr><td><div>Name</div></td><td><div>Qty</div></td></tr>
        <tr><td><div>Apples</div></td><td><div><b>3</b></div></td></tr>
        </table></div>
        """
        let fromNotes = NotesMarkdown.htmlToMarkdown(notesTable)
        expect("notes table header", fromNotes.contains("| Name | Qty |"), fromNotes)
        expect("notes table sep", fromNotes.contains("| --- | --- |"), fromNotes)
        expect("notes table cell", fromNotes.contains("| Apples | **3** |"), fromNotes)
        let notesRound = NotesMarkdown.htmlToMarkdown(NotesMarkdown.markdownToHTML(fromNotes))
        expect("notes table round-trip", notesRound.contains("| Name | Qty |") && notesRound.contains("| Apples | **3** |"), notesRound)

        if failed == 0 {
            print("All checks passed.")
        } else {
            print("\(failed) checks failed.")
            exit(1)
        }
    }
}
