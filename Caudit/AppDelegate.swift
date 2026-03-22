import AppKit
import SwiftUI
import Sparkle

extension Notification.Name {
    static let showDashboard = Notification.Name("showDashboard")
    static let cauditDataUpdated = Notification.Name("cauditDataUpdated")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let appState = AppState()
    let updaterController: SPUStandardUpdaterController
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?
    private var settingsCloseObserver: Any?
    private var dashboardWindow: NSWindow?
    private var dashboardCloseObserver: Any?
    private var sessionWindows: Set<NSWindow> = []
    private var sessionCloseObservers: [NSWindow: Any] = [:]

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupMainMenu()

        NotificationCenter.default.addObserver(
            self, selector: #selector(showDashboard),
            name: .showDashboard, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDataUpdated),
            name: .cauditDataUpdated, object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventMonitor()
        if let obs = settingsCloseObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = dashboardCloseObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        for obs in sessionCloseObservers.values {
            NotificationCenter.default.removeObserver(obs)
        }
        sessionCloseObservers.removeAll()
    }

    @objc private func handleDataUpdated() {
        updateStatusItemText()
    }

    // MARK: - Settings

    func showSettings() {
        if let window = settingsWindow {
            activateApp(window: window)
            return
        }

        let window = makeWindow(
            title: "Caudit Settings",
            size: NSSize(width: 680, height: 480),
            minSize: NSSize(width: 560, height: 400),
            rootView: SettingsView(updater: updaterController.updater)
        )

        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                if let w = notification.object as? NSWindow { self?.windowDelegates.removeValue(forKey: w) }
                self?.settingsWindow = nil
                if let obs = self?.settingsCloseObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self?.settingsCloseObserver = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.revertToAccessoryIfNeeded()
                }
            }
        }

        self.settingsWindow = window
        activateApp(window: window)
    }

    // MARK: - Dashboard

    @objc func showDashboard() {
        if let window = dashboardWindow {
            activateApp(window: window)
            return
        }

        let window = makeWindow(
            title: "Caudit",
            size: NSSize(width: 820, height: 600),
            minSize: NSSize(width: 720, height: 580),
            maxSize: NSSize(width: 960, height: CGFloat.greatestFiniteMagnitude),
            rootView: DashboardView()
        )

        dashboardCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                if let w = notification.object as? NSWindow { self?.windowDelegates.removeValue(forKey: w) }
                self?.dashboardWindow = nil
                if let obs = self?.dashboardCloseObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self?.dashboardCloseObserver = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.revertToAccessoryIfNeeded()
                }
            }
        }

        self.dashboardWindow = window
        activateApp(window: window)
    }

    // MARK: - Session Detail Window

    func openSessionWindow(session: SessionInfo) {
        let window = makeWindow(
            title: session.displayName,
            size: NSSize(width: 700, height: 550),
            minSize: NSSize(width: 500, height: 400),
            rootView: SessionReaderView(session: session)
        )

        sessionWindows.insert(window)
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                self?.windowDelegates.removeValue(forKey: window)
                if let obs = self?.sessionCloseObservers.removeValue(forKey: window) {
                    NotificationCenter.default.removeObserver(obs)
                }
                self?.sessionWindows.remove(window)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.revertToAccessoryIfNeeded()
                }
            }
        }
        sessionCloseObservers[window] = observer

        activateApp(window: window)
    }

    // MARK: - Window Factory

    private var windowDelegates: [NSWindow: WindowSizeDelegate] = [:]

    private func makeWindow(
        title: String,
        size: NSSize,
        minSize: NSSize,
        maxSize: NSSize? = nil,
        rootView: some View,
        toolbar: Bool = true
    ) -> NSWindow {
        let controller = NSHostingController(
            rootView: rootView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(appState)
        )
        controller.sizingOptions = []

        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.collectionBehavior = [.fullScreenNone, .managed]
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .none

        if toolbar {
            let tb = NSToolbar(identifier: "\(title)Toolbar")
            tb.displayMode = .iconOnly
            window.toolbar = tb
            window.toolbarStyle = .unified
        }

        window.setContentSize(size)

        let effectiveMax = maxSize ?? NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let sizeDelegate = WindowSizeDelegate(minSize: minSize, maxSize: effectiveMax)
        window.delegate = sizeDelegate
        windowDelegates[window] = sizeDelegate

        window.center()

        return window
    }

    // MARK: - Activation Policy

    private var activationObserver: NSKeyValueObservation?

    private func activateApp(window: NSWindow? = nil) {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)

        if NSApp.isActive {
            NSApp.activate()
            return
        }

        activationObserver?.invalidate()
        activationObserver = NSApp.observe(\.isActive, options: .new) { [weak self] app, change in
            guard change.newValue == true else { return }
            self?.activationObserver?.invalidate()
            self?.activationObserver = nil
            window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    private func revertToAccessoryIfNeeded() {
        let dashboardVisible = dashboardWindow?.isVisible == true
        let settingsVisible = settingsWindow?.isVisible == true
        let sessionVisible = sessionWindows.contains { $0.isVisible }

        if !dashboardVisible && !settingsVisible && !sessionVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About Caudit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Caudit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        mainMenu.addItem(appMenuItem)

        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    // MARK: - Status Item & Popover

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Caudit")
        button.imagePosition = .imageLeading
        button.title = " --"
        button.action = #selector(togglePopover)
        button.target = self
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 380)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView()
                .environment(appState)
        )
    }

    private func updateStatusItemText() {
        guard let button = statusItem.button else { return }
        let text = appState.menuBarText
        let newTitle = " \(text)"
        if button.title != newTitle {
            button.title = newTitle
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            stopEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startEventMonitor()
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
            self.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Window Size Delegate

/// NSWindowDelegate that enforces min/max frame size via windowWillResize.
/// NavigationSplitView's internal NSSplitView installs Auto Layout constraints
/// that override NSWindow.contentMinSize/contentMaxSize, so this delegate is
/// the only reliable way to clamp the window size.
@MainActor
private final class WindowSizeDelegate: NSObject, NSWindowDelegate {
    let minSize: NSSize
    let maxSize: NSSize

    init(minSize: NSSize, maxSize: NSSize) {
        self.minSize = minSize
        self.maxSize = maxSize
    }

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        MainActor.assumeIsolated {
            var clamped = frameSize
            clamped.width = max(minSize.width, min(maxSize.width, clamped.width))
            clamped.height = max(minSize.height, clamped.height)
            return clamped
        }
    }
}
