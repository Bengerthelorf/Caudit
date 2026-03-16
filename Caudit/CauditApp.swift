import SwiftUI
import Sparkle

@main
struct CauditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "placeholder") {}
            .commands {
                CommandGroup(after: .appInfo) {
                    CheckForUpdatesView(updater: appDelegate.updaterController.updater)
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        AppDelegate.shared.showSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
