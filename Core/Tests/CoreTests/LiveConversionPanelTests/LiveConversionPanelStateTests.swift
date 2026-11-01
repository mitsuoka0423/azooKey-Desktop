import Core
import Testing

@Suite("LiveConversionPanelState")
struct LiveConversionPanelStateTests {
    private static let clauses: [LiveConversionClause] = [
        .init(reading: "あしたは", surface: "明日は"),
        .init(reading: "はしの", surface: "橋の"),
        .init(reading: "はしを", surface: "橋を"),
        .init(reading: "わたる", surface: "渡る")
    ]

    /// 文節ごとの候補。先頭がエンジンの表記
    private static func candidates(_ index: Int) -> [String] {
        switch index {
        case 2: ["橋を", "箸を", "端を", "はしを", "ハシを", "嘴を"]
        default: [clauses[index].surface, clauses[index].reading]
        }
    }

    private static func press(_ keys: [LiveConversionPanelState.Key], from state: LiveConversionPanelState = .init()) -> LiveConversionPanelState {
        var state = state
        for key in keys {
            _ = state.handle(key, clauses: clauses, candidates: candidates)
        }
        return state
    }

    @Test("パネルが扱うキー。⇧← →、修飾キーつき、0 は本来のキー処理に任せる")
    func keyMapping() {
        typealias Key = LiveConversionPanelState.Key
        #expect(Key(userAction: .navigation(.left), modifiers: []) == .left)
        #expect(Key(userAction: .navigation(.down), modifiers: []) == .down)
        #expect(Key(userAction: .space(prefersFullWidthWhenInput: true), modifiers: []) == .space)
        #expect(Key(userAction: .number(.three), modifiers: []) == .number(3))
        #expect(Key(userAction: .navigation(.left), modifiers: [.shift]) == nil)
        #expect(Key(userAction: .tab, modifiers: [.option]) == nil)
        #expect(Key(userAction: .number(.zero), modifiers: []) == nil)
        #expect(Key(userAction: .enter, modifiers: []) == nil)
        #expect(Key(userAction: .backspace, modifiers: []) == nil)
    }

    @Test("入力中の対象は、自信の低い文節のうち最後のもの。なければ最後の文節")
    func targetWhileTyping() {
        let state = LiveConversionPanelState()
        #expect(state.targetIndex(clauseCount: 4) == 3)
        #expect(state.targetIndex(clauseCount: 4, lowConfidence: [1, 2]) == 2)
        #expect(state.targetIndex(clauseCount: 0) == nil)
    }

    @Test("入力中に ← を押すと最後の文節、→ を押すと最初の文節から選ぶ")
    func arrowsEnterSelection() {
        #expect(Self.press([.left]).mode == .selecting(3))
        #expect(Self.press([.right]).mode == .selecting(0))
        #expect(Self.press([.left, .left, .left]).mode == .selecting(1))
        // 端で止まる
        #expect(Self.press([.right, .left, .left]).mode == .selecting(0))
        #expect(Self.press([.left, .right]).mode == .selecting(3))
    }

    @Test("↓ と Space で次の候補、↑ で前の候補。上位 4 件の中で回る")
    func cycleCandidates() {
        let base = Self.press([.left, .left])
        #expect(base.applying(to: Self.clauses)[2].surface == "橋を")
        #expect(Self.press([.down], from: base).applying(to: Self.clauses)[2].surface == "箸を")
        #expect(Self.press([.space, .space], from: base).applying(to: Self.clauses)[2].surface == "端を")
        #expect(Self.press([.up], from: base).applying(to: Self.clauses)[2].surface == "はしを")
        #expect(Self.press([.up], from: base).isExpanded == false)
    }

    @Test("4 件目から ↓ で候補を広げて 5 件目へ")
    func expandFromFourth() {
        let state = Self.press([.left, .left, .down, .down, .down, .down])
        #expect(state.isExpanded)
        #expect(state.applying(to: Self.clauses)[2].surface == "ハシを")
    }

    @Test("Tab で広げる・たたむ。広げる候補がなければ本来の Tab に任せる")
    func tabTogglesExpansion() {
        var state = Self.press([.left, .left])
        #expect(state.handle(.tab, clauses: Self.clauses, candidates: Self.candidates) == .handled)
        #expect(state.isExpanded)
        #expect(state.handle(.tab, clauses: Self.clauses, candidates: Self.candidates) == .handled)
        #expect(!state.isExpanded)

        var last = LiveConversionPanelState()
        #expect(last.handle(.tab, clauses: Self.clauses, candidates: Self.candidates) == .notHandled)
    }

    @Test("Esc で対象の文節を読みに戻す")
    func escapeRevertsToReading() {
        let state = Self.press([.left, .left, .escape])
        #expect(state.applying(to: Self.clauses)[2].surface == "はしを")
        #expect(state.isUserSelected(2, in: Self.clauses))
    }

    @Test("数字で選べるのは文節を選んでいる間だけ。出ていない番号は無視する")
    func numbersOnlyWhileSelecting() {
        var typing = LiveConversionPanelState()
        #expect(typing.handle(.number(2), clauses: Self.clauses, candidates: Self.candidates) == .notHandled)

        let picked = Self.press([.left, .left, .number(3)])
        #expect(picked.applying(to: Self.clauses)[2].surface == "端を")

        // たたんでいるときは 5 以降を選べない
        let ignored = Self.press([.left, .left, .number(5)])
        #expect(ignored.applying(to: Self.clauses)[2].surface == "橋を")
        let expanded = Self.press([.left, .left, .tab, .number(5)])
        #expect(expanded.applying(to: Self.clauses)[2].surface == "ハシを")
    }

    @Test("文字を打つと入力に戻るが、選んだ表記は保つ")
    func editingKeepsSelection() {
        var state = Self.press([.left, .left, .down, .tab])
        state.didEditText()
        #expect(state.mode == .typing)
        #expect(!state.isExpanded)
        #expect(state.applying(to: Self.clauses)[2].surface == "箸を")
    }

    @Test("変換し直して同じ位置・同じ読みの文節があれば表記を保ち、なければ外す")
    func overridesFollowReconversion() {
        var state = Self.press([.left, .left, .down])
        // 後ろに文字が増えても、選んだ文節の位置と読みは同じ
        let longer = Self.clauses + [.init(reading: "ひと", surface: "人")]
        #expect(state.applying(to: longer)[2].surface == "箸を")

        // 区切りが変わって同じ範囲の文節がなくなったら外す
        let resplit: [LiveConversionClause] = [
            .init(reading: "あしたは", surface: "明日は"),
            .init(reading: "はしのはしを", surface: "橋の橋を"),
            .init(reading: "わたる", surface: "渡る")
        ]
        state.dropOverrides(notMatching: resplit)
        #expect(state.overrides.isEmpty)
    }
}

@Suite("LiveConversionPanelModel")
struct LiveConversionPanelModelTests {
    private static let clauses: [LiveConversionClause] = [
        .init(reading: "はしを", surface: "橋を"),
        .init(reading: "わたる", surface: "渡る")
    ]
    private static let targetCandidates = ["渡る", "渉る", "亘る", "わたる", "ワタル", "航る"]

    @Test("文節の列と、対象の文節の上位 4 件と「ほかの候補」")
    func collapsed() {
        let model = LiveConversionPanelModel.make(
            clauses: Self.clauses,
            state: .init(),
            targetCandidates: Self.targetCandidates
        )
        #expect(model.columns.map(\.isTarget) == [false, true])
        #expect(model.candidateList?.items.map(\.text) == ["渡る", "渉る", "亘る", "わたる"])
        #expect(model.candidateList?.items.map(\.number) == [1, 2, 3, 4])
        #expect(model.candidateList?.selectedIndex == 0)
        #expect(model.candidateList?.moreRowTitle == "ほかの候補 2 件")
    }

    @Test("広げると最大 9 件で「候補をたたむ」")
    func expanded() {
        let model = LiveConversionPanelModel.make(
            clauses: Self.clauses,
            state: .init(isExpanded: true),
            targetCandidates: Self.targetCandidates
        )
        #expect(model.candidateList?.items.count == 6)
        #expect(model.candidateList?.moreRowTitle == "候補をたたむ")
    }

    @Test("自信の低い文節に印をつけ、入力中はそれを対象にする")
    func lowConfidenceBecomesTarget() {
        let model = LiveConversionPanelModel.make(
            clauses: Self.clauses,
            state: .init(),
            lowConfidence: [0],
            targetCandidates: ["橋を", "箸を"]
        )
        #expect(model.columns.map(\.isLowConfidence) == [true, false])
        #expect(model.columns.map(\.isTarget) == [true, false])
        #expect(model.candidateList?.selectedIndex == 0)
    }

    @Test("ユーザーが選んだ文節は自信の低さの印を消す")
    func userSelectionClearsLowConfidence() {
        let state = LiveConversionPanelState(overrides: [.init(start: 0, reading: "はしを", surface: "箸を")])
        let model = LiveConversionPanelModel.make(
            clauses: Self.clauses,
            state: state,
            lowConfidence: [0],
            targetCandidates: Self.targetCandidates
        )
        #expect(model.columns[0].surface == "箸を")
        #expect(model.columns[0].isLowConfidence == false)
    }

    @Test("候補はエンジンの表記・辞書・ひらがな・カタカナの順で、重ならず 9 件まで")
    func candidateOrder() {
        #expect(LiveConversionPanelModel.candidates(engineSurface: "橋を", reading: "はしを", dictionaryCandidates: ["橋を", "箸を", "端を"])
                    == ["橋を", "箸を", "端を", "はしを", "ハシヲ"])
        let many = (1...20).map { "候補\($0)" }
        #expect(LiveConversionPanelModel.candidates(engineSurface: "a", reading: "あ", dictionaryCandidates: many).count == 9)
    }
}
