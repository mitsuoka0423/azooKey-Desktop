import Cocoa
import Core
import InputMethodKit

/// 音声入力のつなぎ。状態の変化は `Core.VoiceInputSession` が決め、ここではキーを渡して結果を実行するだけにする
extension azooKeyMacInputController {
    /// 止めてから最後の結果を待つ長さ
    private static let voiceInputFinishTimeout: TimeInterval = 3

    // MARK: - キー入力

    /// 音声入力がキーを受け持ったら `true` を返す。`nil` ならふだんのキー処理に回す
    @MainActor
    func handleVoiceInputKeyEvent(_ event: NSEvent, client: IMKTextInput) -> Bool? {
        let isShortcut = Config.VoiceInputShortcut().value.matches(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: KeyEventCore.ModifierFlag(from: event.modifierFlags)
        )
        if self.voiceInputSession.isActive {
            let voiceEvent: VoiceInputSession.Event = if isShortcut {
                .toggle
            } else {
                switch event.keyCode {
                case 36, 76: .enter // Return, テンキーの Enter
                case 53: .escape
                default: .otherKey
                }
            }
            let outcome = self.voiceInputSession.handle(voiceEvent)
            self.performVoiceInputEffects(outcome.effects, client: client)
            return outcome.consumesKey ? true : nil
        }
        guard Config.VoiceInput().value, isShortcut else {
            return nil
        }
        self.startVoiceInput(client: client)
        return true
    }

    // MARK: - メニュー

    @MainActor @objc func toggleVoiceInput(_ sender: Any) {
        guard let client = self.client() else {
            return
        }
        if self.voiceInputSession.isActive {
            let outcome = self.voiceInputSession.handle(.toggle)
            self.performVoiceInputEffects(outcome.effects, client: client)
        } else if Config.VoiceInput().value {
            self.startVoiceInput(client: client)
        }
    }

    /// 設定がオンのときだけ、メニューに音声入力の項目を入れる。
    ///
    /// 設定がオフのときはメニューを本家と同じにしておく。隠した項目（`isHidden`）を入れたままにすると、
    /// 打鍵のたびに IME が入力先との接続を切り、日本語入力が通らなくなったため。
    /// 打鍵のたびには書き換えず、設定が変わったときだけ出し入れする
    /// （ショートカットの判定は `handleVoiceInputKeyEvent` が行う）。
    func updateVoiceInputMenuItem() {
        let enabled = Config.VoiceInput().value
        let index = self.appMenu.index(of: self.voiceInputMenuItem)
        if enabled, index < 0 {
            let transformIndex = self.appMenu.index(of: self.transformSelectedTextMenuItem)
            self.appMenu.insertItem(self.voiceInputMenuItem, at: transformIndex + 1)
        } else if !enabled, index >= 0 {
            self.appMenu.removeItem(at: index)
        }
    }

    // MARK: - フォーカスが外れたとき

    /// 入力先から離れるときに、ここまでの文字を確定して聞き取りを止める
    @MainActor
    func endVoiceInputOnFocusLost(client: IMKTextInput?) {
        guard self.voiceInputSession.isActive else {
            return
        }
        let outcome = self.voiceInputSession.handle(.focusLost)
        if let client {
            self.performVoiceInputEffects(outcome.effects, client: client)
        } else {
            VoiceRecognizer.shared.cancel()
        }
        self.voicePillPresenter.end()
        self.stopVoicePillTimer()
        self.voicePillWindow.hide(animated: false)
    }

    // MARK: - 中身

    @MainActor
    private func startVoiceInput(client: IMKTextInput) {
        // 打ちかけの文字があれば先に確定する
        if !self.segmentsManager.isEmpty {
            self.commitComposition(client)
        }
        let outcome = self.voiceInputSession.handle(.toggle)
        self.performVoiceInputEffects(outcome.effects, client: client)
    }

    @MainActor
    private func handleVoiceRecognitionEvent(_ event: VoiceInputSession.Event) {
        switch event {
        case .partialResult, .utteranceEnded, .finalResult:
            self.voicePillPresenter.recognized(at: Self.now)
        default:
            break
        }
        let outcome = self.voiceInputSession.handle(event)
        guard let client = self.client() else {
            if !self.voiceInputSession.isActive {
                VoiceRecognizer.shared.cancel()
            }
            return
        }
        self.performVoiceInputEffects(outcome.effects, client: client)
    }

    // 効果ごとに 1 つずつ分けて書くと、かえって流れが追いにくいので lint を外す
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private func performVoiceInputEffects(_ effects: [VoiceInputSession.Effect], client: IMKTextInput) {
        for effect in effects {
            switch effect {
            case .startRecognition:
                self.voicePillPresenter.start(at: Self.now)
                self.updateVoicePillAnchor(client: client)
                self.startVoicePillTimer()
                VoiceRecognizer.shared.start { [weak self] event in
                    self?.handleVoiceRecognitionEvent(event)
                } levelHandler: { [weak self] level in
                    self?.voicePillPresenter.updateLevel(level, at: Self.now)
                    self?.refreshVoicePill()
                }
            case .finishRecognition:
                VoiceRecognizer.shared.finish()
                self.voiceInputFinishToken += 1
                let token = self.voiceInputFinishToken
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.voiceInputFinishTimeout) { [weak self] in
                    guard let self, token == self.voiceInputFinishToken else {
                        return
                    }
                    self.handleVoiceRecognitionEvent(.finishTimedOut)
                }
            case .cancelRecognition:
                VoiceRecognizer.shared.cancel()
            case .setMarkedText(let text):
                self.setVoiceInputMarkedText(text, client: client)
                self.updateVoicePillAnchor(client: client)
            case .clearMarkedText:
                self.setVoiceInputMarkedText(VoiceInlineText(), client: client)
            case .commit(let text):
                client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            case .report(let failure):
                self.segmentsManager.appendDebugMessage("Voice input failed: \(failure)")
                self.voicePillPresenter.fail(failure, at: Self.now)
                self.startVoicePillTimer()
                if let url = failure.privacySettingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if !self.voiceInputSession.isActive, self.voicePillPresenter.isFailureExpired(at: Self.now) {
            self.voicePillPresenter.end()
        }
        self.refreshVoicePill()
    }

    /// 固まった部分は実線（`VoiceInlineText.Settled`）、まだ変わる部分は点線（`VoiceInlineText.Live`）の下線で出す
    private func setVoiceInputMarkedText(_ text: VoiceInlineText, client: IMKTextInput) {
        var settledAttributes = self.mark(
            forStyle: kTSMHiliteConvertedText,
            at: NSRange(location: NSNotFound, length: 0)
        ) as? [NSAttributedString.Key: Any] ?? [:]
        settledAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        settledAttributes[.markedClauseSegment] = 0
        var liveAttributes = settledAttributes
        liveAttributes[.underlineStyle] = NSUnderlineStyle.single.union(.patternDot).rawValue
        liveAttributes[.markedClauseSegment] = text.settled.isEmpty ? 0 : 1

        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: text.settled, attributes: settledAttributes))
        attributed.append(NSAttributedString(string: text.live, attributes: liveAttributes))
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: attributed.length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    // MARK: - 聞き取りピル

    private static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// ピルの位置の基準。入力先への問い合わせは重いので、未確定文字列が変わったときだけ取り直す
    private func updateVoicePillAnchor(client: IMKTextInput) {
        var rect: NSRect = .zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        self.voicePillAnchor = rect
    }

    @MainActor
    private func refreshVoicePill() {
        let model = self.voicePillPresenter.model(
            phase: self.voiceInputSession.phase,
            now: Self.now,
            shortcut: Config.VoiceInputShortcut().value,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if let model {
            self.voicePillWindow.show(model: model, anchor: self.voicePillAnchor)
        } else {
            self.voicePillWindow.hide()
            self.stopVoicePillTimer()
        }
    }

    /// 2 秒・3 秒の決まりのために、ピルが出ているあいだだけ見直す
    private func startVoicePillTimer() {
        guard self.voicePillTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshVoicePill()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.voicePillTimer = timer
    }

    private func stopVoicePillTimer() {
        self.voicePillTimer?.invalidate()
        self.voicePillTimer = nil
    }
}
