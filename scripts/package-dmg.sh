#!/usr/bin/env bash
# Builds the app and packages it as dist/Mechanify-<version>.dmg
# (the app plus an Applications shortcut, so people can drag to install).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Mechanify.app/Contents/Info.plist)"
dmg="dist/Mechanify-$version.dmg"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R build/Mechanify.app "$stage/"
ln -s /Applications "$stage/Applications"

mkdir -p dist
rm -f "$dmg"
hdiutil create -volname "Mechanify" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
shasum -a 256 "$dmg" | tee "$dmg.sha256"
echo "Packaged $dmg"
