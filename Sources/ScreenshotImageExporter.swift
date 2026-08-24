import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotImageExporter {
    static func data(
        from original: CGImage,
        plan: ScreenshotExportPlan,
        forCopy: Bool
    ) -> Data? {
        let size = forCopy ? plan.copyPixelSize : plan.savePixelSize
        guard let image = resized(
            original,
            to: size,
            whiteBackground: plan.effectiveFormat == .jpeg
        ) else { return nil }
        return encode(image, format: plan.effectiveFormat, quality: plan.qualityFraction)
    }

    static func pasteboardType(for format: ScreenshotExportFormat) -> NSPasteboard.PasteboardType {
        switch format {
        case .jpeg: return NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        case .webp: return NSPasteboard.PasteboardType(UTType.webP.identifier)
        case .png: return .png
        }
    }

    private static func resized(_ image: CGImage, to size: CGSize, whiteBackground: Bool) -> CGImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        if whiteBackground {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func encode(_ image: CGImage, format: ScreenshotExportFormat, quality: CGFloat) -> Data? {
        if format == .webp {
            return encodeWebP(image, quality: quality)
        }
        let type: UTType = format == .jpeg ? .jpeg : .png
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func encodeWebP(_ image: CGImage, quality: CGFloat) -> Data? {
        guard let providerData = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData),
              CFDataGetLength(providerData) >= image.bytesPerRow * image.height else { return nil }

        var rgba = Data(count: image.width * image.height * 4)
        rgba.withUnsafeMutableBytes { output in
            guard let destination = output.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<image.height {
                let sourceRow = bytes.advanced(by: y * image.bytesPerRow)
                let destinationRow = destination.advanced(by: y * image.width * 4)
                for x in 0..<image.width {
                    let source = sourceRow.advanced(by: x * 4)
                    let target = destinationRow.advanced(by: x * 4)
                    let alpha = Int(source[3])
                    target[3] = source[3]
                    if alpha == 0 {
                        target[0] = 0
                        target[1] = 0
                        target[2] = 0
                    } else if alpha == 255 {
                        target[0] = source[0]
                        target[1] = source[1]
                        target[2] = source[2]
                    } else {
                        target[0] = UInt8(min(255, (Int(source[0]) * 255 + alpha / 2) / alpha))
                        target[1] = UInt8(min(255, (Int(source[1]) * 255 + alpha / 2) / alpha))
                        target[2] = UInt8(min(255, (Int(source[2]) * 255 + alpha / 2) / alpha))
                    }
                }
            }
        }

        var outputSize: UInt = 0
        let output = rgba.withUnsafeBytes { buffer -> UnsafeMutablePointer<UInt8>? in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return STMWebPEncodeRGBA(
                base,
                Int32(image.width),
                Int32(image.height),
                Int32(image.width * 4),
                Float(quality * 100),
                &outputSize
            )
        }
        guard let output, outputSize > 0 else { return nil }
        defer { STMWebPFree(output) }
        return Data(bytes: output, count: Int(outputSize))
    }
}
