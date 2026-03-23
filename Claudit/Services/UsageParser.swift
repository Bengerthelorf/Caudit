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

    private static func discoverOpenClawDirs() -> [(dir: URL, label: String)] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default
        var results: [(URL, String)] = []
        guard let entries = try? fm.contentsOfDirectory(atPath: home.path) else { return [] }
        for entry in entries {
            guard entry.hasPrefix(".openclaw") else { continue }
            let dirURL = home.appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let agentsDir = dirURL.appendingPathComponent("agents")
            guard fm.fileExists(atPath: agentsDir.path) else { continue }

            let suffix = entry.dropFirst(".openclaw".count)
            let label: String
            if suffix.isEmpty {
                label = "OpenClaw"
            } else {
                let clean = suffix.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
                label = "OpenClaw " + clean.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            }
            results.append((agentsDir, label))
        }
        return results
    }

    // MARK: - Local Scanning

    func scanLocalRecords() -> [UsageRecord] {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        let fm = FileManager.default

        let claudeExists = fm.fileExists(atPath: projectsDir.path)
        let openClawDirs = Self.discoverOpenClawDirs()

        guard claudeExists || !openClawDirs.isEmpty else { return [] }

        var fingerParts: [String] = []
        if claudeExists { fingerParts.append(computeFingerprint(dir: projectsDir, fm: fm)) }
        for (agentsDir, _) in openClawDirs {
            fingerParts.append(computeFingerprint(dir: agentsDir, fm: fm))
        }
        let newFingerprint = fingerParts.joined(separator: "|")

        lock.lock()
        if newFingerprint == cachedFingerprint && !cachedRecords.isEmpty {
            let records = cachedRecords
            lock.unlock()
            return records
        }
        lock.unlock()

        var records: [UsageRecord] = []
        if claudeExists { records += nativeScanAndParse(projectsDir: projectsDir) }
        for (agentsDir, label) in openClawDirs {
            records += nativeScanOpenClaw(agentsDir: agentsDir, projectLabel: label)
        }

        lock.lock()
        cachedFingerprint = newFingerprint
        cachedRecords = records
        lock.unlock()

        return records
    }

    private func computeFingerprint(dir: URL, fm: FileManager) -> String {
        var totalSize: UInt64 = 0
        var fileCount = 0

        guard let enumerator = fm.enumerator(
            at: dir,
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

    private func nativeScanAndParse(projectsDir: URL) -> [UsageRecord] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let basePath = projectsDir.path + "/"
        var jsonlFiles: [(path: String, project: String, projectDir: String)] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let fullPath = url.path
            guard fullPath.hasPrefix(basePath) else { continue }
            let rel = String(fullPath.dropFirst(basePath.count))
            let projDir = String(rel.prefix(while: { $0 != "/" }))
            jsonlFiles.append((fullPath, Self.readableProjectName(projDir), projDir))
        }

        var records: [UsageRecord] = []
        records.reserveCapacity(jsonlFiles.count * 50)

        // C-level I/O + strstr pre-filter: avoids loading 200MB+ JSONL files into Swift
        // strings; only lines containing "input_tokens" are parsed as JSON.
        for (filePath, project, projDir) in jsonlFiles {
            guard let file = fopen(filePath, "r") else { continue }
            defer { fclose(file) }

            var linePtr: UnsafeMutablePointer<CChar>? = nil
            var lineCapacity: Int = 0
            defer { free(linePtr) }

            while getline(&linePtr, &lineCapacity, file) > 0 {
                guard let ptr = linePtr else { continue }
                guard strstr(ptr, "\"input_tokens\"") != nil else { continue }

                autoreleasepool {
                    let len = strlen(ptr)
                    let data = Data(bytes: ptr, count: len)

                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
                        timestamp = ClauditFormatter.parseISO8601(ts) ?? Date()
                    } else {
                        timestamp = Date()
                    }

                    let pricing = PricingTable.shared.pricing(for: model)
                    let cost = pricing.cost(
                        input: inputTokens, output: outputTokens,
                        cacheRead: cacheReadTokens, cacheCreation: cacheCreationTokens
                    )

                    let sessionId = json["sessionId"] as? String ?? ""
                    let slug = json["slug"] as? String ?? ""

                    var toolNames: [String] = []
                    if let contentArray = message["content"] as? [[String: Any]] {
                        for item in contentArray {
                            if item["type"] as? String == "tool_use",
                               let name = item["name"] as? String {
                                toolNames.append(name)
                            }
                        }
                    }

                    records.append(UsageRecord(
                        inputTokens: inputTokens, outputTokens: outputTokens,
                        cacheReadTokens: cacheReadTokens, cacheCreationTokens: cacheCreationTokens,
                        model: model, timestamp: timestamp, cost: cost,
                        project: project, source: "Local",
                        sessionId: sessionId, slug: slug,
                        toolCalls: toolNames, projectDir: projDir
                    ))
                }
            }
        }

        return records
    }

    private func nativeScanOpenClaw(agentsDir: URL, projectLabel: String = "OpenClaw") -> [UsageRecord] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: agentsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var jsonlFiles: [(path: String, sessionId: String)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let sessionId = url.deletingPathExtension().lastPathComponent
            jsonlFiles.append((url.path, sessionId))
        }

        var records: [UsageRecord] = []
        records.reserveCapacity(jsonlFiles.count * 20)

        for (filePath, fileSessionId) in jsonlFiles {
            guard let file = fopen(filePath, "r") else { continue }
            defer { fclose(file) }

            var linePtr: UnsafeMutablePointer<CChar>? = nil
            var lineCapacity: Int = 0
            defer { free(linePtr) }

            while getline(&linePtr, &lineCapacity, file) > 0 {
                guard let ptr = linePtr else { continue }
                guard strstr(ptr, "\"usage\"") != nil else { continue }

                autoreleasepool {
                    let len = strlen(ptr)
                    let data = Data(bytes: ptr, count: len)

                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          json["type"] as? String == "message",
                          let message = json["message"] as? [String: Any],
                          message["role"] as? String == "assistant",
                          let usage = message["usage"] as? [String: Any] else {
                        return
                    }

                    let inputTokens = usage["input"] as? Int ?? 0
                    let outputTokens = usage["output"] as? Int ?? 0
                    let cacheReadTokens = usage["cacheRead"] as? Int ?? 0
                    let cacheCreationTokens = usage["cacheWrite"] as? Int ?? 0

                    guard inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens > 0 else { return }

                    let model = message["model"] as? String ?? "unknown"

                    let timestamp: Date
                    if let ts = json["timestamp"] as? String {
                        timestamp = ClauditFormatter.parseISO8601(ts) ?? Date()
                    } else {
                        timestamp = Date()
                    }

                    let pricing = PricingTable.shared.pricing(for: model)
                    let cost = pricing.cost(
                        input: inputTokens, output: outputTokens,
                        cacheRead: cacheReadTokens, cacheCreation: cacheCreationTokens
                    )

                    var toolNames: [String] = []
                    if let contentArray = message["content"] as? [[String: Any]] {
                        for item in contentArray {
                            let itemType = item["type"] as? String
                            if (itemType == "tool_use" || itemType == "toolCall"),
                               let name = item["name"] as? String {
                                toolNames.append(name)
                            }
                        }
                    }

                    records.append(UsageRecord(
                        inputTokens: inputTokens, outputTokens: outputTokens,
                        cacheReadTokens: cacheReadTokens, cacheCreationTokens: cacheCreationTokens,
                        model: model, timestamp: timestamp, cost: cost,
                        project: projectLabel, source: "Local",
                        sessionId: fileSessionId, slug: "",
                        toolCalls: toolNames, projectDir: projectLabel
                    ))
                }
            }
        }

        return records
    }

    // MARK: - Grep Output Parser

    static func parseGrepOutput(_ output: String, projectPrefix: String = "", source: String = "Local") -> [UsageRecord] {
        let lines = output.split(separator: "\n")
        var records: [UsageRecord] = []
        records.reserveCapacity(lines.count / 3)
        var currentProject = "unknown"
        var currentProjectDir = ""
        var currentOCSessionId = ""

        for line in lines {
            if line.hasPrefix("===CAUDIT_PROJECT:") && line.hasSuffix("===") {
                let raw = String(line.dropFirst("===CAUDIT_PROJECT:".count).dropLast(3))
                currentProject = readableProjectName(raw)
                currentProjectDir = raw
                currentOCSessionId = ""
                continue
            }

            if line.hasPrefix("===CAUDIT_OC:") && line.hasSuffix("===") {
                let payload = String(line.dropFirst("===CAUDIT_OC:".count).dropLast(3))
                if let slashIdx = payload.firstIndex(of: "/") {
                    let dirName = String(payload[payload.startIndex..<slashIdx])
                    currentOCSessionId = String(payload[payload.index(after: slashIdx)...])
                    let suffix = dirName.dropFirst(".openclaw".count)
                    if suffix.isEmpty {
                        currentProject = "OpenClaw"
                    } else {
                        let clean = suffix.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
                        currentProject = "OpenClaw " + clean.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                    }
                } else {
                    currentOCSessionId = payload
                    currentProject = "OpenClaw"
                }
                currentProjectDir = currentProject
                continue
            }

            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let message = json["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                let type = json["type"] as? String
                let role = message["role"] as? String
                guard type == "assistant" || (type == "message" && role == "assistant") else { return }

                let inputTokens = (usage["input_tokens"] as? Int) ?? (usage["input"] as? Int) ?? 0
                let outputTokens = (usage["output_tokens"] as? Int) ?? (usage["output"] as? Int) ?? 0
                let cacheReadTokens = (usage["cache_read_input_tokens"] as? Int) ?? (usage["cacheRead"] as? Int) ?? 0

                var cacheCreationTokens = (usage["cache_creation_input_tokens"] as? Int) ?? (usage["cacheWrite"] as? Int) ?? 0
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
                    timestamp = ClauditFormatter.parseISO8601(ts) ?? Date()
                } else {
                    timestamp = Date()
                }

                let pricing = PricingTable.shared.pricing(for: model)
                let cost = pricing.cost(
                    input: inputTokens, output: outputTokens,
                    cacheRead: cacheReadTokens, cacheCreation: cacheCreationTokens
                )

                let sessionId = json["sessionId"] as? String ?? currentOCSessionId
                let slug = json["slug"] as? String ?? ""

                var toolNames: [String] = []
                if let contentArray = message["content"] as? [[String: Any]] {
                    for item in contentArray {
                        let itemType = item["type"] as? String
                        if (itemType == "tool_use" || itemType == "toolCall"),
                           let name = item["name"] as? String {
                            toolNames.append(name)
                        }
                    }
                }

                records.append(UsageRecord(
                    inputTokens: inputTokens, outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens, cacheCreationTokens: cacheCreationTokens,
                    model: model, timestamp: timestamp, cost: cost,
                    project: currentProject, source: source,
                    sessionId: sessionId, slug: slug,
                    toolCalls: toolNames, projectDir: currentProjectDir
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

        let tableStart = tableTimeRange.filterStart

        var today = AggregatedUsage()
        var month = AggregatedUsage()
        var allTime = AggregatedUsage()
        var modelMap: [String: ModelUsageEntry] = [:]
        var dailyMap: [String: DailyUsage] = [:]
        var allTimeDailyMap: [Int: DailyUsage] = [:]
        var hourlyMap: [Int: DailyUsage] = [:]
        var projectMap: [String: ProjectUsage] = [:]
        var projectSessionSets: [String: Set<String>] = [:]
        var sessionMap: [String: SessionInfo] = [:]
        var toolMap: [String: Int] = [:]
        var dayHourMap: [Int: (date: Date, slots: [Double])] = [:]

        let dayFormatter = Self.dayFormatter

        for record in records {
            let tokens = record.inputTokens + record.outputTokens + record.cacheReadTokens + record.cacheCreationTokens
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

                let hour = calendar.component(.hour, from: record.timestamp)
                let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfToday) ?? record.timestamp
                var hourEntry = hourlyMap[hour] ?? DailyUsage(date: hourDate, dateString: String(format: "%d:00", hour))
                hourEntry.totalCost += record.cost
                hourEntry.totalTokens += tokens
                hourEntry.costBySource[record.source, default: 0] += record.cost
                hourlyMap[hour] = hourEntry
            }

            let dayStart = calendar.startOfDay(for: record.timestamp)
            let key = dayFormatter.string(from: dayStart)
            let julianDay = calendar.ordinality(of: .day, in: .era, for: dayStart) ?? 0

            var allDay = allTimeDailyMap[julianDay] ?? DailyUsage(date: dayStart, dateString: key)
            allDay.totalCost += record.cost
            allDay.totalTokens += tokens
            allDay.costBySource[record.source, default: 0] += record.cost
            allTimeDailyMap[julianDay] = allDay

            let hourOfDay = calendar.component(.hour, from: record.timestamp)
            let slot = hourOfDay / 6
            if dayHourMap[julianDay] == nil {
                dayHourMap[julianDay] = (date: dayStart, slots: Array(repeating: 0, count: 4))
            }
            dayHourMap[julianDay]!.slots[slot] += record.cost

            if record.timestamp >= sevenDaysAgo {
                var day = dailyMap[key] ?? DailyUsage(date: dayStart, dateString: key)
                day.totalCost += record.cost
                day.totalTokens += tokens
                day.costBySource[record.source, default: 0] += record.cost
                dailyMap[key] = day
            }

            if record.timestamp >= tableStart {
                var proj = projectMap[record.project] ?? ProjectUsage(project: record.project, source: record.source)
                proj.totalCost += record.cost
                proj.totalTokens += tokens
                if !record.sessionId.isEmpty {
                    projectSessionSets[record.project, default: []].insert(record.sessionId)
                }
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

                if !record.sessionId.isEmpty {
                    var session = sessionMap[record.sessionId] ?? SessionInfo(
                        sessionId: record.sessionId,
                        slug: record.slug,
                        project: record.project,
                        projectDir: record.projectDir,
                        source: record.source,
                        firstTimestamp: record.timestamp,
                        lastTimestamp: record.timestamp
                    )
                    session.messageCount += 1
                    session.totalTokens += tokens
                    session.totalCost += record.cost
                    if record.timestamp < session.firstTimestamp {
                        session.firstTimestamp = record.timestamp
                    }
                    if record.timestamp > session.lastTimestamp {
                        session.lastTimestamp = record.timestamp
                    }
                    sessionMap[record.sessionId] = session
                }

                for toolName in record.toolCalls {
                    toolMap[toolName, default: 0] += 1
                }
            }
        }

        var dailyHistory: [DailyUsage] = []
        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday)!
            let key = dayFormatter.string(from: date)
            dailyHistory.append(dailyMap[key] ?? DailyUsage(date: date, dateString: key))
        }

        var todayHourlyHistory: [DailyUsage] = []
        for hour in 0..<24 {
            let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfToday) ?? startOfToday
            todayHourlyHistory.append(hourlyMap[hour] ?? DailyUsage(date: hourDate, dateString: String(format: "%d:00", hour)))
        }

        let dayHourlyBreakdown = dayHourMap.map { (key, value) in
            DayHourlyBreakdown(date: value.date, slotCosts: value.slots)
        }.sorted { $0.date < $1.date }

        var finalProjects = Array(projectMap.values)
        for i in finalProjects.indices {
            finalProjects[i].sessionCount = projectSessionSets[finalProjects[i].project]?.count ?? 0
        }

        return ParseResult(
            today: today,
            month: month,
            allTime: allTime,
            modelBreakdown: Array(modelMap.values),
            dailyHistory: dailyHistory,
            projectBreakdown: finalProjects.sorted { $0.totalCost > $1.totalCost },
            sessionBreakdown: sessionMap.values.sorted { $0.lastTimestamp > $1.lastTimestamp },
            toolBreakdown: toolMap.map { ToolUsageEntry(name: $0.key, usageCount: $0.value) }
                .sorted { $0.usageCount > $1.usageCount },
            allTimeDailyHistory: allTimeDailyMap.values.sorted { $0.date < $1.date },
            todayHourlyHistory: todayHourlyHistory,
            dayHourlyBreakdown: dayHourlyBreakdown
        )
    }
}
