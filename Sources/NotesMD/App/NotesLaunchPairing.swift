import AppKit
import Foundation

enum NotesLaunchPairing {
    static let defaultsKey = "launchWithNotes"
    static let agentLabel = "app.notesmd.notewatcher"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
        if enabled {
            installAgent()
        } else {
            uninstallAgent()
        }
    }

    static func installAgent() {
        let appPath = Bundle.main.bundlePath
        let script = Bundle.main.url(forResource: "notesmd-watch", withExtension: "sh")?.path
            ?? (appPath as NSString).appendingPathComponent("Contents/Resources/notesmd-watch.sh")
        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plist = agents.appendingPathComponent("\(agentLabel).plist")
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/zsh</string>
                <string>\(script)</string>
                <string>\(appPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
        </dict>
        </plist>
        """
        do {
            try xml.write(to: plist, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        let uid = getuid()
        let domain = "gui/\(uid)/\(agentLabel)"
        _ = try? ProcessRunner.run("/bin/launchctl", arguments: ["bootout", domain], timeout: 5)
        _ = try? ProcessRunner.run("/bin/launchctl", arguments: ["bootstrap", "gui/\(uid)", plist.path], timeout: 5)
    }

    static func uninstallAgent() {
        let uid = getuid()
        _ = try? ProcessRunner.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid)/\(agentLabel)"], timeout: 5)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    static func suppressUntilNotesRelaunch() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotesMD")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("skip-autolaunch").path,
            contents: Data()
        )
    }
}
