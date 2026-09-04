import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

final class KeyEventTap {
    var onPalette: (() -> Void)?
    var onSlash: (() -> Void)?
    var onToolbar: (() -> Void)?
    var onQuickOpen: (() -> Void)?

    /// Written from the main thread, read from the tap callback. Do not hop to main to inspect these.
    var paletteCapturing = false
    var notesFrontmost = false
    var lastEventUptime: TimeInterval = 0

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<KeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = tap.port {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }
                tap.lastEventUptime = ProcessInfo.processInfo.systemUptime

                let flags = event.flags
                let command = flags.contains(.maskCommand)
                if !command && !tap.paletteCapturing {
                    return Unmanaged.passUnretained(event)
                }

                let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                if tap.paletteCapturing, let paletteKey = PaletteKey(keyCode: key, flags: flags) {
                    DispatchQueue.main.async {
                        PaletteKeyPost.send(paletteKey)
                    }
                    return nil
                }

                guard command,
                      !flags.contains(.maskAlternate),
                      !flags.contains(.maskControl),
                      tap.notesFrontmost else {
                    return Unmanaged.passUnretained(event)
                }

                let shift = flags.contains(.maskShift)
                if shift, key == CGKeyCode(kVK_Return) || key == CGKeyCode(kVK_ANSI_KeypadEnter) {
                    DispatchQueue.main.async { tap.onPalette?() }
                    return nil
                }
                if shift, key == CGKeyCode(kVK_ANSI_P) {
                    DispatchQueue.main.async { tap.onSlash?() }
                    return nil
                }
                if shift, key == CGKeyCode(kVK_ANSI_M) {
                    DispatchQueue.main.async { tap.onToolbar?() }
                    return nil
                }
                if !shift, key == CGKeyCode(kVK_ANSI_O) {
                    DispatchQueue.main.async { tap.onQuickOpen?() }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: info
        ) else {
            return false
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        source = nil
        self.port = nil
    }
}
