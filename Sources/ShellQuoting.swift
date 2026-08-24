import Foundation

func shellQuotedArgument(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

func shellQuotedArguments(_ values: [String]) -> String {
    values.map(shellQuotedArgument).joined(separator: " ")
}
