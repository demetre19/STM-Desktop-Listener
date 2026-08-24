import AppKit
import CoreImage
import CoreText
import Foundation

struct ScreenshotGradientStop: Equatable {
    var color: NSColor
    var position: CGFloat
}

enum ScreenshotBackdropBackground: Equatable {
    case solid(NSColor)
    case linear(stops: [ScreenshotGradientStop], angle: CGFloat)
    case radial(stops: [ScreenshotGradientStop])
    case image
}

struct ScreenshotBackdropSettings {
    var isEnabled = false
    var padding: CGFloat = 40
    var shadow: CGFloat = 20
    var shadowBlur: CGFloat = 30
    var shadowColor = NSColor.black
    var shadowOffsetX: CGFloat = 0
    var shadowOffsetY: CGFloat = 8
    var shadowOpacity: CGFloat = 0.3
    var outerRadius: CGFloat = 12
    var innerRadius: CGFloat = 8
    var background: ScreenshotBackdropBackground = .solid(NSColor(stmHex: "#1A1A1A")!)
    var backgroundImage: CGImage?
    var backgroundImageBlur: CGFloat = 20
    var backgroundImageOffsetX: CGFloat = 0
    var backgroundImageOffsetY: CGFloat = 0

    static let gradientPresets: [(String, [ScreenshotGradientStop])] = [
        ("Sunset", [ScreenshotGradientStop(color: NSColor(stmHex: "#FF6B6B")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#FECA57")!, position: 1)]),
        ("Ocean", [ScreenshotGradientStop(color: NSColor(stmHex: "#4FACFE")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#00F2FE")!, position: 1)]),
        ("Purple", [ScreenshotGradientStop(color: NSColor(stmHex: "#667EEA")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#764BA2")!, position: 1)]),
        ("Forest", [ScreenshotGradientStop(color: NSColor(stmHex: "#134E5E")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#71B280")!, position: 1)]),
        ("Flame", [ScreenshotGradientStop(color: NSColor(stmHex: "#F093FB")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#F5576C")!, position: 1)]),
        ("Steel", [ScreenshotGradientStop(color: NSColor(stmHex: "#D4FC79")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#96E6A1")!, position: 1)]),
        ("Neon", [ScreenshotGradientStop(color: NSColor(stmHex: "#00D2FF")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#3A7BD5")!, position: 1)]),
        ("Earth", [ScreenshotGradientStop(color: NSColor(stmHex: "#6A3093")!, position: 0), ScreenshotGradientStop(color: NSColor(stmHex: "#A044FF")!, position: 1)])
    ]
}

enum ScreenshotEditorRenderer {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let ciContext = CIContext(options: [.cacheIntermediates: true])

    static func render(
        baseImage: CGImage,
        annotations: [ScreenshotAnnotation],
        backdrop: ScreenshotBackdropSettings,
        includeSelection: UUID? = nil,
        cropRect: CGRect? = nil
    ) -> CGImage? {
        let baseSize = CGSize(width: baseImage.width, height: baseImage.height)
        let padding = backdrop.isEnabled ? max(0, backdrop.padding) : 0
        let outputSize = CGSize(width: baseSize.width + padding * 2, height: baseSize.height + padding * 2)
        guard let context = bitmapContext(width: Int(outputSize.width.rounded()), height: Int(outputSize.height.rounded())) else { return nil }

        context.translateBy(x: 0, y: outputSize.height)
        context.scaleBy(x: 1, y: -1)

        if backdrop.isEnabled {
            drawBackdrop(backdrop, context: context, size: outputSize)
            let imageRect = CGRect(origin: CGPoint(x: padding, y: padding), size: baseSize)
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: backdrop.shadowOffsetX, height: backdrop.shadowOffsetY),
                blur: backdrop.shadowBlur,
                color: backdrop.shadowColor.withAlphaComponent(backdrop.shadowOpacity).cgColor
            )
            context.setFillColor(NSColor.black.withAlphaComponent(min(0.6, max(0, backdrop.shadow / 100))).cgColor)
            context.fill(roundedRect: imageRect, radius: backdrop.innerRadius)
            context.restoreGState()
            context.saveGState()
            context.addPath(CGPath(roundedRect: imageRect, cornerWidth: backdrop.innerRadius, cornerHeight: backdrop.innerRadius, transform: nil))
            context.clip()
            drawImage(baseImage, in: imageRect, context: context)
            context.restoreGState()
        } else {
            drawImage(baseImage, in: CGRect(origin: .zero, size: baseSize), context: context)
        }

        for annotation in annotations where annotation.tool != .crop && annotation.tool != .backdrop {
            draw(annotation, in: context, baseImage: baseImage, offset: CGPoint(x: padding, y: padding))
            if annotation.id == includeSelection {
                drawSelection(annotation, in: context, offset: CGPoint(x: padding, y: padding))
            }
        }

        if let cropRect {
            drawCropOverlay(cropRect.offsetBy(dx: padding, dy: padding), in: context, canvasSize: outputSize)
        }
        return context.makeImage()
    }

    static func crop(image: CGImage, to topLeftRect: CGRect) -> CGImage? {
        let integral = topLeftRect.standardized.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !integral.isEmpty else { return nil }
        return image.cropping(to: integral)
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func drawBackdrop(_ settings: ScreenshotBackdropSettings, context: CGContext, size: CGSize) {
        context.saveGState()
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: settings.outerRadius, cornerHeight: settings.outerRadius, transform: nil))
        context.clip()
        switch settings.background {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        case .linear(let stops, let angle):
            drawLinearGradient(stops, angle: angle, context: context, size: size)
        case .radial(let stops):
            drawRadialGradient(stops, context: context, size: size)
        case .image:
            if let image = settings.backgroundImage {
                let rendered = blurred(image: image, radius: settings.backgroundImageBlur) ?? image
                drawCoverImage(
                    rendered,
                    context: context,
                    size: size,
                    offset: CGPoint(x: settings.backgroundImageOffsetX, y: settings.backgroundImageOffsetY)
                )
            } else {
                context.setFillColor(NSColor(stmHex: "#1A1A1A")!.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
        context.restoreGState()
    }

    private static func drawLinearGradient(_ stops: [ScreenshotGradientStop], angle: CGFloat, context: CGContext, size: CGSize) {
        let normalized = validStops(stops)
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: normalized.map { $0.color.cgColor } as CFArray,
            locations: normalized.map(\.position)
        ) else { return }
        let radians = angle * .pi / 180
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let half = abs(size.width * cos(radians)) / 2 + abs(size.height * sin(radians)) / 2
        let delta = CGPoint(x: cos(radians) * half, y: sin(radians) * half)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x - delta.x, y: center.y - delta.y),
            end: CGPoint(x: center.x + delta.x, y: center.y + delta.y),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func drawRadialGradient(_ stops: [ScreenshotGradientStop], context: CGContext, size: CGSize) {
        let normalized = validStops(stops)
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: normalized.map { $0.color.cgColor } as CFArray,
            locations: normalized.map(\.position)
        ) else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: hypot(size.width, size.height) / 2,
            options: [.drawsAfterEndLocation]
        )
    }

    private static func validStops(_ stops: [ScreenshotGradientStop]) -> [ScreenshotGradientStop] {
        let sorted = stops.sorted { $0.position < $1.position }
        if sorted.count >= 2 { return sorted }
        return ScreenshotBackdropSettings.gradientPresets[2].1
    }

    private static func drawCoverImage(_ image: CGImage, context: CGContext, size: CGSize, offset: CGPoint) {
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let canvasAspect = size.width / size.height
        var target = CGRect(origin: .zero, size: size)
        if imageAspect > canvasAspect {
            target.size.width = size.height * imageAspect
            target.origin.x = (size.width - target.width) / 2
        } else {
            target.size.height = size.width / imageAspect
            target.origin.y = (size.height - target.height) / 2
        }
        target.origin.x += offset.x
        target.origin.y += offset.y
        drawImage(image, in: target, context: context)
    }

    private static func draw(_ annotation: ScreenshotAnnotation, in context: CGContext, baseImage: CGImage, offset: CGPoint) {
        context.saveGState()
        context.translateBy(x: offset.x, y: offset.y)
        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.tool {
        case .line:
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()
        case .arrow:
            drawArrow(annotation, in: context)
        case .box:
            if annotation.fillOpacity > 0 {
                context.setFillColor(annotation.color.withAlphaComponent(annotation.fillOpacity).cgColor)
                context.fill(annotation.rect)
            }
            context.stroke(annotation.rect)
        case .text:
            drawText(annotation, in: context)
        case .number:
            drawNumber(annotation, in: context)
        case .blur:
            drawEffect(annotation, in: context, effect: .blur(radius: max(2, annotation.strokeWidth)), offset: offset)
        case .pixelate:
            drawEffect(annotation, in: context, effect: .pixelate(scale: max(4, annotation.strokeWidth * 2)), offset: offset)
        case .magnifier:
            drawMagnifier(annotation, in: context, baseImage: baseImage)
        case .crop, .backdrop:
            break
        }
        context.restoreGState()
    }

    private static func drawArrow(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        let angle = atan2(annotation.end.y - annotation.start.y, annotation.end.x - annotation.start.x)
        let head = max(15, annotation.strokeWidth * 2)
        context.beginPath()
        context.move(to: annotation.start)
        context.addLine(to: annotation.end)
        context.strokePath()
        context.beginPath()
        context.move(to: annotation.end)
        context.addLine(to: CGPoint(
            x: annotation.end.x - head * cos(angle - .pi / 6),
            y: annotation.end.y - head * sin(angle - .pi / 6)
        ))
        context.move(to: annotation.end)
        context.addLine(to: CGPoint(
            x: annotation.end.x - head * cos(angle + .pi / 6),
            y: annotation.end.y - head * sin(angle + .pi / 6)
        ))
        context.strokePath()
    }

    private static func drawText(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        let font = CTFontCreateWithName(".AppleSystemUIFont" as CFString, annotation.fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: contrastingColor(for: annotation.color)
        ]
        let attributed = NSAttributedString(string: annotation.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let padding: CGFloat = 8
        let rect = CGRect(
            x: annotation.start.x,
            y: annotation.start.y - annotation.fontSize,
            width: width + padding * 2,
            height: annotation.fontSize + padding * 2
        )
        if let tail = annotation.tailPoint {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dx = tail.x - center.x
            let dy = tail.y - center.y
            let baseWidth = min(rect.width * 0.3, 20)
            let first: CGPoint
            let second: CGPoint
            if abs(dx) > abs(dy) {
                let x = dx > 0 ? rect.maxX : rect.minX
                first = CGPoint(x: x, y: center.y - baseWidth / 2)
                second = CGPoint(x: x, y: center.y + baseWidth / 2)
            } else {
                let y = dy > 0 ? rect.maxY : rect.minY
                first = CGPoint(x: center.x - baseWidth / 2, y: y)
                second = CGPoint(x: center.x + baseWidth / 2, y: y)
            }
            context.setFillColor(annotation.color.cgColor)
            context.move(to: first)
            context.addLine(to: tail)
            context.addLine(to: second)
            context.closePath()
            context.fillPath()
        }

        context.setFillColor(annotation.color.cgColor)
        context.fill(roundedRect: rect, radius: 8)
        context.saveGState()
        context.translateBy(x: rect.midX - width / 2, y: rect.midY + annotation.fontSize * 0.36)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawNumber(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        let radius = max(15, annotation.strokeWidth * 1.5)
        context.setFillColor(annotation.color.cgColor)
        context.fillEllipse(in: CGRect(
            x: annotation.start.x - radius,
            y: annotation.start.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        let font = CTFontCreateWithName(".AppleSystemUIFontBold" as CFString, radius, nil)
        let attributed = NSAttributedString(string: String(annotation.number), attributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let glyphBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.saveGState()
        context.translateBy(
            x: annotation.start.x - glyphBounds.midX,
            y: annotation.start.y + glyphBounds.midY
        )
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private enum ImageEffect {
        case blur(radius: CGFloat)
        case pixelate(scale: CGFloat)
    }

    private static func drawEffect(_ annotation: ScreenshotAnnotation, in context: CGContext, effect: ImageEffect, offset: CGPoint) {
        let rect = annotation.rect.integral
        let snapshotRect = rect.offsetBy(dx: offset.x, dy: offset.y)
        guard rect.width > 1, rect.height > 1, let snapshot = context.makeImage() else { return }
        let cropRect = CGRect(
            x: snapshotRect.minX,
            y: snapshotRect.minY,
            width: snapshotRect.width,
            height: snapshotRect.height
        )
        guard let crop = snapshot.cropping(to: cropRect) else { return }
        let input = CIImage(cgImage: crop)
        let output: CIImage?
        switch effect {
        case .blur(let radius):
            output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: input.extent)
        case .pixelate(let scale):
            output = input.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale]).cropped(to: input.extent)
        }
        guard let output, let rendered = ciContext.createCGImage(output, from: output.extent) else { return }
        drawImage(rendered, in: rect, context: context)
    }

    private static func drawMagnifier(_ annotation: ScreenshotAnnotation, in context: CGContext, baseImage: CGImage) {
        let source = annotation.magnifierSource
        let display = annotation.end
        let sourceRadius = max(12, annotation.magnifierSourceRadius)
        let displayRadius = max(20, annotation.magnifierDisplayRadius)
        let angle = atan2(display.y - source.y, display.x - source.x)
        let sourceEdge = CGPoint(x: source.x + sourceRadius * cos(angle), y: source.y + sourceRadius * sin(angle))
        let displayEdge = CGPoint(x: display.x - displayRadius * cos(angle), y: display.y - displayRadius * sin(angle))

        context.move(to: sourceEdge)
        context.addLine(to: displayEdge)
        context.strokePath()
        let sourceRect = CGRect(x: source.x - sourceRadius, y: source.y - sourceRadius, width: sourceRadius * 2, height: sourceRadius * 2)
        let displayRect = CGRect(x: display.x - displayRadius, y: display.y - displayRadius, width: displayRadius * 2, height: displayRadius * 2)
        let sourcePath = annotation.magnifierSquare
            ? CGPath(rect: sourceRect, transform: nil)
            : CGPath(ellipseIn: sourceRect, transform: nil)
        let displayPath = annotation.magnifierSquare
            ? CGPath(rect: displayRect, transform: nil)
            : CGPath(ellipseIn: displayRect, transform: nil)
        context.addPath(sourcePath)
        context.strokePath()

        context.saveGState()
        context.addPath(displayPath)
        context.clip()
        let sourceCrop = sourceRect.intersection(
            CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        )
        if let crop = baseImage.cropping(to: sourceCrop), sourceCrop.width > 0, sourceCrop.height > 0 {
            context.interpolationQuality = .none
            drawImage(crop, in: displayRect, context: context)
        }
        context.restoreGState()
        context.addPath(displayPath)
        context.strokePath()
    }

    private static func drawSelection(_ annotation: ScreenshotAnnotation, in context: CGContext, offset: CGPoint) {
        context.saveGState()
        context.translateBy(x: offset.x, y: offset.y)
        let cyan = NSColor(stmHex: "#0FFFFF")!
        context.setStrokeColor(cyan.cgColor)
        context.setFillColor(NSColor(stmHex: "#0A0A0A")!.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [5, 5])

        if annotation.tool == .line || annotation.tool == .arrow {
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(NSColor(stmHex: "#6B7280")!.cgColor)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            let anchorRadius: CGFloat = 7
            for point in [annotation.start, annotation.end] {
                let anchor = CGRect(
                    x: point.x - anchorRadius,
                    y: point.y - anchorRadius,
                    width: anchorRadius * 2,
                    height: anchorRadius * 2
                )
                context.fillEllipse(in: anchor)
                context.strokeEllipse(in: anchor)
            }
            context.restoreGState()
            return
        }

        if annotation.tool == .magnifier {
            let sourceRect = CGRect(
                x: annotation.magnifierSource.x - annotation.magnifierSourceRadius,
                y: annotation.magnifierSource.y - annotation.magnifierSourceRadius,
                width: annotation.magnifierSourceRadius * 2,
                height: annotation.magnifierSourceRadius * 2
            )
            let displayRect = CGRect(
                x: annotation.end.x - annotation.magnifierDisplayRadius,
                y: annotation.end.y - annotation.magnifierDisplayRadius,
                width: annotation.magnifierDisplayRadius * 2,
                height: annotation.magnifierDisplayRadius * 2
            )
            if annotation.magnifierSquare {
                context.stroke(sourceRect)
                context.stroke(displayRect)
            } else {
                context.strokeEllipse(in: sourceRect)
                context.strokeEllipse(in: displayRect)
            }
            context.setLineDash(phase: 0, lengths: [])
            for point in [
                CGPoint(x: sourceRect.maxX, y: sourceRect.midY),
                CGPoint(x: displayRect.maxX, y: displayRect.midY)
            ] {
                context.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                context.strokeEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            }
            context.restoreGState()
            return
        }

        let rect = selectionBounds(annotation).insetBy(dx: -5, dy: -5)
        if annotation.tool == .number {
            context.strokeEllipse(in: rect)
        } else {
            context.stroke(rect)
        }
        context.setLineDash(phase: 0, lengths: [])
        for point in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ] {
            context.fill(CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            context.stroke(CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        }
        if annotation.tool == .text {
            let handle = textTailHandlePosition(annotation)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.move(to: CGPoint(x: rect.midX, y: rect.minY))
            context.addLine(to: handle)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor((annotation.tailPoint == nil ? NSColor(stmHex: "#6B7280")! : cyan).cgColor)
            context.fillEllipse(in: CGRect(x: handle.x - 10, y: handle.y - 10, width: 20, height: 20))
            context.setStrokeColor(NSColor.white.cgColor)
            context.strokeEllipse(in: CGRect(x: handle.x - 10, y: handle.y - 10, width: 20, height: 20))
        }
        context.restoreGState()
    }

    static func selectionBounds(_ annotation: ScreenshotAnnotation) -> CGRect {
        switch annotation.tool {
        case .line, .arrow, .box, .blur, .pixelate, .crop:
            return annotation.rect
        case .number:
            let radius = max(15, annotation.strokeWidth * 1.5)
            return CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius, width: radius * 2, height: radius * 2)
        case .text:
            let font = CTFontCreateWithName(".AppleSystemUIFont" as CFString, annotation.fontSize, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: annotation.text, attributes: [.font: font]))
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            return CGRect(x: annotation.start.x, y: annotation.start.y - annotation.fontSize, width: width + 16, height: annotation.fontSize + 16)
        case .magnifier:
            let sourceRect = CGRect(x: annotation.magnifierSource.x - annotation.magnifierSourceRadius, y: annotation.magnifierSource.y - annotation.magnifierSourceRadius, width: annotation.magnifierSourceRadius * 2, height: annotation.magnifierSourceRadius * 2)
            let displayRect = CGRect(x: annotation.end.x - annotation.magnifierDisplayRadius, y: annotation.end.y - annotation.magnifierDisplayRadius, width: annotation.magnifierDisplayRadius * 2, height: annotation.magnifierDisplayRadius * 2)
            return sourceRect.union(displayRect)
        case .backdrop:
            return .zero
        }
    }

    static func textTailHandlePosition(_ annotation: ScreenshotAnnotation) -> CGPoint {
        if let tailPoint = annotation.tailPoint {
            return tailPoint
        }
        let bounds = selectionBounds(annotation)
        return CGPoint(x: bounds.midX, y: bounds.minY - 25)
    }

    private static func drawCropOverlay(_ rect: CGRect, in context: CGContext, canvasSize: CGSize) {
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.58).cgColor)
        context.addRect(CGRect(origin: .zero, size: canvasSize))
        context.addRect(rect)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(rect)
        context.restoreGState()
    }

    private static func blurred(image: CGImage, radius: CGFloat) -> CGImage? {
        guard radius > 0 else { return image }
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: output.extent)
    }

    private static func contrastingColor(for background: NSColor) -> NSColor {
        guard let rgb = background.usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.55 ? .black : .white
    }
}

private extension CGContext {
    func fill(roundedRect rect: CGRect, radius: CGFloat) {
        addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        fillPath()
    }
}
