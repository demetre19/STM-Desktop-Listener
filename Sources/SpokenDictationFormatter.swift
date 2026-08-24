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

        var accepted = proposed
        for (sourceWord, proposedWord) in zip(sourceWords, proposedWords).reversed()
            where sourceWord.text.rangeOfCharacter(from: .uppercaseLetters) != nil {
            guard let range = Range(proposedWord.range, in: accepted) else {
                return enforcingLikelyQuestionTerminal(in: source)
            }
            accepted.replaceSubrange(range, with: sourceWord.text)
        }
        accepted = restoringSourceFormatting(
            from: source,
            in: accepted,
            sourceWords: sourceWords,
            candidateWords: proposedWords
        )
        return enforcingLikelyQuestionTerminal(in: accepted)
    }

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
                guard newlineCount > 0 else { continue }
                var candidateGap = result.substring(with: candidateGapRange)
                while let last = candidateGap.last,
                      last == " " || last == "\t" || last == "\r" || last == "\n" {
                    candidateGap.removeLast()
                }
                candidateGap += newlineCount > 1 ? "\n\n" : "\n"
                result.replaceCharacters(in: candidateGapRange, with: candidateGap)
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
