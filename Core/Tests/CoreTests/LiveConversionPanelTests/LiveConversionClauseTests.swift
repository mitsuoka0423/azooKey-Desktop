import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Suite("LiveConversionClause")
struct LiveConversionClauseTests {
    private static let noun = CIDData.一般名詞.cid
    private static let particle = CIDData.係助詞ハ.cid

    private struct Word {
        var word: String
        var ruby: String
        var cid: Int

        init(_ word: String, _ ruby: String, _ cid: Int) {
            self.word = word
            self.ruby = ruby
            self.cid = cid
        }
    }

    private static func candidate(_ words: [Word]) -> Candidate {
        let data = words.map { DicdataElement(word: $0.word, ruby: $0.ruby, cid: $0.cid, mid: 500, value: -10) }
        return Candidate(
            text: data.map(\.word).joined(),
            value: -10,
            composingCount: .surfaceCount(data.reduce(0) { $0 + $1.ruby.count }),
            lastMid: 500,
            data: data
        )
    }

    @Test("付属語は前の語にまとめ、読みはひらがなにする")
    func joinsParticlesToPreviousWord() {
        let candidate = Self.candidate([
            Word("私", "ワタシ", Self.noun), Word("は", "ハ", Self.particle),
            Word("学生", "ガクセイ", Self.noun), Word("は", "ハ", Self.particle)
        ])
        let clauses = LiveConversionClause.clauses(convertTarget: "わたしはがくせいは", candidate: candidate)
        #expect(clauses == [
            .init(reading: "わたしは", surface: "私は"),
            .init(reading: "がくせいは", surface: "学生は")
        ])
    }

    @Test("候補が覆っていない末尾（未変換のローマ字）は変換しない文節として足す")
    func appendsUncoveredTail() {
        let candidate = Self.candidate([Word("有賀", "アリガ", Self.noun)])
        let clauses = LiveConversionClause.clauses(convertTarget: "ありがt", candidate: candidate)
        #expect(clauses == [
            .init(reading: "ありが", surface: "有賀"),
            .init(reading: "t", surface: "t")
        ])
    }

    @Test("候補がなければ読みをそのまま 1 つの文節にする")
    func withoutCandidate() {
        #expect(LiveConversionClause.clauses(convertTarget: "あ", candidate: nil) == [.init(reading: "あ", surface: "あ")])
        #expect(LiveConversionClause.clauses(convertTarget: "", candidate: nil).isEmpty)
    }

    @Test("表記が語の連結と合わないときは区切らない")
    func templateTextIsNotSplit() {
        var candidate = Self.candidate([Word("今日", "キョウ", Self.noun), Word("は", "ハ", Self.particle)])
        candidate.text = "2026/10/31は"
        let clauses = LiveConversionClause.clauses(convertTarget: "きょうは", candidate: candidate)
        #expect(clauses == [.init(reading: "きょうは", surface: "2026/10/31は")])
    }

    @Test("カタカナをひらがなに直す")
    func hiragana() {
        #expect(LiveConversionClause.hiragana("ヴァイオリン") == "ゔぁいおりん")
        #expect(LiveConversionClause.hiragana("ケーキ") == "けーき")
        #expect(LiveConversionClause.hiragana("ヵヶ") == "ゕゖ")
    }

    @MainActor
    @Test("実際の変換：明日、橋の端を渡る")
    func realConversion() {
        let converter = KanaKanjiConverter.withDefaultDictionary()
        func clauses(_ input: String) -> [LiveConversionClause] {
            let manager = SegmentsManager(
                kanaKanjiConverter: converter,
                applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
                containerURL: nil,
                context: .init(useZenzai: false)
            )
            manager.insertAtCursorPosition(input, inputStyle: .roman2kana)
            manager.update(requestRichCandidates: false)
            return manager.getLiveConversionClauses()
        }
        // 読点は前の文節につく
        #expect(clauses("asita,hasinohasiwowataru").map(\.reading) == ["あした,", "はしの", "はしを", "わたる"])
        #expect(clauses("watasihagakuseidesu") == [
            .init(reading: "わたしは", surface: "私は"),
            .init(reading: "がくせいです", surface: "学生です")
        ])
        #expect(clauses("arigat").last == .init(reading: "t", surface: "t"))
    }
}
