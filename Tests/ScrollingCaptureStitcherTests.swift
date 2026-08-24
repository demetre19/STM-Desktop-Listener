import AppKit
import Darwin

struct SimpleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@main
struct ScrollingCaptureStitcherTests {
    static func main() throws {
        let frame = makeImage(width: 100, height: 100)
        let stitcher = ScrollingCaptureStitcher(maximumCanvasBytes: 80_000)
        stitcher.start(with: frame)
        expect(stitcher.hasProgress == false, "initial frame alone is not partial capture progress")

        expect(stitcher.add(frame, advancePixels: 30) == .appended(30), "measured pixel advance determines the new strip")
        expect(stitcher.hasProgress, "an accepted strip marks partial capture progress")
        expect(stitcher.outputHeight == 130, "output height tracks measured pixel movement")
        expect(stitcher.add(frame, advancePixels: 1) == .duplicate, "movement inside the dead zone is a duplicate")
        expect(stitcher.add(frame, advancePixels: -1) == .duplicate, "subpixel reverse drift is a duplicate")
        expect(stitcher.add(frame, advancePixels: -10) == .unreliable, "reverse movement is rejected")
        expect(stitcher.add(frame, advancePixels: 101) == .unreliable, "movement larger than the selected frame is rejected")

        let png = try stitcher.pngData()
        guard let bitmap = NSBitmapImageRep(data: png) else {
            fail("PNG output decodes")
        }
        expect(bitmap.pixelsWide == 100, "PNG preserves frame width")
        expect(bitmap.pixelsHigh == 130, "PNG includes the exactly measured strip")

        let capped = ScrollingCaptureStitcher(maximumCanvasBytes: 48_000)
        capped.start(with: frame)
        expect(capped.add(frame, advancePixels: 25) == .maximumSize, "capture stops before exceeding the canvas byte budget")
        expect(capped.outputHeight == 100, "canvas byte budget does not append a partial frame")

        print("ScrollingCaptureStitcherTests: all 11 checks passed")
    }

    private static func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(EXIT_FAILURE)
    }
}
