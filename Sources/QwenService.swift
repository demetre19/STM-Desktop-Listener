import CryptoKit
import Foundation

enum DictationTranscriptionEngine: String, CaseIterable {
    case worker
    case qwen

    var title: String {
        switch self {
        case .worker: return "Cloudflare Worker (preferred)"
        case .qwen: return "Qwen3-ASR 0.6B (local)"
        }
    }
}

struct DictationLocalConfiguration {
    static let engineKey = "dictation.transcriptionEngine"
    static let modelPathKey = "dictation.qwenModelPath"
    static let voiceCommandsKey = "dictation.voiceCommandsEnabled"

    let engine: DictationTranscriptionEngine
    let modelPath: String
    let voiceCommandsEnabled: Bool

    static func load() -> DictationLocalConfiguration {
        let storedEngine = ConfigStore.string(engineKey) ?? DictationTranscriptionEngine.worker.rawValue
        let engine = DictationTranscriptionEngine(rawValue: storedEngine) ?? .worker
        if storedEngine != engine.rawValue {
            try? ConfigStore.set(engine.rawValue, for: engineKey)
        }
        return DictationLocalConfiguration(
            engine: engine,
            modelPath: ConfigStore.string(modelPathKey) ?? "",
            voiceCommandsEnabled: ConfigStore.bool(voiceCommandsKey, default: false)
        )
    }

    func save() throws {
        try ConfigStore.set(engine.rawValue, for: Self.engineKey)
        try ConfigStore.set(modelPath, for: Self.modelPathKey)
        try ConfigStore.set(voiceCommandsEnabled, for: Self.voiceCommandsKey)
    }
}

enum QwenModelManager {
    private struct ModelFile {
        let name: String
        let size: Int64
        let sha256: String
    }

    static let modelDirectoryName = "qwen3-asr-0.6b-8bit"
    static let modelRepository = "mlx-community/Qwen3-ASR-0.6B-8bit"
    static let modelRevision = "89e96d92ba34aca20b3e29fb10cc284097d1219f"
    static let modelStorageRootKey = "dictation.qwenModelStorageRoot"

    private static let files = [
        ModelFile(
            name: "chat_template.json",
            size: 1_161,
            sha256: "75a8cfca24f00de72d796fbfed6858fc9614ef3dabd8696684cc3bc03a9c58ff"
        ),
        ModelFile(
            name: "config.json",
            size: 7_187,
            sha256: "5d104a945fed08728ab010f12bf3ce5ab4d0794bba276d81bff5bd83ae9d2be0"
        ),
        ModelFile(
            name: "generation_config.json",
            size: 142,
            sha256: "1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c"
        ),
        ModelFile(
            name: "merges.txt",
            size: 1_671_853,
            sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
        ),
        ModelFile(
            name: "model.safetensors",
            size: 1_006_229_426,
            sha256: "b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8"
        ),
        ModelFile(
            name: "model.safetensors.index.json",
            size: 71_815,
            sha256: "caa32ece76c395ba241533eb4aceb0efbc72488ef3d8d2fd3c677ce068dad57d"
        ),
        ModelFile(
            name: "preprocessor_config.json",
            size: 330,
            sha256: "45e120a4eda2c20c5d7f2ea9354e63536bf35e27aa573fb7cdf78017b378770d"
        ),
        ModelFile(
            name: "tokenizer_config.json",
            size: 12_487,
            sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"
        ),
        ModelFile(
            name: "vocab.json",
            size: 2_776_833,
            sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
        ),
    ]
    private static let totalDownloadBytes = files.reduce(Int64(0)) { $0 + $1.size }
    static var defaultStorageRootURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("Models", isDirectory: true)
    }

    static var storageRootURL: URL {
        guard let configuredPath = ConfigStore.string(modelStorageRootKey) else {
            return defaultStorageRootURL
        }
        return URL(fileURLWithPath: configuredPath, isDirectory: true).standardizedFileURL
    }

    static var managedModelURL: URL {
        storageRootURL.appendingPathComponent(modelDirectoryName, isDirectory: true)
    }

    static func setStorageRoot(_ rootURL: URL) throws {
        let selectedURL = rootURL.standardizedFileURL
        try FileManager.default.createDirectory(at: selectedURL, withIntermediateDirectories: true)
        let writeProbe = selectedURL.appendingPathComponent(".stm-qwen-write-\(UUID().uuidString)")
        do {
            try Data().write(to: writeProbe, options: .atomic)
            try FileManager.default.removeItem(at: writeProbe)
        } catch {
            try? FileManager.default.removeItem(at: writeProbe)
            throw SimpleError("STM Desktop Listener cannot write to the selected model folder.")
        }

        try ConfigStore.set(selectedURL.path, for: modelStorageRootKey)
        let candidateURL = selectedURL.appendingPathComponent(modelDirectoryName, isDirectory: true)
        try ConfigStore.set(isValidModel(at: candidateURL) ? candidateURL.path : "", for: DictationLocalConfiguration.modelPathKey)
        QwenTranscriber.reset()
    }

    static func isValidModel(at url: URL) -> Bool {
        files.allSatisfy { file in
            let fileURL = url.appendingPathComponent(file.name)
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                return false
            }
            return Int64(values.fileSize ?? -1) == file.size
        }
    }

    static func resolvedModelURL() -> URL? {
        let configuredPath = DictationLocalConfiguration.load().modelPath
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath, isDirectory: true)
            if isValidModel(at: configuredURL) {
                return configuredURL
            }
        }
        return isValidModel(at: managedModelURL) ? managedModelURL : nil
    }

    static func statusText() -> String {
        guard QwenRuntimeManager.isInstalled else {
            return "Qwen3-ASR local runtime is not installed"
        }
        guard let modelURL = resolvedModelURL() else {
            return "Qwen3-ASR model is not installed"
        }
        return "Ready — \(modelURL.lastPathComponent)"
    }

    static func useExistingModel(at modelURL: URL) throws {
        guard isValidModel(at: modelURL) else {
            throw SimpleError("The Qwen3-ASR model folder is incomplete.")
        }
        try ConfigStore.set(modelURL.path, for: DictationLocalConfiguration.modelPathKey)
        QwenTranscriber.reset()
    }

    static func install(
        progress: @escaping @Sendable (QwenInstallationProgress) -> Void = { _ in }
    ) async throws -> URL {
        progress(QwenInstallationProgress(fraction: 0, message: "Preparing Qwen3-ASR installation…"))
        try await QwenRuntimeManager.install(progress: progress)
        let modelURL = try await downloadModel(progress: progress)
        progress(QwenInstallationProgress(fraction: 0.97, message: "Loading Qwen3-ASR into memory…"))
        try await QwenTranscriber.preloadAsync(modelURL: modelURL)
        progress(QwenInstallationProgress(fraction: 1, message: "Qwen3-ASR local backup is ready"))
        return modelURL
    }

    private static func downloadModel(
        progress: @escaping @Sendable (QwenInstallationProgress) -> Void
    ) async throws -> URL {
        if let existingModelURL = resolvedModelURL() {
            progress(QwenInstallationProgress(fraction: 0.96, message: "Verified Qwen3-ASR model is ready"))
            return existingModelURL
        }

        let fileManager = FileManager.default
        let modelsURL = managedModelURL.deletingLastPathComponent()
        let workURL = modelsURL.appendingPathComponent(".qwen-download-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workURL) }

        var completedBytes: Int64 = 0
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let destinationURL = workURL.appendingPathComponent(file.name)
            let encodedName = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
            guard let url = URL(
                string: "https://huggingface.co/\(modelRepository)/resolve/\(modelRevision)/\(encodedName)?download=true"
            ) else {
                throw SimpleError("Qwen3-ASR download URL is invalid.")
            }

            let completedBeforeFile = completedBytes
            try await QwenFileDownloader.download(
                from: url,
                to: destinationURL,
                expectedBytes: file.size
            ) { bytesWritten in
                let downloaded = min(completedBeforeFile + bytesWritten, totalDownloadBytes)
                let fraction = 0.20 + 0.74 * Double(downloaded) / Double(totalDownloadBytes)
                progress(QwenInstallationProgress(
                    fraction: fraction,
                    message: "Downloading Qwen3-ASR \(index + 1)/\(files.count): \(file.name)"
                ))
            }

            let values = try destinationURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, Int64(values.fileSize ?? -1) == file.size else {
                throw SimpleError("Qwen3-ASR download size verification failed for \(file.name).")
            }
            progress(QwenInstallationProgress(
                fraction: 0.94,
                message: "Verifying Qwen3-ASR \(index + 1)/\(files.count): \(file.name)"
            ))
            guard try sha256(of: destinationURL) == file.sha256 else {
                throw SimpleError("Qwen3-ASR download integrity verification failed for \(file.name).")
            }
            completedBytes += file.size
        }

        guard isValidModel(at: workURL) else {
            throw SimpleError("The downloaded Qwen3-ASR model is incomplete.")
        }

        let attribution = """
        Qwen3-ASR-0.6B 8-bit MLX model
        Converted model: https://huggingface.co/\(modelRepository)
        Revision: \(modelRevision)
        Original model: https://huggingface.co/Qwen/Qwen3-ASR-0.6B
        Model license: Apache License 2.0
        Runtime: mlx-audio 0.5.3
        Runtime license: MIT
        """
        try attribution.write(
            to: workURL.appendingPathComponent("STM_MODEL_ATTRIBUTION.txt"),
            atomically: true,
            encoding: .utf8
        )

        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: managedModelURL.path) {
            try fileManager.removeItem(at: managedModelURL)
        }
        try fileManager.moveItem(at: workURL, to: managedModelURL)
        try ConfigStore.set(managedModelURL.path, for: DictationLocalConfiguration.modelPathKey)
        QwenTranscriber.reset()
        return managedModelURL
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

private final class QwenFileDownloader: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let progress: @Sendable (Int64) -> Void
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var downloadError: Error?
    private var movedDownload = false
    private var finished = false

    private init(
        destinationURL: URL,
        expectedBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) {
        self.destinationURL = destinationURL
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    static func download(
        from url: URL,
        to destinationURL: URL,
        expectedBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let transfer = QwenFileDownloader(
            destinationURL: destinationURL,
            expectedBytes: expectedBytes,
            progress: progress
        )
        try await transfer.start(url: url)
    }

    private func start(url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 60
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > expectedBytes {
            downloadTask.cancel()
            downloadError = SimpleError("Qwen3-ASR download exceeded its expected size.")
            return
        }
        progress(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  response.url?.scheme == "https" else {
                throw SimpleError("Qwen3-ASR download returned an invalid response.")
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            movedDownload = true
        } catch {
            downloadError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(downloadError ?? error))
        } else if let downloadError {
            finish(.failure(downloadError))
        } else if movedDownload {
            finish(.success(()))
        } else {
            finish(.failure(SimpleError("Qwen3-ASR download did not produce a file.")))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        session = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}

enum VoiceCommandIntentRouter {
    private static let prefixes = ["run command ", "command "]

    static func commandTitle(in transcript: String) -> String? {
        let normalized = normalize(transcript)
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            let title = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return nil
    }

    static func matchingCommand(for transcript: String, commands: [CommandShortcutDefinition]) -> CommandShortcutDefinition? {
        guard let requestedTitle = commandTitle(in: transcript) else { return nil }
        return commands.first { normalize($0.title) == requestedTitle }
    }

    static func isCommandPhrase(_ transcript: String) -> Bool {
        let normalized = normalize(transcript)
        return prefixes.contains { normalized.hasPrefix($0) }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
