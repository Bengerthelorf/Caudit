import Foundation
import SwiftUI
import ServiceManagement
import CoreServices
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "AppState")

@Observable @MainActor
final class AppState {
    // MARK: - Usage Data
    var todayUsage = AggregatedUsage()
    var monthUsage = AggregatedUsage()
    var allTimeUsage = AggregatedUsage()
    var modelBreakdown: [ModelUsageEntry] = []
    var dailyHistory: [DailyUsage] = []
    var allTimeDailyHistory: [DailyUsage] = []
    var projectBreakdown: [ProjectUsage] = []
    var sessionBreakdown: [SessionInfo] = []
    var toolBreakdown: [ToolUsageEntry] = []
    var todayHourlyHistory: [DailyUsage] = []
    var dayHourlyBreakdown: [DayHourlyBreakdown] = []
    var isParsingUsage = false

    // MARK: - Navigation State
    var selectedTab: DashboardTab? = .overview
    var selectedSessionForDetail: SessionInfo?
    var projectFilter: String?
    var lastUsageUpdate: Date?
    var availableSources: [String] = []

    var burnRate: Double? {
        guard hasLoadedUsage, todayUsage.totalCost > 0 else { return nil }
        let hoursElapsed = max(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date())) / 3600, 0.5)
        return todayUsage.totalCost / hoursElapsed * 24
    }

    // MARK: - Filter
    var dashboardFilter = DashboardFilter() {
        didSet { recomputeFromFilter() }
    }

    // MARK: - Quota Data
    var quotaInfo: QuotaInfo?
    var isLoadingQuota = false
    var quotaError: String?

    // MARK: - Pace
    var sessionPace: PaceStatus?
    var weeklyPace: PaceStatus?
    var sessionElapsedFraction: Double = 0

    // MARK: - Claude System Status
    var claudeStatus: ClaudeStatus?

    // MARK: - Loading State
    var hasLoadedUsage = false
    var hasLoadedQuota = false

    // MARK: - Remote Devices
    var remoteDevices: [RemoteDevice] = [] {
        didSet {
            guard let data = try? JSONEncoder().encode(remoteDevices) else { return }
            UserDefaults.standard.set(data, forKey: "remoteDevices")
            cleanStaleCaches()
            if hasFinishedInit {
                scheduleRefresh()
            }
        }
    }
    var remoteDeviceStatus: [UUID: RemoteDeviceStatus] = [:]

    // MARK: - Settings
    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode") }
    }

    var launchAtLogin: Bool {
        get {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.warning("Failed to \(newValue ? "register" : "unregister") launch at login: \(error.localizedDescription)")
            }
        }
    }

    var usageRefreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(usageRefreshInterval, forKey: "usageRefreshInterval")
            restartUsageTimer()
        }
    }

    var quotaRefreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(quotaRefreshInterval, forKey: "quotaRefreshInterval")
            restartQuotaTimer()
        }
    }

    var notifyOnQuotaThreshold: Bool {
        didSet { UserDefaults.standard.set(notifyOnQuotaThreshold, forKey: "notifyOnQuotaThreshold") }
    }

    var quotaNotificationThreshold: Double {
        didSet { UserDefaults.standard.set(quotaNotificationThreshold, forKey: "quotaNotificationThreshold") }
    }

    var enabledNotificationThresholds: Set<Int> {
        didSet {
            let array = Array(enabledNotificationThresholds)
            UserDefaults.standard.set(array, forKey: "enabledNotificationThresholds")
        }
    }

    var notifyOnSessionReset: Bool {
        didSet { UserDefaults.standard.set(notifyOnSessionReset, forKey: "notifyOnSessionReset") }
    }

    var notifyOnWeeklyThreshold: Bool {
        didSet { UserDefaults.standard.set(notifyOnWeeklyThreshold, forKey: "notifyOnWeeklyThreshold") }
    }

    // MARK: - Services
    private let usageParser = UsageParser()
    private let quotaService = QuotaService()
    private let notificationService = NotificationService()
    private let remoteUsageService = RemoteUsageService()
    private let claudeStatusService = ClaudeStatusService()

    // MARK: - Private State
    private var allRecords: [UsageRecord] = []
    private var remoteFingerprints: [UUID: String] = [:]
    private var remoteCachedRecords: [UUID: [UsageRecord]] = [:]
    private var usageTimer: Timer?
    private var quotaTimer: Timer?
    private var statusTimer: Timer?
    private var directoryMonitor: DirectoryMonitor?
    private var systemEventService: SystemEventService?
    private var lastUsageRefreshTime: Date?
    private var lastNotifiedQuotaLevel: Double = 0
    private var lastNotifiedWeeklyLevel: Double = 0
    private var hasFinishedInit = false

    init() {
        let defaults = UserDefaults.standard

        if let saved = defaults.string(forKey: "menuBarDisplayMode"),
           let mode = MenuBarDisplayMode(rawValue: saved) {
            self.menuBarDisplayMode = mode
        } else {
            self.menuBarDisplayMode = .cost
        }

        let savedUsageInterval = defaults.double(forKey: "usageRefreshInterval")
        self.usageRefreshInterval = savedUsageInterval > 0 ? savedUsageInterval : 60

        let savedQuotaInterval = defaults.double(forKey: "quotaRefreshInterval")
        self.quotaRefreshInterval = savedQuotaInterval > 0 ? savedQuotaInterval : 120

        self.notifyOnQuotaThreshold = defaults.bool(forKey: "notifyOnQuotaThreshold")

        let savedThreshold = defaults.double(forKey: "quotaNotificationThreshold")
        self.quotaNotificationThreshold = savedThreshold > 0 ? savedThreshold : 80

        if let savedThresholds = defaults.array(forKey: "enabledNotificationThresholds") as? [Int] {
            self.enabledNotificationThresholds = Set(savedThresholds)
        } else {
            self.enabledNotificationThresholds = [75, 90, 95]
        }

        self.notifyOnSessionReset = defaults.bool(forKey: "notifyOnSessionReset")
        self.notifyOnWeeklyThreshold = defaults.bool(forKey: "notifyOnWeeklyThreshold")

        if let data = UserDefaults.standard.data(forKey: "remoteDevices"),
           let devices = try? JSONDecoder().decode([RemoteDevice].self, from: data) {
            self.remoteDevices = devices
        }

        startRefreshing()
        hasFinishedInit = true
    }

    func startRefreshing() {
        refreshUsage(force: true)
        restartUsageTimer()
        setupDirectoryMonitor()
        setupSystemEventService()

        refreshQuota()
        restartQuotaTimer()

        refreshClaudeStatus()
        restartStatusTimer()
    }

    private func restartStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshClaudeStatus() }
        }
    }

    func refreshClaudeStatus() {
        let service = self.claudeStatusService
        Task.detached {
            do {
                let status = try await service.fetchStatus()
                await MainActor.run { [weak self] in
                    self?.claudeStatus = status
                }
            } catch {
                logger.warning("Failed to fetch Claude status: \(error.localizedDescription)")
            }
        }
    }

    private func setupSystemEventService() {
        systemEventService = SystemEventService { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func setupDirectoryMonitor() {
        let claudeDir: String
        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            claudeDir = configDir
        } else {
            claudeDir = NSHomeDirectory() + "/.claude"
        }
        let projectsPath = claudeDir + "/projects"

        directoryMonitor = DirectoryMonitor(path: projectsPath, latency: 5.0) { [weak self] in
            Task { @MainActor in self?.refreshUsage() }
        }
    }

    private func restartUsageTimer() {
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: usageRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshUsage() }
        }
    }

    private func restartQuotaTimer() {
        quotaTimer?.invalidate()
        quotaTimer = Timer.scheduledTimer(withTimeInterval: quotaRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshQuota() }
        }
    }

    func refresh() {
        isParsingUsage = false
        remoteFingerprints.removeAll()
        for device in remoteDevices where device.isEnabled {
            remoteDeviceStatus[device.id] = .fetching
        }
        refreshUsage(force: true)
        refreshQuota()
    }

    private func cleanStaleCaches() {
        let activeIds = Set(remoteDevices.filter(\.isEnabled).map(\.id))
        for id in remoteCachedRecords.keys where !activeIds.contains(id) {
            remoteCachedRecords.removeValue(forKey: id)
            remoteFingerprints.removeValue(forKey: id)
            remoteDeviceStatus.removeValue(forKey: id)
        }
    }

    private func scheduleRefresh() {
        remoteFingerprints.removeAll()
        if isParsingUsage {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.refreshUsage(force: true)
            }
        } else {
            refreshUsage(force: true)
        }
    }

    func refreshUsage(force: Bool = false) {
        guard !isParsingUsage else { return }
        if !force, let last = lastUsageRefreshTime, Date().timeIntervalSince(last) < usageRefreshInterval {
            return
        }
        isParsingUsage = true
        lastUsageRefreshTime = Date()

        let parser = self.usageParser
        let remoteService = self.remoteUsageService
        let enabledDevices = self.remoteDevices.filter { $0.isEnabled }
        let cachedFingerprints = self.remoteFingerprints
        let cachedRecords = self.remoteCachedRecords

        let currentFilter = self.dashboardFilter

        Task.detached {
            let localRecords = parser.scanLocalRecords()
            let allCachedRemote = cachedRecords.values.flatMap { $0 }
            let merged = localRecords + allCachedRemote
            let filtered = Self.applySourceFilter(merged, filter: currentFilter)
            let initialResult = parser.aggregate(records: filtered, tableTimeRange: currentFilter.timeRange)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allRecords = merged
                self.availableSources = Self.computeSources(merged)
                self.applyResult(initialResult)
                self.hasLoadedUsage = true
            }

            if !enabledDevices.isEmpty {
                var updatedFingerprints = cachedFingerprints
                var updatedCachedRecords = cachedRecords
                var anyChanged = false

                await withTaskGroup(of: (RemoteDevice, String?, [UsageRecord]?, Error?).self) { group in
                    for device in enabledDevices {
                        let oldFingerprint = cachedFingerprints[device.id]
                        group.addTask {
                            let newFingerprint = try? await remoteService.fingerprint(for: device)

                            if let newFP = newFingerprint, let oldFP = oldFingerprint, newFP == oldFP {
                                return (device, newFP, nil, nil)
                            }

                            do {
                                let records = try await remoteService.fetchRecords(from: device)
                                return (device, newFingerprint, records, nil)
                            } catch {
                                return (device, newFingerprint, nil, error)
                            }
                        }
                    }

                    for await (device, fingerprint, records, error) in group {
                        if let fingerprint {
                            updatedFingerprints[device.id] = fingerprint
                        }

                        if let records {
                            updatedCachedRecords[device.id] = records
                            anyChanged = true
                            await MainActor.run { [weak self] in
                                self?.remoteDeviceStatus[device.id] = .success(records.count)
                            }
                        } else if let error {
                            await MainActor.run { [weak self] in
                                self?.remoteDeviceStatus[device.id] = .failed(error.localizedDescription)
                            }
                        } else {
                            let count = updatedCachedRecords[device.id]?.count ?? 0
                            await MainActor.run { [weak self] in
                                self?.remoteDeviceStatus[device.id] = .success(count)
                            }
                        }
                    }
                }

                let snapshotFingerprints = updatedFingerprints
                let snapshotCachedRecords = updatedCachedRecords
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.remoteFingerprints = snapshotFingerprints
                    self.remoteCachedRecords = snapshotCachedRecords
                }

                if anyChanged {
                    let allRemote = snapshotCachedRecords.values.flatMap { $0 }
                    let merged = localRecords + allRemote
                    let filtered = Self.applySourceFilter(merged, filter: currentFilter)
                    let mergedResult = parser.aggregate(records: filtered, tableTimeRange: currentFilter.timeRange)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.allRecords = merged
                        self.availableSources = Self.computeSources(merged)
                        self.applyResult(mergedResult)
                    }
                }
            }

            await MainActor.run { [weak self] in
                self?.isParsingUsage = false
            }
        }
    }

    private func applyResult(_ result: ParseResult) {
        todayUsage = result.today
        monthUsage = result.month
        allTimeUsage = result.allTime
        modelBreakdown = result.modelBreakdown.sorted { $0.totalCost > $1.totalCost }
        dailyHistory = result.dailyHistory
        allTimeDailyHistory = result.allTimeDailyHistory
        projectBreakdown = result.projectBreakdown
        sessionBreakdown = result.sessionBreakdown
        toolBreakdown = result.toolBreakdown
        todayHourlyHistory = result.todayHourlyHistory
        dayHourlyBreakdown = result.dayHourlyBreakdown
        lastUsageUpdate = Date()
        NotificationCenter.default.post(name: .clauditDataUpdated, object: nil)
    }

    // MARK: - Filtering

    /// Empty selectedSources means "all selected". Toggling a source when all are
    /// selected deselects just that one; re-selecting all collapses back to empty set.
    func toggleSource(_ source: String) {
        if dashboardFilter.selectedSources.isEmpty {
            var all = Set(availableSources)
            all.remove(source)
            dashboardFilter.selectedSources = all
        } else if dashboardFilter.selectedSources.contains(source) {
            dashboardFilter.selectedSources.remove(source)
        } else {
            dashboardFilter.selectedSources.insert(source)
            if dashboardFilter.selectedSources == Set(availableSources) {
                dashboardFilter.selectedSources = []
            }
        }
    }

    var filteredRecords: [UsageRecord] {
        Self.applySourceFilter(allRecords, filter: dashboardFilter)
    }

    private func recomputeFromFilter() {
        guard !allRecords.isEmpty else { return }
        let filtered = Self.applySourceFilter(allRecords, filter: dashboardFilter)
        let result = usageParser.aggregate(records: filtered, tableTimeRange: dashboardFilter.timeRange)
        applyResult(result)
    }

    private nonisolated static func applySourceFilter(_ records: [UsageRecord], filter: DashboardFilter) -> [UsageRecord] {
        guard !filter.selectedSources.isEmpty else { return records }
        return records.filter { filter.selectedSources.contains($0.source) }
    }

    private nonisolated static func computeSources(_ records: [UsageRecord]) -> [String] {
        var set = Set<String>()
        for r in records { set.insert(r.source) }
        var result = set.sorted()
        if let idx = result.firstIndex(of: "Local") {
            result.remove(at: idx)
            result.insert("Local", at: 0)
        }
        return result
    }

    func refreshQuota() {
        guard !isLoadingQuota else { return }
        isLoadingQuota = true
        quotaError = nil

        let service = self.quotaService
        Task.detached {
            do {
                let info = try await service.fetchQuota()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.quotaInfo = info
                    self.isLoadingQuota = false
                    self.hasLoadedQuota = true
                    self.updatePace(info)
                    self.checkQuotaNotification(info)
                    NotificationCenter.default.post(name: .clauditDataUpdated, object: nil)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.quotaInfo == nil {
                        self.quotaError = error.localizedDescription
                    }
                    self.isLoadingQuota = false
                    self.hasLoadedQuota = true
                }
            }
        }
    }

    private func updatePace(_ quota: QuotaInfo) {
        let fiveHourElapsed = PaceService.fiveHourElapsedFraction(resetAt: quota.fiveHourResetAt)
        sessionElapsedFraction = fiveHourElapsed
        sessionPace = PaceService.calculatePace(usedPercentage: quota.fiveHourUtilization, elapsedFraction: fiveHourElapsed)

        let sevenDayElapsed = PaceService.sevenDayElapsedFraction(resetAt: quota.sevenDayResetAt)
        weeklyPace = PaceService.calculatePace(usedPercentage: quota.sevenDayUtilization, elapsedFraction: sevenDayElapsed)
    }

    private func checkQuotaNotification(_ quota: QuotaInfo) {
        let current = quota.fiveHourUtilization

        // Session reset detection
        if notifyOnSessionReset && NotificationService.isSessionReset(current: current, previousLevel: lastNotifiedQuotaLevel) {
            notificationService.sendSessionResetNotification()
        }

        // Multi-threshold 5h alerts
        if notifyOnQuotaThreshold {
            let thresholds = NotificationService.thresholdsToFire(
                current: current,
                previousLevel: lastNotifiedQuotaLevel,
                enabledThresholds: enabledNotificationThresholds
            )
            for threshold in thresholds {
                notificationService.sendQuotaAlert(percentage: current, threshold: Double(threshold))
            }
        }

        lastNotifiedQuotaLevel = current

        // Weekly threshold alerts
        if notifyOnWeeklyThreshold {
            let weeklyUtilization = quota.sevenDayUtilization
            let weeklyThresholds = NotificationService.thresholdsToFire(
                current: weeklyUtilization,
                previousLevel: lastNotifiedWeeklyLevel,
                enabledThresholds: enabledNotificationThresholds
            )
            for threshold in weeklyThresholds {
                notificationService.sendWeeklyQuotaAlert(percentage: weeklyUtilization, threshold: Double(threshold))
            }
            lastNotifiedWeeklyLevel = weeklyUtilization
        }
    }

    var menuBarText: String {
        guard hasLoadedUsage else { return "--" }
        switch menuBarDisplayMode {
        case .cost:
            return ClauditFormatter.cost(todayUsage.totalCost)
        case .quota:
            if let quota = quotaInfo {
                return "\(Int(quota.fiveHourUtilization))%"
            }
            return "--"
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable {
    case cost = "Today's Cost"
    case quota = "Quota %"
}

// MARK: - FSEvents Directory Monitor

private final class DirectoryMonitor {
    private var stream: FSEventStreamRef?
    private let handler: () -> Void

    init(path: String, latency: TimeInterval, handler: @escaping () -> Void) {
        self.handler = handler
        startStream(path: path, latency: latency)
    }

    private func startStream(path: String, latency: TimeInterval) {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<DirectoryMonitor>.fromOpaque(info).takeUnretainedValue().handler()
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
