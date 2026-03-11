import Foundation
import SwiftUI
import ServiceManagement
import CoreServices

@Observable
final class AppState {
    // MARK: - Usage Data
    var todayUsage = AggregatedUsage()
    var monthUsage = AggregatedUsage()
    var allTimeUsage = AggregatedUsage()
    var modelBreakdown: [ModelUsageEntry] = []
    var dailyHistory: [DailyUsage] = []
    var projectBreakdown: [ProjectUsage] = []
    var sessionBreakdown: [SessionInfo] = []
    var toolBreakdown: [ToolUsageEntry] = []
    var isParsingUsage = false
    var lastUsageUpdate: Date?
    var availableSources: [String] = []
    var heatmapData: [HeatmapEntry] = (0..<7).flatMap { day in
        (0..<24).map { hour in HeatmapEntry(dayOfWeek: day, hour: hour) }
    }

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

    // MARK: - Loading State
    var hasLoadedUsage = false
    var hasLoadedQuota = false

    // MARK: - Remote Devices
    var remoteDevices: [RemoteDevice] = [] {
        didSet {
            guard let data = try? JSONEncoder().encode(remoteDevices) else { return }
            UserDefaults.standard.set(data, forKey: "remoteDevices")
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
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
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

    // MARK: - Services
    private var usageParser: UsageParser?
    private var quotaService: QuotaService?
    private var notificationService: NotificationService?
    private var remoteUsageService: RemoteUsageService?

    // MARK: - Private State
    private var allRecords: [UsageRecord] = []
    private var remoteFingerprints: [UUID: String] = [:]
    private var remoteCachedRecords: [UUID: [UsageRecord]] = [:]
    private var usageTimer: Timer?
    private var quotaTimer: Timer?
    private var directoryMonitor: DirectoryMonitor?
    private var lastUsageRefreshTime: Date?
    private var lastNotifiedQuotaLevel: Double = 0
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

        self.usageParser = UsageParser()
        self.quotaService = QuotaService()
        self.notificationService = NotificationService()
        self.remoteUsageService = RemoteUsageService()

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

        refreshQuota()
        restartQuotaTimer()
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
            DispatchQueue.main.async {
                self?.refreshUsage()
            }
        }
    }

    private func restartUsageTimer() {
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: usageRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    private func restartQuotaTimer() {
        quotaTimer?.invalidate()
        quotaTimer = Timer.scheduledTimer(withTimeInterval: quotaRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshQuota()
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

    private func scheduleRefresh() {
        remoteFingerprints.removeAll()
        if isParsingUsage {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
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
        let enabledDevices = self.remoteDevices.filter(\.isEnabled)
        let cachedFingerprints = self.remoteFingerprints
        let cachedRecords = self.remoteCachedRecords

        let currentFilter = self.dashboardFilter

        Task.detached {
            guard let parser else {
                await MainActor.run { [weak self] in self?.isParsingUsage = false }
                return
            }

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

            if let remoteService, !enabledDevices.isEmpty {
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
        projectBreakdown = result.projectBreakdown
        sessionBreakdown = result.sessionBreakdown
        toolBreakdown = result.toolBreakdown
        lastUsageUpdate = Date()
        recomputeHeatmap()
        NotificationCenter.default.post(name: .cauditDataUpdated, object: nil)
    }

    private func recomputeHeatmap() {
        let sourceFiltered: [UsageRecord]
        if dashboardFilter.selectedSources.isEmpty {
            sourceFiltered = allRecords
        } else {
            sourceFiltered = allRecords.filter { dashboardFilter.selectedSources.contains($0.source) }
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let tableStart: Date
        switch dashboardFilter.timeRange {
        case .today: tableStart = startOfToday
        case .week: tableStart = calendar.date(byAdding: .day, value: -6, to: startOfToday)!
        case .month: tableStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        case .allTime: tableStart = .distantPast
        }

        var counts = [(Int, Double)](repeating: (0, 0.0), count: 168)

        for record in sourceFiltered where record.timestamp >= tableStart {
            let weekday = calendar.component(.weekday, from: record.timestamp) - 1
            let hour = calendar.component(.hour, from: record.timestamp)
            let idx = weekday * 24 + hour
            counts[idx].0 += 1
            counts[idx].1 += record.cost
        }

        heatmapData = (0..<7).flatMap { day in
            (0..<24).map { hour in
                let idx = day * 24 + hour
                return HeatmapEntry(
                    dayOfWeek: day, hour: hour,
                    messageCount: counts[idx].0, totalCost: counts[idx].1
                )
            }
        }
    }

    // MARK: - Filtering

    func toggleSource(_ source: String) {
        if dashboardFilter.selectedSources.isEmpty {
            // All visible → hide this one
            var all = Set(availableSources)
            all.remove(source)
            dashboardFilter.selectedSources = all
        } else if dashboardFilter.selectedSources.contains(source) {
            dashboardFilter.selectedSources.remove(source)
            // If none left → reset to show all
        } else {
            dashboardFilter.selectedSources.insert(source)
            if dashboardFilter.selectedSources == Set(availableSources) {
                dashboardFilter.selectedSources = []
            }
        }
    }

    private func recomputeFromFilter() {
        guard let parser = usageParser, !allRecords.isEmpty else { return }
        let filtered = Self.applySourceFilter(allRecords, filter: dashboardFilter)
        let result = parser.aggregate(records: filtered, tableTimeRange: dashboardFilter.timeRange)
        applyResult(result)
    }

    private static func applySourceFilter(_ records: [UsageRecord], filter: DashboardFilter) -> [UsageRecord] {
        guard !filter.selectedSources.isEmpty else { return records }
        return records.filter { filter.selectedSources.contains($0.source) }
    }

    private static func computeSources(_ records: [UsageRecord]) -> [String] {
        var set = Set<String>()
        for r in records { set.insert(r.source) }
        var result = set.sorted()
        // Put "Local" first
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
            guard let service else { return }
            do {
                let info = try await service.fetchQuota()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.quotaInfo = info
                    self.isLoadingQuota = false
                    self.hasLoadedQuota = true
                    self.checkQuotaNotification(info)
                    NotificationCenter.default.post(name: .cauditDataUpdated, object: nil)
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

    private func checkQuotaNotification(_ quota: QuotaInfo) {
        guard notifyOnQuotaThreshold else { return }
        let threshold = quotaNotificationThreshold
        let current = quota.fiveHourUtilization

        if current >= threshold && lastNotifiedQuotaLevel < threshold {
            notificationService?.sendQuotaAlert(percentage: current, threshold: threshold)
        }
        lastNotifiedQuotaLevel = current
    }

    var menuBarText: String {
        guard hasLoadedUsage else { return "--" }
        switch menuBarDisplayMode {
        case .cost:
            return CauditFormatter.cost(todayUsage.totalCost)
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
