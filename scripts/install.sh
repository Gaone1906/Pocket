#!/bin/zsh
set -euo pipefail
root=${0:A:h:h}
app="${POCKET_APP_DIR:-$HOME/Applications}/Pocket.app"
identity="${POCKET_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ { print $2; exit }')}"
identity="${identity:--}"
cd "$root"
echo "building pocket"
swift build -c release
bin="$(swift build -c release --show-bin-path)/Pocket"
pkill -x Pocket 2>/dev/null && sleep 1 || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Pocket"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :PocketSource string $root" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :PocketCommit string $(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)" "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
codesign --force --sign "$identity" "$app"
echo "installed $app (signed with ${identity/-/ad-hoc signature})"
[[ "${POCKET_NO_OPEN:-0}" == 1 ]] || open "$app"
