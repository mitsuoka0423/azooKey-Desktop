import Testing

@testable import Core

@Suite("SoftwareUpdateMenuItem")
struct SoftwareUpdateMenuItemTests {
    @Test("更新を確かめられないときは、項目を残したまま押せなくする")
    func unavailable() {
        #expect(SoftwareUpdateMenuItem.make(for: .unavailable) == SoftwareUpdateMenuItem(title: "アップデートを確認…", isEnabled: false))
    }

    @Test("ふだんは「アップデートを確認…」を押せる")
    func idle() {
        #expect(SoftwareUpdateMenuItem.make(for: .idle) == SoftwareUpdateMenuItem(title: "アップデートを確認…", isEnabled: true))
    }

    @Test("新しい版が見つかったら、題に版を出す")
    func updateAvailable() {
        #expect(SoftwareUpdateMenuItem.make(for: .updateAvailable(version: "1.0.42")) == SoftwareUpdateMenuItem(title: "新しい版があります（1.0.42）…", isEnabled: true))
    }

    @Test("版がわからないときは、版を出さない")
    func updateAvailableWithoutVersion() {
        #expect(SoftwareUpdateMenuItem.make(for: .updateAvailable(version: "")).title == "新しい版があります…")
    }
}

@Suite("SoftwareUpdateConfiguration")
struct SoftwareUpdateConfigurationTests {
    private let feed = "https://github.com/mitsuoka0423/azooKey-Desktop/releases/latest/download/appcast.xml"

    @Test("公開鍵とフィードがそろえば動かす")
    func available() {
        #expect(SoftwareUpdateConfiguration.isAvailable(publicEDKey: "abc=", feedURL: self.feed))
    }

    @Test("公開鍵がない・空・展開されていないときは動かさない")
    func missingKey() {
        #expect(!SoftwareUpdateConfiguration.isAvailable(publicEDKey: nil, feedURL: self.feed))
        #expect(!SoftwareUpdateConfiguration.isAvailable(publicEDKey: "", feedURL: self.feed))
        #expect(!SoftwareUpdateConfiguration.isAvailable(publicEDKey: " \n", feedURL: self.feed))
        #expect(!SoftwareUpdateConfiguration.isAvailable(publicEDKey: "$(SPARKLE_PUBLIC_ED_KEY)", feedURL: self.feed))
    }

    @Test("フィードがない・https でないときは動かさない（手元の確認用の 127.0.0.1 と localhost は除く）")
    func feedRequirements() {
        #expect(!SoftwareUpdateConfiguration.isAvailable(publicEDKey: "abc=", feedURL: nil))
        #expect(!SoftwareUpdateConfiguration.isAvailable(publicEDKey: "abc=", feedURL: ""))
        #expect(!SoftwareUpdateConfiguration.isAvailable(publicEDKey: "abc=", feedURL: "http://example.com/appcast.xml"))
        #expect(SoftwareUpdateConfiguration.isAvailable(publicEDKey: "abc=", feedURL: "http://127.0.0.1:8000/appcast.xml"))
        #expect(SoftwareUpdateConfiguration.isAvailable(publicEDKey: "abc=", feedURL: "http://localhost:8000/appcast.xml"))
    }
}
