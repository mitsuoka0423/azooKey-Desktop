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
        public var text: String
        /// 意味の手がかり（なければ空）
        public var hint: String

        public init(text: String, hint: String) {
            self.text = text
            self.hint = hint
        }
    }

    public struct CandidateList: Sendable, Equatable {
        public var items: [CandidateItem]
        /// 選択中の行（`items` の位置）
        public var selectedIndex: Int?
        /// `items` が全候補の何件目から何件目か
        public var range: Range<Int>
        /// 全候補の件数
        public var totalCount: Int
        public var isExpanded: Bool

        public init(items: [CandidateItem], selectedIndex: Int?, range: Range<Int>, totalCount: Int, isExpanded: Bool) {
            self.items = items
            self.selectedIndex = selectedIndex
            self.range = range
            self.totalCount = totalCount
            self.isExpanded = isExpanded
        }

        /// 候補リストの末尾の行。出さないときは `nil`
        public var moreRowTitle: String? {
            if self.isExpanded {
                // 1 ページに収まらないときは、今どこを出しているかも示す
                self.totalCount > LiveConversionPanelState.pageCandidateCount
                    ? "候補をたたむ　\(self.range.lowerBound + 1)–\(self.range.upperBound) / \(self.totalCount) 件"
                    : "候補をたたむ"
            } else if self.totalCount > self.range.count {
                "ほかの候補 \(self.totalCount - self.range.count) 件"
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
        let total = targetCandidates.count
        let selected = targetCandidates.firstIndex(of: shown[target].surface)
        let range: Range<Int>
        if state.isExpanded {
            // 9 件ずつのページに分け、選んでいる候補のページを出す
            let page = LiveConversionPanelState.pageCandidateCount
            let start = (selected ?? 0) / page * page
            range = start..<min(start + page, total)
        } else {
            range = 0..<min(total, LiveConversionPanelState.shownCandidateCount)
        }
        let items = targetCandidates[range].map { text in
            CandidateItem(text: text, hint: hint(text))
        }
        let list = CandidateList(
            items: items,
            selectedIndex: selected.flatMap { range.contains($0) ? $0 - range.lowerBound : nil },
            range: range,
            totalCount: total,
            isExpanded: state.isExpanded
        )
        return .init(columns: columns, targetIndex: target, candidateList: list)
    }

    /// 文節の候補を並べる。最初の 9 件は、エンジンの表記を先頭に、辞書変換の候補、ひらがな、カタカナ、打ったとおりの英字の順。
    /// 日時の候補（「きょう」の「2026/11/11」など）は、辞書変換の候補の 3 番目から入れる。
    /// 9 件に収まらない候補は、その後ろに続ける（ひらがな・カタカナ・英字を最初のページに残すため）。重なりを除き、最大 100 件
    public static func candidates(engineSurface: String, reading: String, dictionaryCandidates: [String], dateTimeCandidates: [String] = [], typed: String? = nil) -> [String] {
        let fixed = [reading, Self.katakana(reading), typed ?? ""]
        var seen = Set(dateTimeCandidates)
        var converted = ([engineSurface] + dictionaryCandidates).filter { !$0.isEmpty && seen.insert($0).inserted }
        converted.insert(contentsOf: dateTimeCandidates, at: min(2, converted.count))
        seen = []
        var firstPage = (converted + fixed).filter { !$0.isEmpty && seen.insert($0).inserted }
        var rest: [String] = []
        while firstPage.count > LiveConversionPanelState.pageCandidateCount,
              let last = firstPage.indices.dropFirst().last(where: { !fixed.contains(firstPage[$0]) }) {
            rest.insert(firstPage.remove(at: last), at: 0)
        }
        return Array((firstPage + rest).prefix(LiveConversionPanelState.maxCandidateCount))
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
