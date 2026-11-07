import Foundation

/// 聞き取りピル（VoicePill）に出す内容。`nil` のときはピルを出さない
public struct VoicePillModel: Sendable, Equatable {
    /// マイク（`VoicePill.Mic`）の見た目
    public enum Mic: Sendable, Equatable {
        /// 赤い丸。聞いている
        case listening
        /// 灰色の丸。もう聞いていない
        case finishing
        /// オレンジの丸に斜線。使えない
        case failed
    }

    /// 声の揺れ（`VoicePill.Level`）の見た目
    public enum Level: Sendable, Equatable {
        /// 声がない。灰色の点を 3 つ
        case silent
        /// 声がある。0〜1 の大きさで赤い棒の高さを変える
        case voice(Double)
    }

    public var mic: Mic
    /// 状態の文言（`VoicePill.Label`）
    public var label: String
    /// マイクの輪が脈打つか（動きを減らす設定ではしない）
    public var isPulsing: Bool
    /// 声の揺れ。`nil` なら出さない
    public var level: Level?
    /// 声の揺れを動かすか（動きを減らす設定では、棒の高さを固定する）
    public var animatesLevel: Bool
    /// 止め方（`VoicePill.Keys`）。`nil` なら出さない
    public var keys: Keys?

    /// 止め方の案内。「⌃⇧D 確定 ・ esc 取消」
    public struct Keys: Sendable, Equatable {
        public var commitKey: String
        public var commitLabel: String = "確定"
        public var cancelKey: String = "esc"
        public var cancelLabel: String = "取消"

        public init(commitKey: String) {
            self.commitKey = commitKey
        }
    }
}

/// 聞き取りピルの表示を決める。時間と声の大きさを受け取り、出す内容を返す
public struct VoicePillPresenter: Sendable, Equatable {
    /// 声がないまま、止め方を出すまでの長さ
    public static let silenceBeforeKeys: TimeInterval = 2
    /// 失敗を出しておく長さ
    public static let failureDuration: TimeInterval = 3
    /// これより大きい音（0〜1）を声とみなす
    public static let voiceThreshold: Double = 0.15

    private var listeningStartedAt: TimeInterval?
    private var lastVoiceAt: TimeInterval?
    private var level: Double = 0
    private var failure: (message: String, at: TimeInterval)?
    /// 認識モデルをダウンロードしている
    private var isPreparingModel = false

    public init() {}

    /// 聞き取りを始めた
    public mutating func start(at time: TimeInterval) {
        self.listeningStartedAt = time
        self.lastVoiceAt = nil
        self.level = 0
        self.failure = nil
        self.isPreparingModel = false
    }

    /// 認識モデルのダウンロードを始めた・終えた。終えたら、声がない時間はそこから数える
    public mutating func setPreparingModel(_ preparing: Bool, at time: TimeInterval) {
        if self.isPreparingModel, !preparing {
            self.listeningStartedAt = time
        }
        self.isPreparingModel = preparing
    }

    /// 録音中の音の大きさ（0〜1）を受け取る
    public mutating func updateLevel(_ level: Double, at time: TimeInterval) {
        self.level = min(max(level, 0), 1)
        if self.level >= Self.voiceThreshold {
            self.lastVoiceAt = time
        }
    }

    /// 認識結果が届いた。声があったとみなす
    public mutating func recognized(at time: TimeInterval) {
        self.lastVoiceAt = time
    }

    /// 聞き取りが終わった（確定・取り消し）
    public mutating func end() {
        self.listeningStartedAt = nil
        self.lastVoiceAt = nil
        self.level = 0
        self.isPreparingModel = false
    }

    /// 失敗した
    public mutating func fail(_ failure: VoiceInputSession.Failure, at time: TimeInterval) {
        self.end()
        self.failure = (Self.message(for: failure), time)
    }

    /// 失敗の札を出し終えたか（ピルを消してよいか）
    public func isFailureExpired(at time: TimeInterval) -> Bool {
        guard let failure = self.failure else {
            return true
        }
        return time - failure.at >= Self.failureDuration
    }

    public func model(
        phase: VoiceInputSession.Phase,
        now: TimeInterval,
        shortcut: KeyboardShortcut,
        reduceMotion: Bool
    ) -> VoicePillModel? {
        switch phase {
        case .listening where self.isPreparingModel:
            return VoicePillModel(mic: .finishing, label: "日本語の認識モデルを準備中…", isPulsing: false, level: nil, animatesLevel: false, keys: nil)
        case .listening:
            let quietSince = self.lastVoiceAt ?? self.listeningStartedAt ?? now
            let showsKeys = now - quietSince >= Self.silenceBeforeKeys
            let level: VoicePillModel.Level? = if showsKeys {
                nil
            } else if self.level >= Self.voiceThreshold {
                .voice(self.level)
            } else {
                .silent
            }
            return VoicePillModel(
                mic: .listening,
                label: "聞き取り中",
                isPulsing: !reduceMotion,
                level: level,
                animatesLevel: !reduceMotion,
                keys: showsKeys ? VoicePillModel.Keys(commitKey: shortcut.displayString) : nil
            )
        case .finishing:
            return VoicePillModel(mic: .finishing, label: "仕上げ中…", isPulsing: false, level: nil, animatesLevel: false, keys: nil)
        case .idle:
            guard let failure = self.failure, !self.isFailureExpired(at: now) else {
                return nil
            }
            return VoicePillModel(mic: .failed, label: failure.message, isPulsing: false, level: nil, animatesLevel: false, keys: nil)
        }
    }

    static func message(for failure: VoiceInputSession.Failure) -> String {
        switch failure {
        case .microphoneDenied:
            "マイクが使えません"
        case .speechRecognitionDenied:
            "音声認識が許可されていません"
        case .onDeviceRecognitionUnavailable:
            "この Mac では音声認識を使えません"
        case .modelUnavailable:
            "日本語の認識モデルを準備できません"
        case .other:
            "うまく聞き取れませんでした"
        }
    }

    public static func == (lhs: VoicePillPresenter, rhs: VoicePillPresenter) -> Bool {
        lhs.listeningStartedAt == rhs.listeningStartedAt
            && lhs.lastVoiceAt == rhs.lastVoiceAt
            && lhs.level == rhs.level
            && lhs.failure?.message == rhs.failure?.message
            && lhs.failure?.at == rhs.failure?.at
            && lhs.isPreparingModel == rhs.isPreparingModel
    }
}

/// 録音の音の大きさ（RMS）を、声の揺れに使う 0〜1 に直す
public enum VoiceLevel {
    /// これより小さい音は 0
    public static let floorDecibels: Double = -50
    /// これより大きい音は 1
    public static let ceilingDecibels: Double = -10

    public static func normalized(rms: Double) -> Double {
        guard rms > 0 else {
            return 0
        }
        let decibels = 20 * log10(rms)
        let ratio = (decibels - Self.floorDecibels) / (Self.ceilingDecibels - Self.floorDecibels)
        return min(max(ratio, 0), 1)
    }

    /// 3 本の棒の高さ（pt）。真ん中を高く、左右を少し低くする。声がないときは点（3pt）
    public static func barHeights(_ level: Double, maxHeight: Double = 14, minHeight: Double = 3) -> [Double] {
        [0.6, 1.0, 0.75].map { weight in
            minHeight + (maxHeight - minHeight) * min(max(level, 0), 1) * weight
        }
    }
}
