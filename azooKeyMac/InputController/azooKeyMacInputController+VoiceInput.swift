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

    /// 設定に合わせてメニュー項目を出し入れする。
    ///
    /// メニューを書き換えると IMK が入力先を一度 deactivate するので、打鍵や聞き取りのたびには呼ばない。
    /// 値が変わったときだけ書き換え、タイトルやキー表示も固定にしている
    /// （ショートカットの判定は `handleVoiceInputKeyEvent` が行う）。
    func updateVoiceInputMenuItem() {
        let hidden = !Config.VoiceInput().value
        if self.voiceInputMenuItem.isHidden != hidden {
            self.voiceInputMenuItem.isHidden = hidden
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
        let outcome = self.voiceInputSession.handle(event)
        guard let client = self.client() else {
            if !self.voiceInputSession.isActive {
                VoiceRecognizer.shared.cancel()
            }
            return
        }
        self.performVoiceInputEffects(outcome.effects, client: client)
    }

    @MainActor
    private func performVoiceInputEffects(_ effects: [VoiceInputSession.Effect], client: IMKTextInput) {
        for effect in effects {
            switch effect {
            case .startRecognition:
                VoiceRecognizer.shared.start { [weak self] event in
                    self?.handleVoiceRecognitionEvent(event)
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
            case .clearMarkedText:
                self.setVoiceInputMarkedText("", client: client)
            case .commit(let text):
                client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            case .report(let failure):
                self.segmentsManager.appendDebugMessage("Voice input failed: \(failure)")
                if let url = failure.privacySettingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func setVoiceInputMarkedText(_ text: String, client: IMKTextInput) {
        let underline = self.mark(
            forStyle: kTSMHiliteConvertedText,
            at: NSRange(location: NSNotFound, length: 0)
        ) as? [NSAttributedString.Key: Any]
        client.setMarkedText(
            NSAttributedString(string: text, attributes: underline),
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }
}
