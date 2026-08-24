import Cocoa
import Carbon

final class SelectionOverlayController {
    private var windows: [OverlayWindow] = []
    private var completion: ((CGRect?) -> Void)?
    private var active = false
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var failsafeTimer: Timer?
    private var holdAfterSelection = false
    private var lastEscapeAt: Date?

    var isActive: Bool {
        active
    }


    private func makeWindow(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    func start(
        label: String,
        snapshots: [ScreenSnapshot] = [],
        holdAfterSelection: Bool = false,
        completion: @escaping (CGRect?) -> Void
    ) {
        cancel(notify: true)
        let started = Date()
        self.completion = completion
        self.holdAfterSelection = holdAfterSelection
        for screen in NSScreen.screens {
            let window = makeWindow(for: screen)
            let snapshot = snapshots.first { $0.screenFrame.intersects(screen.frame) }
            let contentView = SelectionOverlayContentView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                label: label,
                frozenImage: snapshot?.image
            )
            let view = contentView.selectionView
            view.onComplete = { [weak self] rect in self?.finish(rect) }
            view.onCancel = { [weak self] in self?.finish(nil) }
            window.contentView = contentView
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        active = true
        installEscapeFallbacks()
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Logger.log("selection overlay ready ms=\(elapsed) windows=\(windows.count) frozen=\(!snapshots.isEmpty) escapeFallback=true")
    }

    func cancel(notify: Bool = false) {
        guard active || completion != nil || !windows.isEmpty else { return }
        let callback = completion
        cleanupOverlay()
        if notify {
            callback?(nil)
        }
    }

    private func finish(_ rect: CGRect?) {
        let callback = completion
        if rect != nil && holdAfterSelection {
            completion = nil
            active = false
            windows.forEach { $0.ignoresMouseEvents = true }
            removeEscapeFallbacks()
            DispatchQueue.main.async {
                callback?(rect)
            }
            return
        }
        cleanupOverlay()
        DispatchQueue.main.async {
            callback?(rect)
        }
    }

    private func cleanupOverlay() {
        let retiredWindows = windows
        windows.removeAll()
        retiredWindows.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
            $0.close()
        }
        completion = nil
        active = false
        holdAfterSelection = false
        removeEscapeFallbacks()
    }

    func dismissHeldOverlay() {
        guard !windows.isEmpty else { return }
        cleanupOverlay()
        Logger.log("selection overlay handoff dismissed")
    }

    private func installEscapeFallbacks() {
        removeEscapeFallbacks()
        lastEscapeAt = nil
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.escapeFallback(source: "local")
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async {
                    self?.escapeFallback(source: "global")
                }
            }
        }
        failsafeTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
            guard let self = self, self.active else { return }
            Logger.log("selection overlay failsafe auto-cancel after 90s")
            self.cancel(notify: true)
        }
        if let failsafeTimer = failsafeTimer {
            RunLoop.main.add(failsafeTimer, forMode: .common)
        }
    }

    private func escapeFallback(source: String) {
        guard active else { return }
        let now = Date()
        let doublePress = lastEscapeAt.map { now.timeIntervalSince($0) < 1.5 } ?? false
        lastEscapeAt = now
        Logger.log("selection overlay escape cancel source=\(source) doublePress=\(doublePress)")
        cancel(notify: true)
    }

    private func removeEscapeFallbacks() {
        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        failsafeTimer?.invalidate()
        localKeyMonitor = nil
        globalKeyMonitor = nil
        failsafeTimer = nil
        lastEscapeAt = nil
    }
}

final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayContentView: NSView {
    let selectionView: SelectionOverlayView

    init(frame: CGRect, screenFrame: CGRect, label: String, frozenImage: CGImage?) {
        selectionView = SelectionOverlayView(
            frame: frame,
            screenFrame: screenFrame,
            label: label,
            hasFrozenImage: frozenImage != nil
        )
        super.init(frame: frame)
        autoresizingMask = [.width, .height]

        if let frozenImage {
            let imageView = NSImageView(frame: bounds)
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleAxesIndependently
            imageView.image = NSImage(cgImage: frozenImage, size: frame.size)
            addSubview(imageView)
        }

        selectionView.autoresizingMask = [.width, .height]
        addSubview(selectionView)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class SelectionOverlayView: NSView {
    let screenFrame: CGRect
    let label: String
    let hasFrozenImage: Bool
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    init(frame: CGRect, screenFrame: CGRect, label: String, hasFrozenImage: Bool) {
        self.screenFrame = screenFrame
        self.label = label
        self.hasFrozenImage = hasFrozenImage
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: hasFrozenImage ? 0.22 : 0.28).setFill()
        bounds.fill()

        if let rect = localSelectionRect() {
            if hasFrozenImage {
                NSColor.clear.setFill()
                rect.fill(using: .copy)
            }
            NSColor.systemCyan.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()

            let text = "\(Int(rect.width)) x \(Int(rect.height))"
            drawLabel(text, at: CGPoint(x: rect.maxX + 8, y: rect.minY - 24))
        } else {
            drawLabel(label, at: CGPoint(x: 24, y: bounds.height - 44))
        }
    }

    private func selectionDisplayRect(_ rect: CGRect) -> CGRect {
        let sizeLabel = CGRect(x: rect.maxX + 4, y: rect.minY - 30, width: 140, height: 34)
        return rect.union(sizeLabel).insetBy(dx: -4, dy: -4)
    }

    private func updateDrag(to point: CGPoint) {
        let previous = localSelectionRect()
        current = point
        guard let previous, let current = localSelectionRect() else {
            needsDisplay = true
            return
        }
        setNeedsDisplay(selectionDisplayRect(previous).union(selectionDisplayRect(current)))
    }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(to: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        current = event.locationInWindow
        guard let rect = globalSelectionRect(), rect.width >= 4, rect.height >= 4 else {
            onCancel?()
            return
        }
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        }
    }

    private func localSelectionRect() -> CGRect? {
        guard let start = start, let current = current else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    private func globalSelectionRect() -> CGRect? {
        guard let local = localSelectionRect() else { return nil }
        return CGRect(
            x: screenFrame.minX + local.minX,
            y: screenFrame.minY + local.minY,
            width: local.width,
            height: local.height
        )
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(calibratedWhite: 0, alpha: 0.75)
        ]
        text.draw(at: point, withAttributes: attrs)
    }
}

final class MeasurementOverlayController {
    private var windows: [MeasurementOverlayWindow] = []
    private var selectedRect: CGRect?
    private var selectedScreenFrame: CGRect?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    var captureRect: CGRect? {
        guard let rect = selectedRect,
              let screenFrame = selectedScreenFrame else {
            return nil
        }
        let outlinePadding: CGFloat = 18
        let labelRect = CGRect(x: rect.minX, y: rect.maxY + 4, width: max(rect.width, 260), height: 36)
        let expanded = rect.insetBy(dx: -outlinePadding, dy: -outlinePadding).union(labelRect)
        return expanded.intersection(screenFrame)
    }

    func show(rect: CGRect, text: String) {
        clear()
        selectedRect = rect
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main else {
            return
        }
        selectedScreenFrame = screen.frame
        let window = MeasurementOverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = MeasurementOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame, rect: rect, text: text)
        window.contentView = view
        window.orderFrontRegardless()
        windows.append(window)
        installEscapeMonitors()
    }

    func clear() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        selectedRect = nil
        selectedScreenFrame = nil
        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        localKeyMonitor = nil
        globalKeyMonitor = nil
    }

    private func installEscapeMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.clear()
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async {
                    self?.clear()
                }
            }
        }
    }
}

final class MeasurementOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MeasurementOverlayView: NSView {
    let screenFrame: CGRect
    let rect: CGRect
    let text: String

    init(frame: CGRect, screenFrame: CGRect, rect: CGRect, text: String) {
        self.screenFrame = screenFrame
        self.rect = rect
        self.text = text
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let local = CGRect(
            x: rect.minX - screenFrame.minX,
            y: rect.minY - screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
        NSColor.systemCyan.setStroke()
        let path = NSBezierPath(rect: local)
        path.lineWidth = 2
        path.stroke()
        drawLabel(text, at: CGPoint(x: local.minX, y: local.maxY + 8))
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(calibratedWhite: 0, alpha: 0.78),
            .paragraphStyle: paragraph
        ]
        text.draw(in: CGRect(x: point.x, y: point.y, width: 320, height: 22), withAttributes: attrs)
    }
}

final class VisualFlashController {
    private var windows: [FlashOverlayWindow] = []

    func flash(rect: CGRect?, color: NSColor = .systemCyan) {
        let targetScreens: [NSScreen]
        if let rect = rect,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) {
            targetScreens = [screen]
        } else {
            targetScreens = NSScreen.screens
        }

        for screen in targetScreens {
            let window = FlashOverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = FlashOverlayView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                rect: rect,
                color: color
            )
            window.orderFrontRegardless()
            windows.append(window)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak window] in
                guard let self = self, let window = window else { return }
                window.orderOut(nil)
                self.windows.removeAll { $0 === window }
            }
        }
    }
}

final class FlashOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FlashOverlayView: NSView {
    let screenFrame: CGRect
    let rect: CGRect?
    let color: NSColor

    init(frame: CGRect, screenFrame: CGRect, rect: CGRect?, color: NSColor) {
        self.screenFrame = screenFrame
        self.rect = rect
        self.color = color
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let flashRect: CGRect
        if let rect = rect {
            flashRect = CGRect(
                x: rect.minX - screenFrame.minX,
                y: rect.minY - screenFrame.minY,
                width: rect.width,
                height: rect.height
            ).insetBy(dx: -5, dy: -5)
        } else {
            flashRect = bounds.insetBy(dx: 8, dy: 8)
        }

        color.withAlphaComponent(0.18).setFill()
        color.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(roundedRect: flashRect, xRadius: 8, yRadius: 8)
        path.lineWidth = 3
        path.fill()
        path.stroke()
    }
}

final class ToastController {
    private var window: ToastWindow?

    enum Placement {
        case nearMouse
        case center
        case bottomCenter
    }

    func show(message: String, duration: TimeInterval = 0.3, placement: Placement = .nearMouse) {
        let targetScreen = screenContainingMouse() ?? NSScreen.main
        guard let screen = targetScreen else { return }

        window?.orderOut(nil)
        let size = toastSize(message: message)
        let frame = frame(for: size, placement: placement, screen: screen)
        let toastWindow = ToastWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        toastWindow.level = .screenSaver
        toastWindow.backgroundColor = .clear
        toastWindow.isOpaque = false
        toastWindow.ignoresMouseEvents = true
        toastWindow.alphaValue = 0
        toastWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toastWindow.contentView = ToastView(frame: NSRect(origin: .zero, size: size), message: message)
        toastWindow.orderFrontRegardless()
        window = toastWindow

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.04
            toastWindow.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak toastWindow] in
            guard let toastWindow = toastWindow else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                toastWindow.animator().alphaValue = 0
            }, completionHandler: {
                toastWindow.orderOut(nil)
                if self?.window === toastWindow {
                    self?.window = nil
                }
            })
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func toastSize(message: String) -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14)
        ]
        let textSize = (message as NSString).size(withAttributes: attrs)
        return NSSize(width: max(92, ceil(textSize.width) + 32), height: 32)
    }

    private func frame(for size: NSSize, placement: Placement, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let origin: CGPoint
        switch placement {
        case .nearMouse:
            let mouse = NSEvent.mouseLocation
            origin = CGPoint(x: mouse.x + 14, y: mouse.y + 18)
        case .center:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .bottomCenter:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 92)
        }
        let x = min(max(visible.minX + 10, origin.x), visible.maxX - size.width - 10)
        let y = min(max(visible.minY + 10, origin.y), visible.maxY - size.height - 10)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

final class ToastWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ToastView: NSView {
    let message: String

    init(frame: CGRect, message: String) {
        self.message = message
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.02, alpha: 0.94).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.18, alpha: 0.9).setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor(calibratedRed: 0.09, green: 0.64, blue: 0.29, alpha: 1),
            .paragraphStyle: paragraph
        ]
        message.draw(in: bounds.insetBy(dx: 14, dy: 8), withAttributes: attrs)
    }
}

final class ColorPickerOverlayController {
    private var windows: [OverlayWindow] = []
    private var onPick: ((CGPoint, CGWindowID?) -> Void)?
    private var cursorHidden = false

    func start(previewProvider: @escaping (CGPoint, CGWindowID?) -> ColorPreview?, onPick: @escaping (CGPoint, CGWindowID?) -> Void) {
        cancel()
        self.onPick = onPick
        hideCursor()
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = ColorPickerOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame, previewProvider: previewProvider)
            view.onPick = { [weak self] point, windowID in self?.onPick?(point, windowID) }
            view.onCancel = { [weak self] in self?.cancel() }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
    }

    func cancel() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        onPick = nil
        showCursor()
    }

    private func hideCursor() {
        guard !cursorHidden else { return }
        NSCursor.hide()
        cursorHidden = true
    }

    private func showCursor() {
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }
}

final class ColorPickerOverlayView: NSView {
    let screenFrame: CGRect
    let previewProvider: (CGPoint, CGWindowID?) -> ColorPreview?
    var onPick: ((CGPoint, CGWindowID?) -> Void)?
    var onCancel: (() -> Void)?
    private var cursorPoint: CGPoint?
    private var preview: ColorPreview?
    private var copiedHex: String?
    private var tracking: NSTrackingArea?
    private var flashUntil: Date?

    init(frame: CGRect, screenFrame: CGRect, previewProvider: @escaping (CGPoint, CGWindowID?) -> ColorPreview?) {
        self.screenFrame = screenFrame
        self.previewProvider = previewProvider
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        if let tracking = tracking {
            removeTrackingArea(tracking)
        }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        tracking = next
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cursorPoint = cursorPoint else {
            drawLabel("Click a pixel to copy its color", at: CGPoint(x: 24, y: bounds.height - 44))
            return
        }

        drawLoupe(at: cursorPoint)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        updateCursor(event.locationInWindow)
    }

    override func mouseDown(with event: NSEvent) {
        let local = event.locationInWindow
        let point = CGPoint(x: screenFrame.minX + local.x, y: screenFrame.minY + local.y)
        preview = previewProvider(point, overlayWindowID())
        copiedHex = preview?.hex
        flashUntil = Date().addingTimeInterval(0.18)
        onPick?(point, overlayWindowID())
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.flashUntil = nil
            self?.needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        }
    }

    private func updateCursor(_ point: CGPoint) {
        cursorPoint = point
        preview = previewProvider(CGPoint(x: screenFrame.minX + point.x, y: screenFrame.minY + point.y), overlayWindowID())
        needsDisplay = true
    }

    private func overlayWindowID() -> CGWindowID? {
        guard let number = window?.windowNumber, number > 0 else { return nil }
        return CGWindowID(number)
    }

    private func drawLoupe(at cursorPoint: CGPoint) {
        let loupeSize: CGFloat = 122
        let loupe = loupeRect(near: cursorPoint, size: loupeSize)
        let outer = NSBezierPath(ovalIn: loupe)
        NSColor(calibratedWhite: 0, alpha: 0.72).setFill()
        outer.fill()

        if let preview = preview {
            NSGraphicsContext.saveGraphicsState()
            outer.addClip()
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: preview.image, size: loupe.size).draw(in: loupe)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.white.setStroke()
        outer.lineWidth = 2
        outer.stroke()

        if let flashUntil = flashUntil, flashUntil > Date() {
            drawPickerFlash(around: loupe)
        }

        NSColor.systemCyan.setStroke()
        let crosshair = NSBezierPath()
        crosshair.lineWidth = 1.5
        crosshair.move(to: CGPoint(x: loupe.midX, y: loupe.minY + 12))
        crosshair.line(to: CGPoint(x: loupe.midX, y: loupe.maxY - 12))
        crosshair.move(to: CGPoint(x: loupe.minX + 12, y: loupe.midY))
        crosshair.line(to: CGPoint(x: loupe.maxX - 12, y: loupe.midY))
        crosshair.stroke()

        let center = NSBezierPath(ovalIn: CGRect(x: loupe.midX - 4, y: loupe.midY - 4, width: 8, height: 8))
        center.lineWidth = 1.5
        center.stroke()

        let hex = preview?.hex ?? copiedHex ?? "Sampling"
        let swatch = CGRect(x: loupe.minX, y: loupe.maxY + 8, width: 24, height: 18)
        if let color = NSColor(hexString: hex) {
            color.setFill()
            NSBezierPath(roundedRect: swatch, xRadius: 4, yRadius: 4).fill()
        }
        drawLabel(hex, at: CGPoint(x: loupe.minX + 30, y: loupe.maxY + 7))
        if let copiedHex = copiedHex {
            drawLabel("Copied \(copiedHex)", at: CGPoint(x: loupe.minX, y: loupe.minY - 24))
        }
    }

    private func drawPickerFlash(around loupe: CGRect) {
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSColor.systemCyan.withAlphaComponent(0.95).setStroke()
        let flashRect = loupe.insetBy(dx: -6, dy: -6)
        let flash = NSBezierPath(ovalIn: flashRect)
        flash.lineWidth = 4
        flash.fill()
        flash.stroke()
    }

    private func loupeRect(near point: CGPoint, size: CGFloat) -> CGRect {
        var x = point.x + 26
        var y = point.y + 26
        if x + size > bounds.maxX - 12 {
            x = point.x - size - 26
        }
        if y + size + 34 > bounds.maxY - 12 {
            y = point.y - size - 42
        }
        return CGRect(
            x: min(max(12, x), bounds.maxX - size - 12),
            y: min(max(12, y), bounds.maxY - size - 46),
            width: size,
            height: size
        )
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(calibratedWhite: 0, alpha: 0.75)
        ]
        text.draw(at: point, withAttributes: attrs)
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return nil
        }
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat(value & 0xff) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
