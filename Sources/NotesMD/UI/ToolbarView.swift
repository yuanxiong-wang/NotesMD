import NotesMDCore
import SwiftUI

struct ToolbarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "note.text")
                .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.18))
                .frame(height: 28)
                .padding(.bottom, 4)
            Divider().opacity(0.35)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(buttonSpecs, id: \.id) { spec in
                        iconButton(spec)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 64)
        .background(Color.clear)
    }

    private var buttonSpecs: [ToolbarButton] {
        [
            makeButton(id: "preview", symbol: "eye", title: "Markdown 預覽", action: {
                state.togglePreview()
            }),
            makeButton(id: "title", symbol: "textformat.size.larger", title: "標題", action: { state.run(cmd("title")) }),
            makeButton(id: "h2", symbol: "textformat", title: "小標題", action: { state.run(cmd("h2")) }),
            makeButton(id: "h3", symbol: "textformat.subscript", title: "副標題", action: { state.run(cmd("h3")) }),
            makeButton(id: "bold", symbol: "bold", title: "粗體", action: { state.run(cmd("bold")) }),
            makeButton(id: "italic", symbol: "italic", title: "斜體", action: { state.run(cmd("italic")) }),
            makeButton(id: "mono", symbol: "chevron.left.forwardslash.chevron.right", title: "等寬", action: { state.run(cmd("mono")) }),
            makeButton(id: "quote", symbol: "text.quote", title: "引用", action: { state.run(cmd("quote")) }),
            makeButton(id: "ul", symbol: "list.bullet", title: "項目符號", action: { state.run(cmd("ul")) }),
            makeButton(id: "ol", symbol: "list.number", title: "編號列表", action: { state.run(cmd("ol")) }),
            makeButton(id: "check", symbol: "checklist", title: "核對清單", action: { state.run(cmd("check")) }),
            makeButton(id: "link", symbol: "link", title: "連結", action: { state.run(cmd("link")) }),
            makeButton(id: "slash", symbol: "slash.circle", title: "斜杠命令", action: { state.toggleSlash() }),
            makeButton(id: "expand", symbol: "sparkles", title: "展開 Markdown", action: { state.expandMarkdown() }),
            makeButton(id: "convert", symbol: "arrow.triangle.2.circlepath", title: "轉換選取範圍", action: { state.convertSelection() }),
            makeButton(id: "copy", symbol: "doc.on.clipboard", title: "複製為 Markdown", action: { state.copyMarkdown() }),
            makeButton(id: "open", symbol: "magnifyingglass", title: "快速開啟", action: { state.toggleQuickOpen() }),
            makeButton(id: "toc", symbol: "list.bullet.indent", title: "目錄", action: {
                state.toggleTOC()
            }),
            makeButton(id: "palette", symbol: "command", title: "命令面板", action: { state.togglePalette() })
        ]
    }

    private func iconButton(_ item: ToolbarButton) -> some View {
        Button(action: item.action) {
            Image(systemName: item.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(item.title)
        .help(item.title)
    }

    private func makeButton(
        id: String,
        symbol: String,
        title: String,
        action: @escaping () -> Void
    ) -> ToolbarButton {
        ToolbarButton(id: id, symbol: symbol, title: title, action: action)
    }

    private func cmd(_ id: String) -> PaletteCommand {
        PaletteCatalog.all.first { $0.id == id }!
    }
}

struct ToolbarButton: Identifiable {
    var id: String
    var symbol: String
    var title: String
    var action: () -> Void = {}
}

struct MarkdownPreviewView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Markdown")
                    .font(.headline)
                Spacer()
                Button {
                    state.refreshPreview()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                Button {
                    state.hidePreview()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            Divider()
            ScrollView {
                Text(state.markdownPreview.isEmpty ? "開啟一篇筆記以預覽 Markdown。" : state.markdownPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .frame(width: 280, height: 420)
        .background(Color.clear)
        .onAppear { state.refreshPreview() }
    }
}
