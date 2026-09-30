import SwiftUI

/// 直播画面预览：显示直播软件最终采到的样子。
/// - 画面合成方式：直接显示“你的屏幕 + 文字”的合成结果；
/// - 绿幕方式：显示纯色底 + 文字（纯色底会被色度键扣掉）。
struct LivePreviewView: View {
    let config: OverlayConfig
    var screenImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image = OverlayRenderer.livePreviewImage(for: config, pixelWidth: 640, screenImage: screenImage) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.black.frame(height: 140)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        switch config.liveComposeMode {
        case .screenComposite:
            return screenImage == nil
                ? "示意预览：开启直播模式后这里会显示你屏幕画面 + 文字的实时合成结果。"
                : "实时预览：观众看到的就是这个（你的屏幕画面 + 悬浮文字）。"
        case .chromaKey:
            return config.liveChromaKeyEnabled
                ? "纯色底会被色度键扣掉，只留下文字；观众那边看到的是下面的游戏画面。"
                : "棋盘格代表透明区域（观众那边会看到下面的游戏画面）。"
        }
    }
}
