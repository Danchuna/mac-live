import AppKit
import SwiftUI

/// 原生 macOS 设置界面：文字 / 样式 / 直播 / 预设 四个分页。
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var liveStatus = LiveModeStatus.shared

    private static let fontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            TabView {
                textTab
                    .tabItem { Label("文字", systemImage: "textformat") }
                styleTab
                    .tabItem { Label("样式", systemImage: "paintbrush") }
                presetTab
                    .tabItem { Label("预设", systemImage: "bookmark") }
                liveTab
                    .tabItem { Label("直播", systemImage: "dot.radiowaves.left.and.right") }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: - 顶部状态栏

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Toggle("显示", isOn: $store.config.isVisible)
                    .help("临时隐藏/显示悬浮文字")

                Toggle("编辑模式", isOn: $store.config.editingMode)
                    .disabled(store.config.isLocked)
                    .help("打开后悬浮文字可以直接拖动定位；关闭后鼠标穿透，不会影响下面直播软件/游戏的操作")

                Toggle("锁定位置", isOn: $store.config.isLocked)
                    .help("锁定后悬浮窗不可拖动、鼠标穿透，避免直播过程中被误拖动；文字内容仍可正常编辑")

                Spacer()

                Button("重置位置") {
                    OverlayController.shared.resetPosition()
                }
                .disabled(store.config.isLocked)
                .help(store.config.isLocked ? "已锁定位置，解锁后可重置" : "把悬浮文字放回屏幕顶部中间")
            }

            if store.config.isLocked {
                Label("已锁定位置：悬浮窗不可拖动，鼠标会穿透到下层应用。", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 文字

    private var textTab: some View {
        Form {
            Section("文字内容") {
                TextEditor(text: $store.config.text)
                    .font(.system(size: 14))
                    .frame(minHeight: 96)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Text("回车换行即可显示多行文字。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("字体") {
                Picker("字体", selection: $store.config.fontFamily) {
                    Text("系统默认").tag(OverlayConfig.systemFontFamily)
                    Divider()
                    ForEach(Self.fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                Picker("字重", selection: $store.config.fontWeight) {
                    ForEach(OverlayFontWeight.allCases) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }

                sliderRow("字号", value: $store.config.fontSize, range: 12...200, format: "%.0f", suffix: "pt")
                sliderRow("字间距", value: $store.config.letterSpacing, range: -5...30, format: "%.1f")
                sliderRow("行距", value: $store.config.lineSpacing, range: 0...40, format: "%.0f")

                Picker("对齐", selection: $store.config.alignment) {
                    ForEach(OverlayTextAlignment.allCases) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 样式

    private var styleTab: some View {
        Form {
            Section("文字与整体") {
                ColorPicker("文字颜色", selection: colorBinding(\.textColor), supportsOpacity: true)
                sliderRow("整体透明度", value: $store.config.opacity, range: 0.05...1, format: "%.2f")
            }

            Section("描边") {
                Toggle("启用描边", isOn: $store.config.strokeEnabled)
                if store.config.strokeEnabled {
                    sliderRow("描边宽度", value: $store.config.strokeWidth, range: 0.5...12, format: "%.1f", suffix: "pt")
                    ColorPicker("描边颜色", selection: colorBinding(\.strokeColor), supportsOpacity: true)
                }
            }

            Section("阴影") {
                Toggle("启用阴影", isOn: $store.config.shadowEnabled)
                if store.config.shadowEnabled {
                    sliderRow("模糊", value: $store.config.shadowRadius, range: 0...20, format: "%.0f")
                    sliderRow("水平偏移", value: $store.config.shadowOffsetX, range: -20...20, format: "%.0f")
                    sliderRow("垂直偏移", value: $store.config.shadowOffsetY, range: -20...20, format: "%.0f")
                    ColorPicker("阴影颜色", selection: colorBinding(\.shadowColor), supportsOpacity: true)
                }
            }

            Section("背景底板") {
                Toggle("启用背景", isOn: $store.config.backgroundEnabled)
                if store.config.backgroundEnabled {
                    ColorPicker("背景颜色", selection: colorBinding(\.backgroundColor), supportsOpacity: true)
                    sliderRow("内边距", value: $store.config.backgroundPadding, range: 0...60, format: "%.0f")
                    sliderRow("圆角", value: $store.config.cornerRadius, range: 0...40, format: "%.0f")
                }
            }

            Section("窗口") {
                Picker("置顶层级", selection: $store.config.windowLevel) {
                    ForEach(OverlayWindowLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Text("悬浮窗会出现在所有桌面空间并覆盖全屏应用，方便被直播软件采集。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 预设

    private var presetTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文案预设")
                    .font(.headline)
                Spacer()
                Button {
                    store.config.presets.append(TextPreset(name: "预设 \(store.config.presets.count + 1)", text: store.config.text))
                } label: {
                    Label("从当前文字新建", systemImage: "plus")
                }
            }

            if store.config.presets.isEmpty {
                Text("还没有预设。先写好一段文案，再点右上角「从当前文字新建」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach($store.config.presets) { $preset in
                    HStack(spacing: 10) {
                        TextField("名称", text: $preset.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)

                        Text(preset.text.replacingOccurrences(of: "\n", with: " "))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("应用") {
                            store.config.text = preset.text
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            store.config.presets.removeAll { $0.id == preset.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除该预设")
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 240)
        }
        .padding(16)
    }

    // MARK: - 直播模式

    private var liveTab: some View {
        Form {
            Section("直播模式") {
                Toggle("开启直播模式（只有观众看得到）", isOn: $store.config.liveMode)

                Text("开启后文字会搬到一块系统虚拟屏上：你自己的屏幕完全看不到它；直播软件从这块屏取画面给观众。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                liveStatusRow
            }

            Section("合成方式") {
                Picker("方式", selection: $store.config.liveComposeMode) {
                    ForEach(LiveComposeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Text(store.config.liveComposeMode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.config.liveComposeMode == .screenComposite {
                    screenPermissionStatus

                    Picker("适配方式", selection: $store.config.liveFitMode) {
                        ForEach(LiveFitMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("帧率", selection: $store.config.liveFrameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }

                    Toggle("画面里隐藏本 App 窗口", isOn: $store.config.liveHideOwnWindows)
                        .help("打开时观众看不到这个设置窗口；关掉则和普通录屏一样会被看到")

                    Text("说明：屏幕不动时画面本来就不会变（系统只在画面有变化时投递新帧），这是正常的；鼠标指针由本 App 实时绘制，会一直跟随。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("虚拟屏") {
                Picker("分辨率", selection: resolutionBinding) {
                    ForEach(Self.resolutions, id: \.self) { resolution in
                        Text(resolution).tag(resolution)
                    }
                }
                .disabled(store.config.liveMode)

                Text("建议与直播输出分辨率一致。画面合成方式下，这块屏的画面就是观众看到的内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.config.liveComposeMode == .chromaKey {
                Section("抠像底色") {
                    Toggle("使用纯色底（绿幕抠像）", isOn: $store.config.liveChromaKeyEnabled)

                    if store.config.liveChromaKeyEnabled {
                        ColorPicker("底色", selection: colorBinding(\.liveChromaKeyColor), supportsOpacity: false)

                        Text("绿幕方式下文字、描边、底板按不透明渲染，避免和底色混色被一起扣掉；半透明阴影建议关闭。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("文字位置") {
                anchorGrid
                sliderRow("水平偏移", value: $store.config.liveOffsetX, range: -1200...1200, format: "%.0f")
                sliderRow("垂直偏移", value: $store.config.liveOffsetY, range: -1200...1200, format: "%.0f")
            }

            Section("画面预览") {
                LivePreviewView(config: store.config, screenImage: liveStatus.latestFrame)
            }

            Section("直播软件接线") {
                Text(Self.instructions(for: store.config))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// 屏幕录制权限状态与申请入口。
    @ViewBuilder
    private var screenPermissionStatus: some View {
        if liveStatus.hasScreenPermission {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: liveStatus.isCapturing ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(liveStatus.isCapturing ? Color.green : Color.secondary)
                Text(liveStatus.isCapturing
                     ? "屏幕采集运行中\(liveStatus.capturedFrameSize.map { "（\($0)）" } ?? "")"
                     : "已获得屏幕录制权限，开启直播模式后开始采集。")
            }
            .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("需要「屏幕录制」权限：授权后请重启本 App。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                HStack(spacing: 8) {
                    Button("申请权限") {
                        ScreenCompositeStream.requestPermission()
                        OverlayController.shared.reapplyLive()
                    }
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("重新检测") {
                        OverlayController.shared.reapplyLive()
                    }
                }
                .controlSize(.small)

                Text("提示：本 App 重新构建/更新后，「屏幕录制」授权会失效，需要把本 App 从列表里移除后重新添加一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func instructions(for config: OverlayConfig) -> String {
        switch (config.liveComposeMode, config.liveChromaKeyEnabled) {
        case (.screenComposite, _):
            return """
            1. 直播软件里添加「显示器采集 / 屏幕采集」，选择 “\(OverlayController.virtualDisplayName)”。
            2. 把它铺满画布，作为唯一的整屏画面来源（原来的显示器采集可以删掉了）。
            3. 不需要任何抠像 / 色度键，观众看到的就是你的屏幕 + 悬浮文字。
            """
        case (.chromaKey, true):
            return """
            1. 直播软件里添加「显示器采集 / 屏幕采集」，选择 “\(OverlayController.virtualDisplayName)”。
            2. 给这个采集源加「色度键 / 抠像」滤镜，颜色选与上面底色一致（默认纯绿）。
            3. 把它放在游戏 / 桌面画面之上。
            """
        case (.chromaKey, false):
            return """
            1. 直播软件里添加「窗口采集」，在窗口列表里选 “mac-live”（可能显示为进程名 mac-live）。
            2. 把它铺满画布，放到游戏 / 桌面画面之上。
            3. 文字位置用上面的九宫格锚点和偏移调整即可，不需要在软件里拖。
            注：若画面出现黑底方块，说明该软件不支持透明窗口，请改用「画面合成」或打开绿幕底色。
            """
        }
    }

    private var liveStatusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: liveStatus.isVirtualDisplayReady ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(liveStatus.isVirtualDisplayReady ? Color.green : Color.secondary)
            if let name = liveStatus.virtualDisplayName, let size = liveStatus.virtualDisplaySize {
                Text("虚拟屏已就绪：\(name)（\(size)），在采集软件的显示器列表里选它。")
            } else if let error = liveStatus.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text("尚未创建虚拟屏，打开上面的开关即可。")
            }
        }
        .font(.caption)
    }

    private var anchorGrid: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                ForEach(LiveAnchor.grid, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row) { anchor in
                            anchorButton(anchor)
                        }
                    }
                }
            }
            Text("选择文字在画面里的落点，再用下面的偏移微调。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func anchorButton(_ anchor: LiveAnchor) -> some View {
        let selected = store.config.liveAnchor == anchor
        return Button {
            store.config.liveAnchor = anchor
        } label: {
            Text(anchor.shortName)
                .font(.caption)
                .frame(width: 36, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(anchor.displayName)
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: { "\(Int(store.config.virtualDisplayWidth))x\(Int(store.config.virtualDisplayHeight))" },
            set: { newValue in
                let parts = newValue.split(separator: "x").compactMap { Double($0) }
                guard parts.count == 2 else { return }
                store.config.virtualDisplayWidth = parts[0]
                store.config.virtualDisplayHeight = parts[1]
            }
        )
    }

    private static let resolutions = ["1280x720", "1920x1080", "2560x1440"]

    // MARK: - 组件

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        suffix: String = ""
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue) + suffix)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<OverlayConfig, ColorValue>) -> Binding<Color> {
        Binding(
            get: { store.config[keyPath: keyPath].color },
            set: { store.config[keyPath: keyPath] = ColorValue($0) }
        )
    }
}
