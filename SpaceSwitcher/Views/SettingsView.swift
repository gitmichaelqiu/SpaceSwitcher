import SwiftUI

struct SettingsView: View {
    @ObservedObject var renamerClient: RenamerClient
    @ObservedObject var ruleEngine: RuleEngine
    
    var body: some View {
        TabView {
            GeneralView(renamerClient: renamerClient)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            RulesView(ruleEngine: ruleEngine, renamerClient: renamerClient)
                .tabItem {
                    Label("Rules", systemImage: "list.bullet.rectangle.portrait")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 400)
        .padding()
    }
}
