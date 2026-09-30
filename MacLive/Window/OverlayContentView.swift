import AppKit
import QuartzCore

/// 画面合成模式下承载物理屏画面的图层（由 App 采集后贴上来）。
final class CaptureLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var frameImage: CGImage? {
        didSet { layer?.contents = frameImage }
    }

    var gravity: CALayerContentsGravity = .resizeAspect {
        didSet { layer?.contentsGravity = gravity }
    }

    override func layout() {
        super.layout()
        // 图层内容就是采集到的像素，按屏幕缩放比例对齐避免发虚。
        layer?.contentsScale = window?.backingScaleFactor ?? 1
        layer?.contentsGravity = gravity
    }

    /// 采集层不参与鼠标命中，拖动由外层容器统一处理。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 绘制文字的图层：普通模式画自身尺寸，直播模式按画面锚点画。
final class OverlayTextView: NSView {
    var config = OverlayConfig() {
        didSet {
            if config != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard config.liveMode else {
            OverlayRenderer.draw(config, in: bounds)
            return
        }
        switch config.liveComposeMode {
        case .chromaKey:
            // 铺满抠像底色 + 不透明文字
            OverlayRenderer.drawLive(config, in: bounds)
        case .screenComposite:
            // 只画文字，叠在采集来的屏幕画面上
            OverlayRenderer.drawLiveText(config, in: bounds, forceOpaque: false)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 自己绘制的鼠标指针。
///
/// ScreenCaptureKit 只在画面变化时投递帧，屏幕静止时采集里根本没有指针位置，
/// 所以指针必须由使用方按固定帧率绘制（macOS 上的录屏/直播软件都是这么做的）。
final class CursorOverlayView: NSView {
    private var currentImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 指针不参与鼠标命中，拖动由外层容器统一处理。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 按 CursorGeometry 算好的 frame 摆放指针；nil 表示隐藏。
    func update(image: NSImage, frame targetFrame: NSRect) {
        if currentImage !== image {
            currentImage = image
            // 按 1x 取图，配合 contentsScale = 1；几何完全由 frame 决定（contentsGravity = .resize）
            var proposed = NSRect(origin: .zero, size: image.size)
            layer?.contents = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
            layer?.contentsScale = 1
        }
        isHidden = false
        frame = targetFrame
    }
}

/// 悬浮窗内容容器：底层是（可选的）采集画面，中间是文字，最上层是自己绘制的鼠标指针。
final class OverlayContentView: NSView {
    private let captureView = CaptureLayerView(frame: .zero)
    private let textView = OverlayTextView(frame: .zero)
    private let cursorView = CursorOverlayView(frame: .zero)

    var config = OverlayConfig() {
        didSet {
            guard config != oldValue else { return }
            captureView.isHidden = !config.showsCaptureLayer
            captureView.gravity = config.liveFitMode.contentsGravity
            textView.config = config
            if !config.showsCaptureLayer {
                setCaptureFrame(nil)
                hideCursor()
            }
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(captureView)
        addSubview(textView)
        addSubview(cursorView)
        captureView.isHidden = true
        cursorView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        captureView.frame = bounds
        textView.frame = bounds
    }

    /// 贴上一帧采集到的物理屏画面（画面合成模式）。
    func setCaptureFrame(_ image: CGImage?) {
        captureView.frameImage = image
    }

    /// 隐藏自己绘制的鼠标指针（指针不在这块画面上时）。
    func hideCursor() {
        cursorView.isHidden = true
    }

    /// 把指针画到指定位置（frame 由 CursorGeometry 算出）。
    func setCursor(image: NSImage, frame: NSRect) {
        cursorView.update(image: image, frame: frame)
    }

    /// 非交互状态下不接收鼠标事件（鼠标穿透到下层窗口）。
    override func hitTest(_ point: NSPoint) -> NSView? {
        config.isInteractive ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard config.isInteractive else { return }
        window?.performDrag(with: event)
    }
}

extension LiveFitMode {
    var contentsGravity: CALayerContentsGravity {
        switch self {
        case .fit: return .resizeAspect
        case .fill: return .resizeAspectFill
        case .stretch: return .resize
        }
    }
}

extension OverlayConfig {
    /// 只有在「直播模式 + 画面合成」时才需要显示采集层。
    var showsCaptureLayer: Bool {
        liveMode && liveComposeMode == .screenComposite
    }
}
