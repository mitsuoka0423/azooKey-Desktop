import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// 入力記録：自分が確定した文を、あとで変換や音声認識を自分好みに育てる材料として手元に残す。
///
/// 記録は 2 種類ある。
/// - 変換の記録（`ConversionEntry`）：キーボードで打った読みと、確定した表記の組
/// - 音声の記録（`VoiceEntry`）：音声入力で確定した文
///
/// 記録は Mac の中のファイルに書くだけで、どこにも送らない。設定でオンにしたときだけ残す。
public enum InputJournal {
    /// 記録を書くフォルダの名前（azooKey のアプリケーションサポートの下）
    public static let directoryName = "InputJournal"
    /// 前の文脈として残す最大の文字数
    public static let leftContextMaxCount = 30

    /// 変換の記録：キーボードで打った読みと、確定した表記の組
    public struct ConversionEntry: Codable, Equatable, Sendable {
        /// どうやって確定したか
        public enum Commit: String, Codable, Sendable {
            /// 未確定文字列をまとめて確定した（Enter など）
            case whole
            /// 候補を選んで、先頭から一部を確定した
            case candidate
        }

        /// 確定した時刻
        public var at: Date
        /// 読み（カタカナ）。Zenzai が受け取る読みと同じ形にする
        public var reading: String
        /// 確定した表記
        public var text: String
        /// 確定した位置より前の文（同じ行の、最大 `leftContextMaxCount` 文字）
        public var leftContext: String
        public var commit: Commit

        public init(at: Date, reading: String, text: String, leftContext: String, commit: Commit) {
            self.at = at
            self.reading = reading
            self.text = text
            self.leftContext = leftContext
            self.commit = commit
        }
    }

    /// 音声の記録：音声入力で確定した文
    public struct VoiceEntry: Codable, Equatable, Sendable {
        /// 確定した時刻
        public var at: Date
        /// 確定した文（認識結果をつないだもの）
        public var text: String
        /// 使った認識の仕組み（設定の値。`speechTranscriber`＝高精度、`standard`＝互換）
        public var engine: String
        /// 確定した位置より前の文（同じ行の、最大 `leftContextMaxCount` 文字）
        public var leftContext: String

        public init(at: Date, text: String, engine: String, leftContext: String) {
            self.at = at
            self.text = text
            self.engine = engine
            self.leftContext = leftContext
        }
    }

    /// 変換の記録を作る。記録しないもの（空の確定）は nil を返す
    /// - Parameter reading: 打った読み（ひらがなでもカタカナでもよい）
    public static func conversionEntry(
        reading: String,
        text: String,
        leftContext: String?,
        commit: ConversionEntry.Commit,
        at: Date
    ) -> ConversionEntry? {
        guard !reading.isEmpty, !text.isEmpty else {
            return nil
        }
        return ConversionEntry(
            at: at,
            reading: reading.toKatakana(),
            text: text,
            leftContext: Self.trimmedLeftContext(leftContext),
            commit: commit
        )
    }

    /// 音声の記録を作る。記録しないもの（空の確定）は nil を返す
    public static func voiceEntry(text: String, engine: String, leftContext: String?, at: Date) -> VoiceEntry? {
        guard !text.isEmpty else {
            return nil
        }
        return VoiceEntry(at: at, text: text, engine: engine, leftContext: Self.trimmedLeftContext(leftContext))
    }

    /// 1 件を 1 行の JSON にする（JSON Lines）
    public static func line(for entry: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(entry)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// 1 行の JSON から 1 件を読む
    public static func entry<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: line)
    }

    private static func trimmedLeftContext(_ leftContext: String?) -> String {
        String((leftContext ?? "").suffix(Self.leftContextMaxCount))
    }
}
