import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var sortOrder: [UUID] = []
    
    var sortedServers: [ServerConfig] {
        let serverMap = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
        // Start with ids in sortOrder that exist in serverMap
        var result = sortOrder.compactMap { serverMap[$0] }
        
        // Find any servers not in sortOrder and append them
        let sortedIds = Set(result.map { $0.id })
        let remaining = servers.filter { !sortedIds.contains($0.id) }
        
        return result + remaining
    }
    
    @Published var nodeStatuses: [UUID: NodeStatus] = [:]
    @Published var selectedNodeId: UUID? = nil
    
    // For heatmap settings
    @Published var heatmapMetric: HeatmapMetric = .gpuUtil
    
    enum HeatmapMetric: String, CaseIterable, Identifiable {
        case gpuUtil = "GPU Util"
        case memoryUtil = "Memory Util"
        case temperature = "Temperature"
        case power = "Power"
        
        var id: String { self.rawValue }
    }
    
    private var timer: Timer?
    
    init() {
        // Load config from UserDefaults or JSON
        loadConfig()
        startPolling()
    }
    
    func addServer(_ config: ServerConfig) {
        servers.append(config)
        // Append to sortOrder to keep it at the end
        if !sortOrder.contains(config.id) {
            sortOrder.append(config.id)
        }
        saveConfig()
    }
    
    func removeServer(_ config: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == config.id }) {
            servers.remove(at: index)
        }
        if let sortIndex = sortOrder.firstIndex(of: config.id) {
            sortOrder.remove(at: sortIndex)
        }
        saveConfig()
    }
    
    func moveServer(from source: IndexSet, to destination: Int) {
        // Ensure sortOrder is up to date with all servers
        var currentOrder = sortedServers.map { $0.id }
        currentOrder.move(fromOffsets: source, toOffset: destination)
        sortOrder = currentOrder
        saveConfig()
    }
    
    func updateServer(_ config: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == config.id }) {
            servers[index] = config
            saveConfig()
            // Invalidate current connection/cache if needed?
            // For now, next polling cycle will just use new config
        }
    }
    
    func loadConfig() {
        // Load servers
        if let data = UserDefaults.standard.data(forKey: "ServerConfig"),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            self.servers = decoded
        }
        
        // Load sort order
        if let data = UserDefaults.standard.data(forKey: "ServerSortOrder"),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            self.sortOrder = decoded
        }
    }
    
    func saveConfig() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: "ServerConfig")
        }
        if let encoded = try? JSONEncoder().encode(sortOrder) {
            UserDefaults.standard.set(encoded, forKey: "ServerSortOrder")
        }
    }
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchAll()
            }
        }
    }
    
    func fetchAll() async {
        await withTaskGroup(of: (UUID, NodeStatus?).self) { group in
            for server in servers {
                group.addTask {
                    do {
                        let output = try await SSHClient.shared.fetchMetrics(for: server)
                        let status = DataParser.parse(output: output, for: server)
                        return (server.id, status)
                    } catch {
                        print("Error fetching \(server.name): \(error)")
                        var errorStatus = NodeStatus(id: server.id, config: server)
                        errorStatus.error = error.localizedDescription
                        return (server.id, errorStatus)
                    }
                }
            }
            
            for await (id, newStatus) in group {
                if var newStatus = newStatus {
                    // Merge history
                    if let oldStatus = self.nodeStatuses[id] {
                        newStatus.history = oldStatus.history
                    }
                    
                    // Add new point
                    var gpuUtils: [Int: Double] = [:]
                    for gpu in newStatus.gpus {
                        gpuUtils[gpu.id] = gpu.utilGPU
                    }
                    
                    let point = HistoryPoint(
                        id: Date(),
                        cpuUsage: newStatus.cpuUsage,
                        ramUsage: newStatus.ramTotal > 0 ? (newStatus.ramUsed / newStatus.ramTotal) * 100 : 0,
                        gpuUtilizations: gpuUtils
                    )
                    
                    newStatus.history.append(point)
                    
                    // Keep last 60 points (assuming 3s interval = 3 mins)
                    if newStatus.history.count > 60 {
                        newStatus.history.removeFirst(newStatus.history.count - 60)
                    }
                    
                    self.nodeStatuses[id] = newStatus
                }
            }
        }
    }
}
