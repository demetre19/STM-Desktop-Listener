import Foundation

struct QwenLiveChunkPolicy {
    enum Decision: String {
        case quiet
        case maximum
    }

    static let quietSearchStartSeconds: TimeInterval = 12
    static let maximumChunkSeconds: TimeInterval = 16
    static let quietThresholdDecibels: Float = -38
    static let requiredQuietSeconds: TimeInterval = 0.15

    private var consecutiveQuietSeconds: TimeInterval = 0

    mutating func observe(
        chunkDuration: TimeInterval,
        bufferDuration: TimeInterval,
        decibels: Float
    ) -> Decision? {
        if chunkDuration >= Self.maximumChunkSeconds {
            return .maximum
        }
        guard chunkDuration >= Self.quietSearchStartSeconds else {
            consecutiveQuietSeconds = 0
            return nil
        }

        if decibels <= Self.quietThresholdDecibels {
            consecutiveQuietSeconds += max(0, bufferDuration)
        } else {
            consecutiveQuietSeconds = 0
        }
        return consecutiveQuietSeconds >= Self.requiredQuietSeconds ? .quiet : nil
    }

    mutating func reset() {
        consecutiveQuietSeconds = 0
    }
}
