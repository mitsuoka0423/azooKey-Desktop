import Core
import Foundation
import Testing

@Suite("日時の候補")
struct DateTimeCandidatesTests {
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func candidates(_ reading: String, _ now: Date) -> [String] {
        DateTimeCandidates.candidates(reading: reading, now: now, timeZone: tokyo)
    }

    @Test("「きょう」は 2 桁の月・日なら 0 埋めの形を足さない")
    func todayTwoDigits() {
        #expect(Self.candidates("きょう", Self.date(2026, 11, 11)) == [
            "11/11", "2026/11/11", "2026-11-11", "11月11日（水）", "2026年11月11日", "令和8年11月11日", "水曜日"
        ])
    }

    @Test("1 桁の月・日があるときは、0 埋めした形をすぐ後ろに足す")
    func todayOneDigit() {
        #expect(Self.candidates("きょう", Self.date(2026, 3, 5)) == [
            "3/5", "03/05", "2026/03/05", "2026-03-05", "3月5日（木）", "03月05日（木）",
            "2026年3月5日", "2026年03月05日", "令和8年3月5日", "令和8年03月05日", "木曜日"
        ])
    }

    @Test("あした・きのう・おととい・あさっては日をずらす（月や年もまたぐ）")
    func dayOffsets() {
        let now = Self.date(2026, 12, 31, 23, 59)
        #expect(Self.candidates("あした", now).prefix(2) == ["1/1", "01/01"])
        #expect(Self.candidates("あした", now).contains("2027年1月1日"))
        #expect(Self.candidates("あさって", now).first == "1/2")
        #expect(Self.candidates("きのう", now).first == "12/30")
        #expect(Self.candidates("おととい", now).first == "12/29")
    }

    @Test("「いま」は 0 埋めしない形を先に、0 埋めした形を後ろに出す")
    func nowOneDigit() {
        #expect(Self.candidates("いま", Self.date(2026, 11, 11, 9, 5)) == [
            "9:05", "09:05", "9時5分", "09時05分", "午前9時5分", "午前09時05分"
        ])
    }

    @Test("「いま」は 2 桁なら 0 埋めの形を足さない。午後は 12 時間で数え、その時が 1 桁なら 0 埋めの形を足す")
    func nowAfternoon() {
        #expect(Self.candidates("いま", Self.date(2026, 11, 11, 13, 45)) == ["13:45", "13時45分", "午後1時45分", "午後01時45分"])
        #expect(Self.candidates("いま", Self.date(2026, 11, 11, 23, 45)) == ["23:45", "23時45分", "午後11時45分"])
        #expect(Self.candidates("いま", Self.date(2026, 11, 11, 12, 30)) == ["12:30", "12時30分", "午後0時30分", "午後00時30分"])
    }

    @Test("ことし・こんげつ")
    func yearAndMonth() {
        #expect(Self.candidates("ことし", Self.date(2026, 3, 5)) == ["2026年", "令和8年"])
        #expect(Self.candidates("こんげつ", Self.date(2026, 3, 5)) == ["3月", "03月"])
        #expect(Self.candidates("こんげつ", Self.date(2026, 11, 5)) == ["11月"])
    }

    @Test("日時の読みでなければ出さない")
    func otherReadings() {
        #expect(Self.candidates("きょうは", Self.date(2026, 11, 11)).isEmpty)
        #expect(Self.candidates("いまから", Self.date(2026, 11, 11)).isEmpty)
        #expect(!DateTimeCandidates.isTarget(reading: "きょうは"))
        #expect(DateTimeCandidates.isTarget(reading: "いま"))
    }
}
