import Cocoa

final class DictationHUDController {
    private let panel: NSPanel
    private let meterView = DictationMeterView(frame: NSRect(x: 0, y: 0, width: 200, height: 42))

    init() {
        panel = NSPanel(
            contentRect: meterView.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = meterView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        position()
    }

    func showRecording() {
        meterView.setMode(.recording)
        position()
        panel.orderFrontRegardless()
    }

    func showProcessing() {
        meterView.setMode(.processing)
        position()
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
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = panel.frame
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - frame.width / 2,
            y: screen.visibleFrame.minY + 18
        ))
    }
}

private final class DictationMeterView: NSView {
    enum Mode {
        case idle
        case recording
        case processing
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
        let gap: CGFloat = 3.05
        let totalWidth = CGFloat(Self.barCount) * barWidth + CGFloat(Self.barCount - 1) * gap
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.midY

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
            let height = 3 + activity * 31
            let rect = NSRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: centerY - height / 2,
                width: barWidth,
                height: height
            )
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}
