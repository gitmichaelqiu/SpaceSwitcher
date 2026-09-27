import AppKit
import Darwin
import Foundation

final class SpaceSwitcherMigrationFinalizer {
    static let shared = SpaceSwitcherMigrationFinalizer()

    private var manifest: SpaceSwitcherMigrationManifest?
    private var backupURL: URL?
    private var targetURL: URL?
    private var launchAttempts = 0
    private var isTerminating = false

    private init() {}

    func startIfRequested() -> Bool {
        let isStagedLaunch = SpaceSwitcherBundleIdentity.isCurrentApplication
            && Bundle.main.bundleURL.standardizedFileURL
                == SpaceSwitcherMigrationConfiguration.stagingApplicationURL.standardizedFileURL
            && FileManager.default.fileExists(atPath: SpaceSwitcherMigrationStorage.manifestURL.path)
        guard CommandLine.arguments.contains("--spaceswitcher-migration") || isStagedLaunch else {
            return false
        }

        DispatchQueue.main.async { [weak self] in self?.beginMigration() }
        return true
    }

    private func beginMigration() {
        do {
            guard SpaceSwitcherBundleIdentity.isCurrentApplication,
                  Bundle.main.bundleURL.standardizedFileURL
                    == SpaceSwitcherMigrationConfiguration.stagingApplicationURL.standardizedFileURL else {
                throw SpaceSwitcherMigrationError.manifestInvalid
            }
            let manifest = try SpaceSwitcherMigrationStorage.read()
            guard manifest.schemaVersion == SpaceSwitcherMigrationManifest.currentSchemaVersion,
                  manifest.targetBundleIdentifier == SpaceSwitcherBundleIdentity.currentBundleIdentifier,
                  manifest.stagingApplicationPath
                    == SpaceSwitcherMigrationConfiguration.stagingApplicationURL.path,
                  manifest.expectedVersion
                    == (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""),
                  URL(fileURLWithPath: manifest.sourceApplicationPath).pathExtension == "app",
                  manifest.sourceApplicationPath
                    != SpaceSwitcherMigrationConfiguration.stagingApplicationURL.path,
                  bundleIdentifier(at: URL(fileURLWithPath: manifest.sourceApplicationPath))
                    == SpaceSwitcherBundleIdentity.legacyBundleIdentifier else {
                throw SpaceSwitcherMigrationError.manifestInvalid
            }
            self.manifest = manifest
            terminateLegacyApplication(attemptsRemaining: 40)
        } catch {
            failMigration(error)
        }
    }

    private func terminateLegacyApplication(attemptsRemaining: Int) {
        guard let manifest else {
            failMigration(SpaceSwitcherMigrationError.manifestInvalid)
            return
        }
        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath).standardizedFileURL
        let runningApplications = NSWorkspace.shared.runningApplications.filter { application in
            guard application.bundleIdentifier == SpaceSwitcherBundleIdentity.legacyBundleIdentifier else {
                return false
            }
            return application.bundleURL?.standardizedFileURL == sourceURL
                || (application.processIdentifier == manifest.sourceProcessIdentifier
                    && application.bundleURL == nil)
        }

        guard !runningApplications.isEmpty else {
            SpaceSwitcherIdentityMigration.migrateLegacyDefaults(
                launchAtLoginEnabled: manifest.launchAtLoginEnabled
            )
            performApplicationSwap()
            return
        }
        guard attemptsRemaining > 0 else {
            failMigration(SpaceSwitcherMigrationError.legacyApplicationDidNotTerminate)
            return
        }

        for application in runningApplications {
            if attemptsRemaining <= 20 {
                if !application.forceTerminate() {
                    _ = Darwin.kill(application.processIdentifier, SIGKILL)
                }
            } else {
                application.terminate()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.terminateLegacyApplication(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    private func performApplicationSwap() {
        guard let manifest else {
            failMigration(SpaceSwitcherMigrationError.manifestInvalid)
            return
        }

        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath, isDirectory: true)
            .standardizedFileURL
        let stagingURL = Bundle.main.bundleURL.standardizedFileURL
        let parentURL = sourceURL.deletingLastPathComponent()
        let temporaryURL = parentURL.appendingPathComponent(
            ".SpaceSwitcher-new-\(UUID().uuidString).app"
        )
        let backupURL = parentURL.appendingPathComponent(
            ".SpaceSwitcher-legacy-\(UUID().uuidString).app"
        )

        do {
            guard sourceURL.pathExtension == "app", sourceURL != stagingURL,
                  bundleIdentifier(at: sourceURL) == SpaceSwitcherBundleIdentity.legacyBundleIdentifier else {
                throw SpaceSwitcherMigrationError.targetApplicationInvalid
            }
            try fileManager.copyItem(at: stagingURL, to: temporaryURL)
            guard bundleIdentifier(at: temporaryURL) == SpaceSwitcherBundleIdentity.currentBundleIdentifier else {
                throw SpaceSwitcherMigrationError.applicationSwapFailed
            }

            try fileManager.moveItem(at: sourceURL, to: backupURL)
            self.backupURL = backupURL
            try fileManager.moveItem(at: temporaryURL, to: sourceURL)
            self.targetURL = sourceURL
            guard bundleIdentifier(at: sourceURL) == SpaceSwitcherBundleIdentity.currentBundleIdentifier else {
                throw SpaceSwitcherMigrationError.applicationSwapFailed
            }
        } catch {
            restoreAfterFailedSwap(targetURL: sourceURL, temporaryURL: temporaryURL, backupURL: backupURL)
            failMigration(error)
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(stagingURL.path, forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey)
        defaults.set(backupURL.path, forKey: SpaceSwitcherBundleIdentity.migrationCleanupBackupPathKey)
        defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationLaunchAcknowledgedKey)
        defaults.synchronize()
        launchCanonicalApplication(at: sourceURL)
    }

    private func launchCanonicalApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.failMigration(error)
                } else {
                    self.waitForCanonicalApplication(at: url)
                }
            }
        }
    }

    private func waitForCanonicalApplication(at url: URL) {
        let isRunning = NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == SpaceSwitcherBundleIdentity.currentBundleIdentifier
                && application.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }
        let hasAcknowledged = UserDefaults.standard.bool(
            forKey: SpaceSwitcherBundleIdentity.migrationLaunchAcknowledgedKey
        )
        if isRunning && hasAcknowledged {
            completeMigration()
            return
        }
        guard launchAttempts < 40 else {
            failMigration(SpaceSwitcherMigrationError.applicationLaunchFailed)
            return
        }
        launchAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForCanonicalApplication(at: url)
        }
    }

    private func completeMigration() {
        if let backupURL, FileManager.default.fileExists(atPath: backupURL.path) {
            do {
                try FileManager.default.removeItem(at: backupURL)
            } catch {
                print("IdentityMigration: legacy app cleanup deferred: \(error)")
            }
        }
        UserDefaults.standard.set(true, forKey: SpaceSwitcherBundleIdentity.migrationCompletedKey)
        UserDefaults.standard.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationLaunchAcknowledgedKey)
        UserDefaults.standard.synchronize()
        terminateMigrationApplication()
    }

    private func restoreAfterFailedSwap(targetURL: URL, temporaryURL: URL, backupURL: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: temporaryURL.path) { try? fileManager.removeItem(at: temporaryURL) }
        if bundleIdentifier(at: targetURL) == SpaceSwitcherBundleIdentity.currentBundleIdentifier {
            try? fileManager.removeItem(at: targetURL)
        }
        if fileManager.fileExists(atPath: backupURL.path) { try? fileManager.moveItem(at: backupURL, to: targetURL) }
    }

    private func failMigration(_ error: Error) {
        if let targetURL {
            NSWorkspace.shared.runningApplications
                .filter {
                    $0.bundleIdentifier == SpaceSwitcherBundleIdentity.currentBundleIdentifier
                        && $0.bundleURL?.standardizedFileURL == targetURL.standardizedFileURL
                }
                .forEach { _ = $0.forceTerminate() }
        }
        if let targetURL, let backupURL,
           FileManager.default.fileExists(atPath: backupURL.path) {
            restoreAfterFailedSwap(
                targetURL: targetURL,
                temporaryURL: targetURL,
                backupURL: backupURL
            )
        }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationCleanupStagedPathKey)
        defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationCleanupBackupPathKey)
        defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationLaunchAcknowledgedKey)
        defaults.removeObject(forKey: SpaceSwitcherBundleIdentity.migrationLaunchAtLoginPendingKey)
        defaults.set(false, forKey: SpaceSwitcherBundleIdentity.migrationCompletedKey)
        defaults.synchronize()
        SpaceSwitcherMigrationStorage.discardPendingMigration()
        relaunchLegacyApplicationIfNeeded()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SpaceSwitcher migration failed"
        alert.informativeText = "\(error.localizedDescription) The previous application was preserved or restored."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        terminateMigrationApplication()
    }

    private func relaunchLegacyApplicationIfNeeded() {
        guard let manifest else { return }
        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath, isDirectory: true)
            .standardizedFileURL
        guard bundleIdentifier(at: sourceURL) == SpaceSwitcherBundleIdentity.legacyBundleIdentifier else { return }
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == SpaceSwitcherBundleIdentity.legacyBundleIdentifier
                && $0.bundleURL?.standardizedFileURL == sourceURL
        }
        guard !isRunning else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: sourceURL, configuration: configuration) { _, error in
            if let error { print("IdentityMigration: failed to relaunch legacy app: \(error)") }
        }
    }

    private func bundleIdentifier(at url: URL) -> String? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["CFBundleIdentifier"] as? String
    }

    private func terminateMigrationApplication() {
        guard !isTerminating else { return }
        isTerminating = true
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if NSApp.isRunning { Darwin.exit(0) }
        }
    }
}
