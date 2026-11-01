import KanaKanjiConverterModuleWithDefaultDictionary

/// 英単語かどうかの判定。アプリでは macOS のスペルチェッカーを使う
public protocol EnglishWordChecker: Sendable {
    /// 小文字にした語を受け取る
    func isEnglishWord(_ word: String) -> Bool
}

/// 日本語のローマ字と英単語が混ざった入力から、英字のまま渡す範囲を見つける（仕様の 10.）
///
/// - ローマ字として読めずに英字が残る位置を含み、英単語と認められる部分は英語とする（「stacked」→「sたcけd」）
/// - 大文字で始まる語は英語とする（「PR」「Stacked」「GitHub」）
/// - ローマ字としても読める英単語（「kite」「commit＋suru」）は日本語のままにする
public enum MixedInputDetector {
    /// 英単語として探す最大の長さ
    private static let maxWordLength = 15

    /// - Parameters:
    ///   - typed: 打った文字の並び
    ///   - inputStyle: 日本語として打った部分のローマ字かな変換
    /// - Returns: 英字のまま渡す範囲（`typed` の位置）。重ならず、前から順
    public static func englishRanges(in typed: [Character], inputStyle: InputStyle, checker: some EnglishWordChecker) -> [Range<Int>] {
        let lowercaseRanges = Self.lowercaseEnglishRanges(in: typed, inputStyle: inputStyle, checker: checker)
        let capitalizedRanges = Self.capitalizedRanges(in: typed, avoiding: lowercaseRanges, inputStyle: inputStyle, checker: checker)
        return Self.merged(lowercaseRanges + capitalizedRanges)
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
            // 英単語は、それより前の日本語の部分がローマ字として読み切れている位置からだけ始める
            for start in stride(from: stray, through: segmentStart, by: -1)
            where chars[start].isLowercase && Self.isCleanRomaji(chars[segmentStart..<start], inputStyle: inputStyle) {
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
        for end in (start + 1)...chars.count {
            var slice = Array(chars[start..<end])
            if end == chars.count {
                slice.append("a")
            }
            let converted = Array(Self.convert(slice[...], inputStyle: inputStyle).unicodeScalars)
            for index in converted.indices.dropLast()
            where Self.isLowercaseASCII(converted[index]) && !Self.isLowercaseASCII(converted[index + 1]) {
                return end - 1
            }
        }
        return nil
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
    private static func isCleanRomaji(_ chars: ArraySlice<Character>, inputStyle: InputStyle) -> Bool {
        var converted = Self.convert(chars, inputStyle: inputStyle)
        if converted.hasSuffix("n") {
            converted.removeLast()
        }
        return !converted.unicodeScalars.contains(where: Self.isLowercaseASCII)
    }

    private static func hasNoSealedStray(_ chars: ArraySlice<Character>, inputStyle: InputStyle) -> Bool {
        let converted = Array(Self.convert(chars, inputStyle: inputStyle).unicodeScalars)
        return !converted.indices.dropLast().contains { index in
            Self.isLowercaseASCII(converted[index]) && !Self.isLowercaseASCII(converted[index + 1])
        }
    }

    private static func isLowercaseASCII(_ scalar: Unicode.Scalar) -> Bool {
        (0x61...0x7A).contains(scalar.value)
    }
}
