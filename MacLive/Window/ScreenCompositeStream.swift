import AppKit
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

/// 采集物理屏幕画面，交给上层合成到虚拟屏上。
///
/// 这样“原画面 + 悬浮文字”直接成为一路可被采集的画面，直播软件只需要「显示器采集」，
/// 不再依赖任何抠像（色度键）能力。需要用户授予「屏幕录制」权限。
final class ScreenCompositeStream: NSObject, SCStreamOutput, SCStreamDelegate {
    enum Failure: LocalizedError {
        case permissionMissing
        case noDisplay
        case startFailed(String)
        case stopped(String)

        var errorDescription: String? {
            switch self {
            case .permissionMissing:
                return "缺少「屏幕录制」权限：点「申请权限」授权，或到 系统设置 → 隐私与安全性 → 屏幕录制 里勾选本 App（若刚更新过 App，需要把本 App 从列表里移除后重新添加），然后重启本 App。"
            case .noDisplay:
                return "找不到可采集的显示器。"
            case .startFailed(let reason):
                return "启动屏幕采集失败：\(reason)"
            case .stopped(let reason):
                return "屏幕采集被中断：\(reason)"
            }
        }
    }

    /// 是否已获得屏幕录制权限。
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// 触发系统权限申请（弹窗）。授权后需要重启 App 才真正生效。
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// 采集被系统中断时回调（例如权限被撤销、显示器变化）。
    var onStreamStopped: ((String) -> Void)?

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.maclive.app.composite")
    private var onFrame: ((CGImage) -> Void)?

    /// 采集输出的像素尺寸（用于把指针位置映射回画面）。
    private(set) var captureSize: CGSize = .zero
    /// 被采集显示器的 displayID（用于判断指针是否在这块屏上）。
    private(set) var capturedDisplayID: CGDirectDisplayID = 0

    var isRunning: Bool { stream != nil }

    func start(
        displayID: CGDirectDisplayID,
        canvasWidth: Int,
        canvasHeight: Int,
        frameRate: Int,
        excludeOwnWindows: Bool,
        onFrame: @escaping (CGImage) -> Void
    ) async throws {
        await stop()

        guard Self.hasPermission else { throw Failure.permissionMissing }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Failure.startFailed(error.localizedDescription)
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw Failure.noDisplay
        }

        let excluded: [SCWindow]
        if excludeOwnWindows {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            excluded = content.windows.filter { $0.owningApplication?.processID == ownPID }
        } else {
            excluded = []
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        // 按显示器自身比例采集（不放大），最终由图层按「适应 / 填满 / 拉伸」缩放到画面尺寸。
        let pixelWidth = Double(CGDisplayPixelsWide(display.displayID))
        let pixelHeight = Double(CGDisplayPixelsHigh(display.displayID))
        let scale = min(
            Double(canvasWidth) / max(pixelWidth, 1),
            Double(canvasHeight) / max(pixelHeight, 1),
            1
        )
        let captureWidth = max(2, Int((pixelWidth * scale).rounded()))
        let captureHeight = max(2, Int((pixelHeight * scale).rounded()))

        let configuration = SCStreamConfiguration()
        configuration.width = captureWidth
        configuration.height = captureHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(frameRate, 1)))
        configuration.queueDepth = 3
        // 指针由使用方按固定帧率自己绘制：ScreenCaptureKit 只在画面变化时投递帧，
        // 屏幕静止时拿不到指针位置，画面会看起来“卡住”。这里关掉采集自带的指针避免重影。
        configuration.showsCursor = false

        self.captureSize = CGSize(width: captureWidth, height: captureHeight)
        self.capturedDisplayID = display.displayID

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            throw Failure.startFailed(error.localizedDescription)
        }

        self.onFrame = onFrame
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        self.onFrame = nil
        try? await stream.stopCapture()
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // ScreenCaptureKit 只在画面变化时投递 complete 帧；idle 帧表示“内容没变”。
        // 这里接受任何带图像缓冲的帧（idle 帧通常没有新 IOSurface，会被下面的判断过滤掉），
        // 从而保证第一帧和变化帧都不会漏。
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let rawStatus = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status == .blank || status == .suspended || status == .stopped {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image) == noErr, let frame = image else {
            return
        }

        guard let onFrame else { return }
        DispatchQueue.main.async { onFrame(frame) }
    }

    // MARK: - SCStreamDelegate

    /// 采集停止通知（由 ReplayKit/ScreenCaptureKit 在后台线程回调）。
    ///
    /// 两个坑：
    /// 1. 「干净停止」时系统会把 error 传成 **nil**，若按非空 `Error` 使用（例如取
    ///    `localizedDescription`）会直接崩溃（EXC_BAD_ACCESS at 0x0），所以这里用 `NSError?` 接收；
    /// 2. 回调不在主线程，状态改动统一回主线程做，避免和 start/stop 抢同一批字段。
    /// 采集停止通知（由 ReplayKit/ScreenCaptureKit 在后台线程回调）。
    ///
    /// 两个坑：
    /// 1. 「干净停止」时系统会把 error 传成 **nil**，按非空 `Error` 用（例如取
    ///    `localizedDescription`）会直接崩溃（EXC_BAD_ACCESS at 0x0），
    ///    所以这里故意声明成可选参数（编译器会提示可选性不同，属于有意为之）；
    /// 2. 回调不在主线程，状态改动统一回主线程做，避免和 start/stop 抢同一批字段。
    @objc
    func stream(_ stream: SCStream, didStopWithError error: Error?) {
        let message = error?.localizedDescription ?? "屏幕采集已停止"
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stream = nil
            self.onFrame = nil
            self.onStreamStopped?(message)
        }
    }
}
