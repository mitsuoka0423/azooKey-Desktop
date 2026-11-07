import Foundation

/// 聞き取り中に認識した文字をつなぎ合わせる。
///
/// オンデバイス認識（`SFSpeechRecognizer`）は、話の間（ポーズ）で発話を区切ると、次の結果を最初からやり直す。
/// 区切りは `speechRecognitionMetadata` の付いた結果で知らされ、`isFinal` は最後の 1 回だけ届く。
/// 最後の `isFinal` は、直前に区切られた発話と同じ文を繰り返すことがある。
/// ここでは、区切られた発話を「確かめた部分」にためて、今の発話とつないで見せる。
public struct VoiceTranscript: Sendable, Equatable {
    /// 区切られた発話をつないだもの
    public private(set) var confirmed: String = ""
    /// 今話している発話（途中の認識結果）
    public private(set) var current: String = ""
    /// 直前に区切られた発話。最後の結果が同じ文を繰り返したときに、二重につながないために持つ
    private var lastEndedUtterance: String?

    public init() {}

    /// 見せる・確定する文字
    public var text: String {
        Self.join(self.confirmed, self.current)
    }

    public var isEmpty: Bool {
        self.text.isEmpty
    }

    /// 途中の認識結果（今の発話のそれまで全体）を受け取る
    public mutating func updateCurrent(_ text: String) {
        if Self.isNewUtterance(previous: self.current, next: text) {
            // 区切りの知らせが来ないまま、やり直しになった
            self.confirmed = Self.join(self.confirmed, self.current)
        }
        self.current = text
        self.lastEndedUtterance = nil
    }

    /// 発話の区切り（その発話の認識結果）を受け取る
    public mutating func endUtterance(_ text: String) {
        let utterance = text.isEmpty ? self.current : text
        self.confirmed = Self.join(self.confirmed, utterance)
        self.current = ""
        self.lastEndedUtterance = utterance
    }

    /// 最後の認識結果を受け取って、確定する文字を返す
    public func finalText(_ text: String) -> String {
        if text.isEmpty {
            return self.text
        }
        if self.current.isEmpty, text == self.lastEndedUtterance {
            return self.confirmed
        }
        return Self.join(self.confirmed, text)
    }

    /// 前の結果の続きではなく、新しい発話が始まったように見えるか。
    ///
    /// 同じ発話の中でも、認識は前のほうの言葉を直すことがある（「今日ははい」→「今日はいい」）。
    /// 先頭が 1 文字も合わず、しかも短くなったときだけ、新しい発話とみなす。
    static func isNewUtterance(previous: String, next: String) -> Bool {
        guard !previous.isEmpty, !next.isEmpty else {
            return false
        }
        return previous.first != next.first && next.count < previous.count
    }

    /// 英数字どうしが続くときだけ、間に空白を入れてつなぐ
    static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else {
            return head + tail
        }
        if Self.isASCIIAlphanumeric(last), Self.isASCIIAlphanumeric(first) {
            return head + " " + tail
        }
        return head + tail
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
