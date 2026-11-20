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
mkdir -p "$app/Contents/Resources"
cp -R "$root/Resources/Embroidery" "$app/Contents/Resources/Embroidery"
codesign --force --sign "$identity" "$app"
echo "installed $app (signed with ${identity/-/ad-hoc signature})"
[[ "${POCKET_NO_OPEN:-0}" == 1 ]] && exit 0
open "$app"
for _ in {1..20}; do
  sleep 0.5
  for pid in $(pgrep -x Pocket || true); do
    if [[ "$(ps -o stat= -p $pid | tr -d ' ')" == T* ]]; then
      kill -CONT $pid
      echo "resumed pocket pid $pid, which launched stopped"
    fi
  done
done
