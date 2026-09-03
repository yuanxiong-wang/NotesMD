import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("NotesMD")
                        .font(.largeTitle.bold())
                    Text("A Markdown companion for Apple Notes")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Slash commands, caret following, and Markdown shortcuts need Accessibility. Without it, `/` and `##` are typed into Notes instead.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    ok: state.accessibilityTrusted,
                    title: "Accessibility  辅助功能",
                    detail: state.accessibilityTrusted
                        ? "Granted. Slash commands and the follow bar can run."
                        : "System Settings → Privacy & Security → Accessibility → turn on NotesMD."
                )
                permissionRow(
                    ok: state.notesRunning,
                    title: "Notes is open  备忘录已打开",
                    detail: "The first time NotesMD talks to Notes, macOS will ask for Automation. Allow Notes."
                )
            }

            if !state.accessibilityTrusted {
                Text("If NotesMD is already in the list but still off, remove it, click the button below, then enable the new row. Rebuilding the app creates a new identity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(state.accessibilityTrusted ? "Accessibility On" : "Grant Accessibility…") {
                    state.requestAccessibility()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.accessibilityTrusted)

                Button("Open Notes") {
                    NotesBridge.launch()
                }
                Spacer()
                Button(state.accessibilityTrusted ? "Done" : "Continue anyway") {
                    state.refreshPermissions()
                    state.onboardingVisible = false
                }
            }
        }
        .padding(28)
        .frame(width: 580)
        .onAppear {
            state.refreshPermissions()
            if !state.accessibilityTrusted {
                state.requestAccessibility()
            }
        }
        .onChange(of: state.accessibilityTrusted) { _, trusted in
            if trusted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    state.onboardingVisible = false
                }
            }
        }
    }

    private func permissionRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
