import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// テスト用の英単語の一覧（スペルチェッカーの代わり）
struct WordListChecker: EnglishWordChecker {
    static let words: Set<String> = [
        "stacked", "stack", "deploy", "deploys", "merge", "merges", "rebase", "rebases", "pull", "request", "quest",
        "branch", "commit", "commits", "review", "test", "build", "error", "swift", "server", "access",
        "kite", "sake", "tomato", "main", "name", "it", "sit", "ten", "kid", "send", "sink", "pr"
    ]

    func isEnglishWord(_ word: String) -> Bool {
        Self.words.contains(word)
    }
}

@Suite("MixedInputDetector")
struct MixedInputDetectorTests {
    private static func english(_ typed: String) -> [String] {
        let chars = Array(typed)
        return MixedInputDetector.englishRanges(in: chars, inputStyle: .roman2kana, checker: WordListChecker())
            .map { String(chars[$0]) }
    }

    @Test("ローマ字として読めない英単語を見つける")
    func lowercaseWords() {
        #expect(Self.english("konoyuuryokuwodeploysuru") == ["deploy"])
        #expect(Self.english("asitahamainnimergesitekararebasesuru") == ["merge"])
        #expect(Self.english("testwokaitekudasai") == ["test"])
        #expect(Self.english("buildgasippaisita") == ["build"])
        #expect(Self.english("errorgadeta") == ["error"])
        #expect(Self.english("serverni") == ["server"])
    }

    @Test("日本語だけの文は英語にしない（ローマ字として読める英単語を含んでも）")
    func japaneseOnly() {
        for typed in ["watasihagakuseidesu", "kyouhaiitenkidesune", "sinkansendetoukyouniiku", "kokonikitekudasai", "sakewonomu", "tomatowokau"] {
            #expect(Self.english(typed).isEmpty, "\(typed)")
        }
    }

    @Test("大文字で始まる語は英語にする")
    func capitalizedWords() {
        #expect(Self.english("PRwoStacked PRnisite") == ["PR", "Stacked", "PR"])
        #expect(Self.english("PRwostacked PRnisite") == ["PR", "stacked", "PR"])
        #expect(Self.english("korehaGitHubnopullrequestdesu") == ["GitHub", "pullrequest"])
    }

    @Test("ローマ字としても読める英単語は日本語のまま（候補から選ぶ）")
    func ambiguousStaysJapanese() {
        #expect(Self.english("branchwokittekaracommitsuru") == ["branch"])
        #expect(Self.english("kitewoageru").isEmpty)
    }
}

@MainActor
@Suite("MixedInput（実際の変換）")
struct MixedInputConversionTests {
    private static func manager() -> SegmentsManager {
        let manager = SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false, forceLiveConversionPanel: true)
        )
        manager.englishWordChecker = WordListChecker()
        return manager
    }

    private static func type(_ manager: SegmentsManager, _ text: String) {
        for character in text {
            manager.insertAtCursorPosition(String(character), inputStyle: .roman2kana)
        }
    }

    @Test("例文：PRをStacked PRにして（英単語の間は Shift+Space）")
    func example() {
        let manager = Self.manager()
        Self.type(manager, "PRwoStacked")
        #expect(manager.handleLiveConversionPanelKey(.literalSpace) == .handled)
        Self.type(manager, "PRnisite")
        let clauses = manager.getLiveConversionClauses()
        #expect(clauses.map(\.surface).joined() == "PRをStacked PRにして")
        #expect(clauses.map(\.surface).contains("Stacked "))
    }

    @Test("小文字で打った英単語も、打っている途中から英字のまま")
    func lowercaseWhileTyping() {
        let manager = Self.manager()
        Self.type(manager, "kononyuuryokuwodeploysuru")
        #expect(manager.getLiveConversionClauses().map(\.surface).joined() == "この入力をdeployする")
    }

    @Test("日本語だけの文は今までどおり")
    func japaneseOnly() {
        let manager = Self.manager()
        Self.type(manager, "watasihagakuseidesu")
        #expect(manager.getLiveConversionClauses().map(\.surface).joined() == "私は学生です")
    }

    @Test("ローマ字としても読める英単語は日本語のまま、候補に打ったとおりの英字が並ぶ")
    func ambiguousCandidate() {
        let manager = Self.manager()
        Self.type(manager, "kitewo")
        let model = manager.getLiveConversionPanelModel()
        let texts = model.candidateList?.items.map(\.text) ?? []
        #expect(!(model.columns.first?.surface.hasPrefix("kite") ?? true))
        #expect(texts.contains("kiteを"))
    }

    @Test("末尾の子音がローマ字として読めなければ、後ろにかなが続く前から英字のまま")
    func trailingConsonants() {
        let manager = Self.manager()
        Self.type(manager, "test")
        #expect(manager.convertTarget == "test")
        Self.type(manager, "o")
        #expect(manager.convertTarget == "testお")
    }

    @Test("消して英単語でなくなったら、日本語の読みに戻る")
    func deleteBackToJapanese() {
        let manager = Self.manager()
        Self.type(manager, "deploy")
        #expect(manager.convertTarget == "deploy")
        manager.deleteBackwardFromCursorPosition()
        #expect(manager.convertTarget == "でpぉ")
    }
}
