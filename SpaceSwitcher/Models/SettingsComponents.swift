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
                    .padding(SettingsComponentMetrics.containerPadding)
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
        VStack(alignment: .leading, spacing: SettingsComponentMetrics.rowContentSpacing) {
            HStack {
                HStack(spacing: SettingsComponentMetrics.labelSpacing) {
                    Text(highlightedText(text: String(localized: title), query: navigationState.searchText))
                        .layoutPriority(1)

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
        }
        .padding(.vertical, SettingsComponentMetrics.rowVerticalPadding)
        .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding)
        .frame(minHeight: SettingsComponentMetrics.listRowHeight)
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
        let names = missingRequirements
            .map { NSLocalizedString($0.name, comment: "") }
            .joined(separator: ", ")
        let format = NSLocalizedString("Requires %@.", comment: "")
        return LocalizedStringKey(String(format: format, names))
    }

    var body: some View {
        if !missingRequirements.isEmpty {
            WarningInfoButton(text: warningText)
        }
    }
}

enum SettingsSectionStyle {
    static var dragPreviewBackgroundColor: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    static var backgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.20, alpha: 1.0)
                : NSColor(calibratedWhite: 1.00, alpha: 1.0)
        }
        return Color(nsColor: nsColor)
    }
}

struct ReorderableSettingsRowContext {
    let index: Int
    let isLast: Bool
}

struct ReorderableSettingsList<Item: Identifiable, RowContent: View, DragPreview: View>: View where Item.ID == String {
    let items: [Item]
    let rowContent: (Item, ReorderableSettingsRowContext) -> RowContent
    let dragPreview: (Item) -> DragPreview
    let moveBefore: (String, String) -> Bool
    let moveToEnd: (String) -> Void

    @State private var targetedItemID: String?

    init(
        items: [Item],
        @ViewBuilder rowContent: @escaping (Item, ReorderableSettingsRowContext) -> RowContent,
        @ViewBuilder dragPreview: @escaping (Item) -> DragPreview,
        moveBefore: @escaping (String, String) -> Bool,
        moveToEnd: @escaping (String) -> Void
    ) {
        self.items = items
        self.rowContent = rowContent
        self.dragPreview = dragPreview
        self.moveBefore = moveBefore
        self.moveToEnd = moveToEnd
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 27.0, *) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    decoratedRow(
                        for: item,
                        context: ReorderableSettingsRowContext(index: index, isLast: index == items.count - 1)
                    )
                }
                .reorderable()
            }
            .reorderContainer(for: Item.self) { difference in
                applyNativeReorder(difference)
            }
        } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                decoratedRow(
                    for: item,
                    context: ReorderableSettingsRowContext(index: index, isLast: index == items.count - 1)
                )
                .draggable(item.id) {
                    dragPreview(item)
                        .background(SettingsSectionStyle.dragPreviewBackgroundColor)
                }
                .dropDestination(for: String.self) { sourceIDs, _ in
                    guard let sourceID = sourceIDs.first,
                          sourceID != item.id,
                          items.contains(where: { $0.id == sourceID }) else { return false }
                    return moveBefore(sourceID, item.id)
                } isTargeted: { isTargeted in
                    if isTargeted {
                        targetedItemID = item.id
                    } else if targetedItemID == item.id {
                        targetedItemID = nil
                    }
                }
            }
        }
    }

    private func decoratedRow(for item: Item, context: ReorderableSettingsRowContext) -> some View {
        rowContent(item, context)
            .contentShape(Rectangle())
            .contentShape(.dragPreview, Rectangle())
            .overlay(
                targetedItemID == item.id
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @available(macOS 27.0, *)
    private func applyNativeReorder(
        _ difference: ReorderDifference<String, ReorderableSingleCollectionIdentifier>
    ) {
        guard let sourceID = difference.sources.first else { return }

        switch difference.destination.position {
        case .before(let targetID):
            _ = moveBefore(sourceID, targetID)
        case .end:
            moveToEnd(sourceID)
        }
    }
}

struct BundleIdentifierText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

func resolvedApplicationName(bundleIdentifier: String, storedName: String = "") -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
       let bundle = Bundle(url: url) {
        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
        if let displayName = info?["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }
        if let name = info?["CFBundleName"] as? String, !name.isEmpty {
            return name
        }
    }

    if !storedName.isEmpty {
        return storedName
    }

    return bundleIdentifier
}

func spaceDisplayName(_ space: SpaceInfo) -> String {
    guard space.name.isEmpty else { return space.name }
    return String.localizedStringWithFormat(
        NSLocalizedString("Space %lld", comment: "Fallback name for an unnamed desktop space"),
        Int64(space.number)
    )
}

enum SettingsComponentMetrics {
    static let containerPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let sectionContentSpacing: CGFloat = 8
    static let rowContentSpacing: CGFloat = 8
    static let labelSpacing: CGFloat = 4
    static let sectionTitleLeadingPadding: CGFloat = 4
    static let rowVerticalPadding: CGFloat = 6
    static let rowHorizontalPadding: CGFloat = 10
    static let listRowHorizontalPadding: CGFloat = 12
    static let listRowHeight: CGFloat = 34
    static let untitledSectionTopAdjustment: CGFloat = -10
    static let iconButtonSize: CGFloat = 32
    static let iconGlyphSize: CGFloat = 15
}

struct SettingsIconControlLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: SettingsComponentMetrics.iconGlyphSize, weight: .medium))
            .frame(width: 20, height: 20)
    }
}

struct SettingsDestructiveIconLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .bold))
            .frame(width: 16, height: 16)
    }
}

extension View {
    func settingsIconControlFrame() -> some View {
        frame(width: SettingsComponentMetrics.iconButtonSize,
              height: SettingsComponentMetrics.iconButtonSize)
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
        let localizedTitle = LocalizedStringKey(title)
        self.title = localizedTitle
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
        let localizedTitle = LocalizedStringKey(title)
        self.title = localizedTitle
        self.helperText = helperText
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsComponentMetrics.sectionContentSpacing) {
            if let title {
                SettingsSectionTitle(title, helperText: helperText)
                .overlay(alignment: .trailing) {
                    accessory
                }
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
        .padding(
            .top,
            title == nil ? SettingsComponentMetrics.untitledSectionTopAdjustment : 0
        )
    }
}

struct SettingsSectionTitle: View {
    let title: LocalizedStringKey
    let helperText: LocalizedStringKey?

    init(_ title: LocalizedStringKey, helperText: LocalizedStringKey? = nil) {
        self.title = title
        self.helperText = helperText
    }

    var body: some View {
        HStack(spacing: SettingsComponentMetrics.labelSpacing) {
            Text(title)
                .font(.headline)

            if let helperText {
                HelperInfoButton(text: helperText)
            }

            Spacer()
        }
        .padding(.leading, SettingsComponentMetrics.sectionTitleLeadingPadding)
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

extension EnvironmentValues {
    @Entry var isSettingsPreRendering = false
    @Entry var settingsTab: SettingsTab = .general
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
        .padding(.horizontal, SettingsComponentMetrics.rowHorizontalPadding)
    }
}
