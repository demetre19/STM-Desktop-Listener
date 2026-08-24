import Foundation
import ServiceManagement

enum LoginItemService {
    static func registerByDefaultIfNeeded() {
        guard #available(macOS 13.0, *) else {
            Logger.log("login item skipped because SMAppService requires macOS 13 or newer")
            return
        }
        guard !ConfigStore.bool("loginItemAutoRegisterCompleted", default: false) else {
            return
        }

        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            try ConfigStore.set(true, for: "loginItemAutoRegisterCompleted")
            Logger.log("login item status=\(String(describing: SMAppService.mainApp.status))")
        } catch {
            Logger.log("login item register failed: \(error.localizedDescription)")
        }
    }
}
