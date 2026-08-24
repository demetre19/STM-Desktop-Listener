import Cocoa

final class NewFileController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let toast: ToastController
    private var panel: NSPanel?
    private var targetFolder: URL?
    private var selectedKind: NewFileKind = .text
    private var buttons: [NewFileKind: NewFileKindButton] = [:]
    private let nameField = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "")

    init(toast: ToastController) {
        self.toast = toast
    }

    func show(targetFolder: URL) {
        self.targetFolder = targetFolder
        if panel == nil {
            panel = buildPanel()
        }
        nameField.stringValue = ""
        errorLabel.stringValue = targetFolder.path
        selectKind(.text)
        guard let panel = panel else { return }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        nameField.becomeFirstResponder()
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "New File"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.level = .floating

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = SettingsPalette.root.cgColor
        panel.contentView = root

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "Create New File")
        title.font = .boldSystemFont(ofSize: 22)
        title.textColor = SettingsPalette.text
        stack.addArrangedSubview(title)

        let formats = NSStackView()
        formats.orientation = .horizontal
        formats.spacing = 8
        formats.translatesAutoresizingMaskIntoConstraints = false
        for kind in NewFileKind.allCases {
            let button = NewFileKindButton(title: kind.title)
            button.target = self
            button.action = #selector(selectKindAction(_:))
            button.tag = kind.tag
            button.widthAnchor.constraint(equalToConstant: 88).isActive = true
            buttons[kind] = button
            formats.addArrangedSubview(button)
        }
        stack.addArrangedSubview(formats)

        let fieldLabel = NSTextField(labelWithString: "File name")
        fieldLabel.font = .boldSystemFont(ofSize: 12)
        fieldLabel.textColor = SettingsPalette.muted
        stack.addArrangedSubview(fieldLabel)

        nameField.placeholderString = "New file"
        nameField.font = .systemFont(ofSize: 16)
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(createFileAction)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 460).isActive = true
        stack.addArrangedSubview(nameField)

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = SettingsPalette.muted
        errorLabel.lineBreakMode = .byTruncatingMiddle
        errorLabel.maximumNumberOfLines = 1
        errorLabel.widthAnchor.constraint(equalToConstant: 460).isActive = true
        stack.addArrangedSubview(errorLabel)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.alignment = .centerY
        actions.addArrangedSubview(NSView())
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancel.bezelStyle = .rounded
        let create = NSButton(title: "Create", target: self, action: #selector(createFileAction))
        create.bezelStyle = .rounded
        create.keyEquivalent = "\r"
        actions.addArrangedSubview(cancel)
        actions.addArrangedSubview(create)
        actions.widthAnchor.constraint(equalToConstant: 460).isActive = true
        stack.addArrangedSubview(actions)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 26)
        ])

        return panel
    }

    @objc private func selectKindAction(_ sender: NSButton) {
        guard let kind = NewFileKind(tag: sender.tag) else { return }
        selectKind(kind)
    }

    private func selectKind(_ kind: NewFileKind) {
        selectedKind = kind
        for (buttonKind, button) in buttons {
            button.isSelectedKind = buttonKind == kind
        }
    }

    @objc private func cancelAction() {
        panel?.orderOut(nil)
    }

    @objc private func createFileAction() {
        do {
            guard let targetFolder = targetFolder else { throw SimpleError("No Finder folder is selected.") }
            let name = try cleanName(nameField.stringValue)
            let url = uniqueURL(folder: targetFolder, name: name, kind: selectedKind)
            try NewFileWriter.write(kind: selectedKind, title: name, to: url)
            panel?.orderOut(nil)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            toast.show(message: "Created", placement: .center)
            Logger.log("new file created kind=\(selectedKind.rawValue) path=\(url.path)")
        } catch {
            errorLabel.stringValue = error.localizedDescription
            errorLabel.textColor = .systemRed
            Logger.log("new file failed \(error.localizedDescription)")
        }
    }

    private func cleanName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SimpleError("Enter a file name.") }
        guard !trimmed.contains("/") && !trimmed.contains(":") else {
            throw SimpleError("File names cannot contain / or :")
        }
        return trimmed
    }

    private func uniqueURL(folder: URL, name: String, kind: NewFileKind) -> URL {
        let base = stripKnownExtension(name)
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(kind.fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension(kind.fileExtension)
            counter += 1
        }
        return candidate
    }

    private func stripKnownExtension(_ name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension.lowercased()
        guard NewFileKind.allCases.contains(where: { $0.fileExtension == ext }) else { return name }
        return url.deletingPathExtension().lastPathComponent
    }

    func controlTextDidChange(_ obj: Notification) {
        errorLabel.textColor = SettingsPalette.muted
        errorLabel.stringValue = targetFolder?.path ?? ""
    }
}

final class NewFileKindButton: NSButton {
    var isSelectedKind = false {
        didSet { needsDisplay = true }
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        font = .boldSystemFont(ofSize: 12)
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        (isSelectedKind ? SettingsPalette.badge : SettingsPalette.selected).setFill()
        path.fill()
        (isSelectedKind ? SettingsPalette.cyan : SettingsPalette.stroke).setStroke()
        path.lineWidth = isSelectedKind ? 2 : 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: isSelectedKind ? SettingsPalette.text : SettingsPalette.muted,
            .paragraphStyle: paragraph
        ]
        title.draw(in: bounds.insetBy(dx: 8, dy: 7), withAttributes: attrs)
    }
}

enum NewFileKind: String, CaseIterable {
    case text
    case doc
    case html
    case word
    case excel

    var title: String {
        switch self {
        case .text: return "Text"
        case .doc: return "Doc"
        case .html: return "HTML"
        case .word: return "Word"
        case .excel: return "Excel"
        }
    }

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .doc: return "doc"
        case .html: return "html"
        case .word: return "docx"
        case .excel: return "xlsx"
        }
    }

    var tag: Int { NewFileKind.allCases.firstIndex(of: self) ?? 0 }

    init?(tag: Int) {
        guard NewFileKind.allCases.indices.contains(tag) else { return nil }
        self = NewFileKind.allCases[tag]
    }
}

enum NewFileWriter {
    static func write(kind: NewFileKind, title: String, to url: URL) throws {
        switch kind {
        case .text:
            try Data().write(to: url, options: .atomic)
        case .doc:
            try "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 }".write(to: url, atomically: true, encoding: .utf8)
        case .html:
            try html(title: title).write(to: url, atomically: true, encoding: .utf8)
        case .word:
            try writeDocx(to: url)
        case .excel:
            try writeXlsx(to: url)
        }
    }

    private static func html(title: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
        </head>
        <body>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func writeDocx(to url: URL) throws {
        try writePackage(to: url) { root in
            try writeFile(root.appendingPathComponent("[Content_Types].xml"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
            """)
            try makeDirectory(root.appendingPathComponent("_rels", isDirectory: true))
            try makeDirectory(root.appendingPathComponent("word", isDirectory: true))
            try writeFile(root.appendingPathComponent("_rels/.rels"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
            """)
            try writeFile(root.appendingPathComponent("word/document.xml"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/><w:sectPr/></w:body></w:document>
            """)
        }
    }

    private static func writeXlsx(to url: URL) throws {
        try writePackage(to: url) { root in
            try writeFile(root.appendingPathComponent("[Content_Types].xml"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """)
            try makeDirectory(root.appendingPathComponent("_rels", isDirectory: true))
            try makeDirectory(root.appendingPathComponent("xl/_rels", isDirectory: true))
            try makeDirectory(root.appendingPathComponent("xl/worksheets", isDirectory: true))
            try writeFile(root.appendingPathComponent("_rels/.rels"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """)
            try writeFile(root.appendingPathComponent("xl/workbook.xml"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
            """)
            try writeFile(root.appendingPathComponent("xl/_rels/workbook.xml.rels"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
            """)
            try writeFile(root.appendingPathComponent("xl/worksheets/sheet1.xml"), content: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>
            """)
        }
    }

    private static func writePackage(to url: URL, populate: (URL) throws -> Void) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stm-new-file-\(UUID().uuidString)", isDirectory: true)
        try makeDirectory(temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        try populate(temp)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", url.path, "."]
        process.currentDirectoryURL = temp
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SimpleError("Could not create \(url.lastPathComponent).")
        }
    }

    private static func writeFile(_ url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
