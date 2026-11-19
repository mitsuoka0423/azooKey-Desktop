import Foundation

/// 入力記録をファイルに書き足す。
///
/// 種類ごとに 1 つのファイル（JSON Lines）に書く。ファイルが `maxBytes` を超えたら、
/// 古いほうを 1 つだけ残して（`〜.old.jsonl`）新しいファイルに書き始める。
/// 書き込みは専用のキューで行い、呼んだ側（キー入力）を待たせない。
public final class InputJournalStore: @unchecked Sendable {
    /// 記録の種類ごとのファイル
    public enum File: String, CaseIterable, Sendable {
        /// 変換の記録
        case conversion
        /// 音声の記録
        case voice

        public var fileName: String {
            "\(self.rawValue).jsonl"
        }

        public var oldFileName: String {
            "\(self.rawValue).old.jsonl"
        }
    }

    /// 1 つのファイルの大きさの上限（バイト）。既定は 20MB
    public let maxBytes: Int
    public let directoryURL: URL
    private let queue = DispatchQueue(label: "dev.azooKey.inputJournal", qos: .utility)

    public init(directoryURL: URL, maxBytes: Int = 20 * 1024 * 1024) {
        self.directoryURL = directoryURL
        self.maxBytes = maxBytes
    }

    /// 変換の記録を書き足す
    public func append(_ entry: InputJournal.ConversionEntry) {
        self.append(entry, to: .conversion)
    }

    /// 音声の記録を書き足す
    public func append(_ entry: InputJournal.VoiceEntry) {
        self.append(entry, to: .voice)
    }

    /// 記録をすべて消す
    public func deleteAll() {
        self.queue.sync {
            for file in File.allCases {
                try? FileManager.default.removeItem(at: self.url(of: file.fileName))
                try? FileManager.default.removeItem(at: self.url(of: file.oldFileName))
            }
        }
    }

    /// 書きかけの記録をすべて書き終えるまで待つ（テストと、消す前の確認に使う）
    public func waitUntilWritten() {
        self.queue.sync {}
    }

    /// 今のファイルにある記録の件数（古いほうは数えない）
    public func count(of file: File) -> Int {
        self.queue.sync {
            guard let data = try? Data(contentsOf: self.url(of: file.fileName)) else {
                return 0
            }
            return data.split(separator: UInt8(ascii: "\n")).count
        }
    }

    // MARK: - 中身

    private func append(_ entry: some Encodable & Sendable, to file: File) {
        self.queue.async {
            guard let line = try? InputJournal.line(for: entry) else {
                return
            }
            try? self.write(line, to: file)
        }
    }

    private func write(_ line: Data, to file: File) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        let url = self.url(of: file.fileName)
        if let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? Int,
           size + line.count > self.maxBytes {
            let oldURL = self.url(of: file.oldFileName)
            try? fileManager.removeItem(at: oldURL)
            try fileManager.moveItem(at: url, to: oldURL)
        }
        guard fileManager.fileExists(atPath: url.path) else {
            // 自分だけが読み書きできるファイルにする
            fileManager.createFile(atPath: url.path, contents: line, attributes: [.posixPermissions: 0o600])
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func url(of fileName: String) -> URL {
        self.directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }
}
