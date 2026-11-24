#!/bin/bash
# テンキーマクロ.app をビルドして /Applications に入れる
#   ./build.sh            ビルドして /Applications/TenkeyMacro.app に入れる
#   ./build.sh --no-install  build/ に作るだけ
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/TenkeyMacro.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TenkeyMacro "$APP/Contents/MacOS/TenkeyMacro"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 署名の「本人確認条件」をアプリID固定にする。
# 既定のアドホック署名だとビルドのたびに別アプリ扱いになり、アクセシビリティの許可が外れるため。
codesign --force --sign - \
  --identifier local.tenkeymacro.app \
  --requirements '=designated => identifier "local.tenkeymacro.app"' \
  "$APP"
echo "OK: $(pwd)/$APP"

if [ "${1:-}" != "--no-install" ]; then
  pkill -x TenkeyMacro 2>/dev/null && sleep 1 || true
  rm -rf /Applications/TenkeyMacro.app
  ditto "$APP" /Applications/TenkeyMacro.app
  echo "インストール: /Applications/TenkeyMacro.app"
fi
