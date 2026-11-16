import AVFoundation
import Core

/// マイクの録音（AVAudioEngine）を、メインスレッドの外の専用のキューで扱う。
///
/// AVAudioEngine の `inputNode` を読むと、OS の録音の仕組みに問い合わせが行き、
/// まれにそこから戻らなくなる（AVFAudio の中で入力機器の形式を読み続ける）。
/// メインスレッドで読むと IME 全体が固まるので、録音の準備・開始・停止はすべて専用のキューで行い、
/// 決まった時間のうちに終わらなければ `.microphoneNotResponding` として失敗させる。
/// キューは 1 本だけなので、戻らない仕事が残っていても、スレッドが積み上がることはない。
final class AudioCapture: @unchecked Sendable {
    /// 準備・開始を待つ長さ（秒）
    static let timeout: TimeInterval = 3

    private static let queue = DispatchQueue(label: "dev.azooKey.voiceInput.audio", qos: .userInitiated)

    /// 専用のキューの上でだけ触る
    private var engine: AVAudioEngine?
    /// 入力機器の形式。録音の知らせ（tap）はこの形式で届く
    let inputFormat: AVAudioFormat

    private init(engine: AVAudioEngine, inputFormat: AVAudioFormat) {
        self.engine = engine
        self.inputFormat = inputFormat
    }

    /// エンジンを作り、今の既定のマイクに合わせて、入力の形式を読む
    static func open() async throws -> AudioCapture {
        try await Self.run(work: {
            let engine = AVAudioEngine()
            try AudioInputDevice.useCurrentDefault(for: engine)
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceRecognitionFailure(failure: .microphoneUnavailable)
            }
            return AudioCapture(engine: engine, inputFormat: format)
        }, cleanUpLateResult: { capture in
            capture.stopOnQueue()
        })
    }

    /// 録音の知らせを受け取り始める。失敗したら録音は止めたままにする
    func start(tap: @escaping AVAudioNodeTapBlock) async throws {
        try await Self.run(work: {
            guard let engine = self.engine else {
                throw VoiceRecognitionFailure(failure: .microphoneUnavailable)
            }
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: self.inputFormat, block: tap)
            engine.prepare()
            do {
                try engine.start()
            } catch {
                self.stopOnQueue()
                throw VoiceRecognitionFailure(failure: .other("録音を始められません: \(error.localizedDescription)"))
            }
        }, cleanUpLateResult: { _ in
            self.stopOnQueue()
        })
    }

    /// 録音を止めてエンジンを手放す。待たずに戻る。何度呼んでもよい
    func stop() {
        Self.queue.async {
            self.stopOnQueue()
        }
    }

    // MARK: - 中身

    private func stopOnQueue() {
        guard let engine = self.engine else {
            return
        }
        self.engine = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    /// `work` を専用のキューで行い、`timeout` 秒のうちに終わらなければ `.microphoneNotResponding` を投げる。
    /// 遅れて終わった `work` の結果は `cleanUpLateResult` で片付ける
    private static func run<T>(
        work: @escaping () throws -> T,
        cleanUpLateResult: @escaping (T) -> Void
    ) async throws -> T {
        let gate = ResumeOnce()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            Self.queue.async {
                let result = Result { try work() }
                guard gate.claim() else {
                    // 待つのをあきらめたあとに終わった。録音が動いていれば止める
                    if case .success(let value) = result {
                        cleanUpLateResult(value)
                    }
                    return
                }
                continuation.resume(with: result)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) {
                guard gate.claim() else {
                    return
                }
                continuation.resume(throwing: VoiceRecognitionFailure(failure: .microphoneNotResponding))
            }
        }
    }
}

/// 2 つの道（仕事が終わった・時間が過ぎた）のうち、先に来たほうだけを通す
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard !self.claimed else {
            return false
        }
        self.claimed = true
        return true
    }
}
