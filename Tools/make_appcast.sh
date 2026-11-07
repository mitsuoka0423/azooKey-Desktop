#!/bin/bash
# Sparkle の appcast.xml を作る（CI のリリースと手元の確認で使う）。
# 最新の版 1 つだけを載せる。フィードは GitHub Releases の最新（releases/latest/download/appcast.xml）から読むので、
# 古い版を載せなくても、どの版からでも最新に上がれる。
#
# EdDSA の秘密鍵は標準入力から受け取る（ファイルにも引数にも置かない）：
#   echo "$SPARKLE_ED_PRIVATE_KEY" | Tools/make_appcast.sh
#
# 環境変数：
#   ZIP_PATH             必須。release_package.sh が作った .app の zip
#   DOWNLOAD_URL         必須。zip をダウンロードする URL
#   BUILD_NUMBER         必須。CFBundleVersion（Sparkle はこれで新旧を比べる）
#   MARKETING_VERSION    表示用の版（既定は 1.0.<BUILD_NUMBER>）
#   RELEASE_NOTES_URL    リリースノートのページ（任意）
#   MINIMUM_SYSTEM_VERSION
#                        動く macOS の下限（既定は 13.0）
#   OUTPUT_APPCAST       できあがる appcast の場所（既定は build/appcast.xml）
#   SPARKLE_BIN          sign_update のあるフォルダ（既定は release_package.sh が取ってきた Sparkle の bin）
set -euo pipefail

: "${ZIP_PATH:?ZIP_PATH を指定してください}"
: "${DOWNLOAD_URL:?DOWNLOAD_URL を指定してください}"
: "${BUILD_NUMBER:?BUILD_NUMBER を指定してください}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.${BUILD_NUMBER}}"
RELEASE_NOTES_URL="${RELEASE_NOTES_URL:-}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-13.0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_APPCAST="${OUTPUT_APPCAST:-${REPO_ROOT}/build/appcast.xml}"
SPARKLE_BIN="${SPARKLE_BIN:-${REPO_ROOT}/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"

if [ ! -x "${SPARKLE_BIN}/sign_update" ]; then
    echo "${SPARKLE_BIN}/sign_update がありません。先に release_package.sh を実行するか、SPARKLE_BIN を指定してください" >&2
    exit 1
fi
if [ -t 0 ]; then
    echo "秘密鍵を標準入力から渡してください（例：echo \"\$SPARKLE_ED_PRIVATE_KEY\" | $0）" >&2
    exit 1
fi

# 署名と長さ（sparkle:edSignature="..." length="..."）。秘密鍵は標準入力のまま sign_update に渡す
SIGNATURE_ATTRIBUTES="$("${SPARKLE_BIN}/sign_update" --ed-key-file - "${ZIP_PATH}")"
if ! [[ "${SIGNATURE_ATTRIBUTES}" =~ ^sparkle:edSignature=\"[A-Za-z0-9+/=]+\"\ length=\"[0-9]+\"$ ]]; then
    echo "sign_update の出力が思った形ではありません" >&2
    exit 1
fi

escape_xml() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<<"$1"
}

PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
RELEASE_NOTES_ELEMENT=""
if [ -n "${RELEASE_NOTES_URL}" ]; then
    RELEASE_NOTES_ELEMENT="            <sparkle:fullReleaseNotesLink>$(escape_xml "${RELEASE_NOTES_URL}")</sparkle:fullReleaseNotesLink>
            <description sparkle:format=\"plain-text\">変更点は GitHub のリリースのページを見てください：$(escape_xml "${RELEASE_NOTES_URL}")</description>"
fi

mkdir -p "$(dirname "${OUTPUT_APPCAST}")"
cat > "${OUTPUT_APPCAST}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>azooKey</title>
        <item>
            <title>azooKey $(escape_xml "${MARKETING_VERSION}")</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>$(escape_xml "${BUILD_NUMBER}")</sparkle:version>
            <sparkle:shortVersionString>$(escape_xml "${MARKETING_VERSION}")</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$(escape_xml "${MINIMUM_SYSTEM_VERSION}")</sparkle:minimumSystemVersion>
${RELEASE_NOTES_ELEMENT}
            <enclosure url="$(escape_xml "${DOWNLOAD_URL}")" type="application/octet-stream" ${SIGNATURE_ATTRIBUTES}/>
        </item>
    </channel>
</rss>
EOF
xmllint --noout "${OUTPUT_APPCAST}"
echo "できあがり：${OUTPUT_APPCAST}"
