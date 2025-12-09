import Foundation

class SSHClient {
    static let shared = SSHClient()
    
    private init() {}
    
    // Path to the ssh binary
    private let sshPath = "/usr/bin/ssh"
    
    // ControlMaster directory
    private var controlPathDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ssh/sockets"
    }
    
    // ASK_PASS script path
    private var askPassPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ssh/askpass_gpuviewer.sh"
    }

    func ensureSocketDir() {
        try? FileManager.default.createDirectory(atPath: controlPathDir, withIntermediateDirectories: true)
        createAskPassScript()
    }
    
    private func createAskPassScript() {
        // Create a simple script that echoes the password from env var
        let script = """
        #!/bin/sh
        echo "$SSH_PASSWORD"
        """
        
        if !FileManager.default.fileExists(atPath: askPassPath) {
            try? script.write(toFile: askPassPath, atomically: true, encoding: .utf8)
            // Make executable
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: askPassPath)
        }
    }
    
    func fetchMetrics(for config: ServerConfig) async throws -> String {
        ensureSocketDir()
        
        // Command to run on the remote server
        // 1. GPU CSV
        // 2. CPU (top -bn1) - simplified grep for Cpu line
        // 3. Mem (free -m)
        // 4. Processes (nvidia-smi pmon -c 1 or query-compute-apps)
        // Note: query-compute-apps doesn't give username directly in some versions, but we can try ps
        // Better strategy: query-compute-apps gives pid, used_memory. Then use ps -p <pids> -o user,comm to get details.
        // For simplicity and speed in one go, we can use a combined shell script.
        
        let remoteCommand = """
        export PATH=$PATH:/usr/local/cuda/bin:/usr/sbin:/sbin
        export LC_ALL=C
        echo "___SECTION_GPU___"
        nvidia-smi --query-gpu=index,uuid,name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,power.limit --format=csv,noheader,nounits
        echo "___SECTION_CPU___"
        top -bn1 | grep "Cpu(s)"
        echo "___SECTION_MEM___"
        free -m | grep Mem
        echo "___SECTION_PROCESS___"
        # Try query-compute-apps with gpu_uuid instead of gpu_index (which is often missing)
        p_out=$(nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader,nounits 2>/dev/null)
        if [ -z "$p_out" ]; then
            # Fallback to fuser/ps if nvidia-smi returns nothing but GPU is used
            # We use "NONE" as uuid for fallback processes
            # Use args for full command, put it last to avoid column shifting
            ps -eo pid,user,rss,args --sort=-rss | head -n 20 | awk 'NR>1 {pid=$1; user=$2; mem=$3/1024; $1=$2=$3=""; cmd=$0; gsub(/^[ \t]+/, "", cmd); gsub(",", " ", cmd); print "NONE,"pid","mem","user","cmd}'
        else
            echo "$p_out" | while IFS=, read -r gpu_uuid pid used_mem; do
                gpu_uuid=$(echo "$gpu_uuid" | tr -d '[:space:]')
                pid=$(echo "$pid" | tr -d '[:space:]')
                used_mem=$(echo "$used_mem" | tr -d '[:space:]')
                
                if [ -n "$pid" ]; then
                    user=$(ps -o user= -p "$pid" 2>/dev/null | tr -d '[:space:]')
                    # Get full command with args
                    comm=$(ps -o args= -p "$pid" 2>/dev/null)
                    
                    [ -z "$user" ] && user="unknown"
                    [ -z "$comm" ] && comm="unknown"
                    
                    # Replace commas in command to avoid CSV parsing issues
                    comm=$(echo "$comm" | tr ',' ' ')
                    
                    echo "$gpu_uuid,$pid,$used_mem,$user,$comm"
                fi
            done
        fi
        """
        
        // print("Executing remote command on \(config.name):")
        // print(remoteCommand)
        
        return try await runSSHCommand(config: config, command: remoteCommand)
    }
    
    private func runSSHCommand(config: ServerConfig, command: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        
        var args: [String] = []
        
        // Connection Sharing (ControlMaster) for performance
        let controlPath = "\(controlPathDir)/%r@%h:%p"
        args.append(contentsOf: ["-o", "ControlMaster=auto"])
        args.append(contentsOf: ["-o", "ControlPath=\(controlPath)"])
        args.append(contentsOf: ["-o", "ControlPersist=600"])
        
        // Auth & Connection
        if let identity = config.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines), !identity.isEmpty {
            args.append(contentsOf: ["-i", identity])
        }
        if let proxyJump = config.proxyJump?.trimmingCharacters(in: .whitespacesAndNewlines), !proxyJump.isEmpty {
            args.append(contentsOf: ["-J", proxyJump])
        }
        if let proxyCmd = config.proxyCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !proxyCmd.isEmpty {
            args.append(contentsOf: ["-o", "ProxyCommand=\(proxyCmd)"])
        }
        
        // ConnectTimeout to avoid hanging
        args.append(contentsOf: ["-o", "ConnectTimeout=5"])
        // StrictHostKeyChecking=no to avoid prompt on new hosts (use with caution, but user wants convenience)
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=no"])
        
        // Password Auth Handling
        var env: [String: String] = ProcessInfo.processInfo.environment
        if let password = config.password, !password.isEmpty {
            // Use SSH_ASKPASS trick
            env["SSH_ASKPASS"] = askPassPath
            env["SSH_PASSWORD"] = password
            env["DISPLAY"] = ":0" // Needed for SSH_ASKPASS to trigger
            args.append(contentsOf: ["-o", "BatchMode=no"]) // Allow interactive (but handled by askpass)
            // Detach from TTY to force askpass
            // process.standardInput = Pipe() 
        } else {
             args.append(contentsOf: ["-o", "BatchMode=yes"]) // Fail if password needed but not provided
        }
        
        args.append("-p")
        args.append("\(config.port)")
        args.append("\(config.username.trimmingCharacters(in: .whitespacesAndNewlines))@\(config.host.trimmingCharacters(in: .whitespacesAndNewlines))")
        
        args.append(command)
        
        // print("SSH Command Arguments: \(args)")
        
        process.arguments = args
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                
                process.terminationHandler = { proc in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    // print("SSH Output from \(config.name):")
                    // print(output)
                    
                    if proc.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errOutput = String(data: errData, encoding: .utf8) ?? "Unknown SSH Error"
                        
                        // print("SSH Error from \(config.name):")
                        // print(errOutput)
                        
                        continuation.resume(throwing: NSError(domain: "SSHClient", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errOutput]))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
