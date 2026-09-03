import AppKit
import Carbon
import NotesMDCore

@MainActor
final class TypingMonitor {
    var onStatus: ((String) -> Void)?
    var onPalette: (() -> Void)?
    var onSlash: (() -> Void)?
    var onToolbar: (() -> Void)?
    var onQuickOpen: (() -> Void)?
    var isBusy = false
    var suppressUntil: Date = .distantPast
    var capturingKeys: () -> Bool = { false }

    private var monitor: Any?
    private var pending: DispatchWorkItem?
    private let tap = KeyEventTap()

    func start() {
        stop()
        tap.shouldSwallow = { [weak self] key, flags, chars in
            self?.shouldSwallow(key: key, flags: flags, chars: chars) ?? false
        }
        _ = tap.start()

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func stop() {
        tap.stop()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pending?.cancel()
    }

    private func shouldSwallow(key: CGKeyCode, flags: CGEventFlags, chars: String) -> Bool {
        if capturingKeys(), let paletteKey = PaletteKey(keyCode: key, flags: flags) {
            DispatchQueue.main.async {
                PaletteKeyPost.send(paletteKey)
            }
            return true
        }

        let command = flags.contains(.maskCommand)
        let shift = flags.contains(.maskShift)
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)
        guard command, !option, !control, isNotesFrontmost() else { return false }

        if shift, key == CGKeyCode(kVK_Return) || key == CGKeyCode(kVK_ANSI_KeypadEnter) {
            DispatchQueue.main.async { [weak self] in self?.onPalette?() }
            return true
        }
        if shift, key == CGKeyCode(kVK_ANSI_P) {
            DispatchQueue.main.async { [weak self] in self?.onSlash?() }
            return true
        }
        if shift, key == CGKeyCode(kVK_ANSI_M) {
            DispatchQueue.main.async { [weak self] in self?.onToolbar?() }
            return true
        }
        if !shift, key == CGKeyCode(kVK_ANSI_O) {
            DispatchQueue.main.async { [weak self] in self?.onQuickOpen?() }
            return true
        }
        return false
    }

    func handle(_ event: NSEvent) {
        guard Date() > suppressUntil, !isBusy else { return }
        guard !capturingKeys() else { return }
        guard isNotesFrontmost() else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return }

        if event.keyCode == UInt16(kVK_Space) {
            schedule(after: 0.05) { self.expandAfterSpace() }
        }
    }

    /// Only runs if Accessibility already exposes the line prefix. Never guesses with Cmd-Shift-Left.
    private func expandAfterSpace() {
        guard let raw = AXBridge.linePrefixToCaret() else { return }
        let line = raw.hasSuffix(" ") ? raw : raw + " "
        guard let trigger = MarkdownTyping.triggerAfterSpace(line: line) else { return }
        runBusy {
            FormatActions.selectToLineStart()
            usleep(30_000)
            FormatActions.deleteSelection()
            usleep(30_000)
            FormatActions.applyParagraph(trigger.style, activate: false)
            self.onStatus?("\(trigger.style.englishMenuName) · \(trigger.style.chineseMenuName)")
        }
    }

    private func runBusy(_ work: () -> Void) {
        isBusy = true
        suppressUntil = Date().addingTimeInterval(0.5)
        work()
        isBusy = false
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pending = nil
            work()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func isNotesFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == NotesBridge.bundleID
    }
}
