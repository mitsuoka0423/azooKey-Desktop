import AppKit
import Core
import Sparkle

/// Sparkle でアプリの中から更新する。
///
/// IME は裏で動いているので、定期の確認で新しい版が見つかっても窓は出さない
/// （打っている最中にフォーカスを奪うと、キーが更新の窓に入ってしまうため）。
/// かわりに入力メニューの項目の題で知らせ、使う人が選んだときにだけ窓を出す。
@MainActor
final class SoftwareUpdater: NSObject {
    static let shared = SoftwareUpdater()

    private var controller: SPUStandardUpdaterController?
    private(set) var state: SoftwareUpdateMenuItem.State = .unavailable

    var isAvailable: Bool {
        self.controller != nil
    }

    /// 起動時に一度呼ぶ。公開鍵やフィードがないビルドでは動かさない
    func start() {
        guard self.controller == nil else {
            return
        }
        let info = Bundle.main.infoDictionary
        guard SoftwareUpdateConfiguration.isAvailable(
            publicEDKey: info?["SUPublicEDKey"] as? String,
            feedURL: info?["SUFeedURL"] as? String
        ) else {
            self.state = .unavailable
            return
        }
        self.controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.state = .idle
    }

    /// 定期の確認をするかどうか。Sparkle の設定（`SUEnableAutomaticChecks`）をそのまま読み書きする
    var automaticallyChecksForUpdates: Bool {
        get {
            self.controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            self.controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// 使う人が選んだときの確認。見つかっていた新しい版があれば、その窓を出す
    func checkForUpdates() {
        guard let controller else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// 更新の窓を、ほかのアプリの窓より前に出す。IME は裏で動くアプリなので、ふつうの高さだと後ろに隠れる
    private func bringUpdateWindowsToFront() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.isVisible && String(describing: type(of: window)).hasPrefix("SU") {
                window.level = .modalPanel
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

extension SoftwareUpdater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    /// 定期の確認で見つかった版は、起動した直後でも Sparkle に出させない。入力メニューの題で知らせる
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            if userInitiated {
                self.bringUpdateWindowsToFront()
            } else {
                self.state = .updateAvailable(version: version)
            }
        }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated {
            self.bringUpdateWindowsToFront()
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            if self.isAvailable {
                self.state = .idle
            }
        }
    }
}
