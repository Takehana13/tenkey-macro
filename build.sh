#!/bin/bash
# テンキーマクロ.app をビルドして build/ に作る
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/TenkeyMacro.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TenkeyMacro "$APP/Contents/MacOS/TenkeyMacro"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "OK: $(pwd)/$APP"
