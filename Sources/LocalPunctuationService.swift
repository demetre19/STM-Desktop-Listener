import Foundation

enum LocalPunctuationService {
    static func apply(to text: String) -> String {
        let modelDirectory = Bundle.main.resourceURL?
            .appendingPathComponent("PunctuationModel", isDirectory: true)

        guard let modelDirectory,
              FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("model.int8.onnx").path),
              FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("bpe.vocab").path) else {
            Logger.log("local punctuation model unavailable; using guarded deterministic punctuation")
            return SpokenDictationFormatter.applyingAutomaticPunctuation(candidate: text, to: text)
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let candidatePointer = modelDirectory.path.withCString { modelPath in
            text.withCString { inputText in
                STMAddPunctuation(modelPath, inputText, &errorPointer)
            }
        }
        defer {
            if let errorPointer {
                STMParakeetFreeString(errorPointer)
            }
        }

        guard let candidatePointer else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            Logger.log("local punctuation failed: \(message)")
            return SpokenDictationFormatter.applyingAutomaticPunctuation(candidate: text, to: text)
        }
        defer { STMParakeetFreeString(candidatePointer) }

        let candidate = String(cString: candidatePointer)
        return SpokenDictationFormatter.applyingAutomaticPunctuation(candidate: candidate, to: text)
    }
}
