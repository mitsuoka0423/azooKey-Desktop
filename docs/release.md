# リリース（main への push で配布用の pkg を作る）

main に push され、「Swift Build and Test」が通ると、`.github/workflows/release.yml` が動きます。

- アプリを Developer ID で署名し、Apple の公証を受けた pkg を作ります。
- その pkg を付けて、GitHub Release `v1.0.<番号>` を作ります。番号はワークフローの実行番号です。

作り方の中身は `Tools/release_package.sh` にあります。Xcode の自動署名は使いません。署名なしで archive してから、`codesign` で署名します。

## 最初に一度だけ用意するもの

### 1. Developer ID の証明書（Application と Installer）

Developer ID の証明書を作れるのは、Apple Developer Program の Account Holder だけです。

1. Xcode の Settings → Accounts でチームを選び、Manage Certificates を開きます。
2. ＋ から「Developer ID Application」と「Developer ID Installer」を作ります。
3. キーチェーンアクセスの「自分の証明書」で、2 つの証明書を秘密鍵ごと選び、.p12 で書き出します。
   - 1 つずつ書き出し、同じパスワードを付けます。

### 2. Developer ID のプロビジョニングプロファイル

App Group を使っているので、アプリにプロファイルを入れる必要があります。

1. developer.apple.com の Certificates, Identifiers & Profiles で、Profiles の ＋ を押します。
2. Distribution の「Developer ID」を選びます。
3. App ID は、App Group を付けて登録済みの `dev.<owner>.inputmethod.azooKeyMac` を選びます。
4. 証明書は、1 で作った Developer ID Application を選びます。
5. できたプロファイル（.provisionprofile）をダウンロードします。

### 3. 公証用の App Store Connect API キー

1. App Store Connect の「ユーザとアクセス」→「統合」→「App Store Connect API」で、チームキーを作ります。
   - アクセスは「Developer」で足ります。
2. .p8 をダウンロードします（一度しかダウンロードできません）。
3. Key ID と Issuer ID を控えます。

### 4. GitHub に登録する

リポジトリの変数（個人の ID はコミットせず、ここに置きます）：

```sh
gh variable set BUNDLE_OWNER --repo <owner>/azooKey-Desktop --body "<owner>"
gh variable set TEAM_ID --repo <owner>/azooKey-Desktop --body "<Team ID>"
```

Secrets（値はファイルから読み込ませ、画面に出さないようにします）：

```sh
base64 -i DeveloperIDApplication.p12 | gh secret set DEVELOPER_ID_APPLICATION_P12 --repo <owner>/azooKey-Desktop
base64 -i DeveloperIDInstaller.p12 | gh secret set DEVELOPER_ID_INSTALLER_P12 --repo <owner>/azooKey-Desktop
gh secret set P12_PASSWORD --repo <owner>/azooKey-Desktop
base64 -i azooKey_Developer_ID.provisionprofile | gh secret set PROVISIONING_PROFILE --repo <owner>/azooKey-Desktop
gh secret set NOTARY_KEY_P8 --repo <owner>/azooKey-Desktop < AuthKey_XXXXXXXXXX.p8
gh secret set NOTARY_KEY_ID --repo <owner>/azooKey-Desktop
gh secret set NOTARY_ISSUER_ID --repo <owner>/azooKey-Desktop
```

`gh secret set` に値を渡さないと、その場で入力を求められます。

## 手元で試す

開発用の証明書とプロファイルでも、署名と pkg づくりまでは試せます。公証と pkg の署名は、環境変数がなければ飛ばします。

```sh
BUILD_NUMBER=2 \
PROVISIONING_PROFILE=~/Library/Input\ Methods/azooKeyMac.app/Contents/embedded.provisionprofile \
APP_SIGN_IDENTITY="Apple Development" \
./Tools/release_package.sh
```

できたアプリは `build/release/root/azooKeyMac.app`、pkg は `build/azooKey-1.0.2.pkg` です。
