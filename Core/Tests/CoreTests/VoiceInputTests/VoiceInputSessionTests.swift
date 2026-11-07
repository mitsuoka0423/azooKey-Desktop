import Testing

@testable import Core

@Suite("VoiceInputSession")
struct VoiceInputSessionTests {
    private func listeningSession(transcript: String = "") -> VoiceInputSession {
        var session = VoiceInputSession()
        _ = session.handle(.toggle)
        if !transcript.isEmpty {
            _ = session.handle(.partialResult(transcript))
        }
        return session
    }

    @Test("待機中にショートカットを押すと聞き取りを始める。本文には何も入れない")
    func toggleStartsListening() {
        var session = VoiceInputSession()
        let outcome = session.handle(.toggle)
        #expect(session.phase == .listening)
        #expect(outcome.effects == [.startRecognition])
        #expect(session.markedText.isEmpty)
        #expect(outcome.consumesKey)
    }

    @Test("待機中はふつうのキーや認識結果に反応しない")
    func idleIgnoresOtherEvents() {
        var session = VoiceInputSession()
        for event: VoiceInputSession.Event in [.enter, .escape, .otherKey, .focusLost, .partialResult("あ"), .finalResult("あ"), .finishTimedOut] {
            let outcome = session.handle(event)
            #expect(outcome.effects.isEmpty)
            #expect(!outcome.consumesKey)
            #expect(session.phase == .idle)
        }
    }

    @Test("途中の認識結果で未確定文字列を置き換える")
    func partialResultUpdatesMarkedText() {
        var session = self.listeningSession()
        let outcome = session.handle(.partialResult("今日は"))
        #expect(outcome.effects == [.setMarkedText(VoiceInlineText(live: "今日は"))])
        #expect(session.transcript == "今日は")
        #expect(session.markedText.text == "今日は")
        _ = session.handle(.partialResult("今日はいい天気"))
        #expect(session.markedText.text == "今日はいい天気")
    }

    @Test("もう一度ショートカットを押すと、最後の結果を待ってから確定する")
    func toggleFinishesAndWaitsForFinalResult() {
        var session = self.listeningSession(transcript: "今日はいい天気")
        let stop = session.handle(.toggle)
        #expect(stop.effects == [.finishRecognition])
        #expect(stop.consumesKey)
        #expect(session.phase == .finishing)
        #expect(session.markedText.text == "今日はいい天気")

        let final = session.handle(.finalResult("今日はいい天気です"))
        #expect(final.effects == [.commit("今日はいい天気です")])
        #expect(session.phase == .idle)
        #expect(session.transcript.isEmpty)
    }

    @Test("Enter でも止めて確定する")
    func enterFinishes() {
        var session = self.listeningSession(transcript: "こんにちは")
        let outcome = session.handle(.enter)
        #expect(outcome.effects == [.finishRecognition])
        #expect(outcome.consumesKey)
        #expect(session.handle(.finalResult("こんにちは")).effects == [.commit("こんにちは")])
    }

    @Test("最後の結果を待っているあいだにもう一度押すと、ここまでの文字ですぐ確定する")
    func secondToggleWhileFinishingCommitsImmediately() {
        var session = self.listeningSession(transcript: "こんにちは")
        _ = session.handle(.toggle)
        let outcome = session.handle(.toggle)
        #expect(outcome.effects == [.cancelRecognition, .commit("こんにちは")])
        #expect(outcome.consumesKey)
        #expect(session.phase == .idle)
    }

    @Test("最後の結果が来ないまま時間が過ぎたら、ここまでの文字で確定する")
    func finishTimeoutCommitsTranscript() {
        var session = self.listeningSession(transcript: "こんにちは")
        _ = session.handle(.toggle)
        #expect(session.handle(.finishTimedOut).effects == [.cancelRecognition, .commit("こんにちは")])
        #expect(session.phase == .idle)
    }

    @Test("聞き取り中は時間切れを無視する（止める前のタイマーが遅れて届いた場合）")
    func timeoutWhileListeningIsIgnored() {
        var session = self.listeningSession(transcript: "こんにちは")
        #expect(session.handle(.finishTimedOut).effects.isEmpty)
        #expect(session.phase == .listening)
    }

    @Test("Escape で聞き取りを捨て、何も確定しない")
    func escapeDiscards() {
        var session = self.listeningSession(transcript: "こんにちは")
        let outcome = session.handle(.escape)
        #expect(outcome.effects == [.cancelRecognition, .clearMarkedText])
        #expect(outcome.consumesKey)
        #expect(session.phase == .idle)

        var finishing = self.listeningSession(transcript: "こんにちは")
        _ = finishing.handle(.toggle)
        #expect(finishing.handle(.escape).effects == [.cancelRecognition, .clearMarkedText])
    }

    @Test("ほかのキーを押すと、ここまでの文字を確定し、キーはふだんどおりに処理させる")
    func otherKeyCommitsAndPassesThrough() {
        var session = self.listeningSession(transcript: "こんにちは")
        let outcome = session.handle(.otherKey)
        #expect(outcome.effects == [.cancelRecognition, .commit("こんにちは")])
        #expect(!outcome.consumesKey)
        #expect(session.phase == .idle)
    }

    @Test("何も認識しないまま止めたら、目印を消すだけにする")
    func emptyTranscriptClearsMarkedText() {
        var session = self.listeningSession()
        #expect(session.handle(.otherKey).effects == [.cancelRecognition, .clearMarkedText])

        var stopped = self.listeningSession()
        _ = stopped.handle(.toggle)
        #expect(stopped.handle(.finalResult("")).effects == [.clearMarkedText])
    }

    @Test("認識側が話し終わりで止まったら、その結果を確定する")
    func finalResultWhileListeningCommits() {
        var session = self.listeningSession(transcript: "こんにち")
        #expect(session.handle(.finalResult("こんにちは")).effects == [.commit("こんにちは")])
        #expect(session.phase == .idle)
    }

    @Test("失敗したら、ここまでの文字を確定してから知らせる")
    func failureCommitsAndReports() {
        var session = self.listeningSession(transcript: "こんにちは")
        let outcome = session.handle(.failed(.other("止まった")))
        #expect(outcome.effects == [.cancelRecognition, .commit("こんにちは"), .report(.other("止まった"))])
        #expect(session.phase == .idle)

        var denied = self.listeningSession()
        #expect(denied.handle(.failed(.microphoneDenied)).effects == [.cancelRecognition, .clearMarkedText, .report(.microphoneDenied)])
    }

    @Test("入力先から離れたら、ここまでの文字を確定する")
    func focusLostCommits() {
        var session = self.listeningSession(transcript: "こんにちは")
        #expect(session.handle(.focusLost).effects == [.cancelRecognition, .commit("こんにちは")])
        #expect(!session.isActive)
    }

    @Test("許可がないときだけシステム設定の画面を開く")
    func privacySettingsURL() {
        #expect(VoiceInputSession.Failure.microphoneDenied.privacySettingsURL?.absoluteString.hasSuffix("Privacy_Microphone") == true)
        #expect(VoiceInputSession.Failure.speechRecognitionDenied.privacySettingsURL?.absoluteString.hasSuffix("Privacy_SpeechRecognition") == true)
        #expect(VoiceInputSession.Failure.onDeviceRecognitionUnavailable.privacySettingsURL == nil)
        #expect(VoiceInputSession.Failure.other("x").privacySettingsURL == nil)
    }
}

@Suite("VoiceInputConfig")
struct VoiceInputConfigTests {
    @Test("音声入力は既定でオフ")
    func defaultIsOff() {
        #expect(Config.VoiceInput.default == false)
        #expect(Config.VoiceInput.key.hasSuffix(".preference.enableVoiceInput"))
    }

    @Test("既定のショートカットは Control+Shift+D")
    func defaultShortcut() {
        #expect(Config.VoiceInputShortcut.default == KeyboardShortcut(key: "d", modifiers: [.control, .shift]))
        #expect(Config.VoiceInputShortcut.default.displayString == "⌃⇧D")
        #expect(Config.VoiceInputShortcut.key != Config.TransformShortcut.key)
    }

    @Test("ショートカットの判定は大文字小文字を問わず、修飾キーは完全一致")
    func shortcutMatching() {
        let shortcut = KeyboardShortcut.defaultVoiceInputShortcut
        #expect(shortcut.matches(charactersIgnoringModifiers: "D", modifiers: [.control, .shift]))
        #expect(shortcut.matches(charactersIgnoringModifiers: "d", modifiers: [.control, .shift]))
        #expect(!shortcut.matches(charactersIgnoringModifiers: "d", modifiers: [.control]))
        #expect(!shortcut.matches(charactersIgnoringModifiers: "d", modifiers: [.control, .shift, .option]))
        #expect(!shortcut.matches(charactersIgnoringModifiers: "s", modifiers: [.control, .shift]))
        #expect(!shortcut.matches(charactersIgnoringModifiers: nil, modifiers: [.control, .shift]))
        #expect(!shortcut.matches(charactersIgnoringModifiers: "", modifiers: [.control, .shift]))
    }
}

@Suite("VoiceTranscript")
struct VoiceTranscriptTests {
    @Test("1 つの発話が伸びていくときは、今の発話を置き換えるだけ")
    func growingUtterance() {
        var transcript = VoiceTranscript()
        for text in ["今", "今日", "今日は", "今日ははい", "今日はいい", "今日はいい天気ですね"] {
            transcript.updateCurrent(text)
        }
        #expect(transcript.text == "今日はいい天気ですね")
        #expect(transcript.confirmed.isEmpty)
    }

    @Test("話の間で区切られたら、それまでの発話を残して次の発話をつなぐ")
    func utteranceEndKeepsPreviousText() {
        // 実機の SFSpeechRecognizer（ja-JP・オンデバイス）が無音 3 秒を挟んだ音声で返した順
        var transcript = VoiceTranscript()
        transcript.updateCurrent("今日はいい天気ですね")
        transcript.endUtterance("今日はいい天気ですね")
        #expect(transcript.text == "今日はいい天気ですね")
        transcript.updateCurrent("明")
        #expect(transcript.text == "今日はいい天気ですね明")
        transcript.updateCurrent("明日の会議は10時からです")
        transcript.endUtterance("明日の会議は10時からです")
        transcript.updateCurrent("よろしくお願いしま")
        #expect(transcript.finalText("よろしくお願いします") == "今日はいい天気ですね明日の会議は10時からですよろしくお願いします")
    }

    @Test("最後の結果が、区切られた発話と同じ文を繰り返しても二重にしない")
    func finalRepeatingEndedUtterance() {
        var transcript = VoiceTranscript()
        transcript.endUtterance("こんにちは")
        transcript.endUtterance("元気ですか？")
        #expect(transcript.finalText("元気ですか？") == "こんにちは元気ですか？")
    }

    @Test("同じ文でも、区切りのあとに新しく話した発話なら二重にする")
    func repeatedSentenceAfterNewSpeech() {
        var transcript = VoiceTranscript()
        transcript.endUtterance("はい")
        transcript.updateCurrent("は")
        #expect(transcript.finalText("はい") == "はいはい")
    }

    @Test("最後の結果が空なら、ここまでの文字を使う")
    func emptyFinal() {
        var transcript = VoiceTranscript()
        transcript.endUtterance("こんにちは")
        transcript.updateCurrent("元気")
        #expect(transcript.finalText("") == "こんにちは元気")
    }

    @Test("区切りの知らせがなくても、先頭が変わって短くなったら新しい発話とみなす")
    func resetWithoutUtteranceEnd() {
        var transcript = VoiceTranscript()
        transcript.updateCurrent("今日はいい天気ですね")
        transcript.updateCurrent("明日")
        #expect(transcript.confirmed == "今日はいい天気ですね")
        #expect(transcript.text == "今日はいい天気ですね明日")
    }

    @Test("前のほうの言葉が直されただけなら、新しい発話とはみなさない")
    func revisionIsNotReset() {
        #expect(!VoiceTranscript.isNewUtterance(previous: "今日ははい", next: "今日はいい"))
        #expect(!VoiceTranscript.isNewUtterance(previous: "明日の会議は10時か", next: "明日の会議は、10時から"))
        // 先頭が変わっても、長くなっていれば同じ発話の言い直しとみなす
        #expect(!VoiceTranscript.isNewUtterance(previous: "今日は", next: "京都はいい天気"))
        #expect(VoiceTranscript.isNewUtterance(previous: "今日はいい天気", next: "明日"))
        #expect(!VoiceTranscript.isNewUtterance(previous: "", next: "明日"))
    }

    @Test("英数字どうしが続くときだけ空白を入れる")
    func joinRule() {
        #expect(VoiceTranscript.join("Swift", "UI") == "Swift UI")
        #expect(VoiceTranscript.join("10", "時") == "10時")
        #expect(VoiceTranscript.join("です。", "OK") == "です。OK")
        #expect(VoiceTranscript.join("", "OK") == "OK")
    }
}

@Suite("VoiceInputSession（発話の区切り）")
struct VoiceInputSessionUtteranceTests {
    @Test("聞き取り中に話の間があっても、前の文が消えない")
    func pauseKeepsEarlierText() {
        var session = VoiceInputSession()
        _ = session.handle(.toggle)
        _ = session.handle(.partialResult("今日はいい天気ですね"))
        #expect(session.handle(.utteranceEnded("今日はいい天気ですね")).effects == [.setMarkedText(VoiceInlineText(settled: "今日はいい天気ですね"))])
        #expect(session.handle(.partialResult("明日")).effects == [.setMarkedText(VoiceInlineText(settled: "今日はいい天気ですね", live: "明日"))])
        _ = session.handle(.toggle)
        #expect(session.handle(.finalResult("明日の会議です")).effects == [.commit("今日はいい天気ですね明日の会議です")])
    }

    @Test("止めたあとの最後の結果が、区切られた発話の繰り返しなら二重にしない")
    func finalAfterUtteranceEnd() {
        var session = VoiceInputSession()
        _ = session.handle(.toggle)
        _ = session.handle(.utteranceEnded("こんにちは"))
        _ = session.handle(.utteranceEnded("元気ですか？"))
        _ = session.handle(.toggle)
        #expect(session.handle(.finalResult("元気ですか？")).effects == [.commit("こんにちは元気ですか？")])
    }

    @Test("ほかのキーで打ち切ったときも、区切られた発話をすべて確定する")
    func otherKeyCommitsAllUtterances() {
        var session = VoiceInputSession()
        _ = session.handle(.toggle)
        _ = session.handle(.utteranceEnded("こんにちは"))
        _ = session.handle(.partialResult("元気"))
        #expect(session.handle(.otherKey).effects == [.cancelRecognition, .commit("こんにちは元気")])
    }

    @Test("待機中は区切りの知らせを無視する")
    func idleIgnoresUtteranceEnd() {
        var session = VoiceInputSession()
        #expect(session.handle(.utteranceEnded("こんにちは")).effects.isEmpty)
    }
}
