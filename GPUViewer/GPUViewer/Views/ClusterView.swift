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
                        NodeCard(server: server, status: appState.nodeStatuses[server.id], metric: appState.heatmapMetric, appState: appState)
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
    
    // Pass appState to update selection
    @ObservedObject var appState: AppState
    
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
                            .onTapGesture {
                                navigateToGPU(gpu)
                            }
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
                    HStack {
                        Label("\(Int(status.cpuUsage))%", systemImage: "cpu")
                    }
                    .contentShape(Rectangle()) // Make the whole area tappable
                    .onTapGesture {
                        navigateToCPU()
                    }
                    
                    Spacer()
                    
                    HStack {
                        Label("\(Int(status.ramUsed))/\(Int(status.ramTotal))G", systemImage: "memorychip")
                    }
                    .contentShape(Rectangle()) // Make the whole area tappable
                    .onTapGesture {
                        navigateToRAM()
                    }
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
            return appState.gpuColor.opacity(0.2 + (val / 100.0) * 0.8)
        case .memoryUtil:
            return appState.memoryColor.opacity(0.2 + (val / 100.0) * 0.8)
        case .temperature:
            // Use user defined temp color with opacity mapping
            return appState.tempColor.opacity(0.2 + (val / 100.0) * 0.8)
        case .power:
            let ratio = gpu.powerLimit > 0 ? gpu.powerDraw / gpu.powerLimit : 0
            return appState.powerColor.opacity(0.2 + ratio * 0.8)
        }
    }
    
    func navigateToGPU(_ gpu: GPUData) {
        appState.selectedGpuIndex = gpu.id
        appState.selectedNodeId = server.id
    }
    
    func navigateToCPU() {
        appState.selectedGpuIndex = -1 // -1 for CPU in NodeDetailView
        appState.selectedNodeId = server.id
    }
    
    func navigateToRAM() {
        appState.selectedGpuIndex = -2 // -2 for RAM in NodeDetailView
        appState.selectedNodeId = server.id
    }
}
