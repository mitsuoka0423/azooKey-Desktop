import Core
import Testing

@Suite("LiveConversionPanelPositioning")
struct LiveConversionPanelPositioningTests {
    private static let screen = WindowPositioning.Rect(origin: .init(x: 0, y: 0), size: .init(width: 1000, height: 800))
    private static let panel = WindowPositioning.Size(width: 300, height: 100)

    private static func anchor(x: Double, y: Double) -> WindowPositioning.Rect {
        .init(origin: .init(x: x, y: y), size: .init(width: 0, height: 20))
    }

    private static func frame(
        anchor: WindowPositioning.Rect,
        size: WindowPositioning.Size = panel,
        previous: WindowPositioning.PanelPlacement? = nil
    ) -> WindowPositioning.PanelFrame {
        WindowPositioning.liveConversionPanelFrame(
            anchor: anchor,
            panelSize: size,
            screenRect: screen,
            previousPlacement: previous,
            leftInset: 12,
            gap: 4
        )
    }

    @Test("原則は行の下で、左端は基準点より少し左")
    func placesBelow() {
        let result = Self.frame(anchor: Self.anchor(x: 200, y: 500))
        #expect(result == .init(origin: .init(x: 188, y: 396), placement: .below))
    }

    @Test("画面の下端に入りきらないときは行の上")
    func placesAboveNearBottom() {
        let result = Self.frame(anchor: Self.anchor(x: 200, y: 50))
        #expect(result == .init(origin: .init(x: 188, y: 74), placement: .above))
    }

    @Test("一度上に出したら、下に入るようになっても上のまま")
    func staysAboveOnceAbove() {
        let small = WindowPositioning.Size(width: 300, height: 20)
        let result = Self.frame(anchor: Self.anchor(x: 200, y: 50), size: small, previous: .above)
        #expect(result.placement == .above)
        #expect(result.origin.y == 74)
    }

    @Test("前回が下なら、下に入る限り下")
    func staysBelowWhenFits() {
        let result = Self.frame(anchor: Self.anchor(x: 200, y: 500), previous: .below)
        #expect(result.placement == .below)
    }

    @Test("画面の右端に入りきらないときは左にずらす")
    func shiftsLeftAtRightEdge() {
        let result = Self.frame(anchor: Self.anchor(x: 900, y: 500))
        #expect(result.origin.x == 700)
    }

    @Test("画面の左端より左には出さない")
    func clampsLeftEdge() {
        let result = Self.frame(anchor: Self.anchor(x: 5, y: 500))
        #expect(result.origin.x == 0)
    }

    @Test("上にも入りきらないときは画面内に押し込む")
    func clampsWhenNeitherFits() {
        let tall = WindowPositioning.Size(width: 300, height: 790)
        let result = Self.frame(anchor: Self.anchor(x: 200, y: 50), size: tall)
        #expect(result.placement == .above)
        #expect(result.origin.y == 10)
    }

    @Test("画面の原点がずれていても（2 枚目のディスプレイなど）同じ規則")
    func respectsScreenOrigin() {
        let screen = WindowPositioning.Rect(origin: .init(x: 1000, y: -800), size: .init(width: 1000, height: 800))
        let result = WindowPositioning.liveConversionPanelFrame(
            anchor: Self.anchor(x: 1500, y: -750),
            panelSize: Self.panel,
            screenRect: screen,
            previousPlacement: nil
        )
        #expect(result.placement == .above)
        #expect(result.origin.x == 1488)
    }
}
