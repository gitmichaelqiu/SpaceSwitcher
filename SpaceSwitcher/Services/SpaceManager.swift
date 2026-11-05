import Foundation
import Combine
import AppKit
import Network
import Darwin

enum SpaceAPIAvailability: Equatable {
    case available
    case disabled
    case accessDenied
    case unavailable
}

private struct SpaceAPIContractVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = normalized.first == "v" || normalized.first == "V"
            ? String(normalized.dropFirst())
            : normalized
        let components = version.split(separator: ".")
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    static let structuredAPI = Self("1.0.0")!
    static let stableSpaceIDs = Self("1.2.0")!
    static let unixSocketTransport = Self("1.3.0")!
}

private struct PendingSpaceAPIRequest {
    let method: String
    let usesSocket: Bool
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

    private static let apiPrefixes = [
        "dev.mqiu.DesktopRenamer",
        "com.michaelqiu.DesktopRenamer"
    ]
    private let jsonRPCVersion = "2.0"
    private let payloadKey = "payload"
    private let maximumPayloadBytes = 1_048_576
    private let networkQueue = DispatchQueue.main

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
    private var pendingRequests: [String: PendingSpaceAPIRequest] = [:]
    private var lastSnapshotRevision: UInt64?
    private var currentVisibleSpaceIDs = Set<String>()
    private var usingLegacyNotificationTransport = false
    private var legacyNotificationPrefix = "dev.mqiu.DesktopRenamer"
    private var legacyContractVersion: SpaceAPIContractVersion?
    private var legacyVersionProbeInFlight = false
    private var legacyVersionProbeGeneration = 0
    private var legacyVersionProbeLastAttempt: Date?
    private var contractVersion: SpaceAPIContractVersion?
    private var structuredIdentifiersAreStable = false
    private var managedSpaceIDToStableSpaceID: [String: String] = [:]
    private var socketEndpointPath: String?
    private var socketConnection: NWConnection?
    private var socketReceiveBuffer = Data()
    private var socketReconnectWorkItem: DispatchWorkItem?

    init() {
        startListening()
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        notificationObservers.forEach(center.removeObserver)
        localNotificationObservers.forEach(NotificationCenter.default.removeObserver)
        socketConnection?.cancel()
    }

    private func startListening() {
        let center = DistributedNotificationCenter.default()

        for prefix in Self.apiPrefixes {
            notificationObservers.append(center.addObserver(
                forName: notificationName("RPCResponse", prefix: prefix),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleRPCResponse(notification)
            })

            notificationObservers.append(center.addObserver(
                forName: notificationName("RPCEvent", prefix: prefix),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleRPCEvent(notification)
            })

            notificationObservers.append(center.addObserver(
                forName: notificationName("ReturnAPIState", prefix: prefix),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleLegacyAPIState(notification)
            })

            notificationObservers.append(center.addObserver(
                forName: notificationName("ReturnActiveSpace", prefix: prefix),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleLegacyActiveSpace(notification)
            })

            notificationObservers.append(center.addObserver(
                forName: notificationName("ReturnSpaceList", prefix: prefix),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleLegacySpaceList(notification)
            })

            notificationObservers.append(center.addObserver(
                forName: notificationName("ReturnAPIVersion", prefix: prefix),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleLegacyAPIVersion(notification, prefix: prefix)
            })
        }

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

        connectSocket()
    }

    func refreshSpaceList() {
        if apiAvailability == .accessDenied {
            reconnectSocket()
            return
        }

        if socketConnection?.state == .ready {
            if structuredAPIAvailable {
                requestStructuredSnapshot()
            } else {
                requestStructuredAPIInfo()
            }
            return
        }

        connectSocket()
        guard usingLegacyNotificationTransport else { return }
        if legacyContractVersion.map({ $0 >= .structuredAPI }) == true {
            if structuredAPIAvailable {
                requestStructuredSnapshot()
            } else {
                requestStructuredAPIInfo()
            }
        } else {
            refreshLegacySpaceList()
        }
    }

    private func notificationName(_ suffix: String, prefix: String) -> Notification.Name {
        Notification.Name("\(prefix).\(suffix)")
    }

    var desktopRenamerApplicationURL: URL? {
        Self.desktopRenamerBundleIdentifiers
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    func openDesktopRenamer() {
        guard let applicationURL = desktopRenamerApplicationURL else { return }
        NSWorkspace.shared.open(applicationURL)
        guard apiAvailability != .accessDenied else { return }

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

    private var defaultSocketEndpointPath: String {
        "/tmp/dev.mqiu.DesktopRenamer-\(getuid()).sock"
    }

    private func connectSocket() {
        guard socketConnection == nil else { return }

        socketReconnectWorkItem?.cancel()
        socketReconnectWorkItem = nil
        socketReceiveBuffer.removeAll(keepingCapacity: true)

        let endpointPath = socketEndpointPath ?? defaultSocketEndpointPath
        let connection = NWConnection(to: .unix(path: endpointPath), using: .tcp)
        socketConnection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.socketConnection === connection else { return }
            switch state {
            case .ready:
                self.handleSocketReady(connection)
            case .failed(let error):
                self.handleSocketFailure(connection, error: error)
            case .cancelled:
                self.handleSocketFailure(connection, error: nil)
            case .waiting(let error):
                print("SpaceSwitcher: Waiting for DesktopRenamer SpaceAPI socket: \(error)")
            default:
                break
            }
        }
        connection.start(queue: networkQueue)
    }

    private func reconnectSocket() {
        socketReconnectWorkItem?.cancel()
        socketReconnectWorkItem = nil
        let previousConnection = socketConnection
        socketConnection = nil
        previousConnection?.stateUpdateHandler = nil
        previousConnection?.cancel()
        socketReceiveBuffer.removeAll(keepingCapacity: true)
        structuredAPIAvailable = false
        structuredProbeInFlight = false
        snapshotRequestInFlight = false
        pendingRequests.removeAll()
        lastSnapshotRevision = nil
        connectSocket()
    }

    private func handleSocketReady(_ connection: NWConnection) {
        guard socketConnection === connection else { return }

        legacyVersionProbeInFlight = false
        legacyVersionProbeGeneration += 1

        if usingLegacyNotificationTransport {
            usingLegacyNotificationTransport = false
            legacyContractVersion = nil
            setDisconnected()
        }

        structuredProbeInFlight = false
        snapshotRequestInFlight = false
        pendingRequests.removeAll()
        lastSnapshotRevision = nil
        receiveSocketData(from: connection)
        requestStructuredAPIInfo()
    }

    private func handleSocketFailure(_ connection: NWConnection, error: NWError?) {
        guard socketConnection === connection else { return }

        socketConnection = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        socketReceiveBuffer.removeAll(keepingCapacity: true)
        structuredProbeInFlight = false
        snapshotRequestInFlight = false
        pendingRequests.removeAll()
        lastSnapshotRevision = nil

        if !usingLegacyNotificationTransport,
           apiAvailability != .disabled,
           apiAvailability != .accessDenied {
            setDisconnected()
        }
        if !usingLegacyNotificationTransport {
            probeForLegacyContractVersion()
        }
        if let error {
            print("SpaceSwitcher: DesktopRenamer SpaceAPI socket disconnected: \(error)")
        }
        scheduleSocketReconnect()
    }

    private func scheduleSocketReconnect() {
        guard apiAvailability != .accessDenied,
              !usingLegacyNotificationTransport else { return }
        socketReconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.connectSocket()
        }
        socketReconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func receiveSocketData(from connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: maximumPayloadBytes + 4
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection, self.socketConnection === connection else { return }

            if let data, !data.isEmpty {
                self.socketReceiveBuffer.append(data)
                guard self.consumeSocketFrames(from: connection) else { return }
            }

            if let error {
                self.handleSocketFailure(connection, error: error)
            } else if isComplete {
                self.handleSocketFailure(connection, error: nil)
            } else {
                self.receiveSocketData(from: connection)
            }
        }
    }

    @discardableResult
    private func consumeSocketFrames(from connection: NWConnection) -> Bool {
        while socketReceiveBuffer.count >= 4 {
            let header = socketReceiveBuffer.prefix(4)
            let payloadLength = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard payloadLength > 0, payloadLength <= UInt32(maximumPayloadBytes) else {
                print("SpaceSwitcher: DesktopRenamer sent an invalid SpaceAPI frame length")
                handleSocketFailure(connection, error: nil)
                return false
            }

            let frameLength = 4 + Int(payloadLength)
            guard socketReceiveBuffer.count >= frameLength else { return true }

            let payloadData = socketReceiveBuffer.subdata(in: 4..<frameLength)
            socketReceiveBuffer.removeSubrange(0..<frameLength)
            guard let payload = String(data: payloadData, encoding: .utf8) else {
                print("SpaceSwitcher: DesktopRenamer sent a non-UTF-8 SpaceAPI message")
                handleSocketFailure(connection, error: nil)
                return false
            }
            handleRPCMessage(payload: payload)
        }

        return true
    }

    private func probeForLegacyContractVersion() {
        guard !legacyVersionProbeInFlight,
              Date().timeIntervalSince(legacyVersionProbeLastAttempt ?? .distantPast) >= 2 else {
            return
        }

        // DNC is only a compatibility path. Confirm that the peer predates
        // socket support before enabling it; socket errors and denials do not
        // fall back to unauthenticated requests.
        legacyVersionProbeInFlight = true
        legacyVersionProbeLastAttempt = Date()
        legacyVersionProbeGeneration += 1
        let generation = legacyVersionProbeGeneration
        let center = DistributedNotificationCenter.default()
        for prefix in Self.apiPrefixes {
            center.postNotificationName(
                notificationName("GetAPIVersion", prefix: prefix),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.legacyVersionProbeGeneration == generation else { return }
            self.legacyVersionProbeInFlight = false
        }
    }

    private func handleLegacyAPIVersion(_ notification: Notification, prefix: String) {
        guard legacyVersionProbeInFlight,
              let versionString = notification.userInfo?["apiVersion"] as? String,
              let version = SpaceAPIContractVersion(versionString) else {
            return
        }

        legacyVersionProbeInFlight = false
        legacyVersionProbeGeneration += 1
        guard version < .unixSocketTransport else { return }

        socketReconnectWorkItem?.cancel()
        socketReconnectWorkItem = nil
        usingLegacyNotificationTransport = true
        legacyNotificationPrefix = prefix
        legacyContractVersion = version
        contractVersion = version
        structuredIdentifiersAreStable = false
        managedSpaceIDToStableSpaceID.removeAll()
        if version >= .structuredAPI {
            requestStructuredAPIInfo()
        } else {
            refreshLegacySpaceList()
        }
    }

    private func requestStructuredAPIInfo() {
        guard !structuredAPIAvailable, !structuredProbeInFlight else { return }

        guard socketConnection?.state == .ready || usingLegacyNotificationTransport else {
            connectSocket()
            return
        }

        structuredProbeInFlight = true
        structuredProbeGeneration += 1
        let generation = structuredProbeGeneration
        let requestID = UUID().uuidString
        let usesSocket = !usingLegacyNotificationTransport
        pendingRequests[requestID] = PendingSpaceAPIRequest(method: "getAPIInfo", usesSocket: usesSocket)

        postStructuredRequest(id: requestID, method: "getAPIInfo")

        // A new socket request can wait for the user's SpaceAPI approval.
        // The compatibility notification path is best-effort and has no ID.
        let timeout: TimeInterval = usesSocket ? 125 : 0.75
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self,
                  self.structuredProbeGeneration == generation,
                  self.structuredProbeInFlight else { return }

            self.pendingRequests.removeValue(forKey: requestID)
            self.structuredProbeInFlight = false
            if usesSocket {
                self.reconnectSocket()
            } else {
                self.refreshLegacySpaceList()
            }
        }
    }

    private func requestStructuredSnapshot() {
        guard structuredAPIAvailable,
              !snapshotRequestInFlight,
              socketConnection?.state == .ready || usingLegacyNotificationTransport else {
            return
        }

        snapshotRequestInFlight = true
        let requestID = UUID().uuidString
        let usesSocket = !usingLegacyNotificationTransport
        pendingRequests[requestID] = PendingSpaceAPIRequest(method: "getSpaceSnapshot", usesSocket: usesSocket)
        postStructuredRequest(id: requestID, method: "getSpaceSnapshot")

        // Socket responses are expected quickly; DNC responses are best-effort.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self,
                  self.pendingRequests.removeValue(forKey: requestID)?.method == "getSpaceSnapshot" else {
                return
            }

            self.snapshotRequestInFlight = false
            if usesSocket {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.requestStructuredSnapshot()
                }
            } else {
                self.setDisconnected()
                self.refreshLegacySpaceList()
            }
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
            pendingRequests.removeValue(forKey: id)
            if method == "getAPIInfo" { structuredProbeInFlight = false }
            if method == "getSpaceSnapshot" { snapshotRequestInFlight = false }
            return
        }

        if pendingRequests[id]?.usesSocket == true,
           let socketConnection,
           socketConnection.state == .ready {
            guard data.count <= maximumPayloadBytes else {
                pendingRequests.removeValue(forKey: id)
                return
            }

            var frame = Data()
            var payloadLength = UInt32(data.count).bigEndian
            withUnsafeBytes(of: &payloadLength) { frame.append(contentsOf: $0) }
            frame.append(data)
            socketConnection.send(content: frame, completion: .contentProcessed { [weak self, weak socketConnection] error in
                guard let self, let socketConnection,
                      self.socketConnection === socketConnection,
                      let error else { return }
                self.handleSocketFailure(socketConnection, error: error)
            })
            return
        }

        guard usingLegacyNotificationTransport else {
            pendingRequests.removeValue(forKey: id)
            if method == "getAPIInfo" { structuredProbeInFlight = false }
            if method == "getSpaceSnapshot" { snapshotRequestInFlight = false }
            scheduleSocketReconnect()
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName("RPCRequest", prefix: legacyNotificationPrefix),
            object: nil,
            userInfo: [payloadKey: payload],
            deliverImmediately: true
        )
    }

    private func handleRPCResponse(_ notification: Notification) {
        guard let payload = notification.userInfo?[payloadKey] as? String else { return }
        handleRPCResponse(payload: payload)
    }

    private func handleRPCMessage(payload: String) {
        guard let data = payload.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["jsonrpc"] as? String == jsonRPCVersion else {
            return
        }

        if message["id"] != nil {
            handleRPCResponse(payload: payload)
        } else if message["method"] as? String == "stateChanged" {
            handleRPCEvent(payload: payload)
        }
    }

    private func handleRPCResponse(payload: String) {
        guard let data = payload.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["jsonrpc"] as? String == jsonRPCVersion,
              let requestID = response["id"] as? String,
              let pendingRequest = pendingRequests.removeValue(forKey: requestID) else {
            return
        }
        let requestType = pendingRequest.method

        if requestType == "getSpaceSnapshot" {
            snapshotRequestInFlight = false
        }
        if requestType == "getAPIInfo" {
            structuredProbeInFlight = false
        }

        if let error = response["error"] as? [String: Any] {
            let code = (error["code"] as? NSNumber)?.intValue
            if code == -32001 {
                setDisconnected(as: .disabled)
            } else if code == -32003 && pendingRequest.usesSocket {
                print("SpaceSwitcher: This app is not approved for DesktopRenamer SpaceAPI")
                setDisconnected(as: .accessDenied)
            } else if code == -32002 {
                setDisconnected(as: .unavailable)
                if pendingRequest.usesSocket {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        self?.requestStructuredAPIInfo()
                    }
                } else {
                    refreshLegacySpaceList()
                }
            } else if requestType == "getAPIInfo" {
                structuredAPIAvailable = false
                if pendingRequest.usesSocket {
                    setDisconnected()
                } else {
                    refreshLegacySpaceList()
                }
            } else {
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
            let contractVersionString = result["contractVersion"] as? String
            guard supportsSnapshots && supportsJSONRPC,
                  let contractVersionString,
                  let contractVersion = SpaceAPIContractVersion(contractVersionString),
                  isSupportedContractVersion(contractVersion) else {
                if pendingRequest.usesSocket {
                    setDisconnected()
                } else {
                    structuredAPIAvailable = false
                    refreshLegacySpaceList()
                }
                return
            }

            self.contractVersion = contractVersion
            structuredIdentifiersAreStable = contractVersion >= .stableSpaceIDs
            if let endpoint = result["socketEndpoint"] as? String, endpoint.hasPrefix("/") {
                socketEndpointPath = endpoint
            }
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

    private func isSupportedContractVersion(_ version: SpaceAPIContractVersion) -> Bool {
        // Major versions can change the contract incompatibly. This client
        // supports the 1.x contract and must not opt into a future 2.x shape.
        return version.major == 1
    }

    private func handleRPCEvent(_ notification: Notification) {
        guard usingLegacyNotificationTransport,
              let payload = notification.userInfo?[payloadKey] as? String else { return }
        handleRPCEvent(payload: payload)
    }

    private func handleRPCEvent(payload: String) {
        guard let data = payload.data(using: .utf8),
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

        if let apiVersion = snapshot["apiVersion"] as? String,
           let version = SpaceAPIContractVersion(apiVersion) {
            contractVersion = version
            structuredIdentifiersAreStable = version >= .stableSpaceIDs
        }

        let revision = (snapshot["revision"] as? NSNumber)?.uint64Value
        if let revision, let lastRevision = lastSnapshotRevision {
            if isEvent {
                if revision <= lastRevision { return }
                if revision != lastRevision + 1 {
                    requestStructuredSnapshot()
                    return
                }
            } else if revision < lastRevision {
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
                managedSpaceID: rawSpace["managedSpaceID"] as? String,
                name: name,
                number: number,
                displayID: displayID,
                displayName: displayName
            )
        }.sorted { $0.number < $1.number }

        var nextManagedSpaceIDMap: [String: String] = [:]
        for space in spaces {
            if let managedSpaceID = space.managedSpaceID {
                nextManagedSpaceIDMap[managedSpaceID] = space.id
            }
        }
        managedSpaceIDToStableSpaceID = nextManagedSpaceIDMap

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
            if usingLegacyNotificationTransport {
                if legacyContractVersion.map({ $0 >= .structuredAPI }) == true {
                    if !structuredAPIAvailable { requestStructuredAPIInfo() }
                    else { requestStructuredSnapshot() }
                } else {
                    refreshLegacySpaceList()
                }
            } else {
                refreshSpaceList()
            }
        } else {
            setDisconnected(as: .disabled)
        }
    }

    private func refreshLegacySpaceList() {
        guard usingLegacyNotificationTransport, !structuredAPIAvailable else { return }

        let center = DistributedNotificationCenter.default()
        center.postNotificationName(
            notificationName("GetSpaceList", prefix: legacyNotificationPrefix),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        center.postNotificationName(
            notificationName("GetActiveSpace", prefix: legacyNotificationPrefix),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func handleLegacyActiveSpace(_ notification: Notification) {
        guard usingLegacyNotificationTransport,
              !structuredAPIAvailable,
              let info = notification.userInfo else { return }

        currentSpaceID = info["spaceUUID"] as? String
        ruleEvaluationSpaceID = currentSpaceID
        currentSpaceName = info["spaceName"] as? String ?? "Unknown"
        isAPIEnabled = true
        apiAvailability = .available
    }

    private func handleLegacySpaceList(_ notification: Notification) {
        guard usingLegacyNotificationTransport,
              !structuredAPIAvailable,
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
                managedSpaceID: id,
                name: name,
                number: number,
                displayID: displayID,
                displayName: displayName(for: displayID)
            )
        }.sorted { $0.number < $1.number }
        isAPIEnabled = true
        apiAvailability = .available
    }

    func ruleSpaceIDs(forManagedSpaceIDs managedSpaceIDs: Set<String>) -> Set<String> {
        guard structuredIdentifiersAreStable else { return managedSpaceIDs }
        return Set(managedSpaceIDs.compactMap { managedSpaceIDToStableSpaceID[$0] })
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
        contractVersion = nil
        structuredIdentifiersAreStable = false
        managedSpaceIDToStableSpaceID.removeAll()
        apiAvailability = availability
        isAPIEnabled = false
        availableSpaces.removeAll()
        currentSpaceName = "Disconnected"
        currentSpaceID = nil
        ruleEvaluationSpaceID = nil
        currentVisibleSpaceIDs.removeAll()
    }
}
