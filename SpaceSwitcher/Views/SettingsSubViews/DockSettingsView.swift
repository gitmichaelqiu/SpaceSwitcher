import SwiftUI

struct DockSettingsView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var spaceManager: SpaceManager
    
    @State private var showingNameSheet = false
    @State private var newSetName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dock Sets").font(.headline)
                Spacer()
                Button("+ Capture Current Dock") {
                    newSetName = "Dock Set \(dockManager.config.dockSets.count + 1)"
                    showingNameSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            
            Divider()
            
            // Content
            HSplitView {
                // LEFT: Dock Sets List
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved Docks").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                        .padding(8)
                    
                    List {
                        ForEach(dockManager.config.dockSets) { set in
                            HStack {
                                Image(systemName: "dock.rectangle")
                                VStack(alignment: .leading) {
                                    Text(set.name).fontWeight(.medium)
                                    if dockManager.config.defaultDockSetID == set.id {
                                        Text("Default").font(.caption2).foregroundColor(.secondary)
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.1)).cornerRadius(4)
                                    }
                                }
                                Spacer()
                                Menu {
                                    Button("Set as Default") { dockManager.config.defaultDockSetID = set.id }
                                    Divider()
                                    Button("Delete") { deleteSet(set) }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 20)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                .frame(minWidth: 200, maxWidth: 300)
                
                // RIGHT: Space Assignments
                VStack(alignment: .leading, spacing: 0) {
                    Text("Space Assignments").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                        .padding(8)
                        .padding(.leading, 12)
                    
                    if dockManager.config.dockSets.isEmpty {
                        Text("Capture a Dock Set first to assign it to spaces.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(spaceManager.availableSpaces) { space in
                                HStack {
                                    Text("\(space.number). \(space.name)")
                                    Spacer()
                                    
                                    // Assignment Picker
                                    Picker("", selection: Binding(
                                        get: { dockManager.config.spaceAssignments[space.id] ?? dockManager.config.defaultDockSetID ?? UUID() },
                                        set: { newVal in
                                            dockManager.config.spaceAssignments[space.id] = newVal
                                        }
                                    )) {
                                        Text("Default").tag(dockManager.config.defaultDockSetID ?? UUID())
                                        Divider()
                                        ForEach(dockManager.config.dockSets) { set in
                                            Text(set.name).tag(set.id)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 140)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .frame(minWidth: 300)
            }
        }
        .sheet(isPresented: $showingNameSheet) {
            VStack(spacing: 20) {
                Text("Name your Dock Set").font(.headline)
                TextField("Name", text: $newSetName)
                    .frame(width: 250)
                    .onSubmit { saveNewSet() }
                HStack {
                    Button("Cancel") { showingNameSheet = false }
                    Button("Save") { saveNewSet() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }
    
    private func saveNewSet() {
        dockManager.captureCurrentDock(as: newSetName)
        showingNameSheet = false
    }
    
    private func deleteSet(_ set: DockSet) {
        dockManager.config.dockSets.removeAll { $0.id == set.id }
        // Clean up assignments
        if dockManager.config.defaultDockSetID == set.id {
            dockManager.config.defaultDockSetID = dockManager.config.dockSets.first?.id
        }
    }
}
