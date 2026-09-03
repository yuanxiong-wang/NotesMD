import NotesMDCore
import SwiftUI

struct SlashView: View {
    @ObservedObject var state: AppState
    @State private var selected = 0

    private var matches: [SlashCommand] {
        MarkdownTyping.slashCommands.filter { $0.matches(state.slashQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("/")
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                CommandSearchField(
                    text: $state.slashQuery,
                    placeholder: "title, quote, todo, template…",
                    fontSize: 15,
                    onMove: moveSelection,
                    onSubmit: runSelected,
                    onCancel: { state.slashVisible = false }
                )
            }
            .padding(10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                            HStack(spacing: 8) {
                                Image(systemName: command.symbol).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(command.title).font(.callout.weight(.medium))
                                    Text("/\(command.token)  \(command.subtitle)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(index == selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .id(command.id)
                            .onTapGesture { state.runSlash(command) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selected) { _, value in
                    if matches.indices.contains(value) {
                        proxy.scrollTo(matches[value].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 360, height: 320)
        .background(.ultraThickMaterial)
        .onAppear { selected = 0 }
        .onPaletteKeys(enabled: state.slashVisible) { key in
            switch key {
            case .up: moveSelection(-1)
            case .down: moveSelection(1)
            case .submit: runSelected()
            case .cancel: state.slashVisible = false
            }
        }
        .onChange(of: state.slashQuery) { _, _ in selected = 0 }
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

    private func runSelected() {
        guard matches.indices.contains(selected) else { return }
        state.runSlash(matches[selected])
    }
}
