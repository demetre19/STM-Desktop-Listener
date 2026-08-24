import Foundation

enum AppPaths {
    static let appName = "STM Desktop Listener"

    static var applicationSupport: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL {
        applicationSupport.appendingPathComponent("config.json")
    }

    static var payloadDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("Payloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var logURL: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }
}

enum ConfigStore {
    private static let lastSuccessfulUpdateCheckKey = "updates.lastSuccessfulCheck"
    private static let dismissedUpdateVersionKey = "updates.dismissedVersion"

    private static func read() -> [String: Any] {
        guard let data = try? Data(contentsOf: AppPaths.configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func write(_ json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: AppPaths.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: AppPaths.configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.configURL.path)
    }

    static func string(_ key: String) -> String? {
        guard let value = read()[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        if let value = read()[key] as? Bool { return value }
        return defaultValue
    }

    static func int(_ key: String, default defaultValue: Int) -> Int {
        if let value = read()[key] as? Int { return value }
        if let value = read()[key] as? NSNumber { return value.intValue }
        return defaultValue
    }

    static func double(_ key: String, default defaultValue: Double) -> Double {
        if let value = read()[key] as? Double { return value }
        if let value = read()[key] as? NSNumber { return value.doubleValue }
        return defaultValue
    }

    static func stringArray(_ key: String) -> [String] {
        guard let value = read()[key] else { return [] }
        if let array = value as? [String] {
            return cleanStringArray(array)
        }
        if let array = value as? [Any] {
            return cleanStringArray(array.compactMap { $0 as? String })
        }
        if let string = value as? String {
            let separators = CharacterSet(charactersIn: ",\n")
            return cleanStringArray(string.components(separatedBy: separators))
        }
        return []
    }

    private static func cleanStringArray(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { return nil }
            seen.insert(cleaned)
            return cleaned
        }
    }

    static func set(_ value: Any, for key: String) throws {
        var json = read()
        json[key] = value
        try write(json)
    }

    static func lastSuccessfulUpdateCheck() -> Date? {
        let timestamp = double(lastSuccessfulUpdateCheckKey, default: .nan)
        guard timestamp.isFinite, timestamp >= 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func recordSuccessfulUpdateCheck(at date: Date) throws {
        let timestamp = date.timeIntervalSince1970
        guard timestamp.isFinite, timestamp >= 0 else { return }
        try set(timestamp, for: lastSuccessfulUpdateCheckKey)
    }

    static func dismissedUpdateVersion() -> String? {
        string(dismissedUpdateVersionKey)
    }

    static func setDismissedUpdateVersion(_ version: String?) throws {
        var json = read()
        if let version {
            let cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                json.removeValue(forKey: dismissedUpdateVersionKey)
            } else {
                json[dismissedUpdateVersionKey] = cleaned
            }
        } else {
            json.removeValue(forKey: dismissedUpdateVersionKey)
        }
        try write(json)
    }

    static func featureEnabled(_ feature: FeatureID) -> Bool {
        bool("feature.\(feature.rawValue).enabled", default: feature.defaultEnabled)
    }

    static func setFeatureEnabled(_ enabled: Bool, feature: FeatureID) throws {
        try set(enabled, for: "feature.\(feature.rawValue).enabled")
    }

    static func setShortcut(_ shortcut: Shortcut?, feature: FeatureID) throws {
        var json = read()
        let key = "feature.\(feature.rawValue).shortcut"
        if let shortcut = shortcut {
            json[key] = shortcut.serialized
        } else {
            json[key] = "__none__"
        }
        try write(json)
    }

    static func resetShortcut(feature: FeatureID) throws {
        var json = read()
        json.removeValue(forKey: "feature.\(feature.rawValue).shortcut")
        try write(json)
    }

    static func shortcut(for feature: FeatureID) -> Shortcut? {
        guard let saved = string("feature.\(feature.rawValue).shortcut") else {
            return feature.defaultShortcut
        }
        if saved == "__none__" {
            return feature == .dictation ? feature.defaultShortcut : nil
        }
        return Shortcut(serialized: saved) ?? feature.defaultShortcut
    }

    static func commandShortcuts() -> [CommandShortcutDefinition] {
        let json = read()
        if let rawItems = json["commandShortcuts"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: rawItems),
           let items = try? JSONDecoder().decode([CommandShortcutDefinition].self, from: data) {
            return items
        }

        if let legacyCommand = json["commandShortcut.command"] as? String, !legacyCommand.isEmpty {
            return [
                CommandShortcutDefinition(
                    id: UUID().uuidString,
                    title: "Command",
                    command: legacyCommand,
                    shortcut: json["feature.commandShortcuts.shortcut"] as? String
                )
            ]
        }
        return []
    }

    static func setCommandShortcuts(_ items: [CommandShortcutDefinition]) throws {
        var json = read()
        let data = try JSONEncoder().encode(items)
        let object = try JSONSerialization.jsonObject(with: data)
        json["commandShortcuts"] = object
        json.removeValue(forKey: "commandShortcut.command")
        try write(json)
    }

    static func updateCommandShortcut(_ item: CommandShortcutDefinition) throws {
        var items = commandShortcuts()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        try setCommandShortcuts(items)
    }

    static func deleteCommandShortcut(id: String) throws {
        let items = commandShortcuts().filter { $0.id != id }
        try setCommandShortcuts(items)
    }
}
