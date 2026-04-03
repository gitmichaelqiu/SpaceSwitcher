import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, rules, dock, permissions, about
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .rules: return "Rules"
        case .dock: return "Docks"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .rules: return "list.bullet.rectangle.portrait"
        case .dock: return "dock.rectangle"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

// Layout Constants
let sidebarWidth: CGFloat = 200
let defaultSettingsWindowWidth = 1050
let defaultSettingsWindowHeight = 650
let sidebarRowHeight: CGFloat = 36
let sidebarFontSize: CGFloat = 14
let titleHeaderHeight: CGFloat = 52

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var dockManager: DockManager
    
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
        .frame(minWidth: CGFloat(defaultSettingsWindowWidth), minHeight: CGFloat(defaultSettingsWindowHeight))
    }
    
    // MARK: - Sidebar
    @ViewBuilder
    private var sidebar: some View {
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
        .modifier(SidebarToggleRemover())
        .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
        .edgesIgnoringSafeArea(.top)
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: -2) {
            Color.clear.frame(height: 54) // Better alignment with traffic lights
            
            Text("Space")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
            Text("Switcher")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.bottom, 16)
        }
    }
    
    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName)
                    .font(.system(size: sidebarFontSize, weight: .medium))
                    .padding(.leading, 4)
            } icon: {
                Image(systemName: tab.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(selectedTab == tab ? .white : .accentColor)
            }
        }
        .frame(height: sidebarRowHeight)
    }
    
    // MARK: - Detail View
    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .top) {
            // 1. CONTENT LAYER
            ScrollView {
                VStack(spacing: 0) {
                    if let tab = selectedTab {
                        switch tab {
                        case .general:
                            GeneralSettingsView(spaceManager: spaceManager)
                        case .rules:
                            RulesView(ruleManager: ruleManager, spaceManager: spaceManager)
                        case .dock:
                            DockSettingsView(dockManager: dockManager, spaceManager: spaceManager)
                        case .permissions:
                            PermissionsSettingsView()
                        case .about:
                            AboutView()
                        }
                    }
                }
                .padding(.top, titleHeaderHeight + 20)
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
            
            // 2. HEADER LAYER
            if let tab = selectedTab {
                VStack(spacing: 0) {
                    HStack {
                        Text(tab.localizedName)
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.leading, 30)
                        Spacer()
                    }
                    .frame(height: titleHeaderHeight)
                    .background(.ultraThinMaterial)
                    
                    Divider()
                        .opacity(0.4)
                }
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

// MARK: - Modifiers
struct SidebarToggleRemover: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
                .toolbar { Color.clear }
        } else {
            content
        }
    }
}
