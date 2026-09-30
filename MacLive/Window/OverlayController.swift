import AppKit
import Combine

/// 悬浮窗的生命周期与配置同步，并负责直播模式（虚拟显示器）的创建与回收。
final class OverlayController: NSObject, NSWindowDelegate {
    static let shared = OverlayController()

    /// 虚拟屏名称：直播软件（OBS / 直播伴侣）在“显示器采集”里会看到这个名字。
    static let virtualDisplayName = "mac-live 虚拟屏"

    private var panel: OverlayPanel?
    private var cancellables = Set<AnyCancellable>()
    /// 程序内部调整窗口时置位，避免把自动调整当成用户拖动来回写。
    private var isApplying = false
    private var virtualDisplay: VirtualDisplay?
    private var liveRetryAttempts = 0
    private var compositeStream: ScreenCompositeStream?
    /// 当前采集参数，用于判断是否需要重启采集。
    private var compositeSignature: String?
    private var lastPreviewPush = Date.distantPast
    /// 自己绘制的鼠标指针刷新计时器。
    private var cursorTimer: Timer?
    /// 本次运行是否已经主动请求过屏幕录制权限（避免反复弹窗）。
    private var didRequestScreenPermission = false

    private override init() {
        super.init()
    }

    func start() {
        guard panel == nil else { return }

        let store = SettingsStore.shared
        let size = OverlayRenderer.contentSize(for: store.config)
        let origin = store.config.origin.map { NSPoint(x: $0.x, y: $0.y) } ?? Self.defaultOrigin(for: size)

        let panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size))
        panel.contentView = OverlayContentView(frame: NSRect(origin: .zero, size: size))
        panel.delegate = self
        panel.setFrame(Self.clamp(NSRect(origin: origin, size: size)), display: false)
        self.panel = panel

        store.$config
            .removeDuplicates()
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        apply(store.config)
    }

    /// 退出前释放虚拟屏并停止屏幕采集。
    func shutdown() {
        teardownLiveMode()
        stopCompositeStream()
    }

    /// 重新应用一次当前配置（例如刚在系统设置里授权“屏幕录制”后重新检测）。
    func reapplyLive() {
        LiveModeStatus.shared.refreshScreenPermission()
        apply(SettingsStore.shared.config)
    }

    /// 把悬浮窗放回主屏幕顶部中间（直播模式下无效，位置由画面锚点决定）。
    func resetPosition() {
        guard let panel, !SettingsStore.shared.config.liveMode else { return }
        let size = OverlayRenderer.contentSize(for: SettingsStore.shared.config)
        var frame = panel.frame
        frame.origin = Self.defaultOrigin(for: size)
        frame.size = size
        isApplying = true
        panel.setFrame(Self.clamp(frame), display: true)
        isApplying = false
        SettingsStore.shared.config.origin = panel.frame.origin
    }

    @objc private func screenParametersChanged() {
        guard !isApplying else { return }
        // 虚拟屏建好/回收都会触发；统一重新应用一次配置即可（两种模式各自处理）。
        apply(SettingsStore.shared.config)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isApplying, let panel else { return }
        // 直播模式下窗口整屏铺在虚拟屏上，不要覆盖用户保存的物理屏位置。
        guard !SettingsStore.shared.config.liveMode else { return }
        SettingsStore.shared.config.origin = panel.frame.origin
    }

    // MARK: - 诊断

    /// 开发/验证用：输出悬浮窗的真实运行状态（屏幕录制受限时用来替代截图检查）。
    func diagnosticDescription() -> String {
        guard let panel, let content = panel.contentView else { return "panel: nil" }
        let config = SettingsStore.shared.config
        let display = virtualDisplay
        return """
        frame=\(panel.frame)
        screen=\(panel.screen?.localizedName ?? "nil")
        contentSize=\(OverlayRenderer.contentSize(for: config))
        isVisible=\(panel.isVisible) configIsVisible=\(config.isVisible) level=\(panel.level.rawValue) alphaValue=\(panel.alphaValue)
        isOpaque=\(panel.isOpaque) backgroundColor=\(String(describing: panel.backgroundColor))
        ignoresMouseEvents=\(panel.ignoresMouseEvents) allowsEditing=\(panel.allowsEditing) canBecomeKey=\(panel.canBecomeKey)
        collectionBehavior=\(panel.collectionBehavior.rawValue) contentView=\(type(of: content))
        interactive=\(config.isInteractive) isLocked=\(config.isLocked) editingMode=\(config.editingMode)
        appActive=\(NSApp.isActive) text=\(config.text) fontSize=\(config.fontSize) opacity=\(config.opacity)
        liveMode=\(config.liveMode) composeMode=\(config.liveComposeMode.rawValue) fit=\(config.liveFitMode.rawValue) fps=\(config.liveFrameRate)
        liveDisplayID=\(display?.displayID ?? 0) liveDisplaySize=\(display.map { "\($0.pixelWidth)x\($0.pixelHeight)" } ?? "nil")
        capture=\(LiveModeStatus.shared.isCapturing) captureSize=\(LiveModeStatus.shared.capturedFrameSize ?? "nil") screenPermission=\(LiveModeStatus.shared.hasScreenPermission)
        savedOrigin=\(config.origin.map { "\(Int($0.x)),\(Int($0.y))" } ?? "nil")
        liveStatusReady=\(LiveModeStatus.shared.isVirtualDisplayReady) liveStatusError=\(LiveModeStatus.shared.errorMessage ?? "nil")
        windowInfo=\(Self.windowCaptureInfo(for: panel))
        screens=\(NSScreen.screens.map { "\($0.localizedName)\($0.frame)" }.joined(separator: " | "))
        """
    }

    /// 检查悬浮窗是否在系统窗口列表里、是否允许被采集（直播软件「窗口采集」能否选到它）。
    private static func windowCaptureInfo(for panel: NSWindow) -> String {
        let number = panel.windowNumber
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(number)) as? [[String: Any]],
              let info = list.first
        else {
            return "windowNumber=\(number) 不在窗口列表中"
        }
        let name = info[kCGWindowName as String] as? String ?? ""
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        // sharingType: 0=不允许采集 1=只读（可采集） 2=可读写
        let sharing = info[kCGWindowSharingState as String] as? UInt32 ?? 0
        let alpha = info[kCGWindowAlpha as String] as? Double ?? -1
        let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
        let layer = info[kCGWindowLayer as String] as? Int ?? -1
        var boundsText = "nil"
        if let boundsValue = info[kCGWindowBounds as String],
           let rect = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary) {
            boundsText = "\(Int(rect.width))x\(Int(rect.height))@\(Int(rect.origin.x)),\(Int(rect.origin.y))"
        }
        return "windowNumber=\(number) title=\(name) owner=\(owner) sharing=\(sharing) alpha=\(alpha) onScreen=\(onScreen) layer=\(layer) bounds=\(boundsText)"
    }

    // MARK: - 配置应用

    private func apply(_ config: OverlayConfig) {
        guard let panel, let content = panel.contentView as? OverlayContentView else { return }

        isApplying = true
        defer { isApplying = false }

        content.config = config

        if config.liveMode {
            applyLiveLayout(config, panel: panel)
        } else {
            let wasLive = virtualDisplay != nil
            teardownLiveMode()
            if wasLive {
                restoreSavedPosition(panel: panel, config: config)
            }
            applyWindowLayout(config, panel: panel)
        }

        // 直播模式下窗口在虚拟屏上，不接受鼠标、也不该被“半透明”影响抠像结果。
        let interactive = config.isInteractive && !config.liveMode
        panel.allowsEditing = interactive
        panel.ignoresMouseEvents = !interactive
        panel.level = config.windowLevel.nsLevel
        panel.alphaValue = config.liveMode ? 1 : CGFloat(min(max(config.opacity, 0), 1))

        // 直播模式下等虚拟屏注册完成再显示，避免文字在自己屏幕上闪一下。
        let liveReady = !config.liveMode || virtualDisplay?.screen != nil
        let shouldShow = config.isVisible && liveReady
        if shouldShow, !panel.isVisible {
            panel.orderFrontRegardless()
        } else if !shouldShow, panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// 普通模式：窗口贴合文字大小，以「顶部居中」为锚点缩放。
    private func applyWindowLayout(_ config: OverlayConfig, panel: OverlayPanel) {
        let size = OverlayRenderer.contentSize(for: config)
        let oldFrame = panel.frame
        var frame = NSRect(
            x: oldFrame.midX - size.width / 2,
            y: oldFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if frame.size != oldFrame.size {
            frame = Self.clamp(frame)
        }
        if frame != oldFrame {
            panel.setFrame(frame, display: true)
        }
    }

    /// 直播模式：创建/复用虚拟显示器，并把窗口整屏铺上去。
    private func applyLiveLayout(_ config: OverlayConfig, panel: OverlayPanel) {
        let width = max(Int(config.virtualDisplayWidth.rounded()), 320)
        let height = max(Int(config.virtualDisplayHeight.rounded()), 240)

        if let display = virtualDisplay, display.pixelWidth != width || display.pixelHeight != height {
            display.release()
            virtualDisplay = nil
            liveRetryAttempts = 0
        }

        if virtualDisplay == nil {
            do {
                virtualDisplay = try VirtualDisplay(width: width, height: height, name: Self.virtualDisplayName)
                liveRetryAttempts = 0
                LiveModeStatus.shared.markStopped()
            } catch {
                virtualDisplay = nil
                LiveModeStatus.shared.markFailed(error.localizedDescription)
                // 建不出来就不要停在“什么都没有”的状态，自动关掉直播模式。
                DispatchQueue.main.async {
                    SettingsStore.shared.config.liveMode = false
                }
                return
            }
        }

        guard let display = virtualDisplay, let screen = display.screen else {
            scheduleLiveScreenRetry()
            return
        }

        liveRetryAttempts = 0
        LiveModeStatus.shared.markReady(name: display.name, width: display.pixelWidth, height: display.pixelHeight)

        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: true)
        }

        syncCompositeStream(config)
    }

    private func teardownLiveMode() {
        stopCompositeStream()
        if let display = virtualDisplay {
            display.release()
            virtualDisplay = nil
        }
        liveRetryAttempts = 0
        // 关闭直播模式后清空状态与错误提示（否则关掉后红字还挂着，像“关闭就报错”）
        LiveModeStatus.shared.markLiveModeDisabled()
    }

    // MARK: - 画面合成（采集物理屏 + 叠加文字）

    /// 需要采集时启动/重启采集，不需要时停掉。
    private func syncCompositeStream(_ config: OverlayConfig) {
        guard config.liveMode, config.liveComposeMode == .screenComposite, virtualDisplay != nil else {
            stopCompositeStream()
            return
        }

        guard ScreenCompositeStream.hasPermission else {
            stopCompositeStream()
            // 授权失效（例如 App 重新构建后签名变化）时，主动弹一次系统授权引导，
            // 并把 App 加进「屏幕录制」列表，用户去系统设置里勾一下即可。
            if !didRequestScreenPermission {
                didRequestScreenPermission = true
                ScreenCompositeStream.requestPermission()
            }
            LiveModeStatus.shared.refreshScreenPermission()
            LiveModeStatus.shared.errorMessage = ScreenCompositeStream.Failure.permissionMissing.errorDescription
            return
        }

        let canvasWidth = Int(config.virtualDisplayWidth.rounded())
        let canvasHeight = Int(config.virtualDisplayHeight.rounded())
        let signature = "\(canvasWidth)x\(canvasHeight)-\(config.liveFrameRate)-\(config.liveHideOwnWindows)"
        if compositeStream != nil, compositeSignature == signature {
            return
        }

        // 采集目标：主屏（排除虚拟屏本身）
        let mainDisplayID = Self.mainPhysicalDisplayID(excluding: virtualDisplay?.displayID)
        let frameRate = max(min(config.liveFrameRate, 60), 5)
        let excludeOwn = config.liveHideOwnWindows
        let stream = compositeStream ?? ScreenCompositeStream()
        stream.onStreamStopped = { [weak self] message in
            self?.compositeStream = nil
            self?.compositeSignature = nil
            LiveModeStatus.shared.markCaptureStopped()
            LiveModeStatus.shared.errorMessage = ScreenCompositeStream.Failure.stopped(message).errorDescription
        }
        compositeStream = stream
        compositeSignature = signature

        Task { @MainActor in
            do {
                try await stream.start(
                    displayID: mainDisplayID,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    frameRate: frameRate,
                    excludeOwnWindows: excludeOwn
                ) { [weak self] image in
                    self?.handleCapturedFrame(image)
                }
                LiveModeStatus.shared.markCapturing(width: canvasWidth, height: canvasHeight)
                startCursorTimer()
            } catch {
                self.compositeStream = nil
                self.compositeSignature = nil
                LiveModeStatus.shared.markCaptureStopped()
                LiveModeStatus.shared.errorMessage = error.localizedDescription
                stopCursorTimer()
            }
        }
    }

    private func stopCompositeStream() {
        stopCursorTimer()
        guard let stream = compositeStream else { return }
        compositeStream = nil
        compositeSignature = nil
        // 主动停止：先摘掉“被中断”回调，避免把它当成采集出错来报错
        stream.onStreamStopped = nil
        LiveModeStatus.shared.markCaptureStopped()
        // 清掉采集层与指针，避免下次进入时残留旧画面
        if let content = panel?.contentView as? OverlayContentView {
            content.setCaptureFrame(nil)
            content.hideCursor()
        }
        Task { @MainActor in
            await stream.stop()
        }
    }

    /// 采集到的每一帧：贴到悬浮窗上，并限频推给设置界面做实时预览。
    private func handleCapturedFrame(_ image: CGImage) {
        guard SettingsStore.shared.config.showsCaptureLayer else { return }
        if let content = panel?.contentView as? OverlayContentView {
            content.setCaptureFrame(image)
        }
        let now = Date()
        if now.timeIntervalSince(lastPreviewPush) > 0.2 {
            lastPreviewPush = now
            LiveModeStatus.shared.latestFrame = image
        }
    }

    // MARK: - 鼠标指针
    //
    // ScreenCaptureKit 只在画面变化时投递帧：屏幕静止时画面不变（这是对的），
    // 但采到的帧里也不会有指针的新位置，看起来就“像卡住”。
    // 所以指针由我们自己按 60Hz 绘制（macOS 上的录屏/直播软件都是这么做的）。

    private func startCursorTimer() {
        stopCursorTimer()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickCursor()
        }
        // 用 .common 模式：拖动窗口、滚动时也继续刷新指针
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
        tickCursor()
    }

    private func stopCursorTimer() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private func tickCursor() {
        guard let panel,
              let content = panel.contentView as? OverlayContentView,
              let stream = compositeStream,
              SettingsStore.shared.config.showsCaptureLayer
        else { return }

        // 只画在被采集的那块屏上；指针移到别的屏（含虚拟屏）就隐藏。
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              number.uint32Value == stream.capturedDisplayID,
              let resolved = CursorGeometry.resolve(NSCursor.currentSystem ?? NSCursor.arrow),
              let frame = CursorGeometry.cursorFrame(
                  mouse: mouse,
                  displayFrame: screen.frame,
                  captureSize: stream.captureSize,
                  viewBounds: content.bounds,
                  fitMode: SettingsStore.shared.config.liveFitMode,
                  cursorImageSize: resolved.image.size,
                  hotspot: resolved.hotspot
              )
        else {
            content.hideCursor()
            return
        }

        content.setCursor(image: resolved.image, frame: frame)
    }

    /// 主屏对应的 CGDirectDisplayID，排除虚拟屏。
    private static func mainPhysicalDisplayID(excluding virtualID: CGDirectDisplayID?) -> CGDirectDisplayID {
        let candidates = [NSScreen.main] + NSScreen.screens.filter { $0 != NSScreen.main }
        for screen in candidates {
            guard let screen else { continue }
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            guard let displayID = number?.uint32Value else { continue }
            if displayID != virtualID {
                return displayID
            }
        }
        return CGMainDisplayID()
    }

    /// 虚拟屏从创建到被系统注册成 NSScreen 有一小段延迟，需要轮询等待。
    private func scheduleLiveScreenRetry() {
        guard liveRetryAttempts < 40 else {
            LiveModeStatus.shared.markFailed("虚拟屏已创建，但系统 4 秒内没有注册它，请重试。")
            return
        }
        liveRetryAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, SettingsStore.shared.config.liveMode else { return }
            self.apply(SettingsStore.shared.config)
        }
    }

    /// 退出直播模式时回到用户之前摆放的位置。
    private func restoreSavedPosition(panel: OverlayPanel, config: OverlayConfig) {
        let size = OverlayRenderer.contentSize(for: config)
        var frame = panel.frame
        frame.size = size
        frame.origin = config.origin.map { NSPoint(x: $0.x, y: $0.y) } ?? Self.defaultOrigin(for: size)
        panel.setFrame(Self.clamp(frame), display: true)
    }

    // MARK: - 位置辅助

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 240, y: 640) }
        let visible = screen.visibleFrame
        return NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.maxY - size.height - 80).rounded()
        )
    }

    /// 保证悬浮窗至少有一部分落在某个屏幕内，避免拔掉外接屏后窗口消失。
    private static func clamp(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let screen = screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main ?? screens.first else {
            return frame
        }
        let bounds = screen.frame
        var result = frame
        result.origin.x = min(max(result.origin.x, bounds.minX), max(bounds.minX, bounds.maxX - result.width))
        result.origin.y = min(max(result.origin.y, bounds.minY), max(bounds.minY, bounds.maxY - result.height))
        return result
    }
}
