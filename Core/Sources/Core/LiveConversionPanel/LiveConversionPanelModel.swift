/// 変換パネルに出す内容。`azooKeyMac` 側はこれを受け取って描くだけにする
public struct LiveConversionPanelModel: Sendable, Equatable {
    public struct Column: Sendable, Equatable {
        public var reading: String
        public var surface: String
        public var isTarget: Bool
        public var isLowConfidence: Bool

        public init(reading: String, surface: String, isTarget: Bool, isLowConfidence: Bool) {
            self.reading = reading
            self.surface = surface
            self.isTarget = isTarget
            self.isLowConfidence = isLowConfidence
        }
    }

    public struct CandidateItem: Sendable, Equatable {
        /// 1 から始まる番号
        public var number: Int
        public var text: String
        /// 意味の手がかり（なければ空）
        public var hint: String

        public init(number: Int, text: String, hint: String) {
            self.number = number
            self.text = text
            self.hint = hint
        }
    }

    public struct CandidateList: Sendable, Equatable {
        public var items: [CandidateItem]
        /// 選択中の行（`items` の位置）
        public var selectedIndex: Int?
        /// たたんでいて出していない候補の件数。0 なら「ほかの候補」の行を出さない
        public var hiddenCount: Int
        public var isExpanded: Bool

        public init(items: [CandidateItem], selectedIndex: Int?, hiddenCount: Int, isExpanded: Bool) {
            self.items = items
            self.selectedIndex = selectedIndex
            self.hiddenCount = hiddenCount
            self.isExpanded = isExpanded
        }

        /// 候補リストの末尾の行。出さないときは `nil`
        public var moreRowTitle: String? {
            if self.isExpanded {
                "候補をたたむ"
            } else if self.hiddenCount > 0 {
                "ほかの候補 \(self.hiddenCount) 件"
            } else {
                nil
            }
        }
    }

    public static let keyHint = "Tab 広げる　Esc 読みに戻す　⇧← → 区切り"

    public var columns: [Column]
    public var targetIndex: Int?
    public var candidateList: CandidateList?

    public init(columns: [Column], targetIndex: Int?, candidateList: CandidateList?) {
        self.columns = columns
        self.targetIndex = targetIndex
        self.candidateList = candidateList
    }

    /// - Parameters:
    ///   - clauses: 覆いかぶせを当てる前の文節の列
    ///   - targetCandidates: 対象の文節の候補（先頭がエンジンの表記）
    ///   - hint: 候補ごとの意味の手がかり
    public static func make(
        clauses: [LiveConversionClause],
        state: LiveConversionPanelState,
        lowConfidence: Set<Int> = [],
        targetCandidates: [String],
        hint: (String) -> String = { _ in "" }
    ) -> LiveConversionPanelModel {
        let shown = state.applying(to: clauses)
        let target = state.targetIndex(clauseCount: clauses.count, lowConfidence: lowConfidence)
        let columns = shown.enumerated().map { index, clause in
            Column(
                reading: clause.reading,
                surface: clause.surface,
                isTarget: index == target,
                // ユーザーが選んだ文節は、自信の低さの印を消す
                isLowConfidence: lowConfidence.contains(index) && !state.isUserSelected(index, in: clauses)
            )
        }
        guard let target, !targetCandidates.isEmpty else {
            return .init(columns: columns, targetIndex: target, candidateList: nil)
        }
        let visible = state.visibleCandidateCount(total: targetCandidates.count)
        let items = targetCandidates.prefix(visible).enumerated().map { index, text in
            CandidateItem(number: index + 1, text: text, hint: hint(text))
        }
        let list = CandidateList(
            items: items,
            selectedIndex: items.firstIndex { $0.text == shown[target].surface },
            hiddenCount: min(targetCandidates.count, LiveConversionPanelState.maxCandidateCount) - visible,
            isExpanded: state.isExpanded
        )
        return .init(columns: columns, targetIndex: target, candidateList: list)
    }

    /// 文節の候補を並べる。エンジンの表記を先頭に、辞書変換の候補、ひらがな、カタカナ、打ったとおりの英字の順。重なりを除き、最大 9 件。
    /// 9 件を超えるときは辞書の候補を後ろから減らし、ひらがな・カタカナ・英字は残す
    public static func candidates(engineSurface: String, reading: String, dictionaryCandidates: [String], typed: String? = nil) -> [String] {
        let fixed = [reading, Self.katakana(reading), typed ?? ""]
        var seen = Set<String>()
        var all = ([engineSurface] + dictionaryCandidates + fixed).filter { !$0.isEmpty && seen.insert($0).inserted }
        while all.count > LiveConversionPanelState.maxCandidateCount,
              let last = all.indices.dropFirst().last(where: { !fixed.contains(all[$0]) }) {
            all.remove(at: last)
        }
        return all
    }

    static func katakana(_ text: String) -> String {
        String(
            String.UnicodeScalarView(
                text.unicodeScalars.map { scalar in
                    // ぁ(U+3041)〜ゖ(U+3096) はカタカナと 0x60 ずれて並んでいる
                    if (0x3041...0x3096).contains(scalar.value),
                       let katakana = Unicode.Scalar(scalar.value + 0x60) {
                        katakana
                    } else {
                        scalar
                    }
                }
            )
        )
    }
}
