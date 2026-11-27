import Foundation

enum LocalPunctuationService {
    private static func resolvedModelDirectory() -> URL? {
        guard let modelDirectory = Bundle.main.resourceURL?
            .appendingPathComponent("PunctuationModel", isDirectory: true),
              FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("model.int8.onnx").path),
              FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("bpe.vocab").path) else {
            return nil
        }
        return modelDirectory
    }

    private enum CandidateResult {
        case success(String)
        case failure(String)
    }

    private static func punctuationCandidate(
        for text: String,
        modelDirectory: URL
    ) -> CandidateResult {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let candidatePointer = modelDirectory.path.withCString { modelPath in
            text.withCString { inputText in
                STMAddPunctuation(modelPath, inputText, &errorPointer)
            }
        }
        defer {
            if let errorPointer {
                STMFreeString(errorPointer)
            }
        }

        guard let candidatePointer else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            return .failure(message)
        }
        defer { STMFreeString(candidatePointer) }
        return .success(String(cString: candidatePointer))
    }

    /// Loads the one-file-per-process sherpa model while the user is still speaking. The C
    /// bridge serializes access, so the later paste path normally finds the model already hot.
    static func warm() {
        DispatchQueue.global(qos: .utility).async {
            guard let modelDirectory = resolvedModelDirectory() else { return }
            _ = punctuationCandidate(for: "warmup", modelDirectory: modelDirectory)
        }
    }

    static func apply(to text: String, trace: PunctuationLearning.Trace? = nil) -> String {
        guard let modelDirectory = resolvedModelDirectory() else {
            Logger.log("local punctuation model unavailable; using guarded deterministic punctuation")
            return SpokenDictationFormatter.applyingAutomaticPunctuation(candidate: text, to: text, trace: trace)
        }

        let modelInput = SpokenDictationFormatter.normalizingForPunctuationModel(text)
        let inferenceInput = modelInput.isEmpty ? text : modelInput

        switch punctuationCandidate(for: inferenceInput, modelDirectory: modelDirectory) {
        case .success(let candidate):
            return SpokenDictationFormatter.applyingAutomaticPunctuation(candidate: candidate, to: text, trace: trace)
        case .failure(let message):
            Logger.log("local punctuation failed: \(message)")
            return SpokenDictationFormatter.applyingAutomaticPunctuation(candidate: text, to: text, trace: trace)
        }
    }
}
