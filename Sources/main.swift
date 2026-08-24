import Cocoa

if ScrollingCaptureCommand.runIfNeeded() {
    exit(0)
}

if SystemPowerController.runCommandLineIfNeeded() {
    exit(0)
}

if DiagnosticsCommand.runIfNeeded() {
    exit(0)
}

if NativeMessagingHost.runIfNeeded() {
    exit(0)
}

private func bundleVersion(at url: URL) -> (short: String, build: String) {
    let bundle = Bundle(url: url)
    return (
        bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    )
}

private func compareBundleVersions(
    _ lhs: (short: String, build: String),
    _ rhs: (short: String, build: String)
) -> ComparisonResult {
    let shortResult = lhs.short.compare(rhs.short, options: .numeric)
    return shortResult == .orderedSame
        ? lhs.build.compare(rhs.build, options: .numeric)
        : shortResult
}
private func executableModificationDate(at bundleURL: URL) -> Date {
    let executableURL = Bundle(url: bundleURL)?.executableURL ?? bundleURL
    return (try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
}


private func enforceSingleRunningApplication() {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
    let currentURL = Bundle.main.bundleURL.standardizedFileURL

    let currentPID = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
    guard !others.isEmpty else { return }

    let installedURL = URL(fileURLWithPath: "/Applications/STM Desktop Listener.app").standardizedFileURL
    let currentVersion = bundleVersion(at: currentURL)
    let currentIsInstalled = currentURL == installedURL
    let currentModificationDate = executableModificationDate(at: currentURL)
    let bestOther = others.max { lhs, rhs in
        guard let lhsURL = lhs.bundleURL?.standardizedFileURL,
              let rhsURL = rhs.bundleURL?.standardizedFileURL else {
            return lhs.bundleURL == nil
        }
        let versionResult = compareBundleVersions(bundleVersion(at: lhsURL), bundleVersion(at: rhsURL))
        if versionResult != .orderedSame {
            return versionResult == .orderedAscending
        }
        let lhsDate = executableModificationDate(at: lhsURL)
        let rhsDate = executableModificationDate(at: rhsURL)
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhsURL != installedURL && rhsURL == installedURL
    }

    if let bestOther,
       let otherURL = bestOther.bundleURL?.standardizedFileURL {
        let versionResult = compareBundleVersions(bundleVersion(at: otherURL), currentVersion)
        let otherModificationDate = executableModificationDate(at: otherURL)
        let otherWinsSameVersion: Bool
        if otherModificationDate != currentModificationDate {
            otherWinsSameVersion = otherModificationDate > currentModificationDate
        } else {
            otherWinsSameVersion = otherURL == installedURL || !currentIsInstalled
        }
        if versionResult == .orderedDescending ||
            (versionResult == .orderedSame && otherWinsSameVersion) {
            bestOther.activate(options: [.activateIgnoringOtherApps])
            exit(0)
        }
    }

    for other in others {
        _ = other.terminate()
    }
    let gracefulDeadline = Date().addingTimeInterval(2)
    while others.contains(where: { !$0.isTerminated }) && Date() < gracefulDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    for other in others where !other.isTerminated {
        _ = other.forceTerminate()
    }
}

let app = NSApplication.shared
enforceSingleRunningApplication()
let singleInstanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil,
    queue: .main
) { _ in
    enforceSingleRunningApplication()
}
let singleInstanceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    enforceSingleRunningApplication()
}
let delegate = AppDelegate(openFeaturesOnLaunch: CommandLine.arguments.contains("--open-features"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
