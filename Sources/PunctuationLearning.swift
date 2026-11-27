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

    /// Mutable decision collector for a single dictation.
    final class Trace {
        private(set) var decisions: [GapDecision] = []
        func record(_ decision: GapDecision) {
            decisions.append(decision)
        }
    }

    /// Learned per-user statistics over gap contexts. Wrong = merged or demoted.
    final class Policy {
        static let shared = Policy()

        /// Dedicated, LLM-auditable store — deliberately NOT inside config.json, which holds
        /// the transcription token. Plain JSON: each sentence-signature key maps to
        /// "keep,wrong" counts so a model can read, rewrite, or prune it directly.
        static let storeURL = AppPaths.applicationSupport
            .appendingPathComponent("punctuation-policy.json")
        private static let maxKeys = 4000
        private static let saveDelay: TimeInterval = 30

        private let lock = NSLock()
        private var stats: [String: (keep: Int, wrong: Int)] = [:]
        private var insertionOrder: [String] = []
        private var dirty = false
        private var loaded = false
        private var savePending = false

        private init() {}

        /// Learned vote on merging a terminator gap. Returns true = merge, false = keep,
        /// nil = insufficient evidence (heuristics decide). The key is a sentence-level
        /// signature — clause opener, flanking words, terminator, and question shape — so
        /// "…how is it running? the next…" and "Is it running?" are separate patterns even
        /// though both end on the same word.
        func vote(
            terminator: String,
            previousWord: String,
            nextWord: String,
            clauseFirst: String,
            shaped: Bool
        ) -> Bool? {
            // Voting is on the paste path. A cold or still-warming policy must abstain rather
            // than wait while a multi-megabyte ledger is replayed before paste.
            guard lock.try() else { return nil }
            defer { lock.unlock() }
            guard loaded, let entry = stats[key(
                clauseFirst: clauseFirst,
                previous: previousWord,
                next: nextWord,
                terminator: terminator,
                shaped: shaped
            )] else { return nil }
            let total = entry.keep + entry.wrong
            guard total >= 6 else { return nil }
            let wrongShare = Double(entry.wrong) / Double(total)
            if terminator == "." {
                // Periods are the least harmful terminator; demand stronger evidence.
                if total >= 12, wrongShare >= 0.95 { return true }
                if entry.keep > entry.wrong * 3 { return false }
                return nil
            }
            if wrongShare >= 0.85 { return true }
            if entry.keep > entry.wrong * 3 { return false }
            return nil
        }

        /// Loads the policy once in the caller's background context. Dictation startup uses
        /// this so paste-time votes usually see an already-loaded store.
        func warm() {
            lock.lock()
            defer { lock.unlock() }
            loadLocked()
        }

        /// Records an observed decision outcome for future votes. Policy-driven decisions are
        /// not independent evidence: counting them again would make the learner reinforce its
        /// own guesses instead of learning from recognizer/model behavior or user corrections.
        func observe(_ decision: GapDecision) {
            guard !decision.learned, !decision.terminator.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            loadLocked()
            observeLocked(decision)
        }

        private func observeLocked(_ decision: GapDecision) {
            guard !decision.learned, !decision.terminator.isEmpty else { return }
            var wrong = false
            switch decision.action {
            case "keep":
                break
            case "merge", "demote", "space":
                wrong = true
            default:
                return // promotions don't inform the merge prior
            }
            accumulate(key(
                clauseFirst: decision.clauseFirst,
                previous: decision.previous,
                next: decision.next,
                terminator: decision.terminator,
                shaped: decision.shaped
            ), wrong: wrong)
        }

        /// Sentence-level signature: clause opener | preceding word | following word
        /// ("$" at end of clause) | terminator | question shape. Human- and LLM-readable.
        private func key(
            clauseFirst: String,
            previous: String,
            next: String,
            terminator: String,
            shaped: Bool
        ) -> String {
            [clauseFirst, previous, next.isEmpty ? "$" : next, terminator, shaped ? "q" : "s"]
                .joined(separator: "|")
        }

        private func accumulate(_ k: String, wrong: Bool) {
            var entry = stats[k] ?? (0, 0)
            if wrong { entry.wrong += 1 } else { entry.keep += 1 }
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

        private func scheduleSaveLocked() {
            guard !savePending else { return }
            savePending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay) { [weak self] in
                self?.flush()
            }
        }

        /// Persists accumulated stats; safe to call on termination.
        func flush() {
            lock.lock()
            defer { lock.unlock() }
            savePending = false
            guard dirty else { return }
            dirty = false
            saveLocked()
        }

        /// Erases every learned statistic and deletes the store file. The decision log is a
        /// separate artifact; callers that want a full reset remove it too.
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

        private func loadLocked() {
            guard !loaded else { return }
            loaded = true
            // One-time cleanup: pre-release stats lived in config.json under
            // `dictation.punctuationPolicy` (which also holds the auth token). Word-level
            // keys are obsolete — the decision log replays into the sentence-level store
            // via rebuildPolicyFromLog, so the legacy key is simply removed.
            try? ConfigStore.remove("dictation.punctuationPolicy")
            guard let data = try? Data(contentsOf: Self.storeURL),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else {
                // Cold start with an existing ledger: replay it so sentence-level stats are
                // seeded from everything already logged.
                for decision in PunctuationLearning.loggedDecisions() {
                    observeLocked(decision)
                }
                saveLocked()
                return
            }
            for (k, v) in dict {
                let parts = v.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                stats[k] = (parts[0], parts[1])
                insertionOrder.append(k)
            }
        }

        private func saveLocked() {
            let serialized = stats.mapValues { "\($0.keep),\($0.wrong)" }
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
            Policy.shared.warm()
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
            // Policy loading and ledger replay can touch multi-megabyte local files. They must
            // never sit between transcription completion and paste.
            for decision in decisions {
                Policy.shared.observe(decision)
            }
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

    /// Records the user's own in-place correction to a pasted dictation: the
    /// text we pasted versus what was finally left in the field. Written as a
    /// decision-free ledger entry so `rebuildPolicyFromLog`/`loggedDecisions`
    /// skip it, while audits and future trainers can mine source→final pairs
    /// (the "what it ends with" signal the model never sees).
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
        }
    }

    /// Re-distills the policy from the decision ledger — e.g. after an LLM audit edits the
    /// log, or after a policy file is corrupted or cleared. Replays every recorded decision
    /// as if it were observed live.
    static func rebuildPolicyFromLog() {
        Policy.shared.clearAll()
        let decisions = loggedDecisions()
        for decision in decisions {
            Policy.shared.observe(decision)
        }
        Policy.shared.flush()
        Logger.log("punctuation policy rebuilt from log decisions=\(decisions.count)")
    }

    /// Decisions from the ledger, oldest first. Used to seed or rebuild the policy.
    static func loggedDecisions() -> [GapDecision] {
        guard let data = try? Data(contentsOf: trainingLogURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        var result: [GapDecision] = []
        for line in text.split(separator: "\n") {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let decisions = entry["decisions"] as? [[String: Any]]
            else { continue }
            for raw in decisions {
                guard let action = raw["action"] as? String else { continue }
                result.append(.init(
                    gap: raw["gap"] as? String ?? "model",
                    terminator: raw["term"] as? String ?? "",
                    previous: raw["prev"] as? String ?? "",
                    next: raw["next"] as? String ?? "",
                    clauseFirst: raw["clause"] as? String ?? "",
                    shaped: raw["shaped"] as? Bool ?? false,
                    action: action,
                    learned: raw["learned"] as? Bool ?? false
                ))
            }
        }
        return result
    }

    /// Full reset: learned stats, policy file, and the decision ledger.
    static func clearAll() {
        // Records are serialized on logQueue. Clearing on that queue prevents already queued
        // dictations from repopulating the policy or ledger after the user asked for a reset.
        logQueue.sync {
            Policy.shared.clearAll()
            try? FileManager.default.removeItem(at: trainingLogURL)
        }
        Logger.log("punctuation learning data cleared")
    }
}
