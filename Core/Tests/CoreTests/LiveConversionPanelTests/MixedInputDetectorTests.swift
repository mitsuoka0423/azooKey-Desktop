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

    var extra: Set<String> = []

    static func adding(_ words: Set<String>) -> WordListChecker {
        WordListChecker(extra: words)
    }

    func isEnglishWord(_ word: String) -> Bool {
        Self.words.contains(word) || self.extra.contains(word)
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

    @Test("日本語として読んだ語が辞書の語なら日本語、学習から来たかなだけの語なら英語")
    func learnedKanaWord() {
        let chars = Array("commitsite")
        func english(_ metadata: DicdataElementMetadata) -> [String] {
            let element = DicdataElement(word: "コッミツィテ", ruby: "コッミツィテ", cid: CIDData.一般名詞.cid, mid: 100, value: -10, metadata: metadata)
            return MixedInputDetector.englishRanges(
                in: chars,
                inputStyle: .roman2kana,
                japaneseReading: .init(elements: [element]),
                checker: WordListChecker()
            ).map { String(chars[$0]) }
        }
        #expect(english(.isLearned) == ["commit"])
        #expect(english(.empty).isEmpty)
    }

    @Test("学習した片仮名語の途中からは英単語を始めない（コマンド＋は の doha、ディレクトリ の tori）")
    func learnedKatakanaWordIsNotCut() {
        func english(_ typed: String, _ words: [(String, String)]) -> [String] {
            let chars = Array(typed)
            let elements = words.map { DicdataElement(word: $0.0, ruby: $0.1, cid: CIDData.一般名詞.cid, mid: 283, value: -10, metadata: .isLearned) }
            return MixedInputDetector.englishRanges(
                in: chars,
                inputStyle: .roman2kana,
                japaneseReading: .init(elements: elements),
                checker: WordListChecker.adding(["doha", "tori", "man"])
            ).map { String(chars[$0]) }
        }
        #expect(english("komanndoha", [("コマンド", "コマンド"), ("は", "ハ")]).isEmpty)
        #expect(english("dhirekutori", [("ディレクトリ", "ディレクトリ")]).isEmpty)
        #expect(english("koman", [("コマ", "コマ"), ("n", "n")]).isEmpty)
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

    @Test("日本語として読める語は日本語のまま、候補に打ったとおりの英字が並ぶ")
    func ambiguousCandidate() {
        let manager = Self.manager()
        Self.type(manager, "sakewo")
        let model = manager.getLiveConversionPanelModel()
        let texts = model.candidateList?.items.map(\.text) ?? []
        #expect(model.columns.first?.surface == "酒を")
        #expect(texts.contains("sakeを"))
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

    @Test("ローマ字としても読める英単語でも、日本語として読むと辞書の語に収まらなければ英字のまま")
    func dictionaryFragmented() {
        for (typed, expected) in [
            ("commitsite", "commitして"),
            ("reviewwoonegaisimasu", "reviewをお願いします"),
            ("rebasesuru", "rebaseする")
        ] {
            let manager = Self.manager()
            Self.type(manager, typed)
            #expect(manager.getLiveConversionClauses().map(\.surface).joined() == expected, "\(typed)")
        }
    }

    @Test("⇧→ で、右隣の英単語の文節の先頭を取り込める。打ちかけのローマ字は取り込まない")
    func extendIntoEnglishClause() {
        let manager = Self.manager()
        Self.type(manager, "asitahabranchwokiru")
        #expect(manager.getLiveConversionClauses().first?.reading == "あしたは")
        // ← で最初の文節まで動かす
        for _ in manager.getLiveConversionClauses() {
            _ = manager.handleLiveConversionPanelKey(.left)
        }
        #expect(manager.handleLiveConversionPanelKey(.extend) == .handled)
        #expect(manager.getLiveConversionClauses().map(\.reading).prefix(2) == ["あしたはb", "ranchをきる"])

        let typing = Self.manager()
        Self.type(typing, "kyouhat")
        #expect(typing.getLiveConversionClauses().last == .init(reading: "t", surface: "t", isUnconverted: true))
        _ = typing.handleLiveConversionPanelKey(.left)
        _ = typing.handleLiveConversionPanelKey(.extend)
        #expect(typing.getLiveConversionClauses().map(\.reading) == ["きょうは", "t"])
    }

    @Test("日本語として読んで辞書の語に収まるなら日本語のまま（来て・酒・トマト・天気）")
    func dictionaryCovered() {
        for (typed, expected) in [
            ("kokonikitekudasai", "ここに来てください"),
            ("sakewonomu", "酒を飲む"),
            ("tomatowokau", "トマトを買う"),
            ("kyouhaiitenkidesune", "今日はいい天気ですね"),
            ("sinkansendeiku", "新幹線で行く")
        ] {
            let manager = Self.manager()
            Self.type(manager, typed)
            #expect(manager.getLiveConversionClauses().map(\.surface).joined() == expected, "\(typed)")
        }
    }
}

#if canImport(AppKit)
import AppKit

/// macOS のスペルチェッカー（アプリと同じ判定）
private struct SpellCheckerWordChecker: EnglishWordChecker {
    func isEnglishWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            .location == NSNotFound
    }
}

@MainActor
@Suite("MixedInput（スペルチェッカー）")
struct MixedInputSpellCheckerTests {
    @Test("スペルチェッカーは site や nod も英単語と認めるが、日本語として打った部分は日本語のまま")
    func englishThenJapanese() {
        for (typed, expected) in [
            ("commitsite", "commitして"),
            ("asitanokaigidehabranchwokittekaracommitsitereviewwoonegaisimasu", "明日の会議ではbranchを切ってからcommitしてreviewをお願いします"),
            ("watasihagakuseidesu", "私は学生です"),
            // 打ちかけの子音（doh、nod）、dhi の途中、辞書の語の途中（ディレクトリ＋で の ride）、し＋て の site を英語にしない
            ("komanndohaninninodhirekutoridejikkoudekiruyounisite", "コマンドは任意のディレクトリで実行できるようにして"),
            ("kodomonotamenisiteageru", "子供のためにしてあげる"),
            ("nanisiteruno", "何してるの"),
            ("sonofilewoeditsite", "そのfileをeditして"),
            ("rebasesuru", "rebaseする")
        ] {
            let manager = SegmentsManager(
                kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
                applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
                containerURL: nil,
                context: .init(useZenzai: false, forceLiveConversionPanel: true)
            )
            manager.englishWordChecker = SpellCheckerWordChecker()
            for character in typed {
                manager.insertAtCursorPosition(String(character), inputStyle: .roman2kana)
            }
            #expect(manager.getLiveConversionClauses().map(\.surface).joined() == expected, "\(typed)")
        }
    }
}
#endif
