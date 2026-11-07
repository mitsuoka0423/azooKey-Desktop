import Foundation
import Testing

@testable import Core

@Suite("VoiceInlineText")
struct VoiceInlineTextTests {
    @Test("区切られた発話は固まった部分、今の発話はまだ変わる部分に分ける")
    func splitSettledAndLive() {
        var transcript = VoiceTranscript()
        transcript.updateCurrent("今日の会議では")
        #expect(transcript.inlineText == VoiceInlineText(settled: "", live: "今日の会議では"))
        transcript.endUtterance("今日の会議では")
        #expect(transcript.inlineText == VoiceInlineText(settled: "今日の会議では", live: ""))
        transcript.updateCurrent("来週の予定を")
        #expect(transcript.inlineText == VoiceInlineText(settled: "今日の会議では", live: "来週の予定を"))
        #expect(transcript.inlineText.text == "今日の会議では来週の予定を")
    }

    @Test("英数字どうしの間の空白は、まだ変わる部分に含める")
    func spaceBelongsToLive() {
        var transcript = VoiceTranscript()
        transcript.endUtterance("Swift")
        transcript.updateCurrent("UI")
        #expect(transcript.inlineText == VoiceInlineText(settled: "Swift", live: " UI"))
    }
}

@Suite("VoicePillPresenter")
struct VoicePillPresenterTests {
    private let shortcut = KeyboardShortcut.defaultVoiceInputShortcut

    @Test("聞き取りを始めたら「聞き取り中」と脈打つマイク、声の揺れは点")
    func startedListening() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        let model = presenter.model(phase: .listening, now: 100.5, shortcut: self.shortcut, reduceMotion: false)
        #expect(model?.mic == .listening)
        #expect(model?.label == "聞き取り中")
        #expect(model?.isPulsing == true)
        #expect(model?.level == .silent)
        #expect(model?.keys == nil)
    }

    @Test("声があると、声の大きさで棒を揺らす")
    func speaking() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        presenter.updateLevel(0.6, at: 101)
        let model = presenter.model(phase: .listening, now: 101, shortcut: self.shortcut, reduceMotion: false)
        #expect(model?.level == .voice(0.6))
        #expect(model?.keys == nil)
    }

    @Test("声がないまま 2 秒たつと、止め方を出して声の揺れを隠す")
    func keysAfterSilence() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        presenter.updateLevel(0.6, at: 101)
        presenter.updateLevel(0.01, at: 102)
        #expect(presenter.model(phase: .listening, now: 102.9, shortcut: self.shortcut, reduceMotion: false)?.keys == nil)
        let model = presenter.model(phase: .listening, now: 103, shortcut: self.shortcut, reduceMotion: false)
        #expect(model?.keys == VoicePillModel.Keys(commitKey: "⌃⇧D"))
        #expect(model?.level == nil)
        #expect(model?.label == "聞き取り中")
    }

    @Test("一度も声がなくても、始めてから 2 秒で止め方を出す")
    func keysWithoutAnyVoice() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        #expect(presenter.model(phase: .listening, now: 102, shortcut: self.shortcut, reduceMotion: false)?.keys != nil)
    }

    @Test("認識結果が届いたら声があったとみなし、止め方を引っ込める")
    func recognitionCountsAsVoice() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        presenter.recognized(at: 103)
        #expect(presenter.model(phase: .listening, now: 104, shortcut: self.shortcut, reduceMotion: false)?.keys == nil)
    }

    @Test("止め方には設定したショートカットを出す")
    func keysUseConfiguredShortcut() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 0)
        let custom = KeyboardShortcut(key: "v", modifiers: [.option])
        #expect(presenter.model(phase: .listening, now: 5, shortcut: custom, reduceMotion: false)?.keys?.commitKey == "⌥V")
    }

    @Test("止めたあとは灰色のマイクで「仕上げ中…」、脈も揺れも止める")
    func finishing() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        let model = presenter.model(phase: .finishing, now: 101, shortcut: self.shortcut, reduceMotion: false)
        #expect(model == VoicePillModel(mic: .finishing, label: "仕上げ中…", isPulsing: false, level: nil, animatesLevel: false, keys: nil))
    }

    @Test("動きを減らす設定では、脈と揺れを止める")
    func reduceMotion() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        presenter.updateLevel(0.6, at: 100)
        let model = presenter.model(phase: .listening, now: 100, shortcut: self.shortcut, reduceMotion: true)
        #expect(model?.isPulsing == false)
        #expect(model?.animatesLevel == false)
        #expect(model?.level == .voice(0.6))
    }

    @Test("待機中はピルを出さない")
    func idleHidesPill() {
        var presenter = VoicePillPresenter()
        #expect(presenter.model(phase: .idle, now: 0, shortcut: self.shortcut, reduceMotion: false) == nil)
        presenter.start(at: 0)
        presenter.end()
        #expect(presenter.model(phase: .idle, now: 1, shortcut: self.shortcut, reduceMotion: false) == nil)
    }

    @Test("失敗したら、理由を 1 行で 3 秒出してから消す")
    func failure() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 100)
        presenter.fail(.microphoneDenied, at: 101)
        let model = presenter.model(phase: .idle, now: 103.9, shortcut: self.shortcut, reduceMotion: false)
        #expect(model == VoicePillModel(mic: .failed, label: "マイクが使えません", isPulsing: false, level: nil, animatesLevel: false, keys: nil))
        #expect(!presenter.isFailureExpired(at: 103.9))
        #expect(presenter.model(phase: .idle, now: 104, shortcut: self.shortcut, reduceMotion: false) == nil)
        #expect(presenter.isFailureExpired(at: 104))
    }

    @Test("失敗の理由ごとの文言")
    func failureMessages() {
        #expect(VoicePillPresenter.message(for: .microphoneDenied) == "マイクが使えません")
        #expect(VoicePillPresenter.message(for: .speechRecognitionDenied) == "音声認識が許可されていません")
        #expect(VoicePillPresenter.message(for: .onDeviceRecognitionUnavailable) == "この Mac では音声認識を使えません")
        #expect(VoicePillPresenter.message(for: .other("x")) == "うまく聞き取れませんでした")
    }

    @Test("もう一度始めたら、前の失敗の札は消す")
    func restartClearsFailure() {
        var presenter = VoicePillPresenter()
        presenter.fail(.microphoneDenied, at: 100)
        presenter.start(at: 101)
        #expect(presenter.model(phase: .listening, now: 101, shortcut: self.shortcut, reduceMotion: false)?.mic == .listening)
    }
}

@Suite("VoiceLevel")
struct VoiceLevelTests {
    @Test("RMS を -50dB〜-10dB で 0〜1 に直す")
    func normalize() {
        #expect(VoiceLevel.normalized(rms: 0) == 0)
        #expect(VoiceLevel.normalized(rms: 0.001) == 0) // -60dB
        #expect(abs(VoiceLevel.normalized(rms: 0.01) - 0.25) < 0.0001) // -40dB
        #expect(VoiceLevel.normalized(rms: 0.5) == 1)
    }

    @Test("棒の高さは声がないと 3pt、最大で 14pt。真ん中がいちばん高い")
    func barHeights() {
        #expect(VoiceLevel.barHeights(0) == [3, 3, 3])
        let heights = VoiceLevel.barHeights(1)
        #expect(heights[1] == 14)
        #expect(heights[0] < heights[1] && heights[2] < heights[1])
    }
}

@Suite("SpeechTranscriber の結果のつなぎ方")
struct SpeechTranscriberResultTests {
    @Test("volatile は今の発話を置き換え、finalized で区切る（実機の SpeechTranscriber が返した順）")
    func volatileAndFinalized() {
        var session = VoiceInputSession()
        _ = session.handle(.toggle)
        for text in ["今", "今日は", "今日はいい天気ですね。"] {
            _ = session.handle(.volatileResult(text))
        }
        #expect(session.markedText == VoiceInlineText(live: "今日はいい天気ですね。"))
        _ = session.handle(.utteranceEnded("今日はいい天気ですね。"))
        _ = session.handle(.volatileResult("明日の会議は 10時からです。"))
        #expect(session.markedText == VoiceInlineText(settled: "今日はいい天気ですね。", live: "明日の会議は 10時からです。"))
        _ = session.handle(.utteranceEnded("明日の会議は 10時からです。"))
        _ = session.handle(.volatileResult("よろしお願い。"))
        _ = session.handle(.toggle)
        _ = session.handle(.utteranceEnded("よろしくお願い。"))
        // 認識が終わると、最後は空の結果で知らせる
        #expect(session.handle(.finalResult("")).effects == [.commit("今日はいい天気ですね。明日の会議は 10時からです。よろしくお願い。")])
    }

    @Test("volatile では、先頭が変わって短くなっても新しい発話とみなさない")
    func volatileDoesNotDetectReset() {
        var session = VoiceInputSession()
        _ = session.handle(.toggle)
        _ = session.handle(.volatileResult("今日はいい天気"))
        _ = session.handle(.volatileResult("京都"))
        #expect(session.markedText == VoiceInlineText(live: "京都"))
    }
}

@Suite("認識の仕組みの設定")
struct VoiceRecognitionEngineConfigTests {
    @Test("設定画面の名前は、何ができるかを先に書き、仕組みの名前をかっこに残す。既定の高精度を先に出す")
    func displayNames() {
        #expect(Config.VoiceRecognitionEngine.Value.allCases == [.speechTranscriber, .standard])
        #expect(Config.VoiceRecognitionEngine.Value.speechTranscriber.displayName == "高精度（SpeechTranscriber・macOS 26 Tahoe 以降）")
        #expect(Config.VoiceRecognitionEngine.Value.standard.displayName == "互換（SFSpeechRecognizer・macOS 13 Ventura 以降）")
    }

    @Test("保存する値は変えない")
    func rawValues() {
        #expect(Config.VoiceRecognitionEngine.Value.speechTranscriber.rawValue == "speechTranscriber")
        #expect(Config.VoiceRecognitionEngine.Value.standard.rawValue == "standard")
    }

    @Test("既定は高精度（SpeechTranscriber）")
    func defaultIsSpeechTranscriber() {
        #expect(Config.VoiceRecognitionEngine.default == .speechTranscriber)
    }

    @Test("既定のままでも、macOS 26 より前では互換を使う")
    func defaultFallsBackOnOlderOS() {
        #expect(Config.VoiceRecognitionEngine.default.resolved(speechTranscriberAvailable: false) == .standard)
        #expect(Config.VoiceRecognitionEngine.default.resolved(speechTranscriberAvailable: true) == .speechTranscriber)
    }

    @Test("保存した値の読み書き：互換を選んだ人は互換のまま")
    func savedChoiceIsKept() {
        let rawStandard = try? JSONEncoder().encode(Config.VoiceRecognitionEngine.Value.standard)
        let decoded = rawStandard.flatMap { try? JSONDecoder().decode(Config.VoiceRecognitionEngine.Value.self, from: $0) }
        #expect(decoded == .standard)
    }

    @Test("高精度が使えない OS では互換を使う")
    func resolveOnOlderOS() {
        #expect(Config.VoiceRecognitionEngine.Value.speechTranscriber.resolved(speechTranscriberAvailable: false) == .standard)
        #expect(Config.VoiceRecognitionEngine.Value.speechTranscriber.resolved(speechTranscriberAvailable: true) == .speechTranscriber)
        #expect(Config.VoiceRecognitionEngine.Value.standard.resolved(speechTranscriberAvailable: true) == .standard)
    }
}

@Suite("認識モデルの準備")
struct VoicePillModelPreparationTests {
    private let shortcut = KeyboardShortcut.defaultVoiceInputShortcut

    @Test("モデルをダウンロードしているあいだは「準備中…」を出し、止め方は出さない")
    func preparing() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 0)
        presenter.setPreparingModel(true, at: 0)
        let model = presenter.model(phase: .listening, now: 10, shortcut: self.shortcut, reduceMotion: false)
        #expect(model == VoicePillModel(mic: .finishing, label: "日本語の認識モデルを準備中…", isPulsing: false, level: nil, animatesLevel: false, keys: nil))
    }

    @Test("準備が終わったら聞き取り中に戻り、声がない時間はそこから数える")
    func preparedThenListening() {
        var presenter = VoicePillPresenter()
        presenter.start(at: 0)
        presenter.setPreparingModel(true, at: 0)
        presenter.setPreparingModel(false, at: 10)
        let model = presenter.model(phase: .listening, now: 11, shortcut: self.shortcut, reduceMotion: false)
        #expect(model?.label == "聞き取り中")
        #expect(model?.keys == nil)
    }

    @Test("モデルを用意できないときの文言")
    func modelUnavailableMessage() {
        #expect(VoicePillPresenter.message(for: .modelUnavailable) == "日本語の認識モデルを準備できません")
        #expect(VoiceInputSession.Failure.modelUnavailable.privacySettingsURL == nil)
    }
}
