import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Statusline")

/// Writes a cache file with current quota data that external statusline scripts can read.
/// Does NOT install or modify any user scripts — it only provides data.
final class StatuslineService: @unchecked Sendable {

    struct Config: Codable, Equatable {
        var enabled: Bool = false
        var showUsagePercent: Bool = true
        var showProgressBar: Bool = true
        var showResetTime: Bool = true
        var showPaceLabel: Bool = true
        var use24HourTime: Bool = true
        var barSegments: Int = 10
    }

    private let lock = NSLock()
    private var config: Config

    private var claudeDir: String {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() + "/.claude")
    }
    var cachePath: String { claudeDir + "/.statusline-usage-cache" }

    /// Callback to trigger an immediate cache write after enabling. Set by AppState.
    var onEnabled: (() -> Void)?

    init() {
        self.config = Self.loadConfig()
    }

    // MARK: - Config Management

    var currentConfig: Config {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    func updateConfig(_ newConfig: Config) {
        lock.lock()
        let oldEnabled = config.enabled
        config = newConfig
        lock.unlock()

        saveConfig(newConfig)

        if newConfig.enabled && !oldEnabled {
            onEnabled?()
        } else if !newConfig.enabled && oldEnabled {
            // Clean up cache file when disabled
            try? FileManager.default.removeItem(atPath: cachePath)
        }
    }

    // MARK: - Cache Writing

    /// Write current usage data to the cache file for external scripts to read.
    func updateCache(
        sessionPercent: Double,
        weeklyPercent: Double,
        sessionResetTime: Date?,
        pace: String?
    ) {
        lock.lock()
        let cfg = config
        lock.unlock()

        guard cfg.enabled else { return }
        var parts: [String] = []

        if cfg.showUsagePercent {
            parts.append("usage=\(Int(sessionPercent))%")
        }

        if cfg.showProgressBar {
            let bar = Self.progressBar(percentage: sessionPercent, segments: cfg.barSegments)
            parts.append("bar=\(bar)")
        }

        if cfg.showResetTime, let resetTime = sessionResetTime {
            let formatter = DateFormatter()
            formatter.dateFormat = cfg.use24HourTime ? "HH:mm" : "h:mma"
            parts.append("reset=\(formatter.string(from: resetTime))")
        }

        if cfg.showPaceLabel, let pace {
            parts.append("pace=\(pace)")
        }

        parts.append("weekly=\(Int(weeklyPercent))%")
        parts.append("updated=\(Int(Date().timeIntervalSince1970))")

        let content = parts.joined(separator: "\n") + "\n"

        do {
            try content.write(toFile: cachePath, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("Failed to write statusline cache: \(error.localizedDescription)")
        }
    }

    var cacheExists: Bool {
        FileManager.default.fileExists(atPath: cachePath)
    }

    // MARK: - Config Persistence

    private func saveConfig(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: "statuslineConfig")
    }

    private static func loadConfig() -> Config {
        guard let data = UserDefaults.standard.data(forKey: "statuslineConfig"),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return config
    }

    // MARK: - Static Helpers

    /// Generate the progress bar string for a given percentage.
    static func progressBar(percentage: Double, segments: Int = 10) -> String {
        let filled = Int(Double(segments) * min(max(percentage / 100.0, 0), 1.0))
        let empty = segments - filled
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: empty)
    }

    /// Generate a preview string showing all enabled components.
    static func formatCacheContent(
        sessionPercent: Double,
        weeklyPercent: Double,
        config: Config
    ) -> String {
        var parts: [String] = []
        if config.showUsagePercent { parts.append("\(Int(sessionPercent))%") }
        if config.showProgressBar {
            parts.append(progressBar(percentage: sessionPercent, segments: config.barSegments))
        }
        if config.showPaceLabel { parts.append("On Track") }
        if config.showResetTime {
            let timeStr = config.use24HourTime ? "14:30" : "2:30PM"
            parts.append("⏱\(timeStr)")
        }
        parts.append("7d:\(Int(weeklyPercent))%")
        return parts.joined(separator: " ")
    }
}
