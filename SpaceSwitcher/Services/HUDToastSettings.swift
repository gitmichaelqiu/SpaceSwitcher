import Combine
import Foundation

@MainActor
final class HUDToastSettings: ObservableObject {
    static let showHUDToastsKey = "showHUDToasts"
    static let showRuleHUDToastsKey = "showRuleHUDToasts"
    static let showDockHUDToastsKey = "showDockHUDToasts"
    static let shared = HUDToastSettings()

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.showHUDToastsKey)
        }
    }

    @Published var isRuleHUDEnabled: Bool {
        didSet {
            defaults.set(isRuleHUDEnabled, forKey: Self.showRuleHUDToastsKey)
        }
    }

    @Published var isDockHUDEnabled: Bool {
        didSet {
            defaults.set(isDockHUDEnabled, forKey: Self.showDockHUDToastsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.showHUDToastsKey) as? Bool ?? true
        self.isRuleHUDEnabled = defaults.object(forKey: Self.showRuleHUDToastsKey) as? Bool ?? true
        self.isDockHUDEnabled = defaults.object(forKey: Self.showDockHUDToastsKey) as? Bool ?? true
    }
}
