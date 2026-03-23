import AppKit
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Export")

enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case csv = "CSV"

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        }
    }
}

struct ExportService {

    static func exportRecords(_ records: [UsageRecord], format: ExportFormat) -> String {
        switch format {
        case .json: return toJSON(records)
        case .csv:  return toCSV(records)
        }
    }

    static func toJSON(_ records: [UsageRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        let entries: [[String: Any]] = records.map { r in
            [
                "timestamp": formatter.string(from: r.timestamp),
                "project": r.project,
                "model": r.model,
                "source": r.source,
                "session_id": r.sessionId,
                "input_tokens": r.inputTokens,
                "output_tokens": r.outputTokens,
                "cache_read_tokens": r.cacheReadTokens,
                "cache_write_tokens": r.cacheCreationTokens,
                "cost": r.cost,
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func toCSV(_ records: [UsageRecord]) -> String {
        let header = "Timestamp,Project,Model,Source,Session ID,Input Tokens,Output Tokens,Cache Read,Cache Write,Cost"
        let formatter = ISO8601DateFormatter()
        let rows = records.map { r in
            [
                formatter.string(from: r.timestamp),
                csvEscape(r.project),
                csvEscape(r.model),
                csvEscape(r.source),
                csvEscape(r.sessionId),
                "\(r.inputTokens)",
                "\(r.outputTokens)",
                "\(r.cacheReadTokens)",
                "\(r.cacheCreationTokens)",
                String(format: "%.6f", r.cost),
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    @MainActor
    static func saveToFile(content: String, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "claudit-export.\(format.fileExtension)"
        panel.allowedContentTypes = format == .json
            ? [.json]
            : [.commaSeparatedText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Exported \(format.rawValue) to \(url.path)")
        } catch {
            logger.error("Export failed: \(error.localizedDescription)")
        }
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
