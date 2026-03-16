import Foundation

final class SessionDetailService: Sendable {
    private let claudeDir: URL
    private let ssh = SSHService.shared

    init() {
        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            self.claudeDir = URL(fileURLWithPath: configDir)
        } else {
            self.claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        }
    }

    func loadSession(sessionId: String, projectDir: String) async -> SessionDetail? {
        if projectDir.hasPrefix("OpenClaw") {
            let home = URL(fileURLWithPath: NSHomeDirectory())
            let fm = FileManager.default
            if let entries = try? fm.contentsOfDirectory(atPath: home.path) {
                for entry in entries where entry.hasPrefix(".openclaw") {
                    let sessionsGlob = home.appendingPathComponent(entry).appendingPathComponent("agents")
                    if let agentDirs = try? fm.contentsOfDirectory(atPath: sessionsGlob.path) {
                        for agent in agentDirs {
                            let filePath = sessionsGlob
                                .appendingPathComponent(agent)
                                .appendingPathComponent("sessions")
                                .appendingPathComponent("\(sessionId).jsonl")
                                .path
                            if fm.fileExists(atPath: filePath) {
                                return await Task.detached {
                                    self.parseSessionFile(path: filePath, sessionId: sessionId, isOpenClaw: true)
                                }.value
                            }
                        }
                    }
                }
            }
            return nil
        }

        let filePath = claudeDir
            .appendingPathComponent("projects")
            .appendingPathComponent(projectDir)
            .appendingPathComponent("\(sessionId).jsonl")
            .path

        guard FileManager.default.fileExists(atPath: filePath) else { return nil }

        return await Task.detached {
            self.parseSessionFile(path: filePath, sessionId: sessionId)
        }.value
    }

    func loadRemoteSession(sessionId: String, projectDir: String, device: RemoteDevice) async throws -> SessionDetail? {
        if projectDir.hasPrefix("OpenClaw") {
            for ocPath in device.openClawPaths {
                let remotePath = "\(ocPath)/agents/main/sessions/\(sessionId).jsonl"
                let output = try await ssh.run(device: device, command: "cat \(remotePath) 2>/dev/null")
                if !output.isEmpty {
                    return await Task.detached {
                        self.parseLines(output, sessionId: sessionId, isOpenClaw: true)
                    }.value
                }
            }
            return nil
        }

        let remotePath = "\(device.claudePath)/projects/\(projectDir)/\(sessionId).jsonl"
        let output = try await ssh.run(device: device, command: "cat \(remotePath) 2>/dev/null")
        guard !output.isEmpty else { return nil }

        return await Task.detached {
            self.parseLines(output, sessionId: sessionId)
        }.value
    }

    private func parseLines(_ content: String, sessionId: String, isOpenClaw: Bool = false) -> SessionDetail {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        var messages: [SessionMessage] = []

        for line in lines {
            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                guard let parsed = self.parseMessageJSON(json, isOpenClaw: isOpenClaw) else { return }
                messages.append(parsed)
            }
        }

        return SessionDetail(sessionId: sessionId, messages: messages)
    }

    private func parseSessionFile(path: String, sessionId: String, isOpenClaw: Bool = false) -> SessionDetail {
        guard let file = fopen(path, "r") else {
            return SessionDetail(sessionId: sessionId, messages: [])
        }
        defer { fclose(file) }

        var linePtr: UnsafeMutablePointer<CChar>? = nil
        var lineCapacity: Int = 0
        defer { free(linePtr) }

        var messages: [SessionMessage] = []

        while getline(&linePtr, &lineCapacity, file) > 0 {
            guard let ptr = linePtr else { continue }

            autoreleasepool {
                let len = strlen(ptr)
                let data = Data(bytes: ptr, count: len)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                guard let parsed = self.parseMessageJSON(json, isOpenClaw: isOpenClaw) else { return }
                messages.append(parsed)
            }
        }

        return SessionDetail(sessionId: sessionId, messages: messages)
    }

    private func parseMessageJSON(_ json: [String: Any], isOpenClaw: Bool) -> SessionMessage? {
        let type = json["type"] as? String ?? ""
        let message = json["message"] as? [String: Any] ?? [:]

        let role: SessionMessage.MessageRole
        if isOpenClaw {
            guard type == "message" else { return nil }
            let msgRole = message["role"] as? String ?? ""
            switch msgRole {
            case "user": role = .user
            case "assistant": role = .assistant
            default: return nil
            }
        } else {
            guard type == "user" || type == "assistant" else { return nil }
            if json["isMeta"] as? Bool == true { return nil }
            if json["isSidechain"] as? Bool == true { return nil }
            role = type == "user" ? .user : .assistant
        }

        let uuid = json["uuid"] as? String ?? json["id"] as? String ?? UUID().uuidString
        let timestamp: Date
        if let ts = json["timestamp"] as? String {
            timestamp = CauditFormatter.parseISO8601(ts) ?? Date()
        } else {
            timestamp = Date()
        }

        let contentItems = parseContent(message: message, role: role, isOpenClaw: isOpenClaw)
        guard !contentItems.isEmpty else { return nil }

        return SessionMessage(id: uuid, role: role, timestamp: timestamp, content: contentItems)
    }

    private func parseContent(message: [String: Any], role: SessionMessage.MessageRole, isOpenClaw: Bool = false) -> [SessionContentItem] {
        let rawContent = message["content"]
        var items: [SessionContentItem] = []

        if let text = rawContent as? String {
            let cleaned = stripXMLTags(text)
            if !cleaned.isEmpty {
                items.append(.text(cleaned))
            }
            return items
        }

        guard let contentArray = rawContent as? [[String: Any]] else { return items }

        for block in contentArray {
            let blockType = block["type"] as? String ?? ""

            switch blockType {
            case "text":
                let text = block["text"] as? String ?? ""
                let cleaned = role == .user ? stripXMLTags(text) : text
                if !cleaned.isEmpty {
                    items.append(.text(cleaned))
                }

            case "thinking":
                let text = block["thinking"] as? String ?? ""
                if !text.isEmpty {
                    items.append(.thinking(text))
                }

            case "tool_use", "toolCall":
                let id = block["id"] as? String ?? UUID().uuidString
                let name = block["name"] as? String ?? "unknown"
                let input: String
                if let inputDict = block["input"] ?? block["arguments"] {
                    if let inputData = try? JSONSerialization.data(withJSONObject: inputDict, options: [.prettyPrinted]),
                       let inputStr = String(data: inputData, encoding: .utf8) {
                        input = inputStr
                    } else {
                        input = "\(inputDict)"
                    }
                } else {
                    input = ""
                }
                items.append(.toolUse(id: id, name: name, input: input))

            case "tool_result", "toolResult":
                let id = block["tool_use_id"] as? String ?? UUID().uuidString
                let isError = block["is_error"] as? Bool ?? false
                let content: String
                if let c = block["content"] as? String {
                    content = c
                } else if let cArray = block["content"] as? [[String: Any]] {
                    content = cArray.compactMap { $0["text"] as? String }.joined(separator: "\n")
                } else {
                    content = ""
                }
                items.append(.toolResult(id: id, content: content, isError: isError))

            default:
                break
            }
        }

        return items
    }

    private func stripXMLTags(_ text: String) -> String {
        var result = text
        while let range = result.range(of: "<[^>]+>[\\s\\S]*?</[^>]+>", options: .regularExpression) {
            result.removeSubrange(range)
        }
        while let range = result.range(of: "<[^>]+/>", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
