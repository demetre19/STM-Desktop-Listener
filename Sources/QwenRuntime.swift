import CryptoKit
import Foundation

enum QwenRuntimeManager {
    private static let runtimeVersion = "mlx-audio-0.5.3-python-3.10.18"
    private static let bundledUVSHA256 = "c59d3ed8e54e863e49393227f30cb19ac894010e1d703f60cd67d1568bf852fe"

    static var runtimeRootURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("QwenRuntime", isDirectory: true)
    }

    static var pythonURL: URL {
        runtimeRootURL.appendingPathComponent("venv/bin/python")
    }

    private static var markerURL: URL {
        runtimeRootURL.appendingPathComponent("runtime.version")
    }

    private static var bundledResourcesURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("QwenRuntime", isDirectory: true)
    }

    static var isInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path),
              let marker = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return false
        }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines) == runtimeVersion
    }

    static func install(progress: @escaping @Sendable (QwenInstallationProgress) -> Void) async throws {
        if isInstalled {
            progress(QwenInstallationProgress(fraction: 0.20, message: "Qwen3-ASR local runtime is ready"))
            return
        }
        try await Task.detached(priority: .utility) {
            try installSynchronously(progress: progress)
        }.value
    }

    private static func installSynchronously(
        progress: @escaping @Sendable (QwenInstallationProgress) -> Void
    ) throws {
        guard let resourcesURL = bundledResourcesURL else {
            throw SimpleError("The bundled Qwen3-ASR installer is unavailable.")
        }
        let uvURL = resourcesURL.appendingPathComponent("uv")
        let requirementsURL = resourcesURL.appendingPathComponent("requirements.lock")
        guard FileManager.default.isExecutableFile(atPath: uvURL.path),
              FileManager.default.fileExists(atPath: requirementsURL.path) else {
            throw SimpleError("The bundled Qwen3-ASR installer is incomplete.")
        }
        guard try sha256(of: uvURL) == bundledUVSHA256 else {
            throw SimpleError("The bundled Qwen3-ASR installer failed integrity verification.")
        }

        QwenTranscriber.reset()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: runtimeRootURL.path) {
            try fileManager.removeItem(at: runtimeRootURL)
        }
        try fileManager.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)

        let cacheURL = runtimeRootURL.appendingPathComponent("cache", isDirectory: true)
        let pythonInstallURL = runtimeRootURL.appendingPathComponent("python", isDirectory: true)
        let environment = installerEnvironment(cacheURL: cacheURL, pythonInstallURL: pythonInstallURL)

        do {
            progress(QwenInstallationProgress(fraction: 0.02, message: "Installing private Python runtime for Qwen3-ASR…"))
            try run(
                executable: uvURL,
                arguments: ["python", "install", "3.10.18"],
                environment: environment
            )
            progress(QwenInstallationProgress(fraction: 0.07, message: "Private Python runtime installed"))

            progress(QwenInstallationProgress(fraction: 0.08, message: "Creating private Qwen3-ASR environment…"))
            try run(
                executable: uvURL,
                arguments: [
                    "venv",
                    "--python", "3.10.18",
                    "--python-preference", "only-managed",
                    runtimeRootURL.appendingPathComponent("venv", isDirectory: true).path,
                ],
                environment: environment
            )
            progress(QwenInstallationProgress(fraction: 0.10, message: "Private Qwen3-ASR environment created"))

            progress(QwenInstallationProgress(fraction: 0.11, message: "Installing verified Qwen3-ASR runtime packages…"))
            try run(
                executable: uvURL,
                arguments: [
                    "pip", "install",
                    "--python", pythonURL.path,
                    "--require-hashes",
                    "--requirement", requirementsURL.path,
                ],
                environment: environment
            )

            try run(
                executable: pythonURL,
                arguments: ["-I", "-c", "import mlx, mlx_audio"],
                environment: environment
            )
            progress(QwenInstallationProgress(fraction: 0.20, message: "Qwen3-ASR local runtime is ready"))
            try runtimeVersion.write(to: markerURL, atomically: true, encoding: .utf8)
            try? fileManager.removeItem(at: cacheURL)
        } catch {
            try? fileManager.removeItem(at: runtimeRootURL)
            throw error
        }
    }

    private static func installerEnvironment(cacheURL: URL, pythonInstallURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["UV_CACHE_DIR"] = cacheURL.path
        environment["UV_PYTHON_INSTALL_DIR"] = pythonInstallURL.path
        environment["UV_PYTHON_DOWNLOADS"] = "automatic"
        environment["UV_LINK_MODE"] = "copy"
        environment["UV_PYTHON_PREFERENCE"] = "only-managed"
        environment["UV_NO_CONFIG"] = "1"
        environment["UV_NO_PROGRESS"] = "1"
        return environment
    }

    private static func run(executable: URL, arguments: [String], environment: [String: String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SimpleError(detail.isEmpty ? "Qwen3-ASR runtime installation failed." : detail)
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum QwenTranscriber {
    static func preload(modelURL: URL) throws {
        try QwenRuntimeProcess.shared.preload(modelURL: modelURL)
    }

    static func preloadAsync(modelURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            try preload(modelURL: modelURL)
        }.value
    }

    static func transcribe(waveURL: URL, modelURL: URL) throws -> String {
        try QwenRuntimeProcess.shared.transcribe(waveURL: waveURL, modelURL: modelURL)
    }

    static func transcribeAsync(waveURL: URL, modelURL: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try transcribe(waveURL: waveURL, modelURL: modelURL)
        }.value
    }

    static func reset() {
        QwenRuntimeProcess.shared.stop()
    }
}

private final class QwenRuntimeProcess {
    static let shared = QwenRuntimeProcess()

    private let lock = NSLock()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var loadedModelPath: String?
    private var nextRequestID = 1

    private init() {}

    func preload(modelURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureStartedLocked(modelURL: modelURL)
    }

    func transcribe(waveURL: URL, modelURL: URL) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try ensureStartedLocked(modelURL: modelURL)
        return try requestTranscriptionLocked(waveURL: waveURL)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func ensureStartedLocked(modelURL: URL) throws {
        if let process, process.isRunning, loadedModelPath == modelURL.path {
            return
        }
        stopLocked()

        guard QwenRuntimeManager.isInstalled else {
            throw SimpleError("The Qwen3-ASR local runtime is not installed.")
        }
        guard QwenModelManager.isValidModel(at: modelURL) else {
            throw SimpleError("The Qwen3-ASR model is unavailable or incomplete.")
        }
        guard let helperURL = Bundle.main.resourceURL?
            .appendingPathComponent("QwenRuntime/qwen_helper.py") else {
            throw SimpleError("The Qwen3-ASR helper is unavailable.")
        }

        let child = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        child.executableURL = QwenRuntimeManager.pythonURL
        child.arguments = ["-I", helperURL.path, modelURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        child.environment = environment
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = FileHandle.nullDevice

        try child.run()
        process = child
        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        outputBuffer.removeAll(keepingCapacity: true)
        loadedModelPath = modelURL.path

        do {
            let response = try readResponseLocked()
            guard response["type"] as? String == "ready" else {
                let message = response["error"] as? String ?? "Qwen3-ASR failed to become ready."
                throw SimpleError(message)
            }
            Logger.log("qwen local runtime ready model=Qwen3-ASR-0.6B-8bit")
        } catch {
            stopLocked()
            throw error
        }
    }

    private func requestTranscriptionLocked(waveURL: URL) throws -> String {
        let requestID = nextRequestID
        nextRequestID += 1
        let request: [String: Any] = [
            "id": requestID,
            "op": "transcribe",
            "path": waveURL.path,
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let inputHandle else {
            throw SimpleError("The Qwen3-ASR helper is unavailable.")
        }
        try inputHandle.write(contentsOf: data + Data([0x0A]))
        let response = try readResponseLocked()
        guard response["id"] as? Int == requestID else {
            throw SimpleError("The Qwen3-ASR helper returned an invalid response.")
        }
        guard response["ok"] as? Bool == true else {
            throw SimpleError(response["error"] as? String ?? "Qwen3-ASR transcription failed.")
        }
        if let elapsed = response["elapsedMilliseconds"] as? Int {
            Logger.log("qwen local transcription elapsedMs=\(elapsed)")
        }
        guard let text = response["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SimpleError("Qwen3-ASR returned an empty transcript.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readResponseLocked() throws -> [String: Any] {
        while true {
            if let newline = outputBuffer.firstIndex(of: 0x0A) {
                let line = outputBuffer.prefix(upTo: newline)
                outputBuffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw SimpleError("The Qwen3-ASR helper returned malformed data.")
                }
                return object
            }
            guard outputBuffer.count < 4 * 1024 * 1024 else {
                throw SimpleError("The Qwen3-ASR helper response exceeded its safety limit.")
            }
            guard let outputHandle else {
                throw SimpleError("The Qwen3-ASR helper output is unavailable.")
            }
            let data = outputHandle.availableData
            guard !data.isEmpty else {
                throw SimpleError("The Qwen3-ASR helper exited unexpectedly.")
            }
            outputBuffer.append(data)
        }
    }

    private func stopLocked() {
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        loadedModelPath = nil
    }
}
