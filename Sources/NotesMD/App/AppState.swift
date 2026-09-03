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
    @Published var caretAnchor: CGRect?
    @Published var slashNeedsConsume = false
    @Published var status = "Waiting for Notes"
    @Published var errorMessage: String?
    @Published var lastAction = ""

    let hotkeys = HotkeyMonitor()
    let typing = TypingMonitor()
    private var timer: Timer?
    private var lastBodyStamp = ""
    private var lastIndexAt: Date?

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
        hotkeys.onToolbar = { [weak self] in self?.toolbarVisible.toggle() }
        hotkeys.onQuickOpen = { [weak self] in self?.toggleQuickOpen() }
        hotkeys.capturingKeys = { [weak self] in self?.isCapturingKeys == true }
        hotkeys.start()

        typing.onStatus = { [weak self] message in
            self?.status = message
        }
        typing.onPalette = { [weak self] in self?.togglePalette() }
        typing.onSlash = { [weak self] in self?.toggleSlash() }
        typing.onToolbar = { [weak self] in self?.toolbarVisible.toggle() }
        typing.onQuickOpen = { [weak self] in self?.toggleQuickOpen() }
        typing.capturingKeys = { [weak self] in
            self?.isCapturingKeys == true
        }
        typing.start()

        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
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
        refreshPermissions()
        notesRunning = NotesBridge.isRunning
        notesFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == NotesBridge.bundleID
            || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier

        guard notesRunning else {
            currentNote = nil
            selectedText = ""
            selectionBounds = nil
            caretAnchor = nil
            status = "Open Notes to begin"
            return
        }

        if accessibilityTrusted {
            AXBridge.enableEnhancedAccessibility()
            if !typing.isBusy {
                selectedText = AXBridge.selectedText()
                selectionBounds = AXBridge.selectionBounds()
                caretAnchor = AXBridge.caretAnchor()
            }
        }

        do {
            let note = try NotesBridge.peekSelection()
            currentNote = note
            if !typing.isBusy {
                status = "\(note.folder) · \(note.name)"
            }
            if (previewVisible || tocVisible), lastBodyStamp != note.id + note.modified {
                lastBodyStamp = note.id + note.modified
                if previewVisible { refreshPreview() }
                if tocVisible { refreshTOC() }
            }
        } catch NotesBridgeError.noSelection {
            currentNote = nil
            status = "Select a note in Notes"
        } catch NotesBridgeError.timeout {
            status = "Notes is busy…"
        } catch {
            status = error.localizedDescription
        }
    }

    func togglePalette() {
        paletteVisible.toggle()
        if paletteVisible {
            slashVisible = false
            quickOpenVisible = false
            NSApp.activate()
        }
    }

    func toggleQuickOpen() {
        quickOpenVisible.toggle()
        if quickOpenVisible {
            paletteVisible = false
            slashVisible = false
            NSApp.activate()
            refreshNoteIndexIfNeeded()
        }
    }

    func toggleSlash() {
        if slashVisible {
            slashVisible = false
            return
        }
        openSlash(query: "", consumeTypedSlash: false)
    }

    func openSlash(query: String, consumeTypedSlash: Bool = false) {
        slashQuery = query
        slashNeedsConsume = consumeTypedSlash
        slashVisible = true
        paletteVisible = false
        quickOpenVisible = false
        NSApp.activate()
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
            previewVisible.toggle()
            if previewVisible { refreshPreview() }
        case .toggleToolbar:
            toolbarVisible.toggle()
        case .permissions:
            onboardingVisible = true
        case .quickOpen:
            quickOpenVisible = true
            refreshNoteIndexIfNeeded()
        case .toc:
            tocVisible = true
            refreshTOC()
        }
    }

    func runSlash(_ command: SlashCommand) {
        slashVisible = false
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
    }

    func expandMarkdown() {
        let target: String
        if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target = selectedText
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
        let text = selectedText
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
            try NotesBridge.convertWholeNoteFromMarkdown(note)
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
        guard let note = currentNote else {
            markdownPreview = ""
            return
        }
        do {
            markdownPreview = try NotesBridge.copyNoteAsMarkdown(note)
        } catch {
            markdownPreview = error.localizedDescription
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
    }

    func openNote(_ hit: NoteHit) {
        quickOpenVisible = false
        do {
            try NotesBridge.show(id: hit.id)
            status = hit.name
        } catch {
            present(error)
        }
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
