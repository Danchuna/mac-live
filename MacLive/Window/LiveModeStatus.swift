import AppKit
import Combine
import Foundation

/// 直播模式的运行状态（给界面显示用）：虚拟屏是否就绪、采集是否在跑、权限状态、出错信息。
final class LiveModeStatus: ObservableObject {
    static let shared = LiveModeStatus()

    @Published var isVirtualDisplayReady = false
    @Published var virtualDisplayName: String?
    @Published var virtualDisplaySize: String?
    @Published var errorMessage: String?

    // 画面合成相关
    @Published var hasScreenPermission = ScreenCompositeStream.hasPermission
    @Published var isCapturing = false
    @Published var capturedFrameSize: String?
    /// 最近一帧物理屏画面，用于设置界面的实时预览（限频刷新）。
    @Published var latestFrame: CGImage?

    private init() {}

    func markReady(name: String, width: Int, height: Int) {
        isVirtualDisplayReady = true
        virtualDisplayName = name
        virtualDisplaySize = "\(width) × \(height)"
        errorMessage = nil
    }

    func markStopped() {
        isVirtualDisplayReady = false
        virtualDisplayName = nil
        virtualDisplaySize = nil
        markCaptureStopped()
    }

    /// 关闭直播模式：状态归零，并清掉上一次的错误提示（否则关掉后红字还挂着）。
    func markLiveModeDisabled() {
        markStopped()
        errorMessage = nil
    }

    func markFailed(_ message: String?) {
        markStopped()
        errorMessage = message
    }

    func markCaptureStopped() {
        isCapturing = false
        capturedFrameSize = nil
        latestFrame = nil
    }

    func markCapturing(width: Int, height: Int) {
        isCapturing = true
        capturedFrameSize = "\(width) × \(height)"
        errorMessage = nil
    }

    func refreshScreenPermission() {
        hasScreenPermission = ScreenCompositeStream.hasPermission
    }
}
