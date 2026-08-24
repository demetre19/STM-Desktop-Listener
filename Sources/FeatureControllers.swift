import Cocoa
import Carbon

final class FeatureRunner {
    let clipboard = ClipboardService()
    let capture = CaptureService()
    let ocr = OCRService()
    let bridge = BrowserBridge()
    let selection = SelectionOverlayController()
    let measurement = MeasurementOverlayController()
    let colorPicker = ColorPickerOverlayController()
    let visualFlash = VisualFlashController()
    let toast = ToastController()
    lazy var newFile = NewFileController(toast: toast)
    lazy var dictation: DictationController = {
        let controller = DictationController(clipboard: clipboard)
        controller.onVoiceCommand = { [weak self] transcript in
            self?.handleVoiceCommand(transcript) ?? false
        }
        return controller
    }()
    let mouseJiggler = MouseJigglerController()
    var onError: ((String, String) -> Void)?
    var onNotice: ((String, String) -> Void)?
    private var screenshotInFlight = false
    private var screenshotEditor: ScreenshotEditorWindowController?

    var captureOverlayActive: Bool {
        screenshotInFlight || selection.isActive
    }

    func featureStateChanged() {
        mouseJiggler.restoreIfNeeded(featureEnabled: ConfigStore.featureEnabled(.mouseJiggler))
    }


    func run(_ feature: FeatureID) {
        if feature == .textTransformers {
            return
        }
        if feature.isTextTransformerChild && !ConfigStore.featureEnabled(.textTransformers) {
            return
        }
        guard ConfigStore.featureEnabled(feature) else {
            onNotice?("Feature disabled", "\(feature.title) is disabled.")
            return
        }

        switch feature {
        case .screenshot: runScreenshot()
        case .ocr: runOCR()
        case .dictation: dictation.toggle()
        case .dictationPolish: dictation.toggle()
        case .textTransformers: return
        case .textCapitalCase: runTextTransformer(mode: "capitalCase")
        case .textLowerCase: runTextTransformer(mode: "lowerCase")
        case .textUpperCase: runTextTransformer(mode: "upperCase")
        case .textSentenceCase: runTextTransformer(mode: "sentenceCase")
        case .textSlugify: runTextTransformer(mode: "slugify")
        case .colorPicker: runColorPicker()
        case .pixelMeasurement: runPixelMeasurement()
        case .imageOptimizer: runImageOptimizer()
        case .copyFinderPath: runCopyFinderPath()
        case .newFile: runNewFile()
        case .mouseJiggler: return
        case .commandShortcuts: return
        }
    }

    func runTextTransformer(mode: String) {
        let text = selectedTextViaAccessibility() ?? selectedTextViaCopy() ?? clipboard.readText() ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let transformed = transform(text, mode: mode)
        clipboard.copyText(transformed)
        clipboard.pasteIfAllowed()
    }

    private func runScreenshot() {
        if selection.isActive {
            Logger.log("screenshot ignored because selection is already active")
            return
        }
        guard !screenshotInFlight else {
            Logger.log("screenshot ignored because capture is already active")
            return
        }
        guard PermissionCenter.ensureScreenAccess() else {
            onNotice?("Screen permission needed", "Grant Screen Recording permission, then try again.")
            return
        }
        screenshotInFlight = true
        if let rect = measurement.captureRect {
            captureScreenshot(rect: rect, clearMeasurementAfter: true)
            return
        }

        do {
            let started = Date()
            let snapshots = try capture.captureVisibleSnapshotsForScreens(assumePermissionGranted: true)
            let snapshotMs = Int(Date().timeIntervalSince(started) * 1000)
            Logger.log("screenshot selection opening frozen=true snapshotMs=\(snapshotMs)")
            selection.start(
                label: "Select screenshot region",
                snapshots: snapshots,
                holdAfterSelection: true
            ) { [weak self] rect in
                guard let self else { return }
                guard let rect else {
                    self.screenshotInFlight = false
                    Logger.log("screenshot selection cancelled")
                    return
                }
                self.captureScreenshot(rect: rect, frozenSnapshots: snapshots, clearMeasurementAfter: false)
            }
        } catch {
            screenshotInFlight = false
            onError?("Screenshot failed", error.localizedDescription)
        }
    }

    private func captureScreenshot(
        rect: CGRect,
        frozenSnapshots: [ScreenSnapshot]? = nil,
        clearMeasurementAfter: Bool
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let started = Date()
                let image: CGImage
                if let frozenSnapshots {
                    image = try self.capture.cropImage(from: frozenSnapshots, rect: rect)
                } else {
                    image = try self.capture.captureImage(rect: rect, assumePermissionGranted: true)
                }
                let captureMs = Int(Date().timeIntervalSince(started) * 1000)
                DispatchQueue.main.async {
                    Logger.log("screenshot native editor open pixels=\(image.width)x\(image.height) frozen=\(frozenSnapshots != nil) measurement=\(clearMeasurementAfter) captureMs=\(captureMs)")
                    self.openScreenshotEditor(image: image) {
                        self.selection.dismissHeldOverlay()
                        self.screenshotInFlight = false
                    }
                    if clearMeasurementAfter {
                        self.measurement.clear()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.selection.dismissHeldOverlay()
                    self.screenshotInFlight = false
                    self.onError?("Screenshot failed", error.localizedDescription)
                }
            }
        }
    }


    private func openScreenshotEditor(image: CGImage, onPresented: @escaping () -> Void) {
        screenshotEditor?.close()
        let editor = ScreenshotEditorWindowController(image: image)
        editor.onClose = { [weak self, weak editor] in
            guard let self, let editor, self.screenshotEditor === editor else {
                return
            }
            self.screenshotEditor = nil
        }
        screenshotEditor = editor
        editor.present(onReady: onPresented)
    }

    private func runOCR() {
        guard PermissionCenter.ensureScreenAccess(), PermissionCenter.hasScreenAccess() else {
            onNotice?("Screen permission needed", "Grant Screen Recording permission, then try again.")
            return
        }
        selection.start(label: "Select OCR region") { [weak self] rect in
            guard let self = self, let rect = rect else { return }
            self.visualFlash.flash(rect: rect)
            SoundEffects.shared.playShutter()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let captureStart = Date()
                    let image = try self.capture.captureImage(rect: rect)
                    let captureMs = Int(Date().timeIntervalSince(captureStart) * 1000)
                    let ocrStart = Date()
                    let text = try self.ocr.recognizeText(in: image)
                    let ocrMs = Int(Date().timeIntervalSince(ocrStart) * 1000)
                    Logger.log("ocr flow captureMs=\(captureMs) recognizeMs=\(ocrMs) rect=\(rect)")
                    DispatchQueue.main.async {
                        guard !text.isEmpty else {
                            self.onNotice?("No text found", "OCR did not find text in that region.")
                            return
                        }
                        self.clipboard.copyText(text)
                        self.toast.show(message: "Copied", duration: 0.3, placement: .center)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onError?("OCR failed", error.localizedDescription)
                    }
                }
            }
        }
    }

    private func runColorPicker() {
        guard PermissionCenter.ensureScreenAccess(), PermissionCenter.hasScreenAccess() else {
            onNotice?("Screen permission needed", "Grant Screen Recording permission, then try again.")
            return
        }
        colorPicker.start(previewProvider: { [weak self] point, windowID in
            self?.capture.fastColorPreview(at: point, excludingWindowNumber: windowID)
        }, onPick: { [weak self] point, windowID in
            guard let self = self else { return }
            if let preview = self.capture.fastColorPreview(at: point, excludingWindowNumber: windowID) {
                self.clipboard.copyText(preview.hex)
                Logger.log("color picked point=\(point) sourceColorSpace=\(preview.sourceColorSpace) sRGB=\(preview.hex)")
                SoundEffects.shared.playShutter()
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let color = try self.capture.sampleColor(at: point)
                    DispatchQueue.main.async {
                        self.clipboard.copyText(color)
                        SoundEffects.shared.playShutter()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onError?("Color picker failed", error.localizedDescription)
                    }
                }
            }
        })
    }

    private func runPixelMeasurement() {
        selection.start(label: "Select area to measure") { [weak self] rect in
            guard let self = self, let rect = rect else { return }
            let scale = NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
            let text = "\(Int(rect.width)) x \(Int(rect.height)) pt, \(Int(rect.width * scale)) x \(Int(rect.height * scale)) px"
            self.clipboard.copyText(text)
            self.measurement.show(rect: rect, text: text)
        }
    }

    private func runImageOptimizer() {
        do {
            let files = try selectedFinderImageFiles()
            if !files.isEmpty {
                let records = try files.map { try PayloadStore.storeFile($0, kind: "image-optimizer-file") }
                let manifest = try PayloadStore.storeManifest(records: records)
                bridge.openImageOptimizer(manifestToken: manifest.token)
                return
            }
            if let imageData = clipboardImagePNGData() {
                let record = try PayloadStore.store(data: imageData, filename: "clipboard.png", contentType: "image/png", kind: "image-optimizer-file")
                let manifest = try PayloadStore.storeManifest(records: [record])
                bridge.openImageOptimizer(manifestToken: manifest.token)
                return
            }
            onNotice?("No image found", "Select image files in Finder or copy an image first.")
        } catch {
            onError?("Image optimizer failed", error.localizedDescription)
        }
    }

    private func runCopyFinderPath() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            Logger.log("copy finder path ignored because Finder is not frontmost")
            return
        }

        do {
            let paths = try selectedFinderPaths()
            guard !paths.isEmpty else {
                Logger.log("copy finder path found no paths")
                return
            }
            clipboard.copyText(shellQuotedArguments(paths))
            toast.show(message: "Copied")
            Logger.log("copy finder path copied count=\(paths.count)")
        } catch {
            onError?("Copy Finder Path failed", error.localizedDescription)
        }
    }

    private func runNewFile() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            Logger.log("new file ignored because Finder is not frontmost")
            return
        }

        do {
            let folder = try currentFinderFolder()
            newFile.show(targetFolder: folder)
            Logger.log("new file panel opened folder=\(folder.path)")
        } catch {
            onError?("New File failed", error.localizedDescription)
        }
    }

    private func handleVoiceCommand(_ transcript: String) -> Bool {
        guard DictationLocalConfiguration.load().voiceCommandsEnabled,
              VoiceCommandIntentRouter.isCommandPhrase(transcript) else {
            return false
        }
        guard ConfigStore.featureEnabled(.commandShortcuts) else {
            onNotice?("Voice command unavailable", "Enable Command Shortcuts before using spoken commands.")
            return true
        }

        let commands = ConfigStore.commandShortcuts()
        guard let item = VoiceCommandIntentRouter.matchingCommand(for: transcript, commands: commands) else {
            onNotice?("Voice command not found", "Say “command” followed by the exact name of a saved command shortcut.")
            return true
        }
        Logger.log("voice command matched saved shortcut id=\(item.id)")
        runCommandShortcut(id: item.id)
        return true
    }

    func runCommandShortcut(id: String) {
        guard ConfigStore.featureEnabled(.commandShortcuts) else { return }
        guard let item = ConfigStore.commandShortcuts().first(where: { $0.id == id }) else {
            onError?("Command Shortcut missing", "That command shortcut no longer exists.")
            return
        }
        let command = item.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            onError?("Command Shortcut missing", "Save a command before using this shortcut.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let started = Date()
                let result = try CommandShortcutRunner.run(command)
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                Logger.log("command shortcut completed elevated=\(result.elevated) ms=\(elapsed) outputBytes=\(result.output.utf8.count)")
                DispatchQueue.main.async {
                    self.toast.show(message: "Command run", placement: .center)
                }
            } catch {
                Logger.log("command shortcut failed \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError?("Command Shortcut failed", error.localizedDescription)
                }
            }
        }
    }

    private func selectedFinderPaths() throws -> [String] {
        let script = """
        tell application "Finder"
          set fileList to selection as alias list
          if (count of fileList) is 0 then
            set fileList to {insertion location as alias}
          end if
          set output to {}
          repeat with itemRef in fileList
            set end of output to POSIX path of itemRef
          end repeat
          return output
        end tell
        """
        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo) else {
            let message = (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "Finder did not return a path."
            throw SimpleError(message)
        }

        guard descriptor.numberOfItems > 0 else { return [] }
        var paths: [String] = []
        for index in 1...descriptor.numberOfItems {
            if let path = descriptor.atIndex(index)?.stringValue, !path.isEmpty {
                paths.append(path)
            }
        }
        return paths
    }

    private func currentFinderFolder() throws -> URL {
        let script = """
        tell application "Finder"
          if (count of Finder windows) is 0 then
            return POSIX path of (desktop as alias)
          end if
          return POSIX path of (target of front Finder window as alias)
        end tell
        """
        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo),
              let path = descriptor.stringValue,
              !path.isEmpty else {
            let message = (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "Finder did not return a folder."
            throw SimpleError(message)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func selectedFinderImageFiles() throws -> [URL] {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return [] }
        let script = """
        tell application "Finder"
          set output to {}
          repeat with itemRef in selection
            set end of output to POSIX path of (itemRef as alias)
          end repeat
          return output
        end tell
        """
        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo) else {
            return []
        }
        var urls: [URL] = []
        for index in 1...descriptor.numberOfItems {
            if let path = descriptor.atIndex(index)?.stringValue {
                let url = URL(fileURLWithPath: path)
                if ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"].contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private func clipboardImagePNGData() -> Data? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) { return data }
        if let data = pasteboard.data(forType: .tiff),
           let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    private func transform(_ text: String, mode: String) -> String {
        switch mode {
        case "upperCase": return text.uppercased()
        case "lowerCase": return text.lowercased()
        case "slugify":
            return text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        case "capitalCase":
            return text.localizedCapitalized
        case "sentenceCase":
            let lower = text.lowercased()
            guard let first = lower.first else { return lower }
            return String(first).uppercased() + lower.dropFirst()
        default:
            return text
        }
    }

    private func selectedTextViaAccessibility() -> String? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              focusedValue != nil else {
            return nil
        }
        let focused = focusedValue as! AXUIElement

        var selectedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
              let selected = selectedValue as? String,
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return selected
    }

    private func selectedTextViaCopy() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let pasteboard = NSPasteboard.general
        let previousText = pasteboard.string(forType: .string)
        let before = pasteboard.changeCount

        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
        postCommandKey(CGKeyCode(kVK_ANSI_C))

        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline && pasteboard.changeCount == before {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
        }

        guard pasteboard.changeCount != before,
              let copied = pasteboard.string(forType: .string),
              !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if copied == previousText {
            return copied
        }
        return copied
    }

    private func postCommandKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
