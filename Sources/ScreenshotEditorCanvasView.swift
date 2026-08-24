import AppKit

final class ScreenshotEditorCanvasView: NSView, NSTextFieldDelegate {
    enum DragMode {
        case none
        case drawing
        case moving(annotation: ScreenshotAnnotation, lastPoint: CGPoint)
        case resizing(annotation: ScreenshotAnnotation, corner: ResizeCorner)
        case lineAnchor(annotation: ScreenshotAnnotation, start: Bool)
        case magnifierSource(annotation: ScreenshotAnnotation)
        case magnifierDisplay(annotation: ScreenshotAnnotation)
        case magnifierSourceResize(annotation: ScreenshotAnnotation)
        case magnifierDisplayResize(annotation: ScreenshotAnnotation)
        case textTail(annotation: ScreenshotAnnotation)
        case backdropImage(lastPoint: CGPoint)
    }

    enum ResizeCorner {
        case northWest
        case northEast
        case southWest
        case southEast
    }

    var baseImage: CGImage {
        didSet { updateFrameForContent(); needsDisplay = true }
    }
    var annotations: [ScreenshotAnnotation] = []
    var backdrop = ScreenshotBackdropSettings() {
        didSet { updateFrameForContent(); needsDisplay = true }
    }
    var currentTool: ScreenshotTool = .arrow
    var currentColor = NSColor.black
    var currentStrokeWidth: CGFloat = 8
    var currentFillOpacity: CGFloat = 0
    var zoom: CGFloat = 1 {
        didSet { updateFrameForContent() }
    }
    private(set) var selectedAnnotation: ScreenshotAnnotation?
    private(set) var cropRect: CGRect?
    private var currentAnnotation: ScreenshotAnnotation?
    private var dragMode: DragMode = .none
    private var nextNumber = 1
    private var textField: NSTextField?
    private var editingText: ScreenshotAnnotation?

    var onSelectionChanged: ((ScreenshotAnnotation?) -> Void)?
    var onDocumentChanged: (() -> Void)?
    var onBaseImageChanged: (() -> Void)?
    var onCommand: ((ScreenshotEditorCommand) -> Void)?
    var onNotice: ((String) -> Void)?
    var onBackdropChanged: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage) {
        self.baseImage = image
        super.init(frame: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        updateFrameForContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var contentSize: CGSize {
        let padding = backdrop.isEnabled ? backdrop.padding * 2 : 0
        return CGSize(width: CGFloat(baseImage.width) + padding, height: CGFloat(baseImage.height) + padding)
    }

    var canvasOffset: CGPoint {
        let padding = backdrop.isEnabled ? backdrop.padding : 0
        return CGPoint(x: padding, y: padding)
    }

    func updateFrameForContent() {
        frame.size = CGSize(width: contentSize.width * zoom, height: contentSize.height * zoom)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rendered = ScreenshotEditorRenderer.render(
            baseImage: baseImage,
            annotations: annotations + (currentAnnotation.map { [$0] } ?? []),
            backdrop: backdrop,
            includeSelection: selectedAnnotation?.id,
            cropRect: cropRect
        ) else { return }
        let image = NSImage(cgImage: rendered, size: contentSize)
        image.draw(
            in: bounds,
            from: CGRect(origin: .zero, size: contentSize),
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    func bakeBackdrop() {
        guard backdrop.isEnabled,
              let baked = ScreenshotEditorRenderer.render(
                baseImage: baseImage,
                annotations: [],
                backdrop: backdrop
              ) else { return }
        let offset = max(0, backdrop.padding)
        annotations.forEach { $0.offsetBy(dx: offset, dy: offset) }
        var retainedSettings = backdrop
        retainedSettings.isEnabled = false
        baseImage = baked
        backdrop = retainedSettings
        onBaseImageChanged?()
        onDocumentChanged?()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = imagePoint(from: viewPoint)
        if event.clickCount == 2,
           let annotation = annotation(at: point),
           annotation.tool == .text {
            select(annotation)
            beginTextEntry(at: annotation.start, editing: annotation)
            return
        }


        if event.modifierFlags.contains(.shift), backdrop.isEnabled, backdrop.backgroundImage != nil {
            dragMode = .backdropImage(lastPoint: point)
            return
        }

        if let selectedAnnotation {
            if let anchor = lineAnchor(at: point, annotation: selectedAnnotation) {
                dragMode = .lineAnchor(annotation: selectedAnnotation, start: anchor)
                return
            }
            if selectedAnnotation.tool == .text,
               distance(point, ScreenshotEditorRenderer.textTailHandlePosition(selectedAnnotation)) <= 15 {
                dragMode = .textTail(annotation: selectedAnnotation)
                return
            }
            if let corner = resizeCorner(at: point, annotation: selectedAnnotation) {
                dragMode = .resizing(annotation: selectedAnnotation, corner: corner)
                return
            }
            if selectedAnnotation.tool == .magnifier {
                let sourceDistance = distance(point, selectedAnnotation.magnifierSource)
                if abs(sourceDistance - selectedAnnotation.magnifierSourceRadius) <= 12 {
                    dragMode = .magnifierSourceResize(annotation: selectedAnnotation)
                    return
                }
                let displayDistance = distance(point, selectedAnnotation.end)
                if abs(displayDistance - selectedAnnotation.magnifierDisplayRadius) <= 12 {
                    dragMode = .magnifierDisplayResize(annotation: selectedAnnotation)
                    return
                }
            }
            if selectedAnnotation.tool == .magnifier {
                if distance(point, selectedAnnotation.magnifierSource) <= selectedAnnotation.magnifierSourceRadius + 8 {
                    dragMode = .magnifierSource(annotation: selectedAnnotation)
                    return
                }
                if distance(point, selectedAnnotation.end) <= selectedAnnotation.magnifierDisplayRadius + 8 {
                    dragMode = .magnifierDisplay(annotation: selectedAnnotation)
                    return
                }
            }
        }

        if let hit = annotation(at: point) {
            select(hit)
            dragMode = .moving(annotation: hit, lastPoint: point)
            return
        }

        let wasDeselecting = selectedAnnotation != nil
        select(nil)
        if wasDeselecting { return }
        switch currentTool {
        case .text:
            beginTextEntry(at: point, editing: nil)
        case .number:
            let annotation = ScreenshotAnnotation(
                tool: .number,
                start: point,
                end: point,
                color: currentColor,
                strokeWidth: currentStrokeWidth,
                number: nextNumber
            )
            annotations.append(annotation)
            nextNumber += 1
            onDocumentChanged?()
            needsDisplay = true
        case .crop:
            cropRect = CGRect(origin: point, size: .zero)
            dragMode = .drawing
            needsDisplay = true
        case .magnifier:
            let annotation = ScreenshotAnnotation(
                tool: .magnifier,
                start: point,
                end: CGPoint(x: point.x + 150, y: point.y),
                color: currentColor,
                strokeWidth: currentStrokeWidth,
                magnifierSource: point
            )
            currentAnnotation = annotation
            dragMode = .drawing
        case .backdrop:
            break
        default:
            currentAnnotation = ScreenshotAnnotation(
                tool: currentTool,
                start: point,
                end: point,
                color: currentColor,
                strokeWidth: currentStrokeWidth,
                fillOpacity: currentFillOpacity
            )
            dragMode = .drawing
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = clampedImagePoint(from: viewPoint)
        switch dragMode {
        case .none:
            break
        case .drawing:
            if currentTool == .crop, let cropRect {
                self.cropRect = CGRect(x: cropRect.origin.x, y: cropRect.origin.y, width: point.x - cropRect.origin.x, height: point.y - cropRect.origin.y)
            } else {
                currentAnnotation?.end = point
            }
        case .moving(let annotation, let lastPoint):
            annotation.offsetBy(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y)
            dragMode = .moving(annotation: annotation, lastPoint: point)
        case .resizing(let annotation, let corner):
            resize(annotation, corner: corner, to: point)
        case .lineAnchor(let annotation, let start):
            if start { annotation.start = point } else { annotation.end = point }
        case .magnifierSource(let annotation):
            annotation.magnifierSource = point
            annotation.start = point
        case .magnifierDisplay(let annotation):
            annotation.end = point
        case .magnifierSourceResize(let annotation):
            annotation.magnifierSourceRadius = max(12, distance(point, annotation.magnifierSource))
        case .magnifierDisplayResize(let annotation):
            annotation.magnifierDisplayRadius = max(20, distance(point, annotation.end))
        case .textTail(let annotation):
            annotation.tailPoint = point
        case .backdropImage(let lastPoint):
            backdrop.backgroundImageOffsetX += point.x - lastPoint.x
            backdrop.backgroundImageOffsetY += point.y - lastPoint.y
            dragMode = .backdropImage(lastPoint: point)
        }
        onDocumentChanged?()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragMode = .none }
        switch dragMode {
        case .drawing:
            if currentTool == .crop {
                guard let cropRect else { return }
                self.cropRect = cropRect.standardized
                if cropRect.width < 10 || cropRect.height < 10 {
                    self.cropRect = nil
                    onNotice?("Crop area too small")
                }
            } else if let annotation = currentAnnotation {
                currentAnnotation = nil
                if annotation.tool == .magnifier || annotation.rect.width >= 2 || annotation.rect.height >= 2 {
                    annotations.append(annotation)
                    select(annotation)
                    onDocumentChanged?()
                }
            }
        case .moving, .resizing, .lineAnchor, .magnifierSource, .magnifierDisplay,
             .magnifierSourceResize, .magnifierDisplayResize, .textTail:
            onDocumentChanged?()
        case .backdropImage:
            onBackdropChanged?()
        case .none:
            break
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = imagePoint(from: convert(event.locationInWindow, from: nil))
        if let selectedAnnotation, resizeCorner(at: point, annotation: selectedAnnotation) != nil {
            NSCursor.crosshair.set()
        } else if annotation(at: point) != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func keyDown(with event: NSEvent) {
        let modifiers = keyModifiers(event.modifierFlags)
        let key = normalizedKey(for: event)
        if let command = ScreenshotEditorShortcut.command(for: key, modifiers: modifiers) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        let change = event.magnification > 0 ? ScreenshotEditorCommand.zoomIn : .zoomOut
        onCommand?(change)
    }


    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self))
    }


    func selectTool(_ tool: ScreenshotTool) {
        currentTool = tool
        if tool != .crop { cropRect = nil }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func undo() {
        if cropRect != nil {
            cropRect = nil
        } else if !annotations.isEmpty {
            annotations.removeLast()
            renumber()
            select(nil)
        }
        onDocumentChanged?()
        needsDisplay = true
    }

    func deleteSelection() {
        guard let selectedAnnotation, let index = annotations.firstIndex(where: { $0.id == selectedAnnotation.id }) else { return }
        annotations.remove(at: index)
        renumber()
        select(nil)
        onDocumentChanged?()
        needsDisplay = true
    }

    func cancelCrop() {
        cropRect = nil
        needsDisplay = true
    }

    @discardableResult
    func applyCrop() -> Bool {
        guard let cropRect else { return false }
        let rect = cropRect.standardized.intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        guard rect.width >= 10, rect.height >= 10, let cropped = ScreenshotEditorRenderer.crop(image: baseImage, to: rect) else {
            self.cropRect = nil
            onNotice?("Crop area too small")
            return false
        }
        baseImage = cropped
        annotations.forEach { $0.offsetBy(dx: -rect.minX, dy: -rect.minY) }
        annotations.removeAll { !ScreenshotEditorRenderer.selectionBounds($0).intersects(CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height)) }
        self.cropRect = nil
        onBaseImageChanged?()
        onDocumentChanged?()
        needsDisplay = true
        return true
    }

    func setSelectedColor(_ color: NSColor) {
        currentColor = color
        if let selectedAnnotation { selectedAnnotation.color = color }
        onDocumentChanged?()
        needsDisplay = true
    }

    func setSelectedStroke(_ width: CGFloat) {
        currentStrokeWidth = max(1, width)
        if let selectedAnnotation {
            if selectedAnnotation.tool == .text {
                selectedAnnotation.fontSize = currentStrokeWidth * 4
            } else {
                selectedAnnotation.strokeWidth = currentStrokeWidth
            }
        }
        onDocumentChanged?()
        needsDisplay = true
    }

    func adjustStroke(by delta: CGFloat) {
        setSelectedStroke(currentStrokeWidth + delta)
    }

    func adjustFill(by delta: CGFloat) {
        guard let selectedAnnotation, selectedAnnotation.tool == .box else { return }
        selectedAnnotation.fillOpacity = max(0, min(1, selectedAnnotation.fillOpacity + delta))
        currentFillOpacity = selectedAnnotation.fillOpacity
        onDocumentChanged?()
        needsDisplay = true
    }

    func setFillOpacity(_ value: CGFloat) {
        currentFillOpacity = max(0, min(1, value))
        selectedAnnotation?.fillOpacity = currentFillOpacity
        onDocumentChanged?()
        needsDisplay = true
    }

    func toggleMagnifierShape() {
        guard let selectedAnnotation, selectedAnnotation.tool == .magnifier else { return }
        selectedAnnotation.magnifierSquare.toggle()
        onDocumentChanged?()
        needsDisplay = true
    }

    func renderedImage(includeSelection: Bool = false) -> CGImage? {
        ScreenshotEditorRenderer.render(
            baseImage: baseImage,
            annotations: annotations,
            backdrop: backdrop,
            includeSelection: includeSelection ? selectedAnnotation?.id : nil,
            cropRect: nil
        )
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: viewPoint.x / zoom - canvasOffset.x,
            y: viewPoint.y / zoom - canvasOffset.y
        )
    }

    private func clampedImagePoint(from viewPoint: CGPoint) -> CGPoint {
        let point = imagePoint(from: viewPoint)
        return CGPoint(
            x: max(0, min(CGFloat(baseImage.width), point.x)),
            y: max(0, min(CGFloat(baseImage.height), point.y))
        )
    }

    private func annotation(at point: CGPoint) -> ScreenshotAnnotation? {
        for annotation in annotations.reversed() {
            let bounds = ScreenshotEditorRenderer.selectionBounds(annotation).insetBy(dx: -10, dy: -10)
            if bounds.contains(point) { return annotation }
        }
        return nil
    }

    private func select(_ annotation: ScreenshotAnnotation?) {
        selectedAnnotation = annotation
        if let annotation {
            currentColor = annotation.color
            currentStrokeWidth = annotation.tool == .text ? annotation.fontSize / 4 : annotation.strokeWidth
            currentFillOpacity = annotation.fillOpacity
        }
        onSelectionChanged?(annotation)
        needsDisplay = true
    }

    private func resizeCorner(at point: CGPoint, annotation: ScreenshotAnnotation) -> ResizeCorner? {
        guard ![.line, .arrow, .number, .magnifier, .backdrop].contains(annotation.tool) else { return nil }
        let rect = ScreenshotEditorRenderer.selectionBounds(annotation).insetBy(dx: -5, dy: -5)
        let handles: [(ResizeCorner, CGPoint)] = [
            (.northWest, CGPoint(x: rect.minX, y: rect.minY)),
            (.northEast, CGPoint(x: rect.maxX, y: rect.minY)),
            (.southWest, CGPoint(x: rect.minX, y: rect.maxY)),
            (.southEast, CGPoint(x: rect.maxX, y: rect.maxY))
        ]
        return handles.first(where: { distance(point, $0.1) <= 12 })?.0
    }

    private func lineAnchor(at point: CGPoint, annotation: ScreenshotAnnotation) -> Bool? {
        guard annotation.tool == .line || annotation.tool == .arrow else { return nil }
        if distance(point, annotation.start) <= 12 { return true }
        if distance(point, annotation.end) <= 12 { return false }
        return nil
    }

    private func resize(_ annotation: ScreenshotAnnotation, corner: ResizeCorner, to point: CGPoint) {
        let oldRect = ScreenshotEditorRenderer.selectionBounds(annotation)
        switch annotation.tool {
        case .text:
            let anchor: CGPoint
            switch corner {
            case .northWest: anchor = CGPoint(x: oldRect.maxX, y: oldRect.maxY)
            case .northEast: anchor = CGPoint(x: oldRect.minX, y: oldRect.maxY)
            case .southWest: anchor = CGPoint(x: oldRect.maxX, y: oldRect.minY)
            case .southEast: anchor = CGPoint(x: oldRect.minX, y: oldRect.minY)
            }
            let oldDistance = max(1, distance(anchor, CGPoint(x: oldRect.maxX, y: oldRect.maxY)))
            let scale = max(0.25, min(4, distance(anchor, point) / oldDistance))
            annotation.fontSize = max(8, min(200, annotation.fontSize * scale))
        default:
            switch corner {
            case .northWest: annotation.start = point
            case .northEast:
                annotation.start.y = point.y
                annotation.end.x = point.x
            case .southWest:
                annotation.start.x = point.x
                annotation.end.y = point.y
            case .southEast: annotation.end = point
            }
        }
    }

    private func beginTextEntry(at point: CGPoint, editing annotation: ScreenshotAnnotation?) {
        textField?.removeFromSuperview()
        editingText = annotation
        let field = NSTextField(string: annotation?.text ?? "")
        let editorFontSize = annotation?.fontSize ?? max(12, currentStrokeWidth * 4)
        let fontSize = editorFontSize * zoom
        field.font = .systemFont(ofSize: fontSize)
        field.placeholderString = "Type here…"
        field.textColor = contrastingColor(for: annotation?.color ?? currentColor)
        field.backgroundColor = annotation?.color ?? currentColor
        field.isBordered = true
        field.isBezeled = true
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(commitText)
        field.frame = CGRect(
            x: (point.x + canvasOffset.x) * zoom,
            y: (point.y - fontSize / zoom + canvasOffset.y) * zoom,
            width: max(120, CGFloat(field.stringValue.count * 14 + 36)),
            height: fontSize + 20
        )
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
        if annotation != nil { field.selectText(nil) }
    }

    @objc private func commitText() {
        guard let field = textField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingText {
            if value.isEmpty {
                annotations.removeAll { $0.id == editingText.id }
                select(nil)
            } else {
                editingText.text = value
                editingText.color = currentColor
                select(editingText)
            }
        } else if !value.isEmpty {
            let point = imagePoint(from: field.frame.origin)
            let annotation = ScreenshotAnnotation(
                tool: .text,
                start: CGPoint(x: point.x, y: point.y + currentStrokeWidth * 4),
                end: point,
                color: currentColor,
                strokeWidth: currentStrokeWidth,
                text: value,
                fontSize: max(12, currentStrokeWidth * 4)
            )
            annotations.append(annotation)
            select(annotation)
        }
        field.removeFromSuperview()
        textField = nil
        self.editingText = nil
        window?.makeFirstResponder(self)
        onDocumentChanged?()
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    override func cancelOperation(_ sender: Any?) {
        if let field = textField {
            field.removeFromSuperview()
            textField = nil
            editingText = nil
            window?.makeFirstResponder(self)
        } else {
            onCommand?(.escape)
        }
    }


    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }


    private func renumber() {
        var number = 1
        for annotation in annotations where annotation.tool == .number {
            annotation.number = number
            number += 1
        }
        nextNumber = number
    }

    private func normalizedKey(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36, 76: return "return"
        case 51: return "backspace"
        case 53: return "escape"
        case 117: return "delete"
        default: return event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
    }

    private func keyModifiers(_ flags: NSEvent.ModifierFlags) -> ScreenshotEditorKeyModifiers {
        var result: ScreenshotEditorKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func contrastingColor(for background: NSColor) -> NSColor {
        guard let rgb = background.usingColorSpace(.deviceRGB) else { return .white }
        return (0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent) > 0.55 ? .black : .white
    }
}
