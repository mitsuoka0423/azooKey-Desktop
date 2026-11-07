import AVFoundation
import Core
import Speech

/// 認識を始められなかった理由
struct VoiceRecognitionFailure: Error {
    var failure: VoiceInputSession.Failure
}

/// SpeechTranscriber（高精度の認識。macOS 26 以降）で、マイクの音を認識する 1 回ぶんの聞き取り。
///
/// 認識は Mac の中だけで行い、音声は外に送らない（ダウンロードするのは日本語の認識モデルだけ）。
/// 結果は、まだ変わる部分（volatile）を `.volatileResult`、区切りの確定（finalized）を `.utteranceEnded`、
/// 終わりを `.finalResult("")` として渡す。
@available(macOS 26.0, *)
@MainActor
final class TranscriberRecognition {
    typealias EventHandler = @MainActor (VoiceInputSession.Event) -> Void
    typealias LevelHandler = @MainActor (Double) -> Void

    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var audioEngine: AVAudioEngine?
    private var resultsTask: Task<Void, Never>?

    private init(analyzer: SpeechAnalyzer, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.analyzer = analyzer
        self.continuation = continuation
    }

    /// モデルを確かめ（なければダウンロードし）、録音と認識を始める
    static func start(
        locale: Locale,
        onPreparingModel: @escaping @MainActor (Bool) -> Void,
        onEvent: @escaping EventHandler,
        onLevel: @escaping LevelHandler
    ) async throws -> TranscriberRecognition {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw VoiceRecognitionFailure(failure: .onDeviceRecognitionUnavailable)
        }
        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        try await Self.prepareModel(for: transcriber, onPreparingModel: onPreparingModel)

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw VoiceRecognitionFailure(failure: .other("マイクが見つかりません"))
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: inputFormat) else {
            throw VoiceRecognitionFailure(failure: .other("音声の形式を決められません"))
        }
        let converter: AVAudioConverter?
        if inputFormat == analyzerFormat {
            converter = nil
        } else {
            guard let made = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
                throw VoiceRecognitionFailure(failure: .other("音声の形式を変換できません"))
            }
            converter = made
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let recognition = TranscriberRecognition(analyzer: analyzer, continuation: continuation)
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            continuation.finish()
            throw VoiceRecognitionFailure(failure: .other("認識を始められません: \(error.localizedDescription)"))
        }

        recognition.resultsTask = Task { @MainActor in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    onEvent(result.isFinal ? .utteranceEnded(text) : .volatileResult(text))
                }
                onEvent(.finalResult(""))
            } catch {
                if !Task.isCancelled {
                    onEvent(.failed(.other(error.localizedDescription)))
                }
            }
        }

        let tapBlock = Self.makeTapBlock(converter: converter, outputFormat: analyzerFormat, continuation: continuation, onLevel: onLevel)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: tapBlock)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            recognition.cancel()
            throw VoiceRecognitionFailure(failure: .other("録音を始められません: \(error.localizedDescription)"))
        }
        recognition.audioEngine = audioEngine
        return recognition
    }

    /// 録音を止め、残りを認識し終えてから `.finalResult("")` を渡す
    func finish() {
        self.stopAudio()
        self.continuation.finish()
        let analyzer = self.analyzer
        Task {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
    }

    /// 録音と認識を捨てる
    func cancel() {
        self.resultsTask?.cancel()
        self.resultsTask = nil
        self.stopAudio()
        self.continuation.finish()
        let analyzer = self.analyzer
        Task {
            await analyzer.cancelAndFinishNow()
        }
    }

    // MARK: - 中身

    private static func prepareModel(
        for transcriber: SpeechTranscriber,
        onPreparingModel: @escaping @MainActor (Bool) -> Void
    ) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
        case .unsupported:
            throw VoiceRecognitionFailure(failure: .onDeviceRecognitionUnavailable)
        case .supported, .downloading:
            break
        @unknown default:
            break
        }
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                return
            }
            onPreparingModel(true)
            defer {
                onPreparingModel(false)
            }
            try await request.downloadAndInstall()
        } catch {
            throw VoiceRecognitionFailure(failure: .modelUnavailable)
        }
    }

    /// 録音スレッドで呼ばれるので、MainActor に縛られないクロージャーとして作る
    nonisolated private static func makeTapBlock(
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        onLevel: @escaping @MainActor (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let level = VoiceLevel.normalized(rms: VoiceRecognizer.rms(of: buffer))
            Task { @MainActor in
                onLevel(level)
            }
            guard let converter else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                return
            }
            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    private func stopAudio() {
        guard let audioEngine = self.audioEngine else {
            return
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine = nil
    }
}
