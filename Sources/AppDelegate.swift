import Cocoa
import UniformTypeIdentifiers
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkeys = HotkeyManager()
    private let features = FeatureRunner()
    private let popover = NSPopover()
    private let menuViewController = STMPopoverViewController()
    private var settingsWindowController: SettingsWindowController?
    private var credentialsGuideWindowController: CredentialsGuideWindowController?
    private let openFeaturesOnLaunch: Bool
    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
    private var animationColor = NSColor.black
    private var runtimeEventObservers: [NSObjectProtocol] = []
    private let updateService = STMUpdateService()
    private var automaticUpdateCheckTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var updateDownloadTask: Task<Void, Never>?

    init(openFeaturesOnLaunch: Bool = false) {
        self.openFeaturesOnLaunch = openFeaturesOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("app launch dictationLiveChunks=true firstChunkSeconds=60 subsequentChunkSeconds=20 normalizedUpload=16kMono uploadConcurrency=2 alertTopClose=true")
        setupRuntimeEventLogging()
        STMNotifier.configure(delegate: self)
        setupCallbacks()
        setupMenu()
        setupWorkspaceNotifications()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(toggleDictationFromExternalRequest(_:)),
            name: Notification.Name("com.seotimemachines.stm-desktop-listener.toggle-dictation"),
            object: nil
        )
        hotkeys.registerEnabledFeatureHotkeys()
        features.featureStateChanged()
        setIdleIcon()
        LoginItemService.registerByDefaultIfNeeded()
        if openFeaturesOnLaunch {
            DispatchQueue.main.async { self.showSettings(tab: "Features") }
        }
        scheduleAutomaticUpdateCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("runtime app event=willTerminate")
        features.dictation.cancel()
        automaticUpdateCheckTask?.cancel()
        automaticUpdateCheckTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        updateDownloadTask?.cancel()
        updateDownloadTask = nil
        runtimeEventObservers.forEach(NotificationCenter.default.removeObserver)
        runtimeEventObservers.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        hotkeys.unregisterAll()
    }

    private func setupCallbacks() {
        hotkeys.onTrigger = { [weak self] feature in self?.features.run(feature) }
        hotkeys.onCommandTrigger = { [weak self] commandID in self?.features.runCommandShortcut(id: commandID) }
        features.onError = { [weak self] title, message in self?.showAlert(title, message) }
        features.onNotice = { _, _ in }
        features.dictation.onError = { [weak self] title, message in self?.showAlert(title, message) }
        features.dictation.onNotice = { [weak self] title, message in self?.showAlert(title, message) }
        features.dictation.onStateChange = { [weak self] state in
            switch state {
            case .idle:
                self?.setIdleIcon()
            case .recording(let elapsed, let limit):
                self?.setWaveIcon(color: .labelColor, title: "\(Self.formatDuration(elapsed))/\(Self.formatDuration(limit))")
            case .processing(let currentChunk, let totalChunks):
                let title = totalChunks > 1 ? "\(currentChunk)/\(totalChunks)" : ""
                self?.setWaveIcon(color: NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.0, alpha: 1.0), title: title)
            }
        }
        features.mouseJiggler.onStateChange = { [weak self] in
            DispatchQueue.main.async {
                self?.setIdleIcon()
                self?.refreshMenu()
            }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        Logger.log("runtime app event=didBecomeActive")
    }

    func applicationDidResignActive(_ notification: Notification) {
        Logger.log("runtime app event=didResignActive")
    }

    func applicationDidHide(_ notification: Notification) {
        Logger.log("runtime app event=didHide")
    }

    func applicationDidUnhide(_ notification: Notification) {
        Logger.log("runtime app event=didUnhide")
    }

    private func setupRuntimeEventLogging() {
        let events: [(Notification.Name, String)] = [
            (NSWindow.didBecomeKeyNotification, "didBecomeKey"),
            (NSWindow.didResignKeyNotification, "didResignKey"),
            (NSWindow.didBecomeMainNotification, "didBecomeMain"),
            (NSWindow.didResignMainNotification, "didResignMain"),
            (NSWindow.didMiniaturizeNotification, "didMiniaturize"),
            (NSWindow.didDeminiaturizeNotification, "didDeminiaturize"),
            (NSWindow.didMoveNotification, "didMove"),
            (NSWindow.didResizeNotification, "didResize"),
            (NSWindow.didChangeOcclusionStateNotification, "didChangeOcclusion"),
            (NSWindow.willCloseNotification, "willClose")
        ]
        for (name, label) in events {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                Logger.log(
                    "runtime window event=\(label) number=\(window.windowNumber) title=\(window.title.debugDescription) " +
                    "visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) " +
                    "level=\(window.level.rawValue) occlusion=\(window.occlusionState.rawValue)"
                )
            }
            runtimeEventObservers.append(observer)
        }
    }


    @objc private func toggleDictationFromExternalRequest(_ notification: Notification) {
        Logger.log("external trigger feature=dictation")
        features.run(.dictation)
    }

    private func setupWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            Logger.log(
                "runtime workspace event=frontmostChanged pid=\(application.processIdentifier) " +
                "bundle=\(application.bundleIdentifier ?? "unknown")"
            )
        }
        hotkeys.refreshContextScopedHotkeys()
    }

    private func setupMenu() {
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        menuViewController.app = self
        popover.contentViewController = menuViewController
        popover.behavior = .transient
        popover.animates = true
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            menuViewController.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }


    func menuFeatureEnabled(_ feature: FeatureID) -> Bool {
        ConfigStore.featureEnabled(feature)
    }

    func menuSetFeature(_ feature: FeatureID, enabled: Bool) {
        if feature == .mouseJiggler {
            if ConfigStore.featureEnabled(.mouseJiggler) != enabled {
                toggleMouseJigglerFeature()
            } else {
                refreshMenu()
            }
            return
        }

        do {
            try ConfigStore.setFeatureEnabled(enabled, feature: feature)
            hotkeys.registerEnabledFeatureHotkeys()
            features.featureStateChanged()
            refreshMenu()
        } catch {
            showAlert("Save failed", error.localizedDescription)
        }
    }

    func menuSelectModel(id: String) {
        let model = TranscriptionModel.byID(id)
        features.dictation.setModel(model)
        refreshMenu()
    }

    var menuMouseStatusTitle: String {
        features.mouseJiggler.statusTitle
    }

    var menuMouseStatusLines: [String] {
        features.mouseJiggler.statusLines
    }

    var menuMouseIsActive: Bool {
        features.mouseJiggler.isActive
    }

    func menuOpenSettings(tab: String? = nil) {
        showSettings(tab: tab)
    }

    func menuImportCredentials() {
        importCredentials()
    }

    func menuInstallBrowserBridge() {
        installBrowserBridge()
    }

    func menuOpenConfigFolder() {
        openConfigFolder()
    }

    var menuUpdateCheckInProgress: Bool {
        updateCheckTask != nil
    }

    func menuCheckForUpdates() {
        automaticUpdateCheckTask?.cancel()
        automaticUpdateCheckTask = nil
        startUpdateCheck(mode: .manual)
    }

    func menuRequestMicrophone() {
        requestMicrophone()
    }

    func menuRequestScreen() {
        requestScreen()
    }

    func menuOpenScreenSettings() {
        openScreenSettings()
    }

    func menuRequestAccessibility() {
        requestAccessibility()
    }

    func menuResetAccessibilityEntry() {
        resetAccessibilityEntry()
    }

    func menuResetScreenRecordingEntry() {
        resetScreenRecordingEntry()
    }

    func menuSchedulePower(_ action: SystemPowerAction, input: String) {
        schedulePower(action, input: input)
    }

    func menuPromptScheduleShutdown() {
        scheduleShutdown()
    }

    func menuPromptScheduleSleep() {
        scheduleSleep()
    }

    func menuKeepAwake(input: String) {
        startKeepAwake(input: input)
    }

    func menuPromptKeepAwake() {
        keepAwake()
    }

    func menuRunGitAutosaveNow() {
        runGitAutosaveNow()
    }

    func menuCancelScheduledPower() {
        cancelScheduledPower()
    }

    func menuStopKeepAwake() {
        stopKeepAwake()
    }

    func menuShowPowerStatus() {
        showPowerStatus()
    }

    func menuCopyPowerStatus() {
        copyPowerStatus()
    }

    func menuOpenPowerLog() {
        openPowerLog()
    }

    func menuOpenNotificationSettings() {
        openNotificationSettings()
    }

    func menuToggleMouseJigglerFeature() {
        toggleMouseJigglerFeature()
    }

    func menuStartMouseJiggler(interval: Int, duration: Int) {
        startMouseJiggler(interval: interval, duration: duration)
    }

    func menuStartCustomMouseJiggler() {
        startCustomMouseJiggler()
    }

    func menuStopMouseJiggler() {
        stopMouseJiggler()
    }

    func menuQuit() {
        quit()
    }

    @objc private func openSettings() {
        showSettings(tab: nil)
    }

    private func showSettings(tab: String?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                onSettingsChanged: { [weak self] in
                    self?.hotkeys.registerEnabledFeatureHotkeys()
                    self?.features.featureStateChanged()
                    self?.refreshMenu()
                },
                onImportCredentials: { [weak self] in self?.importCredentials() },
                onInstallBridge: { [weak self] in self?.installBrowserBridge() },
                onOpenConfig: { [weak self] in self?.openConfigFolder() },
                shouldAutoHide: { [weak self] in
                    !(self?.features.captureOverlayActive ?? false)
                }
            )
        }
        settingsWindowController?.showWindow(nil, tab: tab)
    }

    @objc private func importCredentials() {
        showCredentialsGuide()
    }

    private func chooseCredentialsJSON() {
        let panel = NSOpenPanel()
        panel.title = "Import STM Desktop Listener Credentials"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let liveEnabled = try features.dictation.importCredentials(from: url)
            refreshMenu()
            let message = liveEnabled
                ? "Credentials saved locally. Worker dictation and the optional Cloudflare developer fallback are available."
                : "Credentials saved locally. Worker dictation is available."
            showAlert("Imported", message)
        } catch {
            showAlert("Import failed", error.localizedDescription)
        }
    }

    private func showCredentialsGuide() {
        if credentialsGuideWindowController == nil {
            credentialsGuideWindowController = CredentialsGuideWindowController(
                onChooseJSON: { [weak self] in self?.chooseCredentialsJSON() }
            )
        }
        credentialsGuideWindowController?.showWindow(nil)
        credentialsGuideWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func installBrowserBridge() {
        let bundledScript = Bundle.main.url(forResource: "install-native-host", withExtension: "sh")
        let packagedScript = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("install-native-host.sh")
        let script = [bundledScript, packagedScript].compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }

        guard let script else {
            showAlert(
                "Browser bridge installer unavailable",
                "This build is missing install-native-host.sh. Rebuild the app or use the packaged installer."
            )
            return
        }

        do {
            let output = try runInstallerScript(script)
            showAlert("Browser bridge installed", output.isEmpty ? "Chrome and Brave can now talk to STM Desktop Listener." : output)
        } catch {
            showAlert("Browser bridge install failed", error.localizedDescription)
        }
    }

    private func runInstallerScript(_ script: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw SimpleError(output.isEmpty ? "install-native-host.sh exited with status \(process.terminationStatus)." : output)
        }
        return output
    }

    @objc private func toggleMouseJigglerFeature() {
        let next = !ConfigStore.featureEnabled(.mouseJiggler)
        do {
            try ConfigStore.setFeatureEnabled(next, feature: .mouseJiggler)
            features.featureStateChanged()
            showNotice(next ? "Mouse Jiggler Enabled" : "Mouse Jiggler Disabled", next ? "Use the Mouse Jiggler menu to start movement. It never clicks." : "Mouse Jiggler stopped and disabled.")
            refreshMenu()
        } catch {
            showAlert("Mouse Jiggler failed", error.localizedDescription)
        }
    }

    @objc private func startMouseJigglerPreset(_ sender: NSMenuItem) {
        guard ConfigStore.featureEnabled(.mouseJiggler) else {
            showAlert("Mouse Jiggler disabled", "Enable Mouse Jiggler in Features first.")
            return
        }
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: "|", maxSplits: 1).compactMap { Int($0) }
        guard parts.count == 2 else { return }
        startMouseJiggler(interval: parts[0], duration: parts[1])
    }

    @objc private func startCustomMouseJiggler() {
        guard ConfigStore.featureEnabled(.mouseJiggler) else {
            showAlert("Mouse Jiggler disabled", "Enable Mouse Jiggler in Features first.")
            return
        }
        guard let interval = promptForMouseJigglerChoice(title: "Move Every", message: "Choose how often to move the mouse. No clicks are ever sent.", options: [("1 min", 60), ("2 min", 120), ("5 min", 300)]) else { return }
        guard let duration = promptForMouseJigglerChoice(title: "Stop After", message: "Choose how long Mouse Jiggler stays active.", options: [("Infinite", 0), ("30 min", 1800), ("1 hour", 3600), ("2 hours", 7200)]) else { return }
        startMouseJiggler(interval: interval, duration: duration)
    }

    private func startMouseJiggler(interval: Int, duration: Int) {
        guard PermissionCenter.requestAccessibility() else {
            showAlert("Accessibility permission needed", "Enable STM Desktop Listener in System Settings > Privacy & Security > Accessibility, then start Mouse Jiggler again.")
            return
        }
        if duration > 0 {
            features.mouseJiggler.startTimed(intervalSeconds: interval, durationSeconds: duration)
        } else {
            features.mouseJiggler.startInfinite(intervalSeconds: interval)
        }
        showNotice("Mouse Jiggler Active", "\(features.mouseJiggler.statusTitle). No clicks will be sent.")
        refreshMenu()
    }

    @objc private func stopMouseJiggler() {
        do {
            try ConfigStore.setFeatureEnabled(false, feature: .mouseJiggler)
        } catch {
            showAlert("Stop failed", error.localizedDescription)
            return
        }
        features.mouseJiggler.stop()
        showNotice("Mouse Jiggler Stopped", "Mouse movement is off.")
        refreshMenu()
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(AppPaths.applicationSupport)
    }

    private func scheduleAutomaticUpdateCheck() {
        automaticUpdateCheckTask?.cancel()
        automaticUpdateCheckTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.automaticUpdateCheckTask = nil
            self.startUpdateCheck(mode: .automatic)
        }
    }

    private func startUpdateCheck(mode: STMUpdateCheckMode) {
        guard updateCheckTask == nil else {
            if mode == .manual {
                showAlert("Update check in progress", "STM Desktop Listener is already checking for an update.")
            }
            return
        }

        let service = updateService
        let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        updateCheckTask = Task { @MainActor [weak self] in
            do {
                let result = try await service.check(
                    currentVersionString: installedVersion,
                    mode: mode,
                    now: Date()
                )
                guard !Task.isCancelled else { return }
                self?.updateCheckTask = nil
                self?.refreshMenu()
                self?.handleUpdateCheckResult(result, mode: mode, installedVersion: installedVersion)
            } catch {
                guard !Task.isCancelled else { return }
                self?.updateCheckTask = nil
                self?.refreshMenu()
                if mode == .manual {
                    self?.showAlert(
                        "Couldn’t check for updates",
                        "\(error.localizedDescription)\n\nYour current app is unchanged. Check your connection and try again."
                    )
                }
            }
        }
        refreshMenu()
    }

    private func handleUpdateCheckResult(
        _ result: STMUpdateCheckResult,
        mode: STMUpdateCheckMode,
        installedVersion: String
    ) {
        switch result {
        case .notDue:
            if mode == .manual {
                showAlert("You’re up to date", "STM Desktop Listener \(installedVersion) is the latest available version.")
            }
        case .upToDate:
            if mode == .manual {
                showAlert("You’re up to date", "STM Desktop Listener \(installedVersion) is the latest available version.")
            }
        case let .updateAvailable(release):
            presentUpdateAvailable(release, installedVersion: installedVersion)
        }
    }

    private func presentUpdateAvailable(_ release: STMUpdateRelease, installedVersion: String) {
        let releaseLabel = release.isPrerelease ? "PRERELEASE" : "STABLE"
        let published = DateFormatter.localizedString(
            from: release.publishedAt,
            dateStyle: .medium,
            timeStyle: .none
        )
        let releaseNotes = release.notes.isEmpty
            ? "No release notes were provided."
            : String(release.notes.prefix(1_200))
        let alert = NSAlert()
        alert.messageText = "STM Desktop Listener update available"
        alert.informativeText = """
        Installed: \(installedVersion)
        Available: \(release.version.description)
        Release channel: \(releaseLabel)
        Published: \(published)
        Architecture: Apple silicon (arm64)
        Requires: macOS 14 or later
        Trust: Ad hoc signed, not Apple-notarized

        \(releaseNotes)

        Downloading saves a verified DMG in Downloads and reveals it in Finder. STM will not install or replace the app.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download DMG")
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        alert.buttons[2].keyEquivalent = "\u{1b}"

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            downloadUpdate(release)
        case .alertSecondButtonReturn:
            guard NSWorkspace.shared.open(release.releasePageURL) else {
                showAlert("Couldn’t open release page", "Open \(release.releasePageURL.absoluteString) in your browser.")
                return
            }
        default:
            do {
                try updateService.dismiss(version: release.version)
            } catch {
                showAlert("Couldn’t save Later", error.localizedDescription)
            }
        }
    }

    private func downloadUpdate(_ release: STMUpdateRelease) {
        guard updateDownloadTask == nil else {
            showAlert("Download in progress", "STM Desktop Listener is already downloading and verifying an update.")
            return
        }

        showNotice(
            "Downloading verified DMG",
            "Version \(release.version.description) is downloading. STM will notify you when verification finishes."
        )
        let service = updateService
        updateDownloadTask = Task { @MainActor [weak self] in
            do {
                let downloadedURL = try await service.download(release, downloadsDirectory: nil)
                guard !Task.isCancelled else { return }
                self?.updateDownloadTask = nil
                NSWorkspace.shared.activateFileViewerSelecting([downloadedURL])
                self?.showAlert(
                    "Verified update downloaded",
                    "\(downloadedURL.lastPathComponent) is ready in Downloads.\n\nThe app has not been installed or replaced."
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.updateDownloadTask = nil
                self?.showAlert(
                    "Update download failed",
                    "\(error.localizedDescription)\n\nNothing was installed or replaced. Try again or open the release page."
                )
            }
        }
    }

    @objc private func requestMicrophone() {
        PermissionCenter.requestMicrophone { self.refreshMenu() }
    }

    @objc private func requestScreen() {
        _ = PermissionCenter.requestScreen()
        if PermissionCenter.screenStatusText() != "Ready" {
            PermissionCenter.openScreenRecordingSettings()
        }
        refreshMenu()
    }

    @objc private func openScreenSettings() {
        PermissionCenter.openScreenRecordingSettings()
        refreshMenu()
    }

    @objc private func requestAccessibility() {
        _ = PermissionCenter.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshMenu() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.refreshMenu() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { self.refreshMenu() }
    }

    @objc private func resetAccessibilityEntry() {
        PermissionCenter.resetAccessibilityEntry()
        refreshMenu()
    }

    @objc private func resetScreenRecordingEntry() {
        PermissionCenter.resetScreenRecordingEntry()
        refreshMenu()
    }

    @objc private func scheduleShutdown() {
        guard let target = promptForPowerDate(title: "Schedule Shut Down", action: .shutdown, defaultDate: Self.nextPowerPickerDate(hour: 8)) else { return }
        schedulePower(.shutdown, target: target)
    }

    @objc private func scheduleSleep() {
        guard let input = promptForPowerInput(title: "Schedule Sleep", message: "Enter a time or duration, e.g. 11pm, 23:30, or 2.5h.", defaultValue: "2.5h") else { return }
        schedulePower(.sleep, input: input)
    }

    @objc private func schedulePowerPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let action = SystemPowerAction(rawValue: parts[0]) else { return }
        schedulePower(action, input: parts[1])
    }

    private func schedulePower(_ action: SystemPowerAction, input: String) {
        do {
            let status = try SystemPowerController.schedule(action, when: input)
            showNotice(status.title, status.details)
            refreshMenu()
        } catch {
            showAlert("Schedule failed", error.localizedDescription)
        }
    }

    private func schedulePower(_ action: SystemPowerAction, target: Date) {
        do {
            let status = try SystemPowerController.schedule(action, at: target)
            showNotice(status.title, status.details)
            refreshMenu()
        } catch {
            showAlert("Schedule failed", error.localizedDescription)
        }
    }

    private func promptForPowerDate(title: String, action: SystemPowerAction, defaultDate: Date) -> Date? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Pick a future date and time. Nothing is scheduled until you click Schedule Shutdown."
        alert.alertStyle = .informational
        alert.icon = Bundle.main.image(forResource: "AppIcon")
        alert.addButton(withTitle: "Schedule Shutdown")
        alert.addButton(withTitle: "Cancel")
        let picker = PowerSchedulePickerView(action: action, initialDate: defaultDate)
        let scheduleButton = alert.buttons.first
        let ctaAccent = NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1)
        let styleScheduleButton: (Bool) -> Void = { isEnabled in
            scheduleButton?.wantsLayer = true
            scheduleButton?.layer?.cornerRadius = 7
            scheduleButton?.layer?.borderWidth = 1.25
            scheduleButton?.layer?.borderColor = ctaAccent.withAlphaComponent(isEnabled ? 0.82 : 0.24).cgColor
        }
        picker.onValidityChange = {
            scheduleButton?.isEnabled = $0
            styleScheduleButton($0)
        }
        let initialValidity = picker.selectedDate.timeIntervalSince(Date()) >= 60
        scheduleButton?.isEnabled = initialValidity
        styleScheduleButton(initialValidity)
        alert.accessoryView = picker
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return picker.selectedDate
    }

    private static func nextPowerPickerDate(hour: Int, minute: Int = 0) -> Date {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var target = Calendar.current.date(from: components) else {
            return now.addingTimeInterval(3600)
        }
        if target <= now, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: target) {
            target = tomorrow
        }
        return target
    }

    @objc private func keepAwake() {
        guard let input = promptForPowerInput(title: "Keep Awake", message: "Enter a duration or end time, e.g. 2.5h or 8am.", defaultValue: "2.5h") else { return }
        startKeepAwake(input: input)
    }

    @objc private func keepAwakePreset(_ sender: NSMenuItem) {
        guard let input = sender.representedObject as? String else { return }
        startKeepAwake(input: input)
    }

    private func startKeepAwake(input: String) {
        do {
            let status = try SystemPowerController.keepAwake(until: input)
            showNotice(status.title, status.details)
            refreshMenu()
        } catch {
            showAlert("Keep Awake failed", error.localizedDescription)
        }
    }

    @objc private func runGitAutosaveNow() {
        let status = SystemPowerController.autosaveGitNow()
        showNotice(status.title, status.details)
        refreshMenu()
    }

    @objc private func cancelScheduledPower() {
        do {
            try SystemPowerController.cancelScheduledPower()
            showNotice("Power Schedule", "Cancelled the scheduled shut down or sleep action.")
            refreshMenu()
        } catch {
            showAlert("Cancel failed", error.localizedDescription)
        }
    }

    @objc private func stopKeepAwake() {
        do {
            try SystemPowerController.stopKeepAwake()
            showNotice("Keep Awake", "Keep Awake stopped.")
            refreshMenu()
        } catch {
            showAlert("Stop failed", error.localizedDescription)
        }
    }

    @objc private func showPowerStatus() {
        let status = SystemPowerController.status()
        showAlert(status.title, status.details)
    }

    @objc private func copyPowerStatus() {
        let status = SystemPowerController.status()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(status.details, forType: .string)
        showNotice("Power Status Copied", "The current STM power status is on the clipboard.")
    }

    @objc private func openPowerLog() {
        if FileManager.default.fileExists(atPath: AppPaths.logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logURL])
        } else {
            NSWorkspace.shared.open(AppPaths.logURL.deletingLastPathComponent())
        }
    }

    @objc private func openNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]
        for value in candidates {
            guard let url = URL(string: value) else { continue }
            NSWorkspace.shared.open(url)
            return
        }
    }

    private func promptForPowerInput(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func promptForMouseJigglerChoice(title: String, message: String, options: [(String, Int)]) -> Int? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28), pullsDown: false)
        for option in options {
            popup.addItem(withTitle: option.0)
            popup.lastItem?.representedObject = option.1
        }
        alert.accessoryView = popup
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return popup.selectedItem?.representedObject as? Int
    }

    private func refreshMenu() {
        menuViewController.refresh()
    }

    private func setIdleIcon() {
        stopAnimationTimer()
        statusItem.button?.title = ""
        if features.mouseJiggler.isActive {
            statusItem.button?.toolTip = features.mouseJiggler.statusTitle
            statusItem.button?.image = MouseIcon.menuBarImage(color: .black)
        } else {
            statusItem.button?.toolTip = nil
            statusItem.button?.image = LightningIcon.menuBarImage(color: .black)
        }
    }

    private func setWaveIcon(color: NSColor, title: String = "") {
        stopAnimationTimer()
        animationColor = color
        animationPhase = 0
        statusItem.button?.title = title.isEmpty ? "" : " \(title)"
        statusItem.button?.toolTip = title.isEmpty ? nil : "Dictation \(title)"
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationPhase += 0.35
            self.statusItem.button?.image = WaveIcon.menuBarImage(color: self.animationColor, phase: self.animationPhase)
        }
        if let timer = animationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func showNotice(_ title: String, _ message: String) {
        features.toast.show(message: title, duration: 1.4, placement: .bottomCenter)
        STMNotifier.show(title: title, body: message.replacingOccurrences(of: "\n", with: " "))
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private final class PowerSchedulePickerView: NSView, NSTextFieldDelegate {
    private let action: SystemPowerAction
    private let calendarView: PowerScheduleCalendarView
    private let hourTile = NSTextField(string: "")
    private let minuteTile = NSTextField(string: "")
    private let meridiemTile = NSTextField(labelWithString: "")
    private let validityLabel = NSTextField(labelWithString: "")
    private let selectedLabel = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let calendar = Calendar.current
    private let neutralText = NSColor(calibratedWhite: 0.78, alpha: 1)
    private let neutralBorder = NSColor(calibratedWhite: 0.30, alpha: 1)
    private let red = NSColor(calibratedRed: 1.0, green: 0.33, blue: 0.36, alpha: 1)
    private let panel = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.09, alpha: 1)
    private let controlFill = NSColor(calibratedRed: 0.059, green: 0.071, blue: 0.091, alpha: 1)
    private var selectedHour: Int
    private var selectedMinute: Int
    private var countdownTimer: Timer?
    private var timeInputError: String?

    var onValidityChange: ((Bool) -> Void)?

    var selectedDate: Date {
        var components = calendar.dateComponents([.year, .month, .day], from: calendarView.selectedDate)
        components.hour = selectedHour
        components.minute = selectedMinute
        components.second = 0
        return calendar.date(from: components) ?? calendarView.selectedDate
    }

    init(action: SystemPowerAction, initialDate: Date) {
        self.action = action
        calendarView = PowerScheduleCalendarView(initialDate: initialDate)
        let initialComponents = Calendar.current.dateComponents([.hour, .minute], from: initialDate)
        selectedHour = initialComponents.hour ?? 8
        selectedMinute = initialComponents.minute ?? 0
        super.init(frame: NSRect(x: 0, y: 0, width: 760, height: 604))
        build(initialDate: initialDate)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        countdownTimer?.invalidate()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 760, height: 604)
    }

    private func build(initialDate: Date) {
        wantsLayer = true
        layer?.backgroundColor = panel.cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.29, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 12

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        root.addArrangedSubview(label("Quick picks", size: 13, weight: .bold, color: neutralText))
        root.addArrangedSubview(buttonRow([
            quickButton("In 1 hour", #selector(inOneHour)),
            quickButton("In 2.5 hours", #selector(inTwoAndHalfHours)),
            quickButton("Tomorrow 8:00 AM", #selector(nextMorning))
        ]))
        root.addArrangedSubview(label("Visual date and time", size: 13, weight: .bold, color: neutralText))
        root.addArrangedSubview(selectorRow())
        root.addArrangedSubview(feedbackPanel())

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        calendarView.onDateChange = { [weak self] in
            self?.updateSummary()
        }
        updateTimeTiles()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateSummary()
        }
        if let countdownTimer {
            RunLoop.main.add(countdownTimer, forMode: .common)
        }
        updateSummary()
    }

    private func selectorRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 728).isActive = true

        let calendarPanel = titledPanel(title: "Calendar", width: 356, height: 344)
        calendarView.translatesAutoresizingMaskIntoConstraints = false
        calendarView.widthAnchor.constraint(equalToConstant: 332).isActive = true
        calendarView.heightAnchor.constraint(equalToConstant: 300).isActive = true
        calendarPanel.stack.addArrangedSubview(calendarView)
        row.addArrangedSubview(calendarPanel.view)

        let timePanel = titledPanel(title: "Airport-board time", width: 356, height: 344)
        timePanel.stack.addArrangedSubview(timeBoard())
        timePanel.stack.addArrangedSubview(label("Type hour/minute directly, or use the buttons.", size: 11, weight: .medium, color: neutralText))
        timePanel.stack.addArrangedSubview(buttonRow([
            quickButton("+ Hour", #selector(addHour), width: 108),
            quickButton("+ 5 Min", #selector(addFiveMinutes), width: 108),
            quickButton("AM / PM", #selector(toggleMeridiem), width: 108)
        ], width: 332))
        timePanel.stack.addArrangedSubview(buttonRow([
            quickButton("- Hour", #selector(subtractHour), width: 108),
            quickButton("- 5 Min", #selector(subtractFiveMinutes), width: 108),
            quickButton(":00", #selector(roundToHour), width: 108)
        ], width: 332))
        row.addArrangedSubview(timePanel.view)
        return row
    }

    private func timeBoard() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 332).isActive = true
        row.heightAnchor.constraint(equalToConstant: 170).isActive = true
        row.addArrangedSubview(timeTile(hourTile, width: 104, editable: true))
        row.addArrangedSubview(colonLabel())
        row.addArrangedSubview(timeTile(minuteTile, width: 104, editable: true))
        row.addArrangedSubview(timeTile(meridiemTile, width: 78, size: 26))
        return row
    }

    private func feedbackPanel() -> NSView {
        let feedback = NSView()
        feedback.wantsLayer = true
        feedback.layer?.backgroundColor = NSColor(calibratedRed: 0.066, green: 0.066, blue: 0.066, alpha: 1).cgColor
        feedback.layer?.borderColor = neutralBorder.cgColor
        feedback.layer?.borderWidth = 1
        feedback.layer?.cornerRadius = 10
        feedback.translatesAutoresizingMaskIntoConstraints = false
        feedback.widthAnchor.constraint(equalToConstant: 728).isActive = true
        feedback.heightAnchor.constraint(equalToConstant: 112).isActive = true

        let feedbackStack = NSStackView()
        feedbackStack.orientation = .vertical
        feedbackStack.alignment = .leading
        feedbackStack.spacing = 5
        feedbackStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        feedbackStack.translatesAutoresizingMaskIntoConstraints = false
        feedback.addSubview(feedbackStack)

        validityLabel.font = .systemFont(ofSize: 15, weight: .bold)
        selectedLabel.font = .systemFont(ofSize: 13, weight: .medium)
        selectedLabel.textColor = .white
        countdownLabel.font = .systemFont(ofSize: 22, weight: .bold)
        countdownLabel.textColor = .white
        for field in [validityLabel, selectedLabel, countdownLabel] {
            field.lineBreakMode = .byWordWrapping
            field.maximumNumberOfLines = 2
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 700).isActive = true
            feedbackStack.addArrangedSubview(field)
        }

        NSLayoutConstraint.activate([
            feedbackStack.leadingAnchor.constraint(equalTo: feedback.leadingAnchor),
            feedbackStack.trailingAnchor.constraint(equalTo: feedback.trailingAnchor),
            feedbackStack.topAnchor.constraint(equalTo: feedback.topAnchor),
            feedbackStack.bottomAnchor.constraint(equalTo: feedback.bottomAnchor)
        ])
        return feedback
    }

    private func titledPanel(title: String, width: CGFloat, height: CGFloat) -> (view: NSView, stack: NSStackView) {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.066, green: 0.066, blue: 0.066, alpha: 1).cgColor
        view.layer?.borderColor = NSColor(calibratedWhite: 0.29, alpha: 1).cgColor
        view.layer?.borderWidth = 1
        view.layer?.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        stack.addArrangedSubview(label(title, size: 13, weight: .bold, color: neutralText))

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return (view, stack)
    }

    private func quickButton(_ title: String, _ action: Selector, width: CGFloat = 234) -> STMActionButton {
        let button = STMActionButton(title: title, target: self, action: action)
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.accentColor = nil
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    private func buttonRow(_ buttons: [NSView], width: CGFloat = 728) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    private func timeTile(_ field: NSTextField, width: CGFloat, size: CGFloat = 46, editable: Bool = false) -> NSView {
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.backgroundColor = controlFill.cgColor
        tile.layer?.borderColor = neutralBorder.cgColor
        tile.layer?.borderWidth = 1
        tile.layer?.cornerRadius = 9
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.widthAnchor.constraint(equalToConstant: width).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 118).isActive = true

        field.font = .monospacedDigitSystemFont(ofSize: size, weight: .heavy)
        field.textColor = .white
        field.alignment = .center
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isEditable = editable
        field.isSelectable = editable
        field.focusRingType = editable ? .default : .none
        field.delegate = editable ? self : nil
        field.target = editable ? self : nil
        field.action = editable ? #selector(commitManualTimeInput) : nil
        field.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])
        return tile
    }

    private func colonLabel() -> NSTextField {
        let field = NSTextField(labelWithString: ":")
        field.font = .monospacedDigitSystemFont(ofSize: 42, weight: .bold)
        field.textColor = neutralText
        field.alignment = .center
        return field
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .left
        return field
    }

    @objc private func nextMorning() {
        setDate(nextClockTime(hour: 8, forceTomorrow: true))
    }

    @objc private func nextLateNight() {
        setDate(nextClockTime(hour: 23))
    }

    @objc private func inOneHour() {
        setDate(Date().addingTimeInterval(3600))
    }

    @objc private func inTwoAndHalfHours() {
        setDate(Date().addingTimeInterval(9000))
    }

    @objc private func addHour() {
        selectedHour = (selectedHour + 1) % 24
        updateTimeTiles()
        updateSummary()
    }

    @objc private func subtractHour() {
        selectedHour = (selectedHour + 23) % 24
        updateTimeTiles()
        updateSummary()
    }

    @objc private func addFiveMinutes() {
        selectedMinute += 5
        if selectedMinute >= 60 {
            selectedMinute -= 60
            selectedHour = (selectedHour + 1) % 24
        }
        updateTimeTiles()
        updateSummary()
    }

    @objc private func subtractFiveMinutes() {
        selectedMinute -= 5
        if selectedMinute < 0 {
            selectedMinute += 60
            selectedHour = (selectedHour + 23) % 24
        }
        updateTimeTiles()
        updateSummary()
    }

    @objc private func toggleMeridiem() {
        selectedHour = (selectedHour + 12) % 24
        updateTimeTiles()
        updateSummary()
    }

    @objc private func roundToHour() {
        selectedMinute = 0
        updateTimeTiles()
        updateSummary()
    }

    @objc private func commitManualTimeInput() {
        applyManualTimeInput(reformat: true)
    }

    func controlTextDidChange(_ obj: Notification) {
        applyManualTimeInput(reformat: false)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        applyManualTimeInput(reformat: true)
    }

    private func setDate(_ date: Date) {
        calendarView.selectedDate = date
        let components = calendar.dateComponents([.hour, .minute], from: date)
        selectedHour = components.hour ?? selectedHour
        selectedMinute = components.minute ?? selectedMinute
        updateTimeTiles()
        updateSummary()
    }

    private func nextClockTime(hour: Int, minute: Int = 0, forceTomorrow: Bool = false) -> Date {
        let now = Date()
        let base = forceTomorrow ? (calendar.date(byAdding: .day, value: 1, to: now) ?? now) : now
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var target = calendar.date(from: components) else {
            return now.addingTimeInterval(3600)
        }
        if target <= now, let tomorrow = calendar.date(byAdding: .day, value: 1, to: target) {
            target = tomorrow
        }
        return target
    }

    private func updateTimeTiles() {
        let twelveHour = selectedHour % 12 == 0 ? 12 : selectedHour % 12
        hourTile.stringValue = String(format: "%02d", twelveHour)
        minuteTile.stringValue = String(format: "%02d", selectedMinute)
        meridiemTile.stringValue = selectedHour < 12 ? "AM" : "PM"
        timeInputError = nil
    }

    private func applyManualTimeInput(reformat: Bool) {
        let hourText = hourTile.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let minuteText = minuteTile.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hour = Int(hourText), (1...12).contains(hour) else {
            timeInputError = "Hour must be 1–12."
            updateSummary()
            return
        }
        guard let minute = Int(minuteText), (0...59).contains(minute) else {
            timeInputError = "Minute must be 0–59."
            updateSummary()
            return
        }
        let isPM = selectedHour >= 12
        selectedHour = (hour % 12) + (isPM ? 12 : 0)
        selectedMinute = minute
        timeInputError = nil
        if reformat {
            updateTimeTiles()
        }
        updateSummary()
    }

    private func updateSummary() {
        let remaining = selectedDate.timeIntervalSince(Date())
        let isValid = remaining >= 60 && timeInputError == nil
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        if let timeInputError {
            validityLabel.stringValue = "⚠ \(timeInputError)"
            validityLabel.textColor = red
        } else {
            validityLabel.stringValue = isValid ? "Preview only — not scheduled yet" : "⚠ Choose a future date and time"
            validityLabel.textColor = isValid ? neutralText : red
        }
        selectedLabel.stringValue = "\(action.label.capitalized) will be scheduled for \(formatter.string(from: selectedDate))"
        countdownLabel.stringValue = isValid ? "Selected time is \(Self.countdownText(remaining)) from now" : (timeInputError == nil ? "The selected time has already passed" : "Fix the time format to continue")
        countdownLabel.textColor = isValid ? .white : red
        onValidityChange?(isValid)
    }

    private static func countdownText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}

private final class PowerScheduleCalendarView: NSView {
    private let calendar = Calendar.current
    private let neutralAccent = NSColor(calibratedWhite: 0.78, alpha: 1)
    private let neutralBorder = NSColor(calibratedWhite: 0.32, alpha: 1)
    private let controlFill = NSColor(calibratedRed: 0.059, green: 0.071, blue: 0.091, alpha: 1)
    private let muted = NSColor(calibratedWhite: 0.50, alpha: 1)
    private let text = NSColor.white
    private var visibleMonth: Date
    private var previousRect = NSRect.zero
    private var nextRect = NSRect.zero
    private var dayHitRects: [(date: Date, rect: NSRect, enabled: Bool)] = []
    var onDateChange: (() -> Void)?

    var selectedDate: Date {
        didSet {
            visibleMonth = Self.startOfMonth(selectedDate, calendar: calendar)
            needsDisplay = true
            onDateChange?()
        }
    }

    init(initialDate: Date) {
        selectedDate = initialDate
        visibleMonth = Self.startOfMonth(initialDate, calendar: calendar)
        super.init(frame: NSRect(x: 0, y: 0, width: 332, height: 300))
        wantsLayer = true
        layer?.backgroundColor = controlFill.cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.24, alpha: 0.9).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 9
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 332, height: 300)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHeader()
        drawWeekdays()
        drawDays()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if previousRect.contains(point) {
            if let month = calendar.date(byAdding: .month, value: -1, to: visibleMonth) {
                visibleMonth = month
                needsDisplay = true
            }
            return
        }
        if nextRect.contains(point) {
            if let month = calendar.date(byAdding: .month, value: 1, to: visibleMonth) {
                visibleMonth = month
                needsDisplay = true
            }
            return
        }
        guard let hit = dayHitRects.first(where: { $0.rect.contains(point) && $0.enabled }) else { return }
        selectedDate = hit.date
    }

    private func drawHeader() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let title = formatter.string(from: visibleMonth)
        draw(title, in: NSRect(x: 14, y: bounds.height - 38, width: 210, height: 26), font: .systemFont(ofSize: 22, weight: .bold), color: .white, alignment: .left)

        previousRect = NSRect(x: bounds.width - 78, y: bounds.height - 38, width: 28, height: 28)
        nextRect = NSRect(x: bounds.width - 42, y: bounds.height - 38, width: 28, height: 28)
        drawChevron("‹", in: previousRect)
        drawChevron("›", in: nextRect)
    }

    private func drawChevron(_ value: String, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        path.fill()
        neutralBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
        draw(value, in: rect.offsetBy(dx: 0, dy: -1), font: .systemFont(ofSize: 22, weight: .bold), color: neutralAccent, alignment: .center)
    }

    private func drawWeekdays() {
        let names = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        let cellWidth = bounds.width / 7
        for index in 0..<7 {
            let rect = NSRect(x: CGFloat(index) * cellWidth, y: bounds.height - 70, width: cellWidth, height: 24)
            draw(names[index], in: rect, font: .systemFont(ofSize: 13, weight: .bold), color: neutralAccent, alignment: .center)
        }
    }

    private func drawDays() {
        dayHitRects = []
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) else { return }
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let mondayOffset = (firstWeekday + 5) % 7
        let cellWidth = bounds.width / 7
        let gridTop: CGFloat = bounds.height - 76
        let cellHeight = (gridTop - 8) / 6
        let today = calendar.startOfDay(for: Date())
        let selected = calendar.startOfDay(for: selectedDate)

        for index in 0..<42 {
            let dayOffset = index - mondayOffset
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else { continue }
            let row = index / 7
            let column = index % 7
            let rect = NSRect(
                x: CGFloat(column) * cellWidth + 4,
                y: gridTop - CGFloat(row + 1) * cellHeight + 4,
                width: cellWidth - 8,
                height: cellHeight - 8
            )
            let month = calendar.component(.month, from: date) == calendar.component(.month, from: visibleMonth)
            let enabled = calendar.startOfDay(for: date) >= today
            let isSelected = calendar.isDate(date, inSameDayAs: selected)
            let isToday = calendar.isDateInToday(date)
            dayHitRects.append((date, rect, enabled))

            if isSelected {
                let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                NSColor.white.withAlphaComponent(0.12).setFill()
                path.fill()
                neutralBorder.setStroke()
                path.lineWidth = 1.2
                path.stroke()
            } else if isToday {
                let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                NSColor.white.withAlphaComponent(0.06).setFill()
                path.fill()
                neutralBorder.withAlphaComponent(0.72).setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            let color: NSColor
            if !enabled {
                color = muted.withAlphaComponent(0.42)
            } else if isSelected {
                color = .white
            } else if month {
                color = text
            } else {
                color = muted
            }
            let day = String(calendar.component(.day, from: date))
            draw(day, in: rect.offsetBy(dx: 0, dy: -1), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: color, alignment: .center)
        }
    }

    private func draw(_ string: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        string.draw(in: rect, withAttributes: attributes)
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
