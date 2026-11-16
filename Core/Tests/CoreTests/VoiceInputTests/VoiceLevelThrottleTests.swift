import Foundation
import Testing

@testable import Core

@Suite("VoiceLevelThrottle")
struct VoiceLevelThrottleTests {
    @Test("最初の音の大きさは渡す")
    func deliversFirstLevel() {
        let throttle = VoiceLevelThrottle(interval: 0.05)
        #expect(throttle.shouldDeliver(at: 10))
    }

    @Test("間隔より短いあいだに届いたものは渡さない")
    func skipsLevelsWithinInterval() {
        let throttle = VoiceLevelThrottle(interval: 0.05)
        #expect(throttle.shouldDeliver(at: 10))
        #expect(!throttle.shouldDeliver(at: 10.02))
        #expect(!throttle.shouldDeliver(at: 10.049))
        #expect(throttle.shouldDeliver(at: 10.05))
    }

    @Test("間引いたものは覚えず、渡した時刻から数える")
    func countsFromLastDeliveredLevel() {
        let throttle = VoiceLevelThrottle(interval: 0.05)
        #expect(throttle.shouldDeliver(at: 10))
        #expect(!throttle.shouldDeliver(at: 10.04))
        #expect(throttle.shouldDeliver(at: 10.06))
        #expect(!throttle.shouldDeliver(at: 10.1))
    }

    @Test("1 秒に 43 回届いても、渡すのは 1 秒に 20 回まで")
    func limitsDeliveriesPerSecond() {
        let throttle = VoiceLevelThrottle(interval: 0.05)
        let delivered = (0..<43).filter { throttle.shouldDeliver(at: Double($0) / 43) }.count
        #expect(delivered <= 20)
        #expect(delivered >= 15)
    }
}
