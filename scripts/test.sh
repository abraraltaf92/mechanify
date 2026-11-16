#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode),
# SwiftPM doesn't find the Swift Testing macro plugin on its own, so point at it.
set -euo pipefail
cd "$(dirname "$0")/.."
plugins="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$plugins" ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
