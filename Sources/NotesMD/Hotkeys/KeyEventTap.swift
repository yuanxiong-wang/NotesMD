import ApplicationServices
import CoreGraphics
import Foundation

final class KeyEventTap {
    var shouldSwallow: ((CGKeyCode, CGEventFlags, String) -> Bool)?

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
                let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 8)
                event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
                let chars = length > 0 ? String(utf16CodeUnits: buffer, count: length) : ""

                var swallow = false
                let evaluate = {
                    swallow = tap.shouldSwallow?(key, flags, chars) ?? false
                }
                if Thread.isMainThread {
                    evaluate()
                } else {
                    DispatchQueue.main.sync(execute: evaluate)
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
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
