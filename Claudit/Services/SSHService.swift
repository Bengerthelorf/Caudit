import Foundation

enum SSHError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return "SSH: \(msg)"
        }
    }
}

final class SSHService: Sendable {
    static let shared = SSHService()

    func run(device: RemoteDevice, command: String, connectTimeout: Int = 15, commandTimeout: TimeInterval = 60) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        let password = device.usePassword ? SSHPasswordStore.load(for: device.id) : nil
        var askpassScript: String?

        var args = [
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3",
        ]

        if let password, !password.isEmpty {
            // Create a temporary askpass script that echoes the password
            let scriptPath = NSTemporaryDirectory() + "claudit-askpass-\(UUID().uuidString)"
            let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
            let script = "#!/bin/sh\necho '\(escaped)'"
            FileManager.default.createFile(
                atPath: scriptPath,
                contents: script.data(using: .utf8),
                attributes: [.posixPermissions: 0o700]
            )
            askpassScript = scriptPath
            args += ["-o", "NumberOfPasswordPrompts=1"]
        } else {
            args += ["-o", "BatchMode=yes"]
        }

        if !device.identityFile.isEmpty {
            let expanded = NSString(string: device.identityFile).expandingTildeInPath
            args += ["-i", expanded]
        }

        args += [device.sshHost, command]
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        if let scriptPath = askpassScript {
            env["SSH_ASKPASS"] = scriptPath
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = ":0"
            // Prevent SSH agent from bypassing password
            env.removeValue(forKey: "SSH_AUTH_SOCK")
        } else {
            if env["SSH_AUTH_SOCK"] == nil {
                if let sock = Self.launchdSSHAuthSocket() {
                    env["SSH_AUTH_SOCK"] = sock
                }
            }
        }
        process.environment = env

        defer {
            if let scriptPath = askpassScript {
                try? FileManager.default.removeItem(atPath: scriptPath)
            }
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let outBox = SendableBox()
        let errBox = SendableBox()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global().async {
            outBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global().async {
            errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { _ in
                        readGroup.wait()
                        let output = String(data: outBox.data, encoding: .utf8) ?? ""
                        if !output.isEmpty || process.terminationStatus == 0 {
                            continuation.resume(returning: output)
                        } else {
                            let msg = String(data: errBox.data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "SSH failed"
                            continuation.resume(throwing: SSHError.failed(msg))
                        }
                    }

                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        try? stdout.fileHandleForWriting.close()
                        try? stderr.fileHandleForWriting.close()
                        readGroup.wait()
                        continuation.resume(throwing: error)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(commandTimeout))
                process.terminate()
                throw SSHError.failed("Command timed out after \(Int(commandTimeout))s")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
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

private final class SendableBox: @unchecked Sendable {
    var data = Data()
}

/// Shell-escape a string so it can be safely interpolated into shell commands.
/// Handles tilde expansion by splitting ~/... into ~/'...' so the shell can
/// resolve ~ while the rest stays safely quoted.
enum ShellEscape {
    static func path(_ value: String) -> String {
        var prefix = ""
        var rest = value
        // Split off ~ prefix so shell can expand it outside quotes
        if rest.hasPrefix("~/") {
            prefix = "~/"
            rest = String(rest.dropFirst(2))
        } else if rest == "~" {
            return "~"
        }
        // Escape single quotes: replace ' with '\''
        let escaped = rest.replacingOccurrences(of: "'", with: "'\\''")
        return "\(prefix)'\(escaped)'"
    }
}
