import Foundation

enum NativeMessagingHost {
    static func runIfNeeded() -> Bool {
        let args = CommandLine.arguments.dropFirst()
        guard args.contains("--native-host") || args.contains(where: { $0.hasPrefix("chrome-extension://") }) else {
            return false
        }
        run()
        return true
    }

    private static func run() {
        do {
            guard let message = try readMessage() else { return }
            let response = try handle(message)
            try writeMessage(response)
        } catch {
            try? writeMessage(["ok": false, "error": error.localizedDescription])
        }
    }

    private static func handle(_ message: [String: Any]) throws -> [String: Any] {
        let type = message["type"] as? String ?? message["action"] as? String ?? ""
        let payload = message["payload"] as? [String: Any] ?? message
        Logger.log("runtime native-host event=command type=\(type)")

        switch type {
        case "ping":
            return ["ok": true, "payload": ["status": "ready"]]
        case "start_scrolling_capture":
            let processID = try ScrollingCaptureCommand.launchDetached()
            let started: [String: Any] = ["status": "started", "processId": processID]
            return ["ok": true, "payload": started]
        case "read_scrolling_capture_selection":
            guard let processID = payload["processId"] as? Int else {
                throw SimpleError("Invalid scrolling capture process")
            }
            guard let selection = try ScrollingCaptureProgressStore.readSelection(
                processID: Int32(processID)
            ) else {
                return ["ok": true, "payload": ["ready": false]]
            }
            let selected: [String: Any] = [
                "ready": true,
                "width": selection.width,
                "height": selection.height,
                "scale": selection.scale
            ]
            return ["ok": true, "payload": selected]
        case "update_scrolling_capture_progress":
            guard let processID = payload["processId"] as? Int,
                  let sequence = payload["sequence"] as? Int,
                  let measured = payload["measured"] as? Bool else {
                throw SimpleError("Invalid scrolling capture progress")
            }
            let advancePixels = payload["advancePixels"] as? Int
            try ScrollingCaptureProgressStore.write(
                processID: Int32(processID),
                sequence: sequence,
                measured: measured,
                advancePixels: advancePixels
            )
            return ["ok": true, "payload": ["status": "recorded"]]
        case "read_payload":
            guard let token = payload["token"] as? String else {
                throw SimpleError("Missing token")
            }
            let offset = payload["offset"] as? Int ?? 0
            let limit = payload["limit"] as? Int ?? 393216
            return ["ok": true, "payload": try PayloadStore.readChunk(token: token, offset: offset, limit: limit)]
        default:
            throw SimpleError("Unknown native message: \(type)")
        }
    }

    private static func readMessage() throws -> [String: Any]? {
        let lengthData = FileHandle.standardInput.readData(ofLength: 4)
        if lengthData.count == 0 { return nil }
        guard lengthData.count == 4 else { throw SimpleError("Invalid message length") }
        let length = Int(lengthData.enumerated().reduce(UInt32(0)) { partial, item in
            partial | (UInt32(item.element) << UInt32(item.offset * 8))
        })
        guard length > 0, length < 64 * 1024 * 1024 else {
            throw SimpleError("Message length out of range")
        }
        let data = FileHandle.standardInput.readData(ofLength: length)
        guard data.count == length,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimpleError("Invalid JSON message")
        }
        return json
    }

    private static func writeMessage(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(data.count).littleEndian
        let header = Data(bytes: &length, count: 4)
        FileHandle.standardOutput.write(header)
        FileHandle.standardOutput.write(data)
    }
}
