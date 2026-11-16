#!/usr/bin/env bash
# Builds a release binary and wraps it into build/Mechanify.app.
#   --install   also copy the app to ~/Applications (recommended for launch at login)
set -euo pipefail
cd "$(dirname "$0")/.."

name="Mechanify"
# Kept from the app's first name on purpose: macOS keys the Input Monitoring grant and
# saved settings to this ID (and the signing certificate), so changing it resets both.
bundle_id="local.keyboardsounds"
version="1.0.0"
app="build/$name.app"

swift build -c release
bin="$(swift build -c release --show-bin-path)/Mechanify"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Mechanify"
cp -R Resources/Profiles "$app/Contents/Resources/Profiles"
cp Resources/Icon/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>Mechanify</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# macOS ties the Input Monitoring grant to the signature. With the local identity
# from scripts/setup-signing.sh the signature stays the same across rebuilds, so the
# grant survives. Without it, fall back to ad-hoc (the grant is lost on each rebuild).
identity="Keyboard Sounds Local Signing"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
  codesign --force --sign "$identity" --identifier "$bundle_id" "$app"
else
  echo "warning: \"$identity\" not found (run scripts/setup-signing.sh); signing ad hoc" >&2
  codesign --force --sign - --identifier "$bundle_id" "$app"
fi
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$name.app"
  cp -R "$app" "$HOME/Applications/"
  echo "Installed to ~/Applications/$name.app"
fi
