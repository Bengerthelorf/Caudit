import Foundation

final class SessionDetailService: Sendable {
    private let claudeDir: URL

    init() {
        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            self.claudeDir = URL(fileURLWithPath: configDir)
        } else {
            self.claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        }
    }

    func loadSession(sessionId: String, projectDir: String) async -> SessionDetail? {
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

    private func parseSessionFile(path: String, sessionId: String) -> SessionDetail {
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
            let len = strlen(ptr)
            let data = Data(bytes: ptr, count: len)

            autoreleasepool {
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                let type = json["type"] as? String ?? ""
                guard type == "user" || type == "assistant" else { return }

                // Skip meta and sidechain messages
                if json["isMeta"] as? Bool == true { return }
                if json["isSidechain"] as? Bool == true { return }

                let uuid = json["uuid"] as? String ?? UUID().uuidString
                let timestamp: Date
                if let ts = json["timestamp"] as? String {
                    timestamp = CauditFormatter.parseISO8601(ts) ?? Date()
                } else {
                    timestamp = Date()
                }

                let role: SessionMessage.MessageRole = type == "user" ? .user : .assistant
                let message = json["message"] as? [String: Any] ?? [:]
                let contentItems = parseContent(message: message, role: role)

                guard !contentItems.isEmpty else { return }

                messages.append(SessionMessage(
                    id: uuid, role: role, timestamp: timestamp, content: contentItems
                ))
            }
        }

        return SessionDetail(sessionId: sessionId, messages: messages)
    }

    private func parseContent(message: [String: Any], role: SessionMessage.MessageRole) -> [SessionContentItem] {
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

            case "tool_use":
                let id = block["id"] as? String ?? UUID().uuidString
                let name = block["name"] as? String ?? "unknown"
                let input: String
                if let inputDict = block["input"] {
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

            case "tool_result":
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
        // Remove XML-style tags like <local-command-caveat>...</local-command-caveat>
        var result = text
        while let range = result.range(of: "<[^>]+>[\\s\\S]*?</[^>]+>", options: .regularExpression) {
            result.removeSubrange(range)
        }
        // Also remove self-closing tags
        while let range = result.range(of: "<[^>]+/>", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
