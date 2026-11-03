import KanaKanjiConverterModuleWithDefaultDictionary

/// 英単語かどうかの判定。アプリでは macOS のスペルチェッカーを使う
public protocol EnglishWordChecker: Sendable {
    /// 小文字にした語を受け取る
    func isEnglishWord(_ word: String) -> Bool
}

/// 英単語の判定を語ごとに覚えて使い回す。打つたびに同じ語を何度も調べないため
final class CachingEnglishWordChecker: EnglishWordChecker, @unchecked Sendable {
    private let base: any EnglishWordChecker
    private var results: [String: Bool] = [:]

    init(base: any EnglishWordChecker) {
        self.base = base
    }

    func isEnglishWord(_ word: String) -> Bool {
        if let cached = self.results[word] {
            return cached
        }
        let result = self.base.isEnglishWord(word)
        // 覚えすぎないよう、ある程度たまったら捨てる
        if self.results.count > 10_000 {
            self.results.removeAll(keepingCapacity: true)
        }
        self.results[word] = result
        return result
    }
}

/// 日本語のローマ字と英単語が混ざった入力から、英字のまま渡す範囲を見つける（仕様の 10.）
///
/// - ローマ字として読めずに英字が残る位置を含み、英単語と認められる部分は英語とする（「stacked」→「sたcけd」）
/// - 大文字で始まる語は英語とする（「PR」「Stacked」「GitHub」）
/// - 日本語として読んだときに辞書の語に収まらない英単語は英語とする（「commit＋site」→「こっ｜みつ｜ィて」）。
///   日本語として打った部分は辞書の長い語にまとまり（「酒」「に来てください」）、英語として打った部分は細切れや
///   辞書にない字の並べ方で埋められる（「こっ｜みつ｜ィ」「キテ」）ことを使う
public enum MixedInputDetector {
    /// エンジンが辞書にない字の並べ方で埋めた要素の mid
    fileprivate static let unknownWordMid = 501
    /// 英単語として探す最大の長さ
    fileprivate static let maxWordLength = 15

    /// 打った文字を全部日本語として読んで変換したときの 1 位の語の並び
    public struct JapaneseReading: Sendable {
        public var elements: [DicdataElement]
        /// 調べる文字の並びの先頭が、読みの何文字目に当たるか（末尾だけを調べるとき）
        public var offset: Int

        public init(elements: [DicdataElement], offset: Int = 0) {
            self.elements = elements
            self.offset = offset
        }
    }

    /// - Parameters:
    ///   - typed: 打った文字の並び
    ///   - inputStyle: 日本語として打った部分のローマ字かな変換
    ///   - japaneseReading: 日本語として読んだときの語の並び。`nil` なら辞書による見分けはしない
    /// - Returns: 英字のまま渡す範囲（`typed` の位置）。重ならず、前から順
    public static func englishRanges(
        in typed: [Character],
        inputStyle: InputStyle,
        japaneseReading: JapaneseReading? = nil,
        checker: some EnglishWordChecker
    ) -> [Range<Int>] {
        let lowercaseRanges = Self.lowercaseEnglishRanges(in: typed, inputStyle: inputStyle, checker: checker)
        let capitalizedRanges = Self.capitalizedRanges(in: typed, avoiding: lowercaseRanges, inputStyle: inputStyle, checker: checker)
        let ruleRanges = Self.merged(lowercaseRanges + capitalizedRanges)
        guard let japaneseReading else {
            return ruleRanges
        }
        let rule = DictionaryRule(chars: typed, reading: japaneseReading, inputStyle: inputStyle, checker: checker)
        return Self.merged(ruleRanges + rule.englishRanges(avoiding: ruleRanges))
    }

    // MARK: - 辞書の当てはまり方による見分け

    private struct DictionaryRule {
        let chars: [Character]
        let inputStyle: InputStyle
        let checker: any EnglishWordChecker
        /// 先頭から k 文字を日本語として読んだときの、読みの中での位置
        let kanaLengths: [Int]
        /// 先頭から k 文字の読みが、全体の読みの頭と一致しているか（音節の途中で切れていないか）
        let alignedPrefixes: [Bool]
        /// 語ごとの読みの範囲と、辞書の語か
        let elementRanges: [(range: Range<Int>, isDictionaryWord: Bool)]
        let elements: [DicdataElement]
        /// 語の途中で英単語を始めない語の読みの範囲と、片仮名だけの語か。辞書の語に加え、学習した片仮名語（「コマンド」）も含む
        let wordRanges: [(range: Range<Int>, isKatakana: Bool)]

        init(chars: [Character], reading: JapaneseReading, inputStyle: InputStyle, checker: any EnglishWordChecker) {
            self.chars = chars
            self.inputStyle = inputStyle
            self.checker = checker
            var kanaLengths = [reading.offset]
            var prefixes = [""]
            var text = ComposingText()
            for character in chars {
                text.insertAtCursorPosition(String(character), inputStyle: inputStyle)
                kanaLengths.append(reading.offset + text.convertTarget.count)
                prefixes.append(text.convertTarget)
            }
            self.kanaLengths = kanaLengths
            let whole = text.convertTarget
            self.alignedPrefixes = prefixes.map { whole.hasPrefix($0) }
            var elementRanges: [(range: Range<Int>, isDictionaryWord: Bool)] = []
            var wordRanges: [(range: Range<Int>, isKatakana: Bool)] = []
            var position = 0
            for element in reading.elements {
                let range = position..<(position + element.ruby.count)
                elementRanges.append((range, Self.isDictionaryWord(element)))
                if element.mid != MixedInputDetector.unknownWordMid {
                    wordRanges.append((range, element.word.unicodeScalars.allSatisfy { (0x30A1...0x30FC).contains($0.value) }))
                }
                position += element.ruby.count
            }
            self.elementRanges = elementRanges
            self.wordRanges = wordRanges
            self.elements = reading.elements
        }

        /// 辞書の語として数えるか。辞書にない字の並べ方で埋めた要素と、学習から来たかなだけの語
        /// （英単語をローマ字のつもりで打って確定した「コッミツィテ」など）は数えない
        private static func isDictionaryWord(_ element: DicdataElement) -> Bool {
            if element.mid == MixedInputDetector.unknownWordMid {
                return false
            }
            if element.metadata.contains(.isLearned), LiveConversionConfidence.isKanaOnly(element.word) {
                return false
            }
            return true
        }

        func englishRanges(avoiding ruleRanges: [Range<Int>]) -> [Range<Int>] {
            var found: [Range<Int>] = []
            var start = 0
            // 直前の英単語の後ろ（segmentStart）から k 文字目までが、ローマ字として読み切れているか
            var segmentStart = 0
            var clean = MixedInputDetector.cleanFlags(self.chars, from: 0, inputStyle: self.inputStyle)
            while start < self.chars.count {
                if let rule = ruleRanges.first(where: { $0.contains(start) }) {
                    // 規則で英語と決まった部分は飛ばし、その後ろから読み直す
                    start = rule.upperBound
                } else if self.chars[start].isLowercase, clean[start - segmentStart],
                          // 全体の読みと位置が合う所からだけ（commit｜site の s は、全体の読みでは「つぃ」の途中）
                          self.alignedPrefixes[start],
                          let end = self.wordEnd(from: start, avoiding: ruleRanges, isClean: { clean[$0 - segmentStart] }) {
                    found.append(start..<end)
                    start = end
                } else {
                    start += 1
                    continue
                }
                if start < self.chars.count {
                    segmentStart = start
                    clean = MixedInputDetector.cleanFlags(self.chars, from: start, inputStyle: self.inputStyle)
                }
            }
            return found
        }

        /// `start` から始まる英単語の終わり。見つからなければ `nil`
        private func wordEnd(from start: Int, avoiding ruleRanges: [Range<Int>], isClean: (Int) -> Bool) -> Int? {
            for end in stride(from: min(self.chars.count, start + MixedInputDetector.maxWordLength), through: start + 3, by: -1) {
                let word = self.chars[start..<end]
                guard word.allSatisfy(\.isLowercase),
                      !ruleRanges.contains(where: { $0.overlaps(start..<end) }),
                      !self.joinsNextSyllable(end),
                      // ローマ字として読める英単語は、終わりも音節の切れ目に合っているものだけ
                      !MixedInputDetector.isCleanRomaji(word, inputStyle: self.inputStyle) || isClean(end),
                      !self.isUnfinishedRomaji(word, end: end),
                      self.checker.isEnglishWord(String(word)),
                      !self.isCoveredByDictionaryWord(start, end),
                      !self.cutsDictionaryWord(at: start),
                      !self.isSpelledByDictionaryWords(start, end) else {
                    continue
                }
                // 後ろに母音が続くなら s は日本語の側に回す（commits＋ite → commit＋site）
                if self.chars[end - 1] == "s", end < self.chars.count, "aiueo".contains(self.chars[end]),
                   self.checker.isEnglishWord(String(self.chars[start..<(end - 1)])) {
                    return end - 1
                }
                return end
            }
            return nil
        }

        /// 最後の子音が後ろと組んで自然な音節になる切り方か。sake｜wo の kew、nod｜hi の dhi（でぃ）
        private func joinsNextSyllable(_ end: Int) -> Bool {
            guard end < self.chars.count, !"aiueo".contains(self.chars[end - 1]) else {
                return false
            }
            if "aiueoy".contains(self.chars[end]) {
                return true
            }
            return self.chars[end] == "h" && "cdstw".contains(self.chars[end - 1])
        }

        /// 入力の末尾で、子音を打ちかけているだけの語か（「komanndoh」の doh は、次に a を打てば「どは」）。
        /// まだ英語か決めない
        private func isUnfinishedRomaji(_ word: ArraySlice<Character>, end: Int) -> Bool {
            guard end == self.chars.count, !MixedInputDetector.isCleanRomaji(word, inputStyle: self.inputStyle) else {
                return false
            }
            return "aiueo".contains { vowel in
                MixedInputDetector.isCleanRomaji(word + [vowel], inputStyle: self.inputStyle)
            }
        }

        /// 英単語の頭が、日本語として読んだときの語の途中に当たるか（「ディレクトリ＋で」の ride、「コマンド＋は」の doha、
        /// 「コマ＋n」の man）。学習した片仮名語も語として数える（英単語を誤って確定した「コッミツィテ」でも、
        /// commit は語の頭から始まるので止めない）。「を得」の「え」から始まる edit のように、漢字を含む語の 2 文字目に
        /// 当たるだけなら切ってよい
        private func cutsDictionaryWord(at start: Int) -> Bool {
            let position = self.kanaLengths[start]
            return self.wordRanges.contains { word in
                word.range.lowerBound < position && position < word.range.upperBound
                    && (word.isKatakana || word.range.lowerBound + 2 <= position)
            }
        }

        /// 英単語の範囲が、辞書の語を並べた 1 つの文節としてぴったり読め、ひらがな 1 文字の付属語で終わるか
        /// （「ように＋し＋て」の site、「来＋て」の kite）。文節が分かれる並び（rebase の「レバ｜背」）や、
        /// 付属語で終わらない並び（issue の「いッ＋末」）は英語のまま。
        /// 終わりが音節の切れ目に合っていないときは、読みの位置がずれるので調べない
        private func isSpelledByDictionaryWords(_ start: Int, _ end: Int) -> Bool {
            guard self.alignedPrefixes[end] else {
                return false
            }
            let span = self.kanaLengths[start]..<self.kanaLengths[end]
            let covering = self.elementRanges.indices.filter { self.elementRanges[$0].range.overlaps(span) }
            guard let first = covering.first, let last = covering.last,
                  self.elementRanges[first].range.lowerBound == span.lowerBound,
                  self.elementRanges[last].range.upperBound == span.upperBound,
                  covering.allSatisfy({ self.elementRanges[$0].isDictionaryWord }) else {
                return false
            }
            let words = Array(self.elements[first...last])
            guard words.count >= 2, let tail = words.last?.word, tail.count == 1,
                  tail.unicodeScalars.allSatisfy({ (0x3041...0x3096).contains($0.value) }) else {
                return false
            }
            return Candidate.makePrefixClauseCandidate(data: words).data.count == words.count
        }

        private func isCoveredByDictionaryWord(_ start: Int, _ end: Int) -> Bool {
            let span = self.kanaLengths[start]..<self.kanaLengths[end]
            let element = self.elementRanges.first { $0.range.lowerBound <= span.lowerBound && $0.range.upperBound >= span.upperBound }
            return element?.isDictionaryWord ?? false
        }
    }

    /// 未確定文字列のうち `range`（文字の位置）に当たる部分を打ったときのキーの並び。「来て」の文節なら「kite」
    public static func typedText(forConvertTargetRange range: Range<Int>, in input: [ComposingText.InputElement]) -> String? {
        var lengths: [Int] = [0]
        var text = ComposingText()
        for element in input {
            text.insertAtCursorPosition([element])
            lengths.append(text.convertTarget.count)
        }
        guard let start = lengths.firstIndex(of: range.lowerBound),
              let end = lengths.lastIndex(of: range.upperBound),
              start < end else {
            return nil
        }
        var typed = ""
        for element in input[start..<end] {
            switch element.piece {
            case .character(let character):
                typed.append(character)
            case .key(let intention, let input, _):
                typed.append(intention ?? input)
            case .compositionSeparator:
                return nil
            }
        }
        return typed
    }

    // MARK: - 小文字の英単語

    private static func lowercaseEnglishRanges(in chars: [Character], inputStyle: InputStyle, checker: some EnglishWordChecker) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var segmentStart = 0
        while let stray = Self.sealedStray(chars, from: segmentStart, inputStyle: inputStyle) {
            var best: Range<Int>?
            let clean = Self.cleanFlags(chars, from: segmentStart, inputStyle: inputStyle)
            // 英単語は、それより前の日本語の部分がローマ字として読み切れている位置からだけ始める
            for start in stride(from: stray, through: segmentStart, by: -1)
            where chars[start].isLowercase && clean[start - segmentStart] {
                for end in stride(from: min(chars.count, start + Self.maxWordLength), through: start + 2, by: -1) {
                    let word = String(chars[start..<end])
                    guard word.allSatisfy(\.isLowercase),
                          !Self.isCleanRomaji(chars[start..<end], inputStyle: inputStyle),
                          checker.isEnglishWord(word) else {
                        continue
                    }
                    if best.map({ end - start > $0.count }) ?? true {
                        best = start..<end
                    }
                    break
                }
            }
            guard var range = best else {
                segmentStart = stray + 1
                continue
            }
            // 「deploys＋uru」より「deploy＋suru」：後ろに母音が続くなら s は日本語の側に回す
            if chars[range.upperBound - 1] == "s", range.upperBound < chars.count, "aiueo".contains(chars[range.upperBound]),
               checker.isEnglishWord(String(chars[range.lowerBound..<(range.upperBound - 1)])) {
                range = range.lowerBound..<(range.upperBound - 1)
            }
            found.append(range)
            segmentStart = range.upperBound
        }
        return found
    }

    /// ローマ字として読めずに英字が残り、もう読み直されない位置（その時点までの入力の長さ - 1）。
    /// 後ろにかなが続いたとき、または入力の末尾で母音を足しても英字が残るとき（「test」の「st」）に、読み直されないとみなす
    private static func sealedStray(_ chars: [Character], from start: Int, inputStyle: InputStyle) -> Int? {
        guard start < chars.count else {
            return nil
        }
        // 1 文字ずつ足しながら調べる（毎回最初から変換し直さない）
        var text = ComposingText()
        for end in (start + 1)...chars.count {
            text.insertAtCursorPosition(String(chars[end - 1]), inputStyle: inputStyle)
            if Self.hasSealedStray(text.convertTarget) {
                return end - 1
            }
        }
        // 入力の末尾は、母音を足しても英字が残るかで見る
        text.insertAtCursorPosition("a", inputStyle: inputStyle)
        return Self.hasSealedStray(text.convertTarget) ? chars.count - 1 : nil
    }

    /// `start` から k 文字（k = 0...）を、ローマ字として読み切れているか
    fileprivate static func cleanFlags(_ chars: [Character], from start: Int, inputStyle: InputStyle) -> [Bool] {
        var flags = [true]
        var text = ComposingText()
        for character in chars[start...] {
            text.insertAtCursorPosition(String(character), inputStyle: inputStyle)
            flags.append(Self.isCleanConverted(text.convertTarget))
        }
        return flags
    }

    // MARK: - 大文字で始まる語

    private static func capitalizedRanges(
        in chars: [Character],
        avoiding lowercaseRanges: [Range<Int>],
        inputStyle: InputStyle,
        checker: some EnglishWordChecker
    ) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var index = 0
        while index < chars.count {
            guard chars[index].isUppercase, chars[index].isASCII,
                  !lowercaseRanges.contains(where: { $0.contains(index) }) else {
                index += 1
                continue
            }
            let range = Self.capitalizedWord(in: chars, at: index, avoiding: lowercaseRanges, inputStyle: inputStyle, checker: checker)
            found.append(range)
            index = range.upperBound
        }
        return found
    }

    private static func capitalizedWord(
        in chars: [Character],
        at start: Int,
        avoiding lowercaseRanges: [Range<Int>],
        inputStyle: InputStyle,
        checker: some EnglishWordChecker
    ) -> Range<Int> {
        // 次の英単語・空白・英字以外の手前まで
        let limit = (start..<chars.count).first { position in
            position > start && (!chars[position].isLetter || !chars[position].isASCII || lowercaseRanges.contains { $0.lowerBound == position })
        } ?? chars.count
        // 英単語として認められる最も長い部分（「Stacked」）
        for end in stride(from: min(limit, start + Self.maxWordLength), through: start + 2, by: -1)
        where checker.isEnglishWord(String(chars[start..<end]).lowercased()) {
            return start..<end
        }
        // 大文字が続く間（「PR」）と、そのあとの小文字のうち、後ろがローマ字としてきれいに読めるところまで（「GitHub」）
        var upper = start + 1
        while upper < limit, chars[upper].isUppercase {
            upper += 1
        }
        var lowerEnd = upper
        while lowerEnd < limit, chars[lowerEnd].isLowercase {
            lowerEnd += 1
        }
        if lowerEnd < limit, chars[lowerEnd].isUppercase {
            // 次も大文字なら、ひと続きの名前の途中（「Git」→「Hub」）
            return start..<lowerEnd
        }
        for end in upper...lowerEnd {
            let taken = chars[upper..<end]
            let rest = chars[end..<min(end + 4, limit)]
            if taken.isEmpty || !Self.isCleanRomaji(taken, inputStyle: inputStyle), Self.hasNoSealedStray(rest, inputStyle: inputStyle) {
                return start..<end
            }
        }
        return start..<lowerEnd
    }

    // MARK: - 共通

    private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, last.upperBound >= range.lowerBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func convert(_ chars: ArraySlice<Character>, inputStyle: InputStyle) -> String {
        var text = ComposingText()
        text.insertAtCursorPosition(String(chars), inputStyle: inputStyle)
        return text.convertTarget
    }

    /// ローマ字として読み切れているか（小文字の英字が残らない。末尾の n は許す）
    fileprivate static func isCleanRomaji(_ chars: ArraySlice<Character>, inputStyle: InputStyle) -> Bool {
        Self.isCleanConverted(Self.convert(chars, inputStyle: inputStyle))
    }

    private static func isCleanConverted(_ converted: String) -> Bool {
        var converted = converted
        if converted.hasSuffix("n") {
            converted.removeLast()
        }
        return !converted.unicodeScalars.contains(where: Self.isLowercaseASCII)
    }

    private static func hasNoSealedStray(_ chars: ArraySlice<Character>, inputStyle: InputStyle) -> Bool {
        !Self.hasSealedStray(Self.convert(chars, inputStyle: inputStyle))
    }

    /// 小文字の英字のすぐ後ろに、英字以外が続いているか
    private static func hasSealedStray(_ converted: String) -> Bool {
        let scalars = Array(converted.unicodeScalars)
        return scalars.indices.dropLast().contains { index in
            Self.isLowercaseASCII(scalars[index]) && !Self.isLowercaseASCII(scalars[index + 1])
        }
    }

    private static func isLowercaseASCII(_ scalar: Unicode.Scalar) -> Bool {
        (0x61...0x7A).contains(scalar.value)
    }
}
