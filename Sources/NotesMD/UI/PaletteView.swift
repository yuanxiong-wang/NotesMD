import SwiftUI

struct PaletteView: View {
    @ObservedObject var state: AppState
    @State private var query = ""
    @State private var selected = 0

    private var matches: [PaletteCommand] {
        PaletteCatalog.all.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                CommandSearchField(
                    text: $query,
                    placeholder: "Run a command…  输入命令",
                    onMove: moveSelection,
                    onSubmit: runSelected,
                    onCancel: { state.hidePalette() }
                )
                Text("esc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                            row(command, selected: index == selected)
                                .id(command.id)
                                .onTapGesture { state.run(command) }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selected) { _, newValue in
                    if matches.indices.contains(newValue) {
                        proxy.scrollTo(matches[newValue].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 520, height: 420)
        .background(.ultraThickMaterial)
        .onAppear { selected = 0 }
        .onPaletteKeys(enabled: state.paletteVisible) { key in
            switch key {
            case .up: moveSelection(-1)
            case .down: moveSelection(1)
            case .submit: runSelected()
            case .cancel: state.hidePalette()
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

    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .frame(width: 22)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body.weight(.medium))
                Text(command.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !command.shortcut.isEmpty {
                Text(command.shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func runSelected() {
        guard matches.indices.contains(selected) else { return }
        state.run(matches[selected])
    }
}
