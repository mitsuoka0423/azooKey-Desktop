import Testing

@testable import Core

@Suite("LiveConversionPanelConfig")
struct LiveConversionPanelConfigTests {
    @Test("変換パネルは既定でオフ")
    func defaultIsOff() {
        #expect(Config.LiveConversionPanel.default == false)
    }

    @Test("ほかの設定とキーが重ならない")
    func keyIsUnique() {
        #expect(Config.LiveConversionPanel.key != Config.LiveConversion.key)
        #expect(Config.LiveConversionPanel.key.hasSuffix(".preference.enableLiveConversionPanel"))
    }
}
