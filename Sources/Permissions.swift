import Cocoa
import AVFoundation
import ApplicationServices
import CoreGraphics

enum PermissionCenter {
    static func microphoneStatusText() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Ready"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    static func requestMicrophone(_ completion: @escaping () -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { completion() }
        }
    }

    static func screenStatusText() -> String {
        CGPreflightScreenCaptureAccess() ? "Ready" : "Needs grant"
    }

    static func hasScreenAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreen() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func ensureScreenAccess() -> Bool {
        if hasScreenAccess() {
            return true
        }
        _ = requestScreen()
        return hasScreenAccess()
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func accessibilityStatusText() -> String {
        AXIsProcessTrusted() ? "Ready" : "Needs grant or restart"
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openAccessibilitySettings()
        }
        return trusted
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func resetAccessibilityEntry() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", "com.seotimemachines.stm-desktop-listener"]
        do {
            try process.run()
            process.waitUntilExit()
            Logger.log("accessibility reset status=\(process.terminationStatus)")
        } catch {
            Logger.log("accessibility reset failed: \(error.localizedDescription)")
        }
        openAccessibilitySettings()
    }

    static func resetScreenRecordingEntry() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", "com.seotimemachines.stm-desktop-listener"]
        do {
            try process.run()
            process.waitUntilExit()
            Logger.log("screen recording reset status=\(process.terminationStatus)")
        } catch {
            Logger.log("screen recording reset failed: \(error.localizedDescription)")
        }
        openScreenRecordingSettings()
    }
}
