import AppKit
import SwiftUI

/// 以 sRGB 分量保存颜色，便于用 UserDefaults(JSON) 持久化。
struct ColorValue: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent),
            alpha: Double(ns.alphaComponent)
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let white = ColorValue(red: 1, green: 1, blue: 1)
    static let black = ColorValue(red: 0, green: 0, blue: 0)
}

enum OverlayFontWeight: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold, heavy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: return "常规"
        case .medium: return "中等"
        case .semibold: return "半粗"
        case .bold: return "加粗"
        case .heavy: return "特粗"
        }
    }

    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }

    /// NSFontManager 使用 0...15 的字重刻度，5 为常规、9 为加粗。
    var fontManagerWeight: Int {
        switch self {
        case .regular: return 5
        case .medium: return 6
        case .semibold: return 8
        case .bold: return 9
        case .heavy: return 11
        }
    }
}

enum OverlayTextAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leading: return "左对齐"
        case .center: return "居中"
        case .trailing: return "右对齐"
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

enum OverlayWindowLevel: String, Codable, CaseIterable, Identifiable {
    case floating, screenSaver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floating: return "普通置顶"
        case .screenSaver: return "强制置顶（更高层级）"
        }
    }

    var nsLevel: NSWindow.Level {
        switch self {
        case .floating: return .floating
        case .screenSaver: return .screenSaver
        }
    }
}

/// 可一键切换的文案预设。
struct TextPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var text: String = ""
}

/// 直播模式的合成方式。
enum LiveComposeMode: String, Codable, CaseIterable, Identifiable {
    /// App 采集物理屏 + 叠上文字，输出一整幅画面到虚拟屏（不需要任何抠像，任意采集软件可用）。
    case screenComposite
    /// 只把纯色底 + 文字放到虚拟屏，交给直播软件色度键抠像。
    case chromaKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screenComposite: return "画面合成（原画面 + 文字，推荐）"
        case .chromaKey: return "纯色抠像（绿幕，需软件支持）"
        }
    }

    var summary: String {
        switch self {
        case .screenComposite:
            return "用屏幕采集把“你的屏幕 + 悬浮文字”合成成一整幅画面，输出到虚拟屏。直播软件只要「显示器采集」选这块屏即可，不需要抠像，任何软件都能用；代价是需要给本 App 授权「屏幕录制」。"
        case .chromaKey:
            return "虚拟屏上铺一块纯色（默认纯绿），文字画在上面。直播软件需要有「色度键 / 抠像」滤镜才能把底色扣掉。"
        }
    }
}

/// 画面合成时，屏幕画面如何适配到直播画面。
enum LiveFitMode: String, Codable, CaseIterable, Identifiable {
    case fit
    case fill
    case stretch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: return "等比适应（留黑边）"
        case .fill: return "填满（裁掉多余）"
        case .stretch: return "拉伸铺满"
        }
    }
}

/// 直播画面里文字的摆放位置（九宫格锚点）。
enum LiveAnchor: String, Codable, CaseIterable, Identifiable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    var id: String { rawValue }

    enum Horizontal { case leading, center, trailing }
    enum Vertical { case top, center, bottom }

    var displayName: String {
        switch self {
        case .topLeading: return "左上"
        case .top: return "顶部居中"
        case .topTrailing: return "右上"
        case .leading: return "左中"
        case .center: return "正中"
        case .trailing: return "右中"
        case .bottomLeading: return "左下"
        case .bottom: return "底部居中"
        case .bottomTrailing: return "右下"
        }
    }

    var shortName: String {
        switch self {
        case .topLeading: return "左上"
        case .top: return "上"
        case .topTrailing: return "右上"
        case .leading: return "左"
        case .center: return "中"
        case .trailing: return "右"
        case .bottomLeading: return "左下"
        case .bottom: return "下"
        case .bottomTrailing: return "右下"
        }
    }

    /// 3×3 网格，供设置界面按行列排布。
    static let grid: [[LiveAnchor]] = [
        [.topLeading, .top, .topTrailing],
        [.leading, .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing]
    ]

    var horizontal: Horizontal {
        switch self {
        case .topLeading, .leading, .bottomLeading: return .leading
        case .top, .center, .bottom: return .center
        case .topTrailing, .trailing, .bottomTrailing: return .trailing
        }
    }

    var vertical: Vertical {
        switch self {
        case .topLeading, .top, .topTrailing: return .top
        case .leading, .center, .trailing: return .center
        case .bottomLeading, .bottom, .bottomTrailing: return .bottom
        }
    }
}

/// 悬浮文字的全部可配置项。
struct OverlayConfig: Codable, Equatable {
    /// 用空字符串表示跟随系统字体。
    static let systemFontFamily = ""

    var text: String = "欢迎来到直播间 ✨"

    // 窗口行为
    var isVisible: Bool = true
    /// 编辑模式：可以拖动位置并接收鼠标事件；关闭后鼠标穿透。
    var editingMode: Bool = true
    /// 锁定位置：优先级高于编辑模式，锁定后既不能拖动也鼠标穿透。
    var isLocked: Bool = false
    var windowLevel: OverlayWindowLevel = .floating
    /// 悬浮窗左下角在屏幕坐标系中的位置，nil 表示使用默认位置。
    var origin: CGPoint?

    // 字体
    var fontFamily: String = "PingFang SC"
    var fontWeight: OverlayFontWeight = .semibold
    var fontSize: Double = 44
    var letterSpacing: Double = 1
    var lineSpacing: Double = 8
    var alignment: OverlayTextAlignment = .center
    var textColor: ColorValue = .white

    // 描边
    var strokeEnabled: Bool = true
    var strokeWidth: Double = 2.5
    var strokeColor: ColorValue = .black

    // 阴影
    var shadowEnabled: Bool = true
    var shadowRadius: Double = 5
    var shadowOffsetX: Double = 0
    var shadowOffsetY: Double = 3
    var shadowColor: ColorValue = ColorValue(red: 0, green: 0, blue: 0, alpha: 0.75)

    // 整体透明度
    var opacity: Double = 1

    // 背景底板
    var backgroundEnabled: Bool = false
    var backgroundColor: ColorValue = ColorValue(red: 0, green: 0, blue: 0, alpha: 0.45)
    var backgroundPadding: Double = 16
    var cornerRadius: Double = 14

    // 直播模式：把文字放到虚拟显示器上，自己的物理屏幕什么都不显示。
    var liveMode: Bool = false
    var virtualDisplayWidth: Double = 1920
    var virtualDisplayHeight: Double = 1080
    /// 画面合成：App 采集你的屏幕 + 叠上文字后输出到虚拟屏（免抠像，需要屏幕录制权限）。
    /// 绿幕：只把文字放到虚拟屏上，由直播软件自己抠像合成。
    var liveComposeMode: LiveComposeMode = .screenComposite
    /// 画面合成时，屏幕画面如何适配到直播画面。
    var liveFitMode: LiveFitMode = .fit
    /// 画面合成的采集帧率。
    var liveFrameRate: Int = 30
    /// 画面合成时把本 App 自己的窗口（设置面板）从画面里去掉。
    var liveHideOwnWindows: Bool = true
    /// 抠像底色：直播软件用色度键把这块纯色扣掉，只留下文字。
    var liveChromaKeyEnabled: Bool = true
    var liveChromaKeyColor: ColorValue = ColorValue(red: 0, green: 1, blue: 0)
    /// 文字在画面中的九宫格锚点。
    var liveAnchor: LiveAnchor = .bottom
    /// 相对锚点的偏移（右为正 / 下为正）。
    var liveOffsetX: Double = 0
    var liveOffsetY: Double = -120

    var presets: [TextPreset] = [
        TextPreset(name: "欢迎", text: "欢迎来到直播间 ✨"),
        TextPreset(name: "关注我", text: "点个关注不迷路"),
        TextPreset(name: "稍等", text: "主播马上回来～")
    ]

    /// 悬浮窗是否可以拖动 / 接收鼠标事件。锁定位置后一律不可交互。
    var isInteractive: Bool { editingMode && !isLocked }
}

extension OverlayConfig {
    /// 按比例缩放所有与尺寸相关的字段，用于画面预览等需要缩小的场景。
    func scaled(by scale: Double) -> OverlayConfig {
        guard scale != 1, scale > 0 else { return self }
        var copy = self
        copy.fontSize *= scale
        copy.letterSpacing *= scale
        copy.lineSpacing *= scale
        copy.strokeWidth *= scale
        copy.shadowRadius *= scale
        copy.shadowOffsetX *= scale
        copy.shadowOffsetY *= scale
        copy.backgroundPadding *= scale
        copy.cornerRadius *= scale
        copy.liveOffsetX *= scale
        copy.liveOffsetY *= scale
        return copy
    }
}
