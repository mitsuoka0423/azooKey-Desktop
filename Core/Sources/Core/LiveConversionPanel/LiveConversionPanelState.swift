/// 変換パネルで、ユーザーが選んだ文節の表記や区切り
///
/// エンジンは入力のたびに文全体を変換し直すので、選んだ候補や区切りは IME 側で覆いかぶせて保つ。
/// - 候補を選んだだけのもの：変換し直したあとも、同じ位置に同じ読みの文節があれば、この表記で出す
/// - 区切りを変えたもの（`isBoundary`）：その位置の読みが変わらないかぎり、この区切りと表記で出す
public struct LiveConversionClauseOverride: Sendable, Equatable {
    /// 未確定文字列の中での、文節の読みの開始位置（文字数）
    public var start: Int
    public var reading: String
    public var surface: String
    /// ⇧← → で区切りを変えた文節か
    public var isBoundary: Bool

    public init(start: Int, reading: String, surface: String, isBoundary: Bool = false) {
        self.start = start
        self.reading = reading
        self.surface = surface
        self.isBoundary = isBoundary
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
        /// ⇧←：対象の文節を 1 文字縮める
        case shrink
        /// ⇧→：対象の文節を 1 文字伸ばす
        case extend
        /// Shift+Space：英単語どうしの間などに空白をそのまま入れる
        case literalSpace

        /// キー操作のうち、パネルが扱うもの。修飾キーつき（⇧ を除く）は本来のキー処理に任せる
        public init?(userAction: UserAction, modifiers: KeyEventCore.ModifierFlag) {
            guard modifiers.isDisjoint(with: [.command, .option, .control]) else {
                return nil
            }
            switch userAction {
            case .navigation(.left):
                self = modifiers.contains(.shift) ? .shrink : .left
            case .navigation(.right):
                self = modifiers.contains(.shift) ? .extend : .right
            case .navigation(.up):
                self = .up
            case .navigation(.down):
                self = .down
            case .space:
                self = modifiers.contains(.shift) ? .literalSpace : .space
            case .tab:
                self = .tab
            case .escape:
                self = .escape
            default:
                return nil
            }
        }
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

    /// 区切りの覆いかぶせを当てた文節の列（表記はまだ当てない）。
    /// 区切りを変えた文節は `convert`（読みから表記を作る）で表記を決め、
    /// 区切りの変更で一部だけ残ったエンジンの文節も `convert` で表記を作り直す
    public func segmented(_ clauses: [LiveConversionClause], convert: (String) -> String) -> [LiveConversionClause] {
        let text = Array(clauses.map(\.reading).joined())
        let boundaries = self.overrides
            .filter { override in
                // その位置の読みが変わっていない区切りだけを使う
                override.isBoundary
                    && override.start + override.reading.count <= text.count
                    && String(text[override.start..<override.start + override.reading.count]) == override.reading
            }
            .sorted { $0.start < $1.start }
        guard !boundaries.isEmpty else {
            return clauses
        }
        let starts = Self.starts(of: clauses)
        var result: [LiveConversionClause] = []
        var position = 0
        func appendEngineClauses(upTo end: Int) {
            for (clause, start) in zip(clauses, starts) {
                let from = max(start, position)
                let to = min(start + clause.reading.count, end)
                guard from < to else {
                    continue
                }
                if from == start, to == start + clause.reading.count {
                    result.append(clause)
                } else {
                    let reading = String(text[from..<to])
                    result.append(.init(reading: reading, surface: convert(reading)))
                }
            }
            position = max(position, end)
        }
        for boundary in boundaries where boundary.start >= position {
            appendEngineClauses(upTo: boundary.start)
            result.append(.init(reading: boundary.reading, surface: convert(boundary.reading)))
            position = boundary.start + boundary.reading.count
        }
        appendEngineClauses(upTo: text.count)
        return result
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
        candidates: (Int) -> [String],
        convert: (String) -> String = { $0 }
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
        case .shrink, .extend:
            self.resize(by: key == .extend ? 1 : -1, at: target, in: clauses, convert: convert)
        case .literalSpace:
            // 空白を入れるのは入力の変更なので、SegmentsManager が受け持つ
            return .notHandled
        }
        return .handled
    }

    /// 表示中の対象から 1 つ動かす。入力中に押したときも、自動で決まった対象から動かす
    private mutating func moveTarget(by delta: Int, from target: Int, clauseCount: Int) {
        self.mode = .selecting(min(max(target + delta, 0), clauseCount - 1))
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
        // 区切りを変えた文節で候補を選んでも、区切りは保つ
        let isBoundary = self.overrides.first { $0.start == start }?.isBoundary ?? false
        self.overrides.removeAll { $0.start == start }
        self.overrides.append(.init(start: start, reading: reading, surface: surface, isBoundary: isBoundary))
    }

    /// 対象の文節の区切りを 1 文字動かす。伸ばすときは次の文節の先頭を取り込み、縮めるときは末尾を次の文節へ送る
    private mutating func resize(by delta: Int, at target: Int, in clauses: [LiveConversionClause], convert: (String) -> String) {
        if case .typing = self.mode {
            self.mode = .selecting(target)
        }
        self.isExpanded = false
        let start = Self.starts(of: clauses)[target]
        var reading = Array(clauses[target].reading)
        var next = target + 1 < clauses.count ? Array(clauses[target + 1].reading) : []
        if delta > 0 {
            // 未変換のローマ字は取り込まない。英単語の文節（英字のままエンジンに渡したもの）は取り込む
            guard !next.isEmpty, !clauses[target + 1].isUnconverted else {
                return
            }
            reading.append(next.removeFirst())
        } else {
            guard reading.count > 1 else {
                return
            }
            next.insert(reading.removeLast(), at: 0)
        }
        let end = start + reading.count + next.count
        self.overrides.removeAll { $0.start < end && $0.start + $0.reading.count > start }
        let targetReading = String(reading)
        self.overrides.append(.init(start: start, reading: targetReading, surface: convert(targetReading), isBoundary: true))
        if !next.isEmpty {
            let nextReading = String(next)
            self.overrides.append(.init(start: start + reading.count, reading: nextReading, surface: convert(nextReading), isBoundary: true))
        }
    }
}
