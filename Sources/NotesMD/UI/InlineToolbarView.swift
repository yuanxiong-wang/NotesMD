import NotesMDCore
import SwiftUI

struct InlineToolbarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            btn("textformat.size.larger", "Title") { state.applyParagraph(.title) }
            btn("textformat", "Heading") { state.applyParagraph(.heading) }
            btn("bold", "Bold") { state.applyInline(.bold) }
            btn("italic", "Italic") { state.applyInline(.italic) }
            btn("list.bullet", "List") { state.applyParagraph(.bulleted) }
            btn("checklist", "Checklist") { state.applyParagraph(.checklist) }
            btn("text.quote", "Quote") { state.applyParagraph(.blockQuote) }
            btn("chevron.left.forwardslash.chevron.right", "Code") { state.applyParagraph(.monostyled) }
            btn("link", "Link") { state.applyInline(.link) }
            Divider().frame(height: 16)
            btn("sparkles", "Expand Markdown") { state.expandMarkdown() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private func btn(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
