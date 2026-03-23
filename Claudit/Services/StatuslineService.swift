import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Statusline")

/// Writes a cache file with current quota data that external statusline scripts can read.
///
/// Cache format (key=value, one per line):
///   session=<int>          5-hour window usage percentage (0-100+)
///   weekly=<int>           7-day window usage percentage (0-100+)
///   reset=<ISO8601>        5-hour window reset time (ISO 8601, omitted if unknown)
///   pace=<string>          Pace label (Comfortable/On Track/Warming/Pressing/Critical/Runaway, omitted if too early)
///   updated=<unix>         Cache write timestamp (Unix epoch seconds)
final class StatuslineService: @unchecked Sendable {

    private let lock = NSLock()
    private var _enabled: Bool

    private var claudeDir: String {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() + "/.claude")
    }
    var cachePath: String { claudeDir + "/.statusline-usage-cache" }

    /// Called by AppState to trigger an immediate cache write when enabled.
    var onEnabled: (() -> Void)?

    init() {
        self._enabled = UserDefaults.standard.bool(forKey: "statuslineCacheEnabled")
    }

    // MARK: - Enable/Disable

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _enabled
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        let wasEnabled = _enabled
        _enabled = enabled
        lock.unlock()

        UserDefaults.standard.set(enabled, forKey: "statuslineCacheEnabled")

        if enabled && !wasEnabled {
            onEnabled?()
        } else if !enabled && wasEnabled {
            try? FileManager.default.removeItem(atPath: cachePath)
        }
    }

    // MARK: - Cache Writing

    /// Write all quota data to the cache file. Always writes all available fields.
    func updateCache(
        sessionPercent: Double,
        weeklyPercent: Double,
        sessionResetTime: Date?,
        pace: String?
    ) {
        guard isEnabled else { return }

        var lines: [String] = []
        lines.append("session=\(Int(sessionPercent))")
        lines.append("weekly=\(Int(weeklyPercent))")

        if let resetTime = sessionResetTime {
            lines.append("reset=\(ClauditFormatter.formatISO8601(resetTime))")
        }

        if let pace {
            lines.append("pace=\(pace)")
        }

        lines.append("updated=\(Int(Date().timeIntervalSince1970))")

        let content = lines.joined(separator: "\n") + "\n"

        do {
            try content.write(toFile: cachePath, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("Failed to write statusline cache: \(error.localizedDescription)")
        }
    }

    var cacheExists: Bool {
        FileManager.default.fileExists(atPath: cachePath)
    }

    // MARK: - Static Helpers

    /// Generate a progress bar string for a given percentage.
    static func progressBar(percentage: Double, segments: Int = 10) -> String {
        let filled = Int(Double(segments) * min(max(percentage / 100.0, 0), 1.0))
        let empty = segments - filled
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: empty)
    }
}
