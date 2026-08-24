import Cocoa
import Carbon

struct Shortcut {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let cgModifiers: CGEventFlags
    let label: String

    init(keyCode: UInt32, carbonModifiers: UInt32, cgModifiers: CGEventFlags, label: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.cgModifiers = Shortcut.relevantCGFlags(cgModifiers)
        self.label = label
    }

    init?(event: NSEvent, allowPlainKey: Bool = false) {
        let flags = Shortcut.cgFlags(from: event.modifierFlags)
        guard allowPlainKey || flags.contains(.maskCommand) || flags.contains(.maskControl) else {
            return nil
        }
        self.init(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: Shortcut.carbonModifiers(from: flags),
            cgModifiers: flags,
            label: Shortcut.label(keyCode: event.keyCode, flags: flags)
        )
    }

    init?(serialized: String) {
        let parts = serialized.split(separator: "|", maxSplits: 3).map(String.init)
        guard parts.count == 4,
              let keyCode = UInt32(parts[0]),
              let carbon = UInt32(parts[1]),
              let cgRaw = UInt64(parts[2]),
              !parts[3].isEmpty else {
            return nil
        }
        let normalizedFlags = Shortcut.relevantCGFlags(CGEventFlags(rawValue: cgRaw))
        self.init(keyCode: keyCode, carbonModifiers: carbon, cgModifiers: normalizedFlags, label: Shortcut.label(keyCode: UInt16(keyCode), flags: normalizedFlags))
    }

    var serialized: String {
        "\(keyCode)|\(carbonModifiers)|\(cgModifiers.rawValue)|\(label)"
    }

    static func relevantCGFlags(_ flags: CGEventFlags) -> CGEventFlags {
        let mask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        return flags.intersection(mask)
    }

    static func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
        if flags.contains(.maskControl) { result |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
        if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
        return result
    }

    static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        return result
    }

    static func label(keyCode: UInt16, flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("Ctrl") }
        if flags.contains(.maskAlternate) { parts.append("Alt") }
        if flags.contains(.maskCommand) { parts.append("Cmd") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        parts.append(keyLabel(keyCode))
        return parts.joined(separator: "+")
    }

    static func keyLabel(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_KeypadDecimal: return "Keypad ."
        case kVK_ANSI_KeypadMultiply: return "Keypad *"
        case kVK_ANSI_KeypadPlus: return "Keypad +"
        case kVK_ANSI_KeypadClear: return "Keypad Clear"
        case kVK_ANSI_KeypadDivide: return "Keypad /"
        case kVK_ANSI_KeypadEnter: return "Keypad Enter"
        case kVK_ANSI_KeypadMinus: return "Keypad -"
        case kVK_ANSI_KeypadEquals: return "Keypad ="
        case kVK_ANSI_Keypad0: return "Keypad 0"
        case kVK_ANSI_Keypad1: return "Keypad 1"
        case kVK_ANSI_Keypad2: return "Keypad 2"
        case kVK_ANSI_Keypad3: return "Keypad 3"
        case kVK_ANSI_Keypad4: return "Keypad 4"
        case kVK_ANSI_Keypad5: return "Keypad 5"
        case kVK_ANSI_Keypad6: return "Keypad 6"
        case kVK_ANSI_Keypad7: return "Keypad 7"
        case kVK_ANSI_Keypad8: return "Keypad 8"
        case kVK_ANSI_Keypad9: return "Keypad 9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Backspace"
        case kVK_ForwardDelete: return "Delete"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_UpArrow: return "Arrow Up"
        case kVK_DownArrow: return "Arrow Down"
        case kVK_LeftArrow: return "Arrow Left"
        case kVK_RightArrow: return "Arrow Right"
        case kVK_Help: return "Help"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default: return "Key \(keyCode)"
        }
    }
}
