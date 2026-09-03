import AppKit
import CoreGraphics

struct NotesWindowFrame {
    var cocoaRect: CGRect
    var isOnScreen: Bool
}

enum NotesWindowTracker {
    static func frontNotesFrame() -> NotesWindowFrame? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return nil
        }

        let notesWindows = info.compactMap { entry -> CGRect? in
            let owner = entry[kCGWindowOwnerName as String] as? String
            guard owner == "Notes" else { return nil }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { return nil }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let rect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            guard rect.width > 160, rect.height > 160 else { return nil }
            return rect
        }

        guard let quartz = notesWindows.first else { return nil }
        return NotesWindowFrame(cocoaRect: quartzToCocoa(quartz), isOnScreen: true)
    }

    static func dockedToolbarFrame(toolbarSize: CGSize) -> CGRect? {
        guard let notes = frontNotesFrame() else { return nil }
        let notesRect = notes.cocoaRect
        let screen = NSScreen.screens.first { $0.frame.intersects(notesRect) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return nil }

        let gap: CGFloat = 10
        let y = max(visible.minY + 12, min(notesRect.maxY - toolbarSize.height - 12, notesRect.maxY - toolbarSize.height))
        let rightX = notesRect.maxX + gap
        let leftX = notesRect.minX - gap - toolbarSize.width

        let x: CGFloat
        if rightX + toolbarSize.width <= visible.maxX - 8 {
            x = rightX
        } else if leftX >= visible.minX + 8 {
            x = leftX
        } else {
            x = notesRect.maxX - toolbarSize.width - 16
        }

        return CGRect(x: x, y: y, width: toolbarSize.width, height: toolbarSize.height)
    }

    private static func quartzToCocoa(_ rect: CGRect) -> CGRect {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: rect.origin.x,
            y: height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
