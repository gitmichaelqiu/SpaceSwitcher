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

// Layout Constants - Standardized for macOSers bundle
let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth = 1100
let defaultSettingsWindowHeight = 650
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 16
let titleHeaderHeight: CGFloat = 48

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
        .navigationSplitViewStyle(.prominentDetail)
        .navigationTitle("")
        .modifier(ToolbarHider())
        .edgesIgnoringSafeArea(.top)
        .frame(width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight))
    }
    
    struct ToolbarHider: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.toolbar(.hidden, for: .windowToolbar)
            } else {
                content
            }
        }
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
        .navigationSplitViewColumnWidth(sidebarWidth)
        .edgesIgnoringSafeArea(.top)
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
                    .frame(height: sidebarRowHeight - 15)
            }
        }
        .frame(height: sidebarRowHeight)
    }
    
    // MARK: - Detail View
    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .top) {
            // 1. CONTENT LAYER - Removed outer ScrollView to fix HSplitView collapse
            VStack(alignment: .leading, spacing: 0) {
                if let tab = selectedTab {
                    // Use a top-aligned ZStack and smooth fade transition
                    ZStack(alignment: .topLeading) {
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
                    .id(tab)
                    .transition(.opacity)
                }
            }
            .padding(.top, titleHeaderHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // 2. HEADER LAYER
            if let tab = selectedTab {
                VStack(spacing: 0) {
                    HStack {
                        Text(tab.localizedName)
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.leading, 20)
                        
                        Spacer()
                        
                        // Tab Specific Actions
                        headerActions(for: tab)
                            .padding(.trailing, 20)
                    }
                    .frame(height: titleHeaderHeight)
                    .background(.bar)
                    
                    Divider()
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
    
    @ViewBuilder
    private func headerActions(for tab: SettingsTab) -> some View {
        switch tab {
        case .rules:
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("AddRuleRequest"), object: nil)
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        default:
            EmptyView()
        }
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
