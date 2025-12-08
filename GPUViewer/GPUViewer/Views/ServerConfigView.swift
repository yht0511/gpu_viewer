import SwiftUI

struct ServerConfigView: View {
    @Binding var config: ServerConfig
    
    var body: some View {
        Form {
            Section(header: Text("General")) {
                TextField("Name", text: $config.name)
                TextField("Host", text: $config.host)
                TextField("Port", value: $config.port, formatter: NumberFormatter())
                TextField("Username", text: $config.username)
            }
            
            Section(header: Text("Authentication")) {
                TextField("Identity File (~/.ssh/id_rsa)", text: Binding(
                    get: { config.identityFile ?? "" },
                    set: { config.identityFile = $0.isEmpty ? nil : $0 }
                ))
                SecureField("Password (Optional)", text: Binding(
                    get: { config.password ?? "" },
                    set: { config.password = $0.isEmpty ? nil : $0 }
                ))
            }
            
            Section(header: Text("Proxy / Advanced")) {
                TextField("Proxy Jump (-J)", text: Binding(
                    get: { config.proxyJump ?? "" },
                    set: { config.proxyJump = $0.isEmpty ? nil : $0 }
                ))
                TextField("Proxy Command (-o ProxyCommand)", text: Binding(
                    get: { config.proxyCommand ?? "" },
                    set: { config.proxyCommand = $0.isEmpty ? nil : $0 }
                ))
            }
        }
        .padding()
    }
}
