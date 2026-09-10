import SwiftUI
import Combine

struct SearchableSettingItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let localizedTitle: String
    let tab: SettingsTab
    let keywords: [String]

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(tab)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.tab == rhs.tab
    }
}

final class SettingsNavigationState: ObservableObject {
    @Published var scrollToItemID: String?
    @Published var searchText = ""
    @Published var registeredItems: [SearchableSettingItem] = []

    private var registeredTitleCounts: [String: Int] = [:]

    private func keywords(from string: String) -> [String] {
        string.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    func register(title: String, tab: SettingsTab, keywords: [String] = []) {
        let key = "\(title)-\(tab.rawValue)"
        let count = registeredTitleCounts[key] ?? 0
        registeredTitleCounts[key] = count + 1
        guard count == 0 else { return }

        let localizedTitle = NSLocalizedString(title, comment: "")
        let allKeywords = Set(keywords.map { $0.lowercased() } + self.keywords(from: title) + self.keywords(from: localizedTitle))
        let item = SearchableSettingItem(
            title: title,
            localizedTitle: localizedTitle,
            tab: tab,
            keywords: Array(allKeywords)
        )

        DispatchQueue.main.async { [weak self] in
            self?.registeredItems.append(item)
        }
    }

    func unregister(title: String, tab: SettingsTab) {
        let key = "\(title)-\(tab.rawValue)"
        let count = registeredTitleCounts[key] ?? 0

        if count <= 1 {
            registeredTitleCounts[key] = nil
            DispatchQueue.main.async { [weak self] in
                self?.registeredItems.removeAll { $0.title == title && $0.tab == tab }
            }
        } else {
            registeredTitleCounts[key] = count - 1
        }
    }
}

func highlightedText(text: String, query: String, color: Color? = .blue) -> AttributedString {
    var attributed = AttributedString(text)
    guard !query.isEmpty else { return attributed }

    let lowerQuery = query.lowercased()
    var searchStart = attributed.startIndex

    while searchStart < attributed.endIndex {
        let remaining = String(attributed[searchStart...].characters)
        guard let range = remaining.lowercased().range(of: lowerQuery) else { break }

        let offset = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
        let length = remaining.distance(from: range.lowerBound, to: range.upperBound)
        let start = attributed.index(searchStart, offsetByCharacters: offset)
        let end = attributed.index(start, offsetByCharacters: length)
        let match = start..<end

        if let color {
            attributed[match].foregroundColor = color
        }
        attributed[match].inlinePresentationIntent = .stronglyEmphasized
        searchStart = end
    }

    return attributed
}

struct SettingsContainer<Content: View>: View {
    let tab: SettingsTab
    let content: () -> Content

    @EnvironmentObject private var navigationState: SettingsNavigationState

    init(_ tab: SettingsTab, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.content = content
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                content()
                    .padding(16)
            }
            .environment(\.settingsTab, tab)
            .onChange(of: navigationState.scrollToItemID) { itemID in
                guard let itemID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation {
                        proxy.scrollTo(itemID, anchor: .center)
                    }
                    navigationState.scrollToItemID = nil
                }
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: LocalizedStringResource
    let content: Content
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?
    let requirements: [SettingsRequirement]

    @Environment(\.settingsTab) private var currentTab
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @EnvironmentObject private var navigationState: SettingsNavigationState

    init(
        _ title: LocalizedStringResource,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        requirements: [SettingsRequirement] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self.requirements = requirements
        self.content = content()
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(highlightedText(text: String(localized: title), query: navigationState.searchText))
                    .frame(alignment: .leading)

                if let helperText {
                    HelperInfoButton(text: helperText)
                }

                if let warningText {
                    WarningInfoButton(text: warningText)
                }

                SettingsRequirementWarning(requirements: requirements)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
                .frame(alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .id(title.key)
        .onAppear {
            navigationState.register(title: title.key, tab: currentTab)
        }
        .onDisappear {
            if !isPreRendering {
                navigationState.unregister(title: title.key, tab: currentTab)
            }
        }
    }
}

struct SettingsRequirement: Identifiable {
    let name: String
    let isSatisfied: Bool

    var id: String { name }

    static func accessibility(isGranted: Bool) -> Self {
        Self(name: "Accessibility permission", isSatisfied: isGranted)
    }

    // Shares the Accessibility label with the primary check so the warning
    // popover does not list the same permission twice.
    static func accessibilityEventPosting(isGranted: Bool) -> Self {
        Self(name: "Accessibility permission", isSatisfied: isGranted)
    }

    static func inputEvents(isGranted: Bool) -> Self {
        accessibilityEventPosting(isGranted: isGranted)
    }

    static func screenRecording(isGranted: Bool) -> Self {
        Self(name: "Screen Recording permission", isSatisfied: isGranted)
    }

    static func spaceAPI(isAvailable: Bool) -> Self {
        Self(name: "SpaceAPI", isSatisfied: isAvailable)
    }
}

struct SettingsRequirementWarning: View {
    let requirements: [SettingsRequirement]

    private var missingRequirements: [SettingsRequirement] {
        var seenNames = Set<String>()
        return requirements.filter { requirement in
            !requirement.isSatisfied && seenNames.insert(requirement.name).inserted
        }
    }

    private var warningText: LocalizedStringKey {
        LocalizedStringKey("Requires \(missingRequirements.map(\.name).joined(separator: ", ")).")
    }

    var body: some View {
        if !missingRequirements.isEmpty {
            WarningInfoButton(text: warningText)
        }
    }
}

enum SettingsSectionStyle {
    static var backgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.20, alpha: 1.0)
                : NSColor(calibratedWhite: 1.00, alpha: 1.0)
        }
        return Color(nsColor: nsColor)
    }
}

struct SettingsSection<Content: View, Accessory: View>: View {
    let title: LocalizedStringKey?
    let helperText: LocalizedStringKey?
    let accessory: Accessory
    let content: Content

    init(
        _ title: LocalizedStringKey? = nil,
        helperText: LocalizedStringKey? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.accessory = accessory()
        self.content = content()
    }

    init(
        _ title: LocalizedStringKey? = nil,
        helperText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.helperText = helperText
        self.accessory = EmptyView()
        self.content = content()
    }

    init(
        _ title: String,
        helperText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = LocalizedStringKey(title)
        self.helperText = helperText
        self.accessory = EmptyView()
        self.content = content()
    }

    init(
        _ title: String,
        helperText: LocalizedStringKey? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = LocalizedStringKey(title)
        self.helperText = helperText
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.headline)

                    if let helperText {
                        HelperInfoButton(text: helperText)
                    }

                    Spacer()
                    accessory
                }
                .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsSectionStyle.backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                    )
            )
        }
        .padding(.top, title == nil ? -10 : 0)
    }
}

struct HelperInfoButton: View {
    let text: LocalizedStringKey
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(15)
                .frame(minWidth: 200, maxWidth: 300)
        }
    }
}

struct WarningInfoButton: View {
    let text: LocalizedStringKey
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(15)
                .frame(minWidth: 200, maxWidth: 300)
        }
    }
}

struct IsSettingsPreRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

struct SettingsTabKey: EnvironmentKey {
    static let defaultValue: SettingsTab = .general
}

extension EnvironmentValues {
    var isSettingsPreRendering: Bool {
        get { self[IsSettingsPreRenderingKey.self] }
        set { self[IsSettingsPreRenderingKey.self] = newValue }
    }

    var settingsTab: SettingsTab {
        get { self[SettingsTabKey.self] }
        set { self[SettingsTabKey.self] = newValue }
    }
}

struct SliderSettingsRow<V>: View where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
    let title: LocalizedStringKey
    @Binding var value: V
    let range: ClosedRange<V>
    let defaultValue: V
    let step: V?
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?
    let valueString: (V) -> String

    init(
        _ title: LocalizedStringKey,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        value: Binding<V>,
        range: ClosedRange<V>,
        defaultValue: V,
        step: V? = nil,
        valueString: @escaping (V) -> String = { String(format: "%.2f", Double($0)) }
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
        self.valueString = valueString
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(title)
                    if let helperText {
                        HelperInfoButton(text: helperText)
                    }
                    if let warningText {
                        WarningInfoButton(text: warningText)
                    }
                }

                Spacer()

                Button("↺") {
                    withAnimation {
                        value = defaultValue
                    }
                }
                .help("Reset to default")
                .disabled(value == defaultValue)
            }

            HStack {
                if let step {
                    Slider(value: $value, in: range, step: V.Stride(step))
                } else {
                    Slider(value: $value, in: range)
                }

                Text(valueString(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }
}
