import Cocoa

final class BrowserBridge {
    private var extensionID: String {
        ConfigStore.string("extensionId") ?? "phhmonggcijfgpcenlbhaeoepiadnpjj"
    }

    private var browserBundleID: String {
        ConfigStore.string("browserBundleId") ?? "com.brave.Browser"
    }

    func openScreenshot(token: String) {
        openExtension(path: "screenshot-editor.html", query: "stmDesktopToken=\(token)")
    }


    func openImageOptimizer(manifestToken: String) {
        openExtension(path: "settings/image-optimizer.html", query: "stmDesktopManifest=\(manifestToken)")
    }

    private func openExtension(path: String, query: String) {
        guard let url = URL(string: "chrome-extension://\(extensionID)/\(path)?\(query)") else { return }
        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: browserBundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error = error {
                    Logger.log("browser bridge open failed \(error.localizedDescription)")
                    workspace.open(url)
                }
            }
        } else {
            workspace.open(url)
        }
    }
}
