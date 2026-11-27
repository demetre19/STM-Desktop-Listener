import Foundation

// Minimal type stubs let the platform-independent dictation formatting and learning tests
// compile on Linux. The macOS app uses the real definitions in Models.swift.

enum FeatureID: String {
    case dictation
    var defaultEnabled: Bool { true }
    var defaultShortcut: Shortcut? { nil }
}

struct Shortcut {
    var serialized: String
    init?(serialized: String) { self.serialized = serialized }
}

struct CommandShortcutDefinition: Codable {
    var id: String
    var title: String
    var command: String
    var shortcut: String?
}
