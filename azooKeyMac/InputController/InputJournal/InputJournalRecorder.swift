import Carbon
import Core

/// 入力記録を、設定がオンのときだけファイルに書き足す。
///
/// パスワードの入力中など、OS が安全な入力（Secure Event Input）にしているあいだは記録しない。
@MainActor
enum InputJournalRecorder {
    static let store = InputJournalStore(
        directoryURL: AppGroup.applicationSupportDirectoryURL()
            .appendingPathComponent(InputJournal.directoryName, isDirectory: true)
    )

    /// 今、記録してよいか
    static var isRecording: Bool {
        Config.KeepInputJournal().value && !IsSecureEventInputEnabled()
    }

    static func record(_ entry: InputJournal.ConversionEntry) {
        guard Self.isRecording else {
            return
        }
        Self.store.append(entry)
    }

    static func record(_ entry: InputJournal.VoiceEntry) {
        guard Self.isRecording else {
            return
        }
        Self.store.append(entry)
    }
}
