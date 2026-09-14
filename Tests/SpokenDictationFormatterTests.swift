import Darwin

@main
struct SpokenDictationFormatterTests {
    static func main() {
        let cases: [(name: String, input: String, expected: String)] = [
            ("comma", "Hello comma world", "Hello, world"),
            ("sentence punctuation", "Are you there question mark Yes exclamation point", "Are you there? Yes!"),
            ("new line", "First line new line Second line", "First line\nSecond line"),
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

        for testCase in pipelineCases {
            let commandFormatted = SpokenDictationFormatter.apply(to: testCase.input)
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

        print("SpokenDictationFormatterTests: all \(cases.count + automaticCases.count + pipelineCases.count + substitutionCases.count) cases passed")
    }
}
