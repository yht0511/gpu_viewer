import SwiftUI

struct AddServerSheet: View {
    @Binding var config: ServerConfig
    @Binding var isPresented: Bool
    var onSave: (ServerConfig) -> Void
    
    var body: some View {
        VStack {
            Text(config.name.isEmpty ? "Add New Server" : "Edit Server")
                .font(.headline)
                .padding()
            
            ServerConfigView(config: $config)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add") {
                    // Simple validation
                    if !config.name.isEmpty && !config.host.isEmpty && !config.username.isEmpty {
                        onSave(config)
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(config.name.isEmpty || config.host.isEmpty || config.username.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .padding()
    }
}
