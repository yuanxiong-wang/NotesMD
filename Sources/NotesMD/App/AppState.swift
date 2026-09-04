import AppKit
import Foundation
import NotesMDCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var accessibilityTrusted = false
    @Published var notesRunning = false
    @Published var notesFrontmost = false
    @Published var currentNote: NoteRef?
    @Published var selectedText = ""
    @Published var markdownPreview = ""
    @Published var toolbarVisible = true
    @Published var paletteVisible = false
    @Published var onboardingVisible = false
    @Published var previewVisible = false
    @Published var slashVisible = false
    @Published var slashQuery = ""
    @Published var quickOpenVisible = false
    @Published var tocVisible = false
    @Published var tocItems: [NoteHeading] = []
    @Published var templatePickerVisible = false
    @Published var noteIndex: [NoteHit] = []
    @Published var templates: [NoteHit] = []
    @Published var isIndexing = false
    @Published var selectionBounds: CGRect?
    @Published var slashNeedsConsume = false
    @Published var status = "Waiting for Notes"
    @Published var errorMessage: String?
    @Published var lastAction = ""
    var onOverlayTick: (() -> Void)?

    let hotkeys = HotkeyMonitor()
    let typing = TypingMonitor()
    private var timer: Timer?
    private var previewTimer: Timer?
    private var lastBodyStamp = ""
    private var lastIndexAt: Date?
    private var lastPeekAt = Date.distantPast
    private var lastPermissionCheck = Date.distantPast
    private var lastPreviewHTML = ""
    private var previewRefreshInFlight = false
    private var previewGeneration = 0

    var showsFollowUI: Bool {
        notesRunning
            && notesFrontmost
            && accessibilityTrusted
            && hasSelection
            && !paletteVisible && !slashVisible && !quickOpenVisible && !onboardingVisible && !templatePickerVisible
    }

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isCapturingKeys: Bool {
        paletteVisible || slashVisible || quickOpenVisible || templatePickerVisible
    }

    func start() {
        refreshPermissions()
        if !accessibilityTrusted {
            onboardingVisible = true
        }
        hotkeys.onPalette = { [weak self] in self?.togglePalette() }
        hotkeys.onSlash = { [weak self] in self?.toggleSlash() }
        hotkeys.onToolbar = { [weak self] in self?.toggleToolbar() }
        hotkeys.onQuickOpen = { [weak self] in self?.toggleQuickOpen() }
        hotkeys.capturingKeys = { [weak self] in self?.isCapturingKeys == true }
        hotkeys.start()

        typing.onPalette = { [weak self] in self?.togglePalette() }
        typing.onSlash = { [weak self] in self?.toggleSlash() }
        typing.onToolbar = { [weak self] in self?.toggleToolbar() }
        typing.onQuickOpen = { [weak self] in self?.toggleQuickOpen() }
        typing.start()
        syncInputFlags()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        tick()
    }

    func refreshPermissions() {
        let trusted = AXBridge.isTrusted(prompt: false)
        let gained = trusted && !accessibilityTrusted
        accessibilityTrusted = trusted
        if gained {
            typing.stop()
            typing.start()
            hotkeys.stop()
            hotkeys.start()
        }
    }

    func requestAccessibility() {
        _ = AXBridge.isTrusted(prompt: true)
        refreshPermissions()
        Self.openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for item in urls {
            if let url = URL(string: item) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    func tick() {
        let now = Date()
        publish(\.notesRunning, NotesBridge.isRunning)
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        publish(
            \.notesFrontmost,
            front == NotesBridge.bundleID || front == Bundle.main.bundleIdentifier
        )
        syncInputFlags()

        if now.timeIntervalSince(lastPermissionCheck) > 5 {
            lastPermissionCheck = now
            refreshPermissions()
        }

        guard notesRunning else {
            setCurrentNote(nil)
            publish(\.selectedText, "")
            publish(\.selectionBounds, nil)
            publish(\.status, "Open Notes to begin")
            return
        }

        if typing.isTyping && !isCapturingKeys {
            if previewVisible { refreshPreviewAsync() }
            return
        }

        if accessibilityTrusted && notesFrontmost {
            AXBridge.enableEnhancedAccessibility()
            let selected = AXBridge.selectedTextQuick()
            publish(\.selectedText, selected)
            let bounds = selected.isEmpty ? nil : AXBridge.selectionBounds()
            publish(\.selectionBounds, bounds)
        } else {
            publish(\.selectedText, "")
            publish(\.selectionBounds, nil)
        }

        let peekInterval: TimeInterval = (previewVisible || tocVisible) ? 2 : 8
        guard now.timeIntervalSince(lastPeekAt) > peekInterval else { return }
        lastPeekAt = now

        do {
            let note = try NotesBridge.peekSelection()
            setCurrentNote(note)
            publish(\.status, "\(note.folder) · \(note.name)")
            if previewVisible { refreshPreviewAsync() }
            if tocVisible, lastBodyStamp != note.id + note.modified {
                lastBodyStamp = note.id + note.modified
                refreshTOC()
            }
        } catch NotesBridgeError.noSelection {
            setCurrentNote(nil)
            publish(\.selectedText, "")
            publish(\.selectionBounds, nil)
            publish(\.status, "Select a note in Notes")
        } catch NotesBridgeError.timeout {
            publish(\.status, "Notes is busy…")
        } catch {
            publish(\.status, error.localizedDescription)
        }
    }

    private func setCurrentNote(_ note: NoteRef?) {
        let previewChanged = currentNote?.id != note?.id
            || currentNote?.passwordProtected != note?.passwordProtected
        publish(\.currentNote, note)
        guard previewChanged else { return }
        previewGeneration &+= 1
        previewRefreshInFlight = false
        lastPreviewHTML = ""
        if previewVisible, !markdownPreview.isEmpty {
            markdownPreview = ""
        }
    }

    private func publish<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, T>, _ value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    func syncInputFlags() {
        typing.setPaletteCapturing(isCapturingKeys)
        typing.setNotesFrontmost(notesFrontmost)
    }

    func overlayNow() {
        onOverlayTick?()
    }

    func hidePalette() {
        paletteVisible = false
        syncInputFlags()
        overlayNow()
    }

    func hideSlash() {
        slashVisible = false
        syncInputFlags()
        overlayNow()
    }

    func hideQuickOpen() {
        quickOpenVisible = false
        overlayNow()
    }

    func hidePreview() {
        guard previewVisible else { return }
        previewVisible = false
        stopLivePreview()
        overlayNow()
    }

    func hideTOC() {
        tocVisible = false
        overlayNow()
    }

    func hideTemplates() {
        templatePickerVisible = false
        overlayNow()
    }

    func togglePalette() {
        paletteVisible.toggle()
        if paletteVisible {
            slashVisible = false
            quickOpenVisible = false
            NSApp.activate()
        }
        syncInputFlags()
        overlayNow()
    }

    func toggleQuickOpen() {
        quickOpenVisible.toggle()
        if quickOpenVisible {
            paletteVisible = false
            slashVisible = false
            NSApp.activate()
            refreshNoteIndexIfNeeded()
        }
        syncInputFlags()
        overlayNow()
    }

    func toggleSlash() {
        if slashVisible {
            slashVisible = false
            syncInputFlags()
            overlayNow()
            return
        }
        openSlash(query: "", consumeTypedSlash: false)
    }

    func toggleToolbar() {
        toolbarVisible.toggle()
        overlayNow()
    }

    func togglePreview() {
        previewVisible.toggle()
        if previewVisible {
            startLivePreview()
        } else {
            stopLivePreview()
        }
        overlayNow()
    }

    func toggleTOC() {
        tocVisible.toggle()
        if tocVisible { refreshTOC() }
        overlayNow()
    }

    func openSlash(query: String, consumeTypedSlash: Bool = false) {
        slashQuery = query
        slashNeedsConsume = consumeTypedSlash
        slashVisible = true
        paletteVisible = false
        quickOpenVisible = false
        NSApp.activate()
        syncInputFlags()
        overlayNow()
    }

    func applyParagraph(_ style: NativeParagraphStyle) {
        FormatActions.applyParagraph(style)
        lastAction = style.englishMenuName
    }

    func applyInline(_ style: NativeInlineStyle) {
        FormatActions.applyInline(style)
        lastAction = style.englishMenuName
    }

    func run(_ command: PaletteCommand) {
        errorMessage = nil
        lastAction = command.title
        paletteVisible = false

        switch command.kind {
        case .paragraph(let style):
            applyParagraph(style)
        case .inline(let style):
            applyInline(style)
        case .expand:
            expandMarkdown()
        case .convertSelection:
            convertSelection()
        case .convertNote:
            convertWholeNote()
        case .copyMarkdown:
            copyMarkdown()
        case .preview:
            togglePreview()
        case .toggleToolbar:
            toggleToolbar()
        case .permissions:
            onboardingVisible = true
        case .quickOpen:
            quickOpenVisible = true
            refreshNoteIndexIfNeeded()
        case .toc:
            tocVisible = true
            refreshTOC()
        }
        syncInputFlags()
        overlayNow()
    }

    func runSlash(_ command: SlashCommand) {
        slashVisible = false
        syncInputFlags()
        consumeSlashToken()
        lastAction = command.title
        switch command.kind {
        case .paragraph(let style):
            applyParagraph(style)
        case .inline(let style):
            applyInline(style)
        case .datetime:
            insertDateTime()
        case .templates:
            templatePickerVisible = true
            refreshNoteIndexIfNeeded()
            NSApp.activate()
        case .toc:
            tocVisible = true
            refreshTOC()
        case .quickOpen:
            quickOpenVisible = true
            refreshNoteIndexIfNeeded()
            NSApp.activate()
        }
        overlayNow()
    }

    func expandMarkdown() {
        let selected = AXBridge.selectedText()
        let target: String
        if !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target = selected
        } else if let note = currentNote {
            do {
                target = try NotesBridge.plaintext(of: note.id)
            } catch {
                present(error)
                return
            }
        } else {
            present(NotesBridgeError.noSelection)
            return
        }

        let plan = MarkdownPlanner.plan(for: target)
        if plan == .noChange {
            status = "No markdown to expand"
            return
        }
        FormatActions.applyPlan(plan)
        status = "Wrote formatting back to Notes"
    }

    func convertSelection() {
        let text = AXBridge.selectedText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Select some markdown first"
            return
        }
        let html = NotesMarkdown.markdownToHTML(text)
        FormatActions.pasteHTML(html)
        status = "Converted selection"
    }

    func convertWholeNote() {
        guard let note = currentNote else {
            present(NotesBridgeError.noSelection)
            return
        }
        do {
            let prepared = try NotesBridge.prepareWholeNoteConversion(note)
            let proceed = ConvertConfirm.confirmReplace(
                noteName: note.name,
                current: prepared.source,
                after: prepared.preview
            )
            guard proceed else {
                status = "Conversion cancelled"
                return
            }
            try NotesBridge.setBody(id: note.id, html: prepared.html)
            status = "Converted note from Markdown"
        } catch {
            present(error)
        }
    }

    func copyMarkdown() {
        guard let note = currentNote else {
            present(NotesBridgeError.noSelection)
            return
        }
        do {
            let md = try NotesBridge.copyNoteAsMarkdown(note)
            FormatActions.copyPlain(md)
            status = "Copied Markdown"
        } catch {
            present(error)
        }
    }

    func refreshPreview() {
        refreshPreviewAsync()
    }

    private func startLivePreview() {
        stopLivePreview()
        lastPreviewHTML = ""
        if currentNote == nil, notesRunning {
            setCurrentNote(try? NotesBridge.peekSelection())
        }
        refreshPreviewAsync()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPreviewAsync()
            }
        }
    }

    private func stopLivePreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewGeneration &+= 1
        previewRefreshInFlight = false
    }

    private func refreshPreviewAsync() {
        guard previewVisible else { return }
        guard let note = currentNote else {
            if !markdownPreview.isEmpty { markdownPreview = "" }
            return
        }
        if note.passwordProtected {
            lastPreviewHTML = ""
            let message = NotesBridgeError.locked.localizedDescription
            if markdownPreview != message { markdownPreview = message }
            return
        }
        guard !previewRefreshInFlight else { return }
        previewRefreshInFlight = true
        let generation = previewGeneration
        let noteID = note.id
        DispatchQueue.global(qos: .utility).async {
            let html: String
            do {
                html = try NotesBridge.body(of: noteID, timeout: 4)
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    guard self.previewGeneration == generation,
                          self.previewVisible,
                          self.currentNote?.id == noteID else { return }
                    self.previewRefreshInFlight = false
                    self.lastPreviewHTML = ""
                    if self.markdownPreview != message {
                        self.markdownPreview = message
                    }
                }
                return
            }
            let markdown = NotesMarkdown.htmlToMarkdown(html)
            Task { @MainActor in
                guard self.previewGeneration == generation,
                      self.previewVisible,
                      self.currentNote?.id == noteID else { return }
                self.previewRefreshInFlight = false
                guard html != self.lastPreviewHTML else { return }
                self.lastPreviewHTML = html
                if markdown != self.markdownPreview {
                    self.markdownPreview = markdown
                }
            }
        }
    }

    func refreshTOC() {
        guard let note = currentNote else {
            tocItems = []
            return
        }
        do {
            let html = try NotesBridge.body(of: note.id)
            tocItems = MarkdownTyping.headings(inHTML: html)
        } catch {
            tocItems = []
        }
    }

    func jumpToHeading(_ heading: NoteHeading) {
        tocVisible = false
        FormatActions.findInNote(heading.text)
        status = heading.text
        overlayNow()
    }

    func openNote(_ hit: NoteHit) {
        quickOpenVisible = false
        do {
            try NotesBridge.show(id: hit.id)
            status = hit.name
        } catch {
            present(error)
        }
        overlayNow()
    }

    func insertTemplate(_ hit: NoteHit) {
        templatePickerVisible = false
        do {
            let html = try NotesBridge.body(of: hit.id)
            FormatActions.pasteHTML(html)
            status = "Inserted \(hit.name)"
        } catch {
            present(error)
        }
        overlayNow()
    }

    func insertDateTime() {
        FormatActions.pastePlain(MarkdownTyping.currentDateTime())
        status = "Inserted date"
    }

    func refreshNoteIndexIfNeeded() {
        if isIndexing { return }
        if let lastIndexAt, Date().timeIntervalSince(lastIndexAt) < 40, !noteIndex.isEmpty {
            templates = NotesBridge.templates(from: noteIndex)
            return
        }
        isIndexing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let hits = (try? NotesBridge.listNotes()) ?? []
            Task { @MainActor in
                self.noteIndex = hits
                self.templates = NotesBridge.templates(from: hits)
                self.lastIndexAt = Date()
                self.isIndexing = false
            }
        }
    }

    private func consumeSlashToken() {
        guard slashNeedsConsume else {
            NotesBridge.activate()
            usleep(40_000)
            return
        }
        slashNeedsConsume = false
        NotesBridge.activate()
        usleep(50_000)
        FormatActions.selectToLineStart()
        usleep(35_000)
        let text = AXBridge.selectedText()
        if MarkdownTyping.isSlashLine(text) || text.hasSuffix("/") {
            FormatActions.deleteSelection()
            usleep(30_000)
        } else {
            FormatActions.collapseToEnd()
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        status = error.localizedDescription
    }
}

struct PaletteCommand: Identifiable {
    enum Kind {
        case paragraph(NativeParagraphStyle)
        case inline(NativeInlineStyle)
        case expand
        case convertSelection
        case convertNote
        case copyMarkdown
        case preview
        case toggleToolbar
        case permissions
        case quickOpen
        case toc
    }

    var id: String
    var title: String
    var subtitle: String
    var shortcut: String
    var symbol: String
    var kind: Kind
    var keywords: [String]

    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let q = query.lowercased()
        return title.lowercased().contains(q)
            || subtitle.lowercased().contains(q)
            || keywords.contains { $0.lowercased().contains(q) }
    }
}

enum PaletteCatalog {
    static let all: [PaletteCommand] = [
        PaletteCommand(id: "expand", title: "Expand Markdown", subtitle: "Convert the selection or current line using Notes styles", shortcut: "", symbol: "sparkles", kind: .expand, keywords: ["markdown", "convert", "展开"]),
        PaletteCommand(id: "open", title: "Quick Open", subtitle: "Jump to a note", shortcut: "⌘O", symbol: "magnifyingglass", kind: .quickOpen, keywords: ["goto", "search", "搜索"]),
        PaletteCommand(id: "toc", title: "Table of Contents", subtitle: "Headings in the current note", shortcut: "", symbol: "list.bullet.indent", kind: .toc, keywords: ["outline", "目录"]),
        PaletteCommand(id: "sel", title: "Convert Selection from Markdown", subtitle: "Paste formatted HTML back into the same note", shortcut: "", symbol: "arrow.triangle.2.circlepath", kind: .convertSelection, keywords: ["paste", "html"]),
        PaletteCommand(id: "note", title: "Convert Whole Note from Markdown", subtitle: "Replaces the note body. Skips notes with attachments.", shortcut: "", symbol: "doc.badge.gearshape", kind: .convertNote, keywords: ["full", "body"]),
        PaletteCommand(id: "copy", title: "Copy Note as Markdown", subtitle: "Leaves the original note untouched", shortcut: "", symbol: "doc.on.clipboard", kind: .copyMarkdown, keywords: ["export"]),
        PaletteCommand(id: "preview", title: "Toggle Markdown Preview", subtitle: "Read-only view of the current note", shortcut: "", symbol: "sidebar.right", kind: .preview, keywords: ["preview"]),
        PaletteCommand(id: "title", title: "Title", subtitle: "# + space · 格式 → 标题", shortcut: "", symbol: "textformat.size.larger", kind: .paragraph(.title), keywords: ["h1", "标题"]),
        PaletteCommand(id: "h2", title: "Heading", subtitle: "## + space · 格式 → 小标题", shortcut: "", symbol: "textformat", kind: .paragraph(.heading), keywords: ["h2", "小标题"]),
        PaletteCommand(id: "h3", title: "Subheading", subtitle: "### + space · 格式 → 副标题", shortcut: "", symbol: "textformat.subscript", kind: .paragraph(.subheading), keywords: ["h3", "副标题"]),
        PaletteCommand(id: "body", title: "Body", subtitle: "格式 → 正文", shortcut: "", symbol: "text.alignleft", kind: .paragraph(.body), keywords: ["正文"]),
        PaletteCommand(id: "mono", title: "Monostyled", subtitle: "``` + space", shortcut: "", symbol: "chevron.left.forwardslash.chevron.right", kind: .paragraph(.monostyled), keywords: ["code", "等宽"]),
        PaletteCommand(id: "quote", title: "Block Quote", subtitle: "> + space", shortcut: "", symbol: "text.quote", kind: .paragraph(.blockQuote), keywords: ["引用"]),
        PaletteCommand(id: "ul", title: "Bulleted List", subtitle: "- + space", shortcut: "", symbol: "list.bullet", kind: .paragraph(.bulleted), keywords: ["ul"]),
        PaletteCommand(id: "ol", title: "Numbered List", subtitle: "1. + space", shortcut: "", symbol: "list.number", kind: .paragraph(.numbered), keywords: ["ol"]),
        PaletteCommand(id: "dash", title: "Dashed List", subtitle: "格式 → 短划线列表", shortcut: "", symbol: "list.dash", kind: .paragraph(.dashed), keywords: ["dash"]),
        PaletteCommand(id: "check", title: "Checklist", subtitle: "[] + space", shortcut: "", symbol: "checklist", kind: .paragraph(.checklist), keywords: ["todo", "核对"]),
        PaletteCommand(id: "bold", title: "Bold", subtitle: "⌘B", shortcut: "⌘B", symbol: "bold", kind: .inline(.bold), keywords: ["粗体"]),
        PaletteCommand(id: "italic", title: "Italic", subtitle: "⌘I", shortcut: "⌘I", symbol: "italic", kind: .inline(.italic), keywords: ["斜体"]),
        PaletteCommand(id: "strike", title: "Strikethrough", subtitle: "格式 → 删除线", shortcut: "", symbol: "strikethrough", kind: .inline(.strikethrough), keywords: ["删除线"]),
        PaletteCommand(id: "mark", title: "Highlight", subtitle: "格式 → 高亮标记", shortcut: "", symbol: "highlighter", kind: .inline(.highlight), keywords: ["高亮"]),
        PaletteCommand(id: "link", title: "Add Link", subtitle: "⌘K", shortcut: "⌘K", symbol: "link", kind: .inline(.link), keywords: ["链接"]),
        PaletteCommand(id: "bar", title: "Toggle Toolbar", subtitle: "Dock next to Notes", shortcut: "⌘⇧M", symbol: "menubar.dock.rectangle", kind: .toggleToolbar, keywords: ["overlay"]),
        PaletteCommand(id: "perm", title: "Permissions", subtitle: "Accessibility and Automation", shortcut: "", symbol: "lock.shield", kind: .permissions, keywords: ["tcc"])
    ]
}
