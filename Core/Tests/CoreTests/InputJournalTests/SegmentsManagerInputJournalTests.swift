import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@MainActor
@Suite("確定したときの変換の記録")
struct SegmentsManagerInputJournalTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func manager() -> SegmentsManager {
        SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false, now: { now })
        )
    }

    private static func type(_ manager: SegmentsManager, _ text: String) {
        for character in text {
            manager.insertAtCursorPosition(String(character), inputStyle: .roman2kana)
        }
    }

    @Test("まとめて確定すると、読みと確定した表記の組が 1 件届く")
    func wholeCommit() throws {
        let manager = Self.manager()
        var entries: [InputJournal.ConversionEntry] = []
        manager.onConversionCommitted = { entries.append($0) }
        Self.type(manager, "kyou")
        let text = manager.commitMarkedText(inputState: .composing)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.reading == "キョウ")
        #expect(entry.text == text)
        #expect(entry.commit == .whole)
        #expect(entry.at == Self.now)
    }

    @Test("候補を選んで確定すると、その候補の読みと表記が届く")
    func candidateCommit() throws {
        let manager = Self.manager()
        var entries: [InputJournal.ConversionEntry] = []
        manager.onConversionCommitted = { entries.append($0) }
        Self.type(manager, "kyou")
        manager.requestSetCandidateWindowState(visible: true)
        guard case let .selecting(candidates, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
            Issue.record("候補ウィンドウが出ていない")
            return
        }
        let candidate = try #require(candidates.first { $0.text == "今日" })
        manager.prefixCandidateCommited(candidate, leftSideContext: "明日と")
        #expect(entries == [
            InputJournal.ConversionEntry(at: Self.now, reading: "キョウ", text: "今日", leftContext: "明日と", commit: .candidate)
        ])
    }

    @Test("受け取る先がないときは何もしない")
    func noReceiver() {
        let manager = Self.manager()
        Self.type(manager, "kyou")
        #expect(!manager.commitMarkedText(inputState: .composing).isEmpty)
    }
}
