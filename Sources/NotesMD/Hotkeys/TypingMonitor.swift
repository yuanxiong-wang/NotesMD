import AppKit
import Carbon

@MainActor
final class TypingMonitor {
    var onPalette: (() -> Void)?
    var onSlash: (() -> Void)?
    var onToolbar: (() -> Void)?
    var onQuickOpen: (() -> Void)?

    private let tap = KeyEventTap()
    func start() {
        stop()
        tap.onPalette = { [weak self] in self?.onPalette?() }
        tap.onSlash = { [weak self] in self?.onSlash?() }
        tap.onToolbar = { [weak self] in self?.onToolbar?() }
        tap.onQuickOpen = { [weak self] in self?.onQuickOpen?() }
        _ = tap.start()
    }

    func stop() {
        tap.stop()
    }

    func setPaletteCapturing(_ capturing: Bool) {
        tap.paletteCapturing = capturing
    }

    func setNotesFrontmost(_ frontmost: Bool) {
        tap.notesFrontmost = frontmost
    }

    var isTyping: Bool {
        ProcessInfo.processInfo.systemUptime - tap.lastEditUptime < 2.0
    }
}
