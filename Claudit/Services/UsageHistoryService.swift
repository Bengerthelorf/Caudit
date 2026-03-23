import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "UsageHistory")

/// Records periodic usage snapshots and persists them to disk.
final class UsageHistoryService: @unchecked Sendable {
    static let maxSessionSnapshots = 1000  // ~7 days at 10-min intervals
    static let maxWeeklySnapshots = 500    // ~6 weeks at 2-hour intervals

    private let lock = NSLock()
    private var sessionSnapshots: [UsageSnapshot] = []
    private var weeklySnapshots: [UsageSnapshot] = []
    private var lastSessionRecordTime: Date = .distantPast
    private var lastWeeklyRecordTime: Date = .distantPast

    private let sessionInterval: TimeInterval = 600  // 10 minutes
    private let weeklyInterval: TimeInterval = 7200  // 2 hours

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Claudit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("usage-history.json")
        loadFromDisk()
    }

    /// Record a snapshot if enough time has passed since the last one.
    func recordIfNeeded(sessionPercentage: Double, weeklyPercentage: Double) {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }

        if now.timeIntervalSince(lastSessionRecordTime) >= sessionInterval {
            let snapshot = UsageSnapshot(timestamp: now, type: .session, percentage: sessionPercentage)
            sessionSnapshots.append(snapshot)
            if sessionSnapshots.count > Self.maxSessionSnapshots {
                sessionSnapshots.removeFirst(sessionSnapshots.count - Self.maxSessionSnapshots)
            }
            lastSessionRecordTime = now
        }

        if now.timeIntervalSince(lastWeeklyRecordTime) >= weeklyInterval {
            let snapshot = UsageSnapshot(timestamp: now, type: .weekly, percentage: weeklyPercentage)
            weeklySnapshots.append(snapshot)
            if weeklySnapshots.count > Self.maxWeeklySnapshots {
                weeklySnapshots.removeFirst(weeklySnapshots.count - Self.maxWeeklySnapshots)
            }
            lastWeeklyRecordTime = now
        }

        saveToDisk()
    }

    /// Get all snapshots of a given type within a time range.
    func snapshots(type: SnapshotType, from start: Date, to end: Date = Date()) -> [UsageSnapshot] {
        lock.lock()
        let source = type == .session ? sessionSnapshots : weeklySnapshots
        lock.unlock()
        return source.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// Get all session snapshots.
    func allSessionSnapshots() -> [UsageSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return sessionSnapshots
    }

    /// Get all weekly snapshots.
    func allWeeklySnapshots() -> [UsageSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return weeklySnapshots
    }

    // MARK: - Persistence

    private struct StorageContainer: Codable {
        var sessionSnapshots: [UsageSnapshot]
        var weeklySnapshots: [UsageSnapshot]
    }

    private func saveToDisk() {
        let container = StorageContainer(sessionSnapshots: sessionSnapshots, weeklySnapshots: weeklySnapshots)
        do {
            let data = try JSONEncoder().encode(container)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.warning("Failed to save usage history: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let container = try? JSONDecoder().decode(StorageContainer.self, from: data) else { return }
        sessionSnapshots = container.sessionSnapshots
        weeklySnapshots = container.weeklySnapshots
        lastSessionRecordTime = sessionSnapshots.last?.timestamp ?? .distantPast
        lastWeeklyRecordTime = weeklySnapshots.last?.timestamp ?? .distantPast
        logger.info("Loaded \(self.sessionSnapshots.count) session + \(self.weeklySnapshots.count) weekly snapshots")
    }
}
