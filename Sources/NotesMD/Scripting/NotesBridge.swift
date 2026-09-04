import AppKit
import Foundation
import NotesMDCore

struct NoteRef: Equatable {
    var id: String
    var name: String
    var folder: String
    var attachmentCount: Int
    var passwordProtected: Bool
    var modified: String
}

struct NoteHit: Equatable, Identifiable {
    var id: String
    var name: String
    var folder: String
}

enum NotesBridgeError: LocalizedError {
    case notesNotRunning
    case noSelection
    case locked
    case hasAttachments
    case scripting(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notesNotRunning: return "Notes is not running."
        case .noSelection: return "No note is selected in Notes."
        case .locked: return "This note is locked."
        case .hasAttachments: return "This note has attachments. Convert a selection instead of replacing the whole note."
        case .scripting(let message): return message
        case .timeout: return "Notes did not respond in time."
        }
    }
}

enum NotesBridge {
    static let bundleID = "com.apple.Notes"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static var pid: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    static func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func activate() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?
            .activate()
    }

    static func peekSelection() throws -> NoteRef {
        guard isRunning else { throw NotesBridgeError.notesNotRunning }
        let source = """
        tell application "Notes"
            if (count of selection) is 0 then return "NO_SELECTION"
            set notesmdID to «class seld» of (selection as record)
            set notesmdNote to missing value
            try
                set notesmdNote to note id notesmdID
            on error
                return "NO_SELECTION"
            end try
            if notesmdNote is missing value then return "NO_SELECTION"
            set notesmdDelim to character id 30
            set notesmdName to ""
            try
                set notesmdName to name of notesmdNote
            end try
            set notesmdFolder to ""
            try
                set notesmdFolder to name of container of notesmdNote
            end try
            set notesmdAtt to 0
            try
                set notesmdAtt to count of attachments of notesmdNote
            end try
            set notesmdPW to "false"
            try
                if password protected of notesmdNote then set notesmdPW to "true"
            end try
            set notesmdMod to ""
            try
                set notesmdMod to (modification date of notesmdNote) as string
            end try
            return notesmdID & notesmdDelim & notesmdName & notesmdDelim & notesmdFolder & notesmdDelim & notesmdAtt & notesmdDelim & notesmdPW & notesmdDelim & notesmdMod
        end tell
        """
        let output = try runScript(source)
        if output == "NO_SELECTION" { throw NotesBridgeError.noSelection }
        let parts = output.components(separatedBy: "\u{1e}")
        guard parts.count >= 6 else {
            throw NotesBridgeError.scripting(output)
        }
        return NoteRef(
            id: parts[0],
            name: parts[1],
            folder: parts[2],
            attachmentCount: Int(parts[3]) ?? 0,
            passwordProtected: parts[4].lowercased().contains("true"),
            modified: parts[5]
        )
    }

    static func body(of id: String, timeout: TimeInterval = 15) throws -> String {
        let source = """
        tell application "Notes"
            return body of note id "\(escapeAS(id))"
        end tell
        """
        return try runScript(source, timeout: timeout)
    }

    static func plaintext(of id: String) throws -> String {
        let source = """
        tell application "Notes"
            return plaintext of note id "\(escapeAS(id))"
        end tell
        """
        return try runScript(source, timeout: 15)
    }

    static func setBody(id: String, html: String) throws {
        let dir = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        let htmlURL = dir.appendingPathComponent("notesmd-body-\(token).html")
        let scriptURL = dir.appendingPathComponent("notesmd-setbody-\(token).scpt.txt")
        defer {
            try? FileManager.default.removeItem(at: htmlURL)
            try? FileManager.default.removeItem(at: scriptURL)
        }
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        let script = """
        set htmlPath to "\(escapeAS(htmlURL.path))"
        set noteId to "\(escapeAS(id))"
        set htmlText to read POSIX file htmlPath as «class utf8»
        tell application "Notes"
            set body of note id noteId to htmlText
        end tell
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        _ = try ProcessRunner.osascriptFile(scriptURL, timeout: 15)
    }

    static func copyNoteAsMarkdown(_ note: NoteRef, timeout: TimeInterval = 15) throws -> String {
        if note.passwordProtected { throw NotesBridgeError.locked }
        let html = try body(of: note.id, timeout: timeout)
        return NotesMarkdown.htmlToMarkdown(html)
    }

    static func show(id: String) throws {
        let source = """
        tell application "Notes"
            show note id "\(escapeAS(id))"
            activate
        end tell
        """
        _ = try runScript(source)
    }

    static func listNotes() throws -> [NoteHit] {
        guard isRunning else { throw NotesBridgeError.notesNotRunning }
        let source = """
        tell application "Notes"
            set AppleScript's text item delimiters to character id 31
            set idText to (id of every note) as text
            set nameText to (name of every note) as text
            set folderText to ""
            try
                set folderText to (name of container of every note) as text
            on error
                set folderText to ""
            end try
            set AppleScript's text item delimiters to character id 29
            return idText & (character id 29) & nameText & (character id 29) & folderText
        end tell
        """
        let output = try runScript(source, timeout: 25)
        let chunks = output.components(separatedBy: "\u{1d}")
        guard chunks.count >= 2 else { return [] }
        let ids = chunks[0].components(separatedBy: "\u{1f}")
        let names = chunks[1].components(separatedBy: "\u{1f}")
        let folders = chunks.count >= 3 ? chunks[2].components(separatedBy: "\u{1f}") : []
        let count = min(ids.count, names.count)
        var hits: [NoteHit] = []
        hits.reserveCapacity(count)
        for i in 0..<count {
            let id = ids[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = names[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            let folder = i < folders.count ? folders[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            hits.append(NoteHit(id: id, name: name, folder: folder))
        }
        return hits
    }

    static func templates(from notes: [NoteHit]) -> [NoteHit] {
        notes.filter { $0.folder == "Templates" || $0.folder == "模板" }
    }

    struct MarkdownConversion {
        var source: String
        var html: String
        var preview: String
    }

    static func prepareWholeNoteConversion(_ note: NoteRef) throws -> MarkdownConversion {
        if note.passwordProtected { throw NotesBridgeError.locked }
        if note.attachmentCount > 0 { throw NotesBridgeError.hasAttachments }
        let source = try plaintext(of: note.id)
        let html = NotesMarkdown.markdownToHTML(source)
        let preview = NotesMarkdown.htmlToMarkdown(html)
        return MarkdownConversion(source: source, html: html, preview: preview)
    }

    static func convertWholeNoteFromMarkdown(_ note: NoteRef) throws {
        let prepared = try prepareWholeNoteConversion(note)
        try setBody(id: note.id, html: prepared.html)
    }

    private static func runScript(_ source: String, timeout: TimeInterval = 8) throws -> String {
        do {
            return try ProcessRunner.osascript(source, timeout: timeout)
        } catch is ProcessRunner.TimeoutError {
            throw NotesBridgeError.timeout
        } catch let error as ProcessRunner.LaunchError {
            throw NotesBridgeError.scripting(error.message)
        }
    }

    private static func escapeAS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
