import Foundation

/// 「きょう」「いま」などの読みから、今の日付・時刻の候補を作る
///
/// 1 桁の月・日・時・分があるときは、0 で埋めた形をすぐ後ろに足す（「3/5」の次に「03/05」）。
/// 2 桁なら同じ形になるので足さない
public enum DateTimeCandidates {
    /// 日付を出す読みと、今日から何日ずらすか
    static let dayOffsets: [String: Int] = [
        "おととい": -2,
        "きのう": -1,
        "きょう": 0,
        "あした": 1,
        "あさって": 2
    ]

    /// 日時の候補を出す読みか
    public static func isTarget(reading: String) -> Bool {
        dayOffsets[reading] != nil || ["いま", "ことし", "こんげつ"].contains(reading)
    }

    /// 候補の文字列。日時の候補を出す読みでなければ空
    /// - Parameters:
    ///   - reading: ひらがなの読み
    ///   - now: 今の時刻（テストで固定するため外から渡す）
    ///   - timeZone: 日付と時刻を数えるタイムゾーン
    public static func candidates(reading: String, now: Date, timeZone: TimeZone = .current) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let offset = dayOffsets[reading] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else {
                return []
            }
            return self.dateCandidates(day, calendar: calendar)
        }
        switch reading {
        case "いま":
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)
            let halfDay = hour < 12 ? "午前" : "午後"
            return self.withPadding([
                ("\(hour):\(pad(minute))", "\(pad(hour)):\(pad(minute))"),
                ("\(hour)時\(minute)分", "\(pad(hour))時\(pad(minute))分"),
                ("\(halfDay)\(hour % 12)時\(minute)分", "\(halfDay)\(pad(hour % 12))時\(pad(minute))分")
            ])
        case "ことし":
            let year = calendar.component(.year, from: now)
            return ["\(year)年", self.japaneseYear(now, timeZone: timeZone)]
        case "こんげつ":
            let month = calendar.component(.month, from: now)
            return self.withPadding([("\(month)月", "\(pad(month))月")])
        default:
            return []
        }
    }

    private static func dateCandidates(_ day: Date, calendar: Calendar) -> [String] {
        let year = calendar.component(.year, from: day)
        let month = calendar.component(.month, from: day)
        let date = calendar.component(.day, from: day)
        let weekday = self.weekdaySymbol(calendar.component(.weekday, from: day))
        let era = self.japaneseYear(day, timeZone: calendar.timeZone)
        return self.withPadding([
            ("\(month)/\(date)", "\(pad(month))/\(pad(date))"),
            ("\(year)/\(pad(month))/\(pad(date))", nil),
            ("\(year)-\(pad(month))-\(pad(date))", nil),
            ("\(month)月\(date)日（\(weekday)）", "\(pad(month))月\(pad(date))日（\(weekday)）"),
            ("\(year)年\(month)月\(date)日", "\(year)年\(pad(month))月\(pad(date))日"),
            ("\(era)\(month)月\(date)日", "\(era)\(pad(month))月\(pad(date))日"),
            ("\(weekday)曜日", nil)
        ])
    }

    /// 0 埋めしない形と、0 埋めした形（違うときだけ）を順に並べる
    private static func withPadding(_ forms: [(plain: String, padded: String?)]) -> [String] {
        forms.flatMap { plain, padded in
            if let padded, padded != plain {
                [plain, padded]
            } else {
                [plain]
            }
        }
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// `Calendar.component(.weekday)` は日曜が 1
    private static func weekdaySymbol(_ weekday: Int) -> String {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        return symbols[(weekday - 1 + symbols.count) % symbols.count]
    }

    /// 和暦の年（「令和8年」）
    private static func japaneseYear(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .japanese)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = timeZone
        formatter.dateFormat = "Gy年"
        return formatter.string(from: date)
    }
}
