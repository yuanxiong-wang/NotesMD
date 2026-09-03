import AppKit
import SwiftUI

@main
enum NotesMDMain {
    static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        NotesMDMain.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var overlay: OverlayController!
    var statusItem: NSStatusItem?
    private var followTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var launchWithNotesItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(state: state)
        setupStatusItem()
        state.start()
        if NotesLaunchPairing.isEnabled {
            NotesLaunchPairing.installAgent()
        }
        observeNotesLifecycle()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.overlay.tick()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        followTimer?.invalidate()
        state.hotkeys.stop()
        state.typing.stop()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func observeNotesLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == NotesBridge.bundleID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if !NotesBridge.isRunning {
                    NSApp.terminate(nil)
                }
            }
        })
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotesMD")
                button.image?.isTemplate = true
            }
            button.toolTip = "NotesMD — Markdown for Apple Notes"
        }

        let menu = NSMenu()
        menu.addItem(menuItem("Slash Commands…", action: #selector(openSlash), key: "p", modifiers: [.command, .shift]))
        menu.addItem(menuItem("Command Palette…", action: #selector(openPalette), key: "", modifiers: []))
        menu.addItem(menuItem("Quick Open…", action: #selector(openQuickOpen), key: "o", modifiers: [.command]))
        menu.addItem(menuItem("Table of Contents", action: #selector(openTOC), key: "", modifiers: []))
        menu.addItem(menuItem("Toggle Toolbar", action: #selector(toggleToolbar), key: "m", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(menuItem("Convert Selection from Markdown", action: #selector(convertSelection), key: nil))
        menu.addItem(menuItem("Convert Whole Note from Markdown", action: #selector(convertNote), key: nil))
        menu.addItem(menuItem("Copy Note as Markdown", action: #selector(copyMarkdown), key: nil))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Notes", action: #selector(openNotes), key: nil))
        menu.addItem(menuItem("Permissions…", action: #selector(openPermissions), key: nil))
        let pairing = menuItem("Launch with Apple Notes", action: #selector(toggleLaunchWithNotes), key: nil)
        pairing.state = NotesLaunchPairing.isEnabled ? .on : .off
        launchWithNotesItem = pairing
        menu.addItem(pairing)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit NotesMD", action: #selector(quit), key: "q", modifiers: [.command]))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector, key: String? = nil, modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key ?? "")
        item.target = self
        if key != nil {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    @objc private func openPalette() { state.togglePalette() }
    @objc private func openSlash() { state.toggleSlash() }
    @objc private func openQuickOpen() { state.toggleQuickOpen() }
    @objc private func openTOC() {
        state.tocVisible.toggle()
        if state.tocVisible { state.refreshTOC() }
    }
    @objc private func toggleToolbar() { state.toolbarVisible.toggle() }
    @objc private func convertSelection() { state.convertSelection() }
    @objc private func convertNote() { state.convertWholeNote() }
    @objc private func copyMarkdown() { state.copyMarkdown() }
    @objc private func openNotes() { NotesBridge.launch() }
    @objc private func openPermissions() { state.onboardingVisible = true }
    @objc private func toggleLaunchWithNotes(_ sender: NSMenuItem) {
        let enabled = !NotesLaunchPairing.isEnabled
        NotesLaunchPairing.setEnabled(enabled)
        sender.state = enabled ? .on : .off
    }
    @objc private func quit() {
        NotesLaunchPairing.suppressUntilNotesRelaunch()
        NSApp.terminate(nil)
    }
}
