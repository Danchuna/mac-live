import AppKit

/// 负责把 `OverlayConfig` 变成尺寸计算与最终绘制结果，设置界面和悬浮窗共用同一套度量。
enum OverlayRenderer {
    static let minimumContentSize = NSSize(width: 120, height: 48)

    /// 测量文字时使用的极大宽度：只有用户手动换行才会产生多行。
    private static let measurementWidth: CGFloat = 100_000

    static func font(for config: OverlayConfig) -> NSFont {
        let size = CGFloat(config.fontSize)
        if config.fontFamily.isEmpty {
            return NSFont.systemFont(ofSize: size, weight: config.fontWeight.appKitWeight)
        }
        if let font = NSFontManager.shared.font(
            withFamily: config.fontFamily,
            traits: [],
            weight: config.fontWeight.fontManagerWeight,
            size: size
        ) {
            return font
        }
        if let font = NSFont(name: config.fontFamily, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: config.fontWeight.appKitWeight)
    }

    static func attributedString(for config: OverlayConfig, forceOpaque: Bool = false) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = config.alignment.nsAlignment
        paragraph.lineSpacing = CGFloat(config.lineSpacing)
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: config),
            .foregroundColor: config.textColor.nsColor(opaque: forceOpaque),
            .paragraphStyle: paragraph
        ]

        if config.letterSpacing != 0 {
            attributes[.kern] = CGFloat(config.letterSpacing)
        }

        if config.strokeEnabled, config.strokeWidth > 0, config.fontSize > 0 {
            // NSAttributedString 的 strokeWidth 是字号百分比，负值表示「填充 + 描边」。
            attributes[.strokeWidth] = -CGFloat(config.strokeWidth) / CGFloat(config.fontSize) * 100
            attributes[.strokeColor] = config.strokeColor.nsColor(opaque: forceOpaque)
        }

        if config.shadowEnabled {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = CGFloat(config.shadowRadius)
            // AppKit 坐标 y 轴向上，向下偏移需要取负。
            shadow.shadowOffset = NSSize(
                width: CGFloat(config.shadowOffsetX),
                height: -CGFloat(config.shadowOffsetY)
            )
            shadow.shadowColor = config.shadowColor.nsColor
            attributes[.shadow] = shadow
        }

        return NSAttributedString(string: config.text, attributes: attributes)
    }

    static func textSize(for config: OverlayConfig) -> NSSize {
        let attributed = attributedString(for: config)
        let rect = attributed.boundingRect(
            with: NSSize(width: measurementWidth, height: measurementWidth),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// 阴影会溢出文字矩形，需要预留透明边距，避免被视图裁剪。
    static func shadowPadding(for config: OverlayConfig) -> CGFloat {
        guard config.shadowEnabled else { return 0 }
        let offset = max(abs(CGFloat(config.shadowOffsetX)), abs(CGFloat(config.shadowOffsetY)))
        return ceil(CGFloat(config.shadowRadius) * 2 + offset + 2)
    }

    static func contentSize(for config: OverlayConfig) -> NSSize {
        let text = textSize(for: config)
        let padding = shadowPadding(for: config)
            + (config.backgroundEnabled ? max(CGFloat(config.backgroundPadding), 0) : 0)
        return NSSize(
            width: max(text.width + padding * 2, minimumContentSize.width).rounded(),
            height: max(text.height + padding * 2, minimumContentSize.height).rounded()
        )
    }

    static func draw(_ config: OverlayConfig, in bounds: NSRect) {
        let text = textSize(for: config)
        let textRect = NSRect(
            x: (bounds.width - text.width) / 2,
            y: (bounds.height - text.height) / 2,
            width: text.width,
            height: text.height
        )

        if config.backgroundEnabled, config.backgroundPadding >= 0 {
            let padding = CGFloat(config.backgroundPadding)
            let backgroundRect = textRect.insetBy(dx: -padding, dy: -padding)
            let radius = min(CGFloat(config.cornerRadius), backgroundRect.height / 2)
            let path = NSBezierPath(roundedRect: backgroundRect, xRadius: radius, yRadius: radius)
            config.backgroundColor.nsColor.setFill()
            path.fill()
        }

        attributedString(for: config).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    // MARK: - 直播模式（虚拟屏整屏画面）

    /// 按九宫格锚点 + 偏移算出文字矩形（AppKit 坐标，y 轴向上）。
    static func liveTextRect(for config: OverlayConfig, textSize text: NSSize, in bounds: NSRect) -> NSRect {
        var origin = NSPoint.zero
        switch config.liveAnchor.horizontal {
        case .leading: origin.x = bounds.minX
        case .center: origin.x = bounds.midX - text.width / 2
        case .trailing: origin.x = bounds.maxX - text.width
        }
        switch config.liveAnchor.vertical {
        case .top: origin.y = bounds.maxY - text.height
        case .center: origin.y = bounds.midY - text.height / 2
        case .bottom: origin.y = bounds.minY
        }
        // 数据里「下为正」，这里换算成 AppKit 的 y 轴向上。
        origin.x += CGFloat(config.liveOffsetX)
        origin.y -= CGFloat(config.liveOffsetY)
        return NSRect(x: origin.x, y: origin.y, width: text.width, height: text.height)
    }

    /// 直播画面里的文字绘制（不含底色）。
    ///
    /// 配置里的尺寸都以“画面像素”为单位，这里按 `bounds` 与画面宽度的比例换算，
    /// 因此同一份配置既能画到真实虚拟屏（比例 1），也能画成小尺寸预览图。
    /// `forceOpaque` 用于抠像：半透明像素会和底色混合被一起扣掉，需要按不透明画。
    static func drawLiveText(_ config: OverlayConfig, in bounds: NSRect, forceOpaque: Bool = false) {
        let factor = Double(bounds.width) / Double(max(config.virtualDisplayWidth, 1))
        let scaled = config.scaled(by: factor)

        let text = textSize(for: scaled)
        let textRect = liveTextRect(for: scaled, textSize: text, in: bounds)

        if scaled.backgroundEnabled, scaled.backgroundPadding >= 0 {
            let padding = CGFloat(scaled.backgroundPadding)
            let backgroundRect = textRect.insetBy(dx: -padding, dy: -padding)
            let radius = min(CGFloat(scaled.cornerRadius), backgroundRect.height / 2)
            let path = NSBezierPath(roundedRect: backgroundRect, xRadius: radius, yRadius: radius)
            scaled.backgroundColor.nsColor(opaque: forceOpaque).setFill()
            path.fill()
        }

        attributedString(for: scaled, forceOpaque: forceOpaque).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    /// 抠像模式的整屏绘制：铺满抠像底色 + 不透明文字。
    static func drawLive(_ config: OverlayConfig, in bounds: NSRect) {
        if config.liveChromaKeyEnabled {
            config.liveChromaKeyColor.nsColor.setFill()
            bounds.fill()
        }
        drawLiveText(config, in: bounds, forceOpaque: config.liveChromaKeyEnabled)
    }

    /// 按「等比适应 / 填满 / 拉伸」算出内容在画面里的落位。
    static func fittedRect(contentSize: NSSize, in bounds: NSRect, mode: LiveFitMode) -> NSRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return bounds }
        switch mode {
        case .stretch:
            return bounds
        case .fit, .fill:
            let horizontal = bounds.width / contentSize.width
            let vertical = bounds.height / contentSize.height
            let scale = mode == .fit ? min(horizontal, vertical) : max(horizontal, vertical)
            let size = NSSize(width: contentSize.width * scale, height: contentSize.height * scale)
            return NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    /// 生成直播画面预览图（离屏渲染），供设置界面显示“采集软件看到的样子”。
    ///
    /// - `screenImage`: 画面合成模式下的物理屏画面（最新一帧）；没有就画一个示意背景。
    static func livePreviewImage(for config: OverlayConfig, pixelWidth: Int, screenImage: CGImage? = nil) -> NSImage? {
        let ratio = config.virtualDisplayHeight / max(config.virtualDisplayWidth, 1)
        let pixelHeight = max(Int((Double(pixelWidth) * ratio).rounded()), 1)
        guard pixelWidth > 0, pixelHeight > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelWidth,
                  pixelsHigh: pixelHeight,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return nil
        }

        let size = NSSize(width: pixelWidth, height: pixelHeight)
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(origin: .zero, size: size)

        switch config.liveComposeMode {
        case .screenComposite:
            drawScreenContent(screenImage, in: bounds, mode: config.liveFitMode)
            drawLiveText(config, in: bounds)
        case .chromaKey:
            if !config.liveChromaKeyEnabled {
                // 透明模式用棋盘格表示透明区域，避免预览看起来像“黑底”。
                drawCheckerboard(in: bounds)
            }
            drawLive(config, in: bounds)
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    /// 画面合成模式：把物理屏画面按适配方式画进画面；没有真实画面时用示意背景代替。
    static func drawScreenContent(_ screenImage: CGImage?, in bounds: NSRect, mode: LiveFitMode) {
        guard let screenImage else {
            // 示意背景：渐变 + 提示，表示“这里是你原本的屏幕画面”
            NSColor(white: 0.16, alpha: 1).setFill()
            bounds.fill()
            let placeholder = NSAttributedString(
                string: "这里是你原本的屏幕画面\n（开启后由本 App 实时采集）",
                attributes: [
                    .font: NSFont.systemFont(ofSize: max(bounds.height * 0.045, 9)),
                    .foregroundColor: NSColor(white: 0.55, alpha: 1)
                ]
            )
            let textSize = placeholder.boundingRect(with: bounds.size, options: [.usesLineFragmentOrigin])
            placeholder.draw(
                with: NSRect(
                    x: bounds.midX - textSize.width / 2,
                    y: bounds.midY - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                ),
                options: [.usesLineFragmentOrigin]
            )
            return
        }

        let contentSize = NSSize(width: screenImage.width, height: screenImage.height)
        let rect = fittedRect(contentSize: contentSize, in: bounds, mode: mode)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        NSImage(cgImage: screenImage, size: contentSize).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawCheckerboard(in bounds: NSRect, cell: CGFloat = 12) {
        NSColor(white: 0.30, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: 0.22, alpha: 1).setFill()
        var row = 0
        var y = bounds.minY
        while y < bounds.maxY {
            var column = 0
            var x = bounds.minX
            while x < bounds.maxX {
                if (row + column) % 2 == 1 {
                    NSRect(x: x, y: y, width: cell, height: cell).intersection(bounds).fill()
                }
                x += cell
                column += 1
            }
            y += cell
            row += 1
        }
    }
}

extension ColorValue {
    /// 抠像模式下会与底色混合，需要强制不透明。
    func nsColor(opaque: Bool) -> NSColor {
        opaque ? NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) : nsColor
    }
}
