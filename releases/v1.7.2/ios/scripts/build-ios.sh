#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS App 必須在安裝 Xcode 的 macOS 上編譯。此腳本不產生假的 IPA。' >&2
  exit 1
fi
cd "$project_root"
xcodebuild -project ETFToGo.xcodeproj -scheme ETFToGo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ETFToGo.xcodeproj -scheme ETFToGo -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
printf '%s\n' '模擬器與未簽署裝置編譯完成；真機安裝請在 Xcode 設定 Apple Team 並簽署。'
