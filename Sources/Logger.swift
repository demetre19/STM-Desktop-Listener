import Foundation

enum Logger {
    private static let asyncLogQueue = DispatchQueue(label: "stm.logger", qos: .utility)

    /// Use for high-frequency diagnostics near latency-sensitive paths; file I/O happens off
    /// the caller's queue. Ordering with ordinary synchronous log lines is best-effort.
    static func logAsync(_ message: String) {
        asyncLogQueue.async { log(message) }
    }

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
