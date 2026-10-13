#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--native" ) ]]; then
  echo "Usage: bash scripts/test_macos.sh [--native]" >&2
  exit 1
fi
mkdir -p .build/tests .build/swift-module-cache
swiftc -O -module-cache-path .build/swift-module-cache \
  Sources/WheelMath.swift Tests/CoreTests.swift -o .build/tests/core-tests
.build/tests/core-tests
swiftc -O -module-cache-path .build/swift-module-cache -framework AppKit \
  Sources/TextInputFocus.swift Tests/TextInputFocusTests.swift -o .build/tests/focus-tests
.build/tests/focus-tests

if [[ "${1:-}" == "--native" ]]; then
  EMOTE_TEST_APP=".build/tests/EmoteWheelTest.app"
  mkdir -p "$EMOTE_TEST_APP/Contents/MacOS" "$EMOTE_TEST_APP/Contents/Resources"
  swiftc -O -swift-version 5 -module-cache-path .build/swift-module-cache \
    -framework AppKit -framework SwiftUI -framework QuartzCore \
    Sources/WheelMath.swift Sources/AppModel.swift Sources/Overlay.swift \
    Sources/KeyboardController.swift Sources/TextInputFocus.swift Tests/NativeSmokeTests.swift \
    -o "$EMOTE_TEST_APP/Contents/MacOS/EmoteWheelTest"
  rm -rf "$EMOTE_TEST_APP/Contents/Resources/emotes"
  cp Resources/*.json "$EMOTE_TEST_APP/Contents/Resources/"
  cp -R Resources/starter-emotes "$EMOTE_TEST_APP/Contents/Resources/emotes"
  cat > "$EMOTE_TEST_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EmoteWheelTest</string>
<key>CFBundleIdentifier</key><string>studio.emotewheel.tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
  "$EMOTE_TEST_APP/Contents/MacOS/EmoteWheelTest"
fi
