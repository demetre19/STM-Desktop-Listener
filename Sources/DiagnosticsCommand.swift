import Cocoa
import Foundation

enum DiagnosticsCommand {
    static func runIfNeeded() -> Bool {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.contains("--diagnostics")
                || args.contains("--self-test-screenshot")
                || args.contains("--parakeet-transcribe")
                || args.contains("--voice-intent-self-test")
                || args.contains("--mouse-jiggle-once")
                || args.contains("--request-screen-permission")
                || args.contains("--open-screen-settings") else {
            return false
        }

        do {
            let payload: [String: Any]
            if args.contains("--parakeet-transcribe") {
                payload = try parakeetSelfTest(args: args)
            } else if args.contains("--voice-intent-self-test") {
                payload = try voiceIntentSelfTest()
            } else if args.contains("--self-test-screenshot") {
                payload = try screenshotSelfTest()
            } else if args.contains("--mouse-jiggle-once") {
                payload = mouseJiggleSelfTest()
            } else if args.contains("--request-screen-permission") {
                payload = requestScreenPermission(openSettings: args.contains("--open-screen-settings"))
            } else if args.contains("--open-screen-settings") {
                PermissionCenter.openScreenRecordingSettings()
                payload = diagnostics()
            } else {
                payload = diagnostics()
            }
            try writeJSON(["ok": true, "payload": payload])
            return true
        } catch {
            let payload = diagnostics()
            try? writeJSON([
                "ok": false,
                "error": error.localizedDescription,
                "payload": payload
            ])
            return true
        }
    }

    private static func diagnostics() -> [String: Any] {
        [
            "app": [
                "name": AppPaths.appName,
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                "executable": Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "",
                "minimumSystemVersion": Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? ""
            ],
            "paths": [
                "config": AppPaths.configURL.path,
                "logs": AppPaths.logURL.path,
                "payloads": AppPaths.payloadDirectory.path
            ],
            "permissions": [
                "microphone": PermissionCenter.microphoneStatusText(),
                "screenRecording": PermissionCenter.screenStatusText(),
                "accessibility": PermissionCenter.accessibilityStatusText()
            ],
            "dictation": [
                "transcriptionEngine": DictationLocalConfiguration.load().engine.rawValue,
                "parakeetStatus": ParakeetModelManager.statusText(),
                "voiceCommandsEnabled": DictationLocalConfiguration.load().voiceCommandsEnabled
            ] as [String: Any],
            "features": FeatureID.allCases.map { feature -> [String: Any] in
                [
                    "id": feature.rawValue,
                    "title": feature.title,
                    "enabled": ConfigStore.featureEnabled(feature),
                    "hotkey": ConfigStore.shortcut(for: feature)?.label ?? ""
                ]
            }
        ]
    }

    private static func requestScreenPermission(openSettings: Bool) -> [String: Any] {
        let before = CGPreflightScreenCaptureAccess()
        let requestResult = PermissionCenter.requestScreen()
        let after = CGPreflightScreenCaptureAccess()
        if openSettings || !after {
            PermissionCenter.openScreenRecordingSettings()
        }
        var payload = diagnostics()
        payload["screenRecordingRequest"] = [
            "before": before,
            "requestResult": requestResult,
            "after": after,
            "openedSettings": openSettings || !after
        ] as [String: Any]
        return payload
    }

    private static func parakeetSelfTest(args: [String]) throws -> [String: Any] {
        guard let waveIndex = args.firstIndex(of: "--parakeet-transcribe"),
              args.indices.contains(waveIndex + 1) else {
            throw SimpleError("Pass a WAV path after --parakeet-transcribe.")
        }
        let waveURL = URL(fileURLWithPath: args[waveIndex + 1])
        let modelURL: URL
        if let modelIndex = args.firstIndex(of: "--parakeet-model"),
           args.indices.contains(modelIndex + 1) {
            modelURL = URL(fileURLWithPath: args[modelIndex + 1], isDirectory: true)
        } else if let configuredURL = ParakeetModelManager.resolvedModelURL() {
            modelURL = configuredURL
        } else if ParakeetModelManager.isValidModel(at: ParakeetModelManager.orcaModelURL) {
            modelURL = ParakeetModelManager.orcaModelURL
        } else {
            throw SimpleError("No valid Parakeet model is configured.")
        }
        guard ParakeetModelManager.isValidModel(at: modelURL) else {
            throw SimpleError("The supplied Parakeet model folder is incomplete.")
        }
        let started = Date()
        let text = try ParakeetTranscriber.transcribe(waveURL: waveURL, modelURL: modelURL)
        return [
            "characters": text.count,
            "elapsedMilliseconds": Int(Date().timeIntervalSince(started) * 1000),
            "model": modelURL.path,
            "text": text
        ]
    }

    private static func voiceIntentSelfTest() throws -> [String: Any] {
        let expected = CommandShortcutDefinition(id: "self-test", title: "Open Dashboard", command: "true", shortcut: nil)
        let commands = [expected]
        guard VoiceCommandIntentRouter.matchingCommand(for: "Command open dashboard.", commands: commands)?.id == expected.id,
              VoiceCommandIntentRouter.matchingCommand(for: "run command OPEN DASHBOARD", commands: commands)?.id == expected.id,
              VoiceCommandIntentRouter.matchingCommand(for: "command open", commands: commands) == nil,
              !VoiceCommandIntentRouter.isCommandPhrase("please open dashboard") else {
            throw SimpleError("Voice command intent matching failed.")
        }
        return [
            "exactMatch": true,
            "nearMatchRejected": true,
            "rawShellExecution": false
        ]
    }

    private static func screenshotSelfTest() throws -> [String: Any] {
        guard CGPreflightScreenCaptureAccess() else {
            throw SimpleError("Screen Recording permission is not granted for STM Desktop Listener.")
        }
        guard let screen = NSScreen.main else {
            throw SimpleError("No main screen available")
        }

        let width = min(CGFloat(160), screen.frame.width)
        let height = min(CGFloat(100), screen.frame.height)
        let rect = CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.midY - height / 2,
            width: width,
            height: height
        )
        let data = try CaptureService().capturePNG(rect: rect)
        let record = try PayloadStore.store(data: data, filename: "screenshot-self-test.png", contentType: "image/png", kind: "screenshot-self-test")
        let chunk = try PayloadStore.readChunk(token: record.token, offset: 0, limit: 393216)
        return [
            "screen": [
                "frame": "\(Int(screen.frame.width))x\(Int(screen.frame.height))",
                "scale": screen.backingScaleFactor
            ] as [String: Any],
            "rect": [
                "x": rect.origin.x,
                "y": rect.origin.y,
                "width": rect.width,
                "height": rect.height
            ],
            "payload": [
                "token": record.token,
                "filename": record.filename,
                "contentType": record.contentType,
                "kind": record.kind,
                "bytes": data.count,
                "chunkDone": chunk["done"] as? Bool ?? false,
                "chunkTotal": chunk["total"] as? Int ?? 0
            ] as [String: Any]
        ]
    }

    private static func mouseJiggleSelfTest() -> [String: Any] {
        let before = CGEvent(source: nil)?.location ?? .zero
        let trusted = AXIsProcessTrusted()
        let moved = MouseJigglerController.moveCursorOnce()
        Thread.sleep(forTimeInterval: 0.2)
        let after = CGEvent(source: nil)?.location ?? .zero
        return [
            "accessibilityTrusted": trusted,
            "moved": moved,
            "before": ["x": before.x, "y": before.y],
            "after": ["x": after.x, "y": after.y],
            "delta": ["x": after.x - before.x, "y": after.y - before.y]
        ] as [String: Any]
    }

    private static func writeJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
