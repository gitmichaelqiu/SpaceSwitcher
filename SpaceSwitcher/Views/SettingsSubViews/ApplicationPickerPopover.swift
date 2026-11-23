import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RunningApplicationPickerPopover: View {
    let selectedBundleIdentifier: String?
    let includesAllAppsOption: Bool
    let isAllAppsSelected: Bool
    let onSelectAllApps: () -> Void
    let onSelectApplication: (String, String) -> Void
    let onChooseApplication: () -> Void

    @State private var runningApplications: [RunningApplicationChoice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Target Application")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    if includesAllAppsOption {
                        ApplicationPickerRow(action: onSelectAllApps) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.body)
                                    .frame(width: 20, height: 20)

                                Text("All apps")
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if isAllAppsSelected {
                                    selectionMark
                                }
                            }
                        }
                    }

                    if !runningApplications.isEmpty {
                        Divider()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                        Text("Running Applications")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    } else {
                        Text("No running applications")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }

                    ForEach(runningApplications) { application in
                        ApplicationPickerRow {
                            onSelectApplication(application.name, application.bundleIdentifier)
                        } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: application.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                Text(application.name)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if selectedBundleIdentifier == application.bundleIdentifier {
                                    selectionMark
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()
                .padding(.vertical, 6)

            ApplicationPickerRow(action: onChooseApplication) {
                Label("Choose from Applications…", systemImage: "plus.app")
            }
        }
        .padding(8)
        .frame(width: 300)
        .foregroundStyle(.primary)
        .onAppear(perform: loadRunningApplications)
    }

    private var selectionMark: some View {
        Image(systemName: "checkmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
    }

    private func loadRunningApplications() {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        runningApplications = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != ownBundleIdentifier
                    && !($0.bundleIdentifier ?? "").isEmpty
            }
            .compactMap { application in
                guard let bundleIdentifier = application.bundleIdentifier else { return nil }
                return RunningApplicationChoice(
                    bundleIdentifier: bundleIdentifier,
                    name: application.localizedName ?? bundleIdentifier,
                    icon: application.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct RunningApplicationChoice: Identifiable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage

    var id: String { bundleIdentifier }
}

struct ApplicationPickerRow<LabelContent: View>: View {
    private let action: () -> Void
    private let label: LabelContent
    @State private var isHovered = false

    init(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> LabelContent
    ) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderless)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isHovered
                        ? Color(nsColor: .selectedContentBackgroundColor)
                        : Color.clear
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovered = $0 }
    }
}
