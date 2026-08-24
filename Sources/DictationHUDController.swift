import Cocoa

final class DictationHUDController {
    private enum Keys {
        static let x = "dictationHUD.x"
        static let y = "dictationHUD.y"
        static let width = "dictationHUD.width"
        static let height = "dictationHUD.height"
        static let minimized = "dictationHUD.minimized"
    }

    private static let defaultSize = NSSize(width: 200, height: 42)
    private static let minimizedSize = NSSize(width: 44, height: 24)

    private let panel: NSPanel
    private let meterView: DictationMeterView
    private var normalFrame: NSRect
    private var isMinimized: Bool

    init() {
        let savedSize = NSSize(
            width: ConfigStore.double(Keys.width, default: Self.defaultSize.width),
            height: ConfigStore.double(Keys.height, default: Self.defaultSize.height)
        )
        let safeSize = NSSize(
            width: min(max(savedSize.width, 140), 420),
            height: min(max(savedSize.height, 34), 100)
        )
        let savedX = ConfigStore.double(Keys.x, default: .nan)
        let savedY = ConfigStore.double(Keys.y, default: .nan)
        let defaultScreen = NSScreen.main ?? NSScreen.screens.first
        let defaultOrigin = NSPoint(
            x: (defaultScreen?.visibleFrame.midX ?? safeSize.width / 2) - safeSize.width / 2,
            y: (defaultScreen?.visibleFrame.minY ?? 0) + 18
        )
        normalFrame = NSRect(
            origin: NSPoint(
                x: savedX.isFinite ? savedX : defaultOrigin.x,
                y: savedY.isFinite ? savedY : defaultOrigin.y
            ),
            size: safeSize
        )
        isMinimized = ConfigStore.bool(Keys.minimized, default: false)
        let initialFrame = NSRect(
            origin: normalFrame.origin,
            size: isMinimized ? Self.minimizedSize : normalFrame.size
        )

        meterView = DictationMeterView(frame: NSRect(origin: .zero, size: initialFrame.size))
        panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = meterView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.setFrame(constrained(initialFrame), display: false)
        if isMinimized {
            normalFrame.origin = panel.frame.origin
        } else {
            normalFrame = panel.frame
        }
        meterView.setMinimized(isMinimized)
        wireInteractions()
    }

    func showRecording() {
        meterView.setMode(.recording)
        ensureVisible()
        panel.orderFrontRegardless()
    }

    func showProcessing() {
        meterView.setMode(.processing)
        ensureVisible()
        panel.orderFrontRegardless()
    }

    func updateLevel(_ level: CGFloat) {
        meterView.updateLevel(level)
    }

    func hide() {
        panel.orderOut(nil)
        meterView.setMode(.idle)
    }

    func position() {
        let constrainedFrame = constrained(panel.frame)
        panel.setFrame(constrainedFrame, display: true)
        if !isMinimized {
            normalFrame = constrainedFrame
        }
        persistGeometry()
    }

    private func wireInteractions() {
        meterView.onFrameChange = { [weak self] proposedFrame in
            guard let self else { return }
            let frame = self.constrained(proposedFrame)
            self.panel.setFrame(frame, display: true)
            if !self.isMinimized {
                self.normalFrame = frame
            }
        }
        meterView.onFrameChangeEnded = { [weak self] in
            self?.persistGeometry()
        }
        meterView.onMinimizeToggle = { [weak self] in
            self?.toggleMinimized()
        }
    }

    private func toggleMinimized() {
        if isMinimized {
            isMinimized = false
            let restored = constrained(normalFrame)
            panel.setFrame(restored, display: true, animate: true)
        } else {
            normalFrame = panel.frame
            isMinimized = true
            let compactFrame = NSRect(origin: panel.frame.origin, size: Self.minimizedSize)
            panel.setFrame(constrained(compactFrame), display: true, animate: true)
        }
        meterView.setMinimized(isMinimized)
        persistGeometry()
    }

    private func ensureVisible() {
        panel.setFrame(constrained(panel.frame), display: false)
    }

    private func constrained(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    private func persistGeometry() {
        let frame = normalFrame
        try? ConfigStore.set(Double(frame.origin.x), for: Keys.x)
        try? ConfigStore.set(Double(frame.origin.y), for: Keys.y)
        try? ConfigStore.set(Double(frame.width), for: Keys.width)
        try? ConfigStore.set(Double(frame.height), for: Keys.height)
        try? ConfigStore.set(isMinimized, for: Keys.minimized)
    }
}

private final class DictationMeterView: NSView {
    enum Mode {
        case idle
        case recording
        case processing
    }

    private enum DragMode {
        case moving
        case resizing
    }

    private static let barCount = 31
    private var mode: Mode = .idle
    private var targetLevel: CGFloat = 0
    private var displayedLevel: CGFloat = 0
    private var levelHistory = Array(repeating: CGFloat(0.04), count: barCount)
    private var historyCursor = 0
    private var sampleTick = 0
    private var phase: CGFloat = 0
    private var timer: Timer?
    private var trackingArea: NSTrackingArea?
    private var hovered = false
    private var minimized = false
    private var dragMode: DragMode?
    private var dragStartMouse = NSPoint.zero
    private var dragStartFrame = NSRect.zero

    var onFrameChange: ((NSRect) -> Void)?
    var onFrameChangeEnded: (() -> Void)?
    var onMinimizeToggle: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.20, alpha: 0.75).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !minimized else {
            addCursorRect(bounds, cursor: .pointingHand)
            return
        }
        addCursorRect(resizeHandleRect.insetBy(dx: -4, dy: -4), cursor: .crosshair)
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        if minimized || minimizeButtonRect.contains(convert(event.locationInWindow, from: nil)) {
            onMinimizeToggle?()
            return
        }
        guard let window else { return }
        dragMode = resizeHandleRect.contains(convert(event.locationInWindow, from: nil)) ? .resizing : .moving
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window.frame
        if dragMode == .moving {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode else { return }
        let mouse = NSEvent.mouseLocation
        let deltaX = mouse.x - dragStartMouse.x
        let deltaY = mouse.y - dragStartMouse.y
        var frame = dragStartFrame
        switch dragMode {
        case .moving:
            frame.origin.x += deltaX
            frame.origin.y += deltaY
        case .resizing:
            frame.size.width = min(max(dragStartFrame.width + deltaX, 140), 420)
            let height = min(max(dragStartFrame.height - deltaY, 34), 100)
            frame.origin.y = dragStartFrame.maxY - height
            frame.size.height = height
        }
        onFrameChange?(frame)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragMode != nil else { return }
        dragMode = nil
        window?.invalidateCursorRects(for: self)
        onFrameChangeEnded?()
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        if case .idle = newMode {
            timer?.invalidate()
            timer = nil
            targetLevel = 0
            displayedLevel = 0
            levelHistory = Array(repeating: 0.04, count: Self.barCount)
            historyCursor = 0
            sampleTick = 0
            phase = 0
            needsDisplay = true
            return
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            if let timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        needsDisplay = true
    }

    func setMinimized(_ minimized: Bool) {
        self.minimized = minimized
        layer?.cornerRadius = minimized ? 10 : 14
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func updateLevel(_ level: CGFloat) {
        targetLevel = min(max(level, 0), 1)
    }

    private func tick() {
        switch mode {
        case .idle:
            return
        case .recording:
            let response: CGFloat = targetLevel > displayedLevel ? 0.62 : 0.14
            displayedLevel += (targetLevel - displayedLevel) * response
            targetLevel *= 0.90
            sampleTick += 1
            if sampleTick == 4 {
                levelHistory[historyCursor] = max(0.04, min(1, displayedLevel * 1.45))
                historyCursor = (historyCursor + 1) % Self.barCount
                sampleTick = 0
            }
        case .processing:
            phase += 0.16
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGradient(colors: [
            NSColor(calibratedWhite: 0.065, alpha: 0.98),
            NSColor(calibratedWhite: 0.012, alpha: 0.98)
        ])?.draw(in: bounds, angle: 90)

        if minimized {
            drawMinimizedIndicator()
            return
        }
        guard mode != .idle else { return }

        let baseColor: NSColor
        switch mode {
        case .recording:
            baseColor = .white
        case .processing:
            baseColor = NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1)
        case .idle:
            return
        }

        let barWidth: CGFloat = 2
        let horizontalPadding: CGFloat = 20
        let usableWidth = max(80, bounds.width - horizontalPadding * 2)
        let gap = max(1.5, (usableWidth - CGFloat(Self.barCount) * barWidth) / CGFloat(Self.barCount - 1))
        let totalWidth = CGFloat(Self.barCount) * barWidth + CGFloat(Self.barCount - 1) * gap
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.midY
        let maximumBarHeight = max(16, bounds.height - 10)

        for index in 0..<Self.barCount {
            let normalized = CGFloat(index) / CGFloat(Self.barCount - 1)
            let edgeFade = 0.28 + 0.72 * sin(normalized * .pi)
            baseColor.withAlphaComponent(edgeFade).setFill()
            let activity: CGFloat
            switch mode {
            case .recording:
                let historyIndex = (historyCursor + index) % Self.barCount
                activity = levelHistory[historyIndex]
            case .processing:
                activity = 0.24 + 0.66 * (0.5 + 0.5 * sin(phase - CGFloat(index) * 0.34))
            case .idle:
                activity = 0
            }
            let height = min(maximumBarHeight, 3 + activity * (maximumBarHeight - 3))
            let rect = NSRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: centerY - height / 2,
                width: barWidth,
                height: height
            )
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }

        guard hovered else { return }
        drawHoverControls()
    }

    private var minimizeButtonRect: NSRect {
        NSRect(x: bounds.maxX - 17, y: 4, width: 12, height: 12)
    }

    private var resizeHandleRect: NSRect {
        NSRect(x: bounds.maxX - 13, y: bounds.maxY - 13, width: 9, height: 9)
    }

    private func drawHoverControls() {
        NSColor(calibratedWhite: 0.72, alpha: 0.75).setStroke()
        let minus = NSBezierPath()
        minus.lineWidth = 1.2
        minus.move(to: NSPoint(x: minimizeButtonRect.minX + 2, y: minimizeButtonRect.midY))
        minus.line(to: NSPoint(x: minimizeButtonRect.maxX - 2, y: minimizeButtonRect.midY))
        minus.stroke()

        let handle = NSBezierPath()
        handle.lineWidth = 1
        handle.move(to: NSPoint(x: resizeHandleRect.minX + 2, y: resizeHandleRect.maxY - 1))
        handle.line(to: NSPoint(x: resizeHandleRect.maxX - 1, y: resizeHandleRect.minY + 2))
        handle.move(to: NSPoint(x: resizeHandleRect.minX + 5, y: resizeHandleRect.maxY - 1))
        handle.line(to: NSPoint(x: resizeHandleRect.maxX - 1, y: resizeHandleRect.minY + 5))
        handle.stroke()
    }

    private func drawMinimizedIndicator() {
        let color: NSColor
        switch mode {
        case .processing:
            color = NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1)
        case .recording:
            color = .white
        case .idle:
            color = NSColor(calibratedWhite: 0.65, alpha: 1)
        }
        color.setFill()
        let heights: [CGFloat] = [5, 11, 16, 9, 6]
        let startX = bounds.midX - 9
        for (index, height) in heights.enumerated() {
            let rect = NSRect(x: startX + CGFloat(index) * 4, y: bounds.midY - height / 2, width: 2, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }
}
