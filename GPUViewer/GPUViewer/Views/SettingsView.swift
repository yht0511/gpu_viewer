import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.headline)
            
            Form {
                Section(header: Text("General")) {
                    HStack {
                        Text("Refresh Interval:")
                        Slider(value: $appState.refreshInterval, in: 1...60, step: 1)
                        Text("\(Int(appState.refreshInterval))s")
                            .frame(width: 40)
                    }
                }
                
                Section(header: Text("Appearance")) {
                    ColorPicker("GPU Util Color", selection: $appState.gpuColor)
                    ColorPicker("Memory Util Color", selection: $appState.memoryColor)
                    ColorPicker("Temperature Color", selection: $appState.tempColor)
                    ColorPicker("Power Color", selection: $appState.powerColor)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
        .padding()
    }
}
