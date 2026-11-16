#!/usr/bin/env bash
# Builds Resources/Icon/AppIcon.icns from Resources/Icon/AppIcon-1024.png.
# The artwork is full bleed on purpose: macOS 26 and later apply their own rounded shape.
set -euo pipefail
cd "$(dirname "$0")/.."

src="Resources/Icon/AppIcon-1024.png"
set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir"
trap 'rm -rf "$(dirname "$set_dir")"' EXIT

for size in 16 32 128 256 512; do
  sips -z $size $size "$src" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$src" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/Icon/AppIcon.icns
echo "Wrote Resources/Icon/AppIcon.icns"
