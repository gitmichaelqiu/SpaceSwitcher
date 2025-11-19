import Foundation
import Combine
import AppKit

class RenamerClient: ObservableObject {
    // MARK: - Final API Constants (Must match DesktopRenamer)
    private let apiPrefix = "com.michaelqiu.DesktopRenamer"
    
    // Requests (Send these)
    private lazy var getActiveSpace = Notification.Name("\(apiPrefix).GetActiveSpace")
    private lazy var getSpaceList = Notification.Name("\(apiPrefix).GetSpaceList")
    
    // Responses (Listen for these)
    private lazy var returnActiveSpace = Notification.Name("\(apiPrefix).ReturnActiveSpace")
    private lazy var returnSpaceList = Notification.Name("\(apiPrefix).ReturnSpaceList")
    
    @Published var currentSpaceID: String?
    @Published var currentSpaceName: String = "Unknown"
    @Published var availableSpaces: [RenamerSpace] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Intentionally empty
    }
    
    func startListening() {
        print("CLIENT: Initializing Listener...")
        print("CLIENT: Listening for -> \(returnSpaceList.rawValue)")
        
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
        
        // 3. Trigger a refresh immediately
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
        
        // Also refresh active space just in case
        DistributedNotificationCenter.default().postNotificationName(
            getActiveSpace,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    @objc private func handleActiveSpace(_ note: Notification) {
        print("CLIENT: Success! Received Active Space.")
        guard let info = note.userInfo else { return }
        
        DispatchQueue.main.async {
            if let uuid = info["spaceUUID"] as? String {
                self.currentSpaceID = uuid
            }
            if let name = info["spaceName"] as? String {
                self.currentSpaceName = name
            }
        }
    }
    
    @objc private func handleSpaceList(_ note: Notification) {
        print("CLIENT: Success! Received Space List.")
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
