import SwiftUI

struct SSHImportSheet: View {
    @Binding var isPresented: Bool
    var onImport: ([ServerConfig]) -> Void
    
    @State private var configContent: String = ""
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Import from SSH Config")
                .font(.headline)
            
            Text("Paste your ~/.ssh/config content below:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextEditor(text: $configContent)
                .font(.system(.body, design: .monospaced))
                .border(Color.gray.opacity(0.2), width: 1)
                .frame(minHeight: 300)
            
            if let error = error {
                Text(error)
                    .foregroundColor(.red)
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                
                Button("Import") {
                    let configs = SSHConfigParser.parse(content: configContent)
                    if configs.isEmpty {
                        error = "No valid hosts found."
                    } else {
                        onImport(configs)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(configContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
}
