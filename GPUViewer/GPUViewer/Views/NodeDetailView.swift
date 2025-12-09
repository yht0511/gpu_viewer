import SwiftUI
import Charts
import AppKit

struct NodeDetailView: View {
    let server: ServerConfig
    @ObservedObject var appState: AppState
    
    @State private var selectedGPUIndex: Int = 0
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar: Component List (Win10 Style)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if let status = appState.nodeStatuses[server.id] {
                            // CPU
                            ComponentRow(name: "CPU", value: "\(Int(status.cpuUsage))%", graphValue: status.cpuUsage / 100.0, isSelected: selectedGPUIndex == -1)
                                .onTapGesture { selectedGPUIndex = -1 }
                            
                            // RAM
                            ComponentRow(name: "Memory", value: String(format: "%.1f GB", status.ramUsed), graphValue: status.ramTotal > 0 ? status.ramUsed / status.ramTotal : 0, isSelected: selectedGPUIndex == -2)
                                .onTapGesture { selectedGPUIndex = -2 }
                            
                            Divider()
                            
                            // GPUs
                            ForEach(status.gpus) { gpu in
                                ComponentRow(name: "GPU \(gpu.id)", value: "\(Int(gpu.utilGPU))%", graphValue: gpu.utilGPU / 100.0, isSelected: selectedGPUIndex == gpu.id)
                                    .id(gpu.id) // ID for ScrollViewReader
                                    .onTapGesture { selectedGPUIndex = gpu.id }
                            }
                        } else {
                            Text("Connecting...")
                                .padding()
                        }
                    }
                    .padding(.vertical)
                }
                .onAppear {
                    // Check if we have a pending selection from Overview
                    if let index = appState.selectedGpuIndex {
                        selectedGPUIndex = index
                        // Delay scroll slightly to ensure layout is ready
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                        appState.selectedGpuIndex = nil
                    }
                }
                .onChange(of: appState.selectedGpuIndex) { newIndex in
                    if let index = newIndex {
                        selectedGPUIndex = index
                        withAnimation {
                            proxy.scrollTo(index, anchor: .center)
                        }
                        // Reset global state so it doesn't stick
                        appState.selectedGpuIndex = nil
                    }
                }
            }
            .frame(width: 250)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Right Main Content
            VStack {
                if let status = appState.nodeStatuses[server.id] {
                    if selectedGPUIndex >= 0 {
                        // GPU Detail
                        if let gpu = status.gpus.first(where: { $0.id == selectedGPUIndex }) {
                            GPUDetailPane(gpu: gpu, history: status.history, processes: status.topProcesses)
                        }
                    } else if selectedGPUIndex == -1 {
                        // CPU Detail
                        VStack {
                            Text("CPU Usage History").font(.headline)
                            HistoryChart(history: status.history, keyPath: \.cpuUsage, color: .blue)
                            Spacer()
                        }
                        .padding()
                    } else if selectedGPUIndex == -2 {
                        // Memory Detail
                        VStack {
                            Text("Memory Usage History").font(.headline)
                            HistoryChart(history: status.history, keyPath: \.ramUsage, color: .purple)
                            Spacer()
                        }
                        .padding()
                    } else if selectedGPUIndex == -3 {
                        // All Processes Detail
                        VStack(alignment: .leading) {
                            Text("All Running Processes").font(.headline).padding(.horizontal)
                            ProcessTable(processes: status.topProcesses)
                        }
                        .padding()
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle(server.name)
    }
}

struct HistoryChart: View {
    let history: [HistoryPoint]
    let keyPath: KeyPath<HistoryPoint, Double>
    let color: Color
    
    var body: some View {
        Chart(history) { point in
            LineMark(
                x: .value("Time", point.id),
                y: .value("Value", point[keyPath: keyPath])
            )
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", point.id),
                y: .value("Value", point[keyPath: keyPath])
            )
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...100)
    }
}

struct ComponentRow: View {
    let name: String
    let value: String
    let graphValue: Double
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text(value).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            // Mini sparkline
            Sparkline(value: graphValue)
                .frame(width: 50, height: 30)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}

struct Sparkline: View {
    let value: Double
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let h = geo.size.height
                let w = geo.size.width
                path.move(to: CGPoint(x: 0, y: h))
                // Simple bar for now as we don't have history in row yet, or just fill level
                path.addLine(to: CGPoint(x: 0, y: h * (1.0 - value)))
                path.addLine(to: CGPoint(x: w, y: h * (1.0 - value)))
                path.addLine(to: CGPoint(x: w, y: h))
            }
            .fill(Color.accentColor.opacity(0.5))
        }
    }
}

struct GPUDetailPane: View {
    let gpu: GPUData
    let history: [HistoryPoint]
    let processes: [GPUProcessInfo]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(gpu.name)
                    .font(.title)
                
                HStack(spacing: 20) {
                    GaugeView(title: "Utilization", value: gpu.utilGPU, max: 100, unit: "%")
                    GaugeView(title: "Memory", value: gpu.memoryUsed, max: gpu.memoryTotal, unit: "MB")
                    GaugeView(title: "Temp", value: gpu.temperature, max: 100, unit: "°C")
                    GaugeView(title: "Power", value: gpu.powerDraw, max: gpu.powerLimit, unit: "W")
                }
                
                Divider()
                
                Text("Utilization History")
                    .font(.headline)
                
                Chart(history) { point in
                    LineMark(
                        x: .value("Time", point.id),
                        y: .value("Util", point.gpuUtilizations[gpu.id] ?? 0)
                    )
                    .foregroundStyle(.green)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 200)
                
                Divider()
                
                Text("Processes")
                    .font(.headline)
                
                let gpuProcs = processes.filter { $0.gpuIndex == gpu.id }
                if gpuProcs.isEmpty {
                    Text("No processes running")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ProcessTable(processes: gpuProcs)
                }
            }
            .padding()
        }
    }
}

struct ProcessTable: View {
    let processes: [GPUProcessInfo]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("PID").frame(width: 80, alignment: .leading)
                Divider().padding(.vertical, 4)
                Text("User").frame(width: 100, alignment: .leading).padding(.leading, 8)
                Divider().padding(.vertical, 4)
                Text("Command").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
                Divider().padding(.vertical, 4)
                Text("Memory").frame(width: 100, alignment: .trailing)
            }
            .font(.caption).bold()
            .frame(height: 30) // Fixed Header Height
            .padding(.horizontal, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Rows
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(processes) { proc in
                        HStack(spacing: 0) {
                            Text(proc.pid)
                                .frame(width: 80, alignment: .leading)
                                .font(.system(.body, design: .monospaced))
                            
                            Divider().padding(.vertical, 2)
                            
                            Text(proc.user)
                                .frame(width: 100, alignment: .leading)
                                .padding(.leading, 8)
                            
                            Divider().padding(.vertical, 2)
                            
                            Text(proc.command)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.leading, 8)
                                .help(proc.command) // Hover to show full command
                            
                            Divider().padding(.vertical, 2)
                            
                            Text("\(Int(proc.memoryUsed)) MB")
                                .frame(width: 100, alignment: .trailing)
                        }
                        .frame(height: 30) // Fixed Row Height
                        .padding(.horizontal, 8)
                        .background(Color(NSColor.windowBackgroundColor))
                        
                        Divider()
                    }
                    
                    // Spacer to fill remaining background if few rows
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(NSColor.windowBackgroundColor)) // Ensure background is uniform
        }
        .border(Color.gray.opacity(0.2), width: 1)
        .cornerRadius(4)
        .frame(height: 300)
    }
}

struct GaugeView: View {
    let title: String
    let value: Double
    let max: Double
    let unit: String
    
    var body: some View {
        VStack {
            Text(title).font(.caption)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    .rotationEffect(.degrees(135))
                
                Circle()
                    .trim(from: 0, to: 0.75 * (value / max))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))
                
                VStack {
                    Text("\(Int(value))")
                        .font(.title2)
                        .bold()
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)
        }
    }
}
