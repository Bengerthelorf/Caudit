import AppKit
import Network
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "SystemEvent")

/// Monitors system sleep/wake and network connectivity changes, triggering a refresh callback with debounce.
final class SystemEventService: @unchecked Sendable {
    private let debounceInterval: TimeInterval
    private let onRefresh: @Sendable () -> Void

    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "cc.ffitch.Claudit.networkMonitor")

    private let lock = NSLock()
    private var lastTriggerTime: Date = .distantPast
    private var wasNetworkSatisfied = true

    init(debounceInterval: TimeInterval = 10, onRefresh: @escaping @Sendable () -> Void) {
        self.debounceInterval = debounceInterval
        self.onRefresh = onRefresh

        setupWakeObserver()
        setupNetworkMonitor()
    }

    deinit {
        networkMonitor.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Sleep/Wake

    private func setupWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        logger.info("System woke from sleep")
        triggerRefreshIfNeeded()
    }

    // MARK: - Network

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied

            lock.lock()
            let wasSatisfied = wasNetworkSatisfied
            wasNetworkSatisfied = satisfied
            lock.unlock()

            if satisfied && !wasSatisfied {
                logger.info("Network connectivity restored")
                triggerRefreshIfNeeded()
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Debounce

    func triggerRefreshIfNeeded() {
        let now = Date()
        lock.lock()
        let elapsed = now.timeIntervalSince(lastTriggerTime)
        if elapsed < debounceInterval {
            lock.unlock()
            logger.debug("Refresh debounced (\(String(format: "%.1f", elapsed))s since last)")
            return
        }
        lastTriggerTime = now
        lock.unlock()

        onRefresh()
    }
}
