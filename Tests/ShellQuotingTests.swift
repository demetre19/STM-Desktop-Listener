import Darwin

@main
struct ShellQuotingTests {
    static func main() {
        let cases: [(name: String, actual: String, expected: String)] = [
            (
                name: "path containing spaces",
                actual: shellQuotedArgument("/Users/example/My Files/note.txt"),
                expected: "'/Users/example/My Files/note.txt'"
            ),
            (
                name: "ordinary slash-delimited path",
                actual: shellQuotedArgument("/usr/local/bin/tool"),
                expected: "'/usr/local/bin/tool'"
            ),
            (
                name: "path containing a single quote",
                actual: shellQuotedArgument("/Users/o'reilly/notes.txt"),
                expected: "'/Users/o'\\''reilly/notes.txt'"
            ),
            (
                name: "multiple paths remain separate arguments",
                actual: shellQuotedArguments([
                    "/Users/example/First File.txt",
                    "/tmp/second.txt",
                    "/tmp/o'clock.txt",
                ]),
                expected: "'/Users/example/First File.txt' '/tmp/second.txt' '/tmp/o'\\''clock.txt'"
            ),
            (
                name: "Unicode characters",
                actual: shellQuotedArgument("/Users/example/文書/naïve café.txt"),
                expected: "'/Users/example/文書/naïve café.txt'"
            ),
            (
                name: "empty argument array",
                actual: shellQuotedArguments([]),
                expected: ""
            ),
        ]

        for testCase in cases where testCase.actual != testCase.expected {
            print(
                "FAIL: \(testCase.name)\n" +
                    "  expected: \(String(reflecting: testCase.expected))\n" +
                    "  actual:   \(String(reflecting: testCase.actual))"
            )
            exit(EXIT_FAILURE)
        }

        print("ShellQuotingTests: all \(cases.count) cases passed")
    }
}
