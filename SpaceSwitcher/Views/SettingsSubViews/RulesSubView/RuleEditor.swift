import SwiftUI
internal import UniformTypeIdentifiers

struct RuleEditor: View {
    @State private var workingRule: AppRule
    let availableSpaces: [SpaceInfo]
    let onSave: (AppRule) -> Void
    let onCancel: () -> Void
    @State private var runningApps: [(name: String, id: String, icon: NSImage)] = []
    
    init(rule: AppRule, availableSpaces: [SpaceInfo], onSave: @escaping (AppRule) -> Void, onCancel: @escaping () -> Void) {
        self._workingRule = State(wrappedValue: rule)
        self.availableSpaces = availableSpaces
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            appSelectorHeader.zIndex(1)
            Divider()
            
            // Native List for reliable reordering
            List {
                // --- GROUPS ---
                ForEach(Array(workingRule.groups.enumerated()), id: \.element.id) { index, group in
                    Section {
                        GroupHeaderRow(
                            groupIndex: index,
                            group: $workingRule.groups[index],
                            allGroups: workingRule.groups,
                            availableSpaces: availableSpaces,
                            onRemove: { withAnimation { _ = workingRule.groups.remove(at: index) } }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowSeparator(.hidden)
                        
                        ActionListRows(actions: $workingRule.groups[index].actions)
                        
                        AddActionButton {
                            // Add via menu
                        } menuContent: {
                            Button("Show") { workingRule.groups[index].actions.append(ActionItem(.show)) }
                            Button("Hide") { workingRule.groups[index].actions.append(ActionItem(.hide)) }
                            Button("Minimize") { workingRule.groups[index].actions.append(ActionItem(.minimize)) }
                            Button("Bring to Front") { workingRule.groups[index].actions.append(ActionItem(.bringToFront)) }
                            Divider()
                            Button("Simulate Hotkey...") { workingRule.groups[index].actions.append(ActionItem(.hotkey(keyCode: -1, modifiers: 0))) }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowSeparator(.hidden)
                        
                        // Spacer Row
                        Color.clear.frame(height: 12)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                
                // --- ADD NEW GROUP BUTTON ---
                Section {
                    Button {
                        withAnimation {
                            workingRule.groups.append(RuleGroup(targetSpaceIDs: [], actions: []))
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Space Group")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8) // Tightened padding
                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.hidden)
                }
                
                // --- ELSE / FALLBACK ---
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "asterisk.circle.fill").foregroundColor(.secondary)
                            Text("In All Other Spaces").font(.headline).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12) // Tightened
                        .background(Color(NSColor.controlBackgroundColor))
                        
                        Divider()
                        
                        if workingRule.elseActions.isEmpty {
                            Text("Do Nothing")
                                .italic().foregroundColor(.secondary)
                                .padding(12)
                        } else {
                            ForEach(Array(workingRule.elseActions.enumerated()), id: \.element.id) { i, item in
                                ActionRowContent(
                                    index: i,
                                    item: item,
                                    isRecording: false,
                                    onRecord: {},
                                    onDelete: { workingRule.elseActions.remove(at: i) }
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                if i < workingRule.elseActions.count - 1 { Divider().padding(.leading, 20) }
                            }
                        }
                        
                        Divider()
                        
                        AddActionButton { } menuContent: {
                            Button("Show") { workingRule.elseActions.append(ActionItem(.show)) }
                            Button("Hide") { workingRule.elseActions.append(ActionItem(.hide)) }
                        }
                        // Reuse component style but handle internal padding manually if needed
                        // (AddActionButton handles its own internal layout)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15)))
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            footerView
        }
        .frame(width: 800, height: 600)
        .onAppear { loadRunningApps() }
    }
    
    // ... (Header, Footer, Helpers same as previous) ...
    private var appSelectorHeader: some View {
        ZStack(alignment: .leading) {
            Color(NSColor.controlBackgroundColor).ignoresSafeArea()
            Menu {
                if !runningApps.isEmpty {
                    Section("Running Applications") {
                        ForEach(runningApps, id: \.id) { app in
                            Button { selectApp(name: app.name, id: app.id) } label: { HStack { Image(nsImage: app.icon); Text(app.name) } }
                        }
                    }
                }
                Divider()
                Button("Choose other app...") { pickOtherApp() }
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    if !workingRule.appBundleID.isEmpty, let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: workingRule.appBundleID)?.path {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "app.dashed").resizable().frame(width: 48, height: 48).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workingRule.appBundleID.isEmpty ? "Select Application" : workingRule.appName).font(.title2).fontWeight(.bold)
                        Text(workingRule.appBundleID.isEmpty ? "Click to choose" : workingRule.appBundleID).font(.caption).foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 72)
    }
    
    private var footerView: some View {
        HStack {
            Button("Cancel", action: onCancel).keyboardShortcut(.escape, modifiers: [])
            Spacer()
            Button("Save Rule") { onSave(workingRule) }
                .buttonStyle(.borderedProminent)
                .disabled(workingRule.appBundleID.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(16).background(Color(NSColor.controlBackgroundColor))
    }
    
    private func selectApp(name: String, id: String) { withAnimation { workingRule.appName = name; workingRule.appBundleID = id } }
    private func pickOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.begin { if $0 == .OK, let url = panel.url {
            let b = Bundle(url: url)
            let id = b?.bundleIdentifier ?? ""
            let name = (b?.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            if !id.isEmpty { DispatchQueue.main.async { self.selectApp(name: name, id: id) } }
        }}
    }
    func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        self.runningApps = apps.map { (name: $0.localizedName ?? "Unknown", id: $0.bundleIdentifier ?? "", icon: $0.icon ?? NSImage()) }.sorted { $0.name < $1.name }
    }
}

// MARK: - Row Components (Optimized Padding)

struct GroupHeaderRow: View {
    let groupIndex: Int
    @Binding var group: RuleGroup
    let allGroups: [RuleGroup]
    let availableSpaces: [SpaceInfo]
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workflow Group \(groupIndex + 1)")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8).padding(.horizontal, 12) // Tightened
            .background(Color.secondary.opacity(0.05))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Active in Spaces:")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    Spacer()
                }
                
                if availableSpaces.isEmpty {
                    Text("No spaces detected").font(.caption).foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading) {
                        ForEach(availableSpaces) { space in
                            let isUsedElsewhere = isSpaceUsedElsewhere(space.id)
                            let isSelectedHere = group.targetSpaceIDs.contains(space.id)
                            
                            Toggle(isOn: Binding(
                                get: { isSelectedHere },
                                set: { val in if val { group.targetSpaceIDs.insert(space.id) } else { group.targetSpaceIDs.remove(space.id) } }
                            )) {
                                Text("\(space.number). \(space.name)")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundColor(isUsedElsewhere && !isSelectedHere ? .secondary.opacity(0.5) : .primary)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(isUsedElsewhere && !isSelectedHere)
                        }
                    }
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 12) // Tightened
            
            Divider()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(CustomCornerShape(radius: 8, corners: [.topLeft, .topRight]))
        .overlay(
            CustomCornerShape(radius: 8, corners: [.topLeft, .topRight])
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func isSpaceUsedElsewhere(_ spaceID: String) -> Bool {
        for (idx, g) in allGroups.enumerated() {
            if idx != groupIndex && g.targetSpaceIDs.contains(spaceID) { return true }
        }
        return false
    }
}

struct ActionListRows: View {
    @Binding var actions: [ActionItem]
    @State private var recordingIndex: Int? = nil
    
    var body: some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
            VStack(spacing: 0) {
                ActionRowContent(
                    index: index,
                    item: item,
                    isRecording: recordingIndex == index,
                    onRecord: { startRecording(at: index) },
                    onDelete: { actions.remove(at: index) }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6) // Tightened
                
                if index < actions.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
        }
        .onMove { indices, newOffset in
            actions.move(fromOffsets: indices, toOffset: newOffset)
        }
    }
    
    private func startRecording(at index: Int) {
        recordingIndex = index
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.recordingIndex == index {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let code = Int(event.keyCode)
                self.actions[index].value = .hotkey(keyCode: code, modifiers: UInt(mods))
                self.recordingIndex = nil
                return nil
            }
            return event
        }
    }
}

struct AddActionButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let menuContent: Content
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Menu {
                    menuContent
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Action")
                    }
                    .font(.caption).fontWeight(.medium)
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.blue)
                .fixedSize()
                
                Spacer()
            }
            .padding(.vertical, 8).padding(.horizontal, 12) // Tightened
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(CustomCornerShape(radius: 8, corners: [.bottomLeft, .bottomRight]))
        .overlay(
            CustomCornerShape(radius: 8, corners: [.bottomLeft, .bottomRight])
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

struct ActionRowContent: View {
    let index: Int
    let item: ActionItem
    let isRecording: Bool
    let onRecord: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary.opacity(0.2))
                .font(.caption)
            
            Text("\(index + 1).")
                .font(.caption).monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)
            
            if case .hotkey(let code, let mods) = item.value {
                Button(action: onRecord) {
                    if isRecording {
                        Text("Recording...").foregroundColor(.red).fontWeight(.bold)
                    } else {
                        HStack {
                            Image(systemName: "keyboard")
                            Text(code == -1 ? "Click to Record" : ShortcutHelper.format(code: code, modifiers: mods))
                        }
                        .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(isRecording ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(4)
            } else {
                Text(item.value.localizedString).font(.subheadline)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct CustomCornerShape: Shape {
    var radius: CGFloat
    var corners: RectCorner
    
    struct RectCorner: OptionSet {
        let rawValue: Int
        static let topLeft = RectCorner(rawValue: 1 << 0)
        static let topRight = RectCorner(rawValue: 1 << 1)
        static let bottomLeft = RectCorner(rawValue: 1 << 2)
        static let bottomRight = RectCorner(rawValue: 1 << 3)
        static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p1 = CGPoint(x: rect.minX, y: corners.contains(.topLeft) ? rect.minY + radius : rect.minY)
        let p2 = CGPoint(x: corners.contains(.topLeft) ? rect.minX + radius : rect.minX, y: rect.minY)
        let p3 = CGPoint(x: corners.contains(.topRight) ? rect.maxX - radius : rect.maxX, y: rect.minY)
        let p4 = CGPoint(x: rect.maxX, y: corners.contains(.topRight) ? rect.minY + radius : rect.minY)
        let p5 = CGPoint(x: rect.maxX, y: corners.contains(.bottomRight) ? rect.maxY - radius : rect.maxY)
        let p6 = CGPoint(x: corners.contains(.bottomRight) ? rect.maxX - radius : rect.maxX, y: rect.maxY)
        let p7 = CGPoint(x: corners.contains(.bottomLeft) ? rect.minX + radius : rect.minX, y: rect.maxY)
        let p8 = CGPoint(x: rect.minX, y: corners.contains(.bottomLeft) ? rect.maxY - radius : rect.maxY)
        
        path.move(to: p1)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: p2, radius: radius)
        path.addLine(to: p3)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: p4, radius: radius)
        path.addLine(to: p5)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: p6, radius: radius)
        path.addLine(to: p7)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: p8, radius: radius)
        path.closeSubpath()
        return path
    }
}
