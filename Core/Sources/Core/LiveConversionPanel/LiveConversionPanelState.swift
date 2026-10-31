/// 変換パネルで、ユーザーが選んだ文節の表記
///
/// エンジンは入力のたびに文全体を変換し直すので、選んだ候補は IME 側で覆いかぶせて保つ。
/// 変換し直したあとも、同じ位置に同じ読みの文節があれば、この表記で出す。
public struct LiveConversionClauseOverride: Sendable, Equatable {
    /// 未確定文字列の中での、文節の読みの開始位置（文字数）
    public var start: Int
    public var reading: String
    public var surface: String

    public init(start: Int, reading: String, surface: String) {
        self.start = start
        self.reading = reading
        self.surface = surface
    }
}

/// 変換パネルのキー操作による状態
public struct LiveConversionPanelState: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        /// 入力中。対象の文節は自動で決まる
        case typing
        /// ← → で文節を選んでいる
        case selecting(Int)
    }

    /// パネルが扱うキー
    public enum Key: Sendable, Equatable {
        case left, right, up, down, space, tab, escape
        case number(Int)
    }

    public enum Effect: Sendable, Equatable {
        /// パネルが処理した。本来のキー処理には渡さない
        case handled
        /// パネルは処理しない。本来のキー処理に渡す
        case notHandled
    }

    /// 普段の候補リストに出す件数
    public static let shownCandidateCount = 4
    /// 広げたときに出す最大の件数
    public static let maxCandidateCount = 9

    public var mode: Mode = .typing
    /// 対象の文節の候補を広げているか
    public var isExpanded = false
    public var overrides: [LiveConversionClauseOverride] = []

    public init(mode: Mode = .typing, isExpanded: Bool = false, overrides: [LiveConversionClauseOverride] = []) {
        self.mode = mode
        self.isExpanded = isExpanded
        self.overrides = overrides
    }

    /// 各文節の読みの開始位置
    public static func starts(of clauses: [LiveConversionClause]) -> [Int] {
        var position = 0
        return clauses.map { clause in
            defer { position += clause.reading.count }
            return position
        }
    }

    /// 選んだ表記を覆いかぶせた文節の列
    public func applying(to clauses: [LiveConversionClause]) -> [LiveConversionClause] {
        zip(clauses, Self.starts(of: clauses)).map { clause, start in
            guard let override = self.overrides.first(where: { $0.start == start && $0.reading == clause.reading }) else {
                return clause
            }
            return .init(reading: clause.reading, surface: override.surface)
        }
    }

    /// 変換し直した文節の列に合わなくなった覆いかぶせを捨てる
    public mutating func dropOverrides(notMatching clauses: [LiveConversionClause]) {
        let ranges = Set(zip(Self.starts(of: clauses), clauses).map { "\($0.0):\($0.1.reading)" })
        self.overrides.removeAll { !ranges.contains("\($0.start):\($0.reading)") }
    }

    /// ユーザーが候補を選んだ文節か
    public func isUserSelected(_ index: Int, in clauses: [LiveConversionClause]) -> Bool {
        guard clauses.indices.contains(index) else {
            return false
        }
        let start = Self.starts(of: clauses)[index]
        return self.overrides.contains { $0.start == start && $0.reading == clauses[index].reading }
    }

    /// 対象の文節。入力中は自信の低い文節のうち最後のもの、なければ最後の文節。選んでいるときは選んだ文節
    public func targetIndex(clauseCount: Int, lowConfidence: Set<Int> = []) -> Int? {
        guard clauseCount > 0 else {
            return nil
        }
        switch self.mode {
        case .selecting(let index):
            return min(max(index, 0), clauseCount - 1)
        case .typing:
            return lowConfidence.filter { $0 < clauseCount }.max() ?? clauseCount - 1
        }
    }

    /// 候補リストに今出している件数
    public func visibleCandidateCount(total: Int) -> Int {
        self.isExpanded ? min(total, Self.maxCandidateCount) : min(total, Self.shownCandidateCount)
    }

    /// 文字の入力や削除のあと。入力に戻り、広げた候補をたたむ（選んだ表記は保つ）
    public mutating func didEditText() {
        self.mode = .typing
        self.isExpanded = false
    }

    /// キー操作による状態の変化
    /// - Parameters:
    ///   - clauses: 覆いかぶせを当てる前の文節の列
    ///   - candidates: 文節の位置を受け取り、その文節の候補（先頭がエンジンの表記）を返す
    public mutating func handle(
        _ key: Key,
        clauses: [LiveConversionClause],
        lowConfidence: Set<Int> = [],
        candidates: (Int) -> [String]
    ) -> Effect {
        guard let target = self.targetIndex(clauseCount: clauses.count, lowConfidence: lowConfidence) else {
            return .notHandled
        }
        switch key {
        case .left, .right:
            self.moveTarget(by: key == .left ? -1 : 1, from: target, clauseCount: clauses.count)
        case .up, .down, .space:
            self.cycleCandidate(by: key == .up ? -1 : 1, at: target, in: clauses, candidates: candidates(target))
        case .tab:
            guard candidates(target).count > Self.shownCandidateCount else {
                // 広げる候補がないときは、本来の Tab（予測候補の確定）に渡す
                return .notHandled
            }
            self.isExpanded.toggle()
        case .escape:
            self.select(clauses[target].reading, at: target, in: clauses)
        case .number(let number):
            // 数字で選べるのは文節を選んでいる間だけ。入力中は数字の入力にする
            guard case .selecting = self.mode else {
                return .notHandled
            }
            let list = candidates(target)
            if number >= 1, number <= self.visibleCandidateCount(total: list.count) {
                self.select(list[number - 1], at: target, in: clauses)
            }
        }
        return .handled
    }

    private mutating func moveTarget(by delta: Int, from target: Int, clauseCount: Int) {
        switch self.mode {
        case .typing:
            // 入力中に押すと文節選択に入る。← は最後の文節、→ は最初の文節から
            self.mode = .selecting(delta < 0 ? clauseCount - 1 : 0)
        case .selecting:
            self.mode = .selecting(min(max(target + delta, 0), clauseCount - 1))
        }
        self.isExpanded = false
    }

    private mutating func cycleCandidate(by delta: Int, at target: Int, in clauses: [LiveConversionClause], candidates list: [String]) {
        guard !list.isEmpty else {
            return
        }
        let current = list.firstIndex(of: self.applying(to: clauses)[target].surface) ?? 0
        let visible = self.visibleCandidateCount(total: list.count)
        let next: Int
        if !self.isExpanded, list.count > visible, delta > 0, current >= visible - 1 {
            // 4 件目から下に進むと、候補を広げて 5 件目へ
            self.isExpanded = true
            next = visible
        } else {
            next = (min(current, visible - 1) + delta + visible) % visible
        }
        self.select(list[next], at: target, in: clauses)
    }

    private mutating func select(_ surface: String, at index: Int, in clauses: [LiveConversionClause]) {
        let start = Self.starts(of: clauses)[index]
        let reading = clauses[index].reading
        self.overrides.removeAll { $0.start == start }
        self.overrides.append(.init(start: start, reading: reading, surface: surface))
    }
}
