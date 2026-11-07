#!/bin/bash
# 配布用の pkg を作る（CI のリリースと手元の確認で使う）。
# Xcode の自動署名を使わず、署名なしで archive してから codesign で署名する。
# CI に開発用の証明書を置かずに、Developer ID だけで署名するため。
#
# 環境変数：
#   BUILD_NUMBER         必須。CFBundleVersion と pkg のバージョンになる
#   PROVISIONING_PROFILE 必須。App Group を使うので、アプリに入れるプロファイルが要る
#   APP_SIGN_IDENTITY    アプリの署名に使う ID（既定は "Developer ID Application"）
#   MARKETING_VERSION    CFBundleShortVersionString（既定は 1.0.<BUILD_NUMBER>）
#   PKG_SIGN_IDENTITY    pkg の署名に使う ID（例："Developer ID Installer"）。空なら署名しない
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                        App Store Connect API キー。どれかが空なら公証しない
#   OUTPUT_PKG           できあがる pkg の場所（既定は build/azooKey-<MARKETING_VERSION>.pkg）
#   OUTPUT_ZIP           Sparkle で配る .app の zip の場所（既定は build/azooKeyMac-<MARKETING_VERSION>.zip）
#   SPARKLE_PUBLIC_ED_KEY
#                        Sparkle の公開鍵（Info.plist の SUPublicEDKey）。空なら、アプリの中からの更新は動かない
#   SPARKLE_FEED_URL     appcast の URL。空ならプロジェクトの既定（GitHub Releases の最新）を使う
set -euo pipefail

: "${BUILD_NUMBER:?BUILD_NUMBER を指定してください}"
: "${PROVISIONING_PROFILE:?PROVISIONING_PROFILE を指定してください}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-Developer ID Application}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.${BUILD_NUMBER}}"
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
BUILD_DIR="${REPO_ROOT}/build/release"
OUTPUT_PKG="${OUTPUT_PKG:-${REPO_ROOT}/build/azooKey-${MARKETING_VERSION}.pkg}"
OUTPUT_ZIP="${OUTPUT_ZIP:-${REPO_ROOT}/build/azooKeyMac-${MARKETING_VERSION}.zip}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
# Sparkle の sign_update などを make_appcast.sh から使えるよう、パッケージの置き場所を決めておく
SOURCE_PACKAGES_DIR="${REPO_ROOT}/build/SourcePackages"
ARCHIVE_PATH="${BUILD_DIR}/archive.xcarchive"
ROOT_DIR="${BUILD_DIR}/root"
APP_PATH="${ROOT_DIR}/azooKeyMac.app"

# 公証してチケットを付ける。API キーがなければ飛ばす
notarize_and_staple() {
    if [ -z "${NOTARY_KEY_PATH}" ] || [ -z "${NOTARY_KEY_ID}" ] || [ -z "${NOTARY_ISSUER_ID}" ]; then
        echo "API キーがないので公証を飛ばします：$1"
        return
    fi
    xcrun notarytool submit "$1" --key "${NOTARY_KEY_PATH}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID}" --wait
    xcrun stapler staple "$2"
}

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${ROOT_DIR}"

# 1. 署名なしで archive する
SPARKLE_SETTINGS=("SPARKLE_PUBLIC_ED_KEY=${SPARKLE_PUBLIC_ED_KEY}")
if [ -n "${SPARKLE_FEED_URL}" ]; then
    SPARKLE_SETTINGS+=("SPARKLE_FEED_URL=${SPARKLE_FEED_URL}")
fi
if [ -z "${SPARKLE_PUBLIC_ED_KEY}" ]; then
    echo "SPARKLE_PUBLIC_ED_KEY がないので、アプリの中からの更新は動きません"
fi
xcodebuild \
    -project azooKeyMac.xcodeproj \
    -scheme azooKeyMac \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}" \
    -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_DIR}" \
    -quiet \
    clean archive \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="${MARKETING_VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    "${SPARKLE_SETTINGS[@]}"
ditto "${ARCHIVE_PATH}/Products/Applications/azooKeyMac.app" "${APP_PATH}"

# 2. entitlements を組み立てる（Xcode が署名のときに足すものも足す）
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "${APP_PATH}/Contents/Info.plist")"
security cms -D -i "${PROVISIONING_PROFILE}" > "${BUILD_DIR}/profile.plist"
TEAM_ID="$(/usr/libexec/PlistBuddy -c "Print TeamIdentifier:0" "${BUILD_DIR}/profile.plist")"
ENTITLEMENTS="${BUILD_DIR}/azooKeyMac.entitlements"
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" azooKeyMac/azooKeyMac.entitlements > "${ENTITLEMENTS}"
/usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string ${TEAM_ID}.${BUNDLE_ID}" \
    -c "Add :com.apple.developer.team-identifier string ${TEAM_ID}" \
    -c "Add :com.apple.security.files.user-selected.read-only bool true" \
    "${ENTITLEMENTS}"

# 3. 内側から署名する
cp "${PROVISIONING_PROFILE}" "${APP_PATH}/Contents/embedded.provisionprofile"
# Sparkle は中の部品から順に署名する（--deep は使わない）。
# ネットワークの権限があるので、Downloader の XPC サービスは使わずに外す
SPARKLE_DIR="${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ -d "${SPARKLE_DIR}" ]; then
    rm -rf "${SPARKLE_DIR}/XPCServices/Downloader.xpc"
    for item in "XPCServices/Installer.xpc" "Autoupdate" "Updater.app"; do
        codesign --force --options runtime --timestamp --sign "${APP_SIGN_IDENTITY}" "${SPARKLE_DIR}/${item}"
    done
fi
find "${APP_PATH}/Contents/Frameworks" -depth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 |
    while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "${APP_SIGN_IDENTITY}" "${item}"
    done
codesign --force --options runtime --timestamp --sign "${APP_SIGN_IDENTITY}" --entitlements "${ENTITLEMENTS}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

# 4. アプリを公証して、チケットを付ける
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${BUILD_DIR}/azooKeyMac.zip"
notarize_and_staple "${BUILD_DIR}/azooKeyMac.zip" "${APP_PATH}"

# 5. Sparkle で配る zip を作る（チケットを付けたあとのアプリをまとめる）
mkdir -p "$(dirname "${OUTPUT_ZIP}")"
rm -f "${OUTPUT_ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${OUTPUT_ZIP}"

# 6. pkg にまとめる。distribution.xml で入れる先をホームに限っているので、
#    install-location の /Library/Input Methods は ~/Library/Input Methods になる
mkdir -p "${BUILD_DIR}/scripts" "${BUILD_DIR}/packages"
cp pkg-scripts/postinstall "${BUILD_DIR}/scripts/"
chmod +x "${BUILD_DIR}/scripts/"*
pkgbuild \
    --root "${ROOT_DIR}" \
    --scripts "${BUILD_DIR}/scripts" \
    --component-plist pkg.plist \
    --identifier "${BUNDLE_ID}" \
    --version "${BUILD_NUMBER}" \
    --install-location "/Library/Input Methods" \
    "${BUILD_DIR}/packages/azooKey-tmp.pkg"
mkdir -p "$(dirname "${OUTPUT_PKG}")"
if [ -n "${PKG_SIGN_IDENTITY}" ]; then
    productbuild --distribution distribution.xml --package-path "${BUILD_DIR}/packages" --sign "${PKG_SIGN_IDENTITY}" --timestamp "${OUTPUT_PKG}"
else
    echo "PKG_SIGN_IDENTITY がないので pkg に署名しません"
    productbuild --distribution distribution.xml --package-path "${BUILD_DIR}/packages" "${OUTPUT_PKG}"
fi

# 7. pkg を公証して、チケットを付ける
notarize_and_staple "${OUTPUT_PKG}" "${OUTPUT_PKG}"
echo "できあがり：${OUTPUT_PKG}"
echo "できあがり：${OUTPUT_ZIP}"
