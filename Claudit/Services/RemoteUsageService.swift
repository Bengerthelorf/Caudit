import Foundation

final class RemoteUsageService: Sendable {
    private let ssh = SSHService.shared

    func fingerprint(for device: RemoteDevice) async throws -> String {
        let esc = ShellEscape.path
        let ocFinds = device.openClawPaths.map { "find \(esc($0))/agents -name '*.jsonl' 2>/dev/null" }.joined(separator: "; ")
        let cmd = "{ find \(esc(device.claudePath))/projects -name '*.jsonl' 2>/dev/null; \(ocFinds); } | xargs ls -ln 2>/dev/null | awk '{s+=$5} END{print NR,s}'; true"
        return try await ssh.run(device: device, command: cmd, connectTimeout: 10)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchRecords(from device: RemoteDevice) async throws -> [UsageRecord] {
        let esc = ShellEscape.path
        var parts = ["""
        find \(esc(device.claudePath))/projects -name '*.jsonl' 2>/dev/null | while IFS= read -r f; do \
        rel="${f#*/projects/}"; proj="${rel%%/*}"; \
        echo "===CLAUDIT_PROJECT:${proj}==="; grep '"input_tokens"' "$f" 2>/dev/null; done
        """]

        for ocPath in device.openClawPaths {
            let dirName = (ocPath as NSString).lastPathComponent
            parts.append("""
            find \(esc(ocPath))/agents -name '*.jsonl' 2>/dev/null | while IFS= read -r f; do \
            sess=$(basename "$f" .jsonl); \
            echo "===CLAUDIT_OC:\(dirName)/${sess}==="; grep '"usage"' "$f" 2>/dev/null; done
            """)
        }

        let script = parts.joined(separator: "; ") + "; true"
        let output = try await ssh.run(device: device, command: script)
        return UsageParser.parseGrepOutput(output, projectPrefix: device.name, source: device.name)
    }

    func testConnection(_ device: RemoteDevice) async -> (success: Bool, message: String) {
        do {
            let esc = ShellEscape.path
            let ocChecks = device.openClawPaths.map { "ls -d \(esc($0))/agents 2>/dev/null" }.joined(separator: " || ")
            let cmd = "echo ok && (ls -d \(esc(device.claudePath))/projects 2>/dev/null || \(ocChecks)) && echo found || echo missing"
            let output = try await ssh.run(device: device, command: cmd, connectTimeout: 10)
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
}
