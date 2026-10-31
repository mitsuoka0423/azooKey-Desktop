// 開発用：~/Library/Input Methods に置いた azooKeyMac.app を、ログインし直さずに OS へ登録する。
// 有効にする（入力ソースに追加する）のはシステム設定で行う。
import Carbon
import Foundation

let path = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSHomeDirectory() + "/Library/Input Methods/azooKeyMac.app"
let status = TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL)
guard status == noErr else {
    FileHandle.standardError.write("TISRegisterInputSource failed: \(status)\n".data(using: .utf8)!)
    exit(1)
}
