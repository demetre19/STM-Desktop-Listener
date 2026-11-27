import Foundation

enum SpokenDictationFormatter {
    private struct Rule {
        let phrases: [String]
        let replacement: String
    }

    private static let rules = [
        Rule(phrases: ["new paragraph", "next paragraph"], replacement: "\u{E000}"),
        Rule(
            phrases: [
                "go to a new line",
                "start a new line",
                "go to new line",
                "start new line",
                "new line",
                "next line",
                "line break",
                "newline",
            ],
            replacement: "\u{E001}"
        ),
        Rule(phrases: ["start quotation marks", "starting quotation marks", "open quotation marks", "open quotation mark", "start quote", "begin quote", "open quote"], replacement: "\u{E002}"),
        Rule(phrases: ["end quotation marks", "ending quotation marks", "close quotation marks", "close quotation mark", "end quote", "close quote"], replacement: "\u{E003}"),
        Rule(phrases: ["open parenthesis", "open parentheses", "left parenthesis"], replacement: "\u{E004}"),
        Rule(phrases: ["close parenthesis", "close parentheses", "right parenthesis"], replacement: "\u{E005}"),
        Rule(phrases: ["question mark"], replacement: "\u{E006}"),
        Rule(phrases: ["exclamation point", "exclamation mark"], replacement: "\u{E007}"),
        Rule(phrases: ["semi colon", "semicolon"], replacement: "\u{E008}"),
        Rule(phrases: ["full stop", "period"], replacement: "\u{E009}"),
        Rule(phrases: ["ellipsis", "dot dot dot"], replacement: "\u{E00A}"),
        Rule(phrases: ["comma"], replacement: "\u{E00B}"),
        Rule(phrases: ["colon"], replacement: "\u{E00C}"),
        Rule(phrases: ["em dash", "long dash", "dash"], replacement: "\u{E00D}"),
        Rule(phrases: ["hyphen"], replacement: "\u{E00E}"),
    ]

    /// Invisible marker attached to punctuation produced by explicit spoken commands so the
    /// guarded punctuation pass can distinguish it from recognizer/model noise. Stripped from
    /// all output before text leaves this type.
    static let spokenMarker = "\u{FE00}"

    static func apply(to transcript: String) -> String {
        strippingSpokenMarkers(applyingSpokenCommands(to: transcript))
    }

    static func strippingSpokenMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: spokenMarker, with: "")
    }

    /// Joins independently transcribed audio chunks. Each recognizer adds terminal punctuation
    /// to its own chunk, so naive joining leaves stray `.`, `?`, and `,` artifacts mid-text.
    /// Interior punctuation is preserved; only boundary punctuation is removed so the guarded
    /// punctuation pass can repunctuate the whole transcript coherently.
    static func joiningChunks(_ parts: [String]) -> String {
        let boundaryPunctuation = CharacterSet(charactersIn: ".,;:!?…\"'”’()[]")
        var cleaned: [String] = []
        for (index, part) in parts.enumerated() {
            var text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if index > 0 {
                while let first = text.unicodeScalars.first, boundaryPunctuation.contains(first) {
                    text.removeFirst()
                }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if index < parts.count - 1 {
                while let last = text.unicodeScalars.last, boundaryPunctuation.contains(last) {
                    text.removeLast()
                }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !text.isEmpty {
                cleaned.append(text)
            }
        }
        return cleaned.joined(separator: " ")
    }

    static func applyingSpokenCommands(to transcript: String) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        var protectedLiterals: [(placeholder: String, value: String)] = []
        var literalIndex = 0
        for rule in rules {
            for phrase in rule.phrases {
                let placeholder = "\u{E100}\(literalIndex)\u{E101}"
                let literalPattern = phrasePattern("(?:literal|the word)\\s+\(escapedPhrase(phrase))")
                let updated = replacingMatches(in: text, pattern: literalPattern, with: placeholder)
                if updated != text {
                    protectedLiterals.append((placeholder, phrase))
                    text = updated
                }
                literalIndex += 1
            }
        }


        for rule in rules {
            let alternatives = rule.phrases.map(escapedPhrase).joined(separator: "|")
            text = replacingMatches(in: text, pattern: phrasePattern("(?:\(alternatives))"), with: rule.replacement)
        }

        text = replacingMatches(in: text, pattern: "[ \\t]+", with: " ")
        text = replacingMatches(in: text, pattern: "[ \\t]*\u{E000}[ \\t]*", with: "\n\n")
        text = replacingMatches(in: text, pattern: "[ \\t]*\u{E001}[ \\t]*", with: "\n")
        text = replacingMatches(in: text, pattern: "[ \\t]+([\u{E003}\u{E005}\u{E006}\u{E007}\u{E008}\u{E009}\u{E00A}\u{E00B}\u{E00C}])", with: "$1")
        text = replacingMatches(in: text, pattern: "([\u{E002}\u{E004}])[ \\t]+", with: "$1")
        text = replacingMatches(in: text, pattern: "[ \\t]*\u{E00E}[ \\t]*", with: "-")
        text = replacingMatches(in: text, pattern: "[ \\t]*\u{E00D}[ \\t]*", with: " — ")

        let replacements = [
            ("\u{E002}", "“"), ("\u{E003}", "”"),
            ("\u{E004}", "("), ("\u{E005}", ")"),
            ("\u{E006}", "?\(spokenMarker)"), ("\u{E007}", "!\(spokenMarker)"),
            ("\u{E008}", ";\(spokenMarker)"), ("\u{E009}", ".\(spokenMarker)"),
            ("\u{E00A}", "…\(spokenMarker)"), ("\u{E00B}", ",\(spokenMarker)"),
            ("\u{E00C}", ":\(spokenMarker)"),
        ]
        for (placeholder, value) in replacements {
            text = text.replacingOccurrences(of: placeholder, with: value)
        }
        for literal in protectedLiterals {
            text = text.replacingOccurrences(of: literal.placeholder, with: literal.value)
        }

        text = replacingMatches(in: text, pattern: "[ \\t]+([,.;:!?…”)])", with: "$1")
        text = replacingMatches(in: text, pattern: "([“(])[ \\t]+", with: "$1")
        text = replacingMatches(in: text, pattern: "[ \\t]{2,}", with: " ")
        text = replacingMatches(in: text, pattern: "[ \\t]*\\n[ \\t]*", with: "\n")
        text = replacingMatches(in: text, pattern: "\\n{3,}", with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func applyingSubstitutions(_ substitutions: [String: String], to transcript: String) -> String {
        var text = transcript
        for phrase in substitutions.keys.sorted(by: { $0.count > $1.count }) {
            guard let replacement = substitutions[phrase] else { continue }
            let template = NSRegularExpression.escapedTemplate(for: replacement)
            text = replacingMatches(in: text, pattern: substitutionPattern(phrase), with: template)
        }
        return text
    }

    /// Edge-Punct is trained on whitespace-separated, lowercase, unpunctuated transcript
    /// words. Feeding recognizer punctuation, casing, newlines, or explicit-command markers
    /// changes the whitespace tokens themselves and puts the model outside its input contract.
    /// This projection is only for the model; the original text remains the merge source so
    /// recognizer punctuation and explicit commands are still preserved as evidence.
    private static let punctuationModelTrimCharacters: CharacterSet = {
        var characters = CharacterSet.punctuationCharacters
        characters.insert(charactersIn: "\u{FE00}")
        return characters
    }()

    static func normalizingForPunctuationModel(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { token in
            let normalized = token.trimmingCharacters(in: punctuationModelTrimCharacters).lowercased()
            return normalized.isEmpty ? nil : normalized
        }.joined(separator: " ")
    }

    static func applyingAutomaticPunctuation(
        candidate: String,
        to original: String,
        trace: PunctuationLearning.Trace? = nil
    ) -> String {
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !proposed.isEmpty else {
            return enforcingLikelyQuestionTerminal(in: source, trace: trace)
        }

        let sourceWords = wordMatches(in: source)
        let proposedWords = wordMatches(in: proposed)
        guard !sourceWords.isEmpty, !proposedWords.isEmpty else {
            return enforcingLikelyQuestionTerminal(in: source, trace: trace)
        }
        let anchors = alignWords(source: sourceWords, candidate: proposedWords)

        // A small mismatch window is tolerated: the model may retokenize contractions or drop
        // filler, and the source is still the word of record. Larger divergences fall back to
        // sanitizing the source text itself so recognizer noise is never passed through raw.
        var mergedBoundaryWords: Set<Int> = []
        var accepted = restoringSourceFormatting(
            from: source,
            in: proposed,
            sourceWords: sourceWords,
            candidateWords: proposedWords,
            anchors: anchors,
            mergedBoundaryWords: &mergedBoundaryWords,
            trace: trace
        )
        let acceptedWords = wordMatches(in: accepted)
        if anchors.contains(nil) || acceptedWords.count != sourceWords.count {
            return enforcingLikelyQuestionTerminal(
                in: sanitizedSourceText(
                    source,
                    words: sourceWords,
                    mergedBoundaryWords: &mergedBoundaryWords,
                    trace: trace
                ),
                trace: trace
            )
        }
        for (index, pair) in zip(sourceWords, acceptedWords).enumerated().reversed()
            where pair.0.text != pair.1.text {
            let sourceWord = pair.0
            let acceptedWord = pair.1
            let sourceIsLowercase = sourceWord.text.rangeOfCharacter(from: .uppercaseLetters) == nil
            if sourceIsLowercase && isSentenceStart(wordIndex: index, words: acceptedWords, in: accepted) {
                continue
            }
            guard let range = Range(acceptedWord.range, in: accepted) else {
                return enforcingLikelyQuestionTerminal(
                    in: sanitizedSourceText(
                        source,
                        words: sourceWords,
                        mergedBoundaryWords: &mergedBoundaryWords,
                        trace: trace
                    ),
                    trace: trace
                )
            }
            if sourceWord.text.lowercased() == "i" {
                accepted.replaceSubrange(range, with: "I")
            } else {
                accepted.replaceSubrange(range, with: sourceWord.text)
            }
        }

        if !mergedBoundaryWords.isEmpty {
            // Words that followed a spurious terminator were capitalized as if they began a
            // sentence. Once the terminator is merged away, restore natural mid-clause casing.
            let currentWords = wordMatches(in: accepted)
            for index in mergedBoundaryWords.sorted(by: >) {
                guard index < currentWords.count else { continue }
                let word = currentWords[index]
                guard shouldLowercaseAfterMergedBoundary(word.text),
                      let range = Range(word.range, in: accepted) else { continue }
                accepted.replaceSubrange(range, with: word.text.lowercased())
            }
        }

        accepted = loweringMidClauseFunctionWords(in: accepted)
        return enforcingLikelyQuestionTerminal(in: accepted, trace: trace)
    }

    /// Greedy word alignment with a small skip window. Returns candidate indices per source
    /// word (nil when unmatched), resynchronizing when the model retokenizes or inserts words.
    private static func alignWords(
        source: [(text: String, range: NSRange)],
        candidate: [(text: String, range: NSRange)]
    ) -> [Int?] {
        var anchors = [Int?](repeating: nil, count: source.count)
        var i = 0
        var j = 0
        let maxSkip = 2
        while i < source.count, j < candidate.count {
            var matched = false
            for di in 0...maxSkip where i + di < source.count {
                for dj in 0...maxSkip where j + dj < candidate.count {
                    if source[i + di].text.compare(
                        candidate[j + dj].text,
                        options: .caseInsensitive
                    ) == .orderedSame {
                        i += di
                        j += dj
                        anchors[i] = j
                        i += 1
                        j += 1
                        matched = true
                        break
                    }
                }
                if matched { break }
            }
            if !matched { break }
        }
        return anchors
    }

    /// Applies the same interior-gap cleanup used by the guarded merge directly to the
    /// recognizer's own text, for cases where the model candidate is too divergent to merge.
    private static func sanitizedSourceText(
        _ source: String,
        words: [(text: String, range: NSRange)],
        mergedBoundaryWords: inout Set<Int>,
        trace: PunctuationLearning.Trace? = nil
    ) -> String {
        let result = NSMutableString(string: source)
        guard words.count > 1 else { return result as String }
        for index in stride(from: words.count - 2, through: 0, by: -1) {
            let gapRange = NSRange(
                location: NSMaxRange(words[index].range),
                length: words[index + 1].range.location - NSMaxRange(words[index].range)
            )
            let gap = result.substring(with: gapRange)
            guard !gap.contains(spokenMarker), containsPunctuation(gap) else { continue }
            if let sanitized = sanitizedSourceGap(
                gap,
                previousIndex: index,
                nextIndex: index + 1,
                words: words,
                in: result,
                mergedBoundaryWords: &mergedBoundaryWords,
                trace: trace
            ) {
                result.replaceCharacters(in: gapRange, with: sanitized)
            }
        }
        return result as String
    }

    /// Lowercases a short set of function words the recognizer capitalized mid-clause after a
    /// gap with no sentence terminator. Proper nouns, "I", and words after punctuation are
    /// untouched.
    private static func loweringMidClauseFunctionWords(in text: String) -> String {
        let lowercasedSet: Set<String> = [
            "and", "but", "or", "so", "then", "because", "although", "though",
            "while", "when", "where", "if", "unless", "until", "since", "as",
            "nor", "yet", "however", "therefore", "meanwhile", "otherwise",
            "instead", "also", "that", "which", "who", "whom", "whose", "of",
            "to", "in", "on", "at", "by", "for", "with", "from", "about",
            "into", "over", "under", "through", "during", "before", "after",
        ]
        let words = wordMatches(in: text)
        let nsText = text as NSString
        let result = NSMutableString(string: text)
        guard words.count > 1 else { return result as String }
        for index in stride(from: words.count - 1, through: 1, by: -1) {
            let word = words[index]
            guard word.text.rangeOfCharacter(from: .uppercaseLetters) != nil,
                  lowercasedSet.contains(word.text.lowercased()) else { continue }
            let gapRange = NSRange(
                location: NSMaxRange(words[index - 1].range),
                length: word.range.location - NSMaxRange(words[index - 1].range)
            )
            let gap = nsText.substring(with: gapRange)
            guard !containsPunctuation(gap) else { continue }
            result.replaceCharacters(in: word.range, with: word.text.lowercased())
        }
        return result as String
    }

    private static let singleWordSentenceAllowlist: Set<String> = [
        "yes", "no", "yeah", "nope", "ok", "okay", "sure", "right", "correct",
        "exactly", "absolutely", "definitely", "maybe", "perhaps", "thanks",
        "interesting", "agreed", "done", "go", "stop", "wait", "listen",
        "look", "see", "now", "then", "too", "one", "two", "three", "four",
        "five", "six", "seven", "eight", "nine", "ten", "first", "second",
        "third", "fourth", "fifth", "next", "finally", "lastly",
    ]

    private static let discourseMarkersBeforeComma: Set<String> = [
        "yes", "no", "yeah", "nope", "ok", "okay", "well", "now", "so",
        "right", "sure", "maybe", "perhaps", "however", "therefore", "actually",
        "basically", "literally", "honestly", "frankly", "instead", "otherwise",
        "meanwhile", "finally", "first", "second", "third", "lastly", "plus",
        "also", "too", "unfortunately", "luckily", "sadly", "clearly",
        "obviously", "interestingly", "importantly", "anyway", "anyways",
        "alright", "listen", "look",
    ]

    private static let clauseBoundaryAfterComma: Set<String> = [
        "if", "whether", "who", "whose", "whom", "which", "that", "because",
        "although", "though", "since", "while", "when", "whenever", "where",
        "wherever", "unless", "until", "before", "after", "as", "but", "and",
        "or", "nor", "yet", "so", "then", "however", "therefore", "meanwhile",
        "otherwise", "instead", "also", "plus",
    ]

    /// Words that cannot plausibly end a spoken clause. A stray terminator immediately after
    /// one of these is recognizer/model noise and is merged into the following clause.
    private static let clauseContinuationWords: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those",
        "my", "your", "his", "her", "its", "our", "their", "some", "any", "no",
        "each", "every", "either", "neither", "both", "few", "several", "many",
        "much", "more", "most", "less", "least", "enough",
        "of", "to", "in", "on", "at", "by", "for", "with", "about", "into",
        "onto", "over", "under", "between", "through", "during", "from", "up",
        "down", "off", "out", "against", "within", "without", "toward",
        "towards", "upon", "per", "via", "like",
        "and", "but", "or", "nor", "yet", "if", "because", "although",
        "while", "when", "whenever", "where", "wherever", "unless", "until",
        "whether", "whose", "which", "who", "whom", "what",
        "is", "are", "was", "were", "am", "be", "been", "being",
        "has", "have", "had", "do", "does", "did", "doing", "done",
        "can", "could", "will", "would", "shall", "should", "may", "might",
        "must", "not", "i", "it's", "that's", "there's", "he's", "she's",
        "we're", "they're", "you're", "i'm", "i've", "i'll", "i'd",
        "we've", "they've", "you've", "let's", "who's", "what's", "how's",
        "very", "really", "quite", "pretty", "just", "even", "still",
        "almost", "rather", "fairly", "too", "so", "such", "as", "than",
        "then", "also", "now", "here", "there",
    ]

    /// Degree adverbs that naturally attach forward. A short fragment ending in one of these
    /// (for example, "pretty much.") is a clipped phrase, not a sentence.
    private static let adverbialFragmentEndings: Set<String> = [
        "much", "basically", "literally", "honestly", "frankly", "actually",
        "simply", "merely", "really", "pretty", "quite", "sort", "kind",
        "so", "very", "too",
    ]

    /// Clauses that legitimately start with these words keep their terminator even when short
    /// and adverb-final ("Not much." or "Very well." must not merge forward).
    private static let clauseStatementOpeners: Set<String> = [
        "not", "no", "so", "very", "too", "that", "how", "thank", "thanks",
        "it's", "that's", "i", "i'm", "i've", "we", "we're", "they",
        "they're", "he", "she", "it", "this", "there", "well", "still",
        "almost", "all", "you",
    ]

    private static let questionStarters: Set<String> = [
        "who", "what", "when", "where", "why", "how", "which", "whose", "whom",
    ]

    private static let questionAuxiliaries: Set<String> = [
        "is", "are", "am", "was", "were", "do", "does", "did", "can", "could",
        "should", "would", "will", "shall", "may", "might", "must", "have",
        "has", "had",
    ]

    private static let questionSubjects: Set<String> = [
        "you", "we", "they", "i", "he", "she", "there", "anyone", "everyone",
        "somebody", "someone", "everybody", "nobody",
    ]

    /// Embedded-question verbs only count in their imperative forms ("check if", "find out
    /// whether", "tell me if"). Statements like "I wonder how", "I know why", and "let's see
    /// if" are excluded — only command-form embedded questions keep a question mark.
    private static let embeddedQuestionPattern =
        "(?i)\\b(?:check|determine|verify)\\s+(?:if|whether|who|what|when|where|why|how|which)\\b"
        + "|\\b(?:find\\s+out|tell\\s+me)\\s+(?:if|whether)\\b"

    private static let sentenceTerminators = CharacterSet(charactersIn: ".!?…\n")
    private static let gapSkippables = CharacterSet(charactersIn: " \t\r\n“”\"'()[]{}\u{FE00}")

    /// Rebuilds the merged transcript from source words. Interior gaps prefer the model's
    /// punctuation when the adjacent words anchor to consecutive candidate words; recognizer
    /// gaps are sanitized rather than copied verbatim. Returns the source text unchanged when
    /// the alignment cannot cover a gap.
    private static func restoringSourceFormatting(
        from source: String,
        in candidate: String,
        sourceWords: [(text: String, range: NSRange)],
        candidateWords: [(text: String, range: NSRange)],
        anchors: [Int?],
        mergedBoundaryWords: inout Set<Int>,
        trace: PunctuationLearning.Trace? = nil
    ) -> String {
        let sourceText = source as NSString
        let candidateText = candidate as NSString

        func candidateGap(between left: Int, and right: Int) -> String {
            let range = NSRange(
                location: NSMaxRange(candidateWords[left].range),
                length: candidateWords[right].range.location - NSMaxRange(candidateWords[left].range)
            )
            return candidateText.substring(with: range)
        }

        let result = NSMutableString(capacity: candidate.count)

        let sourcePrefixRange = NSRange(location: 0, length: sourceWords[0].range.location)
        result.append(sourceText.substring(with: sourcePrefixRange))
        result.append(candidateWordText(for: 0, sourceWords: sourceWords, candidateWords: candidateWords, anchors: anchors))

        for index in stride(from: 0, to: sourceWords.count - 1, by: 1) {
            let sourceGapRange = NSRange(
                location: NSMaxRange(sourceWords[index].range),
                length: sourceWords[index + 1].range.location - NSMaxRange(sourceWords[index].range)
            )
            let sourceGap = sourceText.substring(with: sourceGapRange)

            // Explicit spoken punctuation commands are never sanitized.
            if sourceGap.contains(spokenMarker) {
                result.append(sourceGap)
            } else if containsPunctuation(sourceGap) {
                if let sanitized = sanitizedSourceGap(
                    sourceGap,
                    previousIndex: index,
                    nextIndex: index + 1,
                    words: sourceWords,
                    in: sourceText,
                    mergedBoundaryWords: &mergedBoundaryWords,
                    trace: trace
                ) {
                    result.append(sanitized)
                } else {
                    result.append(sourceGap)
                }
            } else {
                let newlineCount = sourceGap.filter { $0 == "\n" }.count
                if newlineCount > 0 {
                    var merged = ""
                    if let left = anchors[index], let right = anchors[index + 1],
                       right == left + 1 {
                        merged = candidateGap(between: left, and: right)
                        while let last = merged.last,
                              last == " " || last == "\t" || last == "\r" || last == "\n" {
                            merged.removeLast()
                        }
                    }
                    merged += newlineCount > 1 ? "\n\n" : "\n"
                    result.append(merged)
                } else if let left = anchors[index], let right = anchors[index + 1],
                          right == left + 1 {
                    let gap = candidateGap(between: left, and: right)
                    if let sanitized = sanitizedCandidateGap(
                        gap,
                        previousIndex: left,
                        nextIndex: right,
                        words: candidateWords,
                        in: candidateText,
                        trace: trace
                    ) {
                        if sanitized == " ", gap.range(of: "[.!?…]", options: .regularExpression) != nil {
                            mergedBoundaryWords.insert(index + 1)
                        }
                        result.append(sanitized)
                    } else {
                        result.append(gap)
                    }
                } else {
                    result.append(" ")
                }
            }

            result.append(candidateWordText(for: index + 1, sourceWords: sourceWords, candidateWords: candidateWords, anchors: anchors))
        }

        let sourceSuffixRange = NSRange(
            location: NSMaxRange(sourceWords.last!.range),
            length: sourceText.length - NSMaxRange(sourceWords.last!.range)
        )
        let sourceSuffix = sourceText.substring(with: sourceSuffixRange)
        if let lastAnchor = anchors[sourceWords.count - 1], lastAnchor == candidateWords.count - 1,
           !containsPunctuation(sourceSuffix) {
            let candidateSuffixRange = NSRange(
                location: NSMaxRange(candidateWords.last!.range),
                length: candidateText.length - NSMaxRange(candidateWords.last!.range)
            )
            // Symbols such as `++` are not punctuation, but they are still meaningful source
            // text. Preserve them and then accept the model's terminal punctuation.
            result.append(sourceSuffix)
            result.append(candidateText.substring(with: candidateSuffixRange))
        } else {
            result.append(sourceSuffix)
        }

        return result as String
    }

    private static func candidateWordText(
        for sourceIndex: Int,
        sourceWords: [(text: String, range: NSRange)],
        candidateWords: [(text: String, range: NSRange)],
        anchors: [Int?]
    ) -> String {
        if let anchored = anchors[sourceIndex] {
            return candidateWords[anchored].text
        }
        return sourceWords[sourceIndex].text
    }

    /// Sanitizes a model-proposed gap. Returns a replacement gap, or nil to keep the
    /// candidate gap unchanged. Model `?`/`!` are demoted to `.` unless the preceding clause
    /// is question-shaped, and stray terminators after continuation words are merged away.
    private static func sanitizedCandidateGap(
        _ gap: String,
        previousIndex: Int,
        nextIndex: Int,
        words: [(text: String, range: NSRange)],
        in candidate: NSString,
        trace: PunctuationLearning.Trace? = nil
    ) -> String? {
        let trimmed = gap.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        func record(_ action: String, learned: Bool = false) {
            trace?.record(.init(
                gap: "model",
                terminator: firstTerminator(in: trimmed),
                previous: words[previousIndex].text.lowercased(),
                next: words[nextIndex].text.lowercased(),
                clauseFirst: words[clauseStartIndex(before: previousIndex, words: words, in: candidate)].text.lowercased(),
                shaped: clauseIsQuestionShaped(precedingWordIndex: previousIndex, words: words, in: candidate),
                action: action,
                learned: learned
            ))
        }

        if trimmed.range(of: "[.!?…]", options: .regularExpression) != nil {
            switch shouldMergeTerminatorGap(
                previousIndex: previousIndex,
                terminator: firstTerminator(in: trimmed),
                words: words,
                in: candidate
            ) {
            case .merge(let learned):
                record("merge", learned: learned)
                return " "
            case .keep(let learned):
                record("keep", learned: learned)
                return nil
            case .undecided:
                break
            }
            if trimmed.hasPrefix("."),
               !trimmed.contains("!"), !trimmed.contains("?"), !trimmed.contains("…"),
               isOneWordSentenceEnding(at: previousIndex, words: words, in: candidate),
               !keepsSingleWordSentence(words[previousIndex].text) {
                record("merge")
                return " "
            }
            let shaped = clauseIsQuestionShaped(
                precedingWordIndex: previousIndex,
                words: words,
                in: candidate
            )
            if let rebuilt = rebuiltTerminatorGap(trimmed, questionShaped: shaped) {
                record(rebuilt.contains("?") && !trimmed.contains("?") ? "promote" : "demote")
                return rebuilt + " "
            }
            record("keep")
            return nil
        }

        if trimmed.contains(",") {
            if keepsModelComma(
                previousText: words[previousIndex].text,
                nextIndex: nextIndex,
                words: words,
                in: candidate
            ) {
                record("keep")
                return nil
            }
            record("space")
            return " "
        }

        return nil
    }

    /// Sanitizes a recognizer-provided gap. Returns a replacement gap, or nil to keep the
    /// source gap verbatim. Explicit spoken punctuation never reaches this function; only
    /// recognizer-added interior punctuation is filtered here.
    private static func sanitizedSourceGap(
        _ sourceGap: String,
        previousIndex: Int,
        nextIndex: Int,
        words: [(text: String, range: NSRange)],
        in sourceText: NSString,
        mergedBoundaryWords: inout Set<Int>,
        trace: PunctuationLearning.Trace? = nil
    ) -> String? {
        let trimmed = sourceGap.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sourceGap }

        if trimmed.contains("\n") { return nil }

        func record(_ action: String, learned: Bool = false) {
            trace?.record(.init(
                gap: "source",
                terminator: firstTerminator(in: trimmed),
                previous: words[previousIndex].text.lowercased(),
                next: words[nextIndex].text.lowercased(),
                clauseFirst: words[clauseStartIndex(before: previousIndex, words: words, in: sourceText)].text.lowercased(),
                shaped: clauseIsQuestionShaped(precedingWordIndex: previousIndex, words: words, in: sourceText),
                action: action,
                learned: learned
            ))
        }

        if trimmed.range(of: "[.!?…]", options: .regularExpression) != nil {
            switch shouldMergeTerminatorGap(
                previousIndex: previousIndex,
                terminator: firstTerminator(in: trimmed),
                words: words,
                in: sourceText
            ) {
            case .merge(let learned):
                mergedBoundaryWords.insert(nextIndex)
                record("merge", learned: learned)
                return " "
            case .keep(let learned):
                record("keep", learned: learned)
                return nil
            case .undecided:
                break
            }
            let shaped = clauseIsQuestionShaped(
                precedingWordIndex: previousIndex,
                words: words,
                in: sourceText
            )
            if let rebuilt = rebuiltTerminatorGap(trimmed, questionShaped: shaped) {
                record(rebuilt.contains("?") && !trimmed.contains("?") ? "promote" : "demote")
                return rebuilt + " "
            }
            record("keep")
            return nil
        }

        if trimmed.contains(",") {
            if keepsModelComma(
                previousText: words[previousIndex].text,
                nextIndex: nextIndex,
                words: words,
                in: sourceText
            ) {
                record("keep")
                return nil
            }
            record("space")
            return " "
        }

        return nil
    }

    /// Three-way merge verdict. `learned` marks verdicts driven by the per-user policy
    /// rather than the static heuristics.
    private enum TerminatorVerdict {
        case merge(learned: Bool)
        case keep(learned: Bool)
        case undecided
    }

    /// Decides whether a terminator after this word is clipped recognizer/model noise. The
    /// learned per-user policy votes first when it has strong evidence; the heuristic sets
    /// (continuation words, statement openers, adverbial fragments) remain the fallback.
    private static func shouldMergeTerminatorGap(
        previousIndex: Int,
        terminator: String,
        words: [(text: String, range: NSRange)],
        in text: NSString
    ) -> TerminatorVerdict {
        let previousWord = words[previousIndex].text.lowercased()
        let clauseStart = clauseStartIndex(before: previousIndex, words: words, in: text)
        let clauseCount = previousIndex - clauseStart + 1

        let clauseShaped = clauseIsQuestionShaped(
            precedingWordIndex: previousIndex,
            words: words,
            in: text
        )
        if !terminator.isEmpty,
           let vote = PunctuationLearning.Policy.shared.vote(
               terminator: terminator,
               previousWord: previousWord,
               nextWord: words[previousIndex + 1].text.lowercased(),
               clauseFirst: words[clauseStart].text.lowercased(),
               shaped: clauseShaped
           ) {
            return vote ? .merge(learned: true) : .keep(learned: true)
        }

        // Short clauses (2–4 words) that legitimately start with a statement opener keep
        // their terminator: "Not much.", "Very well.", "I don't think so." must not merge
        // forward even though the final word also appears in the continuation/adverb sets.
        // One-word clauses ("I.", "You.") are almost always clipped noise and may merge.
        if clauseCount >= 2, clauseCount <= 4,
           clauseStatementOpeners.contains(words[clauseStart].text.lowercased()),
           adverbialFragmentEndings.contains(previousWord)
               || clauseContinuationWords.contains(previousWord) {
            return .keep(learned: false)
        }

        if clauseContinuationWords.contains(previousWord) {
            return .merge(learned: false)
        }

        guard clauseCount <= 3,
              adverbialFragmentEndings.contains(previousWord)
        else {
            return .undecided
        }

        if clauseCount == 3 {
            let qualifiers: Set<String> = [
                "pretty", "very", "really", "quite", "so", "too", "rather",
                "fairly", "that", "how", "this", "still", "almost", "just",
            ]
            guard qualifiers.contains(words[clauseStart + 1].text.lowercased()) else {
                return .undecided
            }
        }
        return .merge(learned: false)
    }

    private static func firstTerminator(in gap: String) -> String {
        gap.first { ".!?…".contains($0) }.map(String.init) ?? ""
    }

    private static func clauseStartIndex(
        before wordIndex: Int,
        words: [(text: String, range: NSRange)],
        in text: NSString
    ) -> Int {
        guard wordIndex > 0 else { return 0 }
        for earlier in stride(from: wordIndex - 1, through: 0, by: -1) {
            let gapRange = NSRange(
                location: NSMaxRange(words[earlier].range),
                length: words[earlier + 1].range.location - NSMaxRange(words[earlier].range)
            )
            let gap = text.substring(with: gapRange)
            if gap.range(of: "[.!?…\\n]", options: .regularExpression) != nil {
                return earlier + 1
            }
        }
        return 0
    }

    /// Rebuilds a gap's terminator run from its clause shape. `?`/`!` become `.` when the
    /// preceding clause is not question-shaped; `.` becomes `?` when it is. Returns nil when
    /// nothing changes.
    private static func rebuiltTerminatorGap(_ trimmedGap: String, questionShaped: Bool) -> String? {
        var result = ""
        var changed = false
        var previousWasPeriod = false
        for scalarView in trimmedGap.unicodeScalars {
            let scalar = Character(scalarView)
            if scalar == "?" || scalar == "!" {
                if questionShaped {
                    result.append("?")
                } else {
                    result.append(".")
                    changed = true
                }
                previousWasPeriod = false
            } else if scalar == "." {
                if questionShaped && !previousWasPeriod {
                    result.append("?")
                    changed = true
                } else {
                    result.append(".")
                }
                previousWasPeriod = true
            } else {
                result.append(scalar)
            }
        }
        return changed ? result : nil
    }

    private static func clauseIsQuestionShaped(
        precedingWordIndex: Int,
        words: [(text: String, range: NSRange)],
        in text: NSString
    ) -> Bool {
        let start = clauseStartIndex(before: precedingWordIndex, words: words, in: text)
        let clauseWords = (start...precedingWordIndex).map { words[$0].text.lowercased() }
        return clauseWordsAreQuestionShaped(clauseWords)
    }

    private static func shouldLowercaseAfterMergedBoundary(_ word: String) -> Bool {
        if word == "I" || word.hasPrefix("I'") || word.hasPrefix("i'") { return false }
        for scalar in word.dropFirst().unicodeScalars where CharacterSet.uppercaseLetters.contains(scalar) {
            return false
        }
        return word != word.lowercased()
    }

    private static func keepsSingleWordSentence(_ previousText: String) -> Bool {
        singleWordSentenceAllowlist.contains(previousText.lowercased())
    }

    private static func isOneWordSentenceEnding(
        at wordIndex: Int,
        words: [(text: String, range: NSRange)],
        in candidate: NSString
    ) -> Bool {
        if wordIndex == 0 { return true }
        let gapRange = NSRange(
            location: NSMaxRange(words[wordIndex - 1].range),
            length: words[wordIndex].range.location - NSMaxRange(words[wordIndex - 1].range)
        )
        let gap = candidate.substring(with: gapRange)
        return gap.range(of: "[.!?…\\n]", options: .regularExpression) != nil
    }

    private static func keepsModelComma(
        previousText: String,
        nextIndex: Int,
        words: [(text: String, range: NSRange)],
        in candidate: NSString
    ) -> Bool {
        if discourseMarkersBeforeComma.contains(previousText.lowercased()) {
            return true
        }
        let nextText = words[nextIndex].text.lowercased()
        if clauseBoundaryAfterComma.contains(nextText) {
            return true
        }
        return isEnumerationComma(wordRange: words[nextIndex].range, in: candidate)
    }

    private static func isEnumerationComma(
        wordRange: NSRange,
        in candidate: NSString
    ) -> Bool {
        var start = wordRange.location
        while start > 0 {
            let scalar = candidate.character(at: start - 1)
            if sentenceTerminators.contains(UnicodeScalar(scalar)!) { break }
            start -= 1
        }
        var end = NSMaxRange(wordRange)
        while end < candidate.length {
            let scalar = candidate.character(at: end)
            if sentenceTerminators.contains(UnicodeScalar(scalar)!) { break }
            end += 1
        }
        guard end > start else { return false }
        let sentence = candidate.substring(with: NSRange(location: start, length: end - start))
        // A ", and"/", or" that opens a verb clause ("kind of thinking behind that, or are
        // you…") is not a list; only keep the comma when a noun-like word follows.
        if let match = sentence.range(
            of: ",\\s+(?:and|or)\\s+([\\p{L}\\p{N}]+)",
            options: .regularExpression
        ) {
            let followingWord = String(sentence[match]).components(
                separatedBy: CharacterSet.alphanumerics.inverted
            ).filter { !$0.isEmpty }.last?.lowercased() ?? ""
            let nonNounFollowers: Set<String> = [
                "is", "are", "am", "was", "were", "do", "does", "did", "can", "could",
                "will", "would", "shall", "should", "may", "might", "must", "have",
                "has", "had", "you", "we", "they", "i", "he", "she", "it", "there",
                "not",
            ]
            if nonNounFollowers.contains(followingWord) {
                return false
            }
            return true
        }
        return false
    }

    private static func isSentenceStart(
        wordIndex: Int,
        words: [(text: String, range: NSRange)],
        in text: String
    ) -> Bool {
        if wordIndex == 0 { return true }
        let nsText = text as NSString
        var location = words[wordIndex].range.location
        while location > 0 {
            let scalar = nsText.character(at: location - 1)
            guard let unicode = UnicodeScalar(scalar) else { return false }
            if sentenceTerminators.contains(unicode) { return true }
            if gapSkippables.contains(unicode) {
                location -= 1
                continue
            }
            return false
        }
        return true
    }

    private static func substitutionPattern(_ phrase: String) -> String {
        "(?i)(?<![\\p{L}\\p{N}])\(escapedPhrase(phrase))(?![\\p{L}\\p{N}])"
    }

    private static func containsPunctuation(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.punctuationCharacters.contains($0) }
    }

    private static let wordExpression = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")

    private static func wordMatches(in text: String) -> [(text: String, range: NSRange)] {
        guard let expression = wordExpression else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (String(text[range]), match.range)
        }
    }

    private static func enforcingLikelyQuestionTerminal(
        in text: String,
        trace: PunctuationLearning.Trace? = nil
    ) -> String {
        // Whether the final terminator came from an explicit spoken command (never touched).
        var terminalIsSpoken = false
        var seenPunctuation = false
        outer: for scalar in text.unicodeScalars.reversed() {
            switch scalar {
            case "\u{FE00}":
                if seenPunctuation {
                    terminalIsSpoken = true
                    break outer
                }
            case ".", "?", "!", "…":
                seenPunctuation = true
            case " ", "\t", "\r", "\n", "”", "’", "\"", "'", "(", ")", "[", "]", "“":
                continue
            default:
                break outer
            }
        }

        let stripped = strippingSpokenMarkers(text)
        let questionPatterns = [
            #"(?i)^\s*(?:who|what|when|where|why|how|which|whose|whom|is|are|am|was|were|do|does|did|can|could|should|would|will|have|has|had|may|might|must)\b"#,
            embeddedQuestionPattern,
        ]
        let finalClause = stripped.split(
            omittingEmptySubsequences: true,
            whereSeparator: { ".!?…".contains($0) }
        ).last.map(String.init) ?? stripped

        let regexShaped = questionPatterns.contains {
            finalClause.range(of: $0, options: .regularExpression) != nil
        }
        let clauseWords = wordMatches(in: finalClause).map { $0.text.lowercased() }
        let shaped = regexShaped || clauseWordsAreQuestionShaped(clauseWords)

        let finalWords = wordMatches(in: finalClause)

        if let terminal = stripped.range(of: #"[.!?…]+(?=[”’"')\]]*\s*$)"#, options: .regularExpression) {
            func record(_ action: String) {
                trace?.record(.init(
                    gap: "terminal",
                    terminator: String(stripped[terminal].first ?? "."),
                    previous: finalWords.last?.text.lowercased() ?? "",
                    next: "",
                    clauseFirst: finalWords.first?.text.lowercased() ?? "",
                    shaped: shaped,
                    action: action,
                    learned: false
                ))
            }
            if shaped {
                if terminalIsSpoken {
                    record("keep")
                    return stripped
                }
                var updated = stripped
                updated.replaceSubrange(terminal, with: "?")
                record("promote")
                return updated
            }
            if !terminalIsSpoken,
               stripped[terminal].contains(where: { $0 == "?" || $0 == "!" }) {
                // A recognizer/model question or exclamation mark on a non-question clause is
                // noise; demote the run to a period.
                var updated = stripped
                updated.replaceSubrange(terminal, with: ".")
                record("demote")
                return updated
            }
            record("keep")
            return stripped
        }
        if shaped {
            return stripped + "?"
        }
        if stripped.range(
            of: #"[,;:…”’"')\]\s]$"#,
            options: .regularExpression
        ) == nil {
            // Recognizer text that ends on a bare word gets a period; dictation output should
            // not trail off unpunctuated.
            return stripped + "."
        }
        return stripped
    }

    private static func clauseWordsAreQuestionShaped(_ clauseWords: [String]) -> Bool {
        guard let first = clauseWords.first else { return false }
        if questionStarters.contains(first) || questionAuxiliaries.contains(first) {
            return true
        }
        for pair in zip(clauseWords, clauseWords.dropFirst()) {
            if questionStarters.contains(pair.0), questionAuxiliaries.contains(pair.1) {
                return true
            }
            if questionAuxiliaries.contains(pair.0), questionSubjects.contains(pair.1) {
                return true
            }
        }
        return clauseWords
            .joined(separator: " ")
            .range(of: embeddedQuestionPattern, options: .regularExpression) != nil
    }

    private static func escapedPhrase(_ phrase: String) -> String {
        NSRegularExpression.escapedPattern(for: phrase).replacingOccurrences(of: "\\ ", with: "\\s+")
    }

    private static func phrasePattern(_ phrase: String) -> String {
        "(?i)(?<![\\p{L}\\p{N}])\(phrase)(?![\\p{L}\\p{N}])(?:[,.])?"
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
