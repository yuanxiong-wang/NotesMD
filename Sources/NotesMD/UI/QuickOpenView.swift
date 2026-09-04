import SwiftUI

struct QuickOpenView: View {
    @ObservedObject var state: AppState
    @State private var query = ""
    @State private var selected = 0

    private var matches: [NoteHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = state.noteIndex
        if q.isEmpty { return Array(source.prefix(40)) }
        return source.filter {
            $0.name.lowercased().contains(q) || $0.folder.lowercased().contains(q)
        }.prefix(50).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                CommandSearchField(
                    text: $query,
                    placeholder: "Search notes and folders…  搜索笔记",
                    onMove: moveSelection,
                    onSubmit: openSelected,
                    onCancel: { state.hideQuickOpen() }
                )
                if state.isIndexing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, hit in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.name).font(.body.weight(.medium)).lineLimit(1)
                                    if !hit.folder.isEmpty {
                                        Text(hit.folder).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(index == selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .id(hit.id)
                            .onTapGesture { state.openNote(hit) }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selected) { _, value in
                    if matches.indices.contains(value) {
                        proxy.scrollTo(matches[value].id, anchor: .center)
                    }
                }
            }
            if matches.isEmpty && !state.isIndexing {
                Text(state.noteIndex.isEmpty ? "No notes indexed yet" : "No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 480, height: 420)
        .background(.ultraThickMaterial)
        .onAppear {
            selected = 0
            state.refreshNoteIndexIfNeeded()
        }
        .onPaletteKeys(enabled: state.quickOpenVisible) { key in
            switch key {
            case .up: moveSelection(-1)
            case .down: moveSelection(1)
            case .submit: openSelected()
            case .cancel: state.hideQuickOpen()
            }
        }
        .onChange(of: query) { _, _ in selected = 0 }
        .onChange(of: matches.count) { _, _ in
            if selected >= matches.count {
                selected = max(0, matches.count - 1)
            }
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !matches.isEmpty else { return }
        selected = (selected + delta + matches.count) % matches.count
    }

    private func openSelected() {
        guard matches.indices.contains(selected) else { return }
        state.openNote(matches[selected])
    }
}
