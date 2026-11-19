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

    @Test("英字の見分けは既定でオン")
    func mixedInputDetectionDefaultIsOn() {
        #expect(Config.MixedInputDetection.default == true)
        #expect(Config.MixedInputDetection.key.hasSuffix(".preference.enableMixedInputDetection"))
    }
}
