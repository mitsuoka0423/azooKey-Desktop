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

# アプリを消して置き直すと OS の入力ソースの登録が外れるので、場所はそのままで中身だけ入れ替える
mkdir -p "${USER_IM_DIR}/${APP_NAME}"
rsync -a --delete "build/archive.xcarchive/Products/Applications/${APP_NAME}/" "${USER_IM_DIR}/${APP_NAME}/"
pkill -x azooKeyMac || true
swift "${REPO_ROOT}/Tools/register_input_source.swift" "${USER_IM_DIR}/${APP_NAME}"
