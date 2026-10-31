#!/bin/bash
# 開発用：sudo を使わずに ~/Library/Input Methods へ入れ直す。
# /Library/Input Methods に同じアプリがあると、どちらが使われるか定まらないので、先に sudo で消しておくこと。
set -xe -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_IM_DIR="${HOME}/Library/Input Methods"
APP_NAME="azooKeyMac.app"

if [ -e "/Library/Input Methods/${APP_NAME}" ]; then
    echo "/Library/Input Methods/${APP_NAME} が残っています。先に次を実行してください：" >&2
    echo "  sudo rm -rf '/Library/Input Methods/${APP_NAME}'" >&2
    exit 1
fi

cd "${REPO_ROOT}"
swiftlint --fix --format
swiftlint --quiet --strict
xcodebuild -project azooKeyMac.xcodeproj -scheme azooKeyMac -quiet clean archive -archivePath build/archive.xcarchive

mkdir -p "${USER_IM_DIR}"
rm -rf "${USER_IM_DIR:?}/${APP_NAME}"
cp -R "build/archive.xcarchive/Products/Applications/${APP_NAME}" "${USER_IM_DIR}/"
pkill -x azooKeyMac || true
