import Cocoa
import Carbon

enum FeatureID: String, CaseIterable, Codable {
    case screenshot
    case ocr
    case dictation
    case dictationPolish
    case textTransformers
    case textCapitalCase
    case textLowerCase
    case textUpperCase
    case textSentenceCase
    case textSlugify
    case colorPicker
    case pixelMeasurement
    case imageOptimizer
    case copyFinderPath
    case newFile
    case mouseJiggler
    case commandShortcuts

    var title: String {
        switch self {
        case .screenshot: return "Screenshot Tool"
        case .ocr: return "OCR Text Sniper"
        case .dictation: return "Voice Dictation"
        case .dictationPolish: return "Voice Dictation (Alternate)"
        case .textTransformers: return "Text Transformers"
        case .textCapitalCase: return "Capital Case"
        case .textLowerCase: return "lower case"
        case .textUpperCase: return "UPPER CASE"
        case .textSentenceCase: return "Sentence case"
        case .textSlugify: return "Slugify"
        case .colorPicker: return "Color Picker"
        case .pixelMeasurement: return "Pixel Measurement"
        case .imageOptimizer: return "Image Optimizer"
        case .copyFinderPath: return "Copy Finder Path"
        case .newFile: return "New File"
        case .mouseJiggler: return "Mouse Jiggler"
        case .commandShortcuts: return "Command Shortcuts"
        }
    }

    var defaultEnabled: Bool {
        if self == .commandShortcuts || self == .mouseJiggler {
            return false
        }
        return true
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .screenshot:
            return Shortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey | shiftKey), cgModifiers: [.maskCommand, .maskShift], label: "Cmd+Shift+S")
        case .ocr:
            return Shortcut(keyCode: UInt32(kVK_ANSI_O), carbonModifiers: UInt32(controlKey | optionKey), cgModifiers: [.maskControl, .maskAlternate], label: "Ctrl+Alt+O")
        case .dictation:
            return Shortcut(keyCode: UInt32(kVK_Home), carbonModifiers: 0, cgModifiers: [], label: "Home")
        case .dictationPolish:
            return Shortcut(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(controlKey | optionKey), cgModifiers: [.maskControl, .maskAlternate], label: "Ctrl+Alt+D")
        case .textTransformers:
            return nil
        case .textCapitalCase:
            return Shortcut(keyCode: UInt32(kVK_UpArrow), carbonModifiers: UInt32(controlKey | optionKey | cmdKey), cgModifiers: [.maskControl, .maskAlternate, .maskCommand], label: "Ctrl+Alt+Cmd+Arrow Up")
        case .textLowerCase:
            return Shortcut(keyCode: UInt32(kVK_DownArrow), carbonModifiers: UInt32(controlKey | optionKey | cmdKey), cgModifiers: [.maskControl, .maskAlternate, .maskCommand], label: "Ctrl+Alt+Cmd+Arrow Down")
        case .textUpperCase:
            return Shortcut(keyCode: UInt32(kVK_UpArrow), carbonModifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), cgModifiers: [.maskControl, .maskAlternate, .maskCommand, .maskShift], label: "Ctrl+Alt+Cmd+Shift+Arrow Up")
        case .textSentenceCase:
            return Shortcut(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(controlKey | optionKey | cmdKey), cgModifiers: [.maskControl, .maskAlternate, .maskCommand], label: "Ctrl+Alt+Cmd+Arrow Left")
        case .textSlugify:
            return Shortcut(keyCode: UInt32(kVK_RightArrow), carbonModifiers: UInt32(controlKey | optionKey | cmdKey), cgModifiers: [.maskControl, .maskAlternate, .maskCommand], label: "Ctrl+Alt+Cmd+Arrow Right")
        case .colorPicker:
            return Shortcut(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(controlKey | optionKey), cgModifiers: [.maskControl, .maskAlternate], label: "Ctrl+Alt+C")
        case .pixelMeasurement:
            return Shortcut(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(controlKey | optionKey), cgModifiers: [.maskControl, .maskAlternate], label: "Ctrl+Alt+P")
        case .imageOptimizer:
            return Shortcut(keyCode: UInt32(kVK_ANSI_I), carbonModifiers: UInt32(controlKey | optionKey), cgModifiers: [.maskControl, .maskAlternate], label: "Ctrl+Alt+I")
        case .copyFinderPath:
            return Shortcut(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(cmdKey | optionKey), cgModifiers: [.maskCommand, .maskAlternate], label: "Cmd+Alt+C")
        case .newFile:
            return Shortcut(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(cmdKey | optionKey), cgModifiers: [.maskCommand, .maskAlternate], label: "Cmd+Alt+N")
        case .commandShortcuts, .mouseJiggler:
            return nil
        }
    }

    var chromeDefaultShortcut: Shortcut? {
        switch self {
        case .screenshot:
            return Shortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey | shiftKey), cgModifiers: [.maskCommand, .maskShift], label: "Cmd+Shift+S")
        case .colorPicker:
            return Shortcut(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(cmdKey | shiftKey), cgModifiers: [.maskCommand, .maskShift], label: "Cmd+Shift+P")
        case .textTransformers, .textCapitalCase, .textLowerCase, .textUpperCase, .textSentenceCase, .textSlugify, .ocr, .dictation, .dictationPolish, .pixelMeasurement, .imageOptimizer, .copyFinderPath, .newFile, .commandShortcuts, .mouseJiggler:
            return nil
        }
    }

    var requiresFinderFrontmostForHotkey: Bool {
        self == .copyFinderPath || self == .newFile
    }

    var isTextTransformerChild: Bool {
        switch self {
        case .textCapitalCase, .textLowerCase, .textUpperCase, .textSentenceCase, .textSlugify:
            return true
        default:
            return false
        }
    }

    static let textTransformerChildren: [FeatureID] = [
        .textCapitalCase,
        .textLowerCase,
        .textUpperCase,
        .textSentenceCase,
        .textSlugify
    ]
}

struct TranscriptionModel {
    let id: String
    let label: String
    let menuTitle: String
    let quotaLabel: String
    let neuronRate: Double

    static let all: [TranscriptionModel] = [
        TranscriptionModel(id: "turbo", label: "Whisper Turbo", menuTitle: "Whisper Turbo", quotaLabel: "Turbo", neuronRate: 46.36),
        TranscriptionModel(id: "whisper", label: "Whisper", menuTitle: "Whisper", quotaLabel: "Whisper", neuronRate: 40.91),
        TranscriptionModel(id: "nova3", label: "Nova-3", menuTitle: "Nova-3", quotaLabel: "Nova-3", neuronRate: 472.73)
    ]

    static let `default` = all[0]

    static func byID(_ id: String?) -> TranscriptionModel {
        guard let id = id else { return .default }
        return all.first { $0.id == id } ?? .default
    }

    static func load() -> TranscriptionModel {
        byID(ConfigStore.string("transcriptionModel"))
    }
}

struct CommandShortcutDefinition: Codable, Equatable {
    var id: String
    var title: String
    var command: String
    var shortcut: String?

    static func create() -> CommandShortcutDefinition {
        CommandShortcutDefinition(
            id: UUID().uuidString,
            title: "Command",
            command: "",
            shortcut: nil
        )
    }

    var shortcutValue: Shortcut? {
        guard let shortcut = shortcut else { return nil }
        return Shortcut(serialized: shortcut)
    }

    var shortcutLabel: String {
        shortcutValue?.label ?? "No hotkey"
    }
}

struct SimpleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
