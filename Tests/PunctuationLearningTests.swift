import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct PunctuationLearningTests {
    static func main() {
        testLedgerReplayIgnoresLearnedDecisions()

        let relatedCases: [(name: String, pasted: String, final: String, expected: Bool)] = [
            (
                "early punctuation correction remains related",
                "Hello, world this is a test dictation.",
                "Hello. World, this is a test dictation!",
                true
            ),
            (
                "surrounding field text remains related",
                "please review the punctuation in this sentence",
                "existing prefix please review the punctuation in this sentence existing suffix",
                true
            ),
            (
                "middle word edit keeps a suffix anchor",
                "please review the punctuation in this sentence and make the ending much better",
                "please review the punctuation in that sentence and make the ending much better",
                true
            ),
            (
                "unrelated field text is rejected",
                "please review the punctuation in this sentence",
                "a completely unrelated document about deployment invoices",
                false
            ),
        ]

        for testCase in relatedCases {
            let actual = PunctuationLearning.postEditTextsAppearRelated(
                pasted: testCase.pasted,
                final: testCase.final
            )
            guard actual == testCase.expected else {
                print(
                    "FAIL: \(testCase.name)\n" +
                        "  expected: \(testCase.expected)\n" +
                        "  actual:   \(actual)"
                )
                exit(EXIT_FAILURE)
            }
        }

        print("PunctuationLearningTests: all \(relatedCases.count + 1) cases passed")
    }

    private static func testLedgerReplayIgnoresLearnedDecisions() {
        let policyBackup = try? Data(contentsOf: PunctuationLearning.Policy.storeURL)
        let ledgerBackup = try? Data(contentsOf: PunctuationLearning.trainingLogURL)
        defer {
            try? FileManager.default.removeItem(at: PunctuationLearning.Policy.storeURL)
            try? FileManager.default.removeItem(at: PunctuationLearning.trainingLogURL)
            if let policyBackup {
                try? policyBackup.write(to: PunctuationLearning.Policy.storeURL, options: .atomic)
            }
            if let ledgerBackup {
                try? ledgerBackup.write(to: PunctuationLearning.trainingLogURL, options: .atomic)
            }
        }

        try? FileManager.default.removeItem(at: PunctuationLearning.Policy.storeURL)
        let entry = #"{"schema":1,"decisions":[{"gap":"model","term":".","prev":"and","next":"then","clause":"alpha","shaped":false,"action":"merge","learned":true}]}"# + "\n"
        try? String(repeating: entry, count: 20).write(to: PunctuationLearning.trainingLogURL, atomically: true, encoding: .utf8)
        PunctuationLearning.Policy.shared.warm()
        let vote = PunctuationLearning.Policy.shared.vote(
            terminator: ".",
            previousWord: "and",
            nextWord: "then",
            clauseFirst: "alpha",
            shaped: false
        )
        guard vote == nil else {
            print("FAIL: ledger replay counted learned decisions as independent evidence")
            exit(EXIT_FAILURE)
        }
    }
}
