import Foundation

struct PayloadRecord {
    let token: String
    let fileURL: URL
    let filename: String
    let contentType: String
    let kind: String
    let expiresAt: Date
}

enum PayloadStore {
    static func store(data: Data, filename: String, contentType: String, kind: String) throws -> PayloadRecord {
        cleanupExpired()
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let payloadURL = AppPaths.payloadDirectory.appendingPathComponent("\(token).bin")
        let metadataURL = AppPaths.payloadDirectory.appendingPathComponent("\(token).json")
        let expires = Date().addingTimeInterval(3600)
        try data.write(to: payloadURL, options: .atomic)
        let metadata: [String: Any] = [
            "token": token,
            "filename": filename,
            "contentType": contentType,
            "kind": kind,
            "path": payloadURL.path,
            "expiresAt": expires.timeIntervalSince1970
        ]
        let metaData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metaData.write(to: metadataURL, options: .atomic)
        return PayloadRecord(token: token, fileURL: payloadURL, filename: filename, contentType: contentType, kind: kind, expiresAt: expires)
    }

    static func storeFile(_ url: URL, kind: String) throws -> PayloadRecord {
        let data = try Data(contentsOf: url)
        return try store(data: data, filename: url.lastPathComponent, contentType: contentType(for: url), kind: kind)
    }

    static func storeManifest(records: [PayloadRecord], filename: String = "image-optimizer-files.json") throws -> PayloadRecord {
        let files = records.map { record in
            [
                "token": record.token,
                "filename": record.filename,
                "contentType": record.contentType,
                "kind": record.kind
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["files": files], options: [.prettyPrinted, .sortedKeys])
        return try store(data: data, filename: filename, contentType: "application/json", kind: "image-optimizer-manifest")
    }

    static func metadata(token: String) throws -> [String: Any] {
        let metadataURL = AppPaths.payloadDirectory.appendingPathComponent("\(token).json")
        let data = try Data(contentsOf: metadataURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimpleError("Invalid payload metadata")
        }
        if let expires = json["expiresAt"] as? Double, Date(timeIntervalSince1970: expires) < Date() {
            throw SimpleError("Payload expired")
        }
        return json
    }

    static func readChunk(token: String, offset: Int, limit: Int) throws -> [String: Any] {
        let meta = try metadata(token: token)
        guard let path = meta["path"] as? String,
              let contentType = meta["contentType"] as? String,
              let filename = meta["filename"] as? String,
              let kind = meta["kind"] as? String else {
            throw SimpleError("Missing payload metadata")
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let safeOffset = max(0, min(offset, data.count))
        let safeLimit = max(1, min(limit, 393216))
        let end = min(data.count, safeOffset + safeLimit)
        let chunk = data.subdata(in: safeOffset..<end)
        return [
            "token": token,
            "filename": filename,
            "contentType": contentType,
            "kind": kind,
            "offset": safeOffset,
            "nextOffset": end,
            "total": data.count,
            "done": end >= data.count,
            "base64": chunk.base64EncodedString()
        ]
    }

    static func cleanupExpired() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: AppPaths.payloadDirectory, includingPropertiesForKeys: nil) else { return }
        let metadataFiles = files.filter { $0.pathExtension == "json" }
        for metadataURL in metadataFiles {
            guard let data = try? Data(contentsOf: metadataURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let expires = json["expiresAt"] as? Double else {
                continue
            }
            if Date(timeIntervalSince1970: expires) < Date() {
                if let path = json["path"] as? String {
                    try? FileManager.default.removeItem(atPath: path)
                }
                try? FileManager.default.removeItem(at: metadataURL)
            }
        }
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "avif": return "image/avif"
        default: return "application/octet-stream"
        }
    }
}
