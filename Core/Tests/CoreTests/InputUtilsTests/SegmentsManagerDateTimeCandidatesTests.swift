import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@MainActor
@Suite("日時の候補（実際の変換）")
struct SegmentsManagerDateTimeCandidatesTests {
    /// 2026/3/5 9:05（この端末のタイムゾーン）
    private static let now: Date = {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 9, minute: 5))!
    }()

    private static func manager(panel: Bool) -> SegmentsManager {
        SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false, forceLiveConversionPanel: panel, now: { now })
        )
    }

    private static func type(_ manager: SegmentsManager, _ text: String) {
        for character in text {
            manager.insertAtCursorPosition(String(character), inputStyle: .roman2kana)
        }
    }

    private static func windowTexts(_ manager: SegmentsManager) -> [String] {
        manager.requestSetCandidateWindowState(visible: true)
        guard case let .selecting(candidates, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
            return []
        }
        return candidates.map(\.text)
    }

    @Test("候補ウィンドウでは 3 番目から日時の候補が並び、本文は変わらない")
    func candidateWindow() {
        let manager = Self.manager(panel: false)
        Self.type(manager, "kyou")
        let texts = Self.windowTexts(manager)
        #expect(texts.first == "今日")
        #expect(Array(texts.dropFirst(2).prefix(4)) == ["3/5", "03/05", "2026/03/05", "2026-03-05"])
        #expect(texts.contains("木曜日"))

        let now = Self.manager(panel: false)
        Self.type(now, "ima")
        #expect(Array(Self.windowTexts(now).dropFirst(2).prefix(6)) == ["9:05", "09:05", "9時5分", "09時05分", "午前9時5分", "午前09時05分"])
    }

    @Test("読みが日時の語だけでないときは出さない")
    func notWholeReading() {
        let manager = Self.manager(panel: false)
        Self.type(manager, "kyouha")
        #expect(!Self.windowTexts(manager).contains("3/5"))
    }

    @Test("変換パネルの文節の候補にも、3 番目から日時の候補が入る")
    func panel() {
        let manager = Self.manager(panel: true)
        Self.type(manager, "kyou")
        #expect(manager.getLiveConversionClauses().map(\.surface) == ["今日"])
        let items = manager.getLiveConversionPanelModel().candidateList?.items.map(\.text) ?? []
        #expect(Array(items.prefix(4)) == ["今日", "きょう", "3/5", "03/05"])
    }

    @Test("日時の候補を選んで確定できる（学習はしない）")
    func commit() {
        let manager = Self.manager(panel: false)
        Self.type(manager, "kyou")
        manager.requestSetCandidateWindowState(visible: true)
        guard case let .selecting(candidates, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
            Issue.record("候補ウィンドウが出ない")
            return
        }
        let date = candidates[2]
        #expect(date.text == "3/5")
        #expect(!date.isLearningTarget)
        manager.prefixCandidateCommited(date, leftSideContext: "")
        #expect(manager.isEmpty)
    }
}
