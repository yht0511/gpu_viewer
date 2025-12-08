import Foundation
import Darwin

class SSHConfigParser {
    struct SSHBlock {
        var patterns: [String]
        var properties: [String: String]
    }
    
    static func parse(content: String) -> [ServerConfig] {
        let lines = content.components(separatedBy: .newlines)
        var blocks: [SSHBlock] = []
        var currentBlock: SSHBlock?
        
        // Helper to finalize a block
        func finalizeBlock() {
            if let block = currentBlock {
                blocks.append(block)
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Check for Host line (case insensitive)
            if trimmed.lowercased().hasPrefix("host ") || trimmed.lowercased().hasPrefix("host\t") || trimmed.lowercased() == "host" {
                // Start new block
                finalizeBlock()
                
                // Extract patterns
                // "Host pattern1 pattern2"
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count > 1 {
                    let patterns = parts.dropFirst().map { String($0) }
                    currentBlock = SSHBlock(patterns: patterns, properties: [:])
                } else {
                    currentBlock = nil // Invalid Host line
                }
            } else {
                // Property line
                // "Key Value" or "Key=Value"
                // Split by space or =
                if currentBlock != nil {
                    // Try to split by first space or =
                    // Regex might be overkill, manual scan is fine
                    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    if parts.count >= 2 {
                        let key = String(parts[0]).lowercased()
                        var value = String(parts[1])
                        
                        // Handle "Key=Value" case if needed, but SSH config usually space separated
                        // If user used =, split check might fail or capture it
                        
                        if value.hasPrefix("=") {
                            value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
                        }
                        
                        // Store property if not exists (first match in block wins? No, in block last match wins?
                        // Actually in SSH config file, within a block, first match wins too?
                        // man ssh_config: "For each parameter, the first obtained value will be used."
                        // So we should only set if nil.
                        if currentBlock?.properties[key] == nil {
                            currentBlock?.properties[key] = value
                        }
                    }
                }
            }
        }
        finalizeBlock()
        
        // Now we have all blocks.
        // Identify concrete hosts.
        var concreteHosts: Set<String> = []
        for block in blocks {
            for pattern in block.patterns {
                if !pattern.contains("*") && !pattern.contains("?") {
                    concreteHosts.insert(pattern)
                }
            }
        }
        
        var configs: [ServerConfig] = []
        
        for host in concreteHosts.sorted() {
            // Resolve config for this host
            var resolved: [String: String] = [:]
            
            for block in blocks {
                // Check if host matches any pattern in block
                var match = false
                for pattern in block.patterns {
                    if fnmatch(pattern, host) {
                        match = true
                        break
                    }
                }
                
                if match {
                    // Apply properties
                    for (k, v) in block.properties {
                        if resolved[k] == nil {
                            resolved[k] = v
                        }
                    }
                }
            }
            
            // Build ServerConfig
            // Required: HostName (fallback to host alias if missing? SSH does this)
            // User (required by our app?)
            
            let hostName = resolved["hostname"] ?? host
            let user = resolved["user"] ?? NSUserName() // Default to current user
            let port = Int(resolved["port"] ?? "22") ?? 22
            let identityFile = resolved["identityfile"]
            let proxyJump = resolved["proxyjump"]
            let proxyCommand = resolved["proxycommand"]
            
            // Clean up IdentityFile path (remove quotes, expand tilde)
            let cleanIdentityFile = cleanPath(identityFile)
            
            let config = ServerConfig(
                name: host,
                host: hostName,
                port: port,
                username: user,
                identityFile: cleanIdentityFile,
                proxyJump: proxyJump,
                proxyCommand: proxyCommand
            )
            configs.append(config)
        }
        
        return configs
    }
    
    // Simple glob matching wrapper
    static func fnmatch(_ pattern: String, _ string: String) -> Bool {
        return pattern.withCString { p in
            string.withCString { s in
                Darwin.fnmatch(p, s, 0) == 0
            }
        }
    }
    
    static func cleanPath(_ path: String?) -> String? {
        guard var p = path else { return nil }
        // Remove quotes
        p = p.replacingOccurrences(of: "\"", with: "")
        // Expand tilde
        if p.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            p = home + p.dropFirst()
        }
        return p
    }
}
