import Cocoa
import Carbon

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown,
           event.charactersIgnoringModifiers?.lowercased() == "v",
           flags.contains(.control),
           !flags.contains(.command),
           !flags.contains(.option),
           let editor = firstResponder as? NSTextView,
           containsCommandEditor(editor, in: contentView) {
            editor.paste(nil)
            return
        }
        super.sendEvent(event)
    }

    private func containsCommandEditor(_ editor: NSTextView, in view: NSView?) -> Bool {
        guard let view else { return false }
        if let field = view as? CommandTextField, field.currentEditor() === editor {
            return true
        }
        return view.subviews.contains { containsCommandEditor(editor, in: $0) }
    }
}

private final class CommandTextField: NSTextField {}

final class RoundedPanelView: NSView {
    var fillColor: NSColor
    var strokeColor: NSColor
    var radius: CGFloat
    var strokeWidth: CGFloat

    init(fillColor: NSColor, strokeColor: NSColor, radius: CGFloat = 14, strokeWidth: CGFloat = 1) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.radius = radius
        self.strokeWidth = strokeWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }
}

enum SettingsPalette {
    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    static let cyan = rgb(18, 252, 255)
    static let amber = rgb(245, 158, 10)
    static let red = rgb(255, 84, 92)
    static let root = rgb(5, 6, 7)
    static let sidebar = rgb(23, 23, 23)
    static let panel = rgb(23, 23, 23)
    static let row = rgb(23, 23, 23)
    static let badge = rgb(15, 18, 23)
    static let childRow = rgb(23, 23, 23)
    static let forest = rgb(24, 43, 44)
    static let stroke = rgb(64, 64, 64)
    static let badgeStroke = rgb(46, 48, 52)
    static let selected = rgb(15, 18, 23)
    static let text = rgb(238, 239, 241)
    static let muted = rgb(166, 170, 177)
}

final class SidebarNavButton: NSButton {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

    var selected = false {
        didSet {
            layer?.backgroundColor = selected ? SettingsPalette.selected.cgColor : NSColor.clear.cgColor
            layer?.borderColor = selected ? SettingsPalette.amber.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
            titleField.textColor = selected ? SettingsPalette.text : SettingsPalette.muted
            iconView.contentTintColor = selected ? SettingsPalette.amber : SettingsPalette.muted
        }
    }

    init(title: String, symbol: String, identifier: String) {
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        self.title = ""
        target = nil
        isBordered = false
        bezelStyle = .regularSquare
        alignment = .left
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        setButtonType(.momentaryChange)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.image?.isTemplate = true
        iconView.contentTintColor = SettingsPalette.cyan
        iconView.imageScaling = .scaleProportionallyDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.stringValue = title
        titleField.font = .boldSystemFont(ofSize: 15)
        titleField.textColor = SettingsPalette.muted

        addSubview(iconView)
        addSubview(titleField)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        widthAnchor.constraint(equalToConstant: 176).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class HoverLinkButton: NSButton {
    private var tracking: NSTrackingArea?

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        alignment = .center
        font = .systemFont(ofSize: 11)
        updateColor(SettingsPalette.cyan)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        if let tracking = tracking {
            removeTrackingArea(tracking)
        }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(next)
        tracking = next
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        updateColor(.white)
    }

    override func mouseExited(with event: NSEvent) {
        updateColor(SettingsPalette.cyan)
    }

    private func updateColor(_ color: NSColor) {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 11),
                .foregroundColor: color,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onSettingsChanged: () -> Void
    private let onImportCredentials: () -> Void
    private let onInstallBridge: () -> Void
    private let onOpenConfig: () -> Void
    private let shouldAutoHide: () -> Bool
    private var permissionLabels: [String: NSTextField] = [:]
    private var permissionDots: [String: NSTextField] = [:]
    private var shortcutLabels: [FeatureID: NSTextField] = [:]
    private var featureChecks: [FeatureID: NSButton] = [:]
    private var featureRows: [FeatureID: NSView] = [:]
    private var commandShortcutLabels: [String: NSTextField] = [:]
    private var commandShortcutFields: [String: NSTextField] = [:]
    private var transcriptionEnginePopup: NSPopUpButton?
    private var voiceCommandsCheck: NSButton?
    private var parakeetStatusLabel: NSTextField?
    private var parakeetDownloadButton: STMActionButton?
    private var parakeetReuseButton: STMActionButton?
    private var sidebarButtons: [String: NSButton] = [:]
    private var recordingMonitor: Any?
    private var recordingFeature: FeatureID?
    private var recordingCommandShortcutID: String?
    private var tabView: NSTabView?
    private var selectedSection = "Features"

    init(onSettingsChanged: @escaping () -> Void,
         onImportCredentials: @escaping () -> Void,
         onInstallBridge: @escaping () -> Void,
         onOpenConfig: @escaping () -> Void,
         shouldAutoHide: @escaping () -> Bool = { true }) {
        self.onSettingsChanged = onSettingsChanged
        self.onImportCredentials = onImportCredentials
        self.onInstallBridge = onInstallBridge
        self.onOpenConfig = onOpenConfig
        self.shouldAutoHide = shouldAutoHide

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "STM Desktop Listener"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        showWindow(sender, tab: nil)
    }

    func showWindow(_ sender: Any?, tab: String?) {
        super.showWindow(sender)
        if let tab = tab {
            selectSection(tab)
        }
        refreshPermissions()
        refreshFeatures()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard shouldAutoHide() else { return }
        stopRecordingShortcut()
        window?.orderOut(nil)
    }

    private func buildContent() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = SettingsPalette.root.cgColor

        let sidebar = sidebarView()
        let tabs = NSTabView()
        tabs.tabViewType = .noTabsNoBorder
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(tab(title: "Features", view: featuresView()))
        tabs.addTabViewItem(tab(title: "General", view: generalView()))
        tabs.addTabViewItem(tab(title: "Voice AI", view: aiPolishView()))
        tabs.addTabViewItem(tab(title: "Permissions", view: permissionsView()))
        tabs.addTabViewItem(tab(title: "Diagnostics", view: diagnosticsView()))
        tabView = tabs

        root.addSubview(sidebar)
        root.addSubview(tabs)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),
            tabs.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: root.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        updateSidebarSelection()
        return root
    }

    private func sidebarView() -> NSView {
        let sidebar = RoundedPanelView(fillColor: SettingsPalette.sidebar, strokeColor: SettingsPalette.badgeStroke, radius: 0)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        let logo = settingsAppIconView(size: 72)
        stack.addArrangedSubview(logo)
        stack.setCustomSpacing(14, after: logo)

        let title = label("STM Desktop", font: .boldSystemFont(ofSize: 18))
        title.textColor = SettingsPalette.text
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(22, after: title)

        stack.addArrangedSubview(sidebarButton(title: "Features", symbol: "sparkles", identifier: "Features"))
        stack.addArrangedSubview(sidebarButton(title: "General", symbol: "house", identifier: "General"))
        stack.addArrangedSubview(sidebarButton(title: "Voice AI", symbol: "waveform.badge.mic", identifier: "Voice AI"))
        stack.addArrangedSubview(sidebarButton(title: "Permissions", symbol: "checkmark.shield", identifier: "Permissions"))
        stack.addArrangedSubview(sidebarButton(title: "Diagnostics", symbol: "waveform.path.ecg", identifier: "Diagnostics"))

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(spacer)

        let badge = RoundedPanelView(fillColor: SettingsPalette.row, strokeColor: SettingsPalette.stroke, radius: 8)
        let badgeRow = NSStackView()
        badgeRow.orientation = .horizontal
        badgeRow.alignment = .centerY
        badgeRow.spacing = 10
        badgeRow.translatesAutoresizingMaskIntoConstraints = false
        let badgeIcon = settingsAppIconView(size: 28)
        let badgeLabel = label("STM Desktop Listener", font: .boldSystemFont(ofSize: 12))
        badgeLabel.textColor = SettingsPalette.muted
        badgeRow.addArrangedSubview(badgeIcon)
        badgeRow.addArrangedSubview(badgeLabel)
        badge.addSubview(badgeRow)
        NSLayoutConstraint.activate([
            badgeRow.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 10),
            badgeRow.trailingAnchor.constraint(lessThanOrEqualTo: badge.trailingAnchor, constant: -10),
            badgeRow.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 52),
            badge.widthAnchor.constraint(equalToConstant: 176)
        ])
        stack.addArrangedSubview(badge)
        stack.setCustomSpacing(8, after: badge)

        let powered = HoverLinkButton(title: "Powered by SEO Time Machines", target: self, action: #selector(openPoweredBy))
        powered.widthAnchor.constraint(equalToConstant: 176).isActive = true
        stack.addArrangedSubview(powered)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -22)
        ])
        return sidebar
    }

    private func sidebarButton(title: String, symbol: String, identifier: String) -> NSButton {
        let button = SidebarNavButton(title: title, symbol: symbol, identifier: identifier)
        button.target = self
        button.action = #selector(selectSidebarSection(_:))
        sidebarButtons[identifier] = button
        return button
    }

    private func settingsAppIconView(size: CGFloat) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = Bundle.main.image(forResource: "AppIcon")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = size >= 64 ? 16 : 7
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: size).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: size).isActive = true
        return imageView
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private func generalView() -> NSView {
        let stack = baseStack()
        stack.addArrangedSubview(pageTitle("General", "App identity, local storage, and bridge setup."))
        stack.addArrangedSubview(infoCard(rows: [
            ("Bundle ID", "com.seotimemachines.stm-desktop-listener"),
            ("Config", AppPaths.configURL.path),
            ("Logs", AppPaths.logURL.path)
        ]))

        let actionRow = horizontalStack(spacing: 10)
        actionRow.addArrangedSubview(button("Import Credentials", action: #selector(importCredentials)))
        actionRow.addArrangedSubview(button("Install Browser Bridge", action: #selector(installBridge)))
        actionRow.addArrangedSubview(button("Open Config Folder", action: #selector(openConfig)))
        stack.addArrangedSubview(actionRow)
        return page(stack)
    }

    private func aiPolishView() -> NSView {
        let localConfig = DictationLocalConfiguration.load()
        let stack = baseStack()
        stack.addArrangedSubview(pageTitle("Voice AI", "Choose cloud or private local transcription and enable safe spoken shortcuts."))

        let enginePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for engine in DictationTranscriptionEngine.allCases {
            enginePopup.addItem(withTitle: engine.title)
            enginePopup.lastItem?.representedObject = engine.rawValue
        }
        enginePopup.selectItem(withTitle: localConfig.engine.title)
        enginePopup.widthAnchor.constraint(equalToConstant: 260).isActive = true
        transcriptionEnginePopup = enginePopup
        stack.addArrangedSubview(polishFieldRow("Transcription", control: enginePopup))

        let status = label(ParakeetModelManager.statusText(), font: .systemFont(ofSize: 12))
        status.textColor = ParakeetModelManager.resolvedModelURL() == nil ? SettingsPalette.muted : .systemGreen
        status.widthAnchor.constraint(equalToConstant: 580).isActive = true
        parakeetStatusLabel = status
        stack.addArrangedSubview(polishFieldRow("Local model", control: status))

        let modelActions = horizontalStack(spacing: 10)
        let downloadButton = button("Download Parakeet (~465 MB)", action: #selector(downloadParakeetModel))
        parakeetDownloadButton = downloadButton
        modelActions.addArrangedSubview(downloadButton)
        if ParakeetModelManager.isValidModel(at: ParakeetModelManager.orcaModelURL) {
            let reuseButton = button("Use Orca Model", action: #selector(reuseOrcaParakeetModel))
            parakeetReuseButton = reuseButton
            modelActions.addArrangedSubview(reuseButton)
        }
        stack.addArrangedSubview(polishFieldRow("Model setup", control: modelActions))

        let voiceCommands = NSButton(checkboxWithTitle: "Allow “command <saved shortcut name>” voice commands", target: nil, action: nil)
        voiceCommands.state = localConfig.voiceCommandsEnabled ? .on : .off
        voiceCommandsCheck = voiceCommands
        stack.addArrangedSubview(polishFieldRow("Voice commands", control: voiceCommands))

        let attribution = label("Parakeet is downloaded only when requested and runs on-device. NVIDIA Parakeet TDT 0.6B v3 is CC-BY-4.0; STM uses Apache-2.0 sherpa-onnx.", font: .systemFont(ofSize: 11))
        attribution.textColor = SettingsPalette.muted
        attribution.widthAnchor.constraint(equalToConstant: 760).isActive = true
        stack.addArrangedSubview(attribution)

        stack.addArrangedSubview(button("Save Voice AI Settings", action: #selector(saveVoiceAISettings)))
        return page(stack)
    }

    private func permissionsView() -> NSView {
        let stack = baseStack()
        stack.addArrangedSubview(pageTitle("Permissions", "Green means ready. Red means the feature needs a grant or is off."))

        for key in ["Microphone", "Screen Recording", "Accessibility"] {
            let card = RoundedPanelView(fillColor: SettingsPalette.forest, strokeColor: SettingsPalette.stroke, radius: 8)
            let row = horizontalStack(spacing: 12)
            let dot = label("●", font: .systemFont(ofSize: 13))
            dot.widthAnchor.constraint(equalToConstant: 16).isActive = true
            let name = label(key, font: .boldSystemFont(ofSize: 13))
            name.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let status = label("")
            permissionDots[key] = dot
            permissionLabels[key] = status
            row.addArrangedSubview(dot)
            row.addArrangedSubview(name)
            row.addArrangedSubview(status)
            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                row.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
                card.widthAnchor.constraint(equalToConstant: 700)
            ])
            stack.addArrangedSubview(card)
        }

        let actionRow = horizontalStack(spacing: 10)
        actionRow.addArrangedSubview(button("Request Microphone", action: #selector(requestMicrophone)))
        actionRow.addArrangedSubview(button("Request Screen Recording", action: #selector(requestScreen)))
        actionRow.addArrangedSubview(button("Request Accessibility", action: #selector(requestAccessibility)))
        stack.addArrangedSubview(actionRow)

        let secondaryRow = horizontalStack(spacing: 10)
        secondaryRow.addArrangedSubview(button("Open Screen Recording Settings", action: #selector(openScreenSettings)))
        secondaryRow.addArrangedSubview(button("Reset Screen Recording Entry", action: #selector(resetScreenRecordingEntry)))
        secondaryRow.addArrangedSubview(button("Reset Accessibility Entry", action: #selector(resetAccessibilityEntry)))
        secondaryRow.addArrangedSubview(button("Import Credentials", action: #selector(importCredentials)))
        secondaryRow.addArrangedSubview(button("Refresh Status", action: #selector(refreshPermissionsAction)))
        stack.addArrangedSubview(secondaryRow)
        return page(stack)
    }

    private func featuresView() -> NSView {
        let outer = baseStack()
        outer.spacing = 12
        outer.addArrangedSubview(pageTitle("Features", "Toggle tools and record desktop shortcuts. Dictation can use Home. Other shortcuts should include Command or Control."))

        let header = horizontalStack(spacing: 10)
        header.addArrangedSubview(columnLabel("On", width: 38))
        header.addArrangedSubview(columnLabel("Feature", width: 235))
        header.addArrangedSubview(columnLabel("Current Shortcut", width: 190))
        header.addArrangedSubview(columnLabel("Actions", width: 260))
        outer.addArrangedSubview(header)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for feature in FeatureID.allCases {
            if feature.isTextTransformerChild {
                continue
            }
            stack.addArrangedSubview(featureRow(feature))
            if feature == .textTransformers {
                for child in FeatureID.textTransformerChildren {
                    stack.addArrangedSubview(featureRow(child, isChild: true))
                }
            }
            if feature == .commandShortcuts {
                stack.addArrangedSubview(commandShortcutHeaderRow())
                for item in ConfigStore.commandShortcuts() {
                    stack.addArrangedSubview(commandShortcutRow(item))
                }
            }
        }

        let listWidth: CGFloat = 820
        let listInset: CGFloat = 16
        let listVerticalInset: CGFloat = 14
        let rowCount = FeatureID.allCases.count + FeatureID.textTransformerChildren.count + ConfigStore.commandShortcuts().count
        let documentHeight = max(1320, 780 + rowCount * 82)
        let document = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: listWidth + listInset * 2, height: CGFloat(documentHeight)))
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: listInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -listInset),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: listVerticalInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -listVerticalInset),
            stack.widthAnchor.constraint(equalToConstant: listWidth)
        ])

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.backgroundColor = .clear
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 520).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 872).isActive = true
        outer.addArrangedSubview(scroll)
        return page(outer)
    }

    private func diagnosticsView() -> NSView {
        let stack = baseStack()
        stack.addArrangedSubview(pageTitle("Diagnostics", "Native host paths, logs, and local payload storage."))
        stack.addArrangedSubview(infoCard(rows: [
            ("Native host", "com.stm.desktop_listener"),
            ("Chrome host manifest", nativeHostPath(browser: "Google/Chrome")),
            ("Brave host manifest", nativeHostPath(browser: "BraveSoftware/Brave-Browser")),
            ("Debug log", AppPaths.logURL.path),
            ("Payloads", AppPaths.payloadDirectory.path)
        ]))
        let actionRow = horizontalStack(spacing: 10)
        actionRow.addArrangedSubview(button("Reveal Debug Log", action: #selector(revealDebugLog)))
        actionRow.addArrangedSubview(button("Open Config Folder", action: #selector(openConfig)))
        stack.addArrangedSubview(actionRow)
        return page(stack)
    }

    private func featureRow(_ feature: FeatureID, isChild: Bool = false) -> NSView {
        let row = RoundedPanelView(fillColor: isChild ? SettingsPalette.childRow : SettingsPalette.row, strokeColor: SettingsPalette.stroke, radius: isChild ? 7 : 8)
        featureRows[feature] = row

        let content = horizontalStack(spacing: 10)
        content.alignment = .centerY

        let enabled = OrangeFeatureToggle(frame: .zero)
        enabled.target = self
        enabled.action = #selector(toggleFeature(_:))
        enabled.state = ConfigStore.featureEnabled(feature) ? .on : .off
        enabled.tag = FeatureID.allCases.firstIndex(of: feature) ?? 0
        featureChecks[feature] = enabled
        content.addArrangedSubview(enabled)

        let nameStack = NSStackView()
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 2
        let title = label(feature.title, font: .boldSystemFont(ofSize: 13))
        title.textColor = SettingsPalette.text
        let detail = label(description(for: feature), font: .systemFont(ofSize: 11))
        detail.textColor = SettingsPalette.muted
        nameStack.addArrangedSubview(title)
        nameStack.addArrangedSubview(detail)
        nameStack.widthAnchor.constraint(equalToConstant: isChild ? 207 : 235).isActive = true
        content.addArrangedSubview(nameStack)

        let shortcutText = (feature == .textTransformers || feature == .commandShortcuts || feature == .mouseJiggler) ? "Menu" : (ConfigStore.shortcut(for: feature)?.label ?? "No hotkey")
        let shortcutBadge = createShortcutBadge(shortcutText)
        let shortcutLabel = shortcutBadge.label
        shortcutLabels[feature] = shortcutLabel
        content.addArrangedSubview(shortcutBadge.view)

        let actions = horizontalStack(spacing: 6)
        actions.widthAnchor.constraint(equalToConstant: 260).isActive = true
        if feature == .textTransformers || feature == .commandShortcuts || feature == .mouseJiggler {
            let hint = label(feature == .mouseJiggler ? "Use menu bar dropdown" : "Shortcuts appear below", font: .systemFont(ofSize: 12))
            hint.textColor = SettingsPalette.muted
            actions.addArrangedSubview(hint)
        } else {
            actions.addArrangedSubview(recordActionButton(feature: feature))
            actions.addArrangedSubview(actionButton("Clear", feature: feature, action: #selector(clearShortcut(_:)), width: 50))
            actions.addArrangedSubview(actionButton("Default", feature: feature, action: #selector(resetShortcut(_:)), width: 62))
            let chromeButton = actionButton("Chrome", feature: feature, action: #selector(applyChromeShortcut(_:)), width: 74)
            chromeButton.isEnabled = feature.chromeDefaultShortcut != nil
            actions.addArrangedSubview(chromeButton)
        }
        content.addArrangedSubview(actions)

        row.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: isChild ? 34 : 14),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            row.widthAnchor.constraint(equalToConstant: 820),
            row.heightAnchor.constraint(equalToConstant: isChild ? 68 : 74)
        ])
        return row
    }

    private func commandShortcutHeaderRow() -> NSView {
        let row = RoundedPanelView(fillColor: SettingsPalette.childRow, strokeColor: SettingsPalette.stroke, radius: 7)
        let content = horizontalStack(spacing: 10)
        let title = label("Saved command shortcuts", font: .boldSystemFont(ofSize: 12))
        title.textColor = SettingsPalette.text
        title.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let hint = label("Add one row per terminal command. Each row records its own shortcut.", font: .systemFont(ofSize: 11))
        hint.textColor = SettingsPalette.muted
        hint.widthAnchor.constraint(equalToConstant: 420).isActive = true
        content.addArrangedSubview(title)
        content.addArrangedSubview(hint)
        content.addArrangedSubview(actionButton("+", commandID: "", action: #selector(addCommandShortcut), width: 38))
        row.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 34),
            content.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            row.widthAnchor.constraint(equalToConstant: 820),
            row.heightAnchor.constraint(equalToConstant: 50)
        ])
        return row
    }

    private func commandShortcutRow(_ item: CommandShortcutDefinition) -> NSView {
        let row = RoundedPanelView(fillColor: SettingsPalette.childRow, strokeColor: SettingsPalette.stroke, radius: 7)
        let stack = baseStack()
        stack.spacing = 8

        let titleRow = horizontalStack(spacing: 8)
        let title = label(item.title.isEmpty ? "Command" : item.title, font: .boldSystemFont(ofSize: 12))
        title.textColor = SettingsPalette.text
        title.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let shortcutBadge = createShortcutBadge(item.shortcutLabel)
        commandShortcutLabels[item.id] = shortcutBadge.label
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(shortcutBadge.view)
        titleRow.addArrangedSubview(recordCommandButton(commandID: item.id))
        titleRow.addArrangedSubview(actionButton("Clear", commandID: item.id, action: #selector(clearCommandShortcut(_:)), width: 50))
        titleRow.addArrangedSubview(actionButton("Delete", commandID: item.id, action: #selector(deleteCommandShortcut(_:)), width: 58))
        stack.addArrangedSubview(titleRow)

        let controls = horizontalStack(spacing: 8)
        let field = CommandTextField(string: item.command)
        field.placeholderString = "sudo killall replayd ControlCenter screencapture"
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = SettingsPalette.text
        field.backgroundColor = SettingsPalette.badge
        field.drawsBackground = true
        field.isBordered = false
        field.wantsLayer = true
        field.layer?.cornerRadius = 7
        field.layer?.backgroundColor = SettingsPalette.badge.cgColor
        field.layer?.borderWidth = 1
        field.layer?.borderColor = SettingsPalette.badgeStroke.cgColor
        field.target = self
        field.action = #selector(saveCommandShortcutField(_:))
        field.identifier = NSUserInterfaceItemIdentifier(item.id)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 650).isActive = true
        field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        commandShortcutFields[item.id] = field
        controls.addArrangedSubview(field)
        controls.addArrangedSubview(actionButton("Save", commandID: item.id, action: #selector(saveCommandShortcut(_:)), width: 58))
        stack.addArrangedSubview(controls)

        let hint = label("Only this row's saved command runs when its shortcut fires. Commands starting with sudo use the macOS administrator prompt.", font: .systemFont(ofSize: 11))
        hint.textColor = SettingsPalette.muted
        hint.widthAnchor.constraint(equalToConstant: 720).isActive = true
        stack.addArrangedSubview(hint)

        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            row.widthAnchor.constraint(equalToConstant: 820),
            row.heightAnchor.constraint(equalToConstant: 140)
        ])
        return row
    }

    private func description(for feature: FeatureID) -> String {
        switch feature {
        case .screenshot: return "Captures a desktop region and opens the native editor instantly."
        case .ocr: return "Captures a region, extracts text locally, then copies it."
        case .dictation: return "Transcribes with the selected engine, then formats spoken commands and punctuation."
        case .dictationPolish: return "Uses the same exact-word dictation pipeline with an alternate shortcut."
        case .textTransformers: return "Enables the individual transformer shortcuts below."
        case .textCapitalCase: return "Selected or clipboard text into Capital Case."
        case .textLowerCase: return "Selected or clipboard text into lower case."
        case .textUpperCase: return "Selected or clipboard text into UPPER CASE."
        case .textSentenceCase: return "Selected or clipboard text into sentence case."
        case .textSlugify: return "Selected or clipboard text into a URL slug."
        case .colorPicker: return "Click any desktop pixel to copy its hex value."
        case .pixelMeasurement: return "Measures a desktop region and keeps the outline visible."
        case .imageOptimizer: return "Sends Finder or clipboard images to the browser optimizer."
        case .copyFinderPath: return "Copies selected Finder paths or the current Finder folder."
        case .newFile: return "Creates a named file in the current Finder folder."
        case .mouseJiggler: return "Moves the mouse every 1, 2, or 5 minutes. Never clicks."
        case .commandShortcuts: return "Runs one saved terminal command from a recorded shortcut."
        }
    }

    private func page(_ view: NSView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = SettingsPalette.root.cgColor

        let panel = RoundedPanelView(fillColor: SettingsPalette.panel, strokeColor: SettingsPalette.stroke, radius: 10)
        panel.addSubview(view)
        container.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            panel.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -28),
            view.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 24),
            view.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -24),
            view.topAnchor.constraint(equalTo: panel.topAnchor, constant: 24),
            view.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -24)
        ])
        return container
    }

    private func pageTitle(_ title: String, _ subtitle: String) -> NSView {
        let stack = baseStack()
        stack.spacing = 4
        let titleLabel = label(title, font: .boldSystemFont(ofSize: 24))
        titleLabel.textColor = SettingsPalette.text
        let subtitleLabel = label(subtitle, font: .systemFont(ofSize: 13))
        subtitleLabel.textColor = SettingsPalette.muted
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        return stack
    }

    private func infoCard(rows: [(String, String)]) -> NSView {
        let card = RoundedPanelView(fillColor: SettingsPalette.forest, strokeColor: SettingsPalette.stroke, radius: 8)
        let stack = baseStack()
        stack.spacing = 12
        for rowData in rows {
            let row = horizontalStack(spacing: 12)
            let key = label(rowData.0, font: .boldSystemFont(ofSize: 12))
            key.textColor = SettingsPalette.muted
            key.widthAnchor.constraint(equalToConstant: 145).isActive = true
            let value = label(rowData.1, font: .systemFont(ofSize: 12))
            value.textColor = SettingsPalette.text
            row.addArrangedSubview(key)
            row.addArrangedSubview(value)
            stack.addArrangedSubview(row)
        }
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),
            card.widthAnchor.constraint(equalToConstant: 760)
        ])
        return card
    }

    private func textInput(_ value: String, placeholder: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12)
        field.textColor = SettingsPalette.text
        field.backgroundColor = SettingsPalette.badge
        field.drawsBackground = true
        field.isBordered = false
        field.wantsLayer = true
        field.layer?.cornerRadius = 7
        field.layer?.backgroundColor = SettingsPalette.badge.cgColor
        field.layer?.borderWidth = 1
        field.layer?.borderColor = SettingsPalette.badgeStroke.cgColor
        field.widthAnchor.constraint(equalToConstant: 420).isActive = true
        field.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return field
    }

    private func secureInput(_ value: String, placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.stringValue = value
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12)
        field.textColor = SettingsPalette.text
        field.backgroundColor = SettingsPalette.badge
        field.drawsBackground = true
        field.isBordered = false
        field.wantsLayer = true
        field.layer?.cornerRadius = 7
        field.layer?.backgroundColor = SettingsPalette.badge.cgColor
        field.layer?.borderWidth = 1
        field.layer?.borderColor = SettingsPalette.badgeStroke.cgColor
        field.widthAnchor.constraint(equalToConstant: 420).isActive = true
        field.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return field
    }

    private func polishFieldRow(_ title: String, control: NSView, credentialValue: String? = nil) -> NSView {
        let row = horizontalStack(spacing: 12)
        let key = label(title, font: .boldSystemFont(ofSize: 12))
        key.textColor = SettingsPalette.muted
        key.widthAnchor.constraint(equalToConstant: 165).isActive = true
        row.addArrangedSubview(key)
        row.addArrangedSubview(control)
        if let credentialValue = credentialValue {
            let filled = !credentialValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let status = label(filled ? "● Saved" : "○ Not saved", font: .systemFont(ofSize: 12))
            status.textColor = filled ? .systemGreen : SettingsPalette.muted
            status.widthAnchor.constraint(equalToConstant: 90).isActive = true
            row.addArrangedSubview(status)
        }
        return row
    }


    private func selectedTranscriptionEngine() -> DictationTranscriptionEngine {
        guard let raw = transcriptionEnginePopup?.selectedItem?.representedObject as? String else {
            return .worker
        }
        return DictationTranscriptionEngine(rawValue: raw) ?? .worker
    }


    private func baseStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func horizontalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 13)) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = .labelColor
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func columnLabel(_ text: String, width: CGFloat) -> NSTextField {
        let field = label(text, font: .boldSystemFont(ofSize: 11))
        field.textColor = SettingsPalette.muted
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    private func button(_ title: String, action: Selector) -> STMActionButton {
        let button = STMActionButton(title: title, target: self, action: action)
        button.font = .boldSystemFont(ofSize: 12)
        button.toolTip = title
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }

    private func actionButton(_ title: String, feature: FeatureID, action: Selector, width: CGFloat) -> STMActionButton {
        let button = STMActionButton(title: title, target: self, action: action)
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.toolTip = title
        button.tag = FeatureID.allCases.firstIndex(of: feature) ?? 0
        button.destructive = title.localizedCaseInsensitiveContains("delete")
        button.accentColor = button.destructive ? SettingsPalette.red : nil
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func actionButton(_ title: String, commandID: String, action: Selector, width: CGFloat) -> STMActionButton {
        let button = STMActionButton(title: title, target: self, action: action)
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.toolTip = title
        button.identifier = NSUserInterfaceItemIdentifier(commandID)
        button.destructive = title.localizedCaseInsensitiveContains("delete")
        button.accentColor = button.destructive ? SettingsPalette.red : nil
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func recordActionButton(feature: FeatureID) -> STMActionButton {
        let button = STMActionButton(title: "●", target: self, action: #selector(recordShortcut(_:)))
        button.font = .systemFont(ofSize: 10, weight: .bold)
        button.toolTip = "Record shortcut"
        button.tag = FeatureID.allCases.firstIndex(of: feature) ?? 0
        button.accentColor = SettingsPalette.red.withAlphaComponent(0.8)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func recordCommandButton(commandID: String) -> STMActionButton {
        let button = STMActionButton(title: "●", target: self, action: #selector(recordCommandShortcut(_:)))
        button.font = .systemFont(ofSize: 10, weight: .bold)
        button.toolTip = "Record shortcut"
        button.identifier = NSUserInterfaceItemIdentifier(commandID)
        button.accentColor = SettingsPalette.red.withAlphaComponent(0.8)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func createShortcutBadge(_ text: String) -> (view: NSView, label: NSTextField) {
        let badge = RoundedPanelView(fillColor: SettingsPalette.badge, strokeColor: SettingsPalette.badgeStroke, radius: 6)
        let value = label(text, font: .monospacedSystemFont(ofSize: 11, weight: .semibold))
        value.textColor = SettingsPalette.text
        value.alignment = .center
        value.lineBreakMode = .byTruncatingMiddle
        value.maximumNumberOfLines = 1
        badge.addSubview(value)
        NSLayoutConstraint.activate([
            value.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 10),
            value.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -10),
            value.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 190),
            badge.heightAnchor.constraint(equalToConstant: 28)
        ])
        return (badge, value)
    }

    private func nativeHostPath(browser: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(browser)/NativeMessagingHosts/com.stm.desktop_listener.json")
            .path
    }

    private func refreshPermissions() {
        setPermission("Microphone", status: PermissionCenter.microphoneStatusText(), ready: PermissionCenter.microphoneStatusText() == "Ready")
        setPermission("Screen Recording", status: PermissionCenter.screenStatusText(), ready: PermissionCenter.screenStatusText() == "Ready")
        setPermission("Accessibility", status: PermissionCenter.accessibilityStatusText(), ready: PermissionCenter.accessibilityStatusText() == "Ready")
    }

    private func setPermission(_ key: String, status: String, ready: Bool) {
        permissionLabels[key]?.stringValue = status
        permissionDots[key]?.textColor = ready ? .systemGreen : .systemRed
    }

    private func refreshFeatures() {
        let textTransformersEnabled = ConfigStore.featureEnabled(.textTransformers)
        for feature in FeatureID.allCases {
            featureChecks[feature]?.state = ConfigStore.featureEnabled(feature) ? .on : .off
            shortcutLabels[feature]?.stringValue = (feature == .textTransformers || feature == .commandShortcuts) ? "Group" : (ConfigStore.shortcut(for: feature)?.label ?? "No hotkey")
            if feature.isTextTransformerChild {
                featureRows[feature]?.isHidden = !textTransformersEnabled
            }
        }
        for item in ConfigStore.commandShortcuts() {
            commandShortcutLabels[item.id]?.stringValue = item.shortcutLabel
            commandShortcutFields[item.id]?.stringValue = item.command
        }
    }

    private func rebuildContentView() {
        stopRecordingShortcut()
        permissionLabels.removeAll()
        permissionDots.removeAll()
        shortcutLabels.removeAll()
        featureChecks.removeAll()
        featureRows.removeAll()
        commandShortcutLabels.removeAll()
        commandShortcutFields.removeAll()
        sidebarButtons.removeAll()
        window?.contentView = buildContent()
        selectSection(selectedSection)
        refreshPermissions()
        refreshFeatures()
    }

    private func selectSection(_ identifier: String) {
        selectedSection = identifier
        tabView?.selectTabViewItem(withIdentifier: identifier)
        updateSidebarSelection()
    }

    private func updateSidebarSelection() {
        for (identifier, button) in sidebarButtons {
            let selected = identifier == selectedSection
            if let sidebarButton = button as? SidebarNavButton {
                sidebarButton.selected = selected
            } else {
                button.layer?.backgroundColor = selected ? SettingsPalette.selected.cgColor : NSColor.clear.cgColor
                button.contentTintColor = selected ? .white : SettingsPalette.muted
            }
        }
    }

    @objc private func selectSidebarSection(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        selectSection(identifier)
    }

    @objc private func toggleFeature(_ sender: NSButton) {
        guard FeatureID.allCases.indices.contains(sender.tag) else { return }
        let feature = FeatureID.allCases[sender.tag]
        do {
            try ConfigStore.setFeatureEnabled(sender.state == .on, feature: feature)
            onSettingsChanged()
            refreshPermissions()
            refreshFeatures()
        } catch {
            sender.state = sender.state == .on ? .off : .on
            showError("Save failed", error.localizedDescription)
        }
    }

    @objc private func recordShortcut(_ sender: NSControl) {
        guard FeatureID.allCases.indices.contains(sender.tag) else { return }
        let feature = FeatureID.allCases[sender.tag]
        startRecordingShortcut(for: feature)
    }

    @objc private func clearShortcut(_ sender: NSControl) {
        guard FeatureID.allCases.indices.contains(sender.tag) else { return }
        let feature = FeatureID.allCases[sender.tag]
        do {
            try ConfigStore.setShortcut(nil, feature: feature)
            onSettingsChanged()
            refreshFeatures()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }

    @objc private func resetShortcut(_ sender: NSControl) {
        guard FeatureID.allCases.indices.contains(sender.tag) else { return }
        let feature = FeatureID.allCases[sender.tag]
        do {
            try ConfigStore.resetShortcut(feature: feature)
            onSettingsChanged()
            refreshFeatures()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }

    @objc private func applyChromeShortcut(_ sender: NSControl) {
        guard FeatureID.allCases.indices.contains(sender.tag) else { return }
        let feature = FeatureID.allCases[sender.tag]
        guard let shortcut = feature.chromeDefaultShortcut else { return }
        do {
            try ConfigStore.setShortcut(shortcut, feature: feature)
            onSettingsChanged()
            refreshFeatures()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }

    @objc private func addCommandShortcut() {
        do {
            var items = ConfigStore.commandShortcuts()
            items.append(CommandShortcutDefinition.create())
            try ConfigStore.setCommandShortcuts(items)
            onSettingsChanged()
            rebuildContentView()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }

    @objc private func saveCommandShortcut(_ sender: NSControl) {
        guard let id = sender.identifier?.rawValue else { return }
        saveCommandShortcut(id: id)
    }

    @objc private func saveCommandShortcutField(_ sender: NSTextField) {
        guard let id = sender.identifier?.rawValue else { return }
        saveCommandShortcut(id: id)
    }

    private func saveCommandShortcut(id: String) {
        do {
            guard var item = ConfigStore.commandShortcuts().first(where: { $0.id == id }) else { return }
            item.command = commandShortcutFields[id]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try ConfigStore.updateCommandShortcut(item)
            onSettingsChanged()
            refreshFeatures()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }


    @objc private func saveVoiceAISettings() {
        do {
            let transcriptionEngine = selectedTranscriptionEngine()
            if transcriptionEngine == .parakeet && ParakeetModelManager.resolvedModelURL() == nil {
                throw SimpleError("Download Parakeet or select Orca's existing model before enabling local transcription.")
            }
            let existingLocalConfig = DictationLocalConfiguration.load()
            let localConfig = DictationLocalConfiguration(
                engine: transcriptionEngine,
                modelPath: existingLocalConfig.modelPath,
                voiceCommandsEnabled: voiceCommandsCheck?.state == .on
            )
            try localConfig.save()

            onSettingsChanged()
            rebuildContentView()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }
    @objc private func reuseOrcaParakeetModel() {
        do {
            _ = try ParakeetModelManager.selectOrcaModel()
            try ConfigStore.set(DictationTranscriptionEngine.parakeet.rawValue, for: DictationLocalConfiguration.engineKey)
            onSettingsChanged()
            rebuildContentView()
        } catch {
            showError("Parakeet setup failed", error.localizedDescription)
        }
    }

    @objc private func downloadParakeetModel() {
        parakeetDownloadButton?.isEnabled = false
        parakeetReuseButton?.isEnabled = false
        parakeetStatusLabel?.stringValue = "Downloading and verifying Parakeet…"
        Task { [weak self] in
            do {
                _ = try await Task.detached {
                    try await ParakeetModelManager.download()
                }.value
                try ConfigStore.set(DictationTranscriptionEngine.parakeet.rawValue, for: DictationLocalConfiguration.engineKey)
                await MainActor.run {
                    guard let self = self else { return }
                    self.onSettingsChanged()
                    self.rebuildContentView()
                }
            } catch {
                await MainActor.run {
                    guard let self = self else { return }
                    self.parakeetDownloadButton?.isEnabled = true
                    self.parakeetReuseButton?.isEnabled = true
                    self.parakeetStatusLabel?.stringValue = ParakeetModelManager.statusText()
                    self.showError("Parakeet download failed", error.localizedDescription)
                }
            }
        }
    }



    @objc private func recordCommandShortcut(_ sender: NSControl) {
        guard let id = sender.identifier?.rawValue else { return }
        startRecordingCommandShortcut(id: id)
    }

    @objc private func clearCommandShortcut(_ sender: NSControl) {
        guard let id = sender.identifier?.rawValue else { return }
        do {
            guard var item = ConfigStore.commandShortcuts().first(where: { $0.id == id }) else { return }
            item.shortcut = nil
            try ConfigStore.updateCommandShortcut(item)
            onSettingsChanged()
            refreshFeatures()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }

    @objc private func deleteCommandShortcut(_ sender: NSControl) {
        guard let id = sender.identifier?.rawValue else { return }
        do {
            try ConfigStore.deleteCommandShortcut(id: id)
            onSettingsChanged()
            rebuildContentView()
        } catch {
            showError("Save failed", error.localizedDescription)
        }
    }

    private func startRecordingShortcut(for feature: FeatureID) {
        stopRecordingShortcut()
        recordingFeature = feature
        shortcutLabels[feature]?.stringValue = "Press keys..."
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureShortcut(event)
            return nil
        }
    }

    private func startRecordingCommandShortcut(id: String) {
        stopRecordingShortcut()
        recordingCommandShortcutID = id
        commandShortcutLabels[id]?.stringValue = "Press keys..."
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureShortcut(event)
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let recordingMonitor = recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        recordingFeature = nil
        recordingCommandShortcutID = nil
    }

    private func captureShortcut(_ event: NSEvent) {
        if let commandID = recordingCommandShortcutID {
            captureCommandShortcut(event, commandID: commandID)
            return
        }
        guard let feature = recordingFeature else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecordingShortcut()
            refreshFeatures()
            return
        }
        let allowPlainKey = feature == .dictation
        guard let shortcut = Shortcut(event: event, allowPlainKey: allowPlainKey) else {
            let title = allowPlainKey ? "Shortcut was not captured" : "Shortcut needs Command or Control"
            let message = allowPlainKey ? "Press a real key such as Home, Page Up, or a key with modifiers." : "Use a shortcut that includes Command or Control."
            showError(title, message)
            stopRecordingShortcut()
            refreshFeatures()
            return
        }
        do {
            try ConfigStore.setShortcut(shortcut, feature: feature)
            stopRecordingShortcut()
            onSettingsChanged()
            refreshFeatures()
        } catch {
            stopRecordingShortcut()
            refreshFeatures()
            showError("Save failed", error.localizedDescription)
        }
    }

    private func captureCommandShortcut(_ event: NSEvent, commandID: String) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecordingShortcut()
            refreshFeatures()
            return
        }
        guard let shortcut = Shortcut(event: event) else {
            showError("Shortcut needs Command or Control", "Use a shortcut that includes Command or Control.")
            stopRecordingShortcut()
            refreshFeatures()
            return
        }
        do {
            guard var item = ConfigStore.commandShortcuts().first(where: { $0.id == commandID }) else { return }
            item.shortcut = shortcut.serialized
            item.command = commandShortcutFields[commandID]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? item.command
            try ConfigStore.updateCommandShortcut(item)
            stopRecordingShortcut()
            onSettingsChanged()
            refreshFeatures()
        } catch {
            stopRecordingShortcut()
            refreshFeatures()
            showError("Save failed", error.localizedDescription)
        }
    }

    @objc private func importCredentials() {
        onImportCredentials()
    }

    @objc private func installBridge() {
        onInstallBridge()
    }

    @objc private func openConfig() {
        onOpenConfig()
    }

    @objc private func revealDebugLog() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: AppPaths.logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logURL])
        } else {
            NSWorkspace.shared.open(AppPaths.logURL.deletingLastPathComponent())
        }
    }

    @objc private func openPoweredBy() {
        guard let url = URL(string: "https://seotimemachines.com/") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func requestMicrophone() {
        PermissionCenter.requestMicrophone { self.refreshPermissions() }
    }

    @objc private func requestScreen() {
        _ = PermissionCenter.requestScreen()
        if PermissionCenter.screenStatusText() != "Ready" {
            PermissionCenter.openScreenRecordingSettings()
        }
        refreshPermissions()
    }

    @objc private func openScreenSettings() {
        PermissionCenter.openScreenRecordingSettings()
        refreshPermissions()
    }

    @objc private func requestAccessibility() {
        _ = PermissionCenter.requestAccessibility()
        refreshPermissions()
        for delay in [1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.refreshPermissions()
            }
        }
    }

    @objc private func resetAccessibilityEntry() {
        PermissionCenter.resetAccessibilityEntry()
        refreshPermissions()
    }

    @objc private func resetScreenRecordingEntry() {
        PermissionCenter.resetScreenRecordingEntry()
        refreshPermissions()
    }

    @objc private func refreshPermissionsAction() {
        refreshPermissions()
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

}
