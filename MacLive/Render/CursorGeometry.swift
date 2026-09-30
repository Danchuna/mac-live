import AppKit

/// 自己绘制鼠标指针时的几何换算。
///
/// 采集画面里不会更新指针位置（ScreenCaptureKit 只在画面变化时投递帧），
/// 所以要把「屏幕坐标下的指针位置」映射成「画面里指针该画的位置」。
enum CursorGeometry {
    /// 取指针图像与该图对应的热点。
    /// 注意：`NSCursor.arrow` / `.iBeam` 的 `.image` 在部分系统上为空，需要退回当前系统指针。
    static func resolve(_ cursor: NSCursor) -> (image: NSImage, hotspot: NSPoint)? {
        if cursor.image.size.width > 0, cursor.image.size.height > 0 {
            return (cursor.image, cursor.hotSpot)
        }
        if let system = NSCursor.currentSystem,
           system.image.size.width > 0,
           system.image.size.height > 0 {
            return (system.image, system.hotSpot)
        }
        return nil
    }

    /// 把屏幕坐标下的指针位置映射成画面里指针的矩形（视图坐标，左下原点）。
    ///
    /// - Parameters:
    ///   - mouse: `NSEvent.mouseLocation` 风格的屏幕坐标（左下原点）
    ///   - displayFrame: 被采集显示器在屏幕坐标里的 frame（点）
    ///   - captureSize: 采集输出的像素尺寸
    ///   - viewBounds: 悬浮窗内容视图的 bounds
    ///   - fitMode: 屏幕画面如何适配到画面
    ///   - cursorImageSize: 指针图像的点尺寸
    ///   - hotspot: 指针热点（**左上原点**的图像坐标，来自 NSCursor.hotSpot）
    /// - Returns: 指针图层应该设置的 frame；指针不在该显示器内时返回 nil
    static func cursorFrame(
        mouse: NSPoint,
        displayFrame: NSRect,
        captureSize: CGSize,
        viewBounds: NSRect,
        fitMode: LiveFitMode,
        cursorImageSize: CGSize,
        hotspot: NSPoint
    ) -> NSRect? {
        guard displayFrame.width > 0, displayFrame.height > 0,
              captureSize.width > 0, captureSize.height > 0,
              cursorImageSize.width > 0, cursorImageSize.height > 0
        else { return nil }

        // 指针在该显示器内的归一化位置（屏幕左下原点 → 采集画面左上原点）
        let u = (mouse.x - displayFrame.minX) / displayFrame.width
        let v = (mouse.y - displayFrame.minY) / displayFrame.height
        guard u >= 0, u <= 1, v >= 0, v <= 1 else { return nil }

        let rect = OverlayRenderer.fittedRect(contentSize: captureSize, in: viewBounds, mode: fitMode)
        // 屏幕坐标与视图坐标都是左下原点，v 直接就是“距底部比例”，不要再翻转一次。
        // （采集图像本身是左上原点，但它被画进 rect 时是正着的，所以这里按同一套比例即可。）
        let tip = NSPoint(x: rect.minX + u * rect.width, y: rect.minY + v * rect.height)
        // 视图单位 / 屏幕点：保证指针和画面内容同比缩放
        let scale = rect.width / displayFrame.width
        // NSCursor.hotSpot 用的是左上原点，图层 frame 用左下原点，需要翻转 y
        let flippedY = cursorImageSize.height - hotspot.y
        return NSRect(
            x: tip.x - hotspot.x * scale,
            y: tip.y - flippedY * scale,
            width: cursorImageSize.width * scale,
            height: cursorImageSize.height * scale
        )
    }
}
