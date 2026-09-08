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
        let canvas = ScreenshotEditorCanvasView(image: base)
        canvas.annotations = [
            ScreenshotAnnotation(
                tool: .box,
                start: CGPoint(x: 120, y: 80),
                end: CGPoint(x: 200, y: 160),
                color: .systemRed,
                strokeWidth: 6
            )
        ]
        let canvasWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        canvasWindow.contentView = canvas
        canvas.selectTool(.number)
        let markerPoints = [CGPoint(x: 140, y: 120), CGPoint(x: 180, y: 120)]
        for point in markerPoints {
            canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: point, windowNumber: canvasWindow.windowNumber))
        }
        var numberedAnnotations = canvas.annotations.filter { $0.tool == .number }
        expect(
            numberedAnnotations.map(\.number) == [1, 2]
                && zip(numberedAnnotations.map(\.start), markerPoints).allSatisfy { $0.0 == $0.1 },
            "number clicks place a contiguous sequence above an existing box"
        )

        canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: markerPoints[0], windowNumber: canvasWindow.windowNumber))
        canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 100, y: 120), windowNumber: canvasWindow.windowNumber))
        canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 100, y: 120), windowNumber: canvasWindow.windowNumber))
        numberedAnnotations = canvas.annotations.filter { $0.tool == .number }
        expect(
            numberedAnnotations.count == 2
                && numberedAnnotations[0].start == CGPoint(x: 100, y: 120)
                && canvas.selectedAnnotation?.id == numberedAnnotations[0].id,
            "clicking an existing number selects and moves it without creating another marker"
        )
        canvas.selectTool(.text)
        canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 160, y: 120), windowNumber: canvasWindow.windowNumber))
        expect(
            canvas.subviews.contains { $0 is NSTextField },
            "text tool starts a new text entry inside an existing annotation"
        )
        canvas.cancelOperation(nil)


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
        guard let darkBase = makeSolidImage(width: 320, height: 240, color: .black) else {
            fail("could not create number marker test image")
        }
        let numberValues = [1, 2, 3, 4]
        let numberCenters = numberValues.indices.map { CGPoint(x: 50 + CGFloat($0) * 70, y: 120) }
        let numberMarkers = zip(numberValues, numberCenters).map { value, center in
            ScreenshotAnnotation(
                tool: .number,
                start: center,
                end: center,
                color: .systemRed,
                strokeWidth: 10,
                number: value
            )
        }
        guard let renderedNumbers = ScreenshotEditorRenderer.render(
            baseImage: darkBase,
            annotations: numberMarkers,
            backdrop: ScreenshotBackdropSettings()
        ) else {
            fail("could not render consecutive number markers")
        }
        for (value, center) in zip(numberValues, numberCenters) {
            guard let bounds = whitePixelBounds(
                renderedNumbers,
                within: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30)
            ) else {
                fail("could not inspect number marker \(value)")
            }
            expect(
                abs(bounds.midX - center.x) <= 1.5 && abs(bounds.midY - center.y) <= 1.5,
                "consecutive number marker \(value) remains centered in its own badge"
            )
        }

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

        runCalloutChecks()

        print("ScreenshotEditorRendererTests: all 24 checks passed")
    }

    /// Shottr-parity text callout: flat by default, flush nub, blob tail that follows the tip, hit-testable, never exported.
    private static func runCalloutChecks() {
        guard let white = makeSolidImage(width: 320, height: 240, color: .white) else {
            fail("could not create callout base image")
        }
        let red = NSColor(stmHex: "#DC2626")!
        let callout = ScreenshotAnnotation(tool: .text, start: CGPoint(x: 100, y: 120), end: CGPoint(x: 100, y: 120), color: red, strokeWidth: 6, text: "Callout", fontSize: 24)
        let rect = ScreenshotEditorRenderer.selectionBounds(callout)

        let nub = ScreenshotEditorRenderer.textTailHandlePosition(callout)
        expect(abs(nub.x - rect.midX) < 0.5 && abs(nub.y - rect.maxY) < 0.5, "flat callout nub sits flush on the bottom edge midpoint")

        guard let flat = ScreenshotEditorRenderer.render(baseImage: white, annotations: [callout], backdrop: ScreenshotBackdropSettings()) else {
            fail("could not render flat callout")
        }
        let outsideBelow = CGRect(x: rect.minX, y: rect.maxY + 3, width: rect.width, height: 60)
        expect(redPixelCount(flat, within: outsideBelow) == 0, "callout renders flat while the nub has not been pulled")

        // Tips hugging the box normalize back to flat; a real pull keeps the tip.
        expect(ScreenshotCalloutGeometry.normalizedTip(rect: rect, tip: CGPoint(x: rect.midX, y: rect.maxY + 2)) == nil, "tip within the flat threshold collapses to a flat box")
        expect(ScreenshotCalloutGeometry.normalizedTip(rect: rect, tip: CGPoint(x: rect.midX, y: rect.maxY + 40)) != nil, "pulled tip is retained")

        // Tail on each side: red outside on the attached side, none on the opposite side.
        let sides: [(String, CGPoint, CGRect, CGRect)] = [
            ("bottom", CGPoint(x: rect.midX + 20, y: rect.maxY + 50), CGRect(x: rect.minX, y: rect.maxY + 3, width: rect.width, height: 40), CGRect(x: rect.minX, y: rect.minY - 43, width: rect.width, height: 40)),
            ("top", CGPoint(x: rect.midX - 20, y: rect.minY - 50), CGRect(x: rect.minX, y: rect.minY - 43, width: rect.width, height: 40), CGRect(x: rect.minX, y: rect.maxY + 3, width: rect.width, height: 40)),
            ("right", CGPoint(x: rect.maxX + 70, y: rect.midY + 5), CGRect(x: rect.maxX + 3, y: rect.minY, width: 40, height: rect.height), CGRect(x: rect.minX - 43, y: rect.minY, width: 40, height: rect.height)),
            ("left", CGPoint(x: rect.minX - 70, y: rect.midY - 5), CGRect(x: rect.minX - 43, y: rect.minY, width: 40, height: rect.height), CGRect(x: rect.maxX + 3, y: rect.minY, width: 40, height: rect.height))
        ]
        for (name, tip, attached, opposite) in sides {
            callout.tailPoint = tip
            guard let image = ScreenshotEditorRenderer.render(baseImage: white, annotations: [callout], backdrop: ScreenshotBackdropSettings()) else {
                fail("could not render \(name) callout tail")
            }
            expect(redPixelCount(image, within: attached) > 50 && redPixelCount(image, within: opposite) == 0, "tail attaches on the \(name) side facing the tip")
        }

        // Blob shape: base flares wider than the straight triangle would and the tail tapers monotonically to the tip.
        let tip = CGPoint(x: rect.midX, y: rect.maxY + 60)
        callout.tailPoint = tip
        guard let tailed = ScreenshotEditorRenderer.render(baseImage: white, annotations: [callout], backdrop: ScreenshotBackdropSettings()) else {
            fail("could not render tapering callout")
        }
        var widths: [Int] = []
        for y in stride(from: Int(rect.maxY) + 2, to: Int(tip.y) - 2, by: 6) {
            widths.append(redPixelCount(tailed, within: CGRect(x: 0, y: CGFloat(y), width: 320, height: 1)))
        }
        expect(widths.first! >= 14, "tail base is at least the minimum blob width, got \(widths.first!)")
        expect(zip(widths, widths.dropFirst()).allSatisfy { $0 >= $1 } && widths.last! < widths.first!, "tail tapers monotonically from base to tip: \(widths)")
        let straightBaseHalf = min(rect.width * 0.3, 20) / 2
        let baseRow = redPixelCount(tailed, within: CGRect(x: 0, y: rect.maxY + 2, width: 320, height: 1))
        expect(CGFloat(baseRow) > straightBaseHalf * 2, "flared base is wider than the legacy straight triangle base")

        // Nub is selection chrome only.
        guard let selected = ScreenshotEditorRenderer.render(baseImage: white, annotations: [callout], backdrop: ScreenshotBackdropSettings(), includeSelection: callout.id) else {
            fail("could not render selected callout")
        }
        let nubRect = CGRect(x: tip.x - 8, y: tip.y - 8, width: 16, height: 16)
        expect(whitePixelBounds(selected, within: nubRect.insetBy(dx: 1, dy: 1)) != nil, "selected callout shows the white-ringed nub at the tip")
        expect(redPixelCount(selected, within: nubRect) > redPixelCount(tailed, within: nubRect) + 40, "nub disc is drawn only with selection; export keeps the bare tapered tip")

        // Canvas: clicking the tail selects the callout, and releasing the tip inside the box flattens it.
        let canvas = ScreenshotEditorCanvasView(image: white)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.annotations = [callout]
        canvas.selectTool(.arrow)
        // Window coordinates are y-up; the flipped canvas maps image y to 240 - y.
        func windowPoint(_ image: CGPoint) -> CGPoint { CGPoint(x: image.x, y: 240 - image.y) }
        let tailMid = windowPoint(CGPoint(x: rect.midX, y: rect.maxY + 25))
        canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: tailMid, windowNumber: window.windowNumber))
        canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: tailMid, windowNumber: window.windowNumber))
        expect(canvas.selectedAnnotation === callout, "clicking the tail selects the callout instead of starting a new annotation")
        let inside = windowPoint(CGPoint(x: rect.midX, y: rect.midY))
        canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: windowPoint(tip), windowNumber: window.windowNumber))
        canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: inside, windowNumber: window.windowNumber))
        canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: inside, windowNumber: window.windowNumber))
        expect(callout.tailPoint == nil, "dragging the tip back into the box returns the callout to flat")
    }

    private static func annotation(_ tool: ScreenshotTool, from start: CGPoint, to end: CGPoint, color: NSColor) -> ScreenshotAnnotation {
        ScreenshotAnnotation(tool: tool, start: start, end: end, color: color, strokeWidth: 6)
    }

    private static func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, windowNumber: Int) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fail("could not create number tool mouse event")
        }
        return event
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

    private static func makeSolidImage(width: Int, height: Int, color: NSColor) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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

    private static func whitePixelBounds(_ image: CGImage, within rect: CGRect) -> CGRect? {
        let bytes = pixelData(image)
        let minX = max(0, Int(rect.minX))
        let maxX = min(image.width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(image.height - 1, Int(rect.maxY))
        var bounds: CGRect?
        bytes.withUnsafeBytes { raw in
            let rgba = raw.bindMemory(to: UInt8.self)
            for y in minY...maxY {
                for x in minX...maxX {
                    let index = (y * image.width + x) * 4
                    guard rgba[index] > 220, rgba[index + 1] > 220, rgba[index + 2] > 220 else { continue }
                    let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                    bounds = bounds.map { $0.union(pixel) } ?? pixel
                }
            }
        }
        return bounds
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

    private static func redPixelCount(_ image: CGImage, within rect: CGRect) -> Int {
        let bytes = pixelData(image)
        let minX = max(0, Int(rect.minX))
        let maxX = min(image.width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(image.height - 1, Int(rect.maxY))
        guard minX <= maxX, minY <= maxY else { return 0 }
        return bytes.withUnsafeBytes { raw -> Int in
            let rgba = raw.bindMemory(to: UInt8.self)
            var count = 0
            for y in minY...maxY {
                for x in minX...maxX {
                    let index = (y * image.width + x) * 4
                    if rgba[index] > 160 && rgba[index + 1] < 100 && rgba[index + 2] < 100 { count += 1 }
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
