import AppKit
import Darwin

@main
struct ScreenshotEditorCoreTests {
    static func main() {
        expect(ScreenshotTool.allCases.map(\.rawValue) == [
            "arrow", "line", "text", "box", "number", "blur", "pixelate", "crop", "magnifier", "backdrop"
        ], "native tool inventory matches the browser editor")

        let preferences = ScreenshotEditorPreferences.defaults
        expect(preferences.maxWidth == 1920, "default max width remains 1920px")
        expect(preferences.format == .jpeg, "default export format remains JPEG")
        expect(preferences.quality == 92, "default export quality remains 92 percent")
        expect(preferences.copyShrink == 2, "default clipboard shrink remains 2x")
        expect(preferences.colorHex == "#DC2626", "default annotation color is red")
        expect(NSColor(stmHex: "#DC2626")?.stmHex == "#DC2626", "annotation color survives an exact sRGB persistence round trip")
        expect(preferences.strokeWidth == 8, "default stroke remains eight pixels")
        expect(preferences.zoom == 1, "default zoom remains 100 percent")

        expect(ScreenshotEditorShortcut.command(for: "a", modifiers: []) == .selectTool(.arrow), "A selects arrow")
        expect(ScreenshotEditorShortcut.command(for: "l", modifiers: []) == .selectTool(.line), "L selects line")
        expect(ScreenshotEditorShortcut.command(for: "t", modifiers: []) == .selectTool(.text), "T selects text")
        expect(ScreenshotEditorShortcut.command(for: "b", modifiers: []) == .selectTool(.box), "B selects box")
        expect(ScreenshotEditorShortcut.command(for: "1", modifiers: []) == .selectTool(.number), "1 selects numbering")
        expect(ScreenshotEditorShortcut.command(for: "r", modifiers: []) == .selectTool(.blur), "R selects blur")
        expect(ScreenshotEditorShortcut.command(for: "p", modifiers: []) == .selectTool(.pixelate), "P selects pixelate")
        expect(ScreenshotEditorShortcut.command(for: "c", modifiers: []) == .selectTool(.crop), "C selects crop")
        expect(ScreenshotEditorShortcut.command(for: "m", modifiers: []) == .selectTool(.magnifier), "M selects magnifier")
        expect(ScreenshotEditorShortcut.command(for: "k", modifiers: []) == .toggleBackdrop, "K toggles backdrop")
        expect(ScreenshotEditorShortcut.command(for: "z", modifiers: [.command]) == .undo, "Command-Z undoes")
        expect(ScreenshotEditorShortcut.command(for: "c", modifiers: [.command]) == .copy, "Command-C copies")
        expect(ScreenshotEditorShortcut.command(for: "s", modifiers: [.command]) == .save, "Command-S saves")
        expect(ScreenshotEditorShortcut.command(for: "w", modifiers: [.command]) == .close, "Command-W closes the editor")
        expect(ScreenshotEditorShortcut.command(for: "escape", modifiers: []) == .escape, "Escape closes or cancels")
        expect(ScreenshotEditorShortcut.command(for: "return", modifiers: []) == .applyCrop, "Return applies crop")
        expect(ScreenshotEditorShortcut.command(for: "delete", modifiers: []) == .deleteSelection, "Delete removes selection")
        expect(ScreenshotEditorShortcut.command(for: "-", modifiers: []) == .decreaseStroke, "minus decreases stroke")
        expect(ScreenshotEditorShortcut.command(for: "=", modifiers: []) == .increaseStroke, "equals increases stroke")
        expect(ScreenshotEditorShortcut.command(for: "[", modifiers: []) == .decreaseFill, "left bracket decreases fill")
        expect(ScreenshotEditorShortcut.command(for: "]", modifiers: []) == .increaseFill, "right bracket increases fill")
        expect(ScreenshotEditorShortcut.command(for: "+", modifiers: [.shift]) == .zoomIn, "Shift-plus zooms in")
        expect(ScreenshotEditorShortcut.command(for: "_", modifiers: [.shift]) == .zoomOut, "Shift-minus zooms out")
        expect(ScreenshotEditorShortcut.command(for: ")", modifiers: [.shift]) == .resetZoom, "Shift-zero resets zoom")

        let copy = ScreenshotExportPlan(
            pixelWidth: 1201,
            pixelHeight: 801,
            requestedFormat: .jpeg,
            quality: 92,
            copyShrink: 2,
            roundedBackdrop: false
        )
        expect(copy.copyPixelSize == CGSize(width: 601, height: 401), "clipboard dimensions use browser-compatible rounded 2x shrink")
        expect(copy.effectiveFormat == .jpeg, "opaque JPEG export remains JPEG")
        expect(copy.qualityFraction == 0.92, "quality converts to ImageIO fraction")

        let rounded = ScreenshotExportPlan(
            pixelWidth: 1200,
            pixelHeight: 800,
            requestedFormat: .jpeg,
            quality: 92,
            copyShrink: 2,
            roundedBackdrop: true
        )
        expect(rounded.effectiveFormat == .png, "rounded backdrop forces PNG transparency")
        expect(rounded.savePixelSize == CGSize(width: 1200, height: 800), "save preserves full rendered resolution")

        expect(approximately(ScreenshotEditorLayout.fitScale(
            content: CGSize(width: 2000, height: 1000),
            viewport: CGSize(width: 1000, height: 800)
        ), 0.488), "wide screenshots scale down to the available editor width")
        expect(ScreenshotEditorLayout.fitScale(
            content: CGSize(width: 1000, height: 500),
            viewport: CGSize(width: 2000, height: 1200)
        ) == 1, "screenshots inside the remembered viewport stay at 100 percent")
        expect(ScreenshotEditorLayout.fitScale(
            content: CGSize(width: 400, height: 300),
            viewport: CGSize(width: 1000, height: 800)
        ) == 1, "small screenshots are never enlarged beyond 100 percent")
        expect(ScreenshotEditorLayout.centeredDocumentOrigin(
            document: CGSize(width: 400, height: 300),
            viewport: CGSize(width: 1000, height: 800),
            proposed: .zero
        ) == CGPoint(x: -300, y: -250), "undersized screenshots center on both axes")
        expect(ScreenshotEditorLayout.centeredDocumentOrigin(
            document: CGSize(width: 1200, height: 300),
            viewport: CGSize(width: 1000, height: 800),
            proposed: CGPoint(x: 80, y: 0)
        ) == CGPoint(x: 80, y: -250), "scrolling stays intact on oversized axes while the other axis centers")

        print("ScreenshotEditorCoreTests: all 43 checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(EXIT_FAILURE)
        }
    }

    private static func approximately(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.0001
    }
}
