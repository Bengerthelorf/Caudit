import Foundation

final class UsageParser: @unchecked Sendable {
    private let claudeDir: URL
    private let lock = NSLock()
    private var cachedFingerprint: String = ""
    private var cachedRecords: [UsageRecord] = []

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    init() {
        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            self.claudeDir = URL(fileURLWithPath: configDir)
        } else {
            self.claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        }
    }

    func parseAll() -> ParseResult {
        aggregate(records: scanLocalRecords())
    }

    // MARK: - Local Scanning

    func scanLocalRecords() -> [UsageRecord] {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDir.path) else { return [] }

        let newFingerprint = computeFingerprint(projectsDir: projectsDir, fm: fm)

        lock.lock()
        if newFingerprint == cachedFingerprint && !cachedRecords.isEmpty {
            let records = cachedRecords
            lock.unlock()
            return records
        }
        lock.unlock()

        let records = grepAndParse(projectsDir: projectsDir)

        lock.lock()
        cachedFingerprint = newFingerprint
        cachedRecords = records
        lock.unlock()

        return records
    }

    /// File count + total bytes fingerprint using FileManager stat.
    private func computeFingerprint(projectsDir: URL, fm: FileManager) -> String {
        var totalSize: UInt64 = 0
        var fileCount = 0

        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "0 0"
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            fileCount += 1
            totalSize += UInt64(values.fileSize ?? 0)
        }

        return "\(fileCount) \(totalSize)"
    }

    /// Grep-based parser: only reads lines containing usage data.
    private func grepAndParse(projectsDir: URL) -> [UsageRecord] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", """
            find '\(projectsDir.path)' -name '*.jsonl' 2>/dev/null | while IFS= read -r f; do \
            rel="${f#*/projects/}"; proj="${rel%%/*}"; \
            echo "===CAUDIT_PROJECT:${proj}==="; grep '"input_tokens"' "$f" 2>/dev/null; done; true
        """]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            return []
        }

        return Self.parseGrepOutput(content)
    }

    // MARK: - Grep Output Parser

    static func parseGrepOutput(_ output: String, projectPrefix: String = "", source: String = "Local") -> [UsageRecord] {
        let lines = output.split(separator: "\n")
        var records: [UsageRecord] = []
        records.reserveCapacity(lines.count / 3)
        var currentProject = "unknown"

        for line in lines {
            if line.hasPrefix("===CAUDIT_PROJECT:") && line.hasSuffix("===") {
                let raw = String(line.dropFirst("===CAUDIT_PROJECT:".count).dropLast(3))
                currentProject = readableProjectName(raw)
                continue
            }

            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["type"] as? String == "assistant",
                      let message = json["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                let inputTokens = usage["input_tokens"] as? Int ?? 0
                let outputTokens = usage["output_tokens"] as? Int ?? 0
                let cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0

                var cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
                if let cacheDict = usage["cache_creation"] as? [String: Any] {
                    let ephemeral5m = cacheDict["ephemeral_5m_input_tokens"] as? Int ?? 0
                    let ephemeral1h = cacheDict["ephemeral_1h_input_tokens"] as? Int ?? 0
                    let nested = ephemeral5m + ephemeral1h
                    if nested > cacheCreationTokens { cacheCreationTokens = nested }
                }

                guard inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens > 0 else { return }

                let model = message["model"] as? String ?? json["model"] as? String ?? "unknown"

                let timestamp: Date
                if let ts = json["timestamp"] as? String {
                    timestamp = CauditFormatter.parseISO8601(ts) ?? Date()
                } else {
                    timestamp = Date()
                }

                let pricing = PricingTable.shared.pricing(for: model)
                let cost = pricing.cost(
                    input: inputTokens, output: outputTokens,
                    cacheRead: cacheReadTokens, cacheCreation: cacheCreationTokens
                )

                records.append(UsageRecord(
                    inputTokens: inputTokens, outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens, cacheCreationTokens: cacheCreationTokens,
                    model: model, timestamp: timestamp, cost: cost,
                    project: currentProject, source: source
                ))
            }
        }

        return records
    }

    static func readableProjectName(_ dirName: String) -> String {
        let parts = dirName.split(separator: "-").map(String.init)
        if let last = parts.last, !last.isEmpty { return last }
        return dirName
    }

    static func shortModelName(_ model: String) -> String {
        if model.contains("opus-4-6") { return "Opus 4.6" }
        if model.contains("sonnet-4-5") { return "Sonnet 4.5" }
        if model.contains("sonnet-4") && !model.contains("4-5") { return "Sonnet 4" }
        if model.contains("opus-4") && !model.contains("4-6") { return "Opus 4" }
        if model.contains("haiku-4-5") { return "Haiku 4.5" }
        if model.contains("3-5-sonnet") { return "Sonnet 3.5" }
        if model.contains("3-5-haiku") { return "Haiku 3.5" }
        if model.contains("3-opus") { return "Opus 3" }
        if model.contains("gemini") { return "Gemini" }
        return model
    }

    // MARK: - Aggregation

    func aggregate(records: [UsageRecord], tableTimeRange: TimeRange = .month) -> ParseResult {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday)!

        let tableStart: Date
        switch tableTimeRange {
        case .today: tableStart = startOfToday
        case .week: tableStart = sevenDaysAgo
        case .month: tableStart = startOfMonth
        case .allTime: tableStart = .distantPast
        }

        var today = AggregatedUsage()
        var month = AggregatedUsage()
        var allTime = AggregatedUsage()
        var modelMap: [String: ModelUsageEntry] = [:]
        var dailyMap: [String: DailyUsage] = [:]
        var projectMap: [String: ProjectUsage] = [:]

        let dayFormatter = Self.dayFormatter

        for record in records {
            let entry = AggregatedUsage(
                inputTokens: record.inputTokens,
                outputTokens: record.outputTokens,
                cacheReadTokens: record.cacheReadTokens,
                cacheCreationTokens: record.cacheCreationTokens,
                totalCost: record.cost
            )

            allTime.add(entry)

            if record.timestamp >= startOfMonth {
                month.add(entry)
            }

            if record.timestamp >= startOfToday {
                today.add(entry)
            }

            // Chart: always 7 days, with per-source breakdown
            if record.timestamp >= sevenDaysAgo {
                let dayStart = calendar.startOfDay(for: record.timestamp)
                let key = dayFormatter.string(from: dayStart)
                var day = dailyMap[key] ?? DailyUsage(date: dayStart, dateString: key)
                day.totalCost += record.cost
                day.totalTokens += record.inputTokens + record.outputTokens + record.cacheReadTokens + record.cacheCreationTokens
                day.costBySource[record.source, default: 0] += record.cost
                dailyMap[key] = day
            }

            // Tables: use filter's time range
            if record.timestamp >= tableStart {
                var proj = projectMap[record.project] ?? ProjectUsage(project: record.project, source: record.source)
                proj.totalCost += record.cost
                proj.totalTokens += record.inputTokens + record.outputTokens + record.cacheReadTokens + record.cacheCreationTokens
                proj.sessionCount += 1
                if record.timestamp > proj.lastActive {
                    proj.lastActive = record.timestamp
                }
                projectMap[record.project] = proj

                let shortModel = Self.shortModelName(record.model)
                var modelEntry = modelMap[shortModel] ?? ModelUsageEntry(model: shortModel)
                modelEntry.inputTokens += record.inputTokens
                modelEntry.outputTokens += record.outputTokens
                modelEntry.cacheReadTokens += record.cacheReadTokens
                modelEntry.cacheCreationTokens += record.cacheCreationTokens
                modelEntry.totalCost += record.cost
                modelMap[shortModel] = modelEntry
            }
        }

        var dailyHistory: [DailyUsage] = []
        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday)!
            let key = dayFormatter.string(from: date)
            dailyHistory.append(dailyMap[key] ?? DailyUsage(date: date, dateString: key))
        }

        return ParseResult(
            today: today,
            month: month,
            allTime: allTime,
            modelBreakdown: Array(modelMap.values),
            dailyHistory: dailyHistory,
            projectBreakdown: projectMap.values.sorted { $0.totalCost > $1.totalCost }
        )
    }
}
