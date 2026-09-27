import AppKit
import CryptoKit
import Foundation
import OSLog
import ServiceManagement

private func runMigrationTool(_ path: String, arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    } catch {
        print("IdentityMigration: failed to run \(path): \(error)")
        return false
    }
}

final class SpaceSwitcherBridgeMigrationManager {
    static let shared = SpaceSwitcherBridgeMigrationManager()
    private static let logger = Logger(
        subsystem: SpaceSwitcherBundleIdentity.currentBundleIdentifier,
        category: "IdentityMigration"
    )

    private var hasPresentedPrompt = false
    private var completion: (() -> Void)?
    private var downloadTask: URLSessionDownloadTask?
    private var installerMonitor: Timer?
    private var installerLaunchDeadline: Date?
    private var installDeadline: Date?
    private var installerExitWaitLogged = false
    private var installerLaunchGate = MigrationInstallerLaunchGate()
    private var stagedLaunchStarted = false
    private var stagedApplicationMonitor: Timer?
    private var stagedLaunchDeadline: Date?
    private var stagedApplicationWasObserved = false
    private var manifest: SpaceSwitcherMigrationManifest?

    private init() {}

    /// Returns true when the legacy bridge owns launch and must defer normal app startup.
    func beginIfNeeded(completion: @escaping () -> Void) -> Bool {
        guard SpaceSwitcherBundleIdentity.isLegacyBridge,
              SpaceSwitcherMigrationConfiguration.isConfigured else { return false }

        self.completion = completion
        SpaceSwitcherIdentityMigration.prepareLegacyBridgeLaunch()
        guard !hasPresentedPrompt else { return true }
        hasPresentedPrompt = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.resumePendingMigrationIfNeeded() { return }
            self.presentMigrationPrompt()
        }
        return true
    }

    private func presentMigrationPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "SpaceSwitcher needs a one-time update"
        alert.informativeText = "This update changes SpaceSwitcher’s application identity. Your settings will be preserved, and the existing app will be replaced only after the new app starts successfully."
        alert.addButton(withTitle: "Migrate Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            startMigration()
        } else {
            continueNormalApplication()
        }
    }

    private func resumePendingMigrationIfNeeded() -> Bool {
        guard let manifest = try? SpaceSwitcherMigrationStorage.read(),
              let expectedVersion = SpaceSwitcherMigrationConfiguration.packageVersion,
              manifest.schemaVersion == SpaceSwitcherMigrationManifest.currentSchemaVersion,
              manifest.sourceApplicationPath == Bundle.main.bundleURL.standardizedFileURL.path,
              manifest.targetBundleIdentifier == SpaceSwitcherBundleIdentity.currentBundleIdentifier,
              manifest.stagingApplicationPath == SpaceSwitcherMigrationConfiguration.stagingApplicationURL.path,
              manifest.expectedVersion == expectedVersion,
              stagedApplicationMatches(expectedVersion: expectedVersion) else {
            return false
        }

        self.manifest = manifest
        launchStagedApplication()
        return true
    }

    private func startMigration() {
        guard let packageURL = SpaceSwitcherMigrationConfiguration.packageURL,
              let packageHash = SpaceSwitcherMigrationConfiguration.packageSHA256,
              let packageVersion = SpaceSwitcherMigrationConfiguration.packageVersion,
              !packageVersion.isEmpty else {
            showFailure(SpaceSwitcherMigrationError.invalidConfiguration)
            return
        }

        stagedLaunchStarted = false
        let manifest = SpaceSwitcherMigrationManifest(
            schemaVersion: SpaceSwitcherMigrationManifest.currentSchemaVersion,
            sourceApplicationPath: Bundle.main.bundleURL.standardizedFileURL.path,
            sourceProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            targetBundleIdentifier: SpaceSwitcherBundleIdentity.currentBundleIdentifier,
            stagingApplicationPath: SpaceSwitcherMigrationConfiguration.stagingApplicationURL.path,
            launchAtLoginEnabled: SMAppService.mainApp.status == .enabled
                || SMAppService.mainApp.status == .requiresApproval,
            expectedVersion: packageVersion,
            createdAt: Date()
        )

        do {
            try SpaceSwitcherMigrationStorage.write(manifest)
            self.manifest = manifest
        } catch {
            showFailure(error)
            return
        }

        let task = URLSession.shared.downloadTask(with: packageURL) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.showFailure(error) }
                return
            }
            guard let temporaryURL,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                DispatchQueue.main.async { self.showFailure(SpaceSwitcherMigrationError.invalidDownload) }
                return
            }

            do {
                let cachedPackage = try self.cachePackage(at: temporaryURL)
                try self.validatePackage(at: cachedPackage, expectedSHA256: packageHash)
                DispatchQueue.main.async { self.openInstaller(for: cachedPackage) }
            } catch {
                DispatchQueue.main.async { self.showFailure(error) }
            }
        }
        downloadTask = task
        task.resume()
        showProgressNotice("Downloading the verified migration package…")
    }

    private func cachePackage(at temporaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: SpaceSwitcherMigrationStorage.cacheURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let packageURL = SpaceSwitcherMigrationStorage.cacheURL.appendingPathComponent("SpaceSwitcher-Migration.pkg")
        if fileManager.fileExists(atPath: packageURL.path) { try fileManager.removeItem(at: packageURL) }
        try fileManager.moveItem(at: temporaryURL, to: packageURL)
        return packageURL
    }

    private func validatePackage(at packageURL: URL, expectedSHA256: String) throws {
        let actualHash = SHA256.hash(data: try Data(contentsOf: packageURL))
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == expectedSHA256 else { throw SpaceSwitcherMigrationError.checksumMismatch }

        guard !SpaceSwitcherMigrationConfiguration.allowsManualApproval else { return }
        guard runMigrationTool("/usr/sbin/pkgutil", arguments: ["--check-signature", packageURL.path]),
              runMigrationTool("/usr/sbin/spctl", arguments: ["--assess", "--type", "install", packageURL.path]) else {
            throw SpaceSwitcherMigrationError.packageVerificationFailed
        }
    }

    private func openInstaller(for packageURL: URL) {
        guard NSWorkspace.shared.open(packageURL) else {
            showFailure(SpaceSwitcherMigrationError.packageVerificationFailed)
            return
        }

        installerLaunchGate = MigrationInstallerLaunchGate()
        installerExitWaitLogged = false
        installerLaunchDeadline = Date().addingTimeInterval(20)
        installDeadline = Date().addingTimeInterval(10 * 60)
        installerMonitor?.invalidate()
        installerMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkForStagedApplication()
        }
        showProgressNotice("Complete the Installer steps to stage the new SpaceSwitcher app.")
    }

    private func checkForStagedApplication() {
        guard !stagedLaunchStarted else { return }
        if let installDeadline, Date() > installDeadline {
            stopMonitoringInstaller()
            showFailure(SpaceSwitcherMigrationError.stagingApplicationMissing)
            return
        }

        let installerRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.installer" && !$0.isTerminated
        }
        let installerWasPreviouslyObserved = installerLaunchGate.installerWasObserved
        let stagedApplicationIsValid = isExpectedStagedApplicationInstalled
        let decision = installerLaunchGate.decision(
            installerIsRunning: installerRunning,
            stagedApplicationIsValid: stagedApplicationIsValid
        )

        switch decision {
        case .launchStagedApplication:
            Self.logger.info("Installer exited and the expected staged app is present; beginning handoff.")
            launchStagedApplication()
        case .waitingForInstaller where installerRunning:
            if !installerWasPreviouslyObserved {
                Self.logger.info("Observed Installer running; waiting for installation to finish.")
            } else if installerExitWaitLogged {
                installerExitWaitLogged = false
            }
        case .waitingForStagedApplication:
            if !installerExitWaitLogged {
                Self.logger.info("Installer exited; waiting for the staged app to finish appearing at the configured path.")
                installerExitWaitLogged = true
            }
        case .stagingFailed:
            stopMonitoringInstaller()
            let stagedPath = SpaceSwitcherMigrationConfiguration.stagingApplicationURL.path
            let stagedMetadata = stagedApplicationMetadata
            let stagedBundleIdentifier = stagedMetadata.bundleIdentifier ?? "<unavailable>"
            let stagedBuild = stagedMetadata.build ?? "<unavailable>"
            Self.logger.error("Staged app did not become valid after Installer exit (path=\(stagedPath, privacy: .public), exists=\(FileManager.default.fileExists(atPath: stagedPath)), bundleID=\(stagedBundleIdentifier, privacy: .public), build=\(stagedBuild, privacy: .public), expectedBuild=\(SpaceSwitcherMigrationConfiguration.packageVersion ?? "<missing>", privacy: .public)).")
            showFailure(SpaceSwitcherMigrationError.installerClosed)
        case .waitingForInstaller:
            break
        }

        if !installerRunning,
           !installerLaunchGate.installerWasObserved,
           let installerLaunchDeadline,
           Date() > installerLaunchDeadline {
            stopMonitoringInstaller()
            Self.logger.error("Installer did not appear after opening the migration package.")
            showFailure(SpaceSwitcherMigrationError.stagingApplicationMissing)
        }
    }

    private var isExpectedStagedApplicationInstalled: Bool {
        guard let expectedVersion = SpaceSwitcherMigrationConfiguration.packageVersion else { return false }
        return stagedApplicationMatches(expectedVersion: expectedVersion)
    }

    private var stagedApplicationMetadata: (bundleIdentifier: String?, build: String?) {
        let infoPlistURL = SpaceSwitcherMigrationConfiguration.stagingApplicationURL
            .appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let infoDictionary = propertyList as? [String: Any] else {
            return (nil, nil)
        }
        return (
            infoDictionary["CFBundleIdentifier"] as? String,
            infoDictionary["CFBundleVersion"] as? String
        )
    }

    private func stagedApplicationMatches(expectedVersion: String) -> Bool {
        let metadata = stagedApplicationMetadata
        return metadata.bundleIdentifier == SpaceSwitcherBundleIdentity.currentBundleIdentifier
            && metadata.build == expectedVersion
    }

    private func launchStagedApplication() {
        guard !stagedLaunchStarted,
              let manifest,
              let expectedVersion = SpaceSwitcherMigrationConfiguration.packageVersion,
              stagedApplicationMatches(expectedVersion: expectedVersion) else {
            if manifest == nil { showFailure(SpaceSwitcherMigrationError.manifestInvalid) }
            return
        }

        stagedLaunchStarted = true
        stopMonitoringInstaller()
        do {
            try SpaceSwitcherMigrationStorage.write(manifest)
        } catch {
            stagedLaunchStarted = false
            showFailure(error)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--spaceswitcher-migration"]
        Self.logger.info("Requesting launch of the staged migration app.")
        NSWorkspace.shared.openApplication(
            at: SpaceSwitcherMigrationConfiguration.stagingApplicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.stagedLaunchStarted = false
                    Self.logger.error("Staged app launch request failed: \(error.localizedDescription, privacy: .private)")
                    self.showFailure(error)
                } else {
                    // The staged app terminates this bridge only after it has validated the
                    // manifest and is ready to replace the legacy app. Do not treat an
                    // accepted Launch Services request as proof that the migration started.
                    Self.logger.info("Launch Services accepted the staged app request; awaiting process startup.")
                    self.monitorStagedApplicationLaunch()
                }
            }
        }
    }

    private func monitorStagedApplicationLaunch() {
        stagedApplicationWasObserved = false
        stagedLaunchDeadline = Date().addingTimeInterval(20)
        stagedApplicationMonitor?.invalidate()
        stagedApplicationMonitor = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkStagedApplicationLaunch()
        }
    }

    private func checkStagedApplicationLaunch() {
        let stagingURL = SpaceSwitcherMigrationConfiguration.stagingApplicationURL.standardizedFileURL
        let isRunning = NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == SpaceSwitcherBundleIdentity.currentBundleIdentifier
                && application.bundleURL?.standardizedFileURL == stagingURL
                && !application.isTerminated
        }

        if isRunning {
            if !stagedApplicationWasObserved {
                Self.logger.info("Observed the staged migration app running.")
                stagedApplicationWasObserved = true
            }
            return
        }

        if stagedApplicationWasObserved {
            stopMonitoringStagedApplication()
            if !FileManager.default.fileExists(atPath: SpaceSwitcherMigrationStorage.manifestURL.path) {
                // The finalizer removes the manifest when it rolls back and presents its own
                // failure alert. Resume the untouched legacy app after that alert is dismissed.
                Self.logger.error("Staged app exited after clearing the handoff manifest; resuming the legacy app.")
                continueNormalApplication()
            } else {
                Self.logger.error("Staged app exited before claiming the handoff.")
                showFailure(SpaceSwitcherMigrationError.applicationLaunchFailed)
            }
            return
        }

        if let stagedLaunchDeadline, Date() > stagedLaunchDeadline {
            stopMonitoringStagedApplication()
            if !FileManager.default.fileExists(atPath: SpaceSwitcherMigrationStorage.manifestURL.path) {
                Self.logger.error("Staged app exited before monitoring observed it and cleared the manifest; resuming the legacy app.")
                continueNormalApplication()
            } else {
                Self.logger.error("Staged app process did not appear after the launch request.")
                showFailure(SpaceSwitcherMigrationError.applicationLaunchFailed)
            }
        }
    }

    private func showProgressNotice(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "SpaceSwitcher migration"
        alert.informativeText = message
        alert.addButton(withTitle: "Continue in Background")
        alert.runModal()
    }

    private func showFailure(_ error: Error) {
        downloadTask = nil
        stopMonitoringInstaller()
        stopMonitoringStagedApplication()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SpaceSwitcher migration was not completed"
        alert.informativeText = "\(error.localizedDescription) The existing app and its settings are still available."
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            startMigration()
        } else {
            SpaceSwitcherMigrationStorage.discardPendingMigration()
            continueNormalApplication()
        }
    }

    private func stopMonitoringInstaller() {
        installerMonitor?.invalidate()
        installerMonitor = nil
        installerLaunchDeadline = nil
        installDeadline = nil
        installerLaunchGate = MigrationInstallerLaunchGate()
        installerExitWaitLogged = false
    }

    private func stopMonitoringStagedApplication() {
        stagedApplicationMonitor?.invalidate()
        stagedApplicationMonitor = nil
        stagedLaunchDeadline = nil
        stagedApplicationWasObserved = false
    }

    private func continueNormalApplication() {
        stopMonitoringInstaller()
        stopMonitoringStagedApplication()
        let completion = self.completion
        self.completion = nil
        completion?()
    }
}
