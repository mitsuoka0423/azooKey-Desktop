import Core
import Testing

@Suite("LiveConversionConfidence")
struct LiveConversionConfidenceTests {
    private static func scored(_ pairs: [(String, Double)]) -> [LiveConversionConfidence.ScoredCandidate] {
        pairs.map { .init(text: $0.0, score: $0.1) }
    }

    @Test("1 位と 2 位のスコア差が小さい文節は自信が低い")
    func smallGapIsLow() {
        let candidates = Self.scored([("橋を", -16.7), ("箸を", -17.3), ("はしを", -17.8), ("端を", -19.1)])
        #expect(LiveConversionConfidence.isLow(surface: "橋を", reading: "はしを", dictionaryCandidates: candidates))
    }

    @Test("スコア差が大きい文節は自信が高い。かなだけの候補は比べない")
    func largeGapIsHigh() {
        let candidates = Self.scored([("開催する", -13.8), ("カイサイスル", -14.0), ("かいさいする", -14.5), ("皆済する", -27.7)])
        #expect(!LiveConversionConfidence.isLow(surface: "開催する", reading: "かいさいする", dictionaryCandidates: candidates))
    }

    @Test("本文の表記が辞書変換の 1 位と食い違う文節は自信が低い")
    func disagreementIsLow() {
        let candidates = Self.scored([("子の", -11.6), ("紙の", -30)])
        #expect(LiveConversionConfidence.isLow(surface: "市の", reading: "しの", dictionaryCandidates: candidates))
    }

    @Test("本文がかなのときは食い違いとみなさない。候補が 1 つだけのとき、候補がないときは印をつけない")
    func noMarkWithoutComparison() {
        #expect(!LiveConversionConfidence.isLow(surface: "ありがとう", reading: "ありがとう", dictionaryCandidates: Self.scored([("有難う", -10), ("在り難う", -20)])))
        #expect(!LiveConversionConfidence.isLow(surface: "学生です", reading: "がくせいです", dictionaryCandidates: Self.scored([("学生です", -18)])))
        #expect(!LiveConversionConfidence.isLow(surface: "t", reading: "t", dictionaryCandidates: []))
    }
}
