import Combine
import Foundation

@MainActor
final class HUDToastSettings: ObservableObject {
    static let showHUDToastsKey = "showHUDToasts"
    static let shared = HUDToastSettings()

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.showHUDToastsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.showHUDToastsKey) as? Bool ?? true
    }
}
