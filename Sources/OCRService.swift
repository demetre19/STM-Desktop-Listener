import Cocoa
import CoreImage
import Vision

final class OCRService {
    private let stateQueue = DispatchQueue(label: "com.seotimemachines.stm-desktop-listener.ocr.state")
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])
    private var cachedConfiguration: OCRPreparedConfiguration?

    func recognizeText(in image: CGImage) throws -> String {
        try recognizeText(in: image, logReason: "user")
    }

    private func recognizeText(in image: CGImage, logReason: String) throws -> String {
        let totalStart = Date()
        let configuration = preparedConfiguration()
        let preprocessStart = Date()
        let preparedImage = preprocess(image, configuration: configuration)
        let preprocessMs = Int(Date().timeIntervalSince(preprocessStart) * 1000)
        var fragments: [RecognizedFragment] = []
        var requestError: Error?

        let visionStart = Date()
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                requestError = error
                return
            }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            fragments = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedFragment(
                    text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: candidate.confidence,
                    box: observation.boundingBox
                )
            }.filter { !$0.text.isEmpty }
        }
        request.recognitionLevel = configuration.recognitionLevel
        request.usesLanguageCorrection = true
        request.recognitionLanguages = configuration.languages
        if !configuration.customWords.isEmpty {
            request.customWords = configuration.customWords
        }

        let handler = VNImageRequestHandler(cgImage: preparedImage, options: [:])
        try handler.perform([request])
        let visionMs = Int(Date().timeIntervalSince(visionStart) * 1000)
        if let requestError = requestError {
            throw requestError
        }

        let confident = fragments.filter { $0.confidence >= configuration.minimumConfidence }
        let usable = confident.isEmpty ? fragments : confident
        let result = Self.orderedText(from: usable).trimmingCharacters(in: .whitespacesAndNewlines)
        let totalMs = Int(Date().timeIntervalSince(totalStart) * 1000)
        Logger.log("ocr recognize reason=\(logReason) totalMs=\(totalMs) preprocessMs=\(preprocessMs) visionMs=\(visionMs) level=\(configuration.recognitionLevelLabel) input=\(image.width)x\(image.height) prepared=\(preparedImage.width)x\(preparedImage.height) fragments=\(fragments.count) outputChars=\(result.count)")
        return result
    }

    private func preparedConfiguration() -> OCRPreparedConfiguration {
        if let cached = stateQueue.sync(execute: { cachedConfiguration }) {
            return cached
        }

        let configuration = OCRConfiguration.load()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = configuration.recognitionLevel
        let languages = configuration.languages(for: request)
        let prepared = OCRPreparedConfiguration(
            languages: languages,
            customWords: configuration.customWords,
            minimumConfidence: configuration.minimumConfidence,
            recognitionLevel: configuration.recognitionLevel,
            recognitionLevelLabel: configuration.recognitionLevelLabel,
            preprocessingMode: configuration.preprocessingMode
        )
        stateQueue.sync {
            cachedConfiguration = prepared
        }
        return prepared
    }

    private func preprocess(_ image: CGImage, configuration: OCRPreparedConfiguration) -> CGImage {
        guard configuration.shouldPreprocess(image) else {
            return image
        }

        let minSide = min(image.width, image.height)
        let scale: CGFloat
        if minSide < 180 {
            scale = min(3.0, max(1.0, 720.0 / CGFloat(max(1, minSide))))
        } else {
            scale = 1.0
        }

        var ciImage = CIImage(cgImage: image)
        if scale > 1.01, let filter = CIFilter(name: "CILanczosScaleTransform") {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(scale, forKey: kCIInputScaleKey)
            filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            if let output = filter.outputImage {
                ciImage = output
            }
        }

        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
            filter.setValue(1.08, forKey: kCIInputContrastKey)
            filter.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let output = filter.outputImage {
                ciImage = output
            }
        }

        let rect = ciImage.extent.integral
        return ciContext.createCGImage(ciImage, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) ?? image
    }

    private static func orderedText(from fragments: [RecognizedFragment]) -> String {
        let sorted = fragments.sorted { left, right in
            let yDelta = abs(left.box.midY - right.box.midY)
            let threshold = max(left.box.height, right.box.height) * 0.55
            if yDelta > threshold {
                return left.box.midY > right.box.midY
            }
            return left.box.minX < right.box.minX
        }

        var lines: [[RecognizedFragment]] = []
        for fragment in sorted {
            if let index = lines.firstIndex(where: { line in
                guard let first = line.first else { return false }
                let yDelta = abs(first.box.midY - fragment.box.midY)
                let threshold = max(first.box.height, fragment.box.height) * 0.55
                return yDelta <= threshold
            }) {
                lines[index].append(fragment)
            } else {
                lines.append([fragment])
            }
        }

        return lines.map { line in
            line.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: " ")
        }.joined(separator: "\n")
    }

}

private struct RecognizedFragment {
    let text: String
    let confidence: VNConfidence
    let box: CGRect
}

private struct OCRConfiguration {
    let requestedLanguages: [String]
    let customWords: [String]
    let minimumConfidence: VNConfidence
    let recognitionLevel: VNRequestTextRecognitionLevel
    let recognitionLevelLabel: String
    let preprocessingMode: String

    static func load() -> OCRConfiguration {
        let levelLabel = (ConfigStore.string("ocr.recognitionLevel") ?? "accurate").lowercased()
        return OCRConfiguration(
            requestedLanguages: ConfigStore.stringArray("ocr.recognitionLanguages"),
            customWords: ConfigStore.stringArray("ocr.customWords"),
            minimumConfidence: VNConfidence(ConfigStore.double("ocr.minimumConfidence", default: 0.18)),
            recognitionLevel: levelLabel == "fast" ? .fast : .accurate,
            recognitionLevelLabel: levelLabel == "fast" ? "fast" : "accurate",
            preprocessingMode: (ConfigStore.string("ocr.preprocessing") ?? "auto").lowercased()
        )
    }

    func languages(for request: VNRecognizeTextRequest) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        guard !supported.isEmpty else {
            return requestedLanguages.isEmpty ? ["en-US"] : requestedLanguages
        }

        if !requestedLanguages.isEmpty {
            let filtered = requestedLanguages.filter { language in
                supported.contains(language) || supported.contains(languageBase(language))
            }
            if !filtered.isEmpty {
                Logger.log("ocr languages configured=\(filtered.joined(separator: ","))")
                return filtered
            }
        }

        let preferred = Locale.preferredLanguages.flatMap { language in
            [language, languageBase(language)]
        }
        let common = ["en-US", "en-GB", "en", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]
        var chosen: [String] = []
        for language in preferred + common {
            let candidate = supported.contains(language) ? language : languageBase(language)
            if supported.contains(candidate), !chosen.contains(candidate) {
                chosen.append(candidate)
            }
            if chosen.count >= 4 {
                break
            }
        }
        let result = chosen.isEmpty ? [supported[0]] : chosen
        Logger.log("ocr languages default=\(result.joined(separator: ","))")
        return result
    }

    private func languageBase(_ language: String) -> String {
        language.components(separatedBy: "-").first ?? language
    }
}

private struct OCRPreparedConfiguration {
    let languages: [String]
    let customWords: [String]
    let minimumConfidence: VNConfidence
    let recognitionLevel: VNRequestTextRecognitionLevel
    let recognitionLevelLabel: String
    let preprocessingMode: String

    func shouldPreprocess(_ image: CGImage) -> Bool {
        switch preprocessingMode {
        case "off", "false", "none":
            return false
        case "on", "true", "always":
            return true
        default:
            return min(image.width, image.height) < 180
        }
    }
}
