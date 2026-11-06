import Foundation

/// キーボードショートカットを表す構造体
public struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: KeyEventCore.ModifierFlag

    public init(key: String, modifiers: KeyEventCore.ModifierFlag) {
        self.key = key
        self.modifiers = modifiers
    }

    /// デフォルトのショートカット（Control+S）
    public static let defaultTransformShortcut = KeyboardShortcut(
        key: "s",
        modifiers: .control
    )

    /// 音声入力を始める・止める既定のショートカット（Control+Shift+D）
    public static let defaultVoiceInputShortcut = KeyboardShortcut(
        key: "d",
        modifiers: [.control, .shift]
    )

    /// キーイベントがこのショートカットに当たるか。
    /// - Parameters:
    ///   - charactersIgnoringModifiers: `NSEvent.charactersIgnoringModifiers`（Shift で大文字になっていてもよい）
    ///   - modifiers: 押されている修飾キー
    public func matches(charactersIgnoringModifiers: String?, modifiers: KeyEventCore.ModifierFlag) -> Bool {
        guard let charactersIgnoringModifiers, !charactersIgnoringModifiers.isEmpty else {
            return false
        }
        return charactersIgnoringModifiers.lowercased() == self.key.lowercased() && modifiers == self.modifiers
    }

    /// 表示用の文字列（例: "⌃S"）
    public var displayString: String {
        var result = ""

        if modifiers.contains(.control) {
            result += "⌃"
        }
        if modifiers.contains(.option) {
            result += "⌥"
        }
        if modifiers.contains(.shift) {
            result += "⇧"
        }
        if modifiers.contains(.command) {
            result += "⌘"
        }

        result += key.uppercased()
        return result
    }
}

protocol KeyboardShortcutConfigItem: ConfigItem<KeyboardShortcut> {
    static var `default`: KeyboardShortcut { get }
}

extension KeyboardShortcutConfigItem {
    public var value: KeyboardShortcut {
        get {
            guard let data = Config.data(forKey: Self.key) else {
                return Self.default
            }
            do {
                let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)
                return decoded
            } catch {
                return Self.default
            }
        }
        nonmutating set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                Config.set(encoded, forKey: Self.key)
            } catch {
                // エンコード失敗時は何もしない
            }
        }
    }
}

extension Config {
    /// いい感じ変換のキーボードショートカット
    public struct TransformShortcut: KeyboardShortcutConfigItem {
        public init() {}

        public static let `default`: KeyboardShortcut = .defaultTransformShortcut
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.transform_shortcut"
    }
}

extension Config {
    /// 音声入力を始める・止めるキーボードショートカット
    public struct VoiceInputShortcut: KeyboardShortcutConfigItem {
        public init() {}

        public static let `default`: KeyboardShortcut = .defaultVoiceInputShortcut
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.voice_input_shortcut"
    }
}
