import Cocoa
import CoreGraphics
import CoreImage
import CoreMedia
import ScreenCaptureKit

struct ColorPreview {
    let image: CGImage
    let hex: String
    let sourceColorSpace: String

    static func make(snapshots: [ScreenSnapshot], at appKitPoint: CGPoint, radius: CGFloat = 7) -> ColorPreview? {
        guard let snapshot = snapshots.first(where: { $0.screenFrame.contains(appKitPoint) }) else {
            return nil
        }
        let point = snapshot.pixelPoint(for: appKitPoint)
        let pixelRadius = max(2, Int(round(radius * snapshot.scale)))
        let imageBounds = CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height)
        let crop = CGRect(
            x: point.x - CGFloat(pixelRadius),
            y: point.y - CGFloat(pixelRadius),
            width: CGFloat(pixelRadius * 2 + 1),
            height: CGFloat(pixelRadius * 2 + 1)
        ).intersection(imageBounds)
        guard let cropped = snapshot.image.cropping(to: crop),
              let sRGBImage = SRGBColorSampler.convertImage(cropped),
              let sample = SRGBColorSampler.sample(snapshot.image, x: Int(round(point.x)), y: Int(round(point.y))) else {
            return nil
        }
        return ColorPreview(image: sRGBImage, hex: sample.hex, sourceColorSpace: sample.sourceColorSpace)
    }

    static func hex(snapshots: [ScreenSnapshot], at appKitPoint: CGPoint) -> String? {
        guard let snapshot = snapshots.first(where: { $0.screenFrame.contains(appKitPoint) }) else {
            return nil
        }
        let point = snapshot.pixelPoint(for: appKitPoint)
        return SRGBColorSampler.sample(snapshot.image, x: Int(round(point.x)), y: Int(round(point.y)))?.hex
    }
}

struct ScreenSnapshot {
    let screenFrame: CGRect
    let scale: CGFloat
    let image: CGImage

    func pixelPoint(for appKitPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(CGFloat(image.width - 1), (appKitPoint.x - screenFrame.minX) * scale)),
            y: max(0, min(CGFloat(image.height - 1), (screenFrame.maxY - appKitPoint.y) * scale))
        )
    }
}

final class CaptureService {
    func capturePNG(rect appKitRect: CGRect, assumePermissionGranted: Bool = false) throws -> Data {
        let image = try captureImage(rect: appKitRect, assumePermissionGranted: assumePermissionGranted)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SimpleError("Could not encode screenshot")
        }
        return png
    }

    func captureImage(rect appKitRect: CGRect, assumePermissionGranted: Bool = false) throws -> CGImage {
        if !assumePermissionGranted {
            guard PermissionCenter.hasScreenAccess() else {
                throw SimpleError("Screen Recording permission is not ready. Reset and grant Screen Recording before testing captures.")
            }
        }

        if let image = captureVisibleWindowServerImage(rect: appKitRect) {
            return image
        }

        guard #available(macOS 12.3, *) else {
            throw SimpleError("ScreenCaptureKit requires macOS 12.3 or newer.")
        }
        guard let screen = screen(containing: appKitRect),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw SimpleError("Could not resolve selected display")
        }

        let display = try screenCaptureDisplay(displayID: CGDirectDisplayID(displayID.uint32Value))
        let scale = screen.backingScaleFactor
        let fullImage = try ScreenCaptureKitFrameGrabber.capture(display: display, screen: screen, scale: scale)
        let crop = pixelCropRect(for: appKitRect, screen: screen, image: fullImage, scale: scale)
        guard let cropped = fullImage.cropping(to: crop) else {
            throw SimpleError("Could not crop captured screen image")
        }
        return cropped
    }

    func captureVisibleSnapshotsForScreens(assumePermissionGranted: Bool = false) throws -> [ScreenSnapshot] {
        let totalStarted = Date()
        if !assumePermissionGranted {
            let permissionStarted = Date()
            guard PermissionCenter.hasScreenAccess() else {
                throw SimpleError("Screen Recording permission is not ready. Reset and grant Screen Recording before testing captures.")
            }
            Logger.log("capture visible snapshots permissionMs=\(Int(Date().timeIntervalSince(permissionStarted) * 1000))")
        }

        let screensStarted = Date()
        let screens = NSScreen.screens
        Logger.log("capture visible snapshots screensMs=\(Int(Date().timeIntervalSince(screensStarted) * 1000)) count=\(screens.count)")
        let snapshots = screens.compactMap { screen -> ScreenSnapshot? in
            let screenStarted = Date()
            guard let image = captureVisibleWindowServerImage(rect: screen.frame) else {
                return nil
            }
            let scale = CGFloat(image.width) / max(1, screen.frame.width)
            Logger.log("capture visible snapshot screenMs=\(Int(Date().timeIntervalSince(screenStarted) * 1000)) frame=\(screen.frame) pixels=\(image.width)x\(image.height)")
            return ScreenSnapshot(screenFrame: screen.frame, scale: scale, image: image)
        }

        guard !snapshots.isEmpty else {
            throw SimpleError("Could not freeze the visible screen before selection.")
        }
        Logger.log("capture visible snapshots totalMs=\(Int(Date().timeIntervalSince(totalStarted) * 1000)) count=\(snapshots.count) assumePermission=\(assumePermissionGranted)")
        return snapshots
    }


    func cropImage(from snapshots: [ScreenSnapshot], rect appKitRect: CGRect) throws -> CGImage {
        guard let snapshot = snapshot(containing: appKitRect, in: snapshots) else {
            throw SimpleError("Could not match the selected region to a frozen screen.")
        }
        let crop = pixelCropRect(for: appKitRect, snapshot: snapshot)
        guard let cropped = snapshot.image.cropping(to: crop) else {
            throw SimpleError("Could not crop frozen screenshot")
        }
        return cropped
    }

    func sampleColor(at appKitPoint: CGPoint) throws -> String {
        let image = try captureImage(rect: CGRect(x: appKitPoint.x, y: appKitPoint.y, width: 1, height: 1))
        guard let sample = SRGBColorSampler.sample(image, x: 0, y: 0) else {
            throw SimpleError("Could not sample color")
        }
        Logger.log("color sample point=\(appKitPoint) sourceColorSpace=\(sample.sourceColorSpace) sRGB=\(sample.hex)")
        return sample.hex
    }

    func fastColorPreview(at appKitPoint: CGPoint, radius: CGFloat = 7, excludingWindowNumber: CGWindowID? = nil) -> ColorPreview? {
        let size = max(3, radius * 2 + 1)
        let rect = CGRect(
            x: appKitPoint.x - radius,
            y: appKitPoint.y - radius,
            width: size,
            height: size
        )

        guard let image = captureVisibleWindowServerImage(rect: rect, belowWindow: excludingWindowNumber),
              let sRGBImage = SRGBColorSampler.convertImage(image),
              let sample = SRGBColorSampler.sample(image, x: image.width / 2, y: image.height / 2) else {
            return nil
        }
        return ColorPreview(image: sRGBImage, hex: sample.hex, sourceColorSpace: sample.sourceColorSpace)
    }

    func colorPreview(at appKitPoint: CGPoint, radius: CGFloat = 7) throws -> ColorPreview {
        let size = max(3, radius * 2 + 1)
        let image = try captureImage(rect: CGRect(
            x: appKitPoint.x - radius,
            y: appKitPoint.y - radius,
            width: size,
            height: size
        ))
        guard let sRGBImage = SRGBColorSampler.convertImage(image),
              let sample = SRGBColorSampler.sample(image, x: image.width / 2, y: image.height / 2) else {
            throw SimpleError("Could not sample color")
        }
        Logger.log("color preview point=\(appKitPoint) sourceColorSpace=\(sample.sourceColorSpace) sRGB=\(sample.hex)")
        return ColorPreview(image: sRGBImage, hex: sample.hex, sourceColorSpace: sample.sourceColorSpace)
    }

    func snapshotsForScreens() throws -> [ScreenSnapshot] {
        guard #available(macOS 12.3, *) else {
            throw SimpleError("ScreenCaptureKit requires macOS 12.3 or newer.")
        }
        return try NSScreen.screens.map { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                throw SimpleError("Could not resolve screen display")
            }
            let display = try screenCaptureDisplay(displayID: CGDirectDisplayID(displayID.uint32Value))
            let scale = screen.backingScaleFactor
            let image = try ScreenCaptureKitFrameGrabber.capture(display: display, screen: screen, scale: scale)
            return ScreenSnapshot(screenFrame: screen.frame, scale: scale, image: image)
        }
    }

    @available(macOS 12.3, *)
    private func screenCaptureDisplay(displayID: CGDirectDisplayID) throws -> SCDisplay {
        var result: Result<SCDisplay, Error>?
        let sem = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            if let error = error {
                result = .failure(error)
            } else if let display = content?.displays.first(where: { $0.displayID == displayID }) {
                result = .success(display)
            } else {
                result = .failure(SimpleError("Screen capture display was not found"))
            }
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 5) == .success, let result = result else {
            throw SimpleError("Timed out while reading screen capture displays")
        }
        return try result.get()
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }
        return NSScreen.screens.max { a, b in
            a.frame.intersection(rect).width * a.frame.intersection(rect).height <
            b.frame.intersection(rect).width * b.frame.intersection(rect).height
        }
    }

    private func snapshot(containing rect: CGRect, in snapshots: [ScreenSnapshot]) -> ScreenSnapshot? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let snapshot = snapshots.first(where: { $0.screenFrame.contains(center) }) {
            return snapshot
        }
        return snapshots.max { a, b in
            a.screenFrame.intersection(rect).width * a.screenFrame.intersection(rect).height <
            b.screenFrame.intersection(rect).width * b.screenFrame.intersection(rect).height
        }
    }

    private func captureVisibleWindowServerImage(rect appKitRect: CGRect, belowWindow: CGWindowID? = nil) -> CGImage? {
        guard let screen = screen(containing: appKitRect),
              let captureRect = windowServerRect(for: appKitRect, screen: screen) else {
            return nil
        }

        let started = Date()
        let options: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        let windowNumber = belowWindow ?? kCGNullWindowID
        let listOption: CGWindowListOption = belowWindow == nil ? .optionOnScreenOnly : .optionOnScreenBelowWindow
        guard let image = CGWindowListCreateImage(captureRect, listOption, windowNumber, options) else {
            if shouldLogCapture(rect: appKitRect) {
                Logger.log("capture backend=windowserver failed rect=\(appKitRect)")
            }
            return nil
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        if shouldLogCapture(rect: appKitRect) {
            Logger.log("capture backend=windowserver ms=\(elapsed) rect=\(appKitRect) pixels=\(image.width)x\(image.height) belowWindow=\(windowNumber)")
        }
        return image
    }

    private func shouldLogCapture(rect: CGRect) -> Bool {
        rect.width > 64 || rect.height > 64
    }

    private func windowServerRect(for appKitRect: CGRect, screen: NSScreen) -> CGRect? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(displayID.uint32Value))
        let localX = appKitRect.minX - screen.frame.minX
        let localYFromTop = screen.frame.maxY - appKitRect.maxY
        return CGRect(
            x: displayBounds.minX + localX,
            y: displayBounds.minY + localYFromTop,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private func pixelCropRect(for rect: CGRect, screen: NSScreen, image: CGImage, scale: CGFloat) -> CGRect {
        let localX = max(0, rect.minX - screen.frame.minX)
        let localYFromTop = max(0, screen.frame.maxY - rect.maxY)
        let x = Int(round(localX * scale))
        let y = Int(round(localYFromTop * scale))
        let width = max(1, Int(round(rect.width * scale)))
        let height = max(1, Int(round(rect.height * scale)))
        return CGRect(
            x: min(x, image.width - 1),
            y: min(y, image.height - 1),
            width: min(width, max(1, image.width - x)),
            height: min(height, max(1, image.height - y))
        )
    }

    private func pixelCropRect(for rect: CGRect, snapshot: ScreenSnapshot) -> CGRect {
        let localX = max(0, rect.minX - snapshot.screenFrame.minX)
        let localYFromTop = max(0, snapshot.screenFrame.maxY - rect.maxY)
        let x = Int(round(localX * snapshot.scale))
        let y = Int(round(localYFromTop * snapshot.scale))
        let width = max(1, Int(round(rect.width * snapshot.scale)))
        let height = max(1, Int(round(rect.height * snapshot.scale)))
        return CGRect(
            x: min(x, snapshot.image.width - 1),
            y: min(y, snapshot.image.height - 1),
            width: min(width, max(1, snapshot.image.width - x)),
            height: min(height, max(1, snapshot.image.height - y))
        )
    }
}

private struct SRGBColorSample {
    let hex: String
    let sourceColorSpace: String
}

private enum SRGBColorSampler {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    static func convertImage(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    static func sample(_ image: CGImage, x: Int, y: Int) -> SRGBColorSample? {
        let safeX = max(0, min(image.width - 1, x))
        let safeY = max(0, min(image.height - 1, y))
        guard let pixel = image.cropping(to: CGRect(x: safeX, y: safeY, width: 1, height: 1)),
              let converted = convertImage(pixel),
              let data = converted.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              CFDataGetLength(data) >= 4 else {
            return nil
        }
        let hex = String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
        let source = image.colorSpace?.name.map { String($0) } ?? "unknown"
        return SRGBColorSample(hex: hex, sourceColorSpace: source)
    }
}

@available(macOS 12.3, *)
private final class ScreenCaptureKitFrameGrabber: NSObject, SCStreamOutput {
    private let context = CIContext()
    private let frameSem = DispatchSemaphore(value: 0)
    private var frameResult: Result<CGImage, Error>?

    static func capture(display: SCDisplay, screen: NSScreen, scale: CGFloat) throws -> CGImage {
        let output = ScreenCaptureKitFrameGrabber()
        let config = SCStreamConfiguration()
        config.width = max(1, Int(round(screen.frame.width * scale)))
        config.height = max(1, Int(round(screen.frame.height * scale)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let queue = DispatchQueue(label: "com.seotimemachines.stm-desktop-listener.capture", qos: .userInitiated)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)

        var startError: Error?
        let startSem = DispatchSemaphore(value: 0)
        stream.startCapture { error in
            startError = error
            startSem.signal()
        }
        guard startSem.wait(timeout: .now() + 5) == .success else {
            throw SimpleError("Timed out starting screen capture")
        }
        if let startError = startError {
            throw startError
        }

        let gotFrame = output.frameSem.wait(timeout: .now() + 5)
        let frameResult = output.frameResult

        let stopSem = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in stopSem.signal() }
        _ = stopSem.wait(timeout: .now() + 2)

        guard gotFrame == .success, let frameResult = frameResult else {
            throw SimpleError("Timed out waiting for screen capture frame")
        }
        return try frameResult.get()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, frameResult == nil else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            frameResult = .failure(SimpleError("Screen capture returned no image buffer"))
            frameSem.signal()
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        if let cgImage = context.createCGImage(ciImage, from: rect) {
            frameResult = .success(cgImage)
        } else {
            frameResult = .failure(SimpleError("Could not convert screen capture frame"))
        }
        frameSem.signal()
    }
}
