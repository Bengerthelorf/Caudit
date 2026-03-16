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
            self, selector: #selector(handleShowDashboard),
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

        let hostingController = NSHostingController(
            rootView: SettingsView(updater: updaterController.updater)
                .environment(appState)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Caudit Settings"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 680, height: 480))
        window.minSize = NSSize(width: 560, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .none

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
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

    @objc private func handleShowDashboard() {
        showDashboard()
    }



    func showDashboard() {
        if let window = dashboardWindow {
            activateApp(window: window)
            return
        }

        let hostingController = NSHostingController(
            rootView: DashboardView().environment(appState)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Caudit"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 820, height: 580))
        window.minSize = NSSize(width: 720, height: 520)
        window.center()
        window.isReleasedWhenClosed = false

        let toolbar = NSToolbar(identifier: "DashboardToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none

        dashboardCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
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
        let hostingController = NSHostingController(
            rootView: SessionReaderView(session: session)
                .environment(appState)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = session.displayName
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 700, height: 550))
        window.minSize = NSSize(width: 500, height: 400)
        window.center()
        window.isReleasedWhenClosed = false

        sessionWindows.insert(window)
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
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

    // MARK: - Activation Policy

    /// The first .accessory → .regular transition after launch needs extra time
    /// for the window server to process the policy change. A short delay before
    /// activate + makeKey ensures the window draws in the active (focused) style.
    private func activateApp(window: NSWindow? = nil) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
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
