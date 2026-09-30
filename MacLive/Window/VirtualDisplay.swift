import AppKit
import CoreGraphics
import Darwin

/// 通过私有 API `CGVirtualDisplay`（CoreGraphics，macOS 10.15+）创建一块虚拟显示器。
///
/// 用途：直播模式下把悬浮文字放到这块“用户看不到”的屏幕上，
/// 直播软件采集这块屏就能得到纯文字画面，而自己的物理屏幕保持干净。
/// 这些类只在运行时存在、SDK 里没有头文件，因此用 Objective-C runtime 调用。
final class VirtualDisplay {
    enum Failure: LocalizedError {
        case unsupported
        case creationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "当前系统不支持创建虚拟显示器（CGVirtualDisplay 不可用）。"
            case .creationFailed(let reason):
                return "创建虚拟显示器失败：\(reason)"
            }
        }
    }

    private var displayObject: NSObject?
    private(set) var displayID: CGDirectDisplayID = 0
    let pixelWidth: Int
    let pixelHeight: Int
    let name: String

    /// 运行环境是否具备这些私有类。
    static var isSupported: Bool {
        let names = [
            "CGVirtualDisplayDescriptor",
            "CGVirtualDisplay",
            "CGVirtualDisplaySettings",
            "CGVirtualDisplayMode"
        ]
        return names.allSatisfy { NSClassFromString($0) != nil }
    }

    init(width: Int, height: Int, name: String) throws {
        guard Self.isSupported else { throw Failure.unsupported }
        self.pixelWidth = width
        self.pixelHeight = height
        self.name = name

        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type
        else {
            throw Failure.creationFailed("取不到 CGVirtualDisplay 相关类")
        }

        let descriptor = descriptorClass.init()
        descriptor.setValue(name, forKey: "name")
        descriptor.setValue(NSNumber(value: width), forKey: "maxPixelsWide")
        descriptor.setValue(NSNumber(value: height), forKey: "maxPixelsHigh")
        // 以 110 ppi 估算物理尺寸，数值不影响采集结果。
        descriptor.setValue(
            NSValue(size: NSSize(width: Double(width) / 110 * 25.4, height: Double(height) / 110 * 25.4)),
            forKey: "sizeInMillimeters"
        )
        descriptor.setValue(NSNumber(value: 0x1F1F), forKey: "serialNum")
        descriptor.setValue(NSNumber(value: 0x1F1F), forKey: "vendorID")
        descriptor.setValue(NSNumber(value: 0x1F1F), forKey: "productID")
        descriptor.setValue(NSValue(point: NSPoint(x: 0.68, y: 0.32)), forKey: "redPrimary")
        descriptor.setValue(NSValue(point: NSPoint(x: 0.26, y: 0.69)), forKey: "greenPrimary")
        descriptor.setValue(NSValue(point: NSPoint(x: 0.15, y: 0.06)), forKey: "bluePrimary")
        descriptor.setValue(NSValue(point: NSPoint(x: 0.3127, y: 0.3290)), forKey: "whitePoint")

        guard let mode = Self.makeMode(class: modeClass, width: width, height: height) else {
            throw Failure.creationFailed("创建显示模式失败")
        }

        let settings = settingsClass.init()
        settings.setValue(NSNumber(value: 1), forKey: "hiDPI")
        settings.setValue([mode], forKey: "modes")

        let alloc = displayClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        guard let display = alloc?.perform(NSSelectorFromString("initWithDescriptor:"), with: descriptor)?
            .takeUnretainedValue() as? NSObject
        else {
            throw Failure.creationFailed("初始化 CGVirtualDisplay 失败")
        }

        _ = display.perform(NSSelectorFromString("applySettings:"), with: settings)
        displayObject = display
        displayID = (display.value(forKey: "displayID") as? NSNumber)?.uint32Value ?? 0

        guard displayID != 0 else {
            release()
            throw Failure.creationFailed("未拿到 displayID")
        }
    }

    /// 释放后虚拟屏立即从系统中消失。
    func release() {
        displayObject = nil
        displayID = 0
    }

    /// 虚拟屏对应的 NSScreen（创建后系统需要一点时间才会注册，需要轮询）。
    var screen: NSScreen? {
        guard displayID != 0 else { return nil }
        return NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == displayID
        }
    }

    // MARK: - runtime 调用

    private typealias MsgSendModeInit = @convention(c) (AnyObject, Selector, Int32, Int32, Double) -> AnyObject?

    /// `-[CGVirtualDisplayMode initWithWidth:height:refreshRate:]` 有多个基础类型参数，不能用 perform 调用。
    private static func makeMode(class modeClass: NSObject.Type, width: Int, height: Int) -> AnyObject? {
        guard let alloc = modeClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "objc_msgSend") else { return nil }
        let send = unsafeBitCast(symbol, to: MsgSendModeInit.self)
        return send(alloc as AnyObject, NSSelectorFromString("initWithWidth:height:refreshRate:"), Int32(width), Int32(height), 60)
    }
}
