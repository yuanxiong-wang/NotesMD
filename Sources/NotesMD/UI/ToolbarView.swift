import NotesMDCore
import SwiftUI

struct ToolbarView: View {
    @ObservedObject var state: AppState
    var compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            buttonGrid
            if state.previewVisible && !compact {
                Divider().opacity(0.35)
                preview
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: compact ? 64 : 280)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.18))
                if !compact {
                    Text("NotesMD")
                        .font(.headline)
                    Spacer()
                }
                Button {
                    state.previewVisible.toggle()
                    if state.previewVisible { state.refreshPreview() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.plain)
                .help("Markdown preview")
            }
            if !compact {
                Text(state.currentNote?.name ?? "No note selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.bottom, 6)
    }

    private var buttonGrid: some View {
        let columns = [GridItem(.adaptive(minimum: compact ? 40 : 36), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            iconButton("textformat.size.larger", "Title") { state.run(cmd("title")) }
            iconButton("textformat", "Heading") { state.run(cmd("h2")) }
            iconButton("textformat.subscript", "Subheading") { state.run(cmd("h3")) }
            iconButton("bold", "Bold") { state.run(cmd("bold")) }
            iconButton("italic", "Italic") { state.run(cmd("italic")) }
            iconButton("chevron.left.forwardslash.chevron.right", "Monostyled") { state.run(cmd("mono")) }
            iconButton("text.quote", "Quote") { state.run(cmd("quote")) }
            iconButton("list.bullet", "Bullets") { state.run(cmd("ul")) }
            iconButton("list.number", "Numbers") { state.run(cmd("ol")) }
            iconButton("checklist", "Checklist") { state.run(cmd("check")) }
            iconButton("link", "Link") { state.run(cmd("link")) }
            iconButton("slash.circle", "Slash commands  ⌘⇧P") {
                state.toggleSlash()
            }
            iconButton("sparkles", "Expand Markdown") { state.expandMarkdown() }
            iconButton("arrow.triangle.2.circlepath", "Convert selection") { state.convertSelection() }
            iconButton("doc.on.clipboard", "Copy as Markdown") { state.copyMarkdown() }
            iconButton("magnifyingglass", "Quick Open  ⌘O") { state.toggleQuickOpen() }
            iconButton("list.bullet.indent", "Table of contents") {
                state.tocVisible.toggle()
                if state.tocVisible { state.refreshTOC() }
            }
            iconButton("command", "Command palette  ⌘⇧↩") { state.togglePalette() }
        }
        .padding(.vertical, 8)
    }

    private var preview: some View {
        ScrollView {
            Text(state.markdownPreview.isEmpty ? "Open a note to preview Markdown." : state.markdownPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 180, maxHeight: 320)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 4) {
            if !state.selectedText.isEmpty && !compact {
                Text(state.selectedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(state.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.top, 6)
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 14 : 13, weight: .semibold))
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func cmd(_ id: String) -> PaletteCommand {
        PaletteCatalog.all.first { $0.id == id }!
    }
}
