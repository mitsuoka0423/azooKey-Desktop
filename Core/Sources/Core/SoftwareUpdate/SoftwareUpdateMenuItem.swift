import Foundation


/// 入力メニューの「アップデートを確認…」の項目に出す内容。
///
/// 項目はいつもメニューに入れておき、題と押せるかどうかだけを変える。
/// 隠した項目（`isHidden`）や打鍵のたびの書き換えは、IME と入力先の接続を切ることがあるため使わない。
public struct SoftwareUpdateMenuItem: Sendable, Equatable {
    public var title: String
    public var isEnabled: Bool

    public init(title: String, isEnabled: Bool) {
        self.title = title
        self.isEnabled = isEnabled
    }

    /// 更新の仕組みの今の状態
    public enum State: Sendable, Equatable {
        /// 公開鍵やフィードがなく、更新を確かめられない（手元のビルドなど）
        case unavailable
        /// 新しい版は見つかっていない
        case idle
        /// 定期の確認で新しい版が見つかった。`version` は表示用の版（例：1.0.42）
        case updateAvailable(version: String)
    }

    public static func make(for state: State) -> Self {
        switch state {
        case .unavailable:
            Self(title: "アップデートを確認…", isEnabled: false)
        case .idle:
            Self(title: "アップデートを確認…", isEnabled: true)
        case .updateAvailable(let version):
            if version.isEmpty {
                Self(title: "新しい版があります…", isEnabled: true)
            } else {
                Self(title: "新しい版があります（\(version)）…", isEnabled: true)
            }
        }
    }
}

/// Sparkle を動かすのに要る設定がそろっているかを確かめる。
public enum SoftwareUpdateConfiguration {
    /// Info.plist の `SUPublicEDKey` と `SUFeedURL` が両方入っているときだけ、更新の仕組みを動かす。
    /// 公開鍵はリリースのビルドでだけ入れるので、手元のビルドでは動かさない。
    public static func isAvailable(publicEDKey: String?, feedURL: String?) -> Bool {
        guard let publicEDKey, let feedURL else {
            return false
        }
        let key = publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let feed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // ビルド設定が展開されずに残った値（$(...)）は入っていないものとして扱う
        guard !key.isEmpty, !key.hasPrefix("$("), !feed.isEmpty, !feed.hasPrefix("$(") else {
            return false
        }
        return feed.hasPrefix("https://") || feed.hasPrefix("http://127.0.0.1") || feed.hasPrefix("http://localhost")
    }
}
