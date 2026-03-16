import Foundation

enum SSHError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return "SSH: \(msg)"
        }
    }
}

final class SSHService: @unchecked Sendable {
    static let shared = SSHService()

    func run(device: RemoteDevice, command: String, connectTimeout: Int = 15) async throws -> String {
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
                    continuation.resume(throwing: SSHError.failed(msg))
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
}
