import Foundation
import Combine
import AppKit

enum SpaceAPIAvailability: Equatable {
    case available
    case disabled
    case unavailable
}

enum RuleSpaceTransitionDetector {
    static func didVisibleSpacesChange(from previous: Set<String>, to current: Set<String>) -> Bool {
        previous != current
    }
}

final class SpaceManager: ObservableObject {
    // DesktopRenamer changed its application bundle identifier. Keep the
    // legacy identifier for users who still have the older release installed.
    static let desktopRenamerBundleIdentifiers = [
        "dev.mqiu.DesktopRenamer",
        "com.michaelqiu.DesktopRenamer"
    ]
    static let desktopRenamerDownloadURL = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer/releases/latest")!

    private let apiPrefix = "com.michaelqiu.DesktopRenamer"
    private let jsonRPCVersion = "2.0"
    private let payloadKey = "payload"

    // Structured SpaceAPI channels.
    private lazy var rpcRequest = Notification.Name("\(apiPrefix).RPCRequest")
    private lazy var rpcResponse = Notification.Name("\(apiPrefix).RPCResponse")
    private lazy var rpcEvent = Notification.Name("\(apiPrefix).RPCEvent")

    // Legacy channels remain supported for older DesktopRenamer releases.
    private lazy var legacyAPIState = Notification.Name("\(apiPrefix).ReturnAPIState")
    private lazy var legacyGetActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    private lazy var legacyGetSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    private lazy var legacyReturnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    private lazy var legacyReturnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")

    @Published var currentSpaceID: String?
    /// The active-display space captured at the last actual visible-space transition.
    /// Unlike `currentSpaceID`, this does not change when focus moves between displays.
    @Published private(set) var ruleEvaluationSpaceID: String?
    @Published var currentSpaceName: String = "Unknown"
    @Published var availableSpaces: [SpaceInfo] = []
    @Published var isAPIEnabled: Bool = false
    @Published private(set) var apiAvailability: SpaceAPIAvailability = .unavailable

    private var notificationObservers: [NSObjectProtocol] = []
    private var localNotificationObservers: [NSObjectProtocol] = []
    private var structuredAPIAvailable = false
    private var structuredProbeInFlight = false
    private var snapshotRequestInFlight = false
    private var structuredProbeGeneration = 0
    private var pendingRequests: [String: String] = [:]
    private var lastSnapshotRevision: UInt64?
    private var currentVisibleSpaceIDs = Set<String>()

    init() {
        startListening()
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        notificationObservers.forEach(center.removeObserver)
        localNotificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func startListening() {
        let center = DistributedNotificationCenter.default()

        notificationObservers.append(center.addObserver(
            forName: rpcResponse,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRPCResponse(notification)
        })

        notificationObservers.append(center.addObserver(
            forName: rpcEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRPCEvent(notification)
        })

        notificationObservers.append(center.addObserver(
            forName: legacyAPIState,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLegacyAPIState(notification)
        })

        notificationObservers.append(center.addObserver(
            forName: legacyReturnActiveSpace,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLegacyActiveSpace(notification)
        })

        notificationObservers.append(center.addObserver(
            forName: legacyReturnSpaceList,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLegacySpaceList(notification)
        })

        let localCenter = NotificationCenter.default
        localNotificationObservers.append(localCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSpaceList()
        })
        localNotificationObservers.append(localCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSpaceList()
        })

        // Prefer the structured contract and fall back to legacy notifications
        // if DesktopRenamer is an older release.
        requestStructuredAPIInfo()
    }

    func refreshSpaceList() {
        if structuredAPIAvailable {
            requestStructuredSnapshot()
        } else {
            requestStructuredAPIInfo()
        }
    }

    var desktopRenamerApplicationURL: URL? {
        Self.desktopRenamerBundleIdentifiers
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    func openDesktopRenamer() {
        guard let applicationURL = desktopRenamerApplicationURL else { return }
        NSWorkspace.shared.open(applicationURL)

        // DesktopRenamer starts its API listener after launch. Retry while it
        // finishes initializing so the status does not remain unavailable.
        for delay in [0.5, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshSpaceList()
            }
        }
    }

    func openDesktopRenamerDownloadPage() {
        NSWorkspace.shared.open(Self.desktopRenamerDownloadURL)
    }

    private func requestStructuredAPIInfo() {
        guard !structuredAPIAvailable, !structuredProbeInFlight else { return }

        structuredProbeInFlight = true
        structuredProbeGeneration += 1
        let generation = structuredProbeGeneration
        let requestID = UUID().uuidString
        pendingRequests[requestID] = "getAPIInfo"

        postStructuredRequest(id: requestID, method: "getAPIInfo")

        // Older DesktopRenamer versions do not know the RPC channel and will
        // never respond, so do not block the legacy path indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self,
                  self.structuredProbeGeneration == generation,
                  self.structuredProbeInFlight else { return }

            self.pendingRequests.removeValue(forKey: requestID)
            self.structuredProbeInFlight = false
            self.refreshLegacySpaceList()
        }
    }

    private func requestStructuredSnapshot() {
        guard !snapshotRequestInFlight else { return }

        snapshotRequestInFlight = true
        let requestID = UUID().uuidString
        pendingRequests[requestID] = "getSpaceSnapshot"
        postStructuredRequest(id: requestID, method: "getSpaceSnapshot")

        // Distributed notifications are best-effort. A timeout prevents a
        // stopped or suspended DesktopRenamer from leaving stale state alive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self,
                  self.pendingRequests.removeValue(forKey: requestID) == "getSpaceSnapshot" else {
                return
            }

            self.snapshotRequestInFlight = false
            self.setDisconnected()
            self.refreshLegacySpaceList()
        }
    }

    private func postStructuredRequest(id: String, method: String) {
        let request: [String: Any] = [
            "jsonrpc": jsonRPCVersion,
            "id": id,
            "method": method
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let payload = String(data: data, encoding: .utf8) else {
            print("SpaceSwitcher: Could not encode DesktopRenamer API request: \(method)")
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            rpcRequest,
            object: nil,
            userInfo: [payloadKey: payload],
            deliverImmediately: true
        )
    }

    private func handleRPCResponse(_ notification: Notification) {
        guard let payload = notification.userInfo?[payloadKey] as? String,
              let data = payload.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["jsonrpc"] as? String == jsonRPCVersion,
              let requestID = response["id"] as? String,
              let requestType = pendingRequests.removeValue(forKey: requestID) else {
            return
        }

        if requestType == "getSpaceSnapshot" {
            snapshotRequestInFlight = false
        }

        if let error = response["error"] as? [String: Any] {
            let code = (error["code"] as? NSNumber)?.intValue
            if code == -32001 {
                setDisconnected(as: .disabled)
            } else if code == -32002 {
                setDisconnected()
            } else if requestType == "getAPIInfo" {
                structuredProbeInFlight = false
                structuredAPIAvailable = false
                refreshLegacySpaceList()
            } else {
                structuredProbeInFlight = false
                isAPIEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.structuredAPIAvailable else { return }
                    self.requestStructuredSnapshot()
                }
            }
            return
        }

        guard let result = response["result"] as? [String: Any] else { return }

        switch requestType {
        case "getAPIInfo":
            let supportsSnapshots = (result["supportedMethods"] as? [String])?.contains("getSpaceSnapshot") == true
            let supportsJSONRPC = result["jsonRPCVersion"] as? String == jsonRPCVersion
            let contractVersion = result["contractVersion"] as? String
            guard supportsSnapshots && supportsJSONRPC,
                  let contractVersion,
                  isSupportedContractVersion(contractVersion) else {
                structuredProbeInFlight = false
                refreshLegacySpaceList()
                return
            }

            structuredProbeInFlight = false
            structuredAPIAvailable = true
            apiAvailability = .available
            isAPIEnabled = true
            requestStructuredSnapshot()

        case "getSpaceSnapshot":
            applyStructuredSnapshot(result, isEvent: false)

        default:
            break
        }
    }

    private func isSupportedContractVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".")
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return false
        }

        // Major versions can change the contract incompatibly. This client
        // supports the 1.x contract and must not opt into a future 2.x shape.
        return major == 1 && minor >= 0 && patch >= 0
    }

    private func handleRPCEvent(_ notification: Notification) {
        guard let payload = notification.userInfo?[payloadKey] as? String,
              let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["jsonrpc"] as? String == jsonRPCVersion,
              event["method"] as? String == "stateChanged",
              let params = event["params"] as? [String: Any],
              let snapshot = params["snapshot"] as? [String: Any] else {
            return
        }

        structuredAPIAvailable = true
        structuredProbeInFlight = false
        apiAvailability = .available
        applyStructuredSnapshot(snapshot, isEvent: true)
    }

    private func applyStructuredSnapshot(_ snapshot: [String: Any], isEvent: Bool) {
        guard let rawSpaces = snapshot["spaces"] as? [[String: Any]] else { return }

        let revision = (snapshot["revision"] as? NSNumber)?.uint64Value
        if isEvent, let revision, let lastRevision = lastSnapshotRevision {
            if revision <= lastRevision { return }
            if revision != lastRevision + 1 {
                requestStructuredSnapshot()
                return
            }
        }

        let spaces = rawSpaces.compactMap { rawSpace -> SpaceInfo? in
            guard let id = rawSpace["id"] as? String,
                  let name = rawSpace["name"] as? String,
                  let number = (rawSpace["number"] as? NSNumber)?.intValue else {
                return nil
            }
            let displayID = rawSpace["displayID"] as? String ?? "Main"
            let displayName = rawSpace["displayName"] as? String
                ?? self.displayName(for: displayID)
            return SpaceInfo(
                id: id,
                name: name,
                number: number,
                displayID: displayID,
                displayName: displayName
            )
        }.sorted { $0.number < $1.number }

        let currentSpaceIDs = snapshot["currentSpaceIDs"] as? [String] ?? []
        let snapshotCurrentSpaceID = snapshot["currentSpaceID"] as? String
        let nextVisibleSpaceIDs = currentSpaceIDs.isEmpty
            ? Set(snapshotCurrentSpaceID.map { [$0] } ?? [])
            : Set(currentSpaceIDs)
        let nextCurrentSpaceID = snapshotCurrentSpaceID
            ?? nextVisibleSpaceIDs.sorted().first
        let visibleSpacesChanged = RuleSpaceTransitionDetector.didVisibleSpacesChange(
            from: currentVisibleSpaceIDs,
            to: nextVisibleSpaceIDs
        )

        currentSpaceID = nextCurrentSpaceID
        currentSpaceName = snapshot["currentSpaceName"] as? String ?? "Unknown"
        availableSpaces = spaces
        isAPIEnabled = true
        apiAvailability = .available

        if visibleSpacesChanged {
            currentVisibleSpaceIDs = nextVisibleSpaceIDs
            ruleEvaluationSpaceID = nextCurrentSpaceID
        }

        if let revision {
            lastSnapshotRevision = revision
        }
    }

    private func handleLegacyAPIState(_ notification: Notification) {
        guard let isEnabled = notification.userInfo?["isEnabled"] as? Bool else { return }

        if isEnabled {
            if !structuredAPIAvailable {
                requestStructuredAPIInfo()
            } else {
                requestStructuredSnapshot()
            }
        } else {
            setDisconnected(as: .disabled)
        }
    }

    private func refreshLegacySpaceList() {
        guard !structuredAPIAvailable else { return }

        let center = DistributedNotificationCenter.default()
        center.postNotificationName(
            legacyGetSpaceList,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        center.postNotificationName(
            legacyGetActiveSpace,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func handleLegacyActiveSpace(_ notification: Notification) {
        guard !structuredAPIAvailable,
              let info = notification.userInfo else { return }

        currentSpaceID = info["spaceUUID"] as? String
        ruleEvaluationSpaceID = currentSpaceID
        currentSpaceName = info["spaceName"] as? String ?? "Unknown"
        isAPIEnabled = true
        apiAvailability = .available
    }

    private func handleLegacySpaceList(_ notification: Notification) {
        guard !structuredAPIAvailable,
              let info = notification.userInfo,
              let rawSpaces = info["spaces"] as? [[String: Any]] else { return }

        availableSpaces = rawSpaces.compactMap { rawSpace -> SpaceInfo? in
            guard let id = rawSpace["spaceUUID"] as? String,
                  let name = rawSpace["spaceName"] as? String,
                  let number = (rawSpace["spaceNumber"] as? NSNumber)?.intValue else {
                return nil
            }
            let displayID = rawSpace["displayID"] as? String ?? "Main"
            return SpaceInfo(
                id: id,
                name: name,
                number: number,
                displayID: displayID,
                displayName: displayName(for: displayID)
            )
        }.sorted { $0.number < $1.number }
        isAPIEnabled = true
        apiAvailability = .available
    }

    private func displayName(for displayID: String) -> String {
        if displayID.caseInsensitiveCompare("Main") == .orderedSame {
            return NSScreen.main?.localizedName ?? "Main Display"
        }

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value)?.takeRetainedValue(),
                  let uuidString = CFUUIDCreateString(nil, uuid) as String? else {
                continue
            }

            if uuidString.caseInsensitiveCompare(displayID) == .orderedSame {
                return screen.localizedName
            }
        }

        return displayID
    }

    private func setDisconnected(as availability: SpaceAPIAvailability = .unavailable) {
        structuredAPIAvailable = false
        structuredProbeInFlight = false
        snapshotRequestInFlight = false
        pendingRequests.removeAll()
        lastSnapshotRevision = nil
        apiAvailability = availability
        isAPIEnabled = false
        availableSpaces.removeAll()
        currentSpaceName = "Disconnected"
        currentSpaceID = nil
        ruleEvaluationSpaceID = nil
        currentVisibleSpaceIDs.removeAll()
    }
}
