import Cocoa
import Carbon

final class HotkeyManager {
    private var refs: [FeatureID: EventHotKeyRef] = [:]
    private var ids: [UInt32: FeatureID] = [:]
    private var commandRefs: [String: EventHotKeyRef] = [:]
    private var commandIds: [UInt32: String] = [:]
    private var eventHandlerInstalled = false
    private let signature = OSType(0x53444C54)
    var onTrigger: ((FeatureID) -> Void)?
    var onCommandTrigger: ((String) -> Void)?

    func registerEnabledFeatureHotkeys() {
        unregisterAll()
        installHandlerIfNeeded()

        for (index, feature) in FeatureID.allCases.enumerated() {
            if feature == .textTransformers {
                continue
            }
            if feature.isTextTransformerChild && !ConfigStore.featureEnabled(.textTransformers) {
                continue
            }
            if feature.requiresFinderFrontmostForHotkey && !Self.finderIsFrontmost() {
                continue
            }
            guard ConfigStore.featureEnabled(feature),
                  let shortcut = ConfigStore.shortcut(for: feature) else { continue }
            register(feature: feature, shortcut: shortcut, id: UInt32(index + 1))
        }

        registerCommandShortcuts()
    }

    func refreshContextScopedHotkeys() {
        installHandlerIfNeeded()
        if Self.finderIsFrontmost() {
            registerFeatureIfEnabled(.copyFinderPath)
            registerFeatureIfEnabled(.newFile)
        } else {
            unregister(feature: .copyFinderPath)
            unregister(feature: .newFile)
        }
    }

    func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        ids.removeAll()
        for (_, ref) in commandRefs {
            UnregisterEventHotKey(ref)
        }
        commandRefs.removeAll()
        commandIds.removeAll()
    }

    private func unregister(feature: FeatureID) {
        guard let ref = refs.removeValue(forKey: feature) else { return }
        UnregisterEventHotKey(ref)
        ids = ids.filter { $0.value != feature }
    }

    private func installHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event = event, let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                if let feature = manager.ids[hotKeyID.id] {
                    Logger.log("hotkey trigger feature=\(feature.rawValue)")
                    if Thread.isMainThread {
                        manager.onTrigger?(feature)
                    } else {
                        DispatchQueue.main.async {
                            manager.onTrigger?(feature)
                        }
                    }
                } else if let commandID = manager.commandIds[hotKeyID.id] {
                    Logger.log("hotkey trigger commandShortcut=\(commandID)")
                    if Thread.isMainThread {
                        manager.onCommandTrigger?(commandID)
                    } else {
                        DispatchQueue.main.async {
                            manager.onCommandTrigger?(commandID)
                        }
                    }
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        eventHandlerInstalled = true
    }

    private func register(feature: FeatureID, shortcut: Shortcut, id: UInt32) {
        unregister(feature: feature)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        Logger.log("hotkey register feature=\(feature.rawValue) label=\(shortcut.label) status=\(status)")
        if status == noErr, let ref = ref {
            refs[feature] = ref
            ids[id] = feature
        }
    }

    private func registerCommandShortcuts() {
        guard ConfigStore.featureEnabled(.commandShortcuts) else { return }
        for (index, item) in ConfigStore.commandShortcuts().enumerated() {
            let command = item.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty, let shortcut = item.shortcutValue else { continue }
            registerCommandShortcut(id: item.id, shortcut: shortcut, hotkeyID: UInt32(1000 + index))
        }
    }

    private func registerCommandShortcut(id: String, shortcut: Shortcut, hotkeyID: UInt32) {
        if let existing = commandRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(existing)
        }
        commandIds = commandIds.filter { $0.value != id }
        var ref: EventHotKeyRef?
        let eventID = EventHotKeyID(signature: signature, id: hotkeyID)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, eventID, GetApplicationEventTarget(), 0, &ref)
        Logger.log("hotkey register commandShortcut=\(id) label=\(shortcut.label) status=\(status)")
        if status == noErr, let ref = ref {
            commandRefs[id] = ref
            commandIds[hotkeyID] = id
        }
    }

    private func registerFeatureIfEnabled(_ feature: FeatureID) {
        guard ConfigStore.featureEnabled(feature),
              let shortcut = ConfigStore.shortcut(for: feature),
              let index = FeatureID.allCases.firstIndex(of: feature) else {
            unregister(feature: feature)
            return
        }
        register(feature: feature, shortcut: shortcut, id: UInt32(index + 1))
    }

    private static func finderIsFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

}
