#!/usr/bin/env bash
# Builds a release binary and wraps it into build/Keyboard Sounds.app.
#   --install   also copy the app to ~/Applications (recommended for launch at login)
set -euo pipefail
cd "$(dirname "$0")/.."

name="Keyboard Sounds"
bundle_id="local.keyboardsounds"
version="1.0.0"
app="build/$name.app"

swift build -c release
bin="$(swift build -c release --show-bin-path)/KeyboardSounds"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/KeyboardSounds"
cp -R Resources/Profiles "$app/Contents/Resources/Profiles"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>KeyboardSounds</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature (no developer certificate needed). macOS ties the Input
# Monitoring grant to the signature, so after a rebuild you may need to toggle
# the app off and on again in System Settings.
codesign --force --sign - --identifier "$bundle_id" "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$name.app"
  cp -R "$app" "$HOME/Applications/"
  echo "Installed to ~/Applications/$name.app"
fi
