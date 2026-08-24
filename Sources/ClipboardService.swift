import Cocoa
import ApplicationServices

final class ClipboardService {
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copyPNGData(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func pasteIfAllowed(force: Bool = false) {
        let enabled = force || ConfigStore.bool("autopasteEnabled", default: true)
        let trusted = AXIsProcessTrusted()
        let frontApp = NSWorkspace.shared.frontmostApplication
        Logger.log("autopaste state enabled=\(enabled) trusted=\(trusted) frontmost=\(frontApp?.localizedName ?? "unknown") bundle=\(frontApp?.bundleIdentifier ?? "unknown")")
        guard enabled, trusted else {
            if !trusted {
                _ = PermissionCenter.requestAccessibility()
            }
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        Logger.log("autopaste attempted")
    }
}
