# CLAUDE.md

このリポジトリは azooKey on macOS（azooKey-Desktop）のフォークです。
目的は、ライブ変換中に「読み・文節の区切り・候補」を確かめられる新しいパネル UI（以下「変換パネル」）を作ることです。

## 最初に読むもの

- `docs/live-conversion-panel/spec.md` … 変換パネルの仕様（UI・キー操作・表示ルール・エンジンの制約）
- `docs/live-conversion-panel/tasks.md` … 段階ごとの作業と完了条件。作業はこの順に進める
- `docs/live-conversion-panel/mockup.html` … 仕様の元になった操作できるモックアップ（ブラウザで開ける）
- `plans/segment_edit.md` … 本家の文節編集に関する設計メモ（エンジンの制約の背景）

## 守ること

- **変換エンジン（AzooKeyKanaKanjiConverter / Zenzai）には手を入れない。** エンジンの変更が必要になったら、作業を止めて理由と選択肢をユーザーに報告する
- **変換パネルは設定でオン・オフできるようにし、オフのときは本家と同じ動作を保つ**
- **ロジックは `Core` に置き、テストを書く。** 文節のまとめ方、パネルに出す内容（表示モデル）、キー操作による状態の変化、パネル位置の計算は、AppKit に依存しない純粋な型・関数として `Core` に実装する
- **`azooKeyMac` 側は薄くする。** `Core` の表示モデルを受け取って描くこと、キーイベントを `Core` に渡すことだけを担当する
- 仕様にない判断が必要になったら、`spec.md` の「決定事項」を確認する。そこで「未決定のまま」となっている項目は、実装前にユーザーに確認する。載っていない小さな判断は自分で決め、PR の説明に書く
- 1つの段階を1つのブランチで進める（例：`feature/panel-p1-display`）。小さくコミットする
- `git push`、`sudo` を使う操作、`./install.sh`（`--dry-run` なし）はユーザーが行う。必要になったら依頼する
- 例外として、`Tools/dev_install_user.sh`（`sudo` なしで `~/Library/Input Methods` に入れ直す）は Claude が実行してよい。実機での確認も、computer use でできるところまで Claude が行う

## ビルドとテスト

```sh
# Core のビルドとテスト（Mac でも Linux でも動く。まずこれを回す）
swift build --package-path Core
swift test --package-path Core

# アプリ本体のビルド確認（Lint → アーカイブまで。インストールはしない）
./install.sh --dry-run

# Lint だけ
swiftlint --quiet --strict
```

- `./install.sh`（`--dry-run` なし）は `sudo` で `/Library/Input Methods/azooKeyMac.app` を置き換える。これはユーザーが実行する
- 開発中は `Tools/dev_install_user.sh` で `~/Library/Input Methods` に入れ直す。`/Library/Input Methods` に同じアプリが残っていると止まる
- `~/Library/Input Methods` に初めて置いたあとは、一度ログインし直さないと入力ソースの一覧に安定して載らない
- computer use で打ち込むときは、`type` ではなく `key` で 1 文字ずつ送る（`type` は IME を通らない）。スクリーンショットには IME のウィンドウ（変換パネル）が写らないので、表示は `CGWindowListCopyWindowInfo` などで確かめる
- 段階の作業が終わったら、ユーザーに「`./install.sh` を実行して、次の点を試してほしい」と、確認項目を箇条書きで伝える
- CI（`.github/workflows/swift.yml`）は macOS で `Core` とアプリのテスト、Ubuntu で `Core` のテストを回す。Ubuntu では Zenzai が無効になる点に注意する（`Core/Package.swift`）

## コードの地図（変換パネルに関係するところ）

- `azooKeyMac/InputController/azooKeyMacInputController.swift`
  - `handle(_:client:)` … キー入力の入口
  - `refreshMarkedText()` … アプリに未確定文字列を渡す。ライブ変換中は 1 つのかたまりで、文節情報なし
  - `refreshCandidateWindow()` … 候補ウィンドウの表示。位置は `client.attributes(forCharacterIndex: 0, lineHeightRectangle:)` の 1 点から決める
- `azooKeyMac/InputController/CandidateWindow/` … 既存の候補ウィンドウ（`NSWindow` + `NSTableView`、注釈欄あり）
- `Core/Sources/Core/InputUtils/SegmentsManager.swift`
  - `getCurrentMarkedText(inputState:)` … 未確定文字列の組み立て。ライブ変換時は `rawCandidates?.mainResults.first`
  - `getCurrentCandidateWindow(inputState:)` … 候補ウィンドウの状態。ライブ変換中の `.composing` は今は `.hidden`
  - `editSegment(count:)` … 既存の文節編集（先頭からの範囲を変える方式）
- `Core/Sources/Core/InputUtils/InputState.swift`、`Actions/UserAction.swift`、`Actions/ClientAction.swift` … 入力状態とキー操作の対応
- `Core/Sources/Core/Windows/WindowPositioning.swift` … ウィンドウ位置の計算（パネル位置の計算はここに寄せる）
- `Core/Sources/Core/Configs/` … 設定項目。真偽値は `BoolConfigItem` に倣う
