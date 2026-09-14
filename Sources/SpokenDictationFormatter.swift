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

    static func apply(to transcript: String) -> String {
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
            ("\u{E006}", "?"), ("\u{E007}", "!"),
            ("\u{E008}", ";"), ("\u{E009}", "."),
            ("\u{E00A}", "…"), ("\u{E00B}", ","),
            ("\u{E00C}", ":"),
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

    static func applyingAutomaticPunctuation(candidate: String, to original: String) -> String {
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !proposed.isEmpty else { return source }

        let sourceWords = wordMatches(in: source)
        let proposedWords = wordMatches(in: proposed)
        guard sourceWords.count == proposedWords.count else {
            return enforcingLikelyQuestionTerminal(in: source)
        }
        for (sourceWord, proposedWord) in zip(sourceWords, proposedWords) {
            guard sourceWord.text.compare(proposedWord.text, options: .caseInsensitive) == .orderedSame else {
                return enforcingLikelyQuestionTerminal(in: source)
            }
        }

        var accepted = restoringSourceFormatting(
            from: source,
            in: proposed,
            sourceWords: sourceWords,
            candidateWords: proposedWords
        )
        let acceptedWords = wordMatches(in: accepted)
        guard acceptedWords.count == sourceWords.count else {
            return enforcingLikelyQuestionTerminal(in: source)
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
                return enforcingLikelyQuestionTerminal(in: source)
            }
            if sourceWord.text.lowercased() == "i" {
                accepted.replaceSubrange(range, with: "I")
            } else {
                accepted.replaceSubrange(range, with: sourceWord.text)
            }
        }
        return enforcingLikelyQuestionTerminal(in: accepted)
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

    private static let sentenceTerminators = CharacterSet(charactersIn: ".!?…\n")
    private static let gapSkippables = CharacterSet(charactersIn: " \t\r\n“”\"'()[]{}")

    private static func restoringSourceFormatting(
        from source: String,
        in candidate: String,
        sourceWords: [(text: String, range: NSRange)],
        candidateWords: [(text: String, range: NSRange)]
    ) -> String {
        guard !sourceWords.isEmpty, sourceWords.count == candidateWords.count else { return candidate }

        let sourceText = source as NSString
        let result = NSMutableString(string: candidate)

        let sourceSuffixRange = NSRange(
            location: NSMaxRange(sourceWords.last!.range),
            length: sourceText.length - NSMaxRange(sourceWords.last!.range)
        )
        let sourceSuffix = sourceText.substring(with: sourceSuffixRange)
        if containsPunctuation(sourceSuffix) {
            let candidateSuffixRange = NSRange(
                location: NSMaxRange(candidateWords.last!.range),
                length: result.length - NSMaxRange(candidateWords.last!.range)
            )
            result.replaceCharacters(in: candidateSuffixRange, with: sourceSuffix)
        }

        if sourceWords.count > 1 {
            for index in stride(from: sourceWords.count - 2, through: 0, by: -1) {
                let sourceGapRange = NSRange(
                    location: NSMaxRange(sourceWords[index].range),
                    length: sourceWords[index + 1].range.location - NSMaxRange(sourceWords[index].range)
                )
                let sourceGap = sourceText.substring(with: sourceGapRange)
                let candidateGapRange = NSRange(
                    location: NSMaxRange(candidateWords[index].range),
                    length: candidateWords[index + 1].range.location - NSMaxRange(candidateWords[index].range)
                )

                if containsPunctuation(sourceGap) {
                    result.replaceCharacters(in: candidateGapRange, with: sourceGap)
                    continue
                }

                let newlineCount = sourceGap.filter { $0 == "\n" }.count
                if newlineCount > 0 {
                    var candidateGap = result.substring(with: candidateGapRange)
                    while let last = candidateGap.last,
                          last == " " || last == "\t" || last == "\r" || last == "\n" {
                        candidateGap.removeLast()
                    }
                    candidateGap += newlineCount > 1 ? "\n\n" : "\n"
                    result.replaceCharacters(in: candidateGapRange, with: candidateGap)
                    continue
                }

                if let sanitized = sanitizedCandidateGap(
                    result,
                    gapRange: candidateGapRange,
                    previousIndex: index,
                    nextIndex: index + 1,
                    words: candidateWords
                ) {
                    result.replaceCharacters(in: candidateGapRange, with: sanitized)
                }
            }
        }

        let sourcePrefixRange = NSRange(location: 0, length: sourceWords[0].range.location)
        let sourcePrefix = sourceText.substring(with: sourcePrefixRange)
        if containsPunctuation(sourcePrefix) {
            let candidatePrefixRange = NSRange(location: 0, length: candidateWords[0].range.location)
            result.replaceCharacters(in: candidatePrefixRange, with: sourcePrefix)
        }

        return result as String
    }

    private static func sanitizedCandidateGap(
        _ candidate: NSMutableString,
        gapRange: NSRange,
        previousIndex: Int,
        nextIndex: Int,
        words: [(text: String, range: NSRange)]
    ) -> String? {
        let gap = candidate.substring(with: gapRange)
        let trimmed = gap.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.range(of: "[.!?…]", options: .regularExpression) != nil {
            if trimmed.hasPrefix("."),
               !trimmed.contains("!"), !trimmed.contains("?"), !trimmed.contains("…"),
               isOneWordSentenceEnding(at: previousIndex, words: words, in: candidate),
               !keepsSingleWordSentence(words[previousIndex].text) {
                return " "
            }
            return nil
        }

        if trimmed.contains(",") {
            if keepsModelComma(
                previousText: words[previousIndex].text,
                nextIndex: nextIndex,
                words: words,
                in: candidate
            ) {
                return nil
            }
            return " "
        }

        return nil
    }

    private static func keepsSingleWordSentence(_ previousText: String) -> Bool {
        singleWordSentenceAllowlist.contains(previousText.lowercased())
    }

    private static func isOneWordSentenceEnding(
        at wordIndex: Int,
        words: [(text: String, range: NSRange)],
        in candidate: NSMutableString
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
        in candidate: NSMutableString
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
        in candidate: NSMutableString
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
        return sentence.range(of: ",\\s+(?:and|or)\\b", options: .regularExpression) != nil
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

    private static func wordMatches(in text: String) -> [(text: String, range: NSRange)] {
        guard let expression = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]+") else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (String(text[range]), match.range)
        }
    }

    private static func enforcingLikelyQuestionTerminal(in text: String) -> String {
        let questionPatterns = [
            #"(?i)^\s*(?:who|what|when|where|why|how|which|whose|whom|is|are|am|was|were|do|does|did|can|could|should|would|will|have|has|had|may|might|must)\b"#,
            #"(?i)\b(?:check|see|determine|verify|find\s+out|tell\s+me)\s+(?:if|whether|who|what|when|where|why|how|which)\b"#,
        ]
        let finalClause = text.split(
            omittingEmptySubsequences: true,
            whereSeparator: { ".!?…".contains($0) }
        ).last.map(String.init) ?? text
        guard questionPatterns.contains(where: { finalClause.range(of: $0, options: .regularExpression) != nil }) else {
            return text
        }
        if let terminal = text.range(of: #"[.!?…]+(?=[”’"')\]]*\s*$)"#, options: .regularExpression) {
            var updated = text
            updated.replaceSubrange(terminal, with: "?")
            return updated
        }
        return text + "?"
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
