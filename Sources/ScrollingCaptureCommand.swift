import Cocoa
import ApplicationServices
import CoreGraphics

private final class ScrollingCaptureAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = ScrollingCaptureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

enum ScrollingCaptureCommand {
    private static var delegate: ScrollingCaptureAppDelegate?

    static func runIfNeeded() -> Bool {
        guard CommandLine.arguments.contains("--scrolling-capture") else { return false }
        let app = NSApplication.shared
        let delegate = ScrollingCaptureAppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        return true
    }

    static func launchDetached() throws -> Int32 {
        guard let executableURL = Bundle.main.executableURL else {
            throw SimpleError("Could not locate STM Desktop Listener executable")
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--scrolling-capture"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }
}

struct ScrollingCaptureProgress: Codable {
    let sequence: Int
    let measured: Bool
    let advancePixels: Int?
}

struct ScrollingCaptureSelection: Codable {
    let width: Double
    let height: Double
    let scale: Double
}

enum ScrollingCaptureProgressStore {
    private static func url(processID: Int32) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stm-scrolling-capture-\(processID).json")
    }

    private static func selectionURL(processID: Int32) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stm-scrolling-capture-\(processID)-selection.json")
    }

    static func write(processID: Int32, sequence: Int, measured: Bool, advancePixels: Int?) throws {
        guard processID > 0,
              sequence > 0,
              sequence <= 10_000,
              advancePixels.map({ abs($0) <= 100_000 }) ?? true else {
            throw SimpleError("Invalid scrolling capture progress target")
        }
        let progress = ScrollingCaptureProgress(
            sequence: sequence,
            measured: measured,
            advancePixels: advancePixels
        )
        try JSONEncoder().encode(progress).write(to: url(processID: processID), options: .atomic)
    }

    static func writeSelection(processID: Int32, rect: CGRect, scale: CGFloat) throws {
        guard processID > 0, rect.width >= 80, rect.height >= 80, scale >= 1 else {
            throw SimpleError("Invalid scrolling capture selection")
        }
        let selection = ScrollingCaptureSelection(
            width: Double(rect.width),
            height: Double(rect.height),
            scale: Double(scale)
        )
        try JSONEncoder().encode(selection).write(
            to: selectionURL(processID: processID),
            options: .atomic
        )
    }

    static func readSelection(processID: Int32) throws -> ScrollingCaptureSelection? {
        let fileURL = selectionURL(processID: processID)
        guard processID > 0, FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            ScrollingCaptureSelection.self,
            from: Data(contentsOf: fileURL)
        )
    }

    static func read(processID: Int32, after sequence: Int) throws -> ScrollingCaptureProgress? {
        let fileURL = url(processID: processID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let progress = try JSONDecoder().decode(
            ScrollingCaptureProgress.self,
            from: Data(contentsOf: fileURL)
        )
        return progress.sequence > sequence ? progress : nil
    }

    static func remove(processID: Int32) {
        try? FileManager.default.removeItem(at: url(processID: processID))
        try? FileManager.default.removeItem(at: selectionURL(processID: processID))
    }
}

private final class ScrollingCaptureController {
    private let captureService = CaptureService()
    private let selectionController = SelectionOverlayController()
    private let toastController = ToastController()
    private let stitcher = ScrollingCaptureStitcher()
    private var selectionRect: CGRect?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var stopped = false
    private var consecutiveDuplicateCount = 0
    private var progressSequence = 0

    func start() {
        ScrollingCaptureProgressStore.remove(processID: getpid())
        Logger.log("scrolling capture command started")
        guard PermissionCenter.hasScreenAccess() else {
            Logger.log("scrolling capture blocked screen permission")
            PermissionCenter.openScreenRecordingSettings()
            finishWithError("Grant Screen Recording, then restart STM Desktop Listener")
            return
        }
        guard AXIsProcessTrusted() else {
            Logger.log("scrolling capture blocked accessibility permission")
            _ = PermissionCenter.requestAccessibility()
            finishWithError("Grant Accessibility, then restart STM Desktop Listener")
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        selectionController.start(label: "Select the scrolling area") { [weak self] rect in
            guard let self else { return }
            guard let rect, rect.width >= 80, rect.height >= 80 else {
                self.stopWithoutSaving()
                return
            }
            Logger.log("scrolling capture selection rect=\(rect)")
            self.selectionRect = rect
            guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else {
                self.finishWithError("Could not map the selected scrolling area")
                return
            }
            do {
                try ScrollingCaptureProgressStore.writeSelection(
                    processID: getpid(),
                    rect: rect,
                    scale: screen.backingScaleFactor
                )
            } catch {
                self.finishWithError(error.localizedDescription)
                return
            }
            self.installEscapeMonitors()
            self.toastController.show(
                message: "Capturing automatically. Press Escape to cancel.",
                duration: 1.2,
                placement: .bottomCenter
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                self.captureInitialFrame()
            }
        }
    }

    private func captureInitialFrame() {
        guard !stopped, let selectionRect else { return }
        do {
            stitcher.start(with: try captureService.captureImage(rect: selectionRect, assumePermissionGranted: true))
            Logger.log("scrolling capture initial frame height=\(stitcher.outputHeight)")
            postScroll()
        } catch {
            finishWithError(error.localizedDescription)
        }
    }

    private func postScroll() {
        guard !stopped, let selectionRect else { return }
        let scrollDistance = Int32(min(900, max(120, selectionRect.height * 0.7)).rounded())
        guard let point = quartzPoint(for: CGPoint(x: selectionRect.midX, y: selectionRect.midY)),
              let event = CGEvent(
                scrollWheelEvent2Source: CGEventSource(stateID: .combinedSessionState),
                units: .pixel,
                wheelCount: 1,
                wheel1: -scrollDistance,
                wheel2: 0,
                wheel3: 0
              ) else {
            finishWithError("Could not create the automatic scroll event")
            return
        }
        event.location = point
        event.post(tap: .cghidEventTap)
        Logger.log("scrolling capture posted scroll distance=\(scrollDistance)")
        waitForMeasuredProgress(attempt: 0)
    }

    private func waitForMeasuredProgress(attempt: Int) {
        guard !stopped else { return }
        do {
            if let progress = try ScrollingCaptureProgressStore.read(
                processID: getpid(),
                after: progressSequence
            ) {
                progressSequence = progress.sequence
                guard progress.measured, let advancePixels = progress.advancePixels else {
                    finishWithError("Could not measure exact page movement. Select the main scrolling content and try again.")
                    return
                }
                captureAfterScroll(advancePixels: advancePixels)
                return
            }
        } catch {
            finishWithError(error.localizedDescription)
            return
        }

        guard attempt < 30 else {
            finishWithError("Timed out while measuring exact page movement")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForMeasuredProgress(attempt: attempt + 1)
        }
    }

    private func captureAfterScroll(advancePixels: Int) {
        guard !stopped, let selectionRect else { return }
        do {
            let image = try captureService.captureImage(rect: selectionRect, assumePermissionGranted: true)
            switch stitcher.add(image, advancePixels: advancePixels) {
            case .appended:
                consecutiveDuplicateCount = 0
                Logger.log("scrolling capture appended advance=\(advancePixels) height=\(stitcher.outputHeight)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.postScroll() }
            case .duplicate:
                consecutiveDuplicateCount += 1
                Logger.log("scrolling capture duplicate count=\(consecutiveDuplicateCount)")
                if consecutiveDuplicateCount >= 3 {
                    saveAndFinish(message: "Scrolling screenshot captured")
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.postScroll() }
                }
            case .unreliable:
                finishWithError("Exact page movement exceeded the selected capture area. Select a taller scrolling area and try again.")
            case .maximumSize:
                Logger.log("scrolling capture maximum canvas bytes height=\(stitcher.outputHeight)")
                saveAndFinish(message: "Scrolling screenshot memory limit reached")
            }
        } catch {
            finishWithError(error.localizedDescription)
        }
    }


    private func saveAndFinish(message: String) {
        guard !stopped else { return }
        stopped = true
        removeEscapeMonitors()
        ScrollingCaptureProgressStore.remove(processID: getpid())
        do {
            let record = try PayloadStore.store(
                data: stitcher.pngData(),
                filename: "scrolling-screenshot.png",
                contentType: "image/png",
                kind: "screenshot"
            )
            Logger.log("scrolling capture saved height=\(stitcher.outputHeight) token=\(record.token)")
            toastController.show(message: message, duration: 1.2, placement: .bottomCenter)
            BrowserBridge().openScreenshot(token: record.token)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { NSApp.terminate(nil) }
        } catch {
            finishWithError(error.localizedDescription)
        }
    }

    private func stopWithoutSaving() {
        guard !stopped else { return }
        stopped = true
        Logger.log("scrolling capture cancelled")
        removeEscapeMonitors()
        ScrollingCaptureProgressStore.remove(processID: getpid())
        NSApp.terminate(nil)
    }

    private func finishWithError(_ message: String) {
        stopped = true
        Logger.log("scrolling capture failed message=\(message)")
        ScrollingCaptureProgressStore.remove(processID: getpid())
        removeEscapeMonitors()
        toastController.show(message: message, duration: 4, placement: .center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.1) { NSApp.terminate(nil) }
    }

    private func installEscapeMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.stopWithoutSaving()
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.stopWithoutSaving() }
        }
    }

    private func removeEscapeMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func quartzPoint(for appKitPoint: CGPoint) -> CGPoint? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(displayNumber.uint32Value))
        return CGPoint(
            x: displayBounds.minX + appKitPoint.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - appKitPoint.y
        )
    }

}
