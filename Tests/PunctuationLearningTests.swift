import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct PunctuationLearningTests {
    static func main() {
        testCorrectionPolicyRebuildsFromPostEdits()
        testCorrectionObservations()

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

        print("PunctuationLearningTests: all \(relatedCases.count + 12) cases passed")
    }

    private static func testCorrectionObservations() {
        let decayed = PunctuationLearning.decayedBoundaryCounts(
            [.period: 4.0],
            elapsedSeconds: PunctuationLearning.correctionEvidenceHalfLifeSeconds
        )
        guard abs((decayed[.period] ?? 0) - 2.0) < 0.0001 else {
            print("FAIL: correction evidence does not decay to half after one half-life: \(decayed)")
            exit(EXIT_FAILURE)
        }

        let mergeDecision = PunctuationLearning.GapDecision(
            gap: "model", terminator: ".", previous: "say", next: "and",
            clauseFirst: "i", shaped: false, action: "keep", learned: false
        )
        let mergeObservations = PunctuationLearning.correctionObservations(
            pasted: "I was going to say. And then he left.",
            final: "I was going to say and then he left.",
            decisions: [mergeDecision]
        )
        guard mergeObservations.count == 1,
              mergeObservations[0].input == .period,
              mergeObservations[0].desired == .none,
              mergeObservations[0].weight == 4 else {
            print("FAIL: punctuation removal correction was not converted to strong none evidence: \(mergeObservations)")
            exit(EXIT_FAILURE)
        }

        let terminalDecision = PunctuationLearning.GapDecision(
            gap: "terminal", terminator: ".", previous: "it", next: "",
            clauseFirst: "can", shaped: false, action: "keep", learned: false
        )
        let questionObservations = PunctuationLearning.correctionObservations(
            pasted: "Can you send it.",
            final: "Can you send it?",
            decisions: [terminalDecision]
        )
        guard questionObservations.count == 1,
              questionObservations[0].desired == .question,
              questionObservations[0].weight == 4 else {
            print("FAIL: terminal replacement correction was not converted to question evidence: \(questionObservations)")
            exit(EXIT_FAILURE)
        }

        let unchangedObservations = PunctuationLearning.correctionObservations(
            pasted: "I was going to say. And then he left.",
            final: "I was going to say. And then he left!",
            decisions: [mergeDecision]
        )
        guard unchangedObservations.count == 1,
              unchangedObservations[0].desired == .period,
              unchangedObservations[0].weight == 1 else {
            print("FAIL: unchanged edited boundary did not produce weak confirmation: \(unchangedObservations)")
            exit(EXIT_FAILURE)
        }

        let capitalizationOnlyObservations = PunctuationLearning.correctionObservations(
            pasted: "I was going to say. And then he left.",
            final: "I was going to say. And then He left.",
            decisions: [mergeDecision]
        )
        guard capitalizationOnlyObservations.isEmpty else {
            print("FAIL: capitalization-only edit produced weak punctuation evidence")
            exit(EXIT_FAILURE)
        }

        let wordEditObservations = PunctuationLearning.correctionObservations(
            pasted: "I was going to say. And then he left.",
            final: "I was going to mention. And then he left.",
            decisions: [mergeDecision]
        )
        guard wordEditObservations.isEmpty else {
            print("FAIL: ambiguous word edit produced punctuation supervision")
            exit(EXIT_FAILURE)
        }

        let embeddedDecision = PunctuationLearning.GapDecision(
            gap: "model", terminator: ".", previous: "zcontext", next: "beta",
            clauseFirst: "alpha", shaped: false, action: "keep", learned: false
        )
        let embeddedObservations = PunctuationLearning.correctionObservations(
            pasted: "Alpha zcontext. Beta end.",
            final: "Existing prefix Alpha zcontext Beta end. existing suffix",
            decisions: [embeddedDecision]
        )
        guard embeddedObservations.count == 1,
              embeddedObservations[0].desired == PunctuationLearning.BoundaryLabel.none else {
            print("FAIL: correction inside surrounding field text was not isolated: \(embeddedObservations)")
            exit(EXIT_FAILURE)
        }
        let ambiguousObservations = PunctuationLearning.correctionObservations(
            pasted: "Alpha zcontext. Beta end.",
            final: "Alpha zcontext Beta end. filler Alpha zcontext Beta end.",
            decisions: [embeddedDecision]
        )
        guard ambiguousObservations.isEmpty else {
            print("FAIL: ambiguous repeated pasted text produced correction labels")
            exit(EXIT_FAILURE)
        }

        let insertionObservations = PunctuationLearning.correctionObservations(
            pasted: "Alpha zinsert beta gamma.",
            final: "Alpha zinsert, beta gamma.",
            decisions: []
        )
        guard insertionObservations.count == 1,
              insertionObservations[0].input == PunctuationLearning.BoundaryLabel.none,
              insertionObservations[0].desired == .comma,
              insertionObservations[0].previous == "zinsert",
              insertionObservations[0].next == "beta",
              insertionObservations[0].weight == 4 else {
            print("FAIL: punctuation insertion correction was not converted to none-input evidence: \(insertionObservations)")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: mergeObservations[0].input,
            desired: mergeObservations[0].desired,
            previousWord: "zz-never-real-prev",
            nextWord: "zz-never-real-next",
            clauseFirst: "zz-never-real-clause",
            shaped: false,
            weight: mergeObservations[0].weight
        )
        let preferred = PunctuationLearning.CorrectionPolicy.shared.preferredLabel(
            input: .period,
            previousWord: "zz-never-real-prev",
            nextWord: "zz-never-real-next",
            clauseFirst: "zz-never-real-clause",
            shaped: false
        )
        guard preferred == PunctuationLearning.BoundaryLabel.none else {
            print("FAIL: correction policy did not prefer user-corrected none label: \(String(describing: preferred))")
            exit(EXIT_FAILURE)
        }

        guard PunctuationLearning.CorrectionPolicy.shared.hasEvidence(
            for: .period,
            previousWord: "zz-never-real-prev"
        ),
              !PunctuationLearning.CorrectionPolicy.shared.hasEvidence(
            for: .period,
            previousWord: "zz-unseen-prev"
        ) else {
            print("FAIL: correction evidence preflight did not filter by previous word")
            exit(EXIT_FAILURE)
        }


        for clause in ["zbackoff-one", "zbackoff-two"] {
            PunctuationLearning.CorrectionPolicy.shared.observe(
                input: .period,
                desired: PunctuationLearning.BoundaryLabel.none,
                previousWord: "zsharedprev",
                nextWord: "zsharednext",
                clauseFirst: clause,
                shaped: false,
                weight: 3
            )
        }
        let generalized = PunctuationLearning.CorrectionPolicy.shared.preferredLabel(
            input: .period,
            previousWord: "zsharedprev",
            nextWord: "zsharednext",
            clauseFirst: "zbackoff-unseen",
            shaped: false
        )
        guard generalized == PunctuationLearning.BoundaryLabel.none else {
            print("FAIL: correction policy did not back off across clause openers: \(String(describing: generalized))")
            exit(EXIT_FAILURE)
        }
        let overgeneralized = PunctuationLearning.CorrectionPolicy.shared.preferredLabel(
            input: .period,
            previousWord: "different-prev",
            nextWord: "zsharednext",
            clauseFirst: "zbackoff-unseen",
            shaped: false
        )
        guard overgeneralized == nil else {
            print("FAIL: correction policy overgeneralized to unrelated boundary words")
            exit(EXIT_FAILURE)
        }
    }

    private static func testCorrectionPolicyRebuildsFromPostEdits() {
        let policyBackup = try? Data(contentsOf: PunctuationLearning.CorrectionPolicy.storeURL)
        let ledgerBackup = try? Data(contentsOf: PunctuationLearning.trainingLogURL)
        defer {
            try? FileManager.default.removeItem(at: PunctuationLearning.CorrectionPolicy.storeURL)
            try? FileManager.default.removeItem(at: PunctuationLearning.trainingLogURL)
            if let policyBackup {
                try? policyBackup.write(to: PunctuationLearning.CorrectionPolicy.storeURL, options: .atomic)
            }
            if let ledgerBackup {
                try? ledgerBackup.write(to: PunctuationLearning.trainingLogURL, options: .atomic)
            }
        }

        try? FileManager.default.removeItem(at: PunctuationLearning.CorrectionPolicy.storeURL)
        let pasted = "Alpha zrebuildprev. Zrebuildnext end."
        let final = "Alpha zrebuildprev zrebuildnext end."
        let acceptedEntry = "{\"schema\":1,\"accepted\":\"\(pasted)\",\"decisions\":[{\"gap\":\"model\",\"term\":\".\",\"prev\":\"zrebuildprev\",\"next\":\"zrebuildnext\",\"clause\":\"alpha\",\"shaped\":false,\"action\":\"keep\",\"learned\":false}]}"
        let idPasted = "Alpha zidprev. Zidnext end."
        let idFinal = "Alpha zidprev zidnext end."
        let correctIDEntry = "{\"schema\":2,\"dictationID\":\"correct-id\",\"accepted\":\"\(idPasted)\",\"decisions\":[{\"gap\":\"model\",\"term\":\".\",\"prev\":\"zidprev\",\"next\":\"zidnext\",\"clause\":\"alpha\",\"shaped\":false,\"action\":\"keep\",\"learned\":false}]}"
        let wrongIDEntry = "{\"schema\":2,\"dictationID\":\"wrong-id\",\"accepted\":\"\(idPasted)\",\"decisions\":[{\"gap\":\"model\",\"term\":\",\",\"prev\":\"zidprev\",\"next\":\"zidnext\",\"clause\":\"alpha\",\"shaped\":false,\"action\":\"keep\",\"learned\":false}]}"
        let idEditEntry = "{\"schema\":2,\"kind\":\"postEdit\",\"dictationID\":\"correct-id\",\"pasted\":\"\(idPasted)\",\"final\":\"\(idFinal)\"}"
        let editEntry = "{\"schema\":1,\"kind\":\"postEdit\",\"pasted\":\"\(pasted)\",\"final\":\"\(final)\"}"
        try? ([acceptedEntry, correctIDEntry, wrongIDEntry, editEntry, idEditEntry].joined(separator: "\n") + "\n").write(
            to: PunctuationLearning.trainingLogURL,
            atomically: true,
            encoding: .utf8
        )

        PunctuationLearning.rebuildPolicyFromLog()
        let preferred = PunctuationLearning.CorrectionPolicy.shared.preferredLabel(
            input: .period,
            previousWord: "zrebuildprev",
            nextWord: "zrebuildnext",
            clauseFirst: "alpha",
            shaped: false
        )
        guard preferred == PunctuationLearning.BoundaryLabel.none else {
            print("FAIL: correction policy rebuild did not recover post-edit evidence: \(String(describing: preferred))")
            exit(EXIT_FAILURE)
        }
        let idPreferred = PunctuationLearning.CorrectionPolicy.shared.preferredLabel(
            input: .period,
            previousWord: "zidprev",
            nextWord: "zidnext",
            clauseFirst: "alpha",
            shaped: false
        )
        guard idPreferred == PunctuationLearning.BoundaryLabel.none else {
            print("FAIL: rebuild did not use dictation IDs to disambiguate repeated text: \(String(describing: idPreferred))")
            exit(EXIT_FAILURE)
        }

        guard let policyData = try? Data(contentsOf: PunctuationLearning.CorrectionPolicy.storeURL),
              let root = try? JSONSerialization.jsonObject(with: policyData) as? [String: Any],
              root["version"] as? Int == 2,
              root["entries"] is [String: Any] else {
            print("FAIL: correction policy did not persist schema-v2 timestamped entries")
            exit(EXIT_FAILURE)
        }
    }
}
