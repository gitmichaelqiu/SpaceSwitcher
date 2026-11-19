import Foundation

enum RuleImportStrategy {
    case replaceAll
    case keepAll
    case addNewApps
    case replaceMatchingApps
}

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

    static func applying(
        _ importedRules: [AppRule],
        to existingRules: [AppRule],
        strategy: RuleImportStrategy
    ) -> [AppRule] {
        let result: [AppRule]

        switch strategy {
        case .replaceAll:
            result = importedRules

        case .keepAll:
            result = existingRules + importedRules

        case .addNewApps:
            var existingApplications = Set<ApplicationKey>()
            for rule in existingRules {
                existingApplications.insert(applicationKey(for: rule))
            }

            var additions: [AppRule] = []
            for rule in importedRules {
                if !existingApplications.contains(applicationKey(for: rule)) {
                    additions.append(rule)
                }
            }
            result = existingRules + additions

        case .replaceMatchingApps:
            result = replacingMatchingApps(importedRules, in: existingRules)
        }

        return ensuringUniqueRuleIDs(in: result)
    }

    private static func replacingMatchingApps(
        _ importedRules: [AppRule],
        in existingRules: [AppRule]
    ) -> [AppRule] {
        var importedByApplication: [ApplicationKey: [AppRule]] = [:]
        for rule in importedRules {
            importedByApplication[applicationKey(for: rule), default: []].append(rule)
        }
        var insertedApplications = Set<ApplicationKey>()
        var result: [AppRule] = []

        for rule in existingRules {
            let application = applicationKey(for: rule)
            guard let replacements = importedByApplication[application] else {
                result.append(rule)
                continue
            }
            guard insertedApplications.insert(application).inserted else { continue }
            result.append(contentsOf: replacements)
        }

        for rule in importedRules {
            let application = applicationKey(for: rule)
            guard insertedApplications.insert(application).inserted else { continue }
            result.append(contentsOf: importedByApplication[application] ?? [rule])
        }

        return result
    }

    private static func ensuringUniqueRuleIDs(in rules: [AppRule]) -> [AppRule] {
        var usedIDs = Set<UUID>()
        return rules.map { rule in
            var uniqueRule = rule
            while usedIDs.contains(uniqueRule.id) {
                uniqueRule.id = UUID()
            }
            usedIDs.insert(uniqueRule.id)
            return uniqueRule
        }
    }

    private static func applicationKey(for rule: AppRule) -> ApplicationKey {
        rule.appliesToAllApps
            ? .allApps
            : .bundleIdentifier(rule.appBundleID.lowercased())
    }

    private enum ApplicationKey: Hashable {
        case allApps
        case bundleIdentifier(String)
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
