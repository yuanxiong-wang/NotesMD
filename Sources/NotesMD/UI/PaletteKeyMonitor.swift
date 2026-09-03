import AppKit
import Carbon
import SwiftUI

enum PaletteKey: Equatable {
    case up
    case down
    case submit
    case cancel

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else {
            return nil
        }
        switch Int(event.keyCode) {
        case Int(kVK_UpArrow), Int(kVK_PageUp):
            self = .up
        case Int(kVK_DownArrow), Int(kVK_PageDown):
            self = .down
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            self = .submit
        case Int(kVK_Escape):
            self = .cancel
        default:
            return nil
        }
    }

    init?(keyCode: CGKeyCode, flags: CGEventFlags) {
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) {
            return nil
        }
        switch Int(keyCode) {
        case Int(kVK_UpArrow), Int(kVK_PageUp):
            self = .up
        case Int(kVK_DownArrow), Int(kVK_PageDown):
            self = .down
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            self = .submit
        case Int(kVK_Escape):
            self = .cancel
        default:
            return nil
        }
    }
}

extension Notification.Name {
    static let notesMDPaletteKey = Notification.Name("notesMDPaletteKey")
}

enum PaletteKeyPost {
    static func send(_ key: PaletteKey) {
        NotificationCenter.default.post(name: .notesMDPaletteKey, object: key)
    }
}

struct PaletteKeyHandler: ViewModifier {
    var enabled: Bool
    var onKey: (PaletteKey) -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .notesMDPaletteKey)) { note in
            guard enabled, let key = note.object as? PaletteKey else { return }
            onKey(key)
        }
    }
}

extension View {
    func onPaletteKeys(enabled: Bool, _ onKey: @escaping (PaletteKey) -> Void) -> some View {
        modifier(PaletteKeyHandler(enabled: enabled, onKey: onKey))
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
