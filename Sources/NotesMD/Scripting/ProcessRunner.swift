import Foundation

enum ProcessRunner {
    struct TimeoutError: Error {}
    struct LaunchError: Error {
        let message: String
    }

    @discardableResult
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            throw LaunchError(message: error.localizedDescription)
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw TimeoutError()
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw LaunchError(message: err.isEmpty ? output : err)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func osascript(_ source: String, timeout: TimeInterval = 8) throws -> String {
        try run("/usr/bin/osascript", arguments: ["-e", source], timeout: timeout)
    }

    static func osascriptFile(_ url: URL, timeout: TimeInterval = 12) throws -> String {
        try run("/usr/bin/osascript", arguments: [url.path], timeout: timeout)
    }
}
