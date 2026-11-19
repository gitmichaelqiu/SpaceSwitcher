import Foundation

enum RuleTransferService {
    static func encode(_ rules: [AppRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rules)
    }

    static func decode(_ data: Data) throws -> [AppRule] {
        let rules = try JSONDecoder().decode([AppRule].self, from: data)
        guard !rules.isEmpty else {
            throw RuleTransferError.emptyRuleSet
        }
        return rules
    }
}

enum RuleTransferError: LocalizedError, Equatable {
    case emptyRuleSet

    var errorDescription: String? {
        switch self {
        case .emptyRuleSet:
            return NSLocalizedString(
                "The selected JSON file does not contain any rules.",
                comment: "Error shown when importing an empty rules file"
            )
        }
    }
}
