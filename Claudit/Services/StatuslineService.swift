import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Statusline")

/// Manages the Claude Code terminal statusline integration.
/// Writes a cache file with current usage data and installs a shell script
/// that reads the cache to display a statusline in the terminal.
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
    private var cachePath: String { claudeDir + "/.statusline-usage-cache" }
    private var scriptPath: String { claudeDir + "/statusline-command.sh" }
    private var configPath: String { claudeDir + "/statusline-config.json" }

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
            installScript()
        } else if !newConfig.enabled && oldEnabled {
            uninstallScript()
        }
    }

    // MARK: - Cache Writing

    /// Write current usage data to the cache file for the shell script to read.
    func updateCache(
        sessionPercent: Double,
        weeklyPercent: Double,
        sessionResetTime: Date?,
        pace: String?
    ) {
        guard currentConfig.enabled else { return }

        let cfg = currentConfig
        var parts: [String] = []

        if cfg.showUsagePercent {
            parts.append("usage=\(Int(sessionPercent))%")
        }

        if cfg.showProgressBar {
            let filled = Int(Double(cfg.barSegments) * min(sessionPercent / 100.0, 1.0))
            let empty = cfg.barSegments - filled
            let bar = String(repeating: "▓", count: filled) + String(repeating: "░", count: empty)
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

    // MARK: - Script Installation

    func installScript() {
        let script = """
        #!/bin/bash
        # Claudit statusline for Claude Code
        # Reads cached usage data and formats it for display.

        CACHE_FILE="\(cachePath)"

        if [ ! -f "$CACHE_FILE" ]; then
            echo "Claudit: no data"
            exit 0
        fi

        # Check if cache is stale (> 10 minutes old)
        if [ "$(uname)" = "Darwin" ]; then
            CACHE_AGE=$(( $(date +%s) - $(stat -f%m "$CACHE_FILE") ))
        else
            CACHE_AGE=$(( $(date +%s) - $(stat -c%Y "$CACHE_FILE") ))
        fi

        if [ "$CACHE_AGE" -gt 600 ]; then
            echo "Claudit: stale"
            exit 0
        fi

        # Read cache values
        USAGE=$(grep '^usage=' "$CACHE_FILE" | cut -d= -f2)
        BAR=$(grep '^bar=' "$CACHE_FILE" | cut -d= -f2)
        RESET=$(grep '^reset=' "$CACHE_FILE" | cut -d= -f2)
        PACE=$(grep '^pace=' "$CACHE_FILE" | cut -d= -f2)
        WEEKLY=$(grep '^weekly=' "$CACHE_FILE" | cut -d= -f2)

        # Build output
        OUTPUT=""
        [ -n "$USAGE" ] && OUTPUT="${OUTPUT}${USAGE}"
        [ -n "$BAR" ] && OUTPUT="${OUTPUT} ${BAR}"
        [ -n "$PACE" ] && OUTPUT="${OUTPUT} ${PACE}"
        [ -n "$RESET" ] && OUTPUT="${OUTPUT} ⏱${RESET}"
        [ -n "$WEEKLY" ] && OUTPUT="${OUTPUT} 7d:${WEEKLY}"

        echo "$OUTPUT"
        """

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
            logger.info("Installed statusline script at \(self.scriptPath)")
        } catch {
            logger.error("Failed to install statusline script: \(error.localizedDescription)")
        }
    }

    func uninstallScript() {
        try? FileManager.default.removeItem(atPath: scriptPath)
        try? FileManager.default.removeItem(atPath: cachePath)
        logger.info("Removed statusline script and cache")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
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

    /// Generate the cache content string (for testing).
    static func formatCacheContent(
        sessionPercent: Double,
        weeklyPercent: Double,
        config: Config
    ) -> String {
        var parts: [String] = []
        if config.showUsagePercent { parts.append("usage=\(Int(sessionPercent))%") }
        if config.showProgressBar {
            parts.append("bar=\(progressBar(percentage: sessionPercent, segments: config.barSegments))")
        }
        parts.append("weekly=\(Int(weeklyPercent))%")
        return parts.joined(separator: "\n")
    }
}
