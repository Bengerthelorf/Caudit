import Foundation

final class RemoteUsageService: @unchecked Sendable {

    // MARK: - Public

    func fingerprint(for device: RemoteDevice) async throws -> String {
        let ocFinds = device.openClawPaths.map { "find \($0)/agents -name '*.jsonl' 2>/dev/null" }.joined(separator: "; ")
        let cmd = "{ find \(device.claudePath)/projects -name '*.jsonl' 2>/dev/null; \(ocFinds); } | xargs ls -ln 2>/dev/null | awk '{s+=$5} END{print NR,s}'; true"
        return try await runSSH(device: device, command: cmd, connectTimeout: 10)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchRecords(from device: RemoteDevice) async throws -> [UsageRecord] {
        // Claude Code grep
        var parts = ["""
        find \(device.claudePath)/projects -name '*.jsonl' 2>/dev/null | while IFS= read -r f; do \
        rel="${f#*/projects/}"; proj="${rel%%/*}"; \
        echo "===CAUDIT_PROJECT:${proj}==="; grep '"input_tokens"' "$f" 2>/dev/null; done
        """]

        // OpenClaw grep for each configured path
        for ocPath in device.openClawPaths {
            let dirName = (ocPath as NSString).lastPathComponent
            parts.append("""
            find \(ocPath)/agents -name '*.jsonl' 2>/dev/null | while IFS= read -r f; do \
            sess=$(basename "$f" .jsonl); \
            echo "===CAUDIT_OC:\(dirName)/${sess}==="; grep '"usage":{' "$f" 2>/dev/null; done
            """)
        }

        let script = parts.joined(separator: "; ") + "; true"
        let output = try await runSSH(device: device, command: script)
        return UsageParser.parseGrepOutput(output, projectPrefix: device.name, source: device.name)
    }

    func testConnection(_ device: RemoteDevice) async -> (success: Bool, message: String) {
        do {
            let ocChecks = device.openClawPaths.map { "ls -d \($0)/agents 2>/dev/null" }.joined(separator: " || ")
            let cmd = "echo ok && (ls -d \(device.claudePath)/projects 2>/dev/null || \(ocChecks)) && echo found || echo missing"
            let output = try await runSSH(device: device, command: cmd, connectTimeout: 10)
            let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
            if lines.first == "ok" {
                return lines.contains("found")
                    ? (true, "Connected. Usage data found.")
                    : (true, "Connected, but no usage data found")
            }
            return (false, "Unexpected response")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - SSH

    private func runSSH(device: RemoteDevice, command: String, connectTimeout: Int = 15) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

                var args = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=\(connectTimeout)",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ServerAliveInterval=10",
                    "-o", "ServerAliveCountMax=3",
                ]

                if !device.identityFile.isEmpty {
                    let expanded = NSString(string: device.identityFile).expandingTildeInPath
                    args += ["-i", expanded]
                }

                args += [device.sshHost, command]
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                if env["SSH_AUTH_SOCK"] == nil {
                    if let sock = Self.launchdSSHAuthSocket() {
                        env["SSH_AUTH_SOCK"] = sock
                    }
                }
                process.environment = env

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                var outData = Data()
                var errData = Data()
                let readGroup = DispatchGroup()

                readGroup.enter()
                DispatchQueue.global().async {
                    outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                readGroup.enter()
                DispatchQueue.global().async {
                    errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                readGroup.wait()
                process.waitUntilExit()

                let output = String(data: outData, encoding: .utf8) ?? ""

                if !output.isEmpty || process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let msg = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "SSH failed"
                    continuation.resume(throwing: RemoteError.sshFailed(msg))
                }
            }
        }
    }

    private static func launchdSSHAuthSocket() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["getenv", "SSH_AUTH_SOCK"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let sock = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (sock?.isEmpty == false) ? sock : nil
        } catch {
            return nil
        }
    }

    enum RemoteError: LocalizedError {
        case sshFailed(String)

        var errorDescription: String? {
            switch self {
            case .sshFailed(let msg): return "SSH: \(msg)"
            }
        }
    }
}
