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

    @Test("待機中にショートカットを押すと聞き取りを始め、目印を未確定文字列に出す")
    func toggleStartsListening() {
        var session = VoiceInputSession()
        let outcome = session.handle(.toggle)
        #expect(session.phase == .listening)
        #expect(outcome.effects == [.startRecognition, .setMarkedText(VoiceInputSession.listeningPlaceholder)])
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
        #expect(outcome.effects == [.setMarkedText("今日は")])
        #expect(session.transcript == "今日は")
        #expect(session.markedText == "今日は")
        _ = session.handle(.partialResult("今日はいい天気"))
        #expect(session.markedText == "今日はいい天気")
    }

    @Test("もう一度ショートカットを押すと、最後の結果を待ってから確定する")
    func toggleFinishesAndWaitsForFinalResult() {
        var session = self.listeningSession(transcript: "今日はいい天気")
        let stop = session.handle(.toggle)
        #expect(stop.effects == [.finishRecognition])
        #expect(stop.consumesKey)
        #expect(session.phase == .finishing)
        #expect(session.markedText == "今日はいい天気")

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
