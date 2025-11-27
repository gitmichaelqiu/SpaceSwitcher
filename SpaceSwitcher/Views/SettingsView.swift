import SwiftUI

enum SettingsTab: String {
    case general, rules, about
}

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var ruleManager: RuleManager
    
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general
    
    var body: some View {
        if #available(macOS 15.0, *) {
            TabView(selection: $selectedTab) {
                Tab("General", systemImage: "gearshape.fill", value: .general) {
                    GeneralSettingsView(spaceManager: spaceManager)
                }
                Tab("Rules", systemImage: "list.bullet.rectangle.portrait.fill", value: .rules) {
                    RulesView(ruleManager: ruleManager, spaceManager: spaceManager)
                }
                Tab("About", systemImage: "info.circle.fill", value: .about) {
                    AboutView()
                }
            }
            .scenePadding()
        } else {
            TabView(selection: $selectedTab) {
                GeneralSettingsView(spaceManager: spaceManager)
                   .tabItem {
                       Label(
                           "General",
                           systemImage: "gearshape.fill"
                       )
                   }
                   .tag(SettingsTab.general)

                RulesView(ruleManager: ruleManager, spaceManager: spaceManager)
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
