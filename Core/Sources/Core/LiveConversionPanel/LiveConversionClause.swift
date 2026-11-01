import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// 変換パネルに出す 1 つの文節（読みと変換結果）
public struct LiveConversionClause: Sendable, Equatable {
    /// 読み（ひらがな）
    public var reading: String
    /// 変換結果
    public var surface: String

    public init(reading: String, surface: String) {
        self.reading = reading
        self.surface = surface
    }
}

public extension LiveConversionClause {
    /// ライブ変換の候補から文節の列を作る。
    ///
    /// 文節の区切りはエンジンと同じ規則（`Candidate.makePrefixClauseCandidate`）に任せ、
    /// 付属語は前の語にまとめる。候補が読みの途中までしか覆っていないとき（未変換のローマ字など）は、
    /// 残りを変換しない文節として末尾に足す。
    static func clauses(convertTarget: String, candidate: Candidate?) -> [LiveConversionClause] {
        guard !convertTarget.isEmpty else {
            return []
        }
        guard let candidate, !candidate.data.isEmpty else {
            return [.init(reading: convertTarget, surface: convertTarget)]
        }
        // テンプレートや絵文字の置き換えで表記が語の連結と合わないときは、区切らずに 1 つで出す
        guard candidate.data.map(\.word).joined() == candidate.text else {
            return [.init(reading: convertTarget, surface: candidate.text)]
        }

        var result: [LiveConversionClause] = []
        var rest = candidate.data[...]
        while !rest.isEmpty {
            let clause = Candidate.makePrefixClauseCandidate(data: rest)
            let count = max(1, clause.data.count)
            var elements = rest.prefix(count)
            rest = rest.dropFirst(count)
            // 文節の先頭に来た句読点は、前の文節の末尾につける。読みも表記（「、」など）で出す
            while let first = elements.first, !result.isEmpty, Self.isPunctuation(first.word) {
                result[result.count - 1].reading += first.word
                result[result.count - 1].surface += first.word
                elements = elements.dropFirst()
            }
            guard !elements.isEmpty else {
                continue
            }
            result.append(
                .init(
                    reading: elements.map { Self.hiragana($0.ruby) }.joined(),
                    surface: elements.map(\.word).joined()
                )
            )
        }

        result = Self.mergingASCIIWords(result)

        let coveredCount = result.reduce(0) { $0 + $1.reading.count }
        if coveredCount < convertTarget.count {
            let tail = String(convertTarget.dropFirst(coveredCount))
            result.append(.init(reading: tail, surface: tail))
        }
        return result
    }

    /// エンジンは英字を 1 文字ずつ別の語として返すので、英字の並びを 1 つの文節にまとめる。
    /// 英字の後ろに英字や空白が続く間は同じ文節にし、空白のあとから新しい文節にする（「Stacked 」「PRにして」）
    static func mergingASCIIWords(_ clauses: [LiveConversionClause]) -> [LiveConversionClause] {
        var result: [LiveConversionClause] = []
        for clause in clauses {
            if let last = result.last?.surface.last, last.isASCII, last.isLetter,
               let first = clause.surface.first, first.isASCII, first.isLetter || first == " " {
                result[result.count - 1].reading += clause.reading
                result[result.count - 1].surface += clause.surface
            } else {
                result.append(clause)
            }
        }
        return result
    }

    private static let punctuations: Set<Character> = ["、", "。", "，", "．", ",", ".", "！", "？", "!", "?"]

    private static func isPunctuation(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy(Self.punctuations.contains)
    }

    /// カタカナをひらがなに直す（長音記号などカタカナ以外はそのまま）
    static func hiragana(_ text: String) -> String {
        String(
            String.UnicodeScalarView(
                text.unicodeScalars.map { scalar in
                    // ァ(U+30A1)〜ヶ(U+30F6) はひらがなと 0x60 ずれて並んでいる
                    if (0x30A1...0x30F6).contains(scalar.value),
                       let hiragana = Unicode.Scalar(scalar.value - 0x60) {
                        hiragana
                    } else {
                        scalar
                    }
                }
            )
        )
    }
}
