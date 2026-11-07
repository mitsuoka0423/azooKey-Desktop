import Foundation

/// 音声入力の状態と、出来事ごとの状態の変化をまとめた型。
///
/// 録音や認識そのもの（AVAudioEngine・Speech）は持たない。
/// アプリ側は出来事（`Event`）を渡し、返ってきた `Outcome` の `effects` を順に実行する。
public struct VoiceInputSession: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// 音声入力をしていない
        case idle
        /// 聞き取り中。途中までの認識結果を未確定文字列として見せる
        case listening
        /// 止める操作のあと、認識の最後の結果を待っている
        case finishing
    }

    /// 音声入力を使えなかった理由
    public enum Failure: Sendable, Equatable {
        /// マイクの使用が許可されていない
        case microphoneDenied
        /// 音声認識が許可されていない
        case speechRecognitionDenied
        /// この Mac では日本語のオンデバイス認識が使えない
        case onDeviceRecognitionUnavailable
        /// 日本語の認識モデルを用意できない（ダウンロード中・ダウンロードに失敗した）
        case modelUnavailable
        /// そのほかの失敗（録音の開始に失敗した、認識が途中で止まった、など）
        case other(String)

        /// 許可がないときに開くシステム設定の画面
        public var privacySettingsURL: URL? {
            switch self {
            case .microphoneDenied:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            case .speechRecognitionDenied:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            case .onDeviceRecognitionUnavailable, .modelUnavailable, .other:
                nil
            }
        }
    }

    public enum Event: Sendable, Equatable {
        /// 始める・止めるショートカット、またはメニュー
        case toggle
        /// 途中までの認識結果（今の発話のそれまで全体）。区切りの知らせなしにやり直すことがある（SFSpeechRecognizer）
        case partialResult(String)
        /// まだ変わる認識結果（区切りの知らせのあとから今までの全体）。やり直しの見分けはしない（SpeechTranscriber）
        case volatileResult(String)
        /// 話の間で発話が区切られた（その発話の認識結果）。次の結果は新しい発話になる
        case utteranceEnded(String)
        /// 認識の最後の結果（最後の発話の認識結果）
        case finalResult(String)
        /// 認識できなかった・止まった
        case failed(Failure)
        /// 止めたあと、最後の結果が来ないまま時間が過ぎた
        case finishTimedOut
        /// Enter キー
        case enter
        /// Escape キー
        case escape
        /// そのほかのキー
        case otherKey
        /// 入力先から離れた（別のアプリ・別の入力欄に移った）
        case focusLost
    }

    public enum Effect: Sendable, Equatable {
        /// 録音と認識を始める
        case startRecognition
        /// 録音を止め、認識の最後の結果を求める
        case finishRecognition
        /// 録音と認識を捨てる
        case cancelRecognition
        /// 未確定文字列を置き換える（固まった部分と、まだ変わる部分に分けて渡す）
        case setMarkedText(VoiceInlineText)
        /// 未確定文字列を消す
        case clearMarkedText
        /// 文字を確定する（未確定文字列はこの文字で置き換わる）
        case commit(String)
        /// 失敗を知らせる
        case report(Failure)
    }

    public struct Outcome: Sendable, Equatable {
        public var effects: [Effect]
        /// キーイベントを音声入力が受け持ったか。`false` ならふだんのキー処理に回す
        public var consumesKey: Bool

        public init(effects: [Effect], consumesKey: Bool) {
            self.effects = effects
            self.consumesKey = consumesKey
        }

        static let ignored = Outcome(effects: [], consumesKey: false)
    }

    public private(set) var phase: Phase = .idle
    /// それまでに認識した文字（発話ごとの結果をつないだもの）
    public private(set) var recognized = VoiceTranscript()

    /// それまでに認識した文字
    public var transcript: String {
        self.recognized.text
    }

    public init() {}

    /// 音声入力をしているか（聞き取り中か、最後の結果を待っているか）
    public var isActive: Bool {
        self.phase != .idle
    }

    /// 今見せる未確定文字列。まだ何も認識していないあいだは空にして、本文には何も入れない
    /// （聞き取り中であることは、聞き取りピルで見せる）
    public var markedText: VoiceInlineText {
        switch self.phase {
        case .idle:
            VoiceInlineText()
        case .listening, .finishing:
            self.recognized.inlineText
        }
    }

    public mutating func handle(_ event: Event) -> Outcome {
        switch self.phase {
        case .idle:
            return self.handleWhenIdle(event)
        case .listening:
            return self.handleWhenListening(event)
        case .finishing:
            return self.handleWhenFinishing(event)
        }
    }

    private mutating func handleWhenIdle(_ event: Event) -> Outcome {
        switch event {
        case .toggle:
            self.phase = .listening
            self.recognized = VoiceTranscript()
            return Outcome(effects: [.startRecognition], consumesKey: true)
        case .partialResult, .volatileResult, .utteranceEnded, .finalResult, .failed, .finishTimedOut, .enter, .escape, .otherKey, .focusLost:
            return .ignored
        }
    }

    private mutating func handleWhenListening(_ event: Event) -> Outcome {
        switch event {
        case .toggle, .enter:
            self.phase = .finishing
            return Outcome(effects: [.finishRecognition], consumesKey: true)
        case .partialResult(let text):
            self.recognized.updateCurrent(text)
            return Outcome(effects: [.setMarkedText(self.markedText)], consumesKey: false)
        case .volatileResult(let text):
            self.recognized.replaceCurrent(text)
            return Outcome(effects: [.setMarkedText(self.markedText)], consumesKey: false)
        case .utteranceEnded(let text):
            self.recognized.endUtterance(text)
            return Outcome(effects: [.setMarkedText(self.markedText)], consumesKey: false)
        case .finalResult(let text):
            // 話し終わりを認識側が判断して止まった
            return self.finish(with: self.recognized.finalText(text), extraEffects: [], consumesKey: false)
        case .failed(let failure):
            return self.finish(with: self.transcript, extraEffects: [.cancelRecognition], trailingEffects: [.report(failure)], consumesKey: false)
        case .finishTimedOut:
            return .ignored
        case .escape:
            return self.discard()
        case .otherKey:
            // 聞き取りを打ち切って、ここまでの文字を確定してから、キーはふだんどおりに処理する
            return self.finish(with: self.transcript, extraEffects: [.cancelRecognition], consumesKey: false)
        case .focusLost:
            return self.finish(with: self.transcript, extraEffects: [.cancelRecognition], consumesKey: false)
        }
    }

    private mutating func handleWhenFinishing(_ event: Event) -> Outcome {
        switch event {
        case .toggle, .enter:
            // 最後の結果を待たずに、ここまでの文字で確定する
            return self.finish(with: self.transcript, extraEffects: [.cancelRecognition], consumesKey: true)
        case .partialResult(let text):
            self.recognized.updateCurrent(text)
            return Outcome(effects: [.setMarkedText(self.markedText)], consumesKey: false)
        case .volatileResult(let text):
            self.recognized.replaceCurrent(text)
            return Outcome(effects: [.setMarkedText(self.markedText)], consumesKey: false)
        case .utteranceEnded(let text):
            self.recognized.endUtterance(text)
            return Outcome(effects: [.setMarkedText(self.markedText)], consumesKey: false)
        case .finalResult(let text):
            return self.finish(with: self.recognized.finalText(text), extraEffects: [], consumesKey: false)
        case .failed(let failure):
            return self.finish(with: self.transcript, extraEffects: [.cancelRecognition], trailingEffects: [.report(failure)], consumesKey: false)
        case .finishTimedOut, .focusLost:
            return self.finish(with: self.transcript, extraEffects: [.cancelRecognition], consumesKey: false)
        case .otherKey:
            return self.finish(with: self.transcript, extraEffects: [.cancelRecognition], consumesKey: false)
        case .escape:
            return self.discard()
        }
    }

    private mutating func finish(with text: String, extraEffects: [Effect], trailingEffects: [Effect] = [], consumesKey: Bool) -> Outcome {
        self.phase = .idle
        self.recognized = VoiceTranscript()
        let commitEffect: Effect = text.isEmpty ? .clearMarkedText : .commit(text)
        return Outcome(effects: extraEffects + [commitEffect] + trailingEffects, consumesKey: consumesKey)
    }

    private mutating func discard() -> Outcome {
        self.phase = .idle
        self.recognized = VoiceTranscript()
        return Outcome(effects: [.cancelRecognition, .clearMarkedText], consumesKey: true)
    }
}
