import AppKit
import Carbon

@MainActor
final class HotkeyMonitor {
    var onPalette: (() -> Void)?
    var onSlash: (() -> Void)?
    var onToolbar: (() -> Void)?
    var onQuickOpen: (() -> Void)?
    var capturingKeys: () -> Bool = { false }

    private var local: Any?
    private var global: Any?

    func start() {
        stop()
        local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handle(event) == true { return nil }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    func stop() {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ours = Bundle.main.bundleIdentifier
        let notesFront = front == NotesBridge.bundleID || front == ours
        guard notesFront else { return false }

        let command = flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
        let commandShift = command && flags.contains(.shift)
        let commandOnly = command && !flags.contains(.shift)

        if commandOnly, event.keyCode == UInt16(kVK_ANSI_O) {
            onQuickOpen?()
            return true
        }
        guard commandShift else { return false }

        switch event.keyCode {
        case UInt16(kVK_ANSI_P):
            onSlash?()
            return true
        case UInt16(kVK_ANSI_M):
            onToolbar?()
            return true
        case UInt16(kVK_ANSI_O):
            onQuickOpen?()
            return true
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            if capturingKeys() { return false }
            onPalette?()
            return true
        default:
            return false
        }
    }
}
