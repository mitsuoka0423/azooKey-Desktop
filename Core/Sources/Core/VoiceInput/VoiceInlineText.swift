/// 聞き取り中に本文へ出す未確定文字列。
///
/// 固まった部分（`VoiceInlineText.Settled`）は実線、まだ変わる部分（`VoiceInlineText.Live`）は点線の下線で見せる。
public struct VoiceInlineText: Sendable, Equatable {
    /// 区切られた発話。もう変わらない
    public var settled: String
    /// 今話している発話。認識が進むと変わる
    public var live: String

    public init(settled: String = "", live: String = "") {
        self.settled = settled
        self.live = live
    }

    public var text: String {
        self.settled + self.live
    }

    public var isEmpty: Bool {
        self.settled.isEmpty && self.live.isEmpty
    }
}
