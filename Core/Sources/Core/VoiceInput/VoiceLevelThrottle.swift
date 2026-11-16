import Foundation

/// 録音の音の大きさを、聞き取りピルへ渡す回数を間引く。
///
/// 録音の知らせは 1 秒に 40 回以上届く。そのたびにメインスレッドへ渡してピルを描き直すと、
/// メインスレッドが追いつかないときに渡す仕事が積み上がり、IME 全体が重くなる。
/// 録音のスレッドから呼ばれるので、中の状態はロックで守る。
public final class VoiceLevelThrottle: @unchecked Sendable {
    /// これより短い間隔では渡さない（秒）
    public let interval: TimeInterval
    private let lock = NSLock()
    private var lastDeliveredAt: TimeInterval?

    public init(interval: TimeInterval = 0.05) {
        self.interval = interval
    }

    /// `now` に音の大きさを渡してよいか。渡してよいときは、渡したものとして覚える
    public func shouldDeliver(at now: TimeInterval) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let lastDeliveredAt = self.lastDeliveredAt, now - lastDeliveredAt < self.interval {
            return false
        }
        self.lastDeliveredAt = now
        return true
    }
}
