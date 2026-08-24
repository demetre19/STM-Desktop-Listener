import Foundation

enum Logger {
    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: AppPaths.logURL.path),
           let handle = try? FileHandle(forWritingTo: AppPaths.logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: AppPaths.logURL)
        }
    }
}
