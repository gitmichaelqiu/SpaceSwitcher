import AppKit
import Foundation
import ServiceManagement

enum SpaceSwitcherBundleIdentity {
    static let legacyBundleIdentifier = "michaelqiu.SpaceSwitcher"
    static let currentBundleIdentifier = "dev.mqiu.SpaceSwitcher"
    static let currentUpdateChannel = "dev-mqiu"
    static let appcastTargetBundleIdentifierKey = "spaceswitcher:targetBundleIdentifier"

    static let migrationPackageURLKey = "SpaceSwitcherMigrationPackageURL"
    static let migrationPackageSHA256Key = "SpaceSwitcherMigrationPackageSHA256"
    static let migrationPackageVersionKey = "SpaceSwitcherMigrationPackageVersion"
    static let migrationAllowManualApprovalKey = "SpaceSwitcherMigrationAllowManualApproval"
    static let migrationStagingPathKey = "SpaceSwitcherMigrationStagingPath"
    static let releaseTagKey = "SpaceSwitcherReleaseTag"

    static let migrationLaunchAtLoginPendingKey = "SpaceSwitcher.IdentityMigration.LaunchAtLoginPending"
    static let migrationCleanupStagedPathKey = "SpaceSwitcher.IdentityMigration.CleanupStagedPath"
    static let migrationCleanupBackupPathKey = "SpaceSwitcher.IdentityMigration.CleanupBackupPath"
    static let migrationLaunchAcknowledgedKey = "SpaceSwitcher.IdentityMigration.LaunchAcknowledged"
    static let migrationCompletedKey = "SpaceSwitcher.IdentityMigration.Completed"

    static var isLegacyBridge: Bool {
        Bundle.main.bundleIdentifier == legacyBundleIdentifier
    }

    static var isCurrentApplication: Bool {
        Bundle.main.bundleIdentifier == currentBundleIdentifier
    }
}

enum SpaceSwitcherMigrationStorage {
    static let manifestFileName = "manifest.json"

    static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpaceSwitcher", isDirectory: true)
            .appendingPathComponent("Migration", isDirectory: true)
    }

    static var manifestURL: URL {
        applicationSupportURL.appendingPathComponent(manifestFileName)
    }

    static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpaceSwitcher", isDirectory: true)
            .appendingPathComponent("Migration", isDirectory: true)
    }

    static func write(_ manifest: SpaceSwitcherMigrationManifest) throws {
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
    }

    static func read() throws -> SpaceSwitcherMigrationManifest {
        try JSONDecoder().decode(SpaceSwitcherMigrationManifest.self, from: Data(contentsOf: manifestURL))
    }

    static func discardPendingMigration() {
        try? FileManager.default.removeItem(at: manifestURL)
        try? FileManager.default.removeItem(at: cacheURL)
    }
}

struct MigrationInstallerLaunchGate {
    enum Decision: Equatable {
        case waitingForInstaller
        case waitingForStagedApplication
        case launchStagedApplication
        case stagingFailed
    }

    static let stagedApplicationGracePeriod: TimeInterval = 30

    private(set) var installerWasObserved = false
    private var installerExitObservedAt: Date?

    mutating func decision(
        installerIsRunning: Bool,
        stagedApplicationIsValid: Bool,
        now: Date = Date()
    ) -> Decision {
        if installerIsRunning {
            installerWasObserved = true
            installerExitObservedAt = nil
            return .waitingForInstaller
        }

        guard installerWasObserved else { return .waitingForInstaller }
        if stagedApplicationIsValid { return .launchStagedApplication }

        if installerExitObservedAt == nil {
            installerExitObservedAt = now
            return .waitingForStagedApplication
        }

        guard let exitObservedAt = installerExitObservedAt else { return .waitingForStagedApplication }
        return now.timeIntervalSince(exitObservedAt) >= Self.stagedApplicationGracePeriod
            ? .stagingFailed
            : .waitingForStagedApplication
    }
}

struct SpaceSwitcherMigrationManifest: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sourceApplicationPath: String
    let sourceProcessIdentifier: Int32
    let targetBundleIdentifier: String
    let stagingApplicationPath: String
    let launchAtLoginEnabled: Bool
    let expectedVersion: String
    let createdAt: Date
}

enum SpaceSwitcherMigrationError: LocalizedError {
    case invalidConfiguration
    case invalidDownload
    case checksumMismatch
    case packageVerificationFailed
    case stagingApplicationMissing
    case installerClosed
    case manifestInvalid
    case legacyApplicationDidNotTerminate
    case targetApplicationInvalid
    case applicationSwapFailed
    case applicationLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The SpaceSwitcher identity migration is not configured correctly."
        case .invalidDownload:
            return "The migration package could not be downloaded."
        case .checksumMismatch:
            return "The migration package checksum did not match the signed release."
        case .packageVerificationFailed:
            return "The migration package did not pass macOS verification."
        case .stagingApplicationMissing:
            return "The migration package did not install the staged application."
        case .installerClosed:
            return "Installer closed before the new application was staged."
        case .manifestInvalid:
            return "The migration manifest is missing or invalid."
        case .legacyApplicationDidNotTerminate:
            return "The previous SpaceSwitcher process could not be stopped safely."
        case .targetApplicationInvalid:
            return "The existing SpaceSwitcher application could not be safely replaced."
        case .applicationSwapFailed:
            return "The new SpaceSwitcher application could not be installed."
        case .applicationLaunchFailed:
            return "The new SpaceSwitcher application did not start successfully."
        }
    }
}

enum SpaceSwitcherMigrationConfiguration {
    static var packageURL: URL? {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: SpaceSwitcherBundleIdentity.migrationPackageURLKey
        ) as? String,
        let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
        url.scheme?.lowercased() == "https",
        url.host != nil else {
            return nil
        }
        return url
    }

    static var packageSHA256: String? {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: SpaceSwitcherBundleIdentity.migrationPackageSHA256Key
        ) as? String else { return nil }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count == 64,
              value.allSatisfy({ $0.isNumber || ("a"..."f").contains($0) }) else {
            return nil
        }
        return value
    }

    static var packageVersion: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: SpaceSwitcherBundleIdentity.migrationPackageVersionKey
        ) as? String else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var allowsManualApproval: Bool {
        let value = Bundle.main.object(
            forInfoDictionaryKey: SpaceSwitcherBundleIdentity.migrationAllowManualApprovalKey
        )
        if let value = value as? Bool { return value }
        guard let value = value as? String else { return false }
        return ["1", "yes", "true"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static var stagingApplicationURL: URL {
        if let rawValue = Bundle.main.object(
            forInfoDictionaryKey: SpaceSwitcherBundleIdentity.migrationStagingPathKey
        ) as? String {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/") && value.hasSuffix(".app") {
                return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            }
        }
        return URL(fileURLWithPath: "/Applications/SpaceSwitcher-Migration.app", isDirectory: true)
    }

    static var isConfigured: Bool {
        packageURL != nil && packageSHA256 != nil && packageVersion?.isEmpty == false
    }
}

enum SpaceSwitcherIdentityMigration {
    private enum CleanupResult {
        case complete
        case retry
    }

    static func prepareLegacyBridgeLaunch() {
        guard SpaceSwitcherBundleIdentity.isLegacyBridge else { return }

        let defaults = UserDefaults.standard
        let legacyDomain = defaults.persistentDomain(
            forName: SpaceSwitcherBundleIdentity.legacyBundleIdentifier
        ) ?? [:]
        guard legacyDomain.isEmpty,
              var currentDomain = defaults.persistentDomain(
                  forName: SpaceSwitcherBundleIdentity.currentBundleIdentifier
              ), !currentDomain.isEmpty else { return }

        currentDomain = currentDomain.filter { key, _ in
            !key.hasPrefix("SU")
                && !key.hasPrefix("SPU")
                && !key.hasPrefix("org.sparkle-project")
                && !key.hasPrefix("SpaceSwitcher.IdentityMigration.")
        }
        guard !currentDomain.isEmpty else { return }
        defaults.setPersistentDomain(currentDomain, forName: SpaceSwitcherBundleIdentity.legacyBundleIdentifier)
        defaults.synchronize()
    }

    static func migrateLegacyDefaults(launchAtLoginEnabled: Bool) {
        guard SpaceSwitcherBundleIdentity.isCurrentApplication else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SpaceSwitcherBundleIdentity.migrationCompletedKey) else { return }

        let legacyDomain = defaults.persistentDomain(
            forName: SpaceSwitcherBundleIdentity.legacyBundleIdentifier
        ) ?? [:]
        var currentDomain = defaults.persistentDomain(
            forName: SpaceSwitcherBundleIdentity.currentBundleIdentifier
        ) ?? [:]
        for (key, value) in legacyDomain where
            !key.hasPrefix("SU") && !key.hasPrefix("SPU") && !key.hasPrefix("org.sparkle-project") {
            currentDomain[key] = value
        }
        currentDomain["HasInitializedDefaults"] = true
        defaults.setPersistentDomain(currentDomain, forName: SpaceSwitcherBundleIdentity.currentBundleIdentifier)
        defaults.set(launchAtLoginEnabled, forKey: SpaceSwitcherBundleIdentity.migrationLaunchAtLoginPendingKey)
        defaults.synchronize()
    }

    static func prepareNormalLaunch() {
        guard SpaceSwitcherBundleIdentity.isCurrentApplication else { return }
        let defaults = UserDefaults.standard
        let hasPendingCleanup = defaults.string(
            forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey
        ) != nil
        if hasPendingCleanup,
           defaults.bool(forKey: SpaceSwitcherBundleIdentity.migrationCompletedKey) {
            retryPendingCleanup()
        }

        guard let launchAtLogin = defaults.object(
            forKey: SpaceSwitcherBundleIdentity.migrationLaunchAtLoginPendingKey
        ) as? Bool else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationLaunchAtLoginPendingKey)
        } catch {
            print("IdentityMigration: failed to restore launch at login: \(error)")
        }
    }

    static func completeSuccessfulLaunch() {
        guard SpaceSwitcherBundleIdentity.isCurrentApplication else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey) != nil else {
            return
        }

        defaults.set(true, forKey: SpaceSwitcherBundleIdentity.migrationLaunchAcknowledgedKey)
        defaults.synchronize()
        retryPendingCleanup()
    }

    private static func retryPendingCleanup(attemptsRemaining: Int = 120) {
        guard attemptsRemaining > 0,
              UserDefaults.standard.string(
                  forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey
              ) != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if case .retry = cleanupStagedApplicationIfNeeded() {
                retryPendingCleanup(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    @discardableResult
    private static func cleanupStagedApplicationIfNeeded() -> CleanupResult {
        let defaults = UserDefaults.standard
        guard let stagedPath = defaults.string(
            forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey
        ) else { return .complete }
        guard defaults.bool(forKey: SpaceSwitcherBundleIdentity.migrationCompletedKey) else {
            return .retry
        }

        let fileManager = FileManager.default
        let stagedURL = URL(fileURLWithPath: stagedPath, isDirectory: true).standardizedFileURL
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        guard stagedURL != currentURL, stagedURL.pathExtension == "app" else {
            defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey)
            return .complete
        }

        let stagedApplicationIsRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == SpaceSwitcherBundleIdentity.currentBundleIdentifier
                && $0.bundleURL?.standardizedFileURL == stagedURL
        }
        guard !stagedApplicationIsRunning else { return .retry }

        do {
            if fileManager.fileExists(atPath: stagedURL.path) { try fileManager.removeItem(at: stagedURL) }
            if let backupPath = defaults.string(forKey: SpaceSwitcherBundleIdentity.migrationCleanupBackupPathKey) {
                let backupURL = URL(fileURLWithPath: backupPath, isDirectory: true).standardizedFileURL
                if backupURL.pathExtension == "app", backupURL != currentURL,
                   fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
            }
            try? fileManager.removeItem(at: SpaceSwitcherMigrationStorage.manifestURL)
            try? fileManager.removeItem(at: SpaceSwitcherMigrationStorage.cacheURL)
            try? SMAppService.loginItem(
                identifier: SpaceSwitcherBundleIdentity.legacyBundleIdentifier
            ).unregister()
            defaults.removePersistentDomain(forName: SpaceSwitcherBundleIdentity.legacyBundleIdentifier)
            defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey)
            defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationCleanupBackupPathKey)
            return .complete
        } catch {
            print("IdentityMigration: staged app cleanup deferred: \(error)")
            return .retry
        }
    }
}
