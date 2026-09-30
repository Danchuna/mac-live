import AppKit
import CoreFoundation
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

/// 开发/验证用：`--capture-probe [秒数]` 实测 ScreenCaptureKit 的帧投递行为。
///
/// 需要「屏幕录制」权限，因此要用正式 App（`dist/mac-live.app`）启动：
///   open -n "dist/mac-live.app" --args --capture-probe 4
/// 结果写入 /tmp/maclive-capture.log。
enum CaptureProbe {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--capture-probe") else { return }
        let seconds = (index + 1 < arguments.count ? Double(arguments[index + 1]) : nil) ?? 4
        run(seconds: max(seconds, 2))
        exit(0)
    }

    private static func run(seconds: Double) {
        var finished = false
        var log = "=== 屏幕采集帧投递探针 ===\n"

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                    throw ScreenCompositeStream.Failure.noDisplay
                }

                let configuration = SCStreamConfiguration()
                configuration.width = CGDisplayPixelsWide(display.displayID)
                configuration.height = CGDisplayPixelsHigh(display.displayID)
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                configuration.queueDepth = 3
                configuration.showsCursor = true

                let handler = ProbeHandler()
                let stream = SCStream(
                    filter: SCContentFilter(display: display, excludingWindows: []),
                    configuration: configuration,
                    delegate: nil
                )
                try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: handler.queue)

                let startTime = Date()
                try await stream.startCapture()
                log += "采集已启动：\(configuration.width)x\(configuration.height) @30fps\n"

                // 阶段一：屏幕静止不动
                try await Task.sleep(nanoseconds: UInt64(seconds * 0.4 * 1_000_000_000))
                log += handler.report(title: "阶段一：静止不动", from: startTime)
                handler.reset()

                // 阶段二：只移动鼠标（不改动任何窗口）
                let cursorStart = CGEvent(source: nil)?.location ?? .zero
                let phaseStart = Date()
                var angle = 0.0
                while Date().timeIntervalSince(phaseStart) < seconds * 0.4 {
                    angle += 0.9
                    CGWarpMouseCursorPosition(
                        CGPoint(x: cursorStart.x + cos(angle) * 70, y: cursorStart.y + sin(angle) * 70)
                    )
                    try await Task.sleep(nanoseconds: 40_000_000)
                }
                CGWarpMouseCursorPosition(cursorStart)
                log += handler.report(title: "阶段二：只移动鼠标", from: phaseStart)
                handler.reset()

                // 阶段三：窗口有变化（用本进程的一个小窗口来回移动）
                let probeWindow = await MainActor.run { () -> NSWindow in
                    let window = NSWindow(
                        contentRect: NSRect(x: 120, y: 120, width: 160, height: 120),
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false
                    )
                    window.backgroundColor = .systemPink
                    window.isOpaque = true
                    window.level = .floating
                    window.orderFrontRegardless()
                    return window
                }
                let moveStart = Date()
                for step in 0..<20 {
                    await MainActor.run {
                        probeWindow.setFrameOrigin(NSPoint(x: 120 + CGFloat(step) * 6, y: 120 + CGFloat(step) * 4))
                    }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                log += handler.report(title: "阶段三：窗口内容/位置变化", from: moveStart)
                await MainActor.run { probeWindow.orderOut(nil) }

                try await stream.stopCapture()
            } catch {
                log += "错误：\(error.localizedDescription)\n"
            }

            try? log.write(toFile: "/tmp/maclive-capture.log", atomically: true, encoding: .utf8)
            finished = true
        }

        // 主线程等待任务完成
        while !finished {
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
        }
    }
}

/// 统计收到帧的状态、间隔，以及 idle 帧是否带可用图像。
private final class ProbeHandler: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "com.maclive.app.probe")

    private var counts: [String: Int] = [:]
    private var intervals: [Double] = []
    private var lastTimestamp: Date?
    private var idleWithImage = 0
    private var idleWithoutImage = 0

    func reset() {
        counts = [:]
        intervals = []
        lastTimestamp = nil
        idleWithImage = 0
        idleWithoutImage = 0
    }

    func report(title: String, from start: Date) -> String {
        let now = Date()
        let duration = max(now.timeIntervalSince(start), 0.001)
        let total = counts.values.reduce(0, +)
        let sortedIntervals = intervals.sorted()
        let median = sortedIntervals.isEmpty ? 0 : sortedIntervals[sortedIntervals.count / 2]
        let maxGap = sortedIntervals.last ?? 0
        let statusText = counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }.joined(separator: " ")
        return """
        [\(title)] 时长 \(String(format: "%.2f", duration))s  帧数 \(total)  实测 \(String(format: "%.1f", Double(total) / duration)) fps
          状态分布: \(statusText.isEmpty ? "无" : statusText)
          帧间隔: 中位 \(String(format: "%.1f", median * 1000))ms  最大 \(String(format: "%.1f", maxGap * 1000))ms
          idle 帧带图像: \(idleWithImage)  不带图像: \(idleWithoutImage)
        """
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        let now = Date()
        var statusName = "未知"
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw) {
            switch status {
            case .complete: statusName = "complete"
            case .idle: statusName = "idle"
            case .blank: statusName = "blank"
            case .suspended: statusName = "suspended"
            case .stopped: statusName = "stopped"
            case .started: statusName = "started"
            @unknown default: statusName = "unknown(\(raw))"
            }
        }

        let hasImage = CMSampleBufferGetImageBuffer(sampleBuffer) != nil
        if statusName == "idle" {
            if hasImage { idleWithImage += 1 } else { idleWithoutImage += 1 }
        }

        counts[statusName, default: 0] += 1
        if let last = lastTimestamp {
            intervals.append(now.timeIntervalSince(last))
        }
        lastTimestamp = now
    }
}
