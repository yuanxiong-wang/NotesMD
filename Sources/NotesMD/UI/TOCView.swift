import NotesMDCore
import SwiftUI

struct TOCView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Contents")
                    .font(.headline)
                Spacer()
                Button {
                    state.refreshTOC()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
                Button {
                    state.hideTOC()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(10)
            Divider()
            if state.tocItems.isEmpty {
                Text("No headings in this note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(state.tocItems) { heading in
                            Button {
                                state.jumpToHeading(heading)
                            } label: {
                                Text(heading.text)
                                    .font(heading.level == 1 ? .body.weight(.semibold) : .callout)
                                    .padding(.leading, CGFloat(heading.level - 1) * 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: 260, height: 320)
        .background(Color.clear)
        .onAppear { state.refreshTOC() }
        .onExitCommand { state.hideTOC() }
    }
}

struct TemplatePickerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Templates")
                    .font(.headline)
                Spacer()
                Button {
                    state.hideTemplates()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(10)
            Divider()
            if state.isIndexing {
                ProgressView("Loading templates…")
                    .padding(12)
            } else if let error = state.noteIndexError, state.templates.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else if state.templates.isEmpty {
                Text("Create a folder named Templates or 模板 in Notes, then put one note per template inside it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                List(state.templates) { hit in
                    Button(hit.name) {
                        state.insertTemplate(hit)
                    }
                }
            }
        }
        .frame(width: 320, height: 280)
        .background(.ultraThickMaterial)
        .onAppear { state.refreshNoteIndexIfNeeded() }
        .onExitCommand { state.hideTemplates() }
    }
}
