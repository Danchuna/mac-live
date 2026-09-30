import AppKit

/// 开发/验证用：
/// - `mac-live --render-preview [--out 路径]` 离屏渲染一张悬浮文字效果图后退出。
/// - 追加 `--live` 则渲染直播模式画面（虚拟屏上的纯色底 + 文字）。
enum SelfTest {
    static func runIfRequested() {
        let arguments = CommandLine.arguments

        if arguments.contains("--cursor-check") {
            var cursorPath = "/tmp/maclive-cursor.png"
            if let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count {
                cursorPath = arguments[index + 1]
            }
            renderCursorCheck(to: cursorPath)
            exit(0)
        }

        guard arguments.contains("--render-preview") else { return }

        var outputPath = "/tmp/maclive-preview.png"
        if let outIndex = arguments.firstIndex(of: "--out"), outIndex + 1 < arguments.count {
            outputPath = arguments[outIndex + 1]
        }

        render(to: outputPath, live: arguments.contains("--live"))
        exit(0)
    }

    /// 验证自己绘制的鼠标指针落点是否准确：在假“屏幕画面”上画一个标记，
    /// 再让指针指向该标记所在的屏幕坐标；映射正确时指针尖端应正好落在标记上。
    private static func renderCursorCheck(to outputPath: String) {
        let screenSize = NSSize(width: 1710, height: 1112)
        let displayFrame = NSRect(origin: .zero, size: screenSize)
        let canvas = NSSize(width: 1920, height: 1080)
        let fitMode = LiveFitMode.fit

        // 标记位置：图像坐标（左上原点）宽 75%、高 25%
        let markerInImage = NSPoint(x: screenSize.width * 0.75, y: screenSize.height * 0.25)
        let markerOnScreen = NSPoint(
            x: displayFrame.minX + markerInImage.x,
            y: displayFrame.maxY - markerInImage.y
        )

        guard let screenImage = syntheticScreenImage(marker: markerInImage),
              let resolved = CursorGeometry.resolve(NSCursor.currentSystem ?? NSCursor.arrow),
              let cursorFrame = CursorGeometry.cursorFrame(
                  mouse: markerOnScreen,
                  displayFrame: displayFrame,
                  captureSize: screenSize,
                  viewBounds: NSRect(origin: .zero, size: canvas),
                  fitMode: fitMode,
                  cursorImageSize: resolved.image.size,
                  hotspot: resolved.hotspot
              ),
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(canvas.width),
                  pixelsHigh: Int(canvas.height),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            FileHandle.standardError.write(Data("cursor-check: 准备失败\n".utf8))
            exit(1)
        }

        bitmap.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(origin: .zero, size: canvas)

        OverlayRenderer.drawScreenContent(screenImage, in: rect, mode: fitMode)

        let fitted = OverlayRenderer.fittedRect(contentSize: screenSize, in: rect, mode: fitMode)
        let expectedTip = NSPoint(
            x: fitted.minX + (markerInImage.x / screenSize.width) * fitted.width,
            y: fitted.maxY - (markerInImage.y / screenSize.height) * fitted.height
        )

        resolved.image.draw(in: cursorFrame)

        // 期望落点画个空心圆，便于肉眼核对
        NSColor.systemBlue.setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: expectedTip.x - 14, y: expectedTip.y - 14, width: 28, height: 28))
        circle.lineWidth = 3
        circle.stroke()

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("cursor-check: 无法编码 PNG\n".utf8))
            exit(1)
        }
        try? data.write(to: URL(fileURLWithPath: outputPath))

        // 由算出的 frame 反推尖端（按热点在图像内的位置），与期望值对比
        let tipFromFrame = NSPoint(
            x: cursorFrame.minX + resolved.hotspot.x / resolved.image.size.width * cursorFrame.width,
            y: cursorFrame.maxY - resolved.hotspot.y / resolved.image.size.height * cursorFrame.height
        )
        print("cursor-check: \(outputPath)")
        print("  指针图像 \(resolved.image.size) 热点 \(resolved.hotspot)")
        print("  指针 frame \(cursorFrame)")
        print("  反推尖端 \(tipFromFrame) 期望 \(expectedTip)")
        print("  误差 dx=\(tipFromFrame.x - expectedTip.x) dy=\(tipFromFrame.y - expectedTip.y)")
        exit(0)
    }

    private static func render(to outputPath: String, live: Bool) {
        let arguments = CommandLine.arguments
        var config = OverlayConfig()
        config.text = "欢迎来到直播间\n关注不迷路 ✨"
        config.backgroundEnabled = true
        if live {
            config.liveMode = true
            if arguments.contains("--transparent") {
                // 窗口采集方案：无底色，窗口完全透明
                config.liveChromaKeyEnabled = false
            }
            if arguments.contains("--composite") {
                // 画面合成：用一张合成出来的“屏幕画面”验证适配与叠加
                config.liveComposeMode = .screenComposite
                config.liveChromaKeyEnabled = false
                if arguments.contains("--fit-fill") {
                    config.liveFitMode = .fill
                } else if arguments.contains("--fit-stretch") {
                    config.liveFitMode = .stretch
                }
            }
            if arguments.contains("--chroma") {
                config.liveComposeMode = .chromaKey
                config.liveChromaKeyEnabled = true
            }
        }

        // 直播模式渲染的是整块画面，预览时按 960×540 出图。
        let size = live
            ? NSSize(width: 960, height: 540)
            : OverlayRenderer.contentSize(for: config)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            FileHandle.standardError.write(Data("preview: 无法创建位图上下文\n".utf8))
            exit(1)
        }

        bitmap.size = size
        context.imageInterpolation = .high

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(origin: .zero, size: size)
        if live {
            switch config.liveComposeMode {
            case .screenComposite:
                // 用一张假“屏幕画面”验证合成：适配方式 + 文字叠加
                OverlayRenderer.drawScreenContent(syntheticScreenImage(), in: rect, mode: config.liveFitMode)
                OverlayRenderer.drawLiveText(config, in: rect)
            case .chromaKey:
                OverlayRenderer.drawLive(config, in: rect)
            }
        } else {
            OverlayRenderer.draw(config, in: rect)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("preview: 无法编码 PNG\n".utf8))
            exit(1)
        }

        do {
            try data.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            FileHandle.standardError.write(Data("preview: 写入失败 \(error)\n".utf8))
            exit(1)
        }

        print("preview: \(outputPath) \(Int(size.width))x\(Int(size.height)) live=\(live) mode=\(config.liveComposeMode.rawValue) fit=\(config.liveFitMode.rawValue)")
    }

    /// 生成一张假的“物理屏画面”，用来验证画面合成的适配与叠加（真机上是实时采集）。
    /// `marker` 是图像坐标（左上原点）下的十字标记位置，用于核对指针落点。
    private static func syntheticScreenImage(marker: NSPoint? = nil) -> CGImage? {
        let width = 1710
        let height = 1112
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)

        NSColor(white: 0.20, alpha: 1).setFill()
        bounds.fill()
        NSColor.systemRed.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 10, dy: 10))
        border.lineWidth = 20
        border.stroke()

        let center = NSAttributedString(
            string: "你的屏幕画面",
            attributes: [
                .font: NSFont.systemFont(ofSize: 110, weight: .bold),
                .foregroundColor: NSColor(white: 0.85, alpha: 1)
            ]
        )
        let centerSize = center.size()
        center.draw(at: NSPoint(x: bounds.midX - centerSize.width / 2, y: bounds.midY - centerSize.height / 2))

        let markers: [(String, NSPoint)] = [
            ("左上", NSPoint(x: 30, y: bounds.maxY - 120)),
            ("右上", NSPoint(x: bounds.maxX - 160, y: bounds.maxY - 120)),
            ("左下", NSPoint(x: 30, y: 40)),
            ("右下", NSPoint(x: bounds.maxX - 160, y: 40))
        ]
        for (text, point) in markers {
            NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 56, weight: .semibold),
                    .foregroundColor: NSColor.systemYellow
                ]
            ).draw(at: point)
        }

        if let marker {
            // 图像坐标为左上原点，绘制用的坐标是左下原点，需要翻转
            let point = NSPoint(x: marker.x, y: bounds.maxY - marker.y)
            NSColor.systemBlue.setStroke()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: point.x - 40, y: point.y))
            cross.line(to: NSPoint(x: point.x + 40, y: point.y))
            cross.move(to: NSPoint(x: point.x, y: point.y - 40))
            cross.line(to: NSPoint(x: point.x, y: point.y + 40))
            cross.lineWidth = 6
            cross.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}
