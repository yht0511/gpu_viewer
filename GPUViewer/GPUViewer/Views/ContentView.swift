import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var appState = AppState()
    // Remove local navigationSelection and use appState.selectedNodeId
    // But List selection binding needs to be optional UUID to match NavigationLink values
    // appState.selectedNodeId is optional UUID, so we can use it directly.
    
    @State private var showAddServerSheet = false
    @State private var showEditServerSheet = false
    @State private var showSSHImportSheet = false
    @State private var showSettingsSheet = false
    @State private var editingServerConfig = ServerConfig(name: "", host: "", username: "")
    @State private var newServerConfig = ServerConfig(name: "", host: "", username: "")
    
    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedNodeId) {
                Section(header: Text("Cluster")) {
                    NavigationLink(value: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) {
                        Label("Overview", systemImage: "square.grid.4x3.fill")
                    }
                }
                
                Section(header: Text("Nodes")) {
                    ForEach(appState.sortedServers) { server in
                        NavigationLink(value: server.id) {
                            HStack {
                                Circle()
                                    .fill(statusColor(for: server.id))
                                    .frame(width: 8, height: 8)
                                Text(server.name)
                            }
                        }
                        .contextMenu {
                            Button("Edit") {
                                editingServerConfig = server
                                showEditServerSheet = true
                            }
                            Button("Delete", role: .destructive) {
                                deleteServer(server)
                            }
                        }
                    }
                    .onMove(perform: appState.moveServer)
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("GPU Viewer")
            .toolbar {
                ToolbarItem {
                    Button(action: { showSettingsSheet = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
                
                ToolbarItem {
                    Menu {
                        Button(action: { showAddServerSheet = true }) {
                            Label("Add Manually", systemImage: "plus")
                        }
                        Button(action: importJSON) {
                            Label("Import JSON", systemImage: "square.and.arrow.down")
                        }
                        Button(action: { showSSHImportSheet = true }) {
                            Label("Import SSH Config", systemImage: "terminal")
                        }
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let sel = appState.selectedNodeId {
                if sel.uuidString == "00000000-0000-0000-0000-000000000000" {
                    ClusterView(appState: appState)
                } else {
                    if let index = appState.servers.firstIndex(where: { $0.id == sel }) {
                        // Bind directly to the array element for editing if needed
                        NodeDetailView(server: appState.servers[index], appState: appState)
                    }
                }
            } else {
                ClusterView(appState: appState)
            }
        }
        .sheet(isPresented: $showAddServerSheet) {
            AddServerSheet(config: $newServerConfig, isPresented: $showAddServerSheet) { config in
                appState.addServer(config)
                // Reset for next time
                newServerConfig = ServerConfig(name: "", host: "", username: "")
            }
        }
        .sheet(isPresented: $showEditServerSheet) {
            AddServerSheet(config: $editingServerConfig, isPresented: $showEditServerSheet) { config in
                appState.updateServer(config)
            }
        }
        .sheet(isPresented: $showSSHImportSheet) {
            SSHImportSheet(isPresented: $showSSHImportSheet) { configs in
                for config in configs {
                    appState.addServer(config)
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(appState: appState, isPresented: $showSettingsSheet)
        }
    }
    
    func deleteServer(_ server: ServerConfig) {
        appState.removeServer(server)
    }
    
    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            if let url = panel.url,
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
                DispatchQueue.main.async {
                    appState.servers.append(contentsOf: decoded)
                    appState.saveConfig()
                }
            }
        }
    }
    
    func statusColor(for id: UUID) -> Color {
        guard let status = appState.nodeStatuses[id] else { return .gray }
        if status.error != nil { return .red }
        return .green
    }
}
