import Foundation

/// Silent background learning for dictation punctuation.
///
/// Two pieces, both local-only and bundled per machine:
///  - A JSONL training log (`punctuation-training.jsonl` in Application Support, mode 0600)
///    recording each dictation's source/accepted text and every guarded-merge decision.
///  - `GapPolicy`: learned per-user statistics for (word-before-gap × terminator) outcomes.
///    It accumulates keep/wrong counts from real dictations and votes on whether a stray
///    terminator should be merged — only when evidence is strong, otherwise the existing
///    heuristics decide. Learns speech patterns ("I" pause a lot) without popovers, servers,
///    or user flagging.
enum PunctuationLearning {

    /// One decision the guarded merge made about a gap or terminal run.
    struct GapDecision {
        var gap: String        // "source" | "model" | "terminal"
        var terminator: String // first of . ! ? … in the gap, or "" for commas/other
        var previous: String   // lowercased word before the gap
        var next: String       // lowercased word after the gap ("" for terminal)
        var clauseFirst: String// lowercased first word of the preceding clause
        var shaped: Bool       // clause scanned as question-shaped by the heuristics
        var action: String     // "keep" | "merge" | "demote" | "promote" | "space"
        var learned: Bool      // a policy vote (not heuristics) decided this
    }

    /// Multiclass boundary outcome learned from user corrections. `none` means no punctuation
    /// at the boundary; newline is recorded but conservatively never auto-inserted.
    enum BoundaryLabel: String, CaseIterable {
        case none, comma, period, question, exclamation, newline, other

        var replacementText: String? {
            switch self {
            case .none: return ""
            case .comma: return ","
            case .period: return "."
            case .question: return "?"
            case .exclamation: return "!"
            case .newline, .other: return nil
            }
        }
    }

    struct CorrectionObservation {
        var input: BoundaryLabel
        var desired: BoundaryLabel
        var previous: String
        var next: String
        var clauseFirst: String
        var shaped: Bool
        var weight: Int
    }

    /// Mutable decision collector for a single dictation.
    final class Trace {
        private(set) var decisions: [GapDecision] = []
        func record(_ decision: GapDecision) {
            decisions.append(decision)
        }
    }

    /// Correction-grounded multiclass boundary policy. Unlike `Policy`, this store is fed only
    /// by pasted→final user corrections, never by the system's own heuristic decisions.
    final class CorrectionPolicy {
        static let shared = CorrectionPolicy()

        static let storeURL = AppPaths.applicationSupport
            .appendingPathComponent("punctuation-correction-policy.json")
        private static let maxKeys = 4000
        private static let saveDelay: TimeInterval = 30

        private let lock = NSLock()
        private var stats: [String: [BoundaryLabel: Int]] = [:]
        private var insertionOrder: [String] = []
        private var dirty = false
        private var loaded = false
        private var savePending = false

        private init() {}

        /// Conservative learned preference for a boundary. Requires repeated correction mass,
        /// a dominant winner, and a margin over the next alternative; otherwise nil means the
        /// deterministic grammar heuristics remain in charge.
        func preferredLabel(
            input: BoundaryLabel,
            previousWord: String,
            nextWord: String,
            clauseFirst: String,
            shaped: Bool
        ) -> BoundaryLabel? {
            guard lock.try() else { return nil }
            defer { lock.unlock() }
            guard loaded,
                  let entry = stats[key(
                      clauseFirst: clauseFirst,
                      previous: previousWord,
                      next: nextWord,
                      input: input,
                      shaped: shaped
                  )] else { return nil }
            let ranked = entry
                .filter { $0.value > 0 }
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key.rawValue < rhs.key.rawValue
                }
            guard let winner = ranked.first else { return nil }
            let runnerUp = ranked.dropFirst().first?.value ?? 0
            let total = ranked.reduce(0) { $0 + $1.value }
            guard total >= 3,
                  winner.value >= 3,
                  winner.value >= runnerUp + 2,
                  Double(winner.value) / Double(total) >= 0.75 else { return nil }
            return winner.key
        }

        func observe(
            input: BoundaryLabel,
            desired: BoundaryLabel,
            previousWord: String,
            nextWord: String,
            clauseFirst: String,
            shaped: Bool,
            weight: Int
        ) {
            guard weight > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            loadLocked()
            let k = key(
                clauseFirst: clauseFirst,
                previous: previousWord,
                next: nextWord,
                input: input,
                shaped: shaped
            )
            var entry = stats[k] ?? [:]
            entry[desired, default: 0] += weight
            if stats[k] == nil {
                insertionOrder.append(k)
                while insertionOrder.count > Self.maxKeys {
                    let evicted = insertionOrder.removeFirst()
                    stats.removeValue(forKey: evicted)
                }
            }
            stats[k] = entry
            dirty = true
            scheduleSaveLocked()
        }

        func warm() {
            lock.lock()
            defer { lock.unlock() }
            loadLocked()
        }

        func flush() {
            lock.lock()
            defer { lock.unlock() }
            savePending = false
            guard dirty else { return }
            dirty = false
            saveLocked()
        }

        func clearAll() {
            lock.lock()
            defer { lock.unlock() }
            stats.removeAll()
            insertionOrder.removeAll()
            dirty = false
            loaded = true
            savePending = false
            try? FileManager.default.removeItem(at: Self.storeURL)
        }

        private func key(
            clauseFirst: String,
            previous: String,
            next: String,
            input: BoundaryLabel,
            shaped: Bool
        ) -> String {
            [clauseFirst, previous, next.isEmpty ? "$" : next, input.rawValue, shaped ? "q" : "s"]
                .joined(separator: "|")
        }

        private func scheduleSaveLocked() {
            guard !savePending else { return }
            savePending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay) { [weak self] in
                self?.flush()
            }
        }

        private func loadLocked() {
            guard !loaded else { return }
            loaded = true
            guard let data = try? Data(contentsOf: Self.storeURL),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Int]]
            else { return }
            for (k, rawEntry) in dict {
                var entry: [BoundaryLabel: Int] = [:]
                for (rawLabel, count) in rawEntry {
                    guard let label = BoundaryLabel(rawValue: rawLabel), count > 0 else { continue }
                    entry[label] = count
                }
                guard !entry.isEmpty else { continue }
                stats[k] = entry
                insertionOrder.append(k)
            }
        }

        private func saveLocked() {
            var serialized: [String: [String: Int]] = [:]
            for (k, entry) in stats {
                serialized[k] = Dictionary(uniqueKeysWithValues: entry.map { ($0.key.rawValue, $0.value) })
            }
            guard let data = try? JSONSerialization.data(
                withJSONObject: serialized,
                options: [.sortedKeys, .prettyPrinted]
            ) else { return }
            try? data.write(to: Self.storeURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Self.storeURL.path
            )
        }
    }

    private static let logQueue = DispatchQueue(label: "stm.punctuation.learning", qos: .utility)
    private static let maxLogBytes = 5_000_000
    /// Public: settings UI reveals it, audits read it, clear deletes it.
    static let trainingLogURL = AppPaths.applicationSupport
        .appendingPathComponent("punctuation-training.jsonl")

    /// Starts cold policy loading while audio is still being captured, keeping file replay off
    /// both app launch and the final paste path.
    static func warm() {
        logQueue.async {
            CorrectionPolicy.shared.warm()
        }
    }

    /// Feeds one finished dictation into the learner: appends a JSONL record and updates the
    /// policy. Cheap, local, and silent — call right after the final text is produced.
    static func record(engine: String, source: String, accepted: String, trace: Trace) {
        let decisions = trace.decisions
        let payload: [String: Any] = [
            "schema": 1,
            "date": ISO8601DateFormatter().string(from: Date()),
            "engine": engine,
            "source": source,
            "accepted": accepted,
            "decisions": decisions.map { decision -> [String: Any] in
                [
                    "gap": decision.gap,
                    "term": decision.terminator,
                    "prev": decision.previous,
                    "next": decision.next,
                    "clause": decision.clauseFirst,
                    "shaped": decision.shaped,
                    "action": decision.action,
                    "learned": decision.learned,
                ]
            },
        ]
        logQueue.async {
            // The ledger is an audit/rebuild artifact, not a label source. System decisions are
            // deliberately not fed back into a policy: deterministic heuristics would otherwise
            // vote for themselves until their own output looked like user truth.
            appendLogLine(payload)
        }
    }

    private static func appendLogLine(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8) else { return }
        let url = trainingLogURL
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int,
           size > maxLogBytes {
            // Start a new epoch rather than growing unboundedly; the policy already distilled
            // the useful signal.
            try? manager.removeItem(at: url)
        }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
    }

    /// Conservative post-edit relatedness check. Punctuation and capitalization edits do not
    /// change the canonical text at all; whitespace is ignored because accessibility clients
    /// often normalize it. Long prefix/suffix anchors permit a word-level correction in the
    /// middle while still rejecting unrelated field contents.
    static func postEditTextsAppearRelated(pasted: String, final: String) -> Bool {
        func canonical(_ text: String) -> String {
            String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            }))
        }
        let oldText = canonical(pasted)
        let newText = canonical(final)
        guard !oldText.isEmpty, !newText.isEmpty else { return false }
        if newText.contains(oldText) || oldText.contains(newText) { return true }
        guard oldText.count >= 12 else { return false }
        let anchorLength = min(40, max(6, oldText.count / 3))
        let prefix = oldText.prefix(anchorLength)
        let suffix = oldText.suffix(anchorLength)
        return newText.contains(prefix) || newText.contains(suffix)
    }

    private struct CorrectionWord {
        var text: String
        var start: Int
        var end: Int
    }

    private static let correctionWordExpression = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")

    private static func correctionWords(in text: String) -> [CorrectionWord] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return correctionWordExpression?.matches(in: text, range: range).map { match in
            CorrectionWord(
                text: nsText.substring(with: match.range).lowercased(),
                start: match.range.location,
                end: match.range.location + match.range.length
            )
        } ?? []
    }

    static func boundaryLabel(for gap: String) -> BoundaryLabel {
        if gap.rangeOfCharacter(from: .newlines) != nil { return .newline }
        if gap.contains("?") { return .question }
        if gap.contains("!") { return .exclamation }
        if gap.contains(".") || gap.contains("…") { return .period }
        if gap.contains(",") { return .comma }
        if gap.rangeOfCharacter(from: .punctuationCharacters) != nil { return .other }
        return .none
    }

    static func inputLabel(for decision: GapDecision) -> BoundaryLabel {
        if !decision.terminator.isEmpty {
            return boundaryLabel(for: decision.terminator)
        }
        // Comma decisions carry an empty terminator because commas are sentence-medial rather
        // than terminators. They are the only punctuation-bearing decision kind with no term.
        return .comma
    }

    private static func gapTexts(words: [CorrectionWord], in text: String) -> (interior: [String], terminal: String) {
        let nsText = text as NSString
        var interior: [String] = []
        guard words.count > 1 else {
            let end = words.first?.end ?? 0
            return ([], end < nsText.length ? nsText.substring(from: end) : "")
        }
        for index in 0..<(words.count - 1) {
            let range = NSRange(location: words[index].end, length: words[index + 1].start - words[index].end)
            interior.append(nsText.substring(with: range))
        }
        let end = words[words.count - 1].end
        return (interior, end < nsText.length ? nsText.substring(from: end) : "")
    }

    private static func pastedClauseFirst(
        boundaryIndex: Int,
        words: [CorrectionWord],
        gaps: [String]
    ) -> String {
        var start = 0
        if boundaryIndex > 0 {
            for gapIndex in stride(from: boundaryIndex - 1, through: 0, by: -1) {
                if gaps[gapIndex].range(of: "[.!?…\\n]", options: .regularExpression) != nil {
                    start = gapIndex + 1
                    break
                }
            }
        }
        return words[start].text
    }

    /// Converts a pasted→final correction into conservative boundary supervision. It trains only
    /// when every word is unchanged (case-insensitively): then any punctuation delta is unambiguous.
    /// Changed boundaries count three times; punctuation the user actively left unchanged counts once.
    static func correctionObservations(
        pasted: String,
        final: String,
        decisions: [GapDecision]
    ) -> [CorrectionObservation] {
        let pastedWords = correctionWords(in: pasted)
        let finalWords = correctionWords(in: final)
        guard !pastedWords.isEmpty,
              pastedWords.count == finalWords.count,
              zip(pastedWords, finalWords).allSatisfy({ $0.text == $1.text })
        else { return [] }

        let pastedGaps = gapTexts(words: pastedWords, in: pasted)
        let finalGaps = gapTexts(words: finalWords, in: final)
        var observations: [CorrectionObservation] = []
        var seen: Set<String> = []

        func appendObservation(
            boundaryIndex: Int,
            pastedGap: String,
            finalGap: String,
            decision: GapDecision
        ) {
            guard !pastedGap.contains("\u{FE00}"), !finalGap.contains("\u{FE00}") else { return }
            let emitted = boundaryLabel(for: pastedGap)
            let desired = boundaryLabel(for: finalGap)
            let input = inputLabel(for: decision)
            let signature = [
                String(boundaryIndex), input.rawValue, desired.rawValue,
                decision.previous, decision.next, decision.clauseFirst, String(decision.shaped)
            ].joined(separator: "|")
            guard seen.insert(signature).inserted else { return }
            observations.append(.init(
                input: input,
                desired: desired,
                previous: decision.previous,
                next: decision.next,
                clauseFirst: decision.clauseFirst,
                shaped: decision.shaped,
                weight: emitted == desired ? 1 : 3
            ))
        }

        for decision in decisions {
            if decision.next.isEmpty {
                let boundaryIndex = pastedWords.count - 1
                guard pastedWords[boundaryIndex].text == decision.previous.lowercased(),
                      pastedClauseFirst(boundaryIndex: boundaryIndex, words: pastedWords, gaps: pastedGaps.interior) == decision.clauseFirst.lowercased()
                else { continue }
                appendObservation(
                    boundaryIndex: boundaryIndex,
                    pastedGap: pastedGaps.terminal,
                    finalGap: finalGaps.terminal,
                    decision: decision
                )
                continue
            }

            for boundaryIndex in 0..<(pastedWords.count - 1) {
                guard pastedWords[boundaryIndex].text == decision.previous.lowercased(),
                      pastedWords[boundaryIndex + 1].text == decision.next.lowercased(),
                      pastedClauseFirst(boundaryIndex: boundaryIndex, words: pastedWords, gaps: pastedGaps.interior) == decision.clauseFirst.lowercased()
                else { continue }
                appendObservation(
                    boundaryIndex: boundaryIndex,
                    pastedGap: pastedGaps.interior[boundaryIndex],
                    finalGap: finalGaps.interior[boundaryIndex],
                    decision: decision
                )
                break
            }
        }
        return observations
    }

    private static func parseDecisions(_ decisions: [[String: Any]]) -> [GapDecision] {
        decisions.compactMap { raw in
            guard let action = raw["action"] as? String else { return nil }
            return GapDecision(
                gap: raw["gap"] as? String ?? "model",
                terminator: raw["term"] as? String ?? "",
                previous: raw["prev"] as? String ?? "",
                next: raw["next"] as? String ?? "",
                clauseFirst: raw["clause"] as? String ?? "",
                shaped: raw["shaped"] as? Bool ?? false,
                action: action,
                learned: raw["learned"] as? Bool ?? false
            )
        }
    }

    private static func loggedDecisions(forAccepted accepted: String) -> [GapDecision] {
        guard let data = try? Data(contentsOf: trainingLogURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        for line in text.split(separator: "\n").reversed() {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  entry["accepted"] as? String == accepted,
                  let decisions = entry["decisions"] as? [[String: Any]]
            else { continue }
            return parseDecisions(decisions)
        }
        return []
    }

    /// Records the user's own in-place correction to a pasted dictation: the
    /// text we pasted versus what was finally left in the field. Written as a
    /// decision-free ledger entry. Rebuilds mine these source→final pairs as the
    /// user-truth labels that system decisions themselves cannot provide.
    static func recordPostEdit(pasted: String, final: String) {
        guard !pasted.isEmpty, !final.isEmpty, pasted != final else { return }
        let payload: [String: Any] = [
            "schema": 1,
            "date": ISO8601DateFormatter().string(from: Date()),
            "kind": "postEdit",
            "pasted": pasted,
            "final": final,
        ]
        logQueue.async {
            appendLogLine(payload)
            let decisions = loggedDecisions(forAccepted: pasted)
            let observations = correctionObservations(pasted: pasted, final: final, decisions: decisions)
            for observation in observations {
                CorrectionPolicy.shared.observe(
                    input: observation.input,
                    desired: observation.desired,
                    previousWord: observation.previous,
                    nextWord: observation.next,
                    clauseFirst: observation.clauseFirst,
                    shaped: observation.shaped,
                    weight: observation.weight
                )
            }
            Logger.log("post-edit training observations=\(observations.count)")
        }
    }

    /// Rebuilds correction-grounded stats from surviving pasted→final ledger pairs. System
    /// decisions are used only to recover boundary context; they are never labels themselves.
    static func rebuildPolicyFromLog() {
        CorrectionPolicy.shared.clearAll()
        guard let data = try? Data(contentsOf: trainingLogURL),
              let text = String(data: data, encoding: .utf8)
        else {
            Logger.log("punctuation correction policy rebuilt from log observations=0")
            return
        }
        var decisionsByAccepted: [String: [GapDecision]] = [:]
        var observationCount = 0
        for line in text.split(separator: "\n") {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            if let accepted = entry["accepted"] as? String,
               let decisions = entry["decisions"] as? [[String: Any]] {
                decisionsByAccepted[accepted] = parseDecisions(decisions)
                continue
            }
            guard entry["kind"] as? String == "postEdit",
                  let pasted = entry["pasted"] as? String,
                  let final = entry["final"] as? String,
                  let decisions = decisionsByAccepted[pasted]
            else { continue }
            let observations = correctionObservations(pasted: pasted, final: final, decisions: decisions)
            observationCount += observations.count
            for observation in observations {
                CorrectionPolicy.shared.observe(
                    input: observation.input,
                    desired: observation.desired,
                    previousWord: observation.previous,
                    nextWord: observation.next,
                    clauseFirst: observation.clauseFirst,
                    shaped: observation.shaped,
                    weight: observation.weight
                )
            }
        }
        CorrectionPolicy.shared.flush()
        Logger.log("punctuation correction policy rebuilt from log observations=\(observationCount)")
    }

    /// Full reset: learned stats, policy file, and the decision ledger.
    static func clearAll() {
        // Records are serialized on logQueue. Clearing on that queue prevents already queued
        // dictations from repopulating the policy or ledger after the user asked for a reset.
        logQueue.sync {
            CorrectionPolicy.shared.clearAll()
            try? FileManager.default.removeItem(at: trainingLogURL)
        }
        Logger.log("punctuation learning data cleared")
    }
}
