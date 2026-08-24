import Cocoa

final class STMPopoverViewController: NSViewController {
    weak var app: AppDelegate?

    private enum Layout {
        static let popoverWidth: CGFloat = 640
        static let contentWidth: CGFloat = 600
        static let innerWidth: CGFloat = 552
        static let buttonWidth: CGFloat = 270
        static let gridGap: CGFloat = 12
        static let buttonHeight: CGFloat = 38
        static let tabHeight: CGFloat = 34
    }

    private enum Tab: String, CaseIterable {
        case features
        case dictation
        case power
        case mouse
        case permissions
        case tools

        var title: String {
            switch self {
            case .features: return "Features"
            case .dictation: return "Dictation"
            case .power: return "Power"
            case .mouse: return "Mouse"
            case .permissions: return "Permissions"
            case .tools: return "Tools"
            }
        }
    }

    private struct ActionSpec {
        let title: String
        let action: Selector
        let enabled: Bool
        let accent: NSColor?
        let destructive: Bool
    }

    private let scrollView = NSScrollView()
    private let rootStack = NSStackView()
    private let tabRow = NSStackView()
    private let contentStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var selectedTab: Tab = .features
    private var tabButtons: [Tab: STMActionButton] = [:]

    private var cyan: NSColor { NSColor(calibratedRed: 0.07, green: 0.99, blue: 1.0, alpha: 1) }
    private var amber: NSColor { NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1) }
    private var green: NSColor { NSColor(calibratedRed: 0.29, green: 0.86, blue: 0.52, alpha: 1) }
    private var red: NSColor { NSColor(calibratedRed: 1.0, green: 0.33, blue: 0.36, alpha: 1) }
    private var forestPanel: NSColor { NSColor(calibratedRed: 24.0 / 255.0, green: 43.0 / 255.0, blue: 44.0 / 255.0, alpha: 1) }
    private var forestStroke: NSColor { NSColor(calibratedRed: 0.22, green: 0.40, blue: 0.40, alpha: 1) }
    private var panel: NSColor { NSColor(calibratedRed: 0.090, green: 0.090, blue: 0.090, alpha: 1) }
    private var panelSoft: NSColor { NSColor(calibratedRed: 0.090, green: 0.090, blue: 0.090, alpha: 1) }
    private var selectedPanel: NSColor { NSColor(calibratedRed: 0.090, green: 0.090, blue: 0.090, alpha: 1) }
    private var stroke: NSColor { NSColor(calibratedWhite: 0.29, alpha: 1) }
    private var muted: NSColor { NSColor(calibratedWhite: 0.74, alpha: 1) }

    override func loadView() {
        let root = STMMenuBackdropView(frame: NSRect(x: 0, y: 0, width: Layout.popoverWidth, height: 780))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.020, green: 0.024, blue: 0.027, alpha: 0.99).cgColor
        view = root

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.edgeInsets = NSEdgeInsets(top: 22, left: 20, bottom: 24, right: 20)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rootStack)
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor),
            rootStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: document.topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor)
        ])

        buildShell()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func refresh() {
        let model = TranscriptionModel.load()
        let power = SystemPowerController.quickStatusTitle()
        let mouse = app?.menuMouseStatusTitle ?? "Mouse Jiggler: Off"
        statusLabel.attributedStringValue = heroStatusText(model: model.label, power: power, mouse: mouse)
        updateTabButtons()
        rebuildContent()
    }

    private func buildShell() {
        rootStack.addArrangedSubview(hero())
        rootStack.addArrangedSubview(tabs())

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(contentStack)

        rebuildContent()
    }

    private func hero() -> NSView {
        let container = softPanel()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = appIconView()

        let texts = NSStackView()
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 5
        texts.addArrangedSubview(label("STM Desktop Listener", size: 21, weight: .bold, color: .white))
        texts.addArrangedSubview(label("Fast capture, dictation, power control, and local utilities", size: 12, weight: .medium, color: muted))
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.maximumNumberOfLines = 2
        texts.addArrangedSubview(statusLabel)

        row.addArrangedSubview(icon)
        row.addArrangedSubview(texts)
        container.addSubview(row)
        pin(row, to: container, inset: 20)
        return container
    }

    private func heroStatusText(model: String, power: String, mouse: String) -> NSAttributedString {
        let text = NSMutableAttributedString()
        appendHeroStatus("Dictation: \(model)", to: text, color: cyan)
        appendHeroSeparator(to: text)
        appendHeroState(power, to: text)
        appendHeroSeparator(to: text)
        appendHeroState(mouse, to: text)
        return text
    }

    private func appendHeroState(_ value: String, to text: NSMutableAttributedString) {
        if value.localizedCaseInsensitiveContains(": Off") {
            let prefix = value.replacingOccurrences(of: ": Off", with: ":")
            appendHeroStatus(prefix + " ", to: text)
            appendHeroDot(red, to: text)
        } else if value.localizedCaseInsensitiveContains(": On") {
            let prefix = value.replacingOccurrences(of: ": On", with: ":")
            appendHeroStatus(prefix + " ", to: text, color: cyan)
            appendHeroDot(green, to: text)
            appendHeroStatus(" On", to: text, color: cyan)
        } else {
            appendHeroStatus(value, to: text, color: cyan)
        }
    }

    private func appendHeroSeparator(to text: NSMutableAttributedString) {
        appendHeroStatus("  ·  ", to: text)
    }

    private func appendHeroDot(_ color: NSColor, to text: NSMutableAttributedString) {
        text.append(NSAttributedString(string: "●", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: color
        ]))
    }

    private func appendHeroStatus(_ value: String, to text: NSMutableAttributedString, color: NSColor = .white) {
        text.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: color
        ]))
    }

    private func tabs() -> NSView {
        let container = softPanel()
        tabRow.orientation = .horizontal
        tabRow.alignment = .centerY
        tabRow.spacing = 8
        tabRow.distribution = .fillEqually
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabRow.widthAnchor.constraint(equalToConstant: Layout.innerWidth).isActive = true

        for tab in Tab.allCases {
            let button = STMActionButton(title: tab.title, target: self, action: #selector(selectTab(_:)))
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.identifier = NSUserInterfaceItemIdentifier(tab.rawValue)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: Layout.tabHeight).isActive = true
            button.toolTip = "Show \(tab.title) controls"
            tabButtons[tab] = button
            tabRow.addArrangedSubview(button)
        }

        container.addSubview(tabRow)
        pin(tabRow, to: container, inset: 16)
        updateTabButtons()
        return container
    }

    @objc private func selectTab(_ sender: STMActionButton) {
        guard let raw = sender.identifier?.rawValue, let tab = Tab(rawValue: raw) else { return }
        selectedTab = tab
        refresh()
    }

    private func updateTabButtons() {
        for (tab, button) in tabButtons {
            let selected = tab == selectedTab
            button.state = selected ? .on : .off
            button.accentColor = selected ? amber : nil
        }
    }

    private func rebuildContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch selectedTab {
        case .features: contentStack.addArrangedSubview(featuresCard())
        case .dictation: contentStack.addArrangedSubview(dictationCard())
        case .power: contentStack.addArrangedSubview(powerCard())
        case .mouse: contentStack.addArrangedSubview(mouseCard())
        case .permissions: contentStack.addArrangedSubview(permissionsCard())
        case .tools: contentStack.addArrangedSubview(toolsCard())
        }
    }

    private func featuresCard() -> NSView {
        var rows: [NSView] = [
            infoBox("Enable only the utilities you want hotkeys for. Text transformer children stay grouped under the text transformer parent.")
        ]
        for feature in FeatureID.allCases where !feature.isTextTransformerChild {
            rows.append(featureRow(feature))
        }
        rows.append(divider())
        rows.append(groupTitle("Text transformer commands", symbol: "textformat"))
        for feature in FeatureID.textTransformerChildren {
            rows.append(featureRow(feature, dependentOn: .textTransformers))
        }
        rows.append(fullWidthButton("Open Feature Settings", #selector(openFeatureSettings)))
        return card(title: "Features", symbol: "sparkles", subtitle: "Visible toggles replace the old nested menu.", views: rows)
    }

    private func dictationCard() -> NSView {
        let current = TranscriptionModel.load()
        var rows: [NSView] = [
            infoBox("Choose the transcription model here. Local Parakeet and spoken commands are configured in Voice AI settings."),
            groupTitle("Model", symbol: "waveform")
        ]
        for model in TranscriptionModel.all {
            rows.append(modelRow(model, selected: model.id == current.id))
        }
        rows.append(divider())
        rows.append(featureRow(.dictation))
        rows.append(featureRow(.dictationPolish))
        rows.append(buttonGrid([
            action("Voice AI Settings", #selector(openAIPolishSettings))
        ]))
        return card(title: "Dictation", symbol: "waveform", subtitle: "Model, dictation, and polish controls in one tab.", views: rows)
    }

    private func powerCard() -> NSView {
        var rows: [NSView] = [
            statusPanel(title: "Current power status", value: SystemPowerController.quickStatusTitle(), color: activeStatusColor(SystemPowerController.quickStatusTitle()))
        ]
        let statusLines = SystemPowerController.menuStatusLines()
        if !statusLines.isEmpty {
            rows.append(infoBox(statusLines.joined(separator: "\n")))
        }
        rows.append(groupTitle("Shutdown", symbol: "power"))
        rows.append(buttonGrid([
            action("Shut Down at 8am", #selector(shutdown8)),
            action("Shut Down in 2.5h", #selector(shutdown25))
        ]))
        rows.append(fullWidthButton("Schedule Shut Down...", #selector(scheduleShutdown)))
        rows.append(groupTitle("Sleep", symbol: "moon.zzz"))
        rows.append(buttonGrid([
            action("Sleep in 1h", #selector(sleep1)),
            action("Sleep in 2.5h", #selector(sleep25))
        ]))
        rows.append(fullWidthButton("Schedule Sleep...", #selector(scheduleSleep)))
        rows.append(groupTitle("Keep Awake", symbol: "sun.max"))
        rows.append(buttonGrid([
            action("Until 8am", #selector(awake8)),
            action("For 2.5h", #selector(awake25))
        ]))
        rows.append(fullWidthButton("Keep Awake...", #selector(keepAwakeCustom)))
        rows.append(groupTitle("Manage", symbol: "slider.horizontal.3"))
        rows.append(buttonGrid([
            action("Power Status", #selector(powerStatus)),
            action("Copy Status", #selector(copyPowerStatus)),
            action("Open Power Log", #selector(openPowerLog)),
            action("Notifications", #selector(openNotifications)),
            action("Run Git Autosave", #selector(gitAutosave)),
            action("Cancel Schedule", #selector(cancelPower), destructive: true)
        ]))
        rows.append(fullWidthButton("Stop Keep Awake", #selector(stopAwake), quiet: true))
        return card(title: "Power", symbol: "bolt.circle", subtitle: "Power actions are grouped by outcome instead of hidden in a submenu.", views: rows)
    }

    private func mouseCard() -> NSView {
        let enabled = app?.menuFeatureEnabled(.mouseJiggler) ?? ConfigStore.featureEnabled(.mouseJiggler)
        var rows: [NSView] = [
            statusPanel(title: "Mouse Jiggler", value: app?.menuMouseStatusTitle ?? "Mouse Jiggler: Off", color: enabled ? cyan : amber),
            featureRow(.mouseJiggler)
        ]
        if let lines = app?.menuMouseStatusLines, !lines.isEmpty {
            rows.append(infoBox(lines.joined(separator: "\n")))
        }
        rows.append(groupTitle("Start infinite", symbol: "infinity"))
        rows.append(buttonGrid([
            action("Every 1 min", #selector(mouseInfinite1), enabled: enabled),
            action("Every 2 min", #selector(mouseInfinite2), enabled: enabled),
            action("Every 5 min", #selector(mouseInfinite5), enabled: enabled)
        ]))
        rows.append(groupTitle("Start timed", symbol: "timer"))
        rows.append(buttonGrid([
            action("30m · Every 1 min", #selector(mouse30m), enabled: enabled),
            action("1h · Every 2 min", #selector(mouse1h), enabled: enabled),
            action("2h · Every 5 min", #selector(mouse2h), enabled: enabled)
        ]))
        rows.append(buttonGrid([
            action("Start Custom...", #selector(mouseCustom), enabled: enabled),
            action("Stop Mouse Jiggler", #selector(mouseStop), enabled: enabled || (app?.menuMouseIsActive ?? false))
        ]))
        return card(title: "Mouse Jiggler", symbol: "computermouse", subtitle: "Fast presets, explicit status, no right-side submenu.", views: rows)
    }

    private func permissionsCard() -> NSView {
        card(title: "Permissions", symbol: "checkmark.shield", subtitle: "Grant required macOS permissions from one visible panel.", views: [
            permissionRow("Microphone", status: PermissionCenter.microphoneStatusText(), actionTitle: "Request", action: #selector(requestMicrophone)),
            permissionRow("Screen Recording", status: PermissionCenter.screenStatusText(), actionTitle: "Request", action: #selector(requestScreen)),
            buttonGrid([
                action("Open Screen Settings", #selector(openScreenSettings)),
                action("Reset Screen Entry", #selector(resetScreenEntry))
            ]),
            permissionRow("Accessibility", status: PermissionCenter.accessibilityStatusText(), actionTitle: "Request", action: #selector(requestAccessibility)),
            buttonGrid([
                action("Reset Accessibility", #selector(resetAccessibility)),
                action("Import Credentials", #selector(importCredentials))
            ])
        ])
    }

    private func toolsCard() -> NSView {
        let checkingForUpdates = app?.menuUpdateCheckInProgress ?? false
        return card(title: "Tools", symbol: "wrench.and.screwdriver", subtitle: "Settings, credentials, integrations, and app maintenance.", views: [
            infoBox("Updates download a verified DMG to Downloads. STM never installs or replaces the app."),
            buttonGrid([
                action("Open Settings", #selector(openSettings)),
                action("Import Credentials", #selector(importCredentials)),
                action("Install Browser Bridge", #selector(installBrowserBridge)),
                action("Open Config Folder", #selector(openConfigFolder)),
                action(
                    checkingForUpdates ? "Checking for Updates..." : "Check for Updates",
                    #selector(checkForUpdates),
                    enabled: !checkingForUpdates,
                    accent: cyan
                )
            ]),
            divider(),
            fullWidthButton("Quit STM Desktop Listener", #selector(quitApp), quiet: true, destructive: true)
        ])
    }

    private func featureRow(_ feature: FeatureID, dependentOn parent: FeatureID? = nil) -> NSView {
        let enabled = app?.menuFeatureEnabled(feature) ?? ConfigStore.featureEnabled(feature)
        let parentEnabled = parent.map { app?.menuFeatureEnabled($0) ?? ConfigStore.featureEnabled($0) } ?? true
        let row = fixedRow()
        let detail: String?
        if !parentEnabled {
            detail = "Enable Text Transformers first"
        } else if feature == .mouseJiggler {
            detail = "Menu preset feature"
        } else if feature == .textTransformers {
            detail = "Parent switch for text commands"
        } else {
            detail = nil
        }
        row.addArrangedSubview(textBlock(feature.title, detail: detail))
        let toggle = OrangeFeatureToggle()
        toggle.state = enabled ? .on : .off
        toggle.isEnabled = parentEnabled || feature == .textTransformers
        toggle.identifier = NSUserInterfaceItemIdentifier(feature.rawValue)
        toggle.target = self
        toggle.action = #selector(toggleFeature(_:))
        row.addArrangedSubview(toggle)
        return row
    }

    private func modelRow(_ model: TranscriptionModel, selected: Bool) -> NSView {
        let row = fixedRow()
        row.addArrangedSubview(textBlock(model.label, detail: "\(model.quotaLabel) · \(Int(model.neuronRate.rounded())) neurons/min"))
        let button = STMActionButton(title: selected ? "Selected" : "Select", target: self, action: #selector(selectModel(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(model.id)
        button.state = selected ? .on : .off
        button.accentColor = selected ? amber : nil
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.toolTip = selected ? "\(model.label) is selected" : "Select \(model.label)"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 104).isActive = true
        button.heightAnchor.constraint(equalToConstant: Layout.buttonHeight).isActive = true
        row.addArrangedSubview(button)
        return row
    }

    private func permissionRow(_ name: String, status: String, actionTitle: String, action: Selector) -> NSView {
        let ready = status == "Ready"
        let row = fixedRow()
        row.addArrangedSubview(permissionStatusBlock(name, status: status, ready: ready))
        row.addArrangedSubview(secondaryButton(ready ? "Granted" : actionTitle, action, enabled: !ready))
        return row
    }

    private func activeStatusColor(_ value: String) -> NSColor {
        value.localizedCaseInsensitiveContains(": Off") ? amber : cyan
    }

    private func statusPanel(title: String, value: String, color: NSColor) -> NSView {
        let container = softPanel(width: Layout.innerWidth, backgroundColor: forestPanel, borderColor: forestStroke)
        container.layer?.backgroundColor = forestPanel.cgColor
        let row = fixedRow()
        row.addArrangedSubview(statusDot(color: color))
        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.addArrangedSubview(label(title, size: 12, weight: .semibold, color: muted))
        text.addArrangedSubview(label(value, size: 15, weight: .bold, color: color))
        row.addArrangedSubview(text)
        container.addSubview(row)
        pin(row, to: container, inset: 14)
        return container
    }

    private func card(title: String, symbol: String, subtitle: String, views: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 18
        box.borderWidth = 1
        box.borderColor = stroke
        box.fillColor = panel
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 16
        inner.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.addArrangedSubview(titleRow(title, symbol: symbol, size: 18, color: .white))
        inner.addArrangedSubview(label(subtitle, size: 12, weight: .medium, color: muted))
        inner.addArrangedSubview(spacer(2))
        views.forEach { inner.addArrangedSubview($0) }
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            inner.topAnchor.constraint(equalTo: box.topAnchor),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    private func softPanel(width: CGFloat = Layout.contentWidth, backgroundColor: NSColor? = nil, borderColor: NSColor? = nil) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.backgroundColor = (backgroundColor ?? panelSoft).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = (borderColor ?? NSColor(calibratedWhite: 0.25, alpha: 1)).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    private func infoBox(_ text: String) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.backgroundColor = forestPanel.cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = forestStroke.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: Layout.innerWidth).isActive = true
        box.toolTip = text
        let textLabel = label(text, size: 11, weight: .regular, color: muted)
        textLabel.maximumNumberOfLines = 6
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(textLabel)
        pin(textLabel, to: box, inset: 12)
        return box
    }

    private func buttonGrid(_ items: [ActionSpec]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Layout.innerWidth).isActive = true
        var index = 0
        while index < items.count {
            if index + 1 < items.count {
                stack.addArrangedSubview(row([
                    secondaryButton(items[index].title, items[index].action, enabled: items[index].enabled, accent: items[index].accent, destructive: items[index].destructive),
                    secondaryButton(items[index + 1].title, items[index + 1].action, enabled: items[index + 1].enabled, accent: items[index + 1].accent, destructive: items[index + 1].destructive)
                ]))
                index += 2
            } else {
                stack.addArrangedSubview(fullWidthButton(items[index].title, items[index].action, enabled: items[index].enabled, accent: items[index].accent, destructive: items[index].destructive))
                index += 1
            }
        }
        return stack
    }

    private func action(_ title: String, _ selector: Selector, enabled: Bool = true, accent: NSColor? = nil, destructive: Bool = false) -> ActionSpec {
        ActionSpec(title: title, action: selector, enabled: enabled, accent: accent, destructive: destructive)
    }

    private func fullWidthButton(_ title: String, _ action: Selector, enabled: Bool = true, accent: NSColor? = nil, quiet: Bool = false, destructive: Bool = false) -> NSView {
        let button = STMActionButton(title: title, target: self, action: action)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.toolTip = title
        button.isEnabled = enabled
        button.accentColor = destructive ? red : accent
        button.quiet = quiet
        button.destructive = destructive
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Layout.innerWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: Layout.buttonHeight).isActive = true
        return button
    }

    private func secondaryButton(_ title: String, _ action: Selector, enabled: Bool = true, accent: NSColor? = nil, destructive: Bool = false) -> NSView {
        let button = STMActionButton(title: title, target: self, action: action)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.toolTip = title
        button.isEnabled = enabled
        button.accentColor = destructive ? red : accent
        button.destructive = destructive
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Layout.buttonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: Layout.buttonHeight).isActive = true
        return button
    }

    private func row(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Layout.gridGap
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Layout.innerWidth).isActive = true
        return stack
    }

    private func fixedRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Layout.innerWidth).isActive = true
        return row
    }

    private func textBlock(_ title: String, detail: String? = nil, width: CGFloat = 270) -> NSStackView {
        let texts = NSStackView()
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3
        texts.translatesAutoresizingMaskIntoConstraints = false
        texts.widthAnchor.constraint(equalToConstant: width).isActive = true
        texts.addArrangedSubview(label(title, size: 13, weight: .semibold, color: .white))
        if let detail, !detail.isEmpty {
            texts.addArrangedSubview(label(detail, size: 11, weight: .regular, color: muted))
        }
        return texts
    }

    private func statusTextBlock(_ title: String, detail: String, color: NSColor, width: CGFloat = 270) -> NSStackView {
        let texts = NSStackView()
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3
        texts.translatesAutoresizingMaskIntoConstraints = false
        texts.widthAnchor.constraint(equalToConstant: width).isActive = true
        texts.addArrangedSubview(label(title, size: 13, weight: .semibold, color: .white))
        texts.addArrangedSubview(label(detail, size: 11, weight: .regular, color: color))
        return texts
    }

    private func permissionStatusBlock(_ title: String, status: String, ready: Bool) -> NSStackView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 3
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 270).isActive = true

        let titleLine = NSStackView()
        titleLine.orientation = .horizontal
        titleLine.alignment = .centerY
        titleLine.spacing = 8
        titleLine.addArrangedSubview(statusDot(color: ready ? green : red))
        titleLine.addArrangedSubview(label(title, size: 13, weight: .semibold, color: .white))
        container.addArrangedSubview(titleLine)

        if !ready {
            container.addArrangedSubview(label(status, size: 11, weight: .regular, color: muted))
        }

        return container
    }

    private func groupTitle(_ text: String, symbol: String) -> NSView {
        titleRow(text, symbol: symbol, size: 12, color: amber)
    }

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 0.24, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        line.widthAnchor.constraint(equalToConstant: Layout.innerWidth).isActive = true
        return line
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func statusDot(color: NSColor) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        view.layer?.backgroundColor = color.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 10).isActive = true
        view.heightAnchor.constraint(equalToConstant: 10).isActive = true
        return view
    }

    private func titleRow(_ text: String, symbol: String, size: CGFloat, color: NSColor = .white) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        imageView.contentTintColor = color
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: size + 4).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: size + 4).isActive = true

        let title = label(text, size: size, weight: .bold, color: color)
        title.maximumNumberOfLines = 1
        row.addArrangedSubview(imageView)
        row.addArrangedSubview(title)
        return row
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .left
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 2
        return field
    }

    private func pin(_ child: NSView, to parent: NSView, inset: CGFloat) {
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    private func appIconView(size: CGFloat = 64) -> NSImageView {
        let imageView = STMAppIconView()
        imageView.image = Bundle.main.image(forResource: "AppIcon")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 14
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: size).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: size).isActive = true
        return imageView
    }
    @objc private func toggleFeature(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let feature = FeatureID(rawValue: raw) else { return }
        app?.menuSetFeature(feature, enabled: sender.state == .on)
        refresh()
    }

    @objc private func selectModel(_ sender: NSControl) {
        guard let id = sender.identifier?.rawValue else { return }
        app?.menuSelectModel(id: id)
        refresh()
    }

    @objc private func openFeatureSettings() { app?.menuOpenSettings(tab: "Features") }
    @objc private func openAIPolishSettings() { app?.menuOpenSettings(tab: "Voice AI") }
    @objc private func openSettings() { app?.menuOpenSettings() }
    @objc private func importCredentials() { app?.menuImportCredentials() }
    @objc private func installBrowserBridge() { app?.menuInstallBrowserBridge() }
    @objc private func openConfigFolder() { app?.menuOpenConfigFolder() }
    @objc private func checkForUpdates() { app?.menuCheckForUpdates() }
    @objc private func requestMicrophone() { app?.menuRequestMicrophone(); refresh() }
    @objc private func requestScreen() { app?.menuRequestScreen(); refresh() }
    @objc private func openScreenSettings() { app?.menuOpenScreenSettings(); refresh() }
    @objc private func requestAccessibility() { app?.menuRequestAccessibility(); refresh() }
    @objc private func resetAccessibility() { app?.menuResetAccessibilityEntry(); refresh() }
    @objc private func resetScreenEntry() { app?.menuResetScreenRecordingEntry(); refresh() }
    @objc private func shutdown8() { app?.menuSchedulePower(.shutdown, input: "8am"); refresh() }
    @objc private func shutdown25() { app?.menuSchedulePower(.shutdown, input: "2.5h"); refresh() }
    @objc private func scheduleShutdown() { app?.menuPromptScheduleShutdown(); refresh() }
    @objc private func sleep1() { app?.menuSchedulePower(.sleep, input: "1h"); refresh() }
    @objc private func sleep25() { app?.menuSchedulePower(.sleep, input: "2.5h"); refresh() }
    @objc private func scheduleSleep() { app?.menuPromptScheduleSleep(); refresh() }
    @objc private func awake8() { app?.menuKeepAwake(input: "8am"); refresh() }
    @objc private func awake25() { app?.menuKeepAwake(input: "2.5h"); refresh() }
    @objc private func keepAwakeCustom() { app?.menuPromptKeepAwake(); refresh() }
    @objc private func powerStatus() { app?.menuShowPowerStatus() }
    @objc private func copyPowerStatus() { app?.menuCopyPowerStatus() }
    @objc private func openPowerLog() { app?.menuOpenPowerLog() }
    @objc private func openNotifications() { app?.menuOpenNotificationSettings() }
    @objc private func gitAutosave() { app?.menuRunGitAutosaveNow(); refresh() }
    @objc private func cancelPower() { app?.menuCancelScheduledPower(); refresh() }
    @objc private func stopAwake() { app?.menuStopKeepAwake(); refresh() }
    @objc private func mouseInfinite1() { app?.menuStartMouseJiggler(interval: 60, duration: 0); refresh() }
    @objc private func mouseInfinite2() { app?.menuStartMouseJiggler(interval: 120, duration: 0); refresh() }
    @objc private func mouseInfinite5() { app?.menuStartMouseJiggler(interval: 300, duration: 0); refresh() }
    @objc private func mouse30m() { app?.menuStartMouseJiggler(interval: 60, duration: 1800); refresh() }
    @objc private func mouse1h() { app?.menuStartMouseJiggler(interval: 120, duration: 3600); refresh() }
    @objc private func mouse2h() { app?.menuStartMouseJiggler(interval: 300, duration: 7200); refresh() }
    @objc private func mouseCustom() { app?.menuStartCustomMouseJiggler(); refresh() }
    @objc private func mouseStop() { app?.menuStopMouseJiggler(); refresh() }
    @objc private func quitApp() { app?.menuQuit() }
}

final class STMAppIconView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 64, height: 64)
    }
}

final class STMMenuBackdropView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.020, green: 0.024, blue: 0.027, alpha: 1).setFill()
        bounds.fill()
    }
}
final class STMActionButton: NSControl {
    var title: String = "" { didSet { needsDisplay = true } }
    override var font: NSFont? { didSet { needsDisplay = true } }
    var accentColor: NSColor? { didSet { needsDisplay = true } }
    var quiet = false { didSet { needsDisplay = true } }
    var destructive = false { didSet { needsDisplay = true } }
    var state: NSControl.StateValue = .off { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var hovered = false { didSet { needsDisplay = true } }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        commonInit()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        focusRingType = .default
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        window?.trackEvents(matching: [.leftMouseUp, .leftMouseDragged], timeout: NSEvent.foreverDuration, mode: .eventTracking) { [weak self] event, stop in
            guard let self else { stop.pointee = true; return }
            if event?.type == .leftMouseUp {
                self.pressed = false
                if let point = event.map({ self.convert($0.locationInWindow, from: nil) }), self.bounds.contains(point) {
                    _ = self.sendAction(self.action, to: self.target)
                }
                stop.pointee = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let rect = bounds.insetBy(dx: 0.5, dy: 1.0)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        let fill: NSColor
        if !isEnabled {
            fill = NSColor(calibratedRed: 0.059, green: 0.071, blue: 0.091, alpha: 0.62)
        } else if pressed {
            fill = NSColor(calibratedRed: 0.043, green: 0.052, blue: 0.066, alpha: 1.0)
        } else if hovered {
            fill = NSColor(calibratedRed: 0.072, green: 0.087, blue: 0.110, alpha: 1.0)
        } else {
            fill = NSColor(calibratedRed: 0.059, green: 0.071, blue: 0.091, alpha: 1.0)
        }
        fill.setFill()
        path.fill()

        let stroke = accentColor?.withAlphaComponent(isEnabled ? (destructive ? 0.82 : 0.72) : 0.22) ?? NSColor(calibratedWhite: 0.24, alpha: isEnabled ? 0.86 : 0.24)
        stroke.setStroke()
        path.lineWidth = accentColor == nil ? 1 : (destructive ? 1.15 : 1.25)
        path.stroke()

        let textColor: NSColor = isEnabled ? .white : NSColor(calibratedWhite: 0.50, alpha: 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let textSize = attributed.size()
        let textRect = NSRect(x: 0, y: (bounds.height - textSize.height) / 2 - (pressed ? 2 : 1), width: bounds.width, height: textSize.height)
        attributed.draw(in: textRect)
    }
}

final class OrangeFeatureToggle: NSButton {
    private let onColor = NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
    private let offColor = NSColor(calibratedWhite: 0.34, alpha: 1.0)
    private let knobColor = NSColor(calibratedWhite: 0.88, alpha: 1.0)
    private var hovered = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 38, height: 22)
    }

    private func commonInit() {
        title = ""
        setButtonType(.toggle)
        isBordered = false
        focusRingType = .default
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 38).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = state == .on
        let alpha: CGFloat = isEnabled ? 1.0 : 0.42
        let track = bounds.insetBy(dx: 1, dy: 2)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        (active ? onColor : offColor).withAlphaComponent(hovered && isEnabled ? min(alpha + 0.12, 1.0) : alpha).setFill()
        trackPath.fill()

        NSColor(calibratedWhite: active ? 1.0 : 0.55, alpha: active ? 0.28 : 0.18).setStroke()
        trackPath.lineWidth = 1
        trackPath.stroke()

        let knobSize = track.height - 4
        let knobX = active ? track.maxX - knobSize - 2 : track.minX + 2
        let knobRect = NSRect(x: knobX, y: track.minY + 2, width: knobSize, height: knobSize)
        let knobPath = NSBezierPath(ovalIn: knobRect)
        knobColor.withAlphaComponent(alpha).setFill()
        knobPath.fill()
    }
}


