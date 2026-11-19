import Foundation
import Testing

@testable import Core

@Suite("入力記録")
struct InputJournalTests {
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("変換の記録は、読みをカタカナにして残す")
    func conversionEntryUsesKatakanaReading() throws {
        let entry = try #require(InputJournal.conversionEntry(reading: "わりびきりつ", text: "割引率", leftContext: "今月の", commit: .whole, at: self.at))
        #expect(entry.reading == "ワリビキリツ")
        #expect(entry.text == "割引率")
        #expect(entry.leftContext == "今月の")
        #expect(entry.commit == .whole)
    }

    @Test("空の確定は記録しない")
    func skipsEmptyCommit() {
        #expect(InputJournal.conversionEntry(reading: "", text: "割引率", leftContext: nil, commit: .whole, at: self.at) == nil)
        #expect(InputJournal.conversionEntry(reading: "わりびき", text: "", leftContext: nil, commit: .whole, at: self.at) == nil)
        #expect(InputJournal.voiceEntry(text: "", engine: "speechTranscriber", leftContext: nil, at: self.at) == nil)
    }

    @Test("前の文は最後の 30 文字だけ残す")
    func trimsLeftContext() throws {
        let long = String(repeating: "あ", count: 40) + "いう"
        let entry = try #require(InputJournal.voiceEntry(text: "こんにちは", engine: "speechTranscriber", leftContext: long, at: self.at))
        #expect(entry.leftContext.count == 30)
        #expect(entry.leftContext.hasSuffix("いう"))
    }

    @Test("1 件を 1 行の JSON にし、読み戻せる")
    func roundTripsLine() throws {
        let entry = try #require(InputJournal.conversionEntry(reading: "いしゅー", text: "Issue", leftContext: "GitHubの", commit: .candidate, at: self.at))
        let line = try InputJournal.line(for: entry)
        #expect(line.last == UInt8(ascii: "\n"))
        #expect(line.dropLast().contains(UInt8(ascii: "\n")) == false)
        let decoded = try InputJournal.entry(InputJournal.ConversionEntry.self, from: line.dropLast())
        #expect(decoded == entry)
    }
}

@Suite("入力記録の保存")
struct InputJournalStoreTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("InputJournalTests-\(UUID().uuidString)", isDirectory: true)
    }

    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("種類ごとのファイルに 1 行ずつ書き足す")
    func appendsLines() throws {
        let directory = self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InputJournalStore(directoryURL: directory)
        store.append(try #require(InputJournal.conversionEntry(reading: "きょう", text: "今日", leftContext: nil, commit: .whole, at: self.at)))
        store.append(try #require(InputJournal.conversionEntry(reading: "あした", text: "明日", leftContext: nil, commit: .whole, at: self.at)))
        store.append(try #require(InputJournal.voiceEntry(text: "こんにちは", engine: "standard", leftContext: nil, at: self.at)))
        store.waitUntilWritten()
        #expect(store.count(of: .conversion) == 2)
        #expect(store.count(of: .voice) == 1)
    }

    @Test("自分だけが読み書きできるファイルにする")
    func createsPrivateFile() throws {
        let directory = self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InputJournalStore(directoryURL: directory)
        store.append(try #require(InputJournal.voiceEntry(text: "こんにちは", engine: "standard", leftContext: nil, at: self.at)))
        store.waitUntilWritten()
        let url = directory.appendingPathComponent(InputJournalStore.File.voice.fileName)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test("上限を超えたら古いほうを 1 つ残して書き直す")
    func rotatesWhenFull() throws {
        let directory = self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = try #require(InputJournal.conversionEntry(reading: "きょう", text: "今日", leftContext: nil, commit: .whole, at: self.at))
        let lineSize = try InputJournal.line(for: entry).count
        let store = InputJournalStore(directoryURL: directory, maxBytes: lineSize * 3)
        for _ in 0..<5 {
            store.append(entry)
        }
        store.waitUntilWritten()
        #expect(store.count(of: .conversion) == 2)
        let oldURL = directory.appendingPathComponent(InputJournalStore.File.conversion.oldFileName)
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
    }

    @Test("すべて消せる")
    func deletesAll() throws {
        let directory = self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InputJournalStore(directoryURL: directory)
        store.append(try #require(InputJournal.conversionEntry(reading: "きょう", text: "今日", leftContext: nil, commit: .whole, at: self.at)))
        store.waitUntilWritten()
        store.deleteAll()
        #expect(store.count(of: .conversion) == 0)
    }
}
