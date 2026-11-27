#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct SpokenDictationFormatterTests {
    static func main() {
        let cases: [(name: String, input: String, expected: String)] = [
            ("comma", "Hello comma world", "Hello, world"),
            ("sentence punctuation", "Are you there question mark Yes exclamation point", "Are you there? Yes!"),
            ("new line", "First line new line Second line", "First line\nSecond line"),
            ("quiet marker does not split new line command", "First line new\u{200B} line Second line", "First line\nSecond line"),
            ("newline", "First line newline Second line", "First line\nSecond line"),
            ("go to a new line", "First line go to a new line Second line", "First line\nSecond line"),
            ("start a new line", "First line start a new line Second line", "First line\nSecond line"),
            ("literal newline", "Use the word newline in the instructions", "Use newline in the instructions"),
            ("new paragraph", "First paragraph new paragraph Second paragraph", "First paragraph\n\nSecond paragraph"),
            ("quotation marks", "She said start quotation marks hello comma world end quotation marks period", "She said “hello, world”."),
            ("filler words preserved", "She said uh starting quotation marks hello ending quotation marks", "She said uh “hello”"),
            ("parentheses", "Use open parenthesis optional close parenthesis values", "Use (optional) values"),
            ("dash and hyphen", "one dash two and up hyphen to hyphen date", "one — two and up-to-date"),
            ("colon and semicolon", "Items colon one semicolon two", "Items: one; two"),
            ("ellipsis", "Wait dot dot dot what", "Wait… what"),
            ("literal command word", "Use the word comma in the label", "Use comma in the label"),
            ("ordinary words unchanged", "The command line is ready.", "The command line is ready."),
            (
                "exact website query is never rewritten",
                "I want you to check if the website has an SMTP provider set up like Mailgun?",
                "I want you to check if the website has an SMTP provider set up like Mailgun?"
            ),
        ]
        let automaticCases: [(name: String, original: String, candidate: String, expected: String)] = [
            (
                "actual website query transcript gets a question mark",
                "I want you to check if the website has an SMTP provider set up like Mailgun.",
                "I want you to check if the website has an SMTP provider set up like MAILGUN.",
                "I want you to check if the website has an SMTP provider set up like Mailgun?"
            ),
            (
                "local model punctuation and capitalization",
                "how are you i am fine thank you",
                "How are you? I am fine. Thank you.",
                "How are you? I am fine. Thank you."
            ),
            (
                "candidate word rewrite is rejected",
                "Please send the report.",
                "Please email the report.",
                "Please send the report."
            ),
            (
                "model-added mid-sentence capitals are reverted",
                "i don't want to open another YouTube panel",
                "I. Don't want to open another, YouTube, panel.",
                "I don't want to open another YouTube panel."
            ),
            (
                "model-added comma mid-clause is dropped",
                "i want it inside the one that already exists",
                "I want it, inside the one that already exists.",
                "I want it inside the one that already exists."
            ),
            (
                "model-added comma before subordinator is kept",
                "tell me when it is done",
                "Tell me, when it is done.",
                "Tell me, when it is done."
            ),
            (
                "enumeration commas are kept",
                "i need apples oranges and pears",
                "I need apples, oranges, and pears.",
                "I need apples, oranges, and pears."
            ),
            (
                "discourse marker comma is kept",
                "yes i agree with that",
                "Yes, I agree with that.",
                "Yes, I agree with that."
            ),
            (
                "one-word sentence allowlist keeps period",
                "yes that is right",
                "Yes. That is right.",
                "Yes. That is right."
            ),
            (
                "question words still get question mark",
                "can you do an audit on the voice processing part",
                "Can, You do an audit on the, voice, processing part.",
                "Can you do an audit on the voice processing part?"
            ),
            (
                "recognizer question mark after a continuation word is merged",
                "everything has a? in weird places",
                "Everything has a? In weird places.",
                "Everything has a in weird places."
            ),
            (
                "recognizer period after a degree adverb fragment is merged",
                "the punctuation is weird. pretty much. everything is wrong.",
                "The punctuation is weird. Pretty much. Everything is wrong.",
                "The punctuation is weird. Pretty much everything is wrong."
            ),
            (
                "model question mark on a statement clause is demoted",
                "can you look at it and there is a bug",
                "Can you look at it? And there is a bug.",
                "Can you look at it? And there is a bug."
            ),
            (
                "recognizer question mark on a statement clause is demoted",
                "that works? and i will fix it",
                "That works? And I will fix it.",
                "That works. And I will fix it."
            ),
            (
                "model mid-clause period promotes to question mark",
                "and how can we improve it and then fix it",
                "And how can we improve it. And then fix it.",
                "And how can we improve it? And then fix it."
            ),
            (
                "recognizer mid-clause comma noise is dropped",
                "the punctuation s weird and i will fix it",
                "The punctuation, s weird and I will fix it.",
                "The punctuation s weird and I will fix it."
            ),
            (
                "recognizer mid-clause comma noise in source gap is dropped",
                "weird punctuation,s and i will fix it",
                "Weird punctuation,s and I will fix it.",
                "Weird punctuation s and I will fix it."
            ),
            (
                "trailing recognizer question mark on a statement is demoted",
                "everything has a?",
                "Everything has a?",
                "Everything has a."
            ),
            (
                "short question keeps its question mark",
                "can you fix it?",
                "Can you fix it?",
                "Can you fix it?"
            ),
            (
                "not much keeps its sentence break",
                "not much. what else?",
                "Not much. What else?",
                "Not much. What else?"
            ),
            (
                "let's see if statement keeps a period",
                "let's see if this works?",
                "Let's see if this works?",
                "Let's see if this works."
            ),
            (
                "can you see if question keeps a question mark",
                "can you see if it works.",
                "Can you see if it works.",
                "Can you see if it works?"
            ),
            (
                "punctuation-only input cannot crash",
                ".\u{FE00}",
                ".",
                "."
            ),
            (
                "model insertion does not shift merged boundary casing",
                "alpha beta and Gamma",
                "Alpha beta filler and. Gamma",
                "Alpha beta and gamma."
            ),
            (
                "meaningful trailing symbols survive model normalization",
                "please use C++",
                "Please use C.",
                "Please use C++."
            ),
            (
                "meaningful interior symbols survive model normalization",
                "please use c++ templates today",
                "Please use c templates today.",
                "Please use c++ templates today."
            ),
            (
                "identical fallback text does not duplicate trailing symbols",
                "please use C++",
                "please use C++",
                "please use C++."
            ),
        ]
        let substitutionCases: [(name: String, substitutions: [String: String], input: String, expected: String)] = [
            (
                "misheard name is replaced",
                ["all eyes": "Demetre"],
                "it always substitutes my name all eyes with something else",
                "it always substitutes my name Demetre with something else"
            ),
            (
                "substitution is case insensitive",
                ["all eyes": "Demetre"],
                "my name All Eyes is wrong",
                "my name Demetre is wrong"
            ),
            (
                "substitution respects word boundaries",
                ["all": "every"],
                "all of the allies are here",
                "every of the allies are here"
            ),
            (
                "longest phrase wins",
                ["eyes": "Eyes", "all eyes": "Demetre"],
                "all eyes on me",
                "Demetre on me"
            ),
            (
                "empty substitutions leave text unchanged",
                [:],
                "nothing changes here",
                "nothing changes here"
            ),
        ]
        let normalizationCases: [(name: String, input: String, expected: String)] = [
            (
                "model input strips punctuation casing newlines and command markers",
                "How are you?\nI am fine.\u{FE00} MAILGUN",
                "how are you i am fine mailgun"
            ),
            (
                "model input preserves word order and numbers",
                "First, SEND 2 copies!",
                "first send 2 copies"
            ),
            (
                "model input preserves contractions and meaningful symbols",
                "I don't use C++.",
                "i don't use c++"
            ),
            (
                "model input strips prosody markers",
                "hello\u{200B} world",
                "hello world"
            ),
        ]
        let pipelineCases: [(name: String, input: String, candidate: String, expected: String)] = [
            (
                "newline command survives punctuation model flattening",
                "First line go to a new line Second line",
                "First line. Second line.",
                "First line.\nSecond line."
            ),
            (
                "new paragraph command survives punctuation model flattening",
                "First paragraph new paragraph Second paragraph",
                "First paragraph. Second paragraph.",
                "First paragraph.\n\nSecond paragraph."
            ),
            (
                "explicit comma and period override duplicate model punctuation",
                "This is some content comma new line This is more content full stop",
                "This is some content,, This is more content..",
                "This is some content,\nThis is more content."
            ),
            (
                "explicit comma overrides mixed comma-period punctuation",
                "This is some content comma new line Now this is more",
                "This is some content,. Now this is more.",
                "This is some content,\nNow this is more."
            ),
        ]

        for testCase in substitutionCases {
            let actual = SpokenDictationFormatter.applyingSubstitutions(
                testCase.substitutions,
                to: testCase.input
            )
            guard actual == testCase.expected else {
                print(
                    "FAIL: \(testCase.name)\n" +
                        "  expected: \(String(reflecting: testCase.expected))\n" +
                        "  actual:   \(String(reflecting: actual))"
                )
                exit(EXIT_FAILURE)
            }
        }

        for testCase in cases {
            let actual = SpokenDictationFormatter.apply(to: testCase.input)
            guard actual == testCase.expected else {
                print(
                    "FAIL: \(testCase.name)\n" +
                        "  expected: \(String(reflecting: testCase.expected))\n" +
                        "  actual:   \(String(reflecting: actual))"
                )
                exit(EXIT_FAILURE)
            }
        }

        for testCase in automaticCases {
            let actual = SpokenDictationFormatter.applyingAutomaticPunctuation(
                candidate: testCase.candidate,
                to: testCase.original
            )
            guard actual == testCase.expected else {
                print(
                    "FAIL: \(testCase.name)\n" +
                        "  expected: \(String(reflecting: testCase.expected))\n" +
                        "  actual:   \(String(reflecting: actual))"
                )
                exit(EXIT_FAILURE)
            }
        }

        for testCase in normalizationCases {
            let actual = SpokenDictationFormatter.normalizingForPunctuationModel(testCase.input)
            guard actual == testCase.expected else {
                print(
                    "FAIL: \(testCase.name)\n" +
                        "  expected: \(String(reflecting: testCase.expected))\n" +
                        "  actual:   \(String(reflecting: actual))"
                )
                exit(EXIT_FAILURE)
            }
        }

        for testCase in pipelineCases {
            let commandFormatted = SpokenDictationFormatter.applyingSpokenCommands(to: testCase.input)
            let actual = SpokenDictationFormatter.applyingAutomaticPunctuation(
                candidate: testCase.candidate,
                to: commandFormatted
            )
            guard actual == testCase.expected else {
                print(
                    "FAIL: \(testCase.name)\n" +
                        "  expected: \(String(reflecting: testCase.expected))\n" +
                        "  actual:   \(String(reflecting: actual))"
                )
                exit(EXIT_FAILURE)
            }
        }

        let prosodicJoined = SpokenDictationFormatter.joiningChunks(
            ["first part.", "and then."],
            prosodyBoundaryAfter: [0]
        )
        guard prosodicJoined.contains(SpokenDictationFormatter.prosodyMarker),
              !SpokenDictationFormatter.strippingSpokenMarkers(prosodicJoined).contains(SpokenDictationFormatter.prosodyMarker) else {
            print("FAIL: quiet-boundary prosody marker was not inserted and stripped safely")
            exit(EXIT_FAILURE)
        }

        let prosodyTerminatorActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "I was going and. Then left.",
            to: "I was going and\u{200B} then left"
        )
        guard prosodyTerminatorActual == "I was going and. Then left.",
              !prosodyTerminatorActual.contains(SpokenDictationFormatter.prosodyMarker) else {
            print("FAIL: quiet boundary did not preserve agreeing lexical terminator: \(String(reflecting: prosodyTerminatorActual))")
            exit(EXIT_FAILURE)
        }

        let prosodyCommaActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "I want it, inside the one.",
            to: "I want it\u{200B} inside the one"
        )
        guard prosodyCommaActual == "I want it, inside the one." else {
            print("FAIL: quiet boundary did not preserve agreeing lexical comma: \(String(reflecting: prosodyCommaActual))")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .period,
            desired: PunctuationLearning.BoundaryLabel.none,
            previousWord: "and",
            nextWord: "zthen",
            clauseFirst: "zprosody",
            shaped: false,
            weight: 4
        )
        let correctionOverridesProsody = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zprosody and. Zthen finish.",
            to: "Zprosody and\u{200B} zthen finish"
        )
        guard correctionOverridesProsody == "Zprosody and zthen finish." else {
            print("FAIL: user correction did not override prosody fusion: \(String(reflecting: correctionOverridesProsody))")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .period,
            desired: PunctuationLearning.BoundaryLabel.none,
            previousWord: "zomega",
            nextWord: "then",
            clauseFirst: "zalpha",
            shaped: false,
            weight: 3
        )
        let learnedTrace = PunctuationLearning.Trace()
        let learnedActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zalpha zomega. Then beta.",
            to: "Zalpha zomega. Then beta.",
            trace: learnedTrace
        )
        guard learnedActual == "Zalpha zomega then beta.",
              learnedTrace.decisions.contains(where: { $0.action == "merge" && $0.learned }) else {
            print(
                "FAIL: correction-grounded merge did not override fallback punctuation\n" +
                    "  actual:   \(String(reflecting: learnedActual))\n" +
                    "  decisions: \(learnedTrace.decisions)"
            )
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .period,
            desired: .question,
            previousWord: "zreplace",
            nextWord: "next",
            clauseFirst: "zstart",
            shaped: false,
            weight: 3
        )
        let replacementActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zstart zreplace. Next finish.",
            to: "Zstart zreplace. Next finish."
        )
        guard replacementActual.contains("zreplace?") else {
            print("FAIL: correction-grounded terminator replacement missing: \(String(reflecting: replacementActual))")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .period,
            desired: .question,
            previousWord: "zterminal",
            nextWord: "",
            clauseFirst: "please",
            shaped: false,
            weight: 3
        )
        let terminalTrace = PunctuationLearning.Trace()
        let terminalActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Please zterminal.",
            to: "Please zterminal.",
            trace: terminalTrace
        )
        guard terminalActual == "Please zterminal?",
              terminalTrace.decisions.contains(where: { $0.gap == "terminal" && $0.action == "replace" && $0.learned }) else {
            print(
                "FAIL: correction-grounded terminal replacement missing\n" +
                    "  actual:   \(String(reflecting: terminalActual))\n" +
                    "  decisions: \(terminalTrace.decisions)"
            )
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: PunctuationLearning.BoundaryLabel.none,
            desired: .comma,
            previousWord: "zadd",
            nextWord: "znext",
            clauseFirst: "zstart",
            shaped: false,
            weight: 3
        )
        let insertionTrace = PunctuationLearning.Trace()
        let insertionActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zstart zadd znext finish.",
            to: "Zstart zadd znext finish.",
            trace: insertionTrace
        )
        guard insertionActual == "Zstart zadd, znext finish.",
              insertionTrace.decisions.contains(where: { $0.action == "insert" && $0.learned }) else {
            print(
                "FAIL: correction-grounded punctuation insertion missing\n" +
                    "  actual:   \(String(reflecting: insertionActual))\n" +
                    "  decisions: \(insertionTrace.decisions)"
            )
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .none,
            desired: .period,
            previousWord: "zstop",
            nextWord: "zresume",
            clauseFirst: "zcase",
            shaped: false,
            weight: 3
        )
        let sentenceInsertionActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zcase zstop zresume finish.",
            to: "Zcase zstop zresume finish."
        )
        guard sentenceInsertionActual == "Zcase zstop. Zresume finish." else {
            print("FAIL: learned sentence insertion did not capitalize following word: \(String(reflecting: sentenceInsertionActual))")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .comma,
            desired: .period,
            previousWord: "zcommaprev",
            nextWord: "zcommanext",
            clauseFirst: "zcase",
            shaped: false,
            weight: 3
        )
        let commaReplacementActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zcase zcommaprev, zcommanext finish.",
            to: "Zcase zcommaprev, zcommanext finish."
        )
        guard commaReplacementActual == "Zcase zcommaprev. Zcommanext finish." else {
            print("FAIL: comma-to-period correction did not capitalize following word: \(String(reflecting: commaReplacementActual))")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .period,
            desired: .comma,
            previousWord: "zperiodprev",
            nextWord: "zperiodnext",
            clauseFirst: "zcase",
            shaped: false,
            weight: 3
        )
        let periodReplacementActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zcase zperiodprev. Zperiodnext finish.",
            to: "Zcase zperiodprev. Zperiodnext finish."
        )
        guard periodReplacementActual == "Zcase zperiodprev, zperiodnext finish." else {
            print("FAIL: period-to-comma correction did not lowercase following word: \(String(reflecting: periodReplacementActual))")
            exit(EXIT_FAILURE)
        }

        let fallbackCommaReplacement = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "totally unrelated fallback candidate",
            to: "Zcase zcommaprev, zcommanext finish."
        )
        guard fallbackCommaReplacement == "Zcase zcommaprev. Zcommanext finish." else {
            print("FAIL: fallback comma-to-period correction did not capitalize following word: \(String(reflecting: fallbackCommaReplacement))")
            exit(EXIT_FAILURE)
        }

        let fallbackPeriodReplacement = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "totally unrelated fallback candidate",
            to: "Zcase zperiodprev. Zperiodnext finish."
        )
        guard fallbackPeriodReplacement == "Zcase zperiodprev, zperiodnext finish." else {
            print("FAIL: fallback period-to-comma correction did not lowercase following word: \(String(reflecting: fallbackPeriodReplacement))")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .none,
            desired: .question,
            previousWord: "zterminalmissing",
            nextWord: "",
            clauseFirst: "zcase",
            shaped: false,
            weight: 3
        )
        let terminalInsertionTrace = PunctuationLearning.Trace()
        let terminalInsertionActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zcase zterminalmissing",
            to: "Zcase zterminalmissing",
            trace: terminalInsertionTrace
        )
        guard terminalInsertionActual == "Zcase zterminalmissing?",
              terminalInsertionTrace.decisions.contains(where: { $0.action == "insert" && $0.learned && $0.terminator.isEmpty }) else {
            print("FAIL: learned terminal insertion did not use none-input evidence: \(String(reflecting: terminalInsertionActual)) \(terminalInsertionTrace.decisions)")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .none,
            desired: .comma,
            previousWord: "c",
            nextWord: "templates",
            clauseFirst: "please",
            shaped: false,
            weight: 3
        )
        let symbolInsertionActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Please use c templates today.",
            to: "please use c++ templates today"
        )
        guard symbolInsertionActual == "Please use c++, templates today." else {
            print("FAIL: learned insertion erased interior symbols: \(String(reflecting: symbolInsertionActual))")
            exit(EXIT_FAILURE)
        }

        PunctuationLearning.CorrectionPolicy.shared.observe(
            input: .none,
            desired: .comma,
            previousWord: "zshapeadd",
            nextWord: "zshapenext",
            clauseFirst: "zshape",
            shaped: true,
            weight: 3
        )
        let shapeFallbackActual = SpokenDictationFormatter.applyingAutomaticPunctuation(
            candidate: "Zshape zshapeadd zshapenext finish.",
            to: "Zshape zshapeadd zshapenext finish."
        )
        guard shapeFallbackActual == "Zshape zshapeadd, zshapenext finish." else {
            print("FAIL: insertion evidence was dropped when heuristic shape bucket changed: \(String(reflecting: shapeFallbackActual))")
            exit(EXIT_FAILURE)
        }

        print("SpokenDictationFormatterTests: all \(cases.count + automaticCases.count + pipelineCases.count + substitutionCases.count + normalizationCases.count + 17) cases passed")
    }
}
