import Cocoa
import Foundation

enum SystemPowerAction: String {
    case shutdown
    case sleep

    var label: String {
        switch self {
        case .shutdown: return "shut down"
        case .sleep: return "sleep"
        }
    }
}

struct SystemPowerStatus {
    let title: String
    let details: String
}


private struct ScheduledPowerInfo {
    let action: String
    let target: Date
}

private struct KeepAwakeInfo {
    let end: Date?
    let seconds: Int
}
private struct ProcessRow {
    let pid: Int
    let ppid: Int
    let command: String
    let arguments: String
}

enum SystemPowerController {
    private static let powerLabel = "com.seotimemachines.stm-desktop-listener.power"
    private static let keepAwakeLabel = "com.seotimemachines.stm-desktop-listener.keep-awake"

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private static var powerPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(powerLabel).plist")
    }

    private static var keepAwakePlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(keepAwakeLabel).plist")
    }

    private static var executablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "/Applications/STM Desktop Listener.app/Contents/MacOS/STM Desktop Listener"
    }

    static func runCommandLineIfNeeded() -> Bool {
        let args = CommandLine.arguments
        do {
            if let markerIndex = args.firstIndex(of: "--power-runner"), args.indices.contains(markerIndex + 1) {
                guard let action = SystemPowerAction(rawValue: args[markerIndex + 1]) else {
                    Logger.log("power runner failed unknown action")
                    return true
                }
                let code = runScheduledAction(action)
                exit(code)
            }
            if args.contains("--power-status") {
                let current = status()
                print(current.details)
                return true
            }
            if args.contains("--power-cancel") {
                try cancelScheduledPower()
                print("Cancelled scheduled shut down or sleep action.")
                return true
            }
            if args.contains("--keep-awake-off") {
                try stopKeepAwake()
                print("Keep Awake stopped.")
                return true
            }
            if let index = args.firstIndex(of: "--git-autosave") {
                _ = index
                let result = autosaveGitNow()
                print(result.details)
                return true
            }
            if let index = args.firstIndex(of: "--git-autosave-repo"), args.indices.contains(index + 1) {
                let result = autosaveRepos(Set([args[index + 1]]))
                print(result.isEmpty ? "No dirty changes found." : result.joined(separator: "\n"))
                return true
            }
            if let index = args.firstIndex(of: "--power-schedule"), args.indices.contains(index + 2),
               let action = SystemPowerAction(rawValue: args[index + 1]) {
                let input = args[(index + 2)...].joined(separator: " ")
                let result = try schedule(action, when: input)
                print(result.details)
                return true
            }
            if let index = args.firstIndex(of: "--keep-awake"), args.indices.contains(index + 1) {
                let input = args[(index + 1)...].joined(separator: " ")
                let result = try keepAwake(until: input)
                print(result.details)
                return true
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return true
        }
        return false
    }

    static func schedule(_ action: SystemPowerAction, when rawInput: String) throws -> SystemPowerStatus {
        try schedule(action, at: parseWhen(rawInput))
    }

    static func schedule(_ action: SystemPowerAction, at target: Date) throws -> SystemPowerStatus {
        guard target > Date() else {
            throw SimpleError("Choose a future date and time.")
        }
        try cancelScheduledPower()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: target)
        let payload: [String: Any] = [
            "Label": powerLabel,
            "ProgramArguments": [executablePath, "--power-runner", action.rawValue],
            "StartCalendarInterval": [
                "Year": components.year ?? 0,
                "Month": components.month ?? 0,
                "Day": components.day ?? 0,
                "Hour": components.hour ?? 0,
                "Minute": components.minute ?? 0
            ],
            "StandardOutPath": AppPaths.logURL.path,
            "StandardErrorPath": AppPaths.logURL.path,
            "STMAction": action.rawValue,
            "STMTargetDate": ISO8601DateFormatter().string(from: target)
        ]
        try writePlist(payload, to: powerPlistURL)
        try launchctl(["bootstrap", "gui/\(getuid())", powerPlistURL.path], allowAlreadyUnloaded: false)
        Logger.log("power scheduled action=\(action.rawValue) target=\(format(target))")
        return SystemPowerStatus(
            title: "Scheduled \(action.label)",
            details: "\(action.label.capitalized) scheduled for \(format(target)).\n\nVisible status is now in the Power menu and Power Status. Shutdown will auto-commit dirty git repos discovered from open cmux/OMP sessions before it runs."
        )
    }

    static func cancelScheduledPower() throws {
        try? launchctl(["bootout", "gui/\(getuid())/\(powerLabel)"], allowAlreadyUnloaded: true)
        if FileManager.default.fileExists(atPath: powerPlistURL.path) {
            try? launchctl(["bootout", "gui/\(getuid())", powerPlistURL.path], allowAlreadyUnloaded: true)
            try FileManager.default.removeItem(at: powerPlistURL)
            Logger.log("power schedule cancelled")
        }
    }

    static func keepAwake(until rawInput: String) throws -> SystemPowerStatus {
        let target = try parseKeepAwakeTarget(rawInput)
        let seconds = target.seconds
        let endDate = target.endDate
        try stopKeepAwake()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "Label": keepAwakeLabel,
            "ProgramArguments": ["/usr/bin/caffeinate", "-dimsu", "-t", String(seconds)],
            "RunAtLoad": true,
            "StandardOutPath": AppPaths.logURL.path,
            "StandardErrorPath": AppPaths.logURL.path,
            "STMEndDate": ISO8601DateFormatter().string(from: endDate)
        ]
        try writePlist(payload, to: keepAwakePlistURL)
        try launchctl(["bootstrap", "gui/\(getuid())", keepAwakePlistURL.path], allowAlreadyUnloaded: false)
        Logger.log("keep awake started seconds=\(seconds) input=\(rawInput)")
        return SystemPowerStatus(title: "Keep Awake", details: "Keeping this Mac awake until \(format(endDate)) (\(formatDuration(TimeInterval(seconds)))).\n\nVisible status is now in the Power menu and Power Status.")
    }

    static func stopKeepAwake() throws {
        if FileManager.default.fileExists(atPath: keepAwakePlistURL.path) {
            try? launchctl(["bootout", "gui/\(getuid())", keepAwakePlistURL.path], allowAlreadyUnloaded: true)
            try FileManager.default.removeItem(at: keepAwakePlistURL)
            Logger.log("keep awake stopped")
        }
    }

    static func status() -> SystemPowerStatus {
        let lines = menuStatusLines() + [
            "",
            "Scheduled shutdown auto-save:",
            "• Stages and commits dirty git repos discovered from open cmux/OMP sessions.",
            "• Skips repos in merge/rebase/cherry-pick/revert states.",
            "• Does not push and cannot save unsaved editor buffers.",
            "",
            "Logs: \(AppPaths.logURL.path)"
        ]
        return SystemPowerStatus(title: "Power Controls", details: lines.joined(separator: "\n"))
    }

    static func quickStatusTitle() -> String {
        let scheduled = scheduledPowerInfo()
        let awake = keepAwakeInfo()
        if let scheduled, awake != nil {
            return "Power: \(scheduled.action.capitalized) \(shortTime(scheduled.target)) · Awake"
        }
        if let scheduled {
            return "Power: \(scheduled.action.capitalized) \(shortTime(scheduled.target))"
        }
        if awake != nil {
            return "Power: Awake"
        }
        return "Power: Off"
    }

    static func menuStatusLines() -> [String] {
        var lines: [String] = []
        if let scheduled = scheduledPowerInfo() {
            lines.append("Scheduled: \(scheduled.action.capitalized) at \(format(scheduled.target))")
        } else {
            lines.append("Scheduled: none")
        }
        if let awake = keepAwakeInfo() {
            if let end = awake.end {
                lines.append("Keep Awake: on until \(format(end)) (\(formatRemaining(until: end)))")
            } else {
                lines.append("Keep Awake: on for \(formatDuration(TimeInterval(awake.seconds))) from last start")
            }
        } else {
            lines.append("Keep Awake: off")
        }
        return lines
    }

    static func autosaveGitNow() -> SystemPowerStatus {
        let result = autosaveOpenSessionRepos()
        return SystemPowerStatus(title: "Git Autosave", details: result.isEmpty ? "No open dirty git repos found." : result.joined(separator: "\n"))
    }

    private static func runScheduledAction(_ action: SystemPowerAction) -> Int32 {
        Logger.log("power runner started action=\(action.rawValue)")
        notifyWithAppleScript(title: "STM Power", body: "Starting scheduled \(action.label).")
        if action == .shutdown {
            let autosave = autosaveOpenSessionRepos()
            let summary = autosave.isEmpty ? "No dirty cmux/OMP git repos found." : autosave.joined(separator: " ")
            Logger.log("power runner autosave summary=\(summary)")
            notifyWithAppleScript(title: "STM Power", body: "Git autosave complete. \(summary)")
        }
        let result: ProcessResult
        switch action {
        case .shutdown:
            result = runProcess("/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"])
        case .sleep:
            result = runProcess("/usr/bin/pmset", ["sleepnow"])
        }
        Logger.log("power runner finished action=\(action.rawValue) status=\(result.status) output=\(result.combinedOutput)")
        if result.status == 0 {
            clearCompletedScheduledPower()
        }
        return result.status
    }

    private static func parseWhen(_ rawInput: String, now: Date = Date()) throws -> Date {
        let cleaned = rawInput
            .lowercased()
            .replacingOccurrences(of: "until", with: " ")
            .replacingOccurrences(of: "today", with: " ")
            .replacingOccurrences(of: "at", with: " ")
            .replacingOccurrences(of: "in", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { throw SimpleError("Enter a time like 8am, 23:30, or 2.5h.") }
        if let seconds = parseDurationSeconds(cleaned) {
            return now.addingTimeInterval(TimeInterval(seconds))
        }
        return try parseClock(cleaned, now: now)
    }

    private static func parseKeepAwakeTarget(_ rawInput: String, now: Date = Date()) throws -> (seconds: Int, endDate: Date) {
        let cleaned = rawInput
            .lowercased()
            .replacingOccurrences(of: "until", with: " ")
            .replacingOccurrences(of: "for", with: " ")
            .replacingOccurrences(of: "today", with: " ")
            .replacingOccurrences(of: "at", with: " ")
            .replacingOccurrences(of: "in", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { throw SimpleError("Enter a duration or time like 2.5h or 8am.") }
        if let seconds = parseDurationSeconds(cleaned) {
            return (seconds, now.addingTimeInterval(TimeInterval(seconds)))
        }
        let endDate = try parseClock(cleaned, now: now)
        return (max(1, Int(endDate.timeIntervalSince(now).rounded(.up))), endDate)
    }

    private static func parseDurationSeconds(_ text: String) -> Int? {
        let pattern = #"^(\d+(?:\.\d+)?)([smhd])$"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(text[match])
        guard matched == text else { return nil }
        let numberText = matched.dropLast()
        guard let value = Double(numberText) else { return nil }
        let multiplier: Double
        switch matched.last {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        case "d": multiplier = 86400
        default: return nil
        }
        return max(1, Int((value * multiplier).rounded()))
    }

    private static func parseClock(_ text: String, now: Date) throws -> Date {
        let pattern = #"^(\d{1,2})(?::(\d{2}))?(am|pm)?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.range.location == range.location, match.range.length == range.length,
              let hourRange = Range(match.range(at: 1), in: text), var hour = Int(text[hourRange]) else {
            throw SimpleError("Enter a time like 8am, 23:30, or 2.5h.")
        }
        var minute = 0
        if match.range(at: 2).location != NSNotFound, let minuteRange = Range(match.range(at: 2), in: text), let parsedMinute = Int(text[minuteRange]) {
            minute = parsedMinute
        }
        guard minute <= 59 else { throw SimpleError("Minutes must be 00-59.") }
        if match.range(at: 3).location != NSNotFound, let suffixRange = Range(match.range(at: 3), in: text) {
            let suffix = String(text[suffixRange])
            guard (1...12).contains(hour) else { throw SimpleError("12-hour times must use 1-12.") }
            if suffix == "am" {
                hour = hour == 12 ? 0 : hour
            } else {
                hour = hour == 12 ? 12 : hour + 12
            }
        } else if hour > 23 {
            throw SimpleError("24-hour times must use 0-23.")
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var target = Calendar.current.date(from: components) else {
            throw SimpleError("Could not build scheduled time.")
        }
        if target <= now, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: target) {
            target = tomorrow
        }
        return target
    }

    private static func scheduledPowerDescription() -> String? {
        guard let info = scheduledPowerInfo() else { return nil }
        return "Scheduled \(info.action): \(format(info.target))"
    }

    private static func scheduledPowerInfo() -> ScheduledPowerInfo? {
        guard let payload = readPlist(powerPlistURL) else { return nil }
        let action = (payload["STMAction"] as? String)
            ?? ((payload["ProgramArguments"] as? [String])?.last)
            ?? "unknown"
        if let raw = payload["STMTargetDate"] as? String,
           let target = ISO8601DateFormatter().date(from: raw) {
            return ScheduledPowerInfo(action: action, target: target)
        }
        guard let interval = payload["StartCalendarInterval"] as? [String: Int] else { return nil }
        var components = DateComponents()
        components.year = interval["Year"]
        components.month = interval["Month"]
        components.day = interval["Day"]
        components.hour = interval["Hour"]
        components.minute = interval["Minute"]
        components.second = 0
        guard let target = Calendar.current.date(from: components) else { return nil }
        return ScheduledPowerInfo(action: action, target: target)
    }

    private static func keepAwakeDescription() -> String? {
        guard let info = keepAwakeInfo() else { return nil }
        if let end = info.end {
            return "Keep Awake: on until \(format(end))"
        }
        return "Keep Awake: active for \(info.seconds)s from last start."
    }

    private static func keepAwakeInfo() -> KeepAwakeInfo? {
        guard let payload = readPlist(keepAwakePlistURL),
              let args = payload["ProgramArguments"] as? [String],
              let secondsText = args.last,
              let seconds = Int(secondsText) else { return nil }
        let end = (payload["STMEndDate"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return KeepAwakeInfo(end: end, seconds: seconds)
    }

    private static func autosaveOpenSessionRepos() -> [String] {
        let repos = discoverOpenSessionRepos()
        Logger.log("git autosave discovered repos=\(repos.count)")
        return autosaveRepos(repos)
    }

    private static func autosaveRepos(_ repos: Set<String>) -> [String] {
        var lines: [String] = []
        for repo in repos.sorted() {
            if let busy = busyGitState(repo) {
                let line = "Skipped \(repo): git operation in progress (\(busy))."
                Logger.log("git autosave \(line)")
                lines.append(line)
                continue
            }
            guard gitIsDirty(repo) else { continue }
            _ = runProcess("/usr/bin/git", ["-C", repo, "add", "-A"])
            let staged = runProcess("/usr/bin/git", ["-C", repo, "diff", "--cached", "--quiet"])
            guard staged.status != 0 else { continue }
            let commit = runProcess("/usr/bin/git", ["-C", repo, "commit", "-m", "chore: auto-save before scheduled shutdown", "-m", "Created by STM Desktop Listener before a scheduled shutdown."])
            if commit.status == 0 {
                let line = "Committed \(repo)."
                Logger.log("git autosave \(line)")
                lines.append(line)
            } else {
                let line = "Failed \(repo): \(commit.combinedOutput)"
                Logger.log("git autosave \(line)")
                lines.append(line)
            }
        }
        return lines
    }

    private static func discoverOpenSessionRepos() -> Set<String> {
        let rows = processRows()
        var children: [Int: [Int]] = [:]
        for row in rows {
            children[row.ppid, default: []].append(row.pid)
        }
        var sessionPids = Set<Int>()
        var stack = rows.filter { row in
            let haystack = "\(row.command) \(row.arguments)".lowercased()
            return haystack.contains("cmux") || haystack.contains("omp")
        }.map(\.pid)
        while let pid = stack.popLast() {
            guard !sessionPids.contains(pid) else { continue }
            sessionPids.insert(pid)
            stack.append(contentsOf: children[pid] ?? [])
        }
        var repos = Set<String>()
        for pid in sessionPids {
            guard let cwd = cwdForProcess(pid), let repo = gitTopLevel(cwd) else { continue }
            repos.insert(URL(fileURLWithPath: repo).standardizedFileURL.path)
        }
        return repos
    }

    private static func processRows() -> [ProcessRow] {
        let output = runProcess("/bin/ps", ["-axo", "pid=,ppid=,comm=,args="]).combinedOutput
        return output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { return nil }
            return ProcessRow(pid: pid, ppid: ppid, command: URL(fileURLWithPath: String(parts[2])).lastPathComponent, arguments: parts.count > 3 ? String(parts[3]) : String(parts[2]))
        }
    }

    private static func cwdForProcess(_ pid: Int) -> String? {
        let output = runProcess("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]).combinedOutput
        return output.split(separator: "\n").first { $0.hasPrefix("n/") }.map { String($0.dropFirst()) }
    }

    private static func gitTopLevel(_ path: String) -> String? {
        let result = runProcess("/usr/bin/git", ["-C", path, "rev-parse", "--show-toplevel"])
        guard result.status == 0 else { return nil }
        let value = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func gitDirectory(_ repo: String) -> String? {
        let result = runProcess("/usr/bin/git", ["-C", repo, "rev-parse", "--git-dir"])
        guard result.status == 0 else { return nil }
        let raw = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") { return raw }
        return URL(fileURLWithPath: repo).appendingPathComponent(raw).path
    }

    private static func busyGitState(_ repo: String) -> String? {
        guard let gitDir = gitDirectory(repo) else { return "unresolved git directory" }
        for name in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "REBASE_HEAD", "rebase-apply", "rebase-merge"] {
            if FileManager.default.fileExists(atPath: URL(fileURLWithPath: gitDir).appendingPathComponent(name).path) {
                return name
            }
        }
        return nil
    }

    private static func gitIsDirty(_ repo: String) -> Bool {
        let result = runProcess("/usr/bin/git", ["-C", repo, "status", "--porcelain=v1", "-uall"])
        return !result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func writePlist(_ payload: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private static func readPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return payload
    }
    
    private static func clearCompletedScheduledPower() {
        guard FileManager.default.fileExists(atPath: powerPlistURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: powerPlistURL)
            Logger.log("power schedule completed and removed")
        } catch {
            Logger.log("power schedule completed but cleanup failed error=\(error.localizedDescription)")
        }
    }
    private static func notifyWithAppleScript(title: String, body: String) {
        let script = "display notification \(appleScriptString(body)) with title \(appleScriptString(title))"
        _ = runProcess("/usr/bin/osascript", ["-e", script])
    }

    private static func appleScriptString(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }


    private static func launchctl(_ arguments: [String], allowAlreadyUnloaded: Bool) throws {
        let result = runProcess("/bin/launchctl", arguments)
        if result.status == 0 { return }
        if allowAlreadyUnloaded,
           result.combinedOutput.contains("Input/output error")
            || result.combinedOutput.contains("No such process")
            || result.combinedOutput.contains("Could not find service") {
            return
        }
        throw SimpleError(result.combinedOutput.isEmpty ? "launchctl failed with exit \(result.status)." : result.combinedOutput)
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ProcessResult(status: process.terminationStatus, combinedOutput: text)
        } catch {
            return ProcessResult(status: 127, combinedOutput: error.localizedDescription)
        }
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatRemaining(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 {
            return "ending now"
        }
        return "\(formatDuration(remaining)) remaining"
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}

private struct ProcessResult {
    let status: Int32
    let combinedOutput: String
}
