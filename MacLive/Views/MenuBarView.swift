import AppKit
import SwiftUI

/// 快捷菜单栏入口：不必切回设置窗口就能开关悬浮文字。
struct MenuBarView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("显示悬浮文字", isOn: $store.config.isVisible)
        Toggle("编辑模式（可拖动）", isOn: $store.config.editingMode)
            .disabled(store.config.isLocked)
        Toggle("锁定位置", isOn: $store.config.isLocked)
        Toggle("直播模式（只给观众看）", isOn: $store.config.liveMode)

        Divider()

        Button("重置位置") {
            OverlayController.shared.resetPosition()
        }
        .disabled(store.config.isLocked)

        Button("打开设置…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: MacLiveApp.settingsWindowID)
        }

        Divider()

        Button("退出 mac-live") {
            NSApp.terminate(nil)
        }
    }
}
