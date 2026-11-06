import AVFoundation
import Core
import Speech

/// マイクの音を日本語のオンデバイス認識にかけ、結果を `VoiceInputSession.Event` として渡す。
///
/// 音声は Mac の外に送らない（`requiresOnDeviceRecognition`）。
/// 入力欄ごとに `azooKeyMacInputController` が作られるが、マイクは 1 つなので全体で 1 つだけ持つ。
@MainActor
final class VoiceRecognizer {
    typealias Handler = @MainActor (VoiceInputSession.Event) -> Void

    static let shared = VoiceRecognizer()

    private static let locale = Locale(identifier: "ja-JP")

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var handler: Handler?
    /// 始めるたびに増やす。止めたあとに届いた古い結果を捨てるのに使う
    private var generation = 0

    private init() {}

    /// 許可を確かめてから、録音と認識を始める。前の聞き取りが残っていれば捨てる
    func start(handler: @escaping Handler) {
        self.cancel()
        self.generation += 1
        let generation = self.generation
        self.handler = handler
        Task { @MainActor in
            if let failure = await Self.requestPermissions() {
                self.deliver(.failed(failure), generation: generation)
                return
            }
            guard generation == self.generation else {
                return
            }
            do {
                try self.beginRecognition(generation: generation)
            } catch let failure as RecognitionFailure {
                self.deliver(.failed(failure.failure), generation: generation)
            } catch {
                self.deliver(.failed(.other(error.localizedDescription)), generation: generation)
            }
        }
    }

    /// 録音を止め、認識の最後の結果を待つ
    func finish() {
        self.stopAudio()
        self.request?.endAudio()
    }

    /// 録音と認識を捨てる。このあと結果は届かない
    func cancel() {
        self.generation += 1
        self.handler = nil
        self.stopAudio()
        self.request?.endAudio()
        self.task?.cancel()
        self.task = nil
        self.request = nil
    }

    // MARK: - 中身

    private struct RecognitionFailure: Error {
        var failure: VoiceInputSession.Failure
    }

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
            throw RecognitionFailure(failure: .onDeviceRecognitionUnavailable)
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecognitionFailure(failure: .other("マイクが見つかりません"))
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(request: request))
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecognitionFailure(failure: .other("録音を始められません: \(error.localizedDescription)"))
        }

        self.audioEngine = audioEngine
        self.request = request
        self.task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, isFinal, errorMessage in
            self?.handleResult(text: text, isFinal: isFinal, errorMessage: errorMessage, generation: generation)
        })
    }

    /// 録音スレッドで呼ばれるので、MainActor に縛られないクロージャーとして作る
    nonisolated private static func makeTapBlock(request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
        }
    }

    /// 認識の結果は任意のスレッドで届くので、文字だけ取り出して MainActor に戻す
    nonisolated private static func makeResultHandler(
        _ deliver: @escaping @MainActor (_ text: String?, _ isFinal: Bool, _ errorMessage: String?) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                deliver(text, isFinal, errorMessage)
            }
        }
    }

    private func handleResult(text: String?, isFinal: Bool, errorMessage: String?, generation: Int) {
        guard generation == self.generation else {
            return
        }
        if let text, isFinal {
            self.tearDown()
            self.deliver(.finalResult(text), generation: generation)
        } else if let errorMessage {
            self.tearDown()
            self.deliver(.failed(.other(errorMessage)), generation: generation)
        } else if let text {
            self.deliver(.partialResult(text), generation: generation)
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
