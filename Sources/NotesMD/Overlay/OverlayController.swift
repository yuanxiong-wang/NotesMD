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
    private var previewPanel: NSPanel?
    private var templatePanel: NSPanel?
    private var inlinePanel: NSPanel?
    private var onboardingWindow: NSWindow?

    private let chromeRadius: CGFloat = 16

    init(state: AppState) {
        self.state = state
        buildToolbar()
        inlinePanel = makeHUDPanel(size: NSSize(width: 360, height: 40))
        inlinePanel?.contentView = NSHostingView(rootView: InlineToolbarView(state: state))
    }

    func tick() {
        let capturing = state.isCapturingKeys
        let leaveChromeAlone = state.notesFrontmost && state.typing.isTyping && !capturing

        showKeyPanel(state.paletteVisible, panel: &palettePanel, size: NSSize(width: 520, height: 420)) {
            PaletteView(state: self.state)
        }
        showKeyPanel(state.slashVisible, panel: &slashPanel, size: NSSize(width: 360, height: 320)) {
            SlashView(state: self.state)
        }
        showKeyPanel(state.quickOpenVisible, panel: &quickOpenPanel, size: NSSize(width: 480, height: 420)) {
            QuickOpenView(state: self.state)
        }
        showKeyPanel(state.templatePickerVisible, panel: &templatePanel, size: NSSize(width: 320, height: 280)) {
            TemplatePickerView(state: self.state)
        }
        showOrHideHUD(state.tocVisible && state.notesFrontmost, panel: &tocPanel, size: NSSize(width: 260, height: 320), stacked: false) {
            TOCView(state: self.state)
        }
        showOrHideHUD(state.previewVisible && state.notesFrontmost, panel: &previewPanel, size: NSSize(width: 280, height: 420), stacked: true) {
            MarkdownPreviewView(state: self.state)
        }

        if capturing || state.typing.isTyping {
            inlinePanel?.orderOut(nil)
        } else {
            positionInlineToolbar()
        }

        if !leaveChromeAlone {
            let shouldShowToolbar = state.toolbarVisible && state.notesRunning && state.notesFrontmost && !capturing
            if shouldShowToolbar {
                followNotesWindow()
                if toolbarPanel?.isVisible != true {
                    toolbarPanel?.orderFrontRegardless()
                }
            } else if capturing {
                toolbarPanel?.orderBack(nil)
            } else {
                toolbarPanel?.orderOut(nil)
            }
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
        guard state.showsFollowUI,
              let bounds = state.selectionBounds,
              bounds.width > 1,
              bounds.height > 1 else {
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
        @ViewBuilder content: () -> V
    ) {
        if visible {
            if panel == nil {
                panel = makeKeyPanel(size: size)
            }
            if panel?.isVisible != true {
                panel?.contentView = NSHostingView(rootView: content())
                placeCentered(panel, size: size)
            }
            if panel?.isKeyWindow != true {
                NSApp.activate()
                panel?.makeKeyAndOrderFront(nil)
            }
        } else if panel?.isVisible == true {
            panel?.orderOut(nil)
        }
    }

    private func showOrHideHUD<V: View>(
        _ visible: Bool,
        panel: inout NSPanel?,
        size: NSSize,
        stacked: Bool,
        @ViewBuilder content: () -> V
    ) {
        if visible {
            if panel == nil {
                panel = makeHUDPanel(size: size)
            }
            if panel?.isVisible != true {
                setHUDContent(panel, content())
            }
            if let frame = accessoryFrame(size: size, stacked: stacked) {
                setFrameIfNeeded(panel, frame)
            } else if panel?.isVisible != true {
                panel?.orderFrontRegardless()
            }
        } else if panel?.isVisible == true {
            panel?.orderOut(nil)
        }
    }

    /// Sit beside the icon toolbar, never over the note body.
    private func accessoryFrame(size: NSSize, stacked: Bool) -> CGRect? {
        guard let notes = NotesWindowTracker.frontNotesFrame()?.cocoaRect else { return nil }
        let screen = NSScreen.screens.first { $0.frame.intersects(notes) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let visible = screen else { return nil }
        let toolbarWidth: CGFloat = 64
        let gap: CGFloat = 10
        var y = min(notes.maxY - size.height - 12, visible.maxY - size.height - 12)
        if stacked {
            y = max(visible.minY + 12, y - 40)
        }
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

    private func placeCentered(_ panel: NSPanel?, size: NSSize) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
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

    private func buildToolbar() {
        let panel = makeHUDPanel(size: NSSize(width: 64, height: 640))
        toolbarPanel = panel
        setHUDContent(panel, ToolbarView(state: state))
    }

    private func followNotesWindow() {
        var height: CGFloat = 640
        if let notes = NotesWindowTracker.frontNotesFrame()?.cocoaRect {
            height = min(640, max(360, notes.height - 24))
        }
        let size = CGSize(width: 64, height: height)
        guard let frame = NotesWindowTracker.dockedToolbarFrame(toolbarSize: size) else {
            return
        }
        setFrameIfNeeded(toolbarPanel, frame)
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
    }

    private func setHUDContent<V: View>(_ panel: NSPanel?, _ view: V) {
        guard let panel else { return }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        wrapHUD(hosting, in: panel)
    }

    private func wrapHUD(_ view: NSView, in panel: NSPanel) {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        effect.material = .contentBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        effect.wantsLayer = true
        effect.layer?.cornerRadius = chromeRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        view.frame = effect.bounds
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        effect.addSubview(view)
        panel.contentView = effect
        panel.invalidateShadow()
    }

    private func setFrameIfNeeded(_ panel: NSPanel?, _ rect: CGRect) {
        guard let panel else { return }
        let current = panel.frame
        let moved = abs(current.minX - rect.minX) > 2
            || abs(current.minY - rect.minY) > 2
            || abs(current.width - rect.width) > 2
            || abs(current.height - rect.height) > 2
        if moved {
            panel.setFrame(rect, display: false)
            panel.invalidateShadow()
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
