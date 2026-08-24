import Cocoa
import AVFoundation

enum DictationState {
    case idle
    case recording(elapsed: TimeInterval, limit: TimeInterval)
    case processing(currentChunk: Int, totalChunks: Int)
}

final class DictationController {
    private struct AudioChunk {
        let index: Int
        let url: URL
        let deleteAfterUse: Bool
        let retryDepth: Int
    }

    private enum TranscriptionRequestError: LocalizedError {
        case workerResourceLimit(String)
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .workerResourceLimit(let message), .requestFailed(let message):
                return message
            }
        }
    }

    private static let defaultFirstChunkSeconds: TimeInterval = 60
    private static let defaultSubsequentChunkSeconds: TimeInterval = 20
    private static let defaultChunkUploadConcurrency = 2
    private static let maxChunkUploadConcurrency = 4
    private static let uploadSampleRate = 16_000.0
    private static let uploadChannelCount: AVAudioChannelCount = 1
    private static let maxResourceLimitRetryDepth = 3
    private static let maxRecordingSeconds: TimeInterval = 10 * 60
    private static let productionWorkerURL = "https://share.seo-time-machines.workers.dev"

    private var audioEngine: AVAudioEngine?
    private var recordingStartedAt: Date?
    private var recordingTimer: Timer?
    private var chunkRotationTimer: Timer?
    private let audioLock = NSLock()
    private var currentChunkWriter: AVAudioFile?
    private var currentChunkURL: URL?
    private var currentChunkFrameCount: AVAudioFramePosition = 0
    private var currentChunkIndex = 0

    private var pendingChunks: [AudioChunk] = []
    private var partialTranscripts: [Int: String] = [:]
    private var completedChunkCount = 0
    private var totalChunkCount = 0
    private var finishRequested = false
    private var activeChunkTranscriptionCount = 0
    private var transcriptionFailure: Error?
    private var transcriptionTasks: [Int: Task<Void, Never>] = [:]
    private var transcriptionGeneration = 0

    private var isBusy = false
    private var currentModel = TranscriptionModel.load()
    private let clipboard: ClipboardService
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()
    var onStateChange: ((DictationState) -> Void)?
    var onError: ((String, String) -> Void)?
    var onNotice: ((String, String) -> Void)?
    var onAudioLevel: ((CGFloat) -> Void)?
    var onVoiceCommand: ((String) -> Bool)?

    init(clipboard: ClipboardService) {
        self.clipboard = clipboard
    }

    func toggle() {
        if audioEngine != nil {
            stopAndTranscribe()
        } else if isBusy {
            cancelTranscription()
        } else {
            startRecording()
        }
    }

    func cancel() {
        if audioEngine != nil {
            discardRecording()
        } else {
            cancelTranscription()
        }
    }

    func setModel(_ model: TranscriptionModel) {
        currentModel = model
        try? ConfigStore.set(model.id, for: "transcriptionModel")
        Logger.log("dictation model selected id=\(model.id) label=\(model.label)")
    }

    func importCredentials(from url: URL) throws -> Bool {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let importedWorkerUrl = jsonString(json, keys: ["workerUrl", "workerURL", "worker_url", "cloudShareWorkerUrl"])
        let importedAuthToken = jsonString(json, keys: ["authToken", "auth_token", "transcriptionAuthToken", "jitsiTranscribeAuthToken"])
        let importedCloudflareAccountID = jsonString(json, keys: ["cloudflareAccountId", "cloudflareAccountID", "cloudflare_account_id"])
        let importedCloudflareAPIToken = jsonString(json, keys: ["cloudflareApiToken", "cloudflareAPIToken", "cloudflare_api_token"])
        let workerUrl = importedWorkerUrl?.isEmpty == false ? importedWorkerUrl : ConfigStore.string("workerUrl")
        let authToken = importedAuthToken?.isEmpty == false ? importedAuthToken : ConfigStore.string("authToken")
        guard let workerUrl = workerUrl,
              let authToken = authToken,
              !workerUrl.isEmpty,
              !authToken.isEmpty else {
            throw SimpleError("JSON must contain workerUrl and authToken, unless they were already imported before.")
        }
        let normalizedWorkerURL = workerUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedWorkerURL == Self.productionWorkerURL else {
            throw SimpleError("workerUrl must remain \(Self.productionWorkerURL).")
        }
        try ConfigStore.set(Self.productionWorkerURL, for: "workerUrl")
        try ConfigStore.set(authToken, for: "authToken")
        if let importedCloudflareAccountID = importedCloudflareAccountID {
            try ConfigStore.set(importedCloudflareAccountID, for: "cloudflareAccountId")
        }
        if let importedCloudflareAPIToken = importedCloudflareAPIToken {
            try ConfigStore.set(importedCloudflareAPIToken, for: "cloudflareApiToken")
        }
        return false
    }

    private func jsonString(_ json: [String: Any]?, keys: [String]) -> String? {
        for key in keys {
            guard let value = json?[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private func startRecording() {
        guard !isBusy else { return }
        let localConfiguration = DictationLocalConfiguration.load()
        if localConfiguration.engine == .worker {
            guard hasCredentials() else {
                onError?("Missing credentials", "Import your Worker URL and auth token first.")
                return
            }
        } else {
            guard ParakeetModelManager.resolvedModelURL() != nil else {
                onError?("Parakeet model missing", "Download Parakeet or select Orca's existing model in Voice AI settings.")
                return
            }
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            PermissionCenter.requestMicrophone { self.startRecording() }
            return
        }
        guard status == .authorized else {
            onError?("Microphone denied", "Enable microphone access in System Settings.")
            return
        }

        resetTranscriptionState()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("Recording failed", "No microphone input format is available.")
            return
        }

        do {
            try openNextChunk(format: format)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.writeAudioBuffer(buffer)
            }
            try engine.start()
            audioEngine = engine
            recordingStartedAt = Date()
            startRecordingTimers()
            emitRecordingState()
            Logger.log("dictation recording started liveChunks=true sampleRate=\(Int(format.sampleRate)) channels=\(format.channelCount)")
        } catch {
            input.removeTap(onBus: 0)
            audioLock.lock()
            let chunk = closeCurrentChunkLocked()
            audioLock.unlock()
            if let chunk = chunk {
                try? FileManager.default.removeItem(at: chunk.url)
            }
            onError?("Recording failed", error.localizedDescription)
        }
    }

    private func stopAndTranscribe() {
        guard let engine = audioEngine else { return }
        stopRecordingTimers()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        recordingStartedAt = nil

        audioLock.lock()
        let finalChunk = closeCurrentChunkLocked()
        audioLock.unlock()
        if let finalChunk = finalChunk {
            enqueueChunk(finalChunk)
        }

        finishRequested = true
        isBusy = true
        onStateChange?(.processing(currentChunk: completedChunkCount, totalChunks: max(totalChunkCount, currentChunkIndex)))
        Logger.log("dictation recording stopped chunks=\(totalChunkCount)")
        startNextChunkIfNeeded()
        finishIfReady()
    }

    private func discardRecording() {
        guard let engine = audioEngine else { return }
        stopRecordingTimers()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        recordingStartedAt = nil
        audioLock.lock()
        let chunk = closeCurrentChunkLocked()
        audioLock.unlock()
        if let chunk = chunk {
            try? FileManager.default.removeItem(at: chunk.url)
        }
        resetTranscriptionState()
        onStateChange?(.idle)
        Logger.log("dictation recording discarded")
    }

    private func cancelTranscription() {
        guard isBusy || activeChunkTranscriptionCount > 0 || !pendingChunks.isEmpty else { return }
        transcriptionGeneration += 1
        transcriptionTasks.values.forEach { $0.cancel() }
        transcriptionTasks.removeAll()
        for chunk in pendingChunks where chunk.deleteAfterUse {
            try? FileManager.default.removeItem(at: chunk.url)
        }
        pendingChunks.removeAll()
        partialTranscripts.removeAll()
        completedChunkCount = 0
        totalChunkCount = 0
        finishRequested = false
        activeChunkTranscriptionCount = 0
        transcriptionFailure = nil
        isBusy = false
        onStateChange?(.idle)
        Logger.log("dictation transcription cancel requested")
    }

    private func resetTranscriptionState() {
        transcriptionGeneration += 1
        transcriptionTasks.values.forEach { $0.cancel() }
        transcriptionTasks.removeAll()
        pendingChunks.removeAll()
        partialTranscripts.removeAll()
        completedChunkCount = 0
        totalChunkCount = 0
        finishRequested = false
        activeChunkTranscriptionCount = 0
        transcriptionFailure = nil
        currentChunkIndex = 0
        currentChunkFrameCount = 0
        currentChunkURL = nil
        currentChunkWriter = nil
        isBusy = false
    }

    private func startRecordingTimers() {
        stopRecordingTimers()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingTimerFired()
        }
        if let recordingTimer = recordingTimer {
            RunLoop.main.add(recordingTimer, forMode: .common)
        }
        scheduleChunkRotationTimer(after: Self.firstChunkSeconds())
    }

    private func scheduleChunkRotationTimer(after interval: TimeInterval) {
        chunkRotationTimer?.invalidate()
        chunkRotationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.rotateRecordingChunk()
        }
        if let chunkRotationTimer = chunkRotationTimer {
            RunLoop.main.add(chunkRotationTimer, forMode: .common)
        }
    }

    private func stopRecordingTimers() {
        recordingTimer?.invalidate()
        chunkRotationTimer?.invalidate()
        recordingTimer = nil
        chunkRotationTimer = nil
    }

    private func recordingTimerFired() {
        emitRecordingState()
        guard let startedAt = recordingStartedAt,
              Date().timeIntervalSince(startedAt) >= Self.maxRecordingSeconds else {
            return
        }
        onNotice?("Dictation limit reached", "Recording stopped at \(Self.formatDuration(Self.maxRecordingSeconds)). The app will finish the background transcripts and paste the result.")
        stopAndTranscribe()
    }

    private func emitRecordingState() {
        let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        onStateChange?(.recording(elapsed: min(elapsed, Self.maxRecordingSeconds), limit: Self.maxRecordingSeconds))
    }

    private func writeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        if let samples = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            var sampleCount = 0
            for index in stride(from: 0, to: frameCount, by: 4) {
                let sample = samples[index]
                sum += sample * sample
                sampleCount += 1
            }
            if sampleCount > 0 {
                let rms = sqrt(sum / Float(sampleCount))
                let decibels = 20 * log10(max(rms, 0.000_001))
                let normalizedLevel = CGFloat(min(max((decibels + 52) / 44, 0), 1))
                let level = sqrt(normalizedLevel)
                DispatchQueue.main.async { [weak self] in
                    self?.onAudioLevel?(level)
                }
            }
        }

        audioLock.lock()
        defer { audioLock.unlock() }
        guard let writer = currentChunkWriter else { return }
        do {
            try writer.write(from: buffer)
            currentChunkFrameCount += AVAudioFramePosition(buffer.frameLength)
        } catch {
            Logger.log("dictation audio write failed \(error.localizedDescription)")
        }
    }

    private func rotateRecordingChunk() {
        guard audioEngine != nil else { return }
        audioLock.lock()
        let completed = closeCurrentChunkLocked()
        do {
            let format = audioEngine?.inputNode.outputFormat(forBus: 0)
            if let format = format {
                try openNextChunkLocked(format: format)
            }
        } catch {
            transcriptionFailure = error
            stopRecordingTimers()
        }
        audioLock.unlock()

        if let completed = completed {
            enqueueChunk(completed)
        }
        if transcriptionFailure == nil, audioEngine != nil {
            scheduleChunkRotationTimer(after: Self.subsequentChunkSeconds())
        }
        startNextChunkIfNeeded()
    }

    private func openNextChunk(format: AVAudioFormat) throws {
        audioLock.lock()
        defer { audioLock.unlock() }
        try openNextChunkLocked(format: format)
    }

    private func openNextChunkLocked(format: AVAudioFormat) throws {
        currentChunkIndex += 1
        currentChunkFrameCount = 0
        let chunkURL = FileManager.default.temporaryDirectory.appendingPathComponent("stm-desktop-listener-\(UUID().uuidString)-live-\(currentChunkIndex).wav")
        currentChunkWriter = try AVAudioFile(forWriting: chunkURL, settings: format.settings)
        currentChunkURL = chunkURL
    }

    private func closeCurrentChunkLocked() -> AudioChunk? {
        guard let url = currentChunkURL else { return nil }
        let index = currentChunkIndex
        let frameCount = currentChunkFrameCount
        currentChunkWriter = nil
        currentChunkURL = nil
        currentChunkFrameCount = 0
        guard frameCount > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return AudioChunk(index: index, url: url, deleteAfterUse: true, retryDepth: 0)
    }

    private func enqueueChunk(_ chunk: AudioChunk) {
        pendingChunks.append(chunk)
        totalChunkCount = max(totalChunkCount, chunk.index)
        Logger.log("dictation chunk queued index=\(chunk.index) pending=\(pendingChunks.count)")
        startNextChunkIfNeeded()
    }

    private func startNextChunkIfNeeded() {
        guard transcriptionFailure == nil else {
            finishIfReady()
            return
        }

        let maxConcurrent = Self.maxConcurrentChunkTranscriptions()
        while activeChunkTranscriptionCount < maxConcurrent, !pendingChunks.isEmpty {
            startChunkTranscription(pendingChunks.removeFirst())
        }

        if pendingChunks.isEmpty {
            finishIfReady()
        }
    }

    private func startChunkTranscription(_ chunk: AudioChunk) {
        let generation = transcriptionGeneration
        activeChunkTranscriptionCount += 1
        if isBusy {
            emitProcessingState()
        }

        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                let text = try await self.transcribeChunk(chunk)
                if chunk.deleteAfterUse {
                    try? FileManager.default.removeItem(at: chunk.url)
                }
                await MainActor.run {
                    guard self.transcriptionGeneration == generation else { return }
                    self.transcriptionTasks[chunk.index] = nil
                    self.partialTranscripts[chunk.index] = text
                    self.completedChunkCount += 1
                    self.activeChunkTranscriptionCount = max(0, self.activeChunkTranscriptionCount - 1)
                    Logger.log("dictation chunk complete index=\(chunk.index) characters=\(text.count)")
                    self.emitProcessingState()
                    self.startNextChunkIfNeeded()
                }
            } catch {
                if chunk.deleteAfterUse {
                    try? FileManager.default.removeItem(at: chunk.url)
                }
                await MainActor.run {
                    guard self.transcriptionGeneration == generation else { return }
                    self.transcriptionTasks[chunk.index] = nil
                    self.activeChunkTranscriptionCount = max(0, self.activeChunkTranscriptionCount - 1)
                    if self.transcriptionFailure == nil {
                        self.transcriptionFailure = error
                    }
                    for (index, task) in self.transcriptionTasks where index != chunk.index {
                        task.cancel()
                    }
                    if self.audioEngine != nil {
                        self.stopAndTranscribe()
                    } else {
                        self.finishIfReady()
                    }
                }
            }
        }
        transcriptionTasks[chunk.index] = task
    }

    private func finishIfReady() {
        guard finishRequested, activeChunkTranscriptionCount == 0 else { return }

        if let transcriptionFailure = transcriptionFailure {
            for chunk in pendingChunks where chunk.deleteAfterUse {
                try? FileManager.default.removeItem(at: chunk.url)
            }
            pendingChunks.removeAll()
            transcriptionTasks.removeAll()
            isBusy = false
            onStateChange?(.idle)
            self.transcriptionFailure = nil
            finishRequested = false
            onError?("Transcription failed", transcriptionFailure.localizedDescription)
            return
        }

        guard pendingChunks.isEmpty else { return }

        transcriptionTasks.removeAll()

        let text = (1...max(totalChunkCount, currentChunkIndex))
            .compactMap { partialTranscripts[$0] }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            partialTranscripts.removeAll()
            finishRequested = false
            isBusy = false
            onStateChange?(.idle)
            onError?("Transcription failed", "Empty transcript")
            return
        }

        partialTranscripts.removeAll()
        finishRequested = false
        if onVoiceCommand?(text) == true {
            isBusy = false
            onStateChange?(.idle)
            Logger.log("dictation completed as matched voice command")
            return
        }
        let formattedText = SpokenDictationFormatter.apply(to: text)
        let punctuatedText = LocalPunctuationService.apply(to: formattedText)
        completeDictation(with: punctuatedText, polished: false)
    }



    private func completeDictation(with text: String, polished: Bool) {
        isBusy = false
        onStateChange?(.idle)
        clipboard.copyText(text)
        clipboard.pasteIfAllowed(force: true)
        Logger.log("dictation complete chunks=\(completedChunkCount) characters=\(text.count) polished=\(polished)")
    }

    private func transcribeChunk(_ chunk: AudioChunk) async throws -> String {
        let uploadChunk = try normalizedChunkForUpload(chunk)
        defer {
            if uploadChunk.url != chunk.url, uploadChunk.deleteAfterUse {
                try? FileManager.default.removeItem(at: uploadChunk.url)
            }
        }

        if DictationLocalConfiguration.load().engine == .parakeet {
            guard let modelURL = ParakeetModelManager.resolvedModelURL() else {
                throw SimpleError("The configured Parakeet model is unavailable.")
            }
            return try await ParakeetTranscriber.transcribeAsync(waveURL: uploadChunk.url, modelURL: modelURL)
        }

        do {
            return try await transcribe(url: uploadChunk.url, allowEmpty: true)
        } catch TranscriptionRequestError.workerResourceLimit where uploadChunk.retryDepth < Self.maxResourceLimitRetryDepth {
            let splitChunks = try splitChunk(uploadChunk)
            guard splitChunks.count > 1 else {
                throw TranscriptionRequestError.workerResourceLimit(Self.resourceLimitFailureMessage())
            }
            defer {
                for splitChunk in splitChunks where splitChunk.deleteAfterUse {
                    try? FileManager.default.removeItem(at: splitChunk.url)
                }
            }
            Logger.log("dictation chunk resource-limit retry index=\(uploadChunk.index) depth=\(uploadChunk.retryDepth + 1) parts=\(splitChunks.count)")
            var texts: [String] = []
            for splitChunk in splitChunks {
                try Task.checkCancellation()
                let text = try await transcribeChunk(splitChunk)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    texts.append(text)
                }
            }
            return texts.joined(separator: " ")
        }
    }

    private func normalizedChunkForUpload(_ chunk: AudioChunk) throws -> AudioChunk {
        let inputFile = try AVAudioFile(forReading: chunk.url)
        if Self.isUploadAudioFormat(inputFile.fileFormat) {
            return chunk
        }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("stm-desktop-listener-\(UUID().uuidString)-upload-\(chunk.index).wav")
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: Self.uploadAudioSettings())
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFile.processingFormat) else {
            throw SimpleError("Could not create audio upload converter")
        }
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: 32768) else {
            throw SimpleError("Could not allocate audio upload buffer")
        }

        while inputFile.framePosition < inputFile.length {
            let remainingFrames = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
            try inputFile.read(into: inputBuffer, frameCount: min(inputBuffer.frameCapacity, remainingFrames))
            if inputBuffer.frameLength == 0 { break }
            try convertAudioBuffer(inputBuffer, converter: converter, outputFile: outputFile)
        }

        Logger.log("dictation chunk normalized index=\(chunk.index) inputBytes=\(Self.fileByteCount(chunk.url)) outputBytes=\(Self.fileByteCount(outputURL))")
        return AudioChunk(index: chunk.index, url: outputURL, deleteAfterUse: true, retryDepth: chunk.retryDepth)
    }

    private func convertAudioBuffer(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFile: AVAudioFile) throws {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputCapacity = max(1024, AVAudioFrameCount(ceil(Double(max(inputBuffer.frameLength, 1)) * ratio) + 64))

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outputCapacity) else {
                throw SimpleError("Could not allocate audio upload output buffer")
            }
            var didProvideInput = false
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if !didProvideInput {
                    didProvideInput = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
                outStatus.pointee = .noDataNow
                return nil
            }
            if let conversionError = conversionError {
                throw conversionError
            }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }

            switch status {
            case .haveData:
                continue
            case .inputRanDry, .endOfStream:
                return
            case .error:
                throw SimpleError("Audio upload conversion failed")
            @unknown default:
                return
            }
        }
    }

    private static func uploadAudioSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: uploadSampleRate,
            AVNumberOfChannelsKey: Int(uploadChannelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private static func isUploadAudioFormat(_ format: AVAudioFormat) -> Bool {
        abs(format.sampleRate - uploadSampleRate) < 1 &&
            format.channelCount == uploadChannelCount &&
            format.commonFormat == .pcmFormatInt16
    }

    private static func fileByteCount(_ url: URL) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }
    private func splitChunk(_ chunk: AudioChunk) throws -> [AudioChunk] {
        let input = try AVAudioFile(forReading: chunk.url)
        let totalFrames = input.length
        guard totalFrames > 1 else { return [] }

        let firstFrameCount = max(1, totalFrames / 2)
        let frameCounts = [firstFrameCount, totalFrames - firstFrameCount].filter { $0 > 0 }
        var splitChunks: [AudioChunk] = []

        for partIndex in 0..<frameCounts.count {
            let partURL = FileManager.default.temporaryDirectory.appendingPathComponent("stm-desktop-listener-\(UUID().uuidString)-retry-\(chunk.index)-\(partIndex + 1).wav")
            let output = try AVAudioFile(forWriting: partURL, settings: input.fileFormat.settings)
            var remainingFrames = frameCounts[partIndex]

            while remainingFrames > 0 {
                let framesToRead = min(AVAudioFrameCount(32768), AVAudioFrameCount(remainingFrames))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: framesToRead) else {
                    throw SimpleError("Could not allocate audio retry buffer")
                }
                try input.read(into: buffer, frameCount: framesToRead)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
                remainingFrames -= AVAudioFramePosition(buffer.frameLength)
            }

            splitChunks.append(AudioChunk(index: chunk.index, url: partURL, deleteAfterUse: true, retryDepth: chunk.retryDepth + 1))
        }

        return splitChunks
    }

    private func transcribe(url audioURL: URL, allowEmpty: Bool = false) async throws -> String {
        guard let baseURL = ConfigStore.string("workerUrl")?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let token = ConfigStore.string("authToken"),
              let url = URL(string: baseURL + "/api/transcribe?model=\(currentModel.id)") else {
            throw SimpleError("Missing credentials")
        }
        Logger.log("dictation transcribe request model=\(currentModel.id)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.upload(for: request, fromFile: audioURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code >= 200 && code < 300 else {
            throw Self.transcriptionError(statusCode: code, data: data)
        }
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var text = (decoded?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty,
           let info = decoded?["transcription_info"] as? [String: Any],
           let transcript = info["text"] as? String {
            text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty,
           let results = decoded?["results"] as? [String: Any],
           let channels = results["channels"] as? [[String: Any]],
           let alternatives = channels.first?["alternatives"] as? [[String: Any]],
           let transcript = alternatives.first?["transcript"] as? String {
            text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty && !allowEmpty { throw SimpleError("Empty transcript") }
        return text
    }

    private static func transcriptionError(statusCode: Int, data: Data) -> Error {
        let raw = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
        if isWorkerResourceLimit(raw) {
            return TranscriptionRequestError.workerResourceLimit(resourceLimitFailureMessage())
        }

        let compact = compactErrorBody(raw)
        if compact.isEmpty {
            return TranscriptionRequestError.requestFailed("HTTP \(statusCode)")
        }
        return TranscriptionRequestError.requestFailed("HTTP \(statusCode): \(compact)")
    }

    private static func isWorkerResourceLimit(_ raw: String) -> Bool {
        raw.localizedCaseInsensitiveContains("Worker exceeded resource limits") ||
            (raw.localizedCaseInsensitiveContains("Cloudflare") && raw.contains("1102"))
    }

    private static func resourceLimitFailureMessage() -> String {
        "Cloudflare Worker exceeded resource limits (1102). The app retried with normalized smaller audio and split the failed chunk, but the Worker still could not finish. Set dictationChunkSeconds to 10 or 5, set dictationUploadConcurrency to 1, or raise the Worker CPU limit on a paid Workers plan."
    }

    private static func compactErrorBody(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&bull;", with: "•")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(700))
    }

    private static func firstChunkSeconds() -> TimeInterval {
        let explicitFirst = ConfigStore.double("dictationFirstChunkSeconds", default: -1)
        if explicitFirst > 0 {
            return min(max(5, explicitFirst), 60)
        }
        if let configured = configuredChunkSeconds() {
            return configured
        }
        return defaultFirstChunkSeconds
    }

    private static func subsequentChunkSeconds() -> TimeInterval {
        configuredChunkSeconds() ?? defaultSubsequentChunkSeconds
    }

    private static func configuredChunkSeconds() -> TimeInterval? {
        let configured = ConfigStore.double("dictationChunkSeconds", default: -1)
        guard configured > 0 else { return nil }
        return min(max(5, configured), 60)
    }

    private static func maxConcurrentChunkTranscriptions() -> Int {
        let configured = ConfigStore.int("dictationUploadConcurrency", default: defaultChunkUploadConcurrency)
        return min(max(1, configured), maxChunkUploadConcurrency)
    }

    private func emitProcessingState() {
        guard isBusy else { return }
        let total = max(totalChunkCount, currentChunkIndex)
        onStateChange?(.processing(currentChunk: min(total, completedChunkCount + activeChunkTranscriptionCount), totalChunks: total))
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func hasCredentials() -> Bool {
        guard let url = ConfigStore.string("workerUrl"), let token = ConfigStore.string("authToken") else { return false }
        return !url.isEmpty && !token.isEmpty
    }
}
