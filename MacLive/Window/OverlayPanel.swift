import AppKit

/// 无边框、透明、不抢焦点的悬浮面板。
final class OverlayPanel: NSPanel {
    /// 编辑模式下才允许成为 key window，直播模式下完全不影响当前前台应用。
    var allowsEditing = true

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // 出现在所有桌面空间（含其他 App 的全屏空间），且不随 Mission Control 移动。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        // 无边框窗口不显示标题，但标题会出现在窗口列表里，方便在直播软件「窗口采集」中认出它。
        title = "mac-live"
        // 明确允许被采集（.none 会把窗口从录屏/采集里排除掉）。
        sharingType = .readOnly
    }

    override var canBecomeKey: Bool { allowsEditing }

    override var canBecomeMain: Bool { false }
}
