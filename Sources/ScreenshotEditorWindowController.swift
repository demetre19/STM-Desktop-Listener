import AppKit
import ImageIO
import UniformTypeIdentifiers

private enum ScreenshotEditorPalette {
    static let root = NSColor(stmHex: "#0A0A0A")!
    static let panel = NSColor(stmHex: "#1A1A1A")!
    static let control = NSColor(stmHex: "#2A2A2A")!
    static let controlHover = NSColor(stmHex: "#3A3A3A")!
    static let border = NSColor(stmHex: "#3A3A3A")!
    static let text = NSColor(stmHex: "#E5E5E5")!
    static let muted = NSColor(stmHex: "#9CA3AF")!
    static let dim = NSColor(stmHex: "#6B7280")!
    static let cyan = NSColor(stmHex: "#0FFFFF")!
}

private struct ScreenshotSavedGradientPreset: Codable {
    struct Stop: Codable {
        var colorHex: String
        var position: CGFloat
    }

    var stops: [Stop]
    var radial: Bool
    var angle: CGFloat
}

private struct ScreenshotBackdropPreferences: Codable {
    var padding: CGFloat = 40
    var shadow: CGFloat = 20
    var shadowColorHex = "#000000"
    var shadowBlur: CGFloat = 30
    var shadowOffsetX: CGFloat = 0
    var shadowOffsetY: CGFloat = 8
    var shadowOpacity: CGFloat = 0.3
    var outerRadius: CGFloat = 12
    var innerRadius: CGFloat = 8
    var mode = "solid"
    var solidColorHex = "#1A1A1A"
    var stops = [
        ScreenshotSavedGradientPreset.Stop(colorHex: "#667EEA", position: 0),
        ScreenshotSavedGradientPreset.Stop(colorHex: "#764BA2", position: 1)
    ]
    var radial = false
    var angle: CGFloat = 135
    var imageBlur: CGFloat = 20
    var imageOffsetX: CGFloat = 0
    var imageOffsetY: CGFloat = 0
    var imagePath: String?
    var useCurrentScreenshot = false
}

private final class ScreenshotGradientEditorView: NSView {
    var stops: [ScreenshotGradientStop] = [] {
        didSet { needsDisplay = true }
    }
    var onChange: (([ScreenshotGradientStop]) -> Void)?
    var onCommit: (() -> Void)?
    private var draggedIndex: Int?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 248, height: 32) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bar = bounds.insetBy(dx: 7, dy: 9)
        let sorted = stops.sorted { $0.position < $1.position }
        if let gradient = NSGradient(
            colors: sorted.map(\.color),
            atLocations: sorted.map { max(0, min(1, $0.position)) },
            colorSpace: .deviceRGB
        ) {
            let path = NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5)
            gradient.draw(in: path, angle: 0)
        }
        ScreenshotEditorPalette.border.setStroke()
        NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).stroke()

        for stop in stops {
            let center = CGPoint(x: bar.minX + max(0, min(1, stop.position)) * bar.width, y: bar.midY)
            stop.color.setFill()
            NSColor.white.setStroke()
            let dot = NSBezierPath(ovalIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
            dot.lineWidth = 2
            dot.fill()
            dot.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let bar = bounds.insetBy(dx: 7, dy: 9)
        if let index = nearestStop(to: point, in: bar, maximumDistance: 10) {
            draggedIndex = index
            return
        }
        guard stops.count < 8, bar.contains(point), !stops.isEmpty else { return }
        let position = max(0, min(1, (point.x - bar.minX) / bar.width))
        let color = stops.min(by: { abs($0.position - position) < abs($1.position - position) })?.color ?? .black
        stops.append(ScreenshotGradientStop(color: color, position: position))
        stops.sort { $0.position < $1.position }
        draggedIndex = nearestStop(to: point, in: bar, maximumDistance: .greatestFiniteMagnitude)
        onChange?(stops)
        onCommit?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let draggedIndex, stops.indices.contains(draggedIndex) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let bar = bounds.insetBy(dx: 7, dy: 9)
        stops[draggedIndex].position = max(0, min(1, (point.x - bar.minX) / bar.width))
        needsDisplay = true
        onChange?(stops)
    }

    override func mouseUp(with event: NSEvent) {
        guard draggedIndex != nil else { return }
        draggedIndex = nil
        stops.sort { $0.position < $1.position }
        onChange?(stops)
        onCommit?()
    }

    private func nearestStop(to point: CGPoint, in bar: CGRect, maximumDistance: CGFloat) -> Int? {
        stops.indices.min(by: {
            abs((bar.minX + stops[$0].position * bar.width) - point.x)
                < abs((bar.minX + stops[$1].position * bar.width) - point.x)
        }).flatMap {
            abs((bar.minX + stops[$0].position * bar.width) - point.x) <= maximumDistance ? $0 : nil
        }
    }
}

private final class ScreenshotToolButton: NSButton {
    var onPrimary: (() -> Void)?
    var onSetDefault: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            onSetDefault?()
        } else {
            onPrimary?()
        }
    }
}

private final class ScreenshotEditorWindow: NSWindow {
    var commandHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, commandHandler?(event) == true { return }
        super.sendEvent(event)
    }
}
private final class ScreenshotEditorCenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return constrained }
        constrained.origin = ScreenshotEditorLayout.centeredDocumentOrigin(
            document: documentView.frame.size,
            viewport: constrained.size,
            proposed: constrained.origin
        )
        return constrained
    }
}


final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: ScreenshotEditorCanvasView
    private let scrollView = NSScrollView()
    private let toolbar = NSView()
    private let contentStack = NSStackView()
    private let sidebarScroll = NSScrollView()
    private let sidebar = NSView()
    private let styleBar = NSStackView()
    private let qualityValue = NSTextField(labelWithString: "92%")
    private let qualitySlider = NSSlider(value: 92, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let widthPopup = NSPopUpButton()
    private let formatPopup = NSPopUpButton()
    private let shrinkPopup = NSPopUpButton()
    private let fillSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let fillLabel = NSTextField(labelWithString: "0%")
    private let shapeToggle = NSButton(title: "Circle / Square", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let gradientEditor = ScreenshotGradientEditorView()
    private let gradientStopsStack = NSStackView()
    private let savedGradientsStack = NSStackView()
    private var toolButtons: [ScreenshotTool: ScreenshotToolButton] = [:]
    private var preferences: ScreenshotEditorPreferences
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var isClosingAfterAction = false
    private var restoredWindowFrame = false
    private var gradientAngle: CGFloat = 135
    private var savedGradientPresets: [ScreenshotSavedGradientPreset]
    private var backdropPreferences: ScreenshotBackdropPreferences
    var onClose: (() -> Void)?

    init(image: CGImage) {
        preferences = Self.loadPreferences()
        savedGradientPresets = Self.loadSavedGradientPresets()
        backdropPreferences = Self.loadBackdropPreferences()
        canvas = ScreenshotEditorCanvasView(image: image)
        canvas.backdrop = Self.makeBackdropSettings(from: backdropPreferences, baseImage: image)
        gradientAngle = backdropPreferences.angle
        canvas.currentTool = preferences.defaultTool
        canvas.currentColor = NSColor(stmHex: preferences.colorHex) ?? .black
        canvas.currentStrokeWidth = preferences.strokeWidth
        canvas.zoom = preferences.zoom

        let window = ScreenshotEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1480, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.delegate = self
        window.title = "STM Screenshot Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.backgroundColor = ScreenshotEditorPalette.root
        window.minSize = CGSize(width: 1080, height: 640)
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        restoredWindowFrame = window.setFrameUsingName("STMScreenshotEditorWindow")
        window.setFrameAutosaveName("STMScreenshotEditorWindow")
        setupWindow()
        wireCanvas()
    }

    required init?(coder: NSCoder) {
        nil
    }
    func windowDidResize(_ notification: Notification) {
        window?.contentView?.layoutSubtreeIfNeeded()
        centerCanvasInViewport()
    }


    func present(onReady: @escaping () -> Void = {}) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !restoredWindowFrame {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        fitCanvasToViewport()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        DispatchQueue.main.async { [weak self, weak window] in
            onReady()
            guard let self, let window else { return }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(self.canvas)
        }
    }

    private func setupWindow() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = ScreenshotEditorPalette.root.cgColor

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = ScreenshotEditorPalette.panel.cgColor
        toolbar.layer?.borderColor = ScreenshotEditorPalette.border.cgColor
        toolbar.layer?.borderWidth = 1
        root.addSubview(toolbar)

        let toolbarStack = NSStackView()
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.spacing = 6
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(toolbarStack)

        for tool in ScreenshotTool.allCases {
            if tool == .backdrop { continue }
            let button = makeToolButton(tool)
            toolbarStack.addArrangedSubview(button)
        }
        toolbarStack.addArrangedSubview(makeToolButton(.backdrop))
        toolbarStack.addArrangedSubview(separator())
        toolbarStack.addArrangedSubview(setting(label: "Max Width", control: configureWidthPopup()))
        toolbarStack.addArrangedSubview(setting(label: "Format", control: configureFormatPopup()))
        toolbarStack.addArrangedSubview(setting(label: "Quality", control: configureQualityControl()))
        toolbarStack.addArrangedSubview(setting(label: "Copy Shrink", control: configureShrinkPopup()))
        toolbarStack.addArrangedSubview(separator())
        toolbarStack.addArrangedSubview(actionButton("Undo", symbol: "arrow.uturn.backward", action: #selector(undo)))
        toolbarStack.addArrangedSubview(actionButton("Copy", symbol: "doc.on.doc", action: #selector(copyScreenshot)))
        toolbarStack.addArrangedSubview(actionButton("Save", symbol: "square.and.arrow.down", action: #selector(saveScreenshot)))
        toolbarStack.addArrangedSubview(actionButton("Close", symbol: "xmark", action: #selector(closeEditor)))

        contentStack.orientation = .horizontal
        contentStack.alignment = .top
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        scrollView.contentView = ScreenshotEditorCenteredClipView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = canvas
        scrollView.contentView.postsBoundsChangedNotifications = true
        contentStack.addArrangedSubview(scrollView)

        buildBackdropSidebar()
        sidebarScroll.documentView = sidebar
        sidebarScroll.drawsBackground = true
        sidebarScroll.backgroundColor = ScreenshotEditorPalette.panel
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.isHidden = true
        sidebarWidthConstraint = sidebarScroll.widthAnchor.constraint(equalToConstant: 0)
        sidebarWidthConstraint?.isActive = true
        contentStack.addArrangedSubview(sidebarScroll)

        configureStyleBar(in: root)
        configureStatusLabel(in: root)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 66),
            toolbarStack.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            toolbarStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 8),
            toolbarStack.leadingAnchor.constraint(greaterThanOrEqualTo: toolbar.leadingAnchor, constant: 12),
            toolbarStack.trailingAnchor.constraint(lessThanOrEqualTo: toolbar.trailingAnchor, constant: -12),
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentStack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        selectTool(preferences.defaultTool)
        if let editorWindow = window as? ScreenshotEditorWindow {
            editorWindow.commandHandler = { [weak self] event in self?.handleWindowKey(event) ?? false }
        }
    }

    private func wireCanvas() {
        canvas.onSelectionChanged = { [weak self] annotation in
            self?.updateStyleBar(for: annotation)
        }
        canvas.onDocumentChanged = { [weak self] in
            self?.persistDrawingPreferences()
        }
        canvas.onBackdropChanged = { [weak self] in
            self?.persistBackdropSettings()
        }
        canvas.onBaseImageChanged = { [weak self] in
            guard let self else { return }
            self.canvas.updateFrameForContent()
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.centerCanvasInViewport()
        }
        canvas.onCommand = { [weak self] command in
            self?.perform(command)
        }
        canvas.onNotice = { [weak self] message in
            self?.showStatus(message, error: true)
        }
    }

    private func fitCanvasToViewport() {
        let zoom = ScreenshotEditorLayout.fitScale(
            content: canvas.contentSize,
            viewport: scrollView.contentSize
        )
        canvas.zoom = zoom
        preferences.zoom = zoom
        window?.contentView?.layoutSubtreeIfNeeded()
        centerCanvasInViewport(proposedOrigin: .zero)
    }

    private func centerCanvasInViewport(proposedOrigin: CGPoint? = nil) {
        let clipView = scrollView.contentView
        let origin = ScreenshotEditorLayout.centeredDocumentOrigin(
            document: canvas.frame.size,
            viewport: clipView.bounds.size,
            proposed: proposedOrigin ?? clipView.bounds.origin
        )
        clipView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func makeToolButton(_ tool: ScreenshotTool) -> ScreenshotToolButton {
        let button = ScreenshotToolButton()
        button.image = NSImage(systemSymbolName: symbol(for: tool), accessibilityDescription: tool.title)
        button.imagePosition = .imageOnly
        button.toolTip = "\(tool.title) Tool (\(tool.shortcutLabel))"
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 38)
        ])
        button.onPrimary = { [weak self] in
            if tool == .backdrop { self?.toggleBackdrop() } else { self?.selectTool(tool) }
        }
        button.onSetDefault = { [weak self] in self?.toggleDefaultTool(tool) }
        toolButtons[tool] = button
        updateToolButton(button, tool: tool)
        return button
    }

    private func symbol(for tool: ScreenshotTool) -> String {
        switch tool {
        case .arrow: return "arrow.up.right"
        case .line: return "minus"
        case .text: return "textformat"
        case .box: return "rectangle"
        case .number: return "1.circle"
        case .blur: return "aqi.medium"
        case .pixelate: return "square.grid.3x3.fill"
        case .crop: return "crop"
        case .magnifier: return "magnifyingglass"
        case .backdrop: return "rectangle.inset.filled"
        }
    }

    private func selectTool(_ tool: ScreenshotTool) {
        guard tool != .backdrop else { toggleBackdrop(); return }
        canvas.selectTool(tool)
        for (candidate, button) in toolButtons { updateToolButton(button, tool: candidate) }
    }

    private func toggleDefaultTool(_ tool: ScreenshotTool) {
        guard tool != .backdrop else { return }
        preferences.defaultTool = preferences.defaultTool == tool ? .arrow : tool
        try? ConfigStore.set(preferences.defaultTool.rawValue, for: "screenshotEditorDefaultTool")
        selectTool(tool)
        showStatus("\(preferences.defaultTool.title) is the default tool")
    }

    private func updateToolButton(_ button: ScreenshotToolButton, tool: ScreenshotTool) {
        let active = canvas.currentTool == tool && tool != .backdrop
        let defaulted = preferences.defaultTool == tool && tool != .arrow
        button.contentTintColor = active ? .white : ScreenshotEditorPalette.muted
        button.layer?.backgroundColor = active
            ? NSColor(stmHex: "#404040")!.cgColor
            : (defaulted ? ScreenshotEditorPalette.cyan.withAlphaComponent(0.15).cgColor : ScreenshotEditorPalette.control.cgColor)
        button.layer?.borderColor = active
            ? (defaulted ? ScreenshotEditorPalette.cyan.cgColor : ScreenshotEditorPalette.dim.cgColor)
            : (defaulted ? ScreenshotEditorPalette.cyan.withAlphaComponent(0.4).cgColor : ScreenshotEditorPalette.border.cgColor)
    }

    private func actionButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = ScreenshotEditorPalette.muted
        button.bezelStyle = .rounded
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = ScreenshotEditorPalette.control.cgColor
        button.layer?.borderColor = ScreenshotEditorPalette.border.cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 6
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func setting(label: String, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label.uppercased())
        title.font = .systemFont(ofSize: 10, weight: .medium)
        title.textColor = ScreenshotEditorPalette.dim
        title.alignment = .center
        let stack = NSStackView(views: [title, control])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        return stack
    }

    private func separator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ScreenshotEditorPalette.border.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: 28)
        ])
        return view
    }

    private func configureWidthPopup() -> NSView {
        let values = [480, 720, 1080, 1440, 1920, 2160]
        widthPopup.addItems(withTitles: values.map { "\($0)px" })
        widthPopup.selectItem(at: values.firstIndex(of: preferences.maxWidth) ?? 4)
        widthPopup.target = self
        widthPopup.action = #selector(widthChanged)
        stylePopup(widthPopup, width: 86)
        return widthPopup
    }

    private func configureFormatPopup() -> NSView {
        formatPopup.addItems(withTitles: ["JPG", "WebP"])
        formatPopup.selectItem(at: preferences.format == .webp ? 1 : 0)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        stylePopup(formatPopup, width: 76)
        return formatPopup
    }

    private func configureShrinkPopup() -> NSView {
        shrinkPopup.addItems(withTitles: ["1x (Full)", "2x (Half)", "3x (1/3)", "4x (1/4)"])
        shrinkPopup.selectItem(at: max(0, min(3, preferences.copyShrink - 1)))
        shrinkPopup.target = self
        shrinkPopup.action = #selector(shrinkChanged)
        stylePopup(shrinkPopup, width: 96)
        return shrinkPopup
    }

    private func stylePopup(_ popup: NSPopUpButton, width: CGFloat) {
        popup.font = .systemFont(ofSize: 12)
        popup.contentTintColor = ScreenshotEditorPalette.muted
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        popup.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func configureQualityControl() -> NSView {
        qualitySlider.doubleValue = Double(preferences.quality)
        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged)
        qualitySlider.controlSize = .small
        qualitySlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
        qualityValue.stringValue = "\(preferences.quality)%"
        qualityValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        qualityValue.textColor = ScreenshotEditorPalette.muted
        let stack = NSStackView(views: [qualitySlider, qualityValue])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        return stack
    }

    private func configureStyleBar(in root: NSView) {
        styleBar.orientation = .horizontal
        styleBar.alignment = .centerY
        styleBar.spacing = 8
        styleBar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        styleBar.wantsLayer = true
        styleBar.layer?.backgroundColor = ScreenshotEditorPalette.panel.cgColor
        styleBar.layer?.borderColor = ScreenshotEditorPalette.border.cgColor
        styleBar.layer?.borderWidth = 1
        styleBar.layer?.cornerRadius = 8
        styleBar.translatesAutoresizingMaskIntoConstraints = false
        styleBar.isHidden = true
        root.addSubview(styleBar)

        for (width, diameter) in [(3, 6), (6, 10), (10, 14)] {
            let button = NSButton(title: "", target: self, action: #selector(styleStroke(_:)))
            button.tag = width
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = ScreenshotEditorPalette.muted.cgColor
            button.layer?.cornerRadius = CGFloat(diameter) / 2
            button.widthAnchor.constraint(equalToConstant: CGFloat(diameter)).isActive = true
            button.heightAnchor.constraint(equalToConstant: CGFloat(diameter)).isActive = true
            styleBar.addArrangedSubview(button)
        }
        styleBar.addArrangedSubview(separator())

        for hex in ["#000000", "#6B7280", "#DC2626", "#FACC15", "#22C55E", "#3B82F6", "#FFFFFF"] {
            let button = NSButton(title: "", target: self, action: #selector(styleColor(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(hex)
            button.toolTip = hex
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(stmHex: hex)!.cgColor
            button.layer?.borderWidth = hex == "#FFFFFF" ? 1 : 0
            button.layer?.borderColor = ScreenshotEditorPalette.dim.cgColor
            button.layer?.cornerRadius = 3
            button.widthAnchor.constraint(equalToConstant: 18).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            styleBar.addArrangedSubview(button)
        }
        let colorWell = NSColorWell()
        colorWell.color = canvas.currentColor
        colorWell.target = self
        colorWell.action = #selector(customStyleColor(_:))
        colorWell.toolTip = "Custom Color"
        colorWell.widthAnchor.constraint(equalToConstant: 24).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        styleBar.addArrangedSubview(colorWell)
        styleBar.addArrangedSubview(separator())

        let fillTitle = NSTextField(labelWithString: "Fill")
        fillTitle.font = .systemFont(ofSize: 11)
        fillTitle.textColor = ScreenshotEditorPalette.muted
        styleBar.addArrangedSubview(fillTitle)
        fillSlider.target = self
        fillSlider.action = #selector(fillChanged)
        fillSlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
        styleBar.addArrangedSubview(fillSlider)
        fillLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        fillLabel.textColor = ScreenshotEditorPalette.muted
        styleBar.addArrangedSubview(fillLabel)

        shapeToggle.target = self
        shapeToggle.action = #selector(toggleMagnifierShape)
        shapeToggle.bezelStyle = .rounded
        styleBar.addArrangedSubview(shapeToggle)

        NSLayoutConstraint.activate([
            styleBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            styleBar.centerXAnchor.constraint(equalTo: root.centerXAnchor)
        ])
    }

    private func configureStatusLabel(in root: NSView) {
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = ScreenshotEditorPalette.text
        statusLabel.alignment = .center
        statusLabel.wantsLayer = true
        statusLabel.layer?.backgroundColor = ScreenshotEditorPalette.panel.cgColor
        statusLabel.layer?.cornerRadius = 6
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        root.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            statusLabel.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func updateStyleBar(for annotation: ScreenshotAnnotation?) {
        guard let annotation else {
            styleBar.isHidden = true
            return
        }
        styleBar.isHidden = false
        let showsFill = annotation.tool == .box
        fillSlider.isHidden = !showsFill
        fillLabel.isHidden = !showsFill
        fillSlider.doubleValue = Double(annotation.fillOpacity * 100)
        fillLabel.stringValue = "\(Int(annotation.fillOpacity * 100))%"
        shapeToggle.isHidden = annotation.tool != .magnifier
    }

    private func buildBackdropSidebar() {
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = ScreenshotEditorPalette.panel.cgColor
        sidebar.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor)
        ])

        let header = NSTextField(labelWithString: "Backdrop")
        header.font = .systemFont(ofSize: 15, weight: .semibold)
        header.textColor = ScreenshotEditorPalette.text
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(sidebarSlider("Padding", min: 10, max: 500, value: 40, tag: 1))
        stack.addArrangedSubview(sidebarSlider("Shadow", min: 0, max: 100, value: 20, tag: 2))

        let expert = collapsibleSection(title: "Expert Shadow", controls: [
            labeledColorWell("Color", color: .black, tag: 10),
            sidebarSlider("Blur", min: 0, max: 100, value: 30, tag: 3),
            sidebarSlider("Offset X", min: -50, max: 50, value: 0, tag: 4),
            sidebarSlider("Offset Y", min: -50, max: 50, value: 8, tag: 5),
            sidebarSlider("Opacity", min: 0, max: 100, value: 30, tag: 6)
        ])
        stack.addArrangedSubview(expert)
        stack.addArrangedSubview(sidebarSlider("Outer Radius", min: 0, max: 50, value: 12, tag: 7))
        stack.addArrangedSubview(sidebarSlider("Inner Radius", min: 0, max: 50, value: 8, tag: 8))

        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: 248).isActive = true
        stack.addArrangedSubview(divider)

        let backgroundTitle = NSTextField(labelWithString: "BACKGROUND")
        backgroundTitle.font = .systemFont(ofSize: 10, weight: .medium)
        backgroundTitle.textColor = ScreenshotEditorPalette.dim
        stack.addArrangedSubview(backgroundTitle)

        let mode = NSSegmentedControl(labels: ["Solid", "Gradient", "Image"], trackingMode: .selectOne, target: self, action: #selector(backdropModeChanged(_:)))
        mode.selectedSegment = 0
        mode.tag = 20
        mode.widthAnchor.constraint(equalToConstant: 248).isActive = true
        stack.addArrangedSubview(mode)

        let colors = NSStackView()
        colors.orientation = .horizontal
        colors.spacing = 5
        for hex in ["#000000", "#1A1A1A", "#374151", "#6B7280", "#D1D5DB", "#FFFFFF", "#0FFFFF"] {
            let button = NSButton(title: "", target: self, action: #selector(backdropSolidColor(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(hex)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(stmHex: hex)!.cgColor
            button.layer?.cornerRadius = 3
            button.layer?.borderColor = ScreenshotEditorPalette.border.cgColor
            button.layer?.borderWidth = 1
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            colors.addArrangedSubview(button)
        }
        stack.addArrangedSubview(colors)

        let customBackground = labeledColorWell("Custom solid", color: NSColor(stmHex: "#1A1A1A")!, tag: 11)
        stack.addArrangedSubview(customBackground)

        let gradientTitle = NSTextField(labelWithString: "Gradient presets")
        gradientTitle.font = .systemFont(ofSize: 11, weight: .medium)
        gradientTitle.textColor = ScreenshotEditorPalette.muted
        stack.addArrangedSubview(gradientTitle)
        let gradients = NSGridView()
        var row: [NSView] = []
        for (index, preset) in ScreenshotBackdropSettings.gradientPresets.enumerated() {
            let button = NSButton(title: preset.0, target: self, action: #selector(backdropGradientPreset(_:)))
            button.tag = index
            button.font = .systemFont(ofSize: 10, weight: .medium)
            button.bezelStyle = .rounded
            button.widthAnchor.constraint(equalToConstant: 58).isActive = true
            row.append(button)
            if row.count == 4 {
                gradients.addRow(with: row)
                row = []
            }
        }
        if !row.isEmpty { gradients.addRow(with: row) }
        gradients.rowSpacing = 6
        gradients.columnSpacing = 5
        stack.addArrangedSubview(gradients)

        let gradientType = NSSegmentedControl(labels: ["Linear", "Radial"], trackingMode: .selectOne, target: self, action: #selector(gradientTypeChanged(_:)))
        gradientType.selectedSegment = 0
        gradientType.tag = 21
        gradientType.widthAnchor.constraint(equalToConstant: 248).isActive = true
        stack.addArrangedSubview(gradientType)
        stack.addArrangedSubview(sidebarSlider("Gradient Angle", min: 0, max: 360, value: 135, tag: 9))

        gradientEditor.stops = currentGradientStops()
        gradientEditor.onChange = { [weak self] stops in
            self?.setGradientStops(stops)
        }
        gradientEditor.onCommit = { [weak self] in
            self?.rebuildGradientControls()
            self?.persistBackdropSettings()
        }
        stack.addArrangedSubview(gradientEditor)

        gradientStopsStack.orientation = .vertical
        gradientStopsStack.alignment = .leading
        gradientStopsStack.spacing = 5
        stack.addArrangedSubview(gradientStopsStack)

        let saveGradient = NSButton(title: "Save Current Gradient", target: self, action: #selector(saveCurrentGradient))
        saveGradient.widthAnchor.constraint(equalToConstant: 248).isActive = true
        stack.addArrangedSubview(saveGradient)

        savedGradientsStack.orientation = .vertical
        savedGradientsStack.alignment = .leading
        savedGradientsStack.spacing = 5
        stack.addArrangedSubview(savedGradientsStack)
        rebuildGradientControls()

        let imageButtons = NSStackView()
        imageButtons.orientation = .horizontal
        imageButtons.spacing = 8
        let upload = NSButton(title: "Upload Image", target: self, action: #selector(uploadBackdropImage))
        let useScreenshot = NSButton(title: "Use Screenshot", target: self, action: #selector(useScreenshotBackdrop))
        imageButtons.addArrangedSubview(upload)
        imageButtons.addArrangedSubview(useScreenshot)
        stack.addArrangedSubview(imageButtons)
        stack.addArrangedSubview(sidebarSlider("Image Blur", min: 0, max: 50, value: 20, tag: 14))
        let reset = NSButton(title: "Reset Image Position", target: self, action: #selector(resetBackdropPosition))
        reset.toolTip = "Shift-drag the canvas to reposition the image"
        stack.addArrangedSubview(reset)
        syncBackdropControls()
    }

    private func syncBackdropControls() {
        let settings = canvas.backdrop
        for view in descendantViews(of: sidebar) {
            if let slider = view as? NSSlider {
                switch slider.tag {
                case 1: slider.doubleValue = Double(settings.padding)
                case 2: slider.doubleValue = Double(settings.shadow)
                case 3: slider.doubleValue = Double(settings.shadowBlur)
                case 4: slider.doubleValue = Double(settings.shadowOffsetX)
                case 5: slider.doubleValue = Double(settings.shadowOffsetY)
                case 6: slider.doubleValue = Double(settings.shadowOpacity * 100)
                case 7: slider.doubleValue = Double(settings.outerRadius)
                case 8: slider.doubleValue = Double(settings.innerRadius)
                case 9: slider.doubleValue = Double(gradientAngle)
                case 14: slider.doubleValue = Double(settings.backgroundImageBlur)
                default: break
                }
            } else if let segmented = view as? NSSegmentedControl {
                if segmented.tag == 20 {
                    switch settings.background {
                    case .solid: segmented.selectedSegment = 0
                    case .linear, .radial: segmented.selectedSegment = 1
                    case .image: segmented.selectedSegment = 2
                    }
                } else if segmented.tag == 21 {
                    if case .radial = settings.background { segmented.selectedSegment = 1 }
                    else { segmented.selectedSegment = 0 }
                }
            } else if let well = view as? NSColorWell {
                switch well.tag {
                case 10: well.color = settings.shadowColor
                case 11:
                    if case .solid(let color) = settings.background { well.color = color }
                    else { well.color = NSColor(stmHex: backdropPreferences.solidColorHex) ?? well.color }
                default: break
                }
            }
        }
    }

    private func descendantViews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendantViews)
    }

    private func sidebarSlider(_ title: String, min: Double, max: Double, value: Double, tag: Int) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = ScreenshotEditorPalette.dim
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(backdropSliderChanged(_:)))
        slider.tag = tag
        slider.widthAnchor.constraint(equalToConstant: 248).isActive = true
        let stack = NSStackView(views: [label, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return stack
    }

    private func labeledColorWell(_ title: String, color: NSColor, tag: Int) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = ScreenshotEditorPalette.muted
        let well = NSColorWell()
        well.color = color
        well.tag = tag
        well.target = self
        well.action = #selector(backdropColorChanged(_:))
        well.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let row = NSStackView(views: [label, well])
        row.orientation = .horizontal
        row.distribution = .fill
        row.widthAnchor.constraint(equalToConstant: 248).isActive = true
        return row
    }

    private func collapsibleSection(title: String, controls: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = ScreenshotEditorPalette.dim
        stack.addArrangedSubview(label)
        controls.forEach(stack.addArrangedSubview)
        return stack
    }

    private func toggleBackdrop() {
        let opening = sidebarScroll.isHidden
        if opening {
            canvas.backdrop.isEnabled = true
        } else {
            canvas.bakeBackdrop()
        }
        sidebarScroll.isHidden = !opening
        sidebarWidthConstraint?.constant = opening ? 280 : 0
        canvas.updateFrameForContent()
        if let button = toolButtons[.backdrop] {
            button.layer?.backgroundColor = opening ? NSColor(stmHex: "#404040")!.cgColor : ScreenshotEditorPalette.control.cgColor
            button.layer?.borderColor = opening ? ScreenshotEditorPalette.dim.cgColor : ScreenshotEditorPalette.border.cgColor
        }
    }

    private func perform(_ command: ScreenshotEditorCommand) {
        switch command {
        case .selectTool(let tool): selectTool(tool)
        case .toggleBackdrop: toggleBackdrop()
        case .undo: canvas.undo()
        case .copy: copyScreenshot()
        case .save: saveScreenshot()
        case .close: closeEditor()
        case .escape:
            if canvas.cropRect != nil { canvas.cancelCrop() }
            else if !sidebarScroll.isHidden { toggleBackdrop() }
            else { closeEditor() }
        case .applyCrop:
            if canvas.applyCrop() { showStatus("Crop applied") }
        case .deleteSelection: canvas.deleteSelection()
        case .decreaseStroke: canvas.adjustStroke(by: -5)
        case .increaseStroke: canvas.adjustStroke(by: 5)
        case .decreaseFill: canvas.adjustFill(by: -0.1)
        case .increaseFill: canvas.adjustFill(by: 0.1)
        case .zoomIn: setZoom(min(4, canvas.zoom + 0.1))
        case .zoomOut: setZoom(max(0.25, canvas.zoom - 0.1))
        case .resetZoom: setZoom(1)
        }
    }

    private func handleWindowKey(_ event: NSEvent) -> Bool {
        var modifiers: ScreenshotEditorKeyModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        let key: String
        switch event.keyCode {
        case 36, 76: key = "return"
        case 51: key = "backspace"
        case 53: key = "escape"
        case 117: key = "delete"
        default: key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
        guard let command = ScreenshotEditorShortcut.command(for: key, modifiers: modifiers) else { return false }
        if window?.firstResponder is NSTextField || window?.firstResponder is NSTextView {
            switch command {
            case .close, .escape,
                 .decreaseStroke, .increaseStroke,
                 .decreaseFill, .increaseFill,
                 .zoomIn, .zoomOut, .resetZoom:
                break
            default:
                return false
            }
        }
        perform(command)
        return true
    }

    private func setZoom(_ zoom: CGFloat) {
        let clipView = scrollView.contentView
        let visible = clipView.bounds
        let oldZoom = max(0.01, canvas.zoom)
        let focus = canvas.selectedAnnotation.map {
            let bounds = ScreenshotEditorRenderer.selectionBounds($0)
            return CGPoint(x: bounds.midX + canvas.canvasOffset.x, y: bounds.midY + canvas.canvasOffset.y)
        } ?? CGPoint(x: visible.midX / oldZoom, y: visible.midY / oldZoom)
        let viewportOffset = CGPoint(
            x: focus.x * oldZoom - visible.minX,
            y: focus.y * oldZoom - visible.minY
        )
        canvas.zoom = zoom
        window?.contentView?.layoutSubtreeIfNeeded()
        let proposedOrigin = CGPoint(
            x: focus.x * zoom - viewportOffset.x,
            y: focus.y * zoom - viewportOffset.y
        )
        centerCanvasInViewport(proposedOrigin: proposedOrigin)
        preferences.zoom = zoom
        try? ConfigStore.set(Double(zoom), for: "screenshotZoomLevel")
        showStatus("Zoom \(Int((zoom * 100).rounded()))%")
    }

    @objc private func undo() { perform(.undo) }
    @objc private func closeEditor() { close() }
    @objc private func toggleMagnifierShape() { canvas.toggleMagnifierShape() }

    @objc private func widthChanged() {
        let values = [480, 720, 1080, 1440, 1920, 2160]
        preferences.maxWidth = values[max(0, widthPopup.indexOfSelectedItem)]
        try? ConfigStore.set(preferences.maxWidth, for: "screenshotMaxWidth")

    }

    @objc private func formatChanged() {
        preferences.format = formatPopup.indexOfSelectedItem == 1 ? .webp : .jpeg
        try? ConfigStore.set(preferences.format.rawValue, for: "screenshotSaveFormat")
    }

    @objc private func shrinkChanged() {
        preferences.copyShrink = shrinkPopup.indexOfSelectedItem + 1
        try? ConfigStore.set(preferences.copyShrink, for: "screenshotCopyShrink")
    }

    @objc private func qualityChanged() {
        preferences.quality = Int(qualitySlider.doubleValue.rounded())
        qualityValue.stringValue = "\(preferences.quality)%"
        try? ConfigStore.set(preferences.quality, for: "screenshotSaveQuality")
    }

    @objc private func styleStroke(_ sender: NSButton) {
        canvas.setSelectedStroke(CGFloat(sender.tag))
        persistDrawingPreferences()
    }

    @objc private func styleColor(_ sender: NSButton) {
        guard let hex = sender.identifier?.rawValue, let color = NSColor(stmHex: hex) else { return }
        canvas.setSelectedColor(color)
        persistDrawingPreferences()
    }

    @objc private func customStyleColor(_ sender: NSColorWell) {
        canvas.setSelectedColor(sender.color)
        persistDrawingPreferences()
    }

    @objc private func fillChanged() {
        canvas.setFillOpacity(CGFloat(fillSlider.doubleValue / 100))
        fillLabel.stringValue = "\(Int(fillSlider.doubleValue.rounded()))%"
    }

    @objc private func backdropSliderChanged(_ sender: NSSlider) {
        switch sender.tag {
        case 1: canvas.backdrop.padding = CGFloat(sender.doubleValue)
        case 2: canvas.backdrop.shadow = CGFloat(sender.doubleValue)
        case 3: canvas.backdrop.shadowBlur = CGFloat(sender.doubleValue)
        case 4: canvas.backdrop.shadowOffsetX = CGFloat(sender.doubleValue)
        case 5: canvas.backdrop.shadowOffsetY = CGFloat(sender.doubleValue)
        case 6: canvas.backdrop.shadowOpacity = CGFloat(sender.doubleValue / 100)
        case 7: canvas.backdrop.outerRadius = CGFloat(sender.doubleValue)
        case 8: canvas.backdrop.innerRadius = CGFloat(sender.doubleValue)
        case 9: updateGradient(angle: CGFloat(sender.doubleValue))
        case 14: canvas.backdrop.backgroundImageBlur = CGFloat(sender.doubleValue)
        default: break
        }
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    @objc private func backdropColorChanged(_ sender: NSColorWell) {
        switch sender.tag {
        case 10: canvas.backdrop.shadowColor = sender.color
        case 11: canvas.backdrop.background = .solid(sender.color)
        case 12: updateGradient(start: sender.color)
        case 13: updateGradient(end: sender.color)
        default: break
        }
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    @objc private func backdropModeChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            canvas.backdrop.background = .solid(
                NSColor(stmHex: backdropPreferences.solidColorHex) ?? NSColor(stmHex: "#1A1A1A")!
            )
        case 1:
            let stops = backdropPreferences.stops.compactMap { stop -> ScreenshotGradientStop? in
                guard let color = NSColor(stmHex: stop.colorHex) else { return nil }
                return ScreenshotGradientStop(color: color, position: stop.position)
            }
            let validStops = stops.count >= 2 ? stops : ScreenshotBackdropSettings.gradientPresets[2].1
            canvas.backdrop.background = backdropPreferences.radial
                ? .radial(stops: validStops)
                : .linear(stops: validStops, angle: gradientAngle)
            gradientEditor.stops = validStops
            rebuildGradientControls()
        default:
            canvas.backdrop.background = .image
            if canvas.backdrop.backgroundImage == nil { canvas.backdrop.backgroundImage = canvas.baseImage }
        }
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    @objc private func backdropSolidColor(_ sender: NSButton) {
        guard let hex = sender.identifier?.rawValue, let color = NSColor(stmHex: hex) else { return }
        canvas.backdrop.background = .solid(color)
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    @objc private func backdropGradientPreset(_ sender: NSButton) {
        let preset = ScreenshotBackdropSettings.gradientPresets[max(0, min(sender.tag, ScreenshotBackdropSettings.gradientPresets.count - 1))]
        gradientAngle = 135
        canvas.backdrop.background = .linear(stops: preset.1, angle: gradientAngle)
        gradientEditor.stops = preset.1
        rebuildGradientControls()
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    @objc private func gradientTypeChanged(_ sender: NSSegmentedControl) {
        let stops = currentGradientStops()
        canvas.backdrop.background = sender.selectedSegment == 1
            ? .radial(stops: stops)
            : .linear(stops: stops, angle: gradientAngle)
        gradientEditor.stops = stops
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    private func updateGradient(start: NSColor? = nil, end: NSColor? = nil, angle: CGFloat? = nil) {
        var stops = currentGradientStops()
        if stops.count < 2 { stops = ScreenshotBackdropSettings.gradientPresets[2].1 }
        if let start { stops[0].color = start }
        if let end { stops[stops.count - 1].color = end }
        if let angle { gradientAngle = angle }
        setGradientStops(stops)
        gradientEditor.stops = stops
        if start != nil || end != nil { rebuildGradientControls() }
    }

    private func currentGradientStops() -> [ScreenshotGradientStop] {
        switch canvas.backdrop.background {
        case .linear(let stops, let angle):
            gradientAngle = angle
            return stops
        case .radial(let stops):
            return stops
        default:
            return gradientEditor.stops.isEmpty
                ? ScreenshotBackdropSettings.gradientPresets[2].1
                : gradientEditor.stops
        }
    }

    private func setGradientStops(_ stops: [ScreenshotGradientStop]) {
        let normalized = stops
            .map { ScreenshotGradientStop(color: $0.color, position: max(0, min(1, $0.position))) }
            .sorted { $0.position < $1.position }
        guard normalized.count >= 2 else { return }
        if case .radial = canvas.backdrop.background {
            canvas.backdrop.background = .radial(stops: normalized)
        } else {
            canvas.backdrop.background = .linear(stops: normalized, angle: gradientAngle)
        }
        gradientEditor.stops = normalized
        canvas.needsDisplay = true
    }

    private func rebuildGradientControls() {
        gradientStopsStack.arrangedSubviews.forEach {
            gradientStopsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let stops = currentGradientStops()
        gradientEditor.stops = stops
        for (index, stop) in stops.enumerated() {
            let color = NSColorWell()
            color.color = stop.color
            color.tag = index
            color.target = self
            color.action = #selector(gradientStopColorChanged(_:))
            color.widthAnchor.constraint(equalToConstant: 30).isActive = true

            let position = NSTextField(string: String(Int((stop.position * 100).rounded())))
            position.tag = index
            position.alignment = .right
            position.target = self
            position.action = #selector(gradientStopPositionChanged(_:))
            position.widthAnchor.constraint(equalToConstant: 44).isActive = true
            let percent = NSTextField(labelWithString: "%")
            percent.textColor = ScreenshotEditorPalette.dim

            let row = NSStackView(views: [color, position, percent])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            if stops.count > 2 {
                let remove = NSButton(title: "×", target: self, action: #selector(removeGradientStop(_:)))
                remove.tag = index
                remove.bezelStyle = .inline
                remove.contentTintColor = NSColor(stmHex: "#EF4444")
                row.addArrangedSubview(remove)
            }
            gradientStopsStack.addArrangedSubview(row)
        }

        savedGradientsStack.arrangedSubviews.forEach {
            savedGradientsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard !savedGradientPresets.isEmpty else { return }
        let title = NSTextField(labelWithString: "SAVED GRADIENTS")
        title.font = .systemFont(ofSize: 10, weight: .medium)
        title.textColor = ScreenshotEditorPalette.dim
        savedGradientsStack.addArrangedSubview(title)
        for index in savedGradientPresets.indices {
            let apply = NSButton(title: "Saved #\(index + 1)", target: self, action: #selector(applySavedGradient(_:)))
            apply.tag = index
            apply.widthAnchor.constraint(equalToConstant: 210).isActive = true
            let remove = NSButton(title: "×", target: self, action: #selector(deleteSavedGradient(_:)))
            remove.tag = index
            remove.bezelStyle = .inline
            remove.contentTintColor = NSColor(stmHex: "#EF4444")
            let row = NSStackView(views: [apply, remove])
            row.orientation = .horizontal
            row.spacing = 6
            savedGradientsStack.addArrangedSubview(row)
        }
    }

    @objc private func gradientStopColorChanged(_ sender: NSColorWell) {
        var stops = currentGradientStops()
        guard stops.indices.contains(sender.tag) else { return }
        stops[sender.tag].color = sender.color
        setGradientStops(stops)
        rebuildGradientControls()
        persistBackdropSettings()
    }

    @objc private func gradientStopPositionChanged(_ sender: NSTextField) {
        var stops = currentGradientStops()
        guard stops.indices.contains(sender.tag) else { return }
        stops[sender.tag].position = CGFloat(max(0, min(100, sender.doubleValue))) / 100
        setGradientStops(stops)
        rebuildGradientControls()
        persistBackdropSettings()
    }

    @objc private func removeGradientStop(_ sender: NSButton) {
        var stops = currentGradientStops()
        guard stops.count > 2, stops.indices.contains(sender.tag) else { return }
        stops.remove(at: sender.tag)
        setGradientStops(stops)
        rebuildGradientControls()
        persistBackdropSettings()
    }

    @objc private func saveCurrentGradient() {
        let radial: Bool
        switch canvas.backdrop.background {
        case .radial: radial = true
        default: radial = false
        }
        let preset = ScreenshotSavedGradientPreset(
            stops: currentGradientStops().map {
                ScreenshotSavedGradientPreset.Stop(colorHex: $0.color.stmHex, position: $0.position)
            },
            radial: radial,
            angle: gradientAngle
        )
        savedGradientPresets.append(preset)
        persistSavedGradientPresets()
        rebuildGradientControls()
    }

    @objc private func applySavedGradient(_ sender: NSButton) {
        guard savedGradientPresets.indices.contains(sender.tag) else { return }
        let preset = savedGradientPresets[sender.tag]
        let stops = preset.stops.compactMap { stop -> ScreenshotGradientStop? in
            guard let color = NSColor(stmHex: stop.colorHex) else { return nil }
            return ScreenshotGradientStop(color: color, position: stop.position)
        }
        guard stops.count >= 2 else { return }
        gradientAngle = preset.angle
        canvas.backdrop.background = preset.radial
            ? .radial(stops: stops)
            : .linear(stops: stops, angle: gradientAngle)
        gradientEditor.stops = stops
        rebuildGradientControls()
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    @objc private func deleteSavedGradient(_ sender: NSButton) {
        guard savedGradientPresets.indices.contains(sender.tag) else { return }
        savedGradientPresets.remove(at: sender.tag)
        persistSavedGradientPresets()
        rebuildGradientControls()
    }

    private func persistSavedGradientPresets() {
        guard let data = try? JSONEncoder().encode(savedGradientPresets),
              let value = String(data: data, encoding: .utf8) else { return }
        try? ConfigStore.set(value, for: "screenshotSavedGradientPresets")
    }

    private func persistBackdropSettings() {
        let settings = canvas.backdrop
        backdropPreferences.padding = settings.padding
        backdropPreferences.shadow = settings.shadow
        backdropPreferences.shadowColorHex = settings.shadowColor.stmHex
        backdropPreferences.shadowBlur = settings.shadowBlur
        backdropPreferences.shadowOffsetX = settings.shadowOffsetX
        backdropPreferences.shadowOffsetY = settings.shadowOffsetY
        backdropPreferences.shadowOpacity = settings.shadowOpacity
        backdropPreferences.outerRadius = settings.outerRadius
        backdropPreferences.innerRadius = settings.innerRadius
        backdropPreferences.imageBlur = settings.backgroundImageBlur
        backdropPreferences.imageOffsetX = settings.backgroundImageOffsetX
        backdropPreferences.imageOffsetY = settings.backgroundImageOffsetY
        switch settings.background {
        case .solid(let color):
            backdropPreferences.mode = "solid"
            backdropPreferences.solidColorHex = color.stmHex
        case .linear(let stops, let angle):
            backdropPreferences.mode = "gradient"
            backdropPreferences.radial = false
            backdropPreferences.angle = angle
            backdropPreferences.stops = stops.map {
                ScreenshotSavedGradientPreset.Stop(colorHex: $0.color.stmHex, position: $0.position)
            }
        case .radial(let stops):
            backdropPreferences.mode = "gradient"
            backdropPreferences.radial = true
            backdropPreferences.angle = gradientAngle
            backdropPreferences.stops = stops.map {
                ScreenshotSavedGradientPreset.Stop(colorHex: $0.color.stmHex, position: $0.position)
            }
        case .image:
            backdropPreferences.mode = "image"
        }
        guard let data = try? JSONEncoder().encode(backdropPreferences),
              let value = String(data: data, encoding: .utf8) else { return }
        try? ConfigStore.set(value, for: "screenshotBackdropSettings")
    }

    @objc private func uploadBackdropImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            self?.backdropPreferences.imagePath = url.path
            self?.backdropPreferences.useCurrentScreenshot = false
            self?.canvas.backdrop.backgroundImage = image
            self?.canvas.backdrop.background = .image
            self?.canvas.needsDisplay = true
            self?.persistBackdropSettings()
        }
    }

    @objc private func useScreenshotBackdrop() {
        canvas.backdrop.backgroundImage = canvas.baseImage
        canvas.backdrop.background = .image
        backdropPreferences.imagePath = nil
        backdropPreferences.useCurrentScreenshot = true
        persistBackdropSettings()
        canvas.needsDisplay = true
    }

    @objc private func resetBackdropPosition() {
        canvas.backdrop.backgroundImageOffsetX = 0
        canvas.backdrop.backgroundImageOffsetY = 0
        canvas.needsDisplay = true
        persistBackdropSettings()
    }

    @objc private func copyScreenshot() {
        guard let image = canvas.renderedImage(), let data = encodedImage(image, forCopy: true) else {
            showStatus("Failed to copy screenshot", error: true)
            return
        }
        let type = ScreenshotImageExporter.pasteboardType(for: effectiveFormat())
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setData(data, forType: type) else {
            showStatus("Failed to copy screenshot", error: true)
            return
        }
        showStatus("Screenshot copied!\(preferences.copyShrink > 1 ? " (\(preferences.copyShrink)x shrink)" : "")")
        closeAfterSuccessfulAction()
    }

    @objc private func saveScreenshot() {
        guard let image = canvas.renderedImage(), let data = encodedImage(image, forCopy: false) else {
            showStatus("Failed to save screenshot", error: true)
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let name = "stm-screenshot-\(formatter.string(from: Date())).\(effectiveFormat().fileExtension)"
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            showStatus("Saved \(name)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
            closeAfterSuccessfulAction()
        } catch {
            showStatus("Save failed: \(error.localizedDescription)", error: true)
        }
    }

    private func encodedImage(_ original: CGImage, forCopy: Bool) -> Data? {
        let plan = ScreenshotExportPlan(
            pixelWidth: original.width,
            pixelHeight: original.height,
            requestedFormat: preferences.format,
            quality: preferences.quality,
            copyShrink: preferences.copyShrink,
            roundedBackdrop: canvas.backdrop.isEnabled && canvas.backdrop.outerRadius > 0
        )
        return ScreenshotImageExporter.data(from: original, plan: plan, forCopy: forCopy)
    }


    private func effectiveFormat() -> ScreenshotExportFormat {
        preferences.format == .jpeg && canvas.backdrop.isEnabled && canvas.backdrop.outerRadius > 0 ? .png : preferences.format
    }


    private func closeAfterSuccessfulAction() {
        guard !isClosingAfterAction else { return }
        isClosingAfterAction = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.close() }
    }

    private func showStatus(_ message: String, error: Bool = false) {
        statusLabel.stringValue = "  \(message)  "
        statusLabel.textColor = error ? NSColor(stmHex: "#FCA5A5")! : ScreenshotEditorPalette.text
        statusLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.statusLabel.isHidden = true }
    }

    private func persistDrawingPreferences() {
        preferences.colorHex = canvas.currentColor.stmHex
        preferences.strokeWidth = canvas.currentStrokeWidth
        try? ConfigStore.set(preferences.colorHex, for: "screenshotEditorColor")
        try? ConfigStore.set(Int(preferences.strokeWidth.rounded()), for: "screenshotStrokeWidth")
    }

    private static func loadPreferences() -> ScreenshotEditorPreferences {
        var preferences = ScreenshotEditorPreferences.defaults
        preferences.maxWidth = ConfigStore.int("screenshotMaxWidth", default: preferences.maxWidth)
        preferences.format = ScreenshotExportFormat(rawValue: ConfigStore.string("screenshotSaveFormat") ?? "") ?? preferences.format
        preferences.quality = ConfigStore.int("screenshotSaveQuality", default: preferences.quality)
        preferences.copyShrink = ConfigStore.int("screenshotCopyShrink", default: preferences.copyShrink)
        preferences.colorHex = ConfigStore.string("screenshotEditorColor") ?? preferences.colorHex
        preferences.strokeWidth = CGFloat(ConfigStore.int("screenshotStrokeWidth", default: Int(preferences.strokeWidth)))
        preferences.zoom = CGFloat(ConfigStore.double("screenshotZoomLevel", default: Double(preferences.zoom)))
        preferences.defaultTool = ScreenshotTool(rawValue: ConfigStore.string("screenshotEditorDefaultTool") ?? "") ?? preferences.defaultTool
        return preferences
    }

    private static func loadSavedGradientPresets() -> [ScreenshotSavedGradientPreset] {
        guard let value = ConfigStore.string("screenshotSavedGradientPresets"),
              let data = value.data(using: .utf8),
              let presets = try? JSONDecoder().decode([ScreenshotSavedGradientPreset].self, from: data) else {
            return []
        }
        return presets
    }

    private static func loadBackdropPreferences() -> ScreenshotBackdropPreferences {
        guard let value = ConfigStore.string("screenshotBackdropSettings"),
              let data = value.data(using: .utf8),
              let settings = try? JSONDecoder().decode(ScreenshotBackdropPreferences.self, from: data) else {
            return ScreenshotBackdropPreferences()
        }
        return settings
    }

    private static func makeBackdropSettings(
        from preferences: ScreenshotBackdropPreferences,
        baseImage: CGImage
    ) -> ScreenshotBackdropSettings {
        var settings = ScreenshotBackdropSettings()
        settings.padding = preferences.padding
        settings.shadow = preferences.shadow
        settings.shadowColor = NSColor(stmHex: preferences.shadowColorHex) ?? .black
        settings.shadowBlur = preferences.shadowBlur
        settings.shadowOffsetX = preferences.shadowOffsetX
        settings.shadowOffsetY = preferences.shadowOffsetY
        settings.shadowOpacity = preferences.shadowOpacity
        settings.outerRadius = preferences.outerRadius
        settings.innerRadius = preferences.innerRadius
        settings.backgroundImageBlur = preferences.imageBlur
        settings.backgroundImageOffsetX = preferences.imageOffsetX
        settings.backgroundImageOffsetY = preferences.imageOffsetY
        let stops = preferences.stops.compactMap { stop -> ScreenshotGradientStop? in
            guard let color = NSColor(stmHex: stop.colorHex) else { return nil }
            return ScreenshotGradientStop(color: color, position: stop.position)
        }
        switch preferences.mode {
        case "gradient":
            let validStops = stops.count >= 2 ? stops : ScreenshotBackdropSettings.gradientPresets[2].1
            settings.background = preferences.radial
                ? .radial(stops: validStops)
                : .linear(stops: validStops, angle: preferences.angle)
        case "image":
            settings.background = .image
            if preferences.useCurrentScreenshot {
                settings.backgroundImage = baseImage
            } else if let path = preferences.imagePath,
                      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) {
                settings.backgroundImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
            if settings.backgroundImage == nil { settings.backgroundImage = baseImage }
        default:
            settings.background = .solid(NSColor(stmHex: preferences.solidColorHex) ?? NSColor(stmHex: "#1A1A1A")!)
        }
        settings.isEnabled = false
        return settings
    }

    deinit {
        Logger.log("screenshot native editor deallocated")
    }

    func windowWillClose(_ notification: Notification) {
        Logger.log("screenshot native editor window closing")
        onClose?()
    }
}
