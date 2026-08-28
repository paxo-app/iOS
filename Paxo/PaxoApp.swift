import SwiftUI

@main
struct PaxoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(AppState.shared)
                .environmentObject(AppState.shared.store)
        } label: {
            Image(systemName: "text.viewfinder")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(AppState.shared)
                .environmentObject(AppState.shared.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }
}
