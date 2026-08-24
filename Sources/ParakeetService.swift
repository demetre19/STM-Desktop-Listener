import CryptoKit
import Foundation

enum DictationTranscriptionEngine: String, CaseIterable {
    case worker
    case parakeet

    var title: String {
        switch self {
        case .worker: return "Cloudflare Worker"
        case .parakeet: return "Parakeet TDT v3 (local)"
        }
    }
}

struct DictationLocalConfiguration {
    static let engineKey = "dictation.transcriptionEngine"
    static let modelPathKey = "dictation.parakeetModelPath"
    static let voiceCommandsKey = "dictation.voiceCommandsEnabled"

    let engine: DictationTranscriptionEngine
    let modelPath: String
    let voiceCommandsEnabled: Bool

    static func load() -> DictationLocalConfiguration {
        DictationLocalConfiguration(
            engine: DictationTranscriptionEngine(rawValue: ConfigStore.string(engineKey) ?? "worker") ?? .worker,
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

enum ParakeetModelManager {
    static let modelDirectoryName = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
    static let archiveURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2")!
    static let archiveSHA256 = "5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf"
    static let requiredFiles = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]

    static var managedModelURL: URL {
        AppPaths.applicationSupport
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(modelDirectoryName, isDirectory: true)
    }

    static var orcaModelURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/orca/speech-models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3-int8", isDirectory: true)
    }

    static func isValidModel(at url: URL) -> Bool {
        requiredFiles.allSatisfy { filename in
            var isDirectory: ObjCBool = false
            let path = url.appendingPathComponent(filename).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
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
        if let modelURL = resolvedModelURL() {
            if modelURL.standardizedFileURL == orcaModelURL.standardizedFileURL {
                return "Ready — reusing Orca's downloaded model"
            }
            return "Ready — \(modelURL.lastPathComponent)"
        }
        if isValidModel(at: orcaModelURL) {
            return "Orca's model is available to reuse"
        }
        return "Parakeet model is not installed"
    }

    static func selectOrcaModel() throws -> URL {
        guard isValidModel(at: orcaModelURL) else {
            throw SimpleError("Orca's Parakeet model was not found on this Mac.")
        }
        try ConfigStore.set(orcaModelURL.path, for: DictationLocalConfiguration.modelPathKey)
        STMParakeetReset()
        return orcaModelURL
    }

    static func download() async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: archiveURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SimpleError("Parakeet download failed with an invalid server response.")
        }

        let fileManager = FileManager.default
        let workURL = AppPaths.applicationSupport
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveFileURL = workURL.appendingPathComponent("parakeet.tar.bz2")
        let extractionURL = workURL.appendingPathComponent("extract", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workURL) }

        try fileManager.moveItem(at: temporaryURL, to: archiveFileURL)
        let digest = try sha256(of: archiveFileURL)
        guard digest == archiveSHA256 else {
            throw SimpleError("Parakeet download failed integrity verification.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archiveFileURL.path, "-C", extractionURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SimpleError(detail.isEmpty ? "Parakeet archive extraction failed." : detail)
        }

        let extractedModelURL = extractionURL.appendingPathComponent(modelDirectoryName, isDirectory: true)
        guard isValidModel(at: extractedModelURL) else {
            throw SimpleError("The downloaded Parakeet archive is incomplete.")
        }

        let modelsURL = managedModelURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: managedModelURL.path) {
            try fileManager.removeItem(at: managedModelURL)
        }
        try fileManager.moveItem(at: extractedModelURL, to: managedModelURL)
        let attribution = """
        NVIDIA Parakeet TDT 0.6B v3 model
        Source: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
        License: Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/)
        Converted for sherpa-onnx by k2-fsa.
        """
        try attribution.write(
            to: managedModelURL.appendingPathComponent("STM_MODEL_ATTRIBUTION.txt"),
            atomically: true,
            encoding: .utf8
        )
        try ConfigStore.set(managedModelURL.path, for: DictationLocalConfiguration.modelPathKey)
        STMParakeetReset()
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

enum ParakeetTranscriber {
    static func transcribe(waveURL: URL, modelURL: URL) throws -> String {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let textPointer = modelURL.path.withCString { modelPath in
            waveURL.path.withCString { wavePath in
                STMParakeetTranscribe(modelPath, wavePath, &errorPointer)
            }
        }
        defer {
            if let errorPointer = errorPointer {
                STMParakeetFreeString(errorPointer)
            }
        }
        guard let textPointer = textPointer else {
            let message = errorPointer.map { String(cString: $0) } ?? "Parakeet transcription failed."
            throw SimpleError(message)
        }
        defer { STMParakeetFreeString(textPointer) }
        return String(cString: textPointer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func transcribeAsync(waveURL: URL, modelURL: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try transcribe(waveURL: waveURL, modelURL: modelURL)
        }.value
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
