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
