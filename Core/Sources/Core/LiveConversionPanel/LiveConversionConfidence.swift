/// 文節の変換に自信が低いかの判定（仕様の決定事項 3）
public enum LiveConversionConfidence {
    /// 辞書変換の 1 つの候補
    public struct ScoredCandidate: Sendable, Equatable {
        public var text: String
        public var score: Double

        public init(text: String, score: Double) {
            self.text = text
            self.score = score
        }
    }

    /// 1 位と 2 位のスコア差がこれより小さいと迷いやすいとみなす。
    /// P2a の例：橋を／箸を 0.6、子の／市の 0.5、記者／汽車 2.3 は迷いやすく、考察／絞殺 3.6、学生です／学制です 4.4 は迷いにくい
    public static let scoreGapThreshold = 3.0

    /// - Parameters:
    ///   - surface: 本文（エンジン）の表記
    ///   - dictionaryCandidates: その文節の読みだけを Zenzai なしで変換した候補（スコアの高い順）
    public static func isLow(surface: String, reading: String, dictionaryCandidates: [ScoredCandidate]) -> Bool {
        // かなだけの候補（ひらがな・カタカナにしただけのもの）は比べない
        let kanji = dictionaryCandidates.filter { !Self.isKanaOnly($0.text) }
        guard let first = kanji.first else {
            return false
        }
        // 本文の表記が辞書変換の 1 位と食い違う
        if !Self.isKanaOnly(surface), surface != first.text {
            return true
        }
        guard kanji.count >= 2 else {
            return false
        }
        return first.score - kanji[1].score < Self.scoreGapThreshold
    }

    static func isKanaOnly(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            // ひらがな・カタカナ・長音記号・句読点
            (0x3041...0x309F).contains(scalar.value)
                || (0x30A0...0x30FF).contains(scalar.value)
                || "、。，．,.！？!?".unicodeScalars.contains(scalar)
        }
    }
}
