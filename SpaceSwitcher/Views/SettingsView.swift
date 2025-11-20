import SwiftUI

// Window size constants are now in SettingsViewController.swift

enum SettingsTab: String {
    case general, rules, about
}

struct SettingsView: View {
    @ObservedObject var renamerClient: RenamerClient
    @ObservedObject var ruleEngine: RuleEngine
    
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general
    
    var body: some View {
        // Adopt OptClicker's TabView style
        if #available(macOS 15.0, *) {
            TabView(selection: $selectedTab) {
                Tab("General", systemImage: "gearshape.fill", value: .general) {
                    GeneralView(renamerClient: renamerClient)
                }
                Tab("Rules", systemImage: "list.bullet.rectangle.portrait.fill", value: .rules) {
                    RulesView(ruleEngine: ruleEngine, renamerClient: renamerClient)
                }
                Tab("About", systemImage: "info.circle.fill", value: .about) {
                    AboutView()
                }
            }
            .scenePadding()
        } else {
            // macOS 14.0 and earlier compatibility, as in OptClicker
            TabView(selection: $selectedTab) {
                GeneralView(renamerClient: renamerClient)
                   .tabItem {
                       Label(
                           "General",
                           systemImage: "gearshape.fill"
                       )
                   }
                   .tag(SettingsTab.general)

                RulesView(ruleEngine: ruleEngine, renamerClient: renamerClient)
                   .tabItem {
                       Label(
                           "Rules",
                           systemImage: "list.bullet.rectangle.portrait.fill"
                       )
                   }
                   .tag(SettingsTab.rules)

                AboutView()
                   .tabItem {
                       Label(
                           "About",
                           systemImage: "info.circle.fill"
                       )
                   }
                   .tag(SettingsTab.about)
                }
                .scenePadding()
        }
    }
}
