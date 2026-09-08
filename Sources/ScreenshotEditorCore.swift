import AppKit
import Foundation

// Browser-parity contract for the native STM Screenshot Editor.
// Keep tool order, shortcut semantics, and export defaults aligned with
// GMB-Extractor/screenshot-editor.html and js/screenshot-editor.js.
enum ScreenshotTool: String, CaseIterable {
    case arrow
    case line
    case text
    case box
    case number
    case blur
    case pixelate
    case crop
    case magnifier
    case backdrop

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .text: return "Text"
        case .box: return "Rectangle"
        case .number: return "Number"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .crop: return "Crop"
        case .magnifier: return "Magnifier"
        case .backdrop: return "Backdrop"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .arrow: return "A"
        case .line: return "L"
        case .text: return "T"
        case .box: return "B"
        case .number: return "1"
        case .blur: return "R"
        case .pixelate: return "P"
        case .crop: return "C"
        case .magnifier: return "M"
        case .backdrop: return "K"
        }
    }
}

enum ScreenshotExportFormat: String, CaseIterable {
    case jpeg
    case webp
    case png

    var displayName: String {
        switch self {
        case .jpeg: return "JPG"
        case .webp: return "WebP"
        case .png: return "PNG"
        }
    }

    var fileExtension: String {
        self == .jpeg ? "jpg" : rawValue
    }
}

struct ScreenshotEditorPreferences: Equatable {
    var maxWidth: Int
    var format: ScreenshotExportFormat
    var quality: Int
    var copyShrink: Int
    var colorHex: String
    var strokeWidth: CGFloat
    var zoom: CGFloat
    var defaultTool: ScreenshotTool

    static let defaults = ScreenshotEditorPreferences(
        maxWidth: 1920,
        format: .jpeg,
        quality: 92,
        copyShrink: 2,
        colorHex: "#DC2626",
        strokeWidth: 8,
        zoom: 1,
        defaultTool: .arrow
    )
}

struct ScreenshotExportPlan {
    let pixelWidth: Int
    let pixelHeight: Int
    let requestedFormat: ScreenshotExportFormat
    let quality: Int
    let copyShrink: Int
    let roundedBackdrop: Bool

    var effectiveFormat: ScreenshotExportFormat {
        requestedFormat == .jpeg && roundedBackdrop ? .png : requestedFormat
    }

    var qualityFraction: CGFloat {
        CGFloat(max(10, min(100, quality))) / 100
    }

    var savePixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    var copyPixelSize: CGSize {
        let shrink = max(1, min(4, copyShrink))
        return CGSize(
            width: Int((Double(pixelWidth) / Double(shrink)).rounded()),
            height: Int((Double(pixelHeight) / Double(shrink)).rounded())
        )
    }
}

enum ScreenshotEditorLayout {
    static func fitScale(
        content: CGSize,
        viewport: CGSize,
        margin: CGFloat = 24
    ) -> CGFloat {
        guard content.width > 0, content.height > 0, viewport.width > 0, viewport.height > 0 else {
            return 1
        }
        let horizontalFit = max(1, viewport.width - margin) / content.width
        let verticalFit = max(1, viewport.height - margin) / content.height
        return max(0.1, min(1, horizontalFit, verticalFit))
    }

    static func centeredDocumentOrigin(
        document: CGSize,
        viewport: CGSize,
        proposed: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: document.width < viewport.width ? -(viewport.width - document.width) / 2 : proposed.x,
            y: document.height < viewport.height ? -(viewport.height - document.height) / 2 : proposed.y
        )
    }
}

struct ScreenshotEditorKeyModifiers: OptionSet {
    let rawValue: Int

    static let command = ScreenshotEditorKeyModifiers(rawValue: 1 << 0)
    static let control = ScreenshotEditorKeyModifiers(rawValue: 1 << 1)
    static let option = ScreenshotEditorKeyModifiers(rawValue: 1 << 2)
    static let shift = ScreenshotEditorKeyModifiers(rawValue: 1 << 3)
}

enum ScreenshotEditorCommand: Equatable {
    case selectTool(ScreenshotTool)
    case toggleBackdrop
    case undo
    case copy
    case save
    case close
    case escape
    case applyCrop
    case deleteSelection
    case decreaseStroke
    case increaseStroke
    case decreaseFill
    case increaseFill
    case zoomIn
    case zoomOut
    case resetZoom
}

enum ScreenshotEditorShortcut {
    static func command(for key: String, modifiers: ScreenshotEditorKeyModifiers) -> ScreenshotEditorCommand? {
        let normalized = key.lowercased()
        let primary = modifiers.contains(.command) || modifiers.contains(.control)

        if primary {
            switch normalized {
            case "z": return .undo
            case "c": return .copy
            case "s": return .save
            case "w" where modifiers.contains(.command): return .close
            default: return nil
            }
        }

        if modifiers.contains(.shift) {
            switch normalized {
            case "+", "=": return .zoomIn
            case "_", "-": return .zoomOut
            case ")", "0": return .resetZoom
            default: break
            }
        }

        switch normalized {
        case "a": return .selectTool(.arrow)
        case "l": return .selectTool(.line)
        case "t": return .selectTool(.text)
        case "b": return .selectTool(.box)
        case "1": return .selectTool(.number)
        case "r": return .selectTool(.blur)
        case "p": return .selectTool(.pixelate)
        case "c": return .selectTool(.crop)
        case "m": return .selectTool(.magnifier)
        case "k": return .toggleBackdrop
        case "escape": return .escape
        case "return", "enter": return .applyCrop
        case "delete", "backspace": return .deleteSelection
        case "-": return .decreaseStroke
        case "=": return .increaseStroke
        case "[": return .decreaseFill
        case "]": return .increaseFill
        default: return nil
        }
    }
}

final class ScreenshotAnnotation {
    let id: UUID
    let tool: ScreenshotTool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var strokeWidth: CGFloat
    var fillOpacity: CGFloat
    var text: String
    var number: Int
    var rotation: CGFloat
    var fontSize: CGFloat
    var tailPoint: CGPoint?
    var magnifierSource: CGPoint
    var magnifierSourceRadius: CGFloat
    var magnifierDisplayRadius: CGFloat
    var magnifierSquare: Bool

    init(
        id: UUID = UUID(),
        tool: ScreenshotTool,
        start: CGPoint,
        end: CGPoint,
        color: NSColor,
        strokeWidth: CGFloat,
        fillOpacity: CGFloat = 0,
        text: String = "",
        number: Int = 0,
        rotation: CGFloat = 0,
        fontSize: CGFloat = 32,
        tailPoint: CGPoint? = nil,
        magnifierSource: CGPoint? = nil,
        magnifierSourceRadius: CGFloat = 48,
        magnifierDisplayRadius: CGFloat = 78,
        magnifierSquare: Bool = false
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
        self.fillOpacity = fillOpacity
        self.text = text
        self.number = number
        self.rotation = rotation
        self.fontSize = fontSize
        self.tailPoint = tailPoint
        self.magnifierSource = magnifierSource ?? start
        self.magnifierSourceRadius = magnifierSourceRadius
        self.magnifierDisplayRadius = magnifierDisplayRadius
        self.magnifierSquare = magnifierSquare
    }

    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) {
        start.x += dx
        start.y += dy
        end.x += dx
        end.y += dy
        magnifierSource.x += dx
        magnifierSource.y += dy
        if var tailPoint {
            tailPoint.x += dx
            tailPoint.y += dy
            self.tailPoint = tailPoint
        }
    }
}

/// Shottr-parity callout tail geometry for text annotations. Pure functions; image coordinates with y down.
enum ScreenshotCalloutGeometry {
    static let cornerRadius: CGFloat = 8
    /// Tips this close to the box (or inside it) collapse back to a flat box.
    static let flatThreshold: CGFloat = 4

    enum Side { case top, bottom, left, right }

    /// Returns nil when the tip is inside or hugging the box, meaning the callout renders flat.
    static func normalizedTip(rect: CGRect, tip: CGPoint) -> CGPoint? {
        rect.insetBy(dx: -flatThreshold, dy: -flatThreshold).contains(tip) ? nil : tip
    }

    /// Where the pull handle sits: flush on the bottom edge when flat, at the tip when tailed.
    static func nubPosition(rect: CGRect, tip: CGPoint?) -> CGPoint {
        if let tip, let tip = normalizedTip(rect: rect, tip: tip) { return tip }
        return CGPoint(x: rect.midX, y: rect.maxY)
    }

    /// Side of the box facing the tip, comparing the tip offset normalized by the box half-extents so
    /// wide boxes attach on top/bottom unless the tip is clearly beside them.
    static func attachedSide(rect: CGRect, tip: CGPoint) -> Side {
        let nx = (tip.x - rect.midX) / max(rect.width / 2, 1)
        let ny = (tip.y - rect.midY) / max(rect.height / 2, 1)
        if abs(nx) > abs(ny) {
            return nx > 0 ? .right : .left
        }
        return ny > 0 ? .bottom : .top
    }

    /// Filled blob tail: wide curved base that flares out of the box, concave sides tapering to the tip.
    /// Nil when the callout is flat. The base is extended slightly into the box so the union with the
    /// rounded rect has no anti-aliasing seam.
    static func tailPath(rect: CGRect, tip rawTip: CGPoint) -> CGPath? {
        guard let tip = normalizedTip(rect: rect, tip: rawTip) else { return nil }
        let side = attachedSide(rect: rect, tip: tip)
        let normal: CGPoint
        let tangent: CGPoint
        let edgeLength: CGFloat
        var baseCenter: CGPoint
        switch side {
        case .top:
            normal = CGPoint(x: 0, y: -1); tangent = CGPoint(x: 1, y: 0); edgeLength = rect.width
            baseCenter = CGPoint(x: tip.x, y: rect.minY)
        case .bottom:
            normal = CGPoint(x: 0, y: 1); tangent = CGPoint(x: 1, y: 0); edgeLength = rect.width
            baseCenter = CGPoint(x: tip.x, y: rect.maxY)
        case .left:
            normal = CGPoint(x: -1, y: 0); tangent = CGPoint(x: 0, y: 1); edgeLength = rect.height
            baseCenter = CGPoint(x: rect.minX, y: tip.y)
        case .right:
            normal = CGPoint(x: 1, y: 0); tangent = CGPoint(x: 0, y: 1); edgeLength = rect.height
            baseCenter = CGPoint(x: rect.maxX, y: tip.y)
        }
        let tailLength = hypot(tip.x - baseCenter.x, tip.y - baseCenter.y)
        let baseWidth = max(18, min(0.6 * edgeLength, 30 + 0.22 * tailLength))

        // Slide the base along the edge toward the tip, keeping clear of the rounded corners.
        let edgeMin = (side == .top || side == .bottom ? rect.minX : rect.minY) + cornerRadius + baseWidth / 2
        let edgeMax = (side == .top || side == .bottom ? rect.maxX : rect.maxY) - cornerRadius - baseWidth / 2
        let along = min(max(side == .top || side == .bottom ? baseCenter.x : baseCenter.y, edgeMin), max(edgeMin, edgeMax))
        if side == .top || side == .bottom { baseCenter.x = along } else { baseCenter.y = along }

        let inset: CGFloat = 3
        let half = baseWidth / 2
        let b1 = CGPoint(x: baseCenter.x - tangent.x * half - normal.x * inset, y: baseCenter.y - tangent.y * half - normal.y * inset)
        let b2 = CGPoint(x: baseCenter.x + tangent.x * half - normal.x * inset, y: baseCenter.y + tangent.y * half - normal.y * inset)

        // Concave sides: pull each control point toward the tail centerline.
        func control(from base: CGPoint) -> CGPoint {
            let onSide = CGPoint(x: base.x + (tip.x - base.x) * 0.3, y: base.y + (tip.y - base.y) * 0.3)
            let onCenter = CGPoint(x: baseCenter.x + (tip.x - baseCenter.x) * 0.3, y: baseCenter.y + (tip.y - baseCenter.y) * 0.3)
            return CGPoint(x: onSide.x + (onCenter.x - onSide.x) * 0.75, y: onSide.y + (onCenter.y - onSide.y) * 0.75)
        }

        let path = CGMutablePath()
        path.move(to: b1)
        path.addQuadCurve(to: tip, control: control(from: b1))
        path.addQuadCurve(to: b2, control: control(from: b2))
        path.closeSubpath()
        return path
    }
}

extension NSColor {
    convenience init?(stmHex: String) {
        let cleaned = stmHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    var stmHex: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#DC2626" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
