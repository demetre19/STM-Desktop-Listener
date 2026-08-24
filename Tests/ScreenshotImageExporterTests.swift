import AppKit
import Darwin
import ImageIO
import UniformTypeIdentifiers

@main
struct ScreenshotImageExporterTests {
    static func main() {
        guard let image = makeTransparentImage(width: 401, height: 301) else {
            fail("could not create source image")
        }

        let jpegPlan = ScreenshotExportPlan(
            pixelWidth: image.width,
            pixelHeight: image.height,
            requestedFormat: .jpeg,
            quality: 92,
            copyShrink: 2,
            roundedBackdrop: false
        )
        guard let copyData = ScreenshotImageExporter.data(from: image, plan: jpegPlan, forCopy: true) else {
            fail("could not encode clipboard JPEG")
        }
        expect(imageProperties(copyData) == [201, 151], "copy encodes the exact browser-compatible 2x shrink")
        expect(imageType(copyData) == UTType.jpeg.identifier, "opaque copy preserves requested JPEG format")

        let pasteboard = NSPasteboard(name: .init("com.seotimemachines.screenshot-editor-test"))
        pasteboard.clearContents()
        let pasteboardType = ScreenshotImageExporter.pasteboardType(for: jpegPlan.effectiveFormat)
        expect(pasteboard.setData(copyData, forType: pasteboardType), "encoded screenshot writes to a native pasteboard")
        expect(pasteboard.data(forType: pasteboardType) == copyData, "native pasteboard reads back identical screenshot bytes")
        pasteboard.clearContents()

        let roundedPlan = ScreenshotExportPlan(
            pixelWidth: image.width,
            pixelHeight: image.height,
            requestedFormat: .jpeg,
            quality: 92,
            copyShrink: 2,
            roundedBackdrop: true
        )
        guard let saveData = ScreenshotImageExporter.data(from: image, plan: roundedPlan, forCopy: false) else {
            fail("could not encode rounded save")
        }
        expect(imageProperties(saveData) == [401, 301], "save preserves full rendered resolution")
        expect(imageType(saveData) == UTType.png.identifier, "rounded backdrop forces transparent PNG")

        guard let quadrantImage = makeQuadrantImage(),
              let quadrantData = ScreenshotImageExporter.data(
                from: quadrantImage,
                plan: ScreenshotExportPlan(
                    pixelWidth: quadrantImage.width,
                    pixelHeight: quadrantImage.height,
                    requestedFormat: .png,
                    quality: 100,
                    copyShrink: 1,
                    roundedBackdrop: false
                ),
                forCopy: false
              ) else {
            fail("could not encode orientation fixture")
        }
        expect(
            cornerColors(quadrantData) == ["red", "green", "blue", "yellow"],
            "export preserves top-left image orientation"
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stm-screenshot-export-test.png")
        try? FileManager.default.removeItem(at: url)
        do {
            try saveData.write(to: url, options: .atomic)
            let readback = try Data(contentsOf: url)
            expect(readback == saveData, "atomic save reads back identical screenshot bytes")
            try FileManager.default.removeItem(at: url)
        } catch {
            fail("atomic save failed: \(error.localizedDescription)")
        }

        let webPPlan = ScreenshotExportPlan(
            pixelWidth: image.width,
            pixelHeight: image.height,
            requestedFormat: .webp,
            quality: 73,
            copyShrink: 1,
            roundedBackdrop: false
        )
        guard let webPData = ScreenshotImageExporter.data(from: image, plan: webPPlan, forCopy: false) else {
            fail("could not encode WebP")
        }
        expect(imageType(webPData) == UTType.webP.identifier, "WebP export bytes match their declared format and extension")

        print("ScreenshotImageExporterTests: all 9 checks passed")
    }

    private static func makeTransparentImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemCyan.cgColor)
        context.fill(CGRect(x: 20, y: 20, width: width - 40, height: height - 40))
        return context.makeImage()
    }

    private static func makeQuadrantImage() -> CGImage? {
        let width = 20
        let height = 20
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let color: (UInt8, UInt8, UInt8)
                    switch (x < width / 2, y < height / 2) {
                    case (true, true): color = (255, 0, 0)
                    case (false, true): color = (0, 255, 0)
                    case (true, false): color = (0, 0, 255)
                    case (false, false): color = (255, 255, 0)
                    }
                    bytes[offset] = color.0
                    bytes[offset + 1] = color.1
                    bytes[offset + 2] = color.2
                    bytes[offset + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func cornerColors(_ data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let providerData = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData) else {
            fail("could not decode orientation fixture")
        }
        let points = [(2, 2), (image.width - 3, 2), (2, image.height - 3), (image.width - 3, image.height - 3)]
        return points.map { x, y in
            let pixel = bytes.advanced(by: y * image.bytesPerRow + x * 4)
            let red = Int(pixel[0]), green = Int(pixel[1]), blue = Int(pixel[2])
            if red > 200 && green < 60 && blue < 60 { return "red" }
            if red < 60 && green > 200 && blue < 60 { return "green" }
            if red < 60 && green < 60 && blue > 200 { return "blue" }
            if red > 200 && green > 200 && blue < 60 { return "yellow" }
            return "unknown"
        }
    }

    private static func imageProperties(_ data: Data) -> [Int] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            fail("could not read encoded image dimensions")
        }
        return [width, height]
    }

    private static func imageType(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            fail("could not read encoded image type")
        }
        return type as String
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(EXIT_FAILURE)
    }
}
