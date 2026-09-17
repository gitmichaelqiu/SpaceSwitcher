import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, rules, dock, permissions, about

    var id: String { rawValue }

    var localizedName: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .rules: "Rules"
        case .dock: "Docks"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: "gearshape"
        case .rules: "list.bullet.below.rectangle"
        case .dock: "dock.arrow.up.rectangle"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth = 900
let defaultSettingsWindowHeight = 600
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 16
let titleHeaderHeight: CGFloat = 48

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var ruleManager: RuleManager
    @ObservedObject var dockManager: DockManager

    @StateObject private var navigationState = SettingsNavigationState()
    @State private var selectedTab: SettingsTab?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var isIndexingSettings = true

    init(
        spaceManager: SpaceManager,
        ruleManager: RuleManager,
        dockManager: DockManager,
        selectedTab: SettingsTab = .general
    ) {
        self.spaceManager = spaceManager
        self.ruleManager = ruleManager
        self.dockManager = dockManager
        _selectedTab = State(initialValue: selectedTab)
    }

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detailView
            }

            if isIndexingSettings {
                // Pre-render settings so search can index every tab, while
                // keeping the hidden hierarchy inert and non-interactive.
                ZStack {
                    GeneralSettingsView()
                        .environment(\.settingsTab, .general)
                    RulesView(ruleManager: ruleManager, spaceManager: spaceManager)
                        .environment(\.settingsTab, .rules)
                    DockSettingsView(dockManager: dockManager, spaceManager: spaceManager)
                        .environment(\.settingsTab, .dock)
                    PermissionsSettingsView(spaceManager: spaceManager)
                        .environment(\.settingsTab, .permissions)
                    AboutView()
                        .environment(\.settingsTab, .about)
                }
                .environmentObject(navigationState)
                .environment(\.isSettingsPreRendering, true)
                .frame(
                    minWidth: CGFloat(defaultSettingsWindowWidth),
                    minHeight: CGFloat(defaultSettingsWindowHeight)
                )
                .opacity(0.001)
                .allowsHitTesting(false)
            }
        }
        .environmentObject(navigationState)
        .navigationTitle("")
        .ignoresSafeArea(edges: .top)
        // The minimum preserves the original usable size; the infinity
        // bounds keep the settings window genuinely resizable.
        .frame(
            minWidth: CGFloat(defaultSettingsWindowWidth),
            maxWidth: .infinity,
            minHeight: CGFloat(defaultSettingsWindowHeight),
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .onChange(of: searchText) { value in
            navigationState.searchText = value
            if !value.isEmpty {
                let tabs = filteredTabs
                if let selectedTab, !tabs.contains(selectedTab) {
                    self.selectedTab = tabs.first
                } else if selectedTab == nil {
                    self.selectedTab = tabs.first
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isIndexingSettings = false
            }
        }
    }

    private var filteredTabs: [SettingsTab] {
        guard !searchText.isEmpty else { return SettingsTab.allCases }
        let query = searchText.lowercased()

        return SettingsTab.allCases.filter { tab in
            let matchesTab = tab.rawValue.lowercased().contains(query)
                || String(localized: tab.localizedName).lowercased().contains(query)
            let matchesSetting = navigationState.registeredItems.contains { item in
                item.tab == tab && (
                    item.title.lowercased().contains(query)
                        || item.localizedTitle.lowercased().contains(query)
                        || item.keywords.contains { $0.contains(query) }
                )
            }
            return matchesTab || matchesSetting
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .background(Color.clear)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.leading, -4)
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            Section {
                if filteredTabs.isEmpty {
                    Text("No results")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .padding(.top, 4)
                } else {
                    ForEach(filteredTabs) { tab in
                        VStack(alignment: .leading, spacing: 2) {
                            sidebarItem(for: tab)

                            if !searchText.isEmpty {
                                let matchingItems = navigationState.registeredItems.filter { item in
                                    item.tab == tab && (
                                        item.title.lowercased().contains(searchText.lowercased())
                                            || item.localizedTitle.lowercased().contains(searchText.lowercased())
                                            || item.keywords.contains { $0.contains(searchText.lowercased()) }
                                    )
                                }

                                ForEach(matchingItems) { item in
                                    Button {
                                        selectedTab = tab
                                        navigationState.scrollToItemID = item.title
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 12)
                                            Text(highlightedText(text: item.localizedTitle, query: searchText, color: nil))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .frame(height: 18)
                                }
                            }
                        }
                        .tag(tab)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Color.clear.frame(height: 45)
                    Text("Space")
                        .font(.custom("Syncopate-Bold", size: 21))
                        .foregroundStyle(.primary)
                    Text("Switcher")
                        .font(.custom("Syncopate-Bold", size: 21))
                        .foregroundStyle(.primary)
                        .padding(.bottom, 10)
                    searchField
                        .padding(.bottom, 12)
                }
            }
            .collapsible(false)
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth)
        .ignoresSafeArea(edges: .top)
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

    @ViewBuilder
    private var detailView: some View {
        let activeTab = selectedTab ?? filteredTabs.first ?? .general

        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                switch activeTab {
                case .general:
                    GeneralSettingsView()
                case .rules:
                    RulesView(ruleManager: ruleManager, spaceManager: spaceManager)
                case .dock:
                    DockSettingsView(dockManager: dockManager, spaceManager: spaceManager)
                case .permissions:
                    PermissionsSettingsView(spaceManager: spaceManager)
                case .about:
                    AboutView()
                }
            }
            .environmentObject(navigationState)
            .environment(\.settingsTab, activeTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, titleHeaderHeight)

            VStack(spacing: 0) {
                HStack {
                    Text(activeTab.localizedName)
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.leading, 20)
                    Spacer()
                }
                .frame(height: titleHeaderHeight)
                .background(.bar)
                Divider()
            }
        }
        .ignoresSafeArea(edges: .top)
    }

}

class SettingsHostingController: NSHostingController<SettingsView> {
    init(
        spaceManager: SpaceManager,
        ruleManager: RuleManager,
        dockManager: DockManager,
        startTab: SettingsTab? = nil
    ) {
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
        preferredContentSize = NSSize(
            width: defaultSettingsWindowWidth,
            height: defaultSettingsWindowHeight
        )
    }
}
