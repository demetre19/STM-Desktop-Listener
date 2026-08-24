import Cocoa
import Foundation

enum CommandShortcutRunner {
    struct Result {
        let output: String
        let elevated: Bool
    }

    static func runSavedCommand() throws -> Result {
        guard let command = ConfigStore.string("commandShortcut.command")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            throw SimpleError("No command is saved.")
        }
        return try run(command)
    }

    static func run(_ command: String) throws -> Result {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SimpleError("No command is saved.")
        }
        if let elevatedCommand = commandAfterLeadingSudo(trimmed) {
            return try runWithAdministratorPrivileges(elevatedCommand)
        }
        return try runProcess(command: trimmed)
    }

    private static func commandAfterLeadingSudo(_ command: String) -> String? {
        if command == "sudo" {
            return ""
        }
        guard command.hasPrefix("sudo ") else { return nil }
        return String(command.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runProcess(command: String) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let outputText = readText(from: output)
        let errorText = readText(from: error)
        guard process.terminationStatus == 0 else {
            throw SimpleError(errorText.isEmpty ? "Command failed with exit code \(process.terminationStatus)." : errorText)
        }
        return Result(output: outputText, elevated: false)
    }

    private static func runWithAdministratorPrivileges(_ command: String) throws -> Result {
        guard !command.isEmpty else {
            throw SimpleError("The saved sudo command is empty.")
        }
        let script = "do shell script \(appleScriptString(command)) with administrator privileges"
        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo) else {
            let message = (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "Administrator command failed."
            throw SimpleError(message)
        }
        return Result(output: descriptor.stringValue ?? "", elevated: true)
    }

    private static func appleScriptString(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func readText(from pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
