import Foundation
import Combine
import AppKit

class RenamerClient: ObservableObject {
    // MARK: - Final API Constants
    private let apiPrefix = "com.michaelqiu.DesktopRenamer"
    
    // Requests
    private lazy var getActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    private lazy var getSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    
    // Returns
    private lazy var returnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    private lazy var returnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")
    private lazy var apiToggleState = Notification.Name("\(apiPrefix).ReturnAPIState")
    
    @Published var currentSpaceID: String?
    @Published var currentSpaceName: String = "Unknown"
    @Published var availableSpaces: [RenamerSpace] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        startListening()
    }
    
    func startListening() {
        print("CLIENT: Initializing Listener...")
        
        let dnc = DistributedNotificationCenter.default()
        
        // 1. Listen for Active Space Response
        dnc.addObserver(
            self,
            selector: #selector(handleActiveSpace(_:)),
            name: returnActiveSpace,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // 2. Listen for List Response
        dnc.addObserver(
            self,
            selector: #selector(handleSpaceList(_:)),
            name: returnSpaceList,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // 3. Listen for API Lifecycle (Toggle/Quit)
        dnc.addObserver(
            self,
            selector: #selector(handleAPIToggle(_:)),
            name: apiToggleState,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // 4. Trigger a refresh immediately
        refreshSpaceList()
    }
    
    func refreshSpaceList() {
        print("CLIENT: Sending Request -> \(getSpaceList.rawValue)")
        DistributedNotificationCenter.default().postNotificationName(
            getSpaceList,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        
        DistributedNotificationCenter.default().postNotificationName(
            getActiveSpace,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    // MARK: - Handlers
    
    @objc private func handleAPIToggle(_ note: Notification) {
        guard let info = note.userInfo,
              let isEnabled = info["isEnabled"] as? Bool else { return }
        
        print("CLIENT: API Toggle Received -> \(isEnabled)")
        
        DispatchQueue.main.async {
            if isEnabled {
                // API came back online: Refresh data
                self.refreshSpaceList()
            } else {
                // API went offline: Clear data to show disconnected state
                self.availableSpaces.removeAll()
                self.currentSpaceName = "Disconnected"
                self.currentSpaceID = nil
            }
        }
    }
    
    @objc private func handleActiveSpace(_ note: Notification) {
        guard let info = note.userInfo else { return }
        
        DispatchQueue.main.async {
            if let uuid = info["spaceUUID"] as? String {
                self.currentSpaceID = uuid
            }
            if let name = info["spaceName"] as? String {
                self.currentSpaceName = name
                print("CLIENT: Space changed to \(name)")
            }
        }
    }
    
    @objc private func handleSpaceList(_ note: Notification) {
        guard let info = note.userInfo,
              let rawSpaces = info["spaces"] as? [[String: Any]] else { return }
        
        DispatchQueue.main.async {
            self.availableSpaces = rawSpaces.compactMap { dict -> RenamerSpace? in
                guard let id = dict["spaceUUID"] as? String,
                      let name = dict["spaceName"] as? String,
                      let num = dict["spaceNumber"] as? NSNumber else { return nil }
                return RenamerSpace(id: id, name: name, number: num.intValue)
            }.sorted { $0.number < $1.number }
        }
    }
}
