import AppKit

enum ScrollingCaptureFrameResult: Equatable {
    case appended(Int)
    case duplicate
    case unreliable
    case maximumSize
}

final class ScrollingCaptureStitcher {
    private let movementDeadZone = 3
    private let maximumCanvasBytes: Int
    private var firstFrame: CGImage?
    private var strips: [CGImage] = []
    private(set) var outputHeight = 0
    private var maximumOutputHeight = 0
    var hasProgress: Bool { !strips.isEmpty }

    init(maximumCanvasBytes: Int = 1_073_741_824) {
        self.maximumCanvasBytes = maximumCanvasBytes
    }

    func start(with image: CGImage) {
        firstFrame = image
        strips = []
        outputHeight = image.height
        maximumOutputHeight = max(
            image.height,
            maximumCanvasBytes / max(1, image.width * 4)
        )
    }

    func add(_ image: CGImage, advancePixels: Int) -> ScrollingCaptureFrameResult {
        guard let firstFrame else {
            start(with: image)
            return .appended(image.height)
        }
        guard image.width == firstFrame.width, image.height == firstFrame.height else {
            return .unreliable
        }
        if abs(advancePixels) <= movementDeadZone {
            return .duplicate
        }
        guard advancePixels > 0, advancePixels <= image.height else {
            return .unreliable
        }
        if outputHeight + advancePixels > maximumOutputHeight {
            return .maximumSize
        }
        guard let strip = image.cropping(to: CGRect(
            x: 0,
            y: image.height - advancePixels,
            width: image.width,
            height: advancePixels
        )) else {
            return .unreliable
        }

        strips.append(strip)
        outputHeight += advancePixels
        return .appended(advancePixels)
    }

    func pngData() throws -> Data {
        guard let firstFrame else { throw SimpleError("No scrolling screenshot frames were captured") }
        guard let context = CGContext(
            data: nil,
            width: firstFrame.width,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SimpleError("Could not create scrolling screenshot canvas")
        }

        var top = outputHeight
        top -= firstFrame.height
        context.draw(firstFrame, in: CGRect(x: 0, y: top, width: firstFrame.width, height: firstFrame.height))
        for strip in strips {
            top -= strip.height
            context.draw(strip, in: CGRect(x: 0, y: top, width: strip.width, height: strip.height))
        }

        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw SimpleError("Could not encode scrolling screenshot")
        }
        return png
    }
}
