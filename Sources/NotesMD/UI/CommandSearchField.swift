import AppKit
import SwiftUI

struct CommandSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 16
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onMove: onMove, onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .regular)
        field.delegate = context.coordinator
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        context.coordinator.field = field
        context.coordinator.startMonitor()
        DispatchQueue.main.async {
            field.window?.makeKeyAndOrderFront(nil)
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onMove = onMove
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        context.coordinator.field = field
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.stopMonitor()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onMove: (Int) -> Void
        var onSubmit: () -> Void
        var onCancel: () -> Void
        weak var field: NSTextField?
        private var monitor: Any?

        init(text: Binding<String>, onMove: @escaping (Int) -> Void, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.text = text
            self.onMove = onMove
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func startMonitor() {
            stopMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let field = self.field, field.window?.isKeyWindow == true else {
                    return event
                }
                guard let key = PaletteKey(event: event) else { return event }
                switch key {
                case .up: self.onMove(-1)
                case .down: self.onMove(1)
                case .submit: self.onSubmit()
                case .cancel: self.onCancel()
                }
                return nil
            }
        }

        func stopMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)),
                 #selector(NSResponder.moveUpAndModifySelection(_:)),
                 #selector(NSResponder.moveToBeginningOfParagraph(_:)):
                onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)),
                 #selector(NSResponder.moveDownAndModifySelection(_:)),
                 #selector(NSResponder.moveToEndOfParagraph(_:)):
                onMove(1)
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                return false
            }
        }

        deinit {
            stopMonitor()
        }
    }
}
