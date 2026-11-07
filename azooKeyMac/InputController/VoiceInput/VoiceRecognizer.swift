import AVFoundation
import Core
import Speech

/// マイクの音を日本語のオンデバイス認識にかけ、結果を `VoiceInputSession.Event` として渡す。
///
/// 認識の仕組みは設定で選ぶ。標準は SFSpeechRecognizer（`requiresOnDeviceRecognition`）、
/// 新しい認識は SpeechTranscriber（macOS 26 以降、`TranscriberRecognition`）。どちらも音声は Mac の外に送らない。
/// 入力欄ごとに `azooKeyMacInputController` が作られるが、マイクは 1 つなので全体で 1 つだけ持つ。
@MainActor
final class VoiceRecognizer {
    typealias Handler = @MainActor (VoiceInputSession.Event) -> Void
    /// 録音の音の大きさ（0〜1）を受け取る
    typealias LevelHandler = @MainActor (Double) -> Void
    /// 認識モデルのダウンロードを始めた（true）・終えた（false）
    typealias PreparingModelHandler = @MainActor (Bool) -> Void

    /// この Mac で新しい認識（SpeechTranscriber）を使えるか
    static var isSpeechTranscriberAvailable: Bool {
        if #available(macOS 26.0, *) {
            true
        } else {
            false
        }
    }

    static let shared = VoiceRecognizer()

    private static let locale = Locale(identifier: "ja-JP")

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var handler: Handler?
    private var levelHandler: LevelHandler?
    /// 新しい認識での聞き取り（`TranscriberRecognition`。macOS 26 より前の OS でも持てるように AnyObject にする）
    private var transcription: AnyObject?
    /// 始めるたびに増やす。止めたあとに届いた古い結果を捨てるのに使う
    private var generation = 0

    private init() {}

    /// 許可を確かめてから、録音と認識を始める。前の聞き取りが残っていれば捨てる
    func start(handler: @escaping Handler, levelHandler: @escaping LevelHandler, preparingModelHandler: @escaping PreparingModelHandler) {
        self.cancel()
        self.generation += 1
        let generation = self.generation
        self.handler = handler
        self.levelHandler = levelHandler
        Task { @MainActor in
            if let failure = await Self.requestPermissions() {
                self.deliver(.failed(failure), generation: generation)
                return
            }
            guard generation == self.generation else {
                return
            }
            let engine = Config.VoiceRecognitionEngine().value.resolved(speechTranscriberAvailable: Self.isSpeechTranscriberAvailable)
            do {
                if engine == .speechTranscriber, #available(macOS 26.0, *) {
                    try await self.beginTranscription(generation: generation, preparingModelHandler: preparingModelHandler)
                } else {
                    try self.beginRecognition(generation: generation)
                }
            } catch let failure as VoiceRecognitionFailure {
                self.deliver(.failed(failure.failure), generation: generation)
            } catch {
                self.deliver(.failed(.other(error.localizedDescription)), generation: generation)
            }
        }
    }

    /// 録音を止め、認識の最後の結果を待つ
    func finish() {
        if #available(macOS 26.0, *), let transcription = self.transcription as? TranscriberRecognition {
            transcription.finish()
            return
        }
        self.stopAudio()
        self.request?.endAudio()
    }

    /// 録音と認識を捨てる。このあと結果は届かない
    func cancel() {
        self.generation += 1
        self.handler = nil
        self.levelHandler = nil
        if #available(macOS 26.0, *), let transcription = self.transcription as? TranscriberRecognition {
            transcription.cancel()
        }
        self.transcription = nil
        self.stopAudio()
        self.request?.endAudio()
        self.task?.cancel()
        self.task = nil
        self.request = nil
    }

    // MARK: - 中身

    private static func requestPermissions() async -> VoiceInputSession.Failure? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                return .microphoneDenied
            }
        case .denied, .restricted:
            return .microphoneDenied
        @unknown default:
            return .microphoneDenied
        }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        } else {
            speechStatus = SFSpeechRecognizer.authorizationStatus()
        }
        return speechStatus == .authorized ? nil : .speechRecognitionDenied
    }

    private func beginRecognition(generation: Int) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale),
              recognizer.supportsOnDeviceRecognition else {
            throw VoiceRecognitionFailure(failure: .onDeviceRecognitionUnavailable)
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceRecognitionFailure(failure: .other("マイクが見つかりません"))
        }
        let tapBlock = Self.makeTapBlock(request: request) { [weak self] level in
            self?.deliverLevel(level, generation: generation)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw VoiceRecognitionFailure(failure: .other("録音を始められません: \(error.localizedDescription)"))
        }

        self.audioEngine = audioEngine
        self.request = request
        self.task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] result in
            self?.handleResult(result, generation: generation)
        })
    }

    @available(macOS 26.0, *)
    private func beginTranscription(generation: Int, preparingModelHandler: @escaping PreparingModelHandler) async throws {
        let transcription = try await TranscriberRecognition.start(
            locale: Self.locale,
            onPreparingModel: { [weak self] preparing in
                guard let self, generation == self.generation else {
                    return
                }
                preparingModelHandler(preparing)
            },
            onEvent: { [weak self] event in
                guard let self, generation == self.generation else {
                    return
                }
                switch event {
                case .finalResult, .failed:
                    self.transcription = nil
                default:
                    break
                }
                self.deliver(event, generation: generation)
            },
            onLevel: { [weak self] level in
                guard let self, generation == self.generation, self.transcription != nil else {
                    return
                }
                self.levelHandler?(level)
            }
        )
        // 準備しているあいだに取り消されていたら、すぐ捨てる
        guard generation == self.generation else {
            transcription.cancel()
            return
        }
        self.transcription = transcription
    }

    /// 録音スレッドで呼ばれるので、MainActor に縛られないクロージャーとして作る
    nonisolated private static func makeTapBlock(
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @MainActor (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            let level = VoiceLevel.normalized(rms: Self.rms(of: buffer))
            Task { @MainActor in
                onLevel(level)
            }
        }
    }

    /// 1 つ目のチャンネルの RMS
    nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        return Double((sum / Float(count)).squareRoot())
    }

    private func deliverLevel(_ level: Double, generation: Int) {
        guard generation == self.generation, self.audioEngine != nil else {
            return
        }
        self.levelHandler?(level)
    }

    /// 認識の結果から取り出したもの
    private struct ResultSummary: Sendable {
        var text: String?
        var isFinal: Bool
        /// 話の間で発話が区切られた（オンデバイス認識は、次の結果を最初からやり直す）
        var endsUtterance: Bool
        var errorMessage: String?
    }

    /// 認識の結果は任意のスレッドで届くので、要るものだけ取り出して MainActor に戻す
    nonisolated private static func makeResultHandler(
        _ deliver: @escaping @MainActor (ResultSummary) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let summary = ResultSummary(
                text: result?.bestTranscription.formattedString,
                isFinal: result?.isFinal ?? false,
                endsUtterance: result?.speechRecognitionMetadata != nil,
                errorMessage: error?.localizedDescription
            )
            Task { @MainActor in
                deliver(summary)
            }
        }
    }

    private func handleResult(_ result: ResultSummary, generation: Int) {
        guard generation == self.generation else {
            return
        }
        if let text = result.text, result.isFinal {
            self.tearDown()
            self.deliver(.finalResult(text), generation: generation)
        } else if let errorMessage = result.errorMessage {
            self.tearDown()
            self.deliver(.failed(.other(errorMessage)), generation: generation)
        } else if let text = result.text {
            self.deliver(result.endsUtterance ? .utteranceEnded(text) : .partialResult(text), generation: generation)
        }
    }

    private func deliver(_ event: VoiceInputSession.Event, generation: Int) {
        guard generation == self.generation else {
            return
        }
        self.handler?(event)
    }

    private func stopAudio() {
        guard let audioEngine = self.audioEngine else {
            return
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine = nil
    }

    private func tearDown() {
        self.stopAudio()
        self.task = nil
        self.request = nil
    }
}
