import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        SelfTest.runIfRequested()
        CaptureProbe.runIfRequested()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        OverlayController.shared.start()

        guard CommandLine.arguments.contains("--dump-window") else { return }
        dumpWindow(phase: "launch")

        // 验证用：--toggle-live-after N 秒后翻转直播模式，观察切换过程。
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--toggle-live-after"),
           index + 1 < arguments.count,
           let delay = Double(arguments[index + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                SettingsStore.shared.config.liveMode.toggle()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.dumpWindow(phase: "afterDelay")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.dumpWindow(phase: "final")
            exit(0)
        }
    }

    /// 把悬浮窗状态追加写入 /tmp/maclive-window.log，便于在没有屏幕录制权限时验证。
    private func dumpWindow(phase: String) {
        let text = "phase=\(phase)\n\(OverlayController.shared.diagnosticDescription())\n\n"
        FileHandle.standardError.write(Data(text.utf8))
        guard let handle = FileHandle(forWritingAtPath: Self.dumpLogPath) else {
            FileManager.default.createFile(atPath: Self.dumpLogPath, contents: Data(text.utf8))
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }

    private static let dumpLogPath = "/tmp/maclive-window.log"

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        OverlayController.shared.shutdown()
        SettingsStore.shared.persist()
    }
}
