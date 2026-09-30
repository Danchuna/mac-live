import Combine
import Foundation

/// 全局配置存储：内存中发布变更，同时写入 UserDefaults。
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var config: OverlayConfig {
        didSet { persist() }
    }

    private static let storageKey = "maclive.overlay.config.v1"

    private init() {
        config = Self.load()
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func resetToDefaults() {
        config = OverlayConfig()
    }

    private static func load() -> OverlayConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return OverlayConfig()
        }
        if let decoded = try? JSONDecoder().decode(OverlayConfig.self, from: data) {
            return decoded
        }
        // 兼容旧版本存档：合成出来的 Decodable 遇到新增字段会整体解码失败，
        // 这里把已保存的 JSON 覆盖到默认值上，缺失字段自动用默认值补齐。
        return mergedWithDefaults(data) ?? OverlayConfig()
    }

    private static func mergedWithDefaults(_ stored: Data) -> OverlayConfig? {
        guard var defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(OverlayConfig())) as? [String: Any],
              let stored = try? JSONSerialization.jsonObject(with: stored) as? [String: Any]
        else {
            return nil
        }
        defaults.merge(stored) { _, newValue in newValue }
        guard let data = try? JSONSerialization.data(withJSONObject: defaults) else { return nil }
        return try? JSONDecoder().decode(OverlayConfig.self, from: data)
    }
}
