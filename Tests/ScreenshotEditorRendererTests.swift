import AppKit
import Darwin

@main
struct ScreenshotEditorRendererTests {
    static func main() {
        guard let base = makeBaseImage(width: 320, height: 240) else {
            fail("could not create base image")
        }

        guard let unmodified = ScreenshotEditorRenderer.render(
            baseImage: base,
            annotations: [],
            backdrop: ScreenshotBackdropSettings()
        ) else {
            fail("could not render unmodified screenshot")
        }
        expect(pixelData(unmodified) == pixelData(base), "renderer preserves the source orientation and pixel layout")

        let annotations = [
            annotation(.arrow, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 110, y: 70), color: .systemRed),
            annotation(.line, from: CGPoint(x: 20, y: 90), to: CGPoint(x: 130, y: 90), color: .systemBlue),
            ScreenshotAnnotation(tool: .box, start: CGPoint(x: 140, y: 20), end: CGPoint(x: 230, y: 85), color: .systemGreen, strokeWidth: 6, fillOpacity: 0.25),
            ScreenshotAnnotation(tool: .text, start: CGPoint(x: 20, y: 145), end: CGPoint(x: 20, y: 145), color: .black, strokeWidth: 6, text: "Native", tailPoint: CGPoint(x: 75, y: 195)),
            ScreenshotAnnotation(tool: .number, start: CGPoint(x: 270, y: 45), end: CGPoint(x: 270, y: 45), color: .systemOrange, strokeWidth: 10, number: 3),
            annotation(.blur, from: CGPoint(x: 140, y: 100), to: CGPoint(x: 215, y: 145), color: .black),
            annotation(.pixelate, from: CGPoint(x: 225, y: 100), to: CGPoint(x: 300, y: 145), color: .black),
            ScreenshotAnnotation(tool: .magnifier, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 250, y: 190), color: .systemPurple, strokeWidth: 5, magnifierSource: CGPoint(x: 100, y: 110), magnifierSourceRadius: 24, magnifierDisplayRadius: 38)
        ]

        guard let plain = ScreenshotEditorRenderer.render(baseImage: base, annotations: annotations, backdrop: ScreenshotBackdropSettings()) else {
            fail("could not render annotation tools")
        }
        expect(plain.width == 320 && plain.height == 240, "annotations preserve the base canvas size")
        expect(pixelData(plain) != pixelData(base), "annotation tools visibly alter rendered pixels")

        let arrowWidths: [CGFloat] = [3, 6, 10]
        let arrowPixelCounts = arrowWidths.compactMap { width -> Int? in
            let arrow = ScreenshotAnnotation(
                tool: .arrow,
                start: CGPoint(x: 40, y: 60),
                end: CGPoint(x: 180, y: 120),
                color: .systemRed,
                strokeWidth: width
            )
            guard let rendered = ScreenshotEditorRenderer.render(
                baseImage: base,
                annotations: [arrow],
                backdrop: ScreenshotBackdropSettings()
            ) else { return nil }
            return redPixelCount(rendered)
        }
        expect(
            arrowPixelCounts.count == arrowWidths.count
                && arrowPixelCounts.allSatisfy { $0 > 0 }
                && zip(arrowPixelCounts, arrowPixelCounts.dropFirst()).allSatisfy(<),
            "extension stroke sizes keep arrows visible and progressively thicker"
        )

        let selectedArrow = ScreenshotAnnotation(
            tool: .arrow,
            start: CGPoint(x: 40, y: 60),
            end: CGPoint(x: 180, y: 120),
            color: .systemRed,
            strokeWidth: 10
        )
        guard let arrowPlain = ScreenshotEditorRenderer.render(
            baseImage: base,
            annotations: [selectedArrow],
            backdrop: ScreenshotBackdropSettings()
        ), let arrowSelected = ScreenshotEditorRenderer.render(
            baseImage: base,
            annotations: [selectedArrow],
            backdrop: ScreenshotBackdropSettings(),
            includeSelection: selectedArrow.id
        ) else {
            fail("could not render selected arrow")
        }
        let unusedCorner = CGRect(x: 30, y: 120, width: 10, height: 10)
        let startAnchor = CGRect(x: 32, y: 52, width: 16, height: 16)
        expect(
            compactPixelData(ScreenshotEditorRenderer.crop(image: arrowPlain, to: unusedCorner)!)
                == compactPixelData(ScreenshotEditorRenderer.crop(image: arrowSelected, to: unusedCorner)!)
                && compactPixelData(ScreenshotEditorRenderer.crop(image: arrowPlain, to: startAnchor)!)
                != compactPixelData(ScreenshotEditorRenderer.crop(image: arrowSelected, to: startAnchor)!),
            "selected arrows use only the extension's endpoint handles, never an obscuring bounding box"
        )

        var backdrop = ScreenshotBackdropSettings()
        backdrop.isEnabled = true
        backdrop.padding = 32
        backdrop.outerRadius = 18
        backdrop.background = .linear(stops: ScreenshotBackdropSettings.gradientPresets[0].1, angle: 45)
        guard let framed = ScreenshotEditorRenderer.render(baseImage: base, annotations: annotations, backdrop: backdrop) else {
            fail("could not render backdrop")
        }
        expect(framed.width == 384 && framed.height == 304, "backdrop padding expands each edge exactly")

        let effect = annotation(
            .pixelate,
            from: CGPoint(x: 120, y: 80),
            to: CGPoint(x: 230, y: 170),
            color: .black
        )
        guard let plainEffect = ScreenshotEditorRenderer.render(
            baseImage: base,
            annotations: [effect],
            backdrop: ScreenshotBackdropSettings()
        ), let framedEffect = ScreenshotEditorRenderer.render(
            baseImage: base,
            annotations: [effect],
            backdrop: backdrop
        ), let plainEffectRegion = ScreenshotEditorRenderer.crop(
            image: plainEffect,
            to: effect.rect
        ), let framedEffectRegion = ScreenshotEditorRenderer.crop(
            image: framedEffect,
            to: effect.rect.offsetBy(dx: backdrop.padding, dy: backdrop.padding)
        ) else {
            fail("could not compare backdrop-aware image effects")
        }
        expect(
            compactPixelData(plainEffectRegion) == compactPixelData(framedEffectRegion),
            "blur and pixelate sample the same screenshot pixels when a backdrop adds padding"
        )

        guard let cropped = ScreenshotEditorRenderer.crop(image: plain, to: CGRect(x: 40, y: 30, width: 101, height: 79)) else {
            fail("could not crop rendered image")
        }
        expect(cropped.width == 101 && cropped.height == 79, "crop preserves the selected pixel dimensions")

        print("ScreenshotEditorRendererTests: all 8 checks passed")
    }

    private static func annotation(_ tool: ScreenshotTool, from start: CGPoint, to end: CGPoint, color: NSColor) -> ScreenshotAnnotation {
        ScreenshotAnnotation(tool: tool, start: start, end: end, color: color, strokeWidth: 6)
    }

    private static func makeBaseImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(NSColor.systemYellow.cgColor)
        context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
        return context.makeImage()
    }

    private static func pixelData(_ image: CGImage) -> Data {
        image.dataProvider?.data as Data? ?? Data()
    }

    private static func compactPixelData(_ image: CGImage) -> Data {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()?.dataProvider?.data as Data? ?? Data()
    }

    private static func redPixelCount(_ image: CGImage) -> Int {
        let bytes = pixelData(image)
        return bytes.withUnsafeBytes { raw -> Int in
            let rgba = raw.bindMemory(to: UInt8.self)
            var count = 0
            for index in stride(from: 0, to: rgba.count, by: 4) {
                if rgba[index] > 160 && rgba[index + 1] < 100 && rgba[index + 2] < 100 {
                    count += 1
                }
            }
            return count
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(EXIT_FAILURE)
    }
}
