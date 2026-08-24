import Cocoa

final class CredentialsGuideWindowController: NSWindowController, NSTextFieldDelegate {
    private static let cardWidth: CGFloat = 650
    private static let rowWidth: CGFloat = 616
    private static let fieldMinWidth: CGFloat = 530
    private static let codeFieldMinWidth: CGFloat = 470
    private let onChooseJSON: () -> Void
    private let workerNameField = NSTextField(string: "share")
    private let workerURLField = NSTextField(string: "")
    private let authTokenField = NSTextField(string: "")
    private var dynamicFields: [String: NSTextField] = [:]

    init(onChooseJSON: @escaping () -> Void) {
        self.onChooseJSON = onChooseJSON
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cloudflare Worker Setup"
        window.minSize = NSSize(width: 720, height: 560)
        super.init(window: window)
        workerURLField.stringValue = "https://share.seo-time-machines.workers.dev"
        workerNameField.isEditable = false
        workerURLField.isEditable = false
        authTokenField.stringValue = ConfigStore.string("authToken") ?? ""
        buildUI()
        updateDynamicFields()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildUI() {
        guard let window else { return }
        let root = GuideBackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        root.addSubview(scroll)

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -36)
        ])

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(existingCredentialsCard())
        stack.addArrangedSubview(formCard())
        stack.addArrangedSubview(stepCard(
            number: "1",
            title: "Create a Cloudflare account",
            description: "Use a free Cloudflare account. If you already have one, sign in to that account instead.",
            rows: [
                linkRow(label: "Open in browser", title: "https://dash.cloudflare.com/sign-up", url: "https://dash.cloudflare.com/sign-up"),
                noteBox(title: "What to expect", lines: [
                    "Use the same Cloudflare account for every step in this guide.",
                    "If Cloudflare asks you to verify your email address, finish that first.",
                    "When you return here, keep this window open and continue with Node.js."
                ])
            ]
        ))
        stack.addArrangedSubview(stepCard(
            number: "2",
            title: "Install Node.js",
            description: "Wrangler, Cloudflare's command line tool, runs on Node.js. Skip this if Node is already installed.",
            rows: [
                linkRow(label: "Download and install", title: "https://nodejs.org", url: "https://nodejs.org"),
                noteBox(title: "What to expect", lines: [
                    "Install the LTS version and accept the default options.",
                    "After installing, close and reopen Terminal so new commands are available.",
                    "Run node -v in Terminal. A version number means Node is ready."
                ])
            ]
        ))
        stack.addArrangedSubview(stepCard(
            number: "3",
            title: "Install Wrangler and log in",
            description: "Open Terminal and run these commands. Wrangler deploys the Worker to your Cloudflare account.",
            rows: [
                codeRow(label: "Install Wrangler globally", text: "npm install -g wrangler"),
                codeRow(label: "Check Wrangler installed", text: "wrangler --version"),
                codeRow(label: "Log in to Cloudflare", text: "wrangler login"),
                noteBox(title: "What happens when you run wrangler login", lines: [
                    "Wrangler opens your browser and asks Cloudflare to authorize the command line tool.",
                    "Click Allow for the Cloudflare account you want the Worker to live in.",
                    "If you are signed in to the wrong account, sign out first or use a private browser window."
                ])
            ]
        ))
        stack.addArrangedSubview(stepCard(
            number: "4",
            title: "Open the STM Chrome Worker guide",
            description: "Use the Chrome extension guide only as a reference for the canonical STM Worker. Production changes must run from the GMB worker-setup directory.",
            rows: [
                linkRow(label: "Full STM Worker guide", title: "Open chrome-extension://phhmonggcijfgpcenlbhaeoepiadnpjj/cloudflare-setup-guide.html", url: "chrome-extension://phhmonggcijfgpcenlbhaeoepiadnpjj/cloudflare-setup-guide.html"),
                noteBox(title: "What to use from that page", lines: [
                    "Keep the production Worker Name as share and its URL as https://share.seo-time-machines.workers.dev.",
                    "Use the Transcription Auth Token from this window for JITSI_TRANSCRIBE_AUTH_TOKEN. Do not reuse or overwrite AUTH_TOKEN.",
                    "Do not deploy a Worker copy from STM Desktop Listener or STM Recorder."
                ])
            ]
        ))
        stack.addArrangedSubview(stepCard(
            number: "5",
            title: "Create the storage bucket",
            description: "The full STM Worker uses one R2 bucket for shared STM cloud tools. The Chrome guide uses this exact bucket name.",
            rows: [
                codeRow(label: "Create the bucket", text: "wrangler r2 bucket create stm-recorder-videos"),
                noteBox(title: "What to expect", lines: [
                    "If Cloudflare says the bucket already exists in this account, that is usually fine.",
                    "If Wrangler asks which account to use, choose the same account you authorized earlier.",
                    "Do not rename the bucket unless you also edit wrangler.toml to match."
                ])
            ]
        ))
        stack.addArrangedSubview(stepCard(
            number: "6",
            title: "Deploy the Worker",
            description: "Open Terminal in the canonical GMB-Extractor/worker-setup checkout. Never deploy from an STM Desktop Listener or STM Recorder directory.",
            rows: [
                dynamicCodeRow(label: "Mac folder command", key: "macFolder"),
                codeRow(label: "Deploy to Cloudflare", text: "wrangler deploy"),
                noteBox(title: "What to expect", lines: [
                    "Wrangler must read the canonical GMB worker-setup files.",
                    "The production URL must remain https://share.seo-time-machines.workers.dev.",
                    "Do not rename, replace, delete, or migrate the production Worker."
                ])
            ]
        ))
        stack.addArrangedSubview(stepCard(
            number: "7",
            title: "Set the transcription auth token secret",
            description: "The desktop app sends this token with each dictation request. The Worker checks it before accepting audio.",
            rows: [
                codeRow(label: "Run this in the canonical Worker folder", text: "wrangler secret put JITSI_TRANSCRIBE_AUTH_TOKEN"),
                dynamicCodeRow(label: "Token to paste when prompted", key: "authToken"),
                noteBox(title: "Important", lines: [
                    "Cloudflare secrets are write-only. You cannot read this value back later.",
                    "If you change the transcription secret, update the JSON file and import credentials again.",
                    "Do not change AUTH_TOKEN, the Worker name, or the production URL."
                ])
            ]
        ))
        stack.addArrangedSubview(stepCard(
            number: "8",
            title: "Import credentials into STM Desktop Listener",
            description: "Create a JSON file with the immutable Worker URL and Transcription Auth Token, then import it here.",
            rows: [
                dynamicCodeRow(label: "Credentials JSON", key: "jsonTemplate", multiline: true),
                actionButtonsRow(),
                noteBox(title: "What each value means", lines: [
                    "workerUrl must remain https://share.seo-time-machines.workers.dev.",
                    "authToken is the same value saved with wrangler secret put JITSI_TRANSCRIBE_AUTH_TOKEN."
                ])
            ]
        ))
    }

    private func header() -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let title = label("Cloudflare Worker Setup", font: .boldSystemFont(ofSize: 26), color: .white)
        let subtitle = label("STM Desktop Listener uses the shared production Worker for voice dictation. Keep https://share.seo-time-machines.workers.dev as the Worker URL and use its dedicated Transcription Auth Token. Do not reuse or overwrite the main AUTH_TOKEN.", font: .systemFont(ofSize: 13), color: SettingsPalette.muted)
        subtitle.maximumNumberOfLines = 0
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    private func formCard() -> NSView {
        let stack = cardStack()
        stack.addArrangedSubview(fieldBlock(
            title: "Worker Name (must remain share)",
            field: workerNameField,
            note: "The production Worker name is share. Do not rename, replace, delete, or migrate it."
        ))
        stack.addArrangedSubview(fieldBlock(
            title: "Worker URL",
            field: workerURLField,
            note: "Use https://share.seo-time-machines.workers.dev. This production URL is immutable."
        ))

        let tokenRow = NSStackView()
        tokenRow.translatesAutoresizingMaskIntoConstraints = false
        tokenRow.orientation = .horizontal
        tokenRow.alignment = .centerY
        tokenRow.spacing = 8
        prepareTextField(authTokenField)
        tokenRow.addArrangedSubview(authTokenField)
        authTokenField.widthAnchor.constraint(greaterThanOrEqualToConstant: 390).isActive = true

        let tokenStack = NSStackView()
        tokenStack.translatesAutoresizingMaskIntoConstraints = false
        tokenStack.orientation = .vertical
        tokenStack.alignment = .leading
        tokenStack.spacing = 6
        tokenStack.addArrangedSubview(label("Transcription Auth Token", font: .boldSystemFont(ofSize: 12), color: .white))
        tokenStack.addArrangedSubview(tokenRow)
        let hint = label("Paste the existing shared transcription token. It must match JITSI_TRANSCRIBE_AUTH_TOKEN for every Desktop Listener and Jitsi client using production. Do not generate a replacement and never replace the main AUTH_TOKEN.", font: .systemFont(ofSize: 12), color: SettingsPalette.muted)
        hint.maximumNumberOfLines = 0
        tokenStack.addArrangedSubview(hint)
        stack.addArrangedSubview(tokenStack)
        return card(stack)
    }

    private func existingCredentialsCard() -> NSView {
        let stack = cardStack()
        let eyebrow = label("Fastest path", font: .boldSystemFont(ofSize: 11), color: NSColor.systemOrange)
        stack.addArrangedSubview(eyebrow)
        stack.addArrangedSubview(label("Already have credentials?", font: .boldSystemFont(ofSize: 17), color: .white))
        let body = label("Choose an existing JSON file if you already have workerUrl and authToken. This is enough for dictation.", font: .systemFont(ofSize: 13), color: SettingsPalette.muted)
        body.maximumNumberOfLines = 0
        stack.addArrangedSubview(body)
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 10
        row.addArrangedSubview(button("Choose JSON", action: #selector(chooseJSON)))
        row.addArrangedSubview(button("Copy JSON Template", action: #selector(copyJSONTemplate)))
        row.addArrangedSubview(button("Open STM Chrome Guide", action: #selector(openChromeGuide)))
        stack.addArrangedSubview(row)
        return highlightedCard(stack)
    }

    private func stepCard(number: String, title: String, description: String, rows: [NSView]) -> NSView {
        let stack = cardStack()
        let titleRow = NSStackView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10
        titleRow.addArrangedSubview(numberBadge(number))
        titleRow.addArrangedSubview(label(title, font: .boldSystemFont(ofSize: 16), color: .white))
        stack.addArrangedSubview(titleRow)
        let desc = label(description, font: .systemFont(ofSize: 13), color: SettingsPalette.muted)
        desc.maximumNumberOfLines = 0
        stack.addArrangedSubview(desc)
        for row in rows {
            stack.addArrangedSubview(row)
        }
        return card(stack)
    }

    private func fieldBlock(title: String, field: NSTextField, note: String) -> NSView {
        prepareTextField(field)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.addArrangedSubview(label(title, font: .boldSystemFont(ofSize: 12), color: .white))
        stack.addArrangedSubview(field)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.fieldMinWidth).isActive = true
        let hint = label(note, font: .systemFont(ofSize: 12), color: SettingsPalette.muted)
        hint.maximumNumberOfLines = 0
        stack.addArrangedSubview(hint)
        return stack
    }

    private func prepareTextField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = .white
        field.backgroundColor = SettingsPalette.root
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
    }

    private func actionButtonsRow() -> NSView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 10
        row.addArrangedSubview(button("Copy JSON Template", action: #selector(copyJSONTemplate)))
        row.addArrangedSubview(button("Choose JSON", action: #selector(chooseJSON)))
        row.addArrangedSubview(button("Open Config Folder", action: #selector(openConfigFolder)))
        return row
    }

    private func codeRow(label labelText: String, text: String) -> NSView {
        let field = codeField(text, multiline: false)
        return codeContainer(labelText: labelText, field: field)
    }

    private func dynamicCodeRow(label labelText: String, key: String, multiline: Bool = false) -> NSView {
        let field = codeField("", multiline: multiline)
        dynamicFields[key] = field
        return codeContainer(labelText: labelText, field: field)
    }

    private func codeContainer(labelText: String, field: NSTextField) -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.addArrangedSubview(label(labelText, font: .systemFont(ofSize: 11), color: SettingsPalette.muted))

        let row = RoundedPanelView(fillColor: SettingsPalette.root, strokeColor: SettingsPalette.stroke, radius: 7)
        let inner = NSStackView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.spacing = 8
        inner.addArrangedSubview(field)
        let copy = button("Copy", action: #selector(copyCode(_:)))
        copy.payload = field
        inner.addArrangedSubview(copy)
        row.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            inner.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            inner.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            row.widthAnchor.constraint(equalToConstant: Self.rowWidth)
        ])
        stack.addArrangedSubview(row)
        return stack
    }

    private func codeField(_ text: String, multiline: Bool) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = SettingsPalette.cyan
        field.maximumNumberOfLines = multiline ? 0 : 1
        field.lineBreakMode = multiline ? .byWordWrapping : .byTruncatingMiddle
        field.isSelectable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.codeFieldMinWidth).isActive = true
        return field
    }

    private func linkRow(label labelText: String, title: String, url: String) -> NSView {
        let field = codeField(title, multiline: false)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.addArrangedSubview(label(labelText, font: .systemFont(ofSize: 11), color: SettingsPalette.muted))

        let row = RoundedPanelView(fillColor: SettingsPalette.root, strokeColor: SettingsPalette.stroke, radius: 7)
        let inner = NSStackView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.spacing = 8
        inner.addArrangedSubview(field)
        let open = button("Open", action: #selector(openURL(_:)))
        open.payload = url
        inner.addArrangedSubview(open)
        row.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            inner.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            inner.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            row.widthAnchor.constraint(equalToConstant: Self.rowWidth)
        ])
        stack.addArrangedSubview(row)
        return stack
    }

    private func noteBox(title: String, lines: [String]) -> NSView {
        let box = RoundedPanelView(fillColor: SettingsPalette.root.withAlphaComponent(0.72), strokeColor: SettingsPalette.cyan.withAlphaComponent(0.28), radius: 7)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.addArrangedSubview(label(title, font: .boldSystemFont(ofSize: 12), color: .white))
        for line in lines {
            let row = label("- \(line)", font: .systemFont(ofSize: 12), color: SettingsPalette.muted)
            row.maximumNumberOfLines = 0
            stack.addArrangedSubview(row)
        }
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            box.widthAnchor.constraint(equalToConstant: Self.rowWidth)
        ])
        return box
    }

    private func cardStack() -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }

    private func card(_ content: NSView) -> NSView {
        let panel = RoundedPanelView(fillColor: SettingsPalette.panel, strokeColor: SettingsPalette.stroke, radius: 12)
        return panelWithContent(panel, content)
    }

    private func highlightedCard(_ content: NSView) -> NSView {
        let panel = RoundedPanelView(fillColor: SettingsPalette.panel, strokeColor: NSColor.systemOrange, radius: 12, strokeWidth: 2)
        return panelWithContent(panel, content)
    }

    private func panelWithContent(_ panel: RoundedPanelView, _ content: NSView) -> NSView {
        panel.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
            panel.widthAnchor.constraint(equalToConstant: Self.cardWidth)
        ])
        return panel
    }

    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 13), color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        return field
    }

    private func button(_ title: String, action: Selector) -> GuideActionButton {
        let button = GuideActionButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = .boldSystemFont(ofSize: 12)
        return button
    }

    private func numberBadge(_ number: String) -> NSView {
        let badge = NSTextField(labelWithString: number)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.alignment = .center
        badge.font = .boldSystemFont(ofSize: 12)
        badge.textColor = .black
        badge.wantsLayer = true
        badge.layer?.backgroundColor = SettingsPalette.cyan.cgColor
        badge.layer?.cornerRadius = 12
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24)
        ])
        return badge
    }

    func controlTextDidChange(_ obj: Notification) {
        updateDynamicFields()
    }


    @objc private func chooseJSON() {
        onChooseJSON()
    }

    @objc private func copyJSONTemplate() {
        copyToPasteboard(jsonTemplate())
    }

    @objc private func openChromeGuide() {
        open("chrome-extension://phhmonggcijfgpcenlbhaeoepiadnpjj/cloudflare-setup-guide.html")
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(AppPaths.applicationSupport)
    }

    @objc private func copyCode(_ sender: GuideActionButton) {
        guard let field = sender.payload as? NSTextField else { return }
        copyToPasteboard(field.stringValue)
        let original = sender.title
        sender.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            sender.title = original
        }
    }

    @objc private func openURL(_ sender: GuideActionButton) {
        guard let url = sender.payload as? String else { return }
        open(url)
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func updateDynamicFields() {
        dynamicFields["macFolder"]?.stringValue = "cd \"/path/to/GMB-Extractor/worker-setup\""
        dynamicFields["authToken"]?.stringValue = currentToken()
        dynamicFields["jsonTemplate"]?.stringValue = jsonTemplate()
    }

    private func jsonTemplate() -> String {
        """
        {
          "workerUrl": "\(currentWorkerURL())",
          "authToken": "\(currentToken())",
          "extensionId": "phhmonggcijfgpcenlbhaeoepiadnpjj",
          "browserBundleId": "com.brave.Browser"
        }
        """
    }

    private func currentWorkerURL() -> String {
        "https://share.seo-time-machines.workers.dev"
    }

    private func currentToken() -> String {
        let token = authTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? "<paste-existing-transcription-token>" : token
    }


}

private final class GuideBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        SettingsPalette.root.setFill()
        bounds.fill()
    }
}

private final class GuideActionButton: NSButton {
    var payload: Any?
}
