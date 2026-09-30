import SwiftUI

@main
struct MacLiveApp: App {
    static let settingsWindowID = "settings"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("mac-live 设置", id: Self.settingsWindowID) {
            SettingsView(store: SettingsStore.shared)
        }
        .defaultSize(width: 500, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("mac-live", systemImage: "textformat") {
            MenuBarView(store: SettingsStore.shared)
        }
    }
}
