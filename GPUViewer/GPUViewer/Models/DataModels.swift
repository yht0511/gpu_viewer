import Foundation

struct ServerConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String // Friendly name (e.g., "Node-01")
    var host: String
    var port: Int = 22
    var username: String
    var password: String? // Optional password
    var identityFile: String? // Path to private key (e.g., "~/.ssh/id_rsa")
    var proxyJump: String? // Optional ProxyJump (e.g., "jumpuser@jumphost")
    var proxyCommand: String? // Optional ProxyCommand
    
    // For Codable compatibility with JSON import
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, password, identityFile, proxyJump, proxyCommand
    }
}

struct GPUData: Identifiable, Hashable {
    var id: Int // GPU Index
    var uuid: String // GPU UUID
    var name: String
    var utilGPU: Double // 0-100
    var utilMemory: Double // 0-100
    var memoryUsed: Double // MB
    var memoryTotal: Double // MB
    var temperature: Double // Celsius
    var powerDraw: Double // Watts
    var powerLimit: Double // Watts
    
    var memoryUtilPercent: Double {
        return memoryTotal > 0 ? (memoryUsed / memoryTotal) * 100.0 : 0.0
    }
}

struct NodeStatus: Identifiable {
    var id: UUID
    var config: ServerConfig
    var isConnected: Bool = false
    var lastUpdated: Date?
    var error: String?
    
    // Metrics
    var cpuUsage: Double = 0.0 // 0-100
    var ramUsed: Double = 0.0 // GB
    var ramTotal: Double = 0.0 // GB
    var diskUsage: Double = 0.0 // 0-100
    
    var gpus: [GPUData] = []
    
    // Process info (simplified for now)
    var topProcesses: [GPUProcessInfo] = []
    
    // History for Charts
    var history: [HistoryPoint] = []
}

struct HistoryPoint: Identifiable {
    var id: Date
    var cpuUsage: Double
    var ramUsage: Double
    var gpuUtilizations: [Int: Double] // GPU ID -> Util
}

struct GPUProcessInfo: Identifiable, Hashable {
    var id: String { pid }
    var pid: String
    var user: String
    var command: String
    var gpuIndex: Int? // If associated with a GPU
    var memoryUsed: Double // MB
}
