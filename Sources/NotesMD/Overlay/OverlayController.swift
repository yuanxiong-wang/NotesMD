import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let state: AppState
    private var toolbarPanel: NSPanel?
    private var palettePanel: NSPanel?
    private var slashPanel: NSPanel?
    private var quickOpenPanel: NSPanel?
    private var tocPanel: NSPanel?
    private var templatePanel: NSPanel?
    private var inlinePanel: NSPanel?
    private var onboardingWindow: NSWindow?
    private var lastPreview = false

    init(state: AppState) {
        self.state = state
        buildToolbar()
        inlinePanel = makeHUDPanel(size: NSSize(width: 340, height: 40))
        inlinePanel?.contentView = NSHostingView(rootView: InlineToolbarView(state: state))
    }

    func tick() {
        let capturing = state.isCapturingKeys
        let shouldShowToolbar = state.toolbarVisible && state.notesRunning && !capturing
        if shouldShowToolbar {
            if state.previewVisible != lastPreview {
                lastPreview = state.previewVisible
                rebuildToolbar()
            }
            followNotesWindow()
            toolbarPanel?.orderFrontRegardless()
        } else if capturing {
            toolbarPanel?.orderBack(nil)
        } else {
            toolbarPanel?.orderOut(nil)
        }

        if capturing {
            inlinePanel?.orderOut(nil)
        } else {
            positionInlineToolbar()
        }

        showKeyPanel(state.paletteVisible, panel: &palettePanel, size: NSSize(width: 520, height: 420), centered: true) {
            PaletteView(state: self.state)
        }
        showKeyPanel(state.slashVisible, panel: &slashPanel, size: NSSize(width: 360, height: 320), centered: false) {
            SlashView(state: self.state)
        }
        showKeyPanel(state.quickOpenVisible, panel: &quickOpenPanel, size: NSSize(width: 480, height: 420), centered: true) {
            QuickOpenView(state: self.state)
        }
        showOrHideHUD(state.tocVisible, panel: &tocPanel, size: NSSize(width: 260, height: 320), useTocPlacement: true) {
            TOCView(state: self.state)
        }
        showKeyPanel(state.templatePickerVisible, panel: &templatePanel, size: NSSize(width: 320, height: 280), centered: true) {
            TemplatePickerView(state: self.state)
        }

        if state.onboardingVisible {
            showOnboarding()
        } else if let window = onboardingWindow, window.isVisible {
            window.orderOut(nil)
            if !capturing {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func positionInlineToolbar() {
        guard state.showsFollowUI else {
            inlinePanel?.orderOut(nil)
            return
        }
        guard let bounds = state.selectionBounds, bounds.width > 1, bounds.height > 1 else {
            inlinePanel?.orderOut(nil)
            return
        }
        let size = NSSize(width: 360, height: 40)
        var x = bounds.minX
        var y = bounds.maxY + 8
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(bounds) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame {
            x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
            if y + size.height > screen.maxY - 8 {
                y = max(screen.minY + 8, bounds.minY - size.height - 8)
            }
        }
        inlinePanel?.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        inlinePanel?.orderFrontRegardless()
    }

    private func showKeyPanel<V: View>(
        _ visible: Bool,
        panel: inout NSPanel?,
        size: NSSize,
        centered: Bool,
        @ViewBuilder content: () -> V
    ) {
        if visible {
            if panel == nil {
                panel = makeKeyPanel(size: size)
            }
            if panel?.isVisible != true {
                panel?.contentView = NSHostingView(rootView: content())
                place(panel, size: size, centered: centered)
            }
            if panel?.isKeyWindow != true {
                NSApp.activate()
                panel?.makeKeyAndOrderFront(nil)
            }
        } else {
            panel?.orderOut(nil)
        }
    }

    private func showOrHideHUD<V: View>(
        _ visible: Bool,
        panel: inout NSPanel?,
        size: NSSize,
        useTocPlacement: Bool = false,
        @ViewBuilder content: () -> V
    ) {
        if visible {
            if panel == nil {
                panel = makeHUDPanel(size: size)
            }
            if panel?.isVisible != true {
                panel?.contentView = NSHostingView(rootView: content())
            }
            if useTocPlacement, let frame = tocFrame(size: size) {
                panel?.setFrame(frame, display: true)
            } else if let docked = NotesWindowTracker.dockedToolbarFrame(toolbarSize: size) {
                panel?.setFrame(docked, display: true)
            }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    /// Sit beside Notes, never over the note body.
    private func tocFrame(size: NSSize) -> CGRect? {
        guard let notes = NotesWindowTracker.frontNotesFrame()?.cocoaRect else { return nil }
        let screen = NSScreen.screens.first { $0.frame.intersects(notes) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let visible = screen else { return nil }
        let toolbarWidth: CGFloat = state.previewVisible ? 280 : 64
        let gap: CGFloat = 10
        let y = min(notes.maxY - size.height - 12, visible.maxY - size.height - 12)
        let rightX = notes.maxX + gap + toolbarWidth + gap
        if rightX + size.width <= visible.maxX - 8 {
            return CGRect(x: rightX, y: max(visible.minY + 12, y), width: size.width, height: size.height)
        }
        let leftX = notes.minX - gap - size.width
        if leftX >= visible.minX + 8 {
            return CGRect(x: leftX, y: max(visible.minY + 12, y), width: size.width, height: size.height)
        }
        return CGRect(
            x: visible.maxX - size.width - 16,
            y: visible.minY + 16,
            width: size.width,
            height: size.height
        )
    }

    private func place(_ panel: NSPanel?, size: NSSize, centered: Bool) {
        if let anchor = state.caretAnchor ?? state.selectionBounds, !centered {
            var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 12)
            if let screen = NSScreen.main?.visibleFrame {
                origin.x = min(max(origin.x, screen.minX + 12), screen.maxX - size.width - 12)
                origin.y = min(max(origin.y, screen.minY + 12), screen.maxY - size.height - 12)
            }
            panel?.setFrame(NSRect(origin: origin, size: size), display: true)
        } else if let screen = NSScreen.main?.visibleFrame {
            panel?.setFrame(
                NSRect(
                    x: screen.midX - size.width / 2,
                    y: screen.midY - size.height / 2 + 60,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
    }

    private func buildToolbar() {
        let panel = makeHUDPanel(size: NSSize(width: 64, height: 480))
        toolbarPanel = panel
        rebuildToolbar()
    }

    private func rebuildToolbar() {
        let compact = !state.previewVisible
        toolbarPanel?.contentView = NSHostingView(rootView: ToolbarView(state: state, compact: compact))
    }

    private func followNotesWindow() {
        let width: CGFloat = state.previewVisible ? 280 : 64
        let height: CGFloat = state.previewVisible ? 580 : 480
        guard let frame = NotesWindowTracker.dockedToolbarFrame(toolbarSize: CGSize(width: width, height: height)) else {
            return
        }
        toolbarPanel?.setFrame(frame, display: true)
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to NotesMD"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(state: state))
            onboardingWindow = window
        }
        if onboardingWindow?.isVisible != true {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            onboardingWindow?.center()
            onboardingWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func makeHUDPanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func makeKeyPanel(size: NSSize) -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .modalPanel
        return panel
    }

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
    }
}
