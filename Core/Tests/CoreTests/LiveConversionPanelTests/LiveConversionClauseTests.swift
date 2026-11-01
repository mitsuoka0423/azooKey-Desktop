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

    @Test("句読点は前の文節につけ、読みも表記で出す")
    func punctuationJoinsPreviousClause() {
        let candidate = Self.candidate([
            Word("明日", "アシタ", Self.noun), Word("、", ",", CIDData.記号.cid), Word("橋", "ハシ", Self.noun)
        ])
        let clauses = LiveConversionClause.clauses(convertTarget: "あした,はし", candidate: candidate)
        #expect(clauses == [
            .init(reading: "あした、", surface: "明日、"),
            .init(reading: "はし", surface: "橋")
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

    @MainActor
    @Test("実際の変換：同音異義語の文節に自信の低さの印と意味の手がかりがつく")
    func lowConfidenceAndHints() {
        let manager = SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false)
        )
        manager.insertAtCursorPosition("kaigiwohasiwo", inputStyle: .roman2kana)
        let model = manager.getLiveConversionPanelModel()
        let low = model.columns.filter(\.isLowConfidence).map(\.reading)
        #expect(low.contains("はしを"))
        #expect(!low.contains("かいぎを"))
        // 入力中は、自信の低い文節が対象になる
        #expect(model.columns.first { $0.isTarget }?.reading == "はしを")
        let hints = Dictionary(uniqueKeysWithValues: (model.candidateList?.items ?? []).map { ($0.text, $0.hint) })
        #expect(hints["箸を"] == "食事の道具")
        #expect(hints["はしを"] == "ひらがな")

        // 候補を選ぶと印は消える
        _ = manager.handleLiveConversionPanelKey(.left)
        _ = manager.handleLiveConversionPanelKey(.down)
        #expect(manager.getLiveConversionPanelModel().columns.first { $0.reading == "はしを" }?.isLowConfidence == false)
    }

    @MainActor
    @Test("実際の変換：⇧← で区切りを直すと、続けて入力しても区切りを保つ")
    func fixBoundary() {
        let manager = SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false)
        )
        manager.insertAtCursorPosition("asitahasino", inputStyle: .roman2kana)
        #expect(manager.getLiveConversionClauses().map(\.reading) == ["あしたは", "しの"])

        // 最初の文節を選び、1 文字縮めて「は」を次の文節へ送る
        #expect(manager.handleLiveConversionPanelKey(.right) == .handled)
        #expect(manager.handleLiveConversionPanelKey(.shrink) == .handled)
        #expect(manager.getLiveConversionClauses().map(\.reading) == ["あした", "はしの"])
        #expect(manager.getLiveConversionClauses().first?.surface == "明日")
        // かなだけの候補はスコアが高めに出るが、区切り直した文節の表記には使わない
        #expect(manager.getLiveConversionClauses().last?.surface != "ハシノ")

        manager.insertAtCursorPosition("hasiwo", inputStyle: .roman2kana)
        let clauses = manager.getLiveConversionClauses()
        #expect(Array(clauses.map(\.reading).prefix(2)) == ["あした", "はしの"])
    }

    @MainActor
    @Test("実際の変換：途中の文節で選んだ候補は、続けて入力しても保つ")
    func keepSelectionWhileTyping() {
        let manager = SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false)
        )
        manager.insertAtCursorPosition("hasinohasiwo", inputStyle: .roman2kana)
        #expect(manager.getLiveConversionClauses().map(\.reading) == ["はしの", "はしを"])

        // 最後の文節を選んで、候補リストから「箸を」を選ぶ
        #expect(manager.handleLiveConversionPanelKey(.left) == .handled)
        let list = manager.getLiveConversionPanelModel().candidateList?.items.map(\.text) ?? []
        #expect(list.contains("箸を"))
        for _ in 0..<LiveConversionPanelState.maxCandidateCount where manager.getLiveConversionClauses().last?.surface != "箸を" {
            #expect(manager.handleLiveConversionPanelKey(.down) == .handled)
        }
        #expect(manager.getLiveConversionClauses().last?.surface == "箸を")

        manager.insertAtCursorPosition("wataru", inputStyle: .roman2kana)
        let clauses = manager.getLiveConversionClauses()
        #expect(clauses.map(\.surface).joined().hasPrefix("橋の箸を"))
        #expect(manager.getLiveConversionPanelModel().columns.last?.isTarget == true)
    }
}
