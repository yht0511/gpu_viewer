import Foundation

class DataParser {
    static func parse(output: String, for config: ServerConfig) -> NodeStatus {
        var status = NodeStatus(id: config.id, config: config, isConnected: true, lastUpdated: Date())
        
        let sections = output.components(separatedBy: "___SECTION_")
        
        // 1. GPU Section (Look for GPU___ or start of file if older version)
        var gpuMap: [String: Int] = [:] // UUID -> Index
        
        if let gpuSection = sections.first(where: { $0.hasPrefix("GPU___") }) {
             // Remove "GPU___\n"
             let clean = gpuSection.dropFirst(7) // "GPU___\n" length approx
             status.gpus = parseGPUCSV(String(clean))
             for gpu in status.gpus {
                 gpuMap[gpu.uuid] = gpu.id
             }
        } else if let first = sections.first, !first.contains("CPU___") {
             // Fallback for older command version where GPU was first without header
             status.gpus = parseGPUCSV(first)
             for gpu in status.gpus {
                 gpuMap[gpu.uuid] = gpu.id
             }
        }
        
        // 2. CPU Section
        if let cpuSection = sections.first(where: { $0.hasPrefix("CPU___") }) {
            status.cpuUsage = parseCPU(cpuSection)
        }
        
        // 3. Mem Section
        if let memSection = sections.first(where: { $0.hasPrefix("MEM___") }) {
            let (used, total) = parseMem(memSection)
            status.ramUsed = used
            status.ramTotal = total
        }
        
        // 4. Process Section
        if let procSection = sections.first(where: { $0.hasPrefix("PROCESS___") }) {
            status.topProcesses = parseProcesses(procSection, gpuMap: gpuMap)
        }
        
        return status
    }
    
    private static func parseProcesses(_ raw: String, gpuMap: [String: Int]) -> [GPUProcessInfo] {
        var procs: [GPUProcessInfo] = []
        let lines = raw.split(separator: "\n")
        
        for line in lines {
            if line.contains("PROCESS___") { continue }
            // Expected format: gpu_uuid,pid,used_mem,user,comm
            let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            if parts.count >= 5,
               let mem = Double(parts[2]) {
                
                let uuid = String(parts[0])
                let gpuIdx = gpuMap[uuid]
                
                let proc = GPUProcessInfo(
                    pid: String(parts[1]),
                    user: String(parts[3]),
                    command: String(parts[4]),
                    gpuIndex: gpuIdx, // Can be nil if "NONE" or not found
                    memoryUsed: mem
                )
                procs.append(proc)
            }
        }
        return procs
    }
    
    private static func parseGPUCSV(_ csv: String) -> [GPUData] {
        var gpus: [GPUData] = []
        let lines = csv.split(separator: "\n")
        
        for line in lines {
            let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            // New format: index,uuid,name,util.gpu,util.mem,mem.used,mem.total,temp,power,power.limit (10 parts)
            if parts.count >= 10 {
                if let idx = Int(parts[0]),
                   let utilG = Double(parts[3]),
                   let utilM = Double(parts[4]),
                   let memU = Double(parts[5]),
                   let memT = Double(parts[6]),
                   let temp = Double(parts[7]),
                   let pwr = Double(parts[8]),
                   let limit = Double(parts[9]) {
                    
                    let gpu = GPUData(
                        id: idx,
                        uuid: String(parts[1]),
                        name: String(parts[2]),
                        utilGPU: utilG,
                        utilMemory: utilM,
                        memoryUsed: memU,
                        memoryTotal: memT,
                        temperature: temp,
                        powerDraw: pwr,
                        powerLimit: limit
                    )
                    gpus.append(gpu)
                }
            }
            // Old format fallback: index,name,util.gpu,util.mem,mem.used,mem.total,temp,power,power.limit (9 parts)
            else if parts.count >= 9 {
                if let idx = Int(parts[0]),
                   let utilG = Double(parts[2]),
                   let utilM = Double(parts[3]),
                   let memU = Double(parts[4]),
                   let memT = Double(parts[5]),
                   let temp = Double(parts[6]),
                   let pwr = Double(parts[7]),
                   let limit = Double(parts[8]) {
                    
                    let gpu = GPUData(
                        id: idx,
                        uuid: "UNKNOWN-\(idx)", // Generate dummy UUID
                        name: String(parts[1]),
                        utilGPU: utilG,
                        utilMemory: utilM,
                        memoryUsed: memU,
                        memoryTotal: memT,
                        temperature: temp,
                        powerDraw: pwr,
                        powerLimit: limit
                    )
                    gpus.append(gpu)
                }
            }
        }
        return gpus
    }
    
    private static func parseCPU(_ raw: String) -> Double {
        // Try to find "id" (idle) percentage and subtract from 100
        // Example: %Cpu(s):  0.3 us,  0.7 sy,  0.0 ni, 99.0 id, ...
        let parts = raw.split(separator: ",")
        for part in parts {
            if part.contains("id") {
                let scanner = Scanner(string: String(part))
                // Scan until we find a double
                if let val = scanner.scanDouble() {
                    return max(0, 100.0 - val)
                }
            }
        }
        return 0.0
    }
    
    private static func parseMem(_ raw: String) -> (Double, Double) {
        // Example: Mem: 32000 16000 ... (total, used)
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true)
        // parts[0] is "Mem:" or similar prefix if grep included it
        // Depending on output of `free -m | grep Mem`
        // Output: Mem:          12345        2345
        
        var numbers: [Double] = []
        for part in parts {
            if let val = Double(part) {
                numbers.append(val)
            }
        }
        
        if numbers.count >= 2 {
            let total = numbers[0]
            let used = numbers[1]
            return (used / 1024.0, total / 1024.0) // Convert MB to GB
        }
        
        return (0.0, 0.0)
    }
}
