import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, rules, dock, about
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .rules: return "Rules"
        case .dock: return "Docks"
        case .about: return "About"
        }
    }
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .rules: return "list.bullet.rectangle.portrait"
        case .dock: return "dock.rectangle"
        case .about: return "info.circle"
        }
    }
}

// Layout Constants matching DesktopRenamer
let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth = 750 // Increased width for better layout
let defaultSettingsWindowHeight = 550
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 16
let titleHeaderHeight: CGFloat = 48

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var dockManager: DockManager
    
    // Controlled by parent or defaults
    @State var selectedTab: SettingsTab? = .general
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .windowToolbar)
        .edgesIgnoringSafeArea(.top)
        .frame(width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight))
    }
    
    // MARK: - Sidebar
    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 14.0, *) {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarItem(for: tab)
                    }
                } header: {
                    headerView
                }
                .collapsible(false)
            }
            .scrollDisabled(true)
            .removeSidebarToggle()
            .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
            .edgesIgnoringSafeArea(.top)
        } else {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarItem(for: tab)
                    }
                } header: {
                    headerView
                }
                .collapsible(false)
            }
            .scrollDisabled(true)
            .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
            .listStyle(.sidebar)
            .edgesIgnoringSafeArea(.top)
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 45)
            
            Text("Space")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.primary)
            Text("Switcher")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.primary)
                .padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName)
                    .font(.system(size: sidebarFontSize, weight: .medium))
                    .padding(.leading, 2)
            } icon: {
                Image(systemName: tab.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: sidebarRowHeight-15)
            }
        }
        .frame(height: sidebarRowHeight)
    }
    
    // MARK: - Detail View (Content + Blurred Header)
    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .top) {
            
            // 1. CONTENT LAYER
            ZStack(alignment: .top) {
                if let tab = selectedTab {
                    switch tab {
                    case .general:
                        GeneralSettingsView(spaceManager: spaceManager)
                    case .rules:
                        RulesView(ruleManager: ruleManager, spaceManager: spaceManager)
                            .padding(.horizontal)
                            .padding(.bottom)
                    case .dock:
                        DockSettingsView(dockManager: dockManager, spaceManager: spaceManager)
                    case .about:
                        AboutView()
                    }
                } else {
                    Text("Select a category")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, titleHeaderHeight) // Push content below header
            
            // 2. HEADER LAYER (Blurry Title Bar)
            if let tab = selectedTab {
                VStack(spacing: 0) {
                    HStack {
                        Text(tab.localizedName)
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.leading, 20)
                        Spacer()
                    }
                    .frame(height: titleHeaderHeight)
                    .background(.bar) // Native blur material
                    
                    Divider()
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
}

// MARK: - Hosting Controller
class SettingsHostingController: NSHostingController<SettingsView> {
    
    init(spaceManager: SpaceManager, ruleManager: RuleManager, dockManager: DockManager, startTab: SettingsTab? = nil) {
        let rootView = SettingsView(
            spaceManager: spaceManager,
            ruleManager: ruleManager,
            dockManager: dockManager,
            selectedTab: startTab ?? .general
        )
        super.init(rootView: rootView)
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.preferredContentSize = NSSize(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
    }
}
