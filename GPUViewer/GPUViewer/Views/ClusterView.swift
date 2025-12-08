import SwiftUI
import AppKit

struct ClusterView: View {
    @ObservedObject var appState: AppState
    
    let columns = [GridItem(.adaptive(minimum: 300, maximum: 400))]
    
    var body: some View {
        VStack {
            Picker("Metric", selection: $appState.heatmapMetric) {
                ForEach(AppState.HeatmapMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(appState.sortedServers) { server in
                        NodeCard(server: server, status: appState.nodeStatuses[server.id], metric: appState.heatmapMetric)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Cluster Overview")
    }
}

struct NodeCard: View {
    let server: ServerConfig
    let status: NodeStatus?
    let metric: AppState.HeatmapMetric
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(server.name)
                    .font(.headline)
                Spacer()
                if let err = status?.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .help(err)
                }
            }
            .padding(.bottom, 5)
            
            if let status = status, status.gpus.count > 0 {
                HStack(spacing: 2) {
                    ForEach(status.gpus) { gpu in
                        Rectangle()
                            .fill(colorFor(gpu: gpu))
                            .frame(height: 40)
                            .overlay(
                                Text("\(Int(valueFor(gpu: gpu)))")
                                    .font(.caption2)
                                    .foregroundColor(.white) // Needs contrast check
                            )
                            .help("\(gpu.name)\nUtil: \(Int(gpu.utilGPU))%\nMem: \(Int(gpu.memoryUtilPercent))%\nTemp: \(Int(gpu.temperature))°C\nPower: \(Int(gpu.powerDraw))W / \(Int(gpu.powerLimit))W")
                    }
                }
            } else {
                Text("No Data")
                    .foregroundColor(.secondary)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
            }
            
            // Mini System Stats
            if let status = status {
                HStack {
                    Label("\(Int(status.cpuUsage))%", systemImage: "cpu")
                    Spacer()
                    Label("\(Int(status.ramUsed))/\(Int(status.ramTotal))G", systemImage: "memorychip")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 2)
    }
    
    func valueFor(gpu: GPUData) -> Double {
        switch metric {
        case .gpuUtil: return gpu.utilGPU
        case .memoryUtil: return gpu.memoryUtilPercent
        case .temperature: return gpu.temperature
        case .power: return gpu.powerDraw
        }
    }
    
    func colorFor(gpu: GPUData) -> Color {
        let val = valueFor(gpu: gpu)
        switch metric {
        case .gpuUtil:
            return Color.green.opacity(0.2 + (val / 100.0) * 0.8)
        case .memoryUtil:
            return Color.blue.opacity(0.2 + (val / 100.0) * 0.8)
        case .temperature:
            // 0-100 map to Green -> Yellow -> Red
            if val < 50 { return .green }
            if val < 80 { return .yellow }
            return .red
        case .power:
            let ratio = gpu.powerLimit > 0 ? gpu.powerDraw / gpu.powerLimit : 0
            return Color.orange.opacity(0.2 + ratio * 0.8)
        }
    }
}
