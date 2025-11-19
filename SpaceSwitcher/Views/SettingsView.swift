import SwiftUI

let defaultSettingsWindowWidth = 417
let defaultSettingsWindowHeight = 480

enum SettingsTab: String {
    case general, rules, about
}

struct SettingsView: View {
    @ObservedObject var renamerClient: RenamerClient
    @ObservedObject var ruleEngine: RuleEngine
    
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralView(renamerClient: renamerClient)
                .tabItem {
                    Text("General")
                }
                .tag(SettingsTab.general)
            
            RulesView(ruleEngine: ruleEngine, renamerClient: renamerClient)
                .tabItem {
                    Text("Rules")
                }
                .tag(SettingsTab.general)
            
            AboutView()
                .tabItem {
                    Text("About")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight))
        .padding()
    }
}
