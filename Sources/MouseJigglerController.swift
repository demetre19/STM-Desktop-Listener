import Cocoa
import CoreGraphics
import Foundation

final class MouseJigglerController {
    private var timer: Timer?
    private var stopTimer: Timer?
    private var direction: CGFloat = 1
    private var isMovementSequenceInProgress = false

    private(set) var isActive = false
    private(set) var intervalSeconds = ConfigStore.int("mouseJiggler.intervalSeconds", default: 120)
    private(set) var endDate: Date? = MouseJigglerController.storedEndDate()
    var onStateChange: (() -> Void)?

    var statusTitle: String {
        guard isActive else { return "Mouse Jiggler: Off" }
        if let endDate = endDate {
            return "Mouse Jiggler: Every \(Self.intervalLabel(intervalSeconds)) until \(Self.shortTime(endDate))"
        }
        return "Mouse Jiggler: Every \(Self.intervalLabel(intervalSeconds))"
    }

    var statusLines: [String] {
        guard isActive else { return ["Status: off", "Clicking: never"] }
        var lines = ["Status: active", "Move every: \(Self.intervalLabel(intervalSeconds))", "Clicking: never"]
        if let endDate = endDate {
            lines.append("Stops: \(Self.format(endDate))")
        } else {
            lines.append("Stops: never")
        }
        return lines
    }

    func restoreIfNeeded(featureEnabled: Bool) {
        guard featureEnabled else {
            stop(reason: "feature-disabled", persist: true)
            return
        }
        let savedInterval = ConfigStore.int("mouseJiggler.intervalSeconds", default: 60)
        guard ConfigStore.bool("mouseJiggler.active", default: false) else {
            stop(reason: "inactive-at-launch", persist: false)
            return
        }
        let savedEnd = Self.storedEndDate()
        if let savedEnd, savedEnd <= Date() {
            stop(reason: "expired-before-restore", persist: true)
            return
        }
        start(intervalSeconds: savedInterval, durationSeconds: nil, explicitEndDate: savedEnd, reason: "restore")
    }

    func startInfinite(intervalSeconds: Int) {
        start(intervalSeconds: intervalSeconds, durationSeconds: nil, explicitEndDate: nil, reason: "infinite")
    }

    func startTimed(intervalSeconds: Int, durationSeconds: Int) {
        let end = Date().addingTimeInterval(TimeInterval(durationSeconds))
        start(intervalSeconds: intervalSeconds, durationSeconds: durationSeconds, explicitEndDate: end, reason: "timed")
    }

    func stop(reason: String = "manual", persist: Bool = true) {
        timer?.invalidate()
        stopTimer?.invalidate()
        timer = nil
        stopTimer = nil
        isActive = false
        endDate = nil
        if persist {
            try? ConfigStore.set(false, for: "mouseJiggler.active")
            try? ConfigStore.set("", for: "mouseJiggler.endDate")
        }
        onStateChange?()
        Logger.log("mouse jiggler stopped reason=\(reason)")
    }

    @discardableResult
    static func moveCursorOnce() -> Bool {
        guard let current = CGEvent(source: nil)?.location else { return false }
        return postMove(from: current, delta: visibleDelta(from: current, preferred: 24)).moved
    }

    @discardableResult
    private static func postMove(from current: CGPoint, delta: CGFloat) -> (moved: Bool, target: CGPoint) {
        let adjustedDelta = visibleDelta(from: current, preferred: delta)
        let target = CGPoint(x: current.x + adjustedDelta, y: current.y)
        guard CGWarpMouseCursorPosition(target) == .success else {
            return (false, current)
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left) else {
            return (false, target)
        }
        event.post(tap: .cghidEventTap)
        return (true, target)
    }

    private static func visibleDelta(from current: CGPoint, preferred: CGFloat) -> CGFloat {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(current) }) ?? NSScreen.main {
            let minX = screen.frame.minX + 4
            let maxX = screen.frame.maxX - 4
            if current.x + preferred > maxX { return -abs(preferred) }
            if current.x + preferred < minX { return abs(preferred) }
        }
        return preferred
    }

    static func intervalLabel(_ seconds: Int) -> String {
        switch seconds {
        case 60: return "1 min"
        case 120: return "2 min"
        case 300: return "5 min"
        default: return "\(max(1, seconds / 60)) min"
        }
    }

    private func start(intervalSeconds: Int, durationSeconds: Int?, explicitEndDate: Date?, reason: String) {
        stop(reason: "restart", persist: false)
        let allowed = [60, 120, 300]
        self.intervalSeconds = allowed.contains(intervalSeconds) ? intervalSeconds : 120
        self.endDate = explicitEndDate
        self.isActive = true
        try? ConfigStore.set(true, for: "mouseJiggler.active")
        try? ConfigStore.set(self.intervalSeconds, for: "mouseJiggler.intervalSeconds")
        try? ConfigStore.set(explicitEndDate.map { ISO8601DateFormatter().string(from: $0) } ?? "", for: "mouseJiggler.endDate")

        let timer = Timer(timeInterval: TimeInterval(self.intervalSeconds), repeats: true) { [weak self] _ in
            self?.moveTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if let explicitEndDate {
            let stopTimer = Timer(fireAt: explicitEndDate, interval: 0, target: self, selector: #selector(stopFromTimer), userInfo: nil, repeats: false)
            RunLoop.main.add(stopTimer, forMode: .common)
            self.stopTimer = stopTimer
        }
        onStateChange?()
        moveTick()
        Logger.log("mouse jiggler started reason=\(reason) interval=\(self.intervalSeconds) duration=\(durationSeconds ?? 0) end=\(explicitEndDate.map { Self.format($0) } ?? "never") click=false")
    }

    private func moveTick() {
        guard isActive, !isMovementSequenceInProgress else { return }
        if let endDate, endDate <= Date() {
            stop(reason: "expired", persist: true)
            return
        }
        guard let current = CGEvent(source: nil)?.location else {
            Logger.log("mouse jiggler skipped no cursor location")
            return
        }
        isMovementSequenceInProgress = true
        let delta = direction * 40
        let moved = Self.postMove(from: current, delta: delta)
        isMovementSequenceInProgress = false
        guard moved.moved else {
            Logger.log("mouse jiggler failed to warp/post mouseMoved event")
            return
        }
        direction = -direction
        Logger.log("mouse jiggler moved from=(\(Int(current.x)),\(Int(current.y))) to=(\(Int(moved.target.x)),\(Int(moved.target.y))) click=false")
    }

    @objc private func stopFromTimer() {
        stop(reason: "duration-ended", persist: true)
    }

    private static func storedEndDate() -> Date? {
        guard let raw = ConfigStore.string("mouseJiggler.endDate") else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
