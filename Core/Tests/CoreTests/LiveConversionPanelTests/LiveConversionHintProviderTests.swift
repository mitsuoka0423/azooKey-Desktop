import Core
import Testing

@Suite("LiveConversionHintProvider")
struct LiveConversionHintProviderTests {
    private let provider = BundledLiveConversionHintProvider()

    @Test("同音異義語に手がかりが出る（助詞や送り仮名を除いて引く）")
    func homophones() {
        #expect(self.provider.displayHint(for: "箸を", reading: "はしを") == "食事の道具")
        #expect(self.provider.displayHint(for: "端を", reading: "はしを") == "物のへり・すみ")
        #expect(self.provider.displayHint(for: "橋を", reading: "はしを") == "川などに架ける")
        #expect(self.provider.displayHint(for: "渡る", reading: "わたる") == "向こう側へ行く")
        #expect(self.provider.displayHint(for: "汽車で", reading: "きしゃで") == "蒸気機関車")
    }

    @Test("読みと同じひらがなは「ひらがな」、カタカナは「カタカナ」")
    func kana() {
        #expect(self.provider.displayHint(for: "はしを", reading: "はしを") == "ひらがな")
        #expect(self.provider.displayHint(for: "ハシヲ", reading: "はしを") == "カタカナ")
        #expect(self.provider.displayHint(for: "ハシを", reading: "はしを") == "カタカナ")
    }

    @Test("説明がない候補は空欄")
    func unknown() {
        #expect(self.provider.displayHint(for: "土師を", reading: "はしを").isEmpty)
    }

    /// 出典を差し替えられる
    private struct FixedHintProvider: LiveConversionHintProvider {
        func hint(for candidate: String, reading: String) -> String? {
            candidate == "橋" ? "ブリッジ" : nil
        }
    }

    @Test("出典はプロトコルで差し替えられる")
    func replaceable() {
        #expect(FixedHintProvider().displayHint(for: "橋を", reading: "はしを") == "ブリッジ")
    }
}
