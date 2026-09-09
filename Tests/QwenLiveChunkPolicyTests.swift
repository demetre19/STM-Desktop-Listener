import Darwin
import Foundation

@main
struct QwenLiveChunkPolicyTests {
    static func main() {
        var policy = QwenLiveChunkPolicy()

        require(
            policy.observe(chunkDuration: 11.99, bufferDuration: 0.2, decibels: -60) == nil,
            "quiet audio must not rotate before the search window"
        )
        require(
            policy.observe(chunkDuration: 12.08, bufferDuration: 0.08, decibels: -45) == nil,
            "one short quiet buffer must not rotate"
        )
        require(
            policy.observe(chunkDuration: 12.16, bufferDuration: 0.08, decibels: -45) == .quiet,
            "sustained quiet audio must rotate after the search window"
        )

        policy.reset()
        require(
            policy.observe(chunkDuration: 13.0, bufferDuration: 0.1, decibels: -45) == nil,
            "quiet accumulation should begin without rotating early"
        )
        require(
            policy.observe(chunkDuration: 13.1, bufferDuration: 0.1, decibels: -20) == nil,
            "speech must clear accumulated quiet time"
        )
        require(
            policy.observe(chunkDuration: 13.2, bufferDuration: 0.1, decibels: -45) == nil,
            "quiet timing must restart after speech"
        )

        policy.reset()
        require(
            policy.observe(chunkDuration: 16.0, bufferDuration: 0.01, decibels: -10) == .maximum,
            "continuous speech must rotate at the maximum duration"
        )

        print("Qwen live chunk policy tests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            print("FAIL: \(message)")
            exit(1)
        }
    }
}
