#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

EMOTE_ARCH="${ARCH:-$(uname -m)}"
EMOTE_OUTPUT="${OUTPUT_DIR:-dist}"
EMOTE_SIGNING="${SIGNING_IDENTITY:--}"
EMOTE_APP="$EMOTE_OUTPUT/EmoteWheel.app"
case "$EMOTE_ARCH" in
  arm64|x86_64) ;;
  *) echo "ARCH must be arm64 or x86_64" >&2; exit 1 ;;
esac

python3 scripts/download_emotes.py --verify-only
mkdir -p "$EMOTE_APP/Contents/MacOS" "$EMOTE_APP/Contents/Resources" .build/swift-module-cache
swiftc -O -swift-version 5 -target "$EMOTE_ARCH-apple-macosx13.0" \
  -module-cache-path .build/swift-module-cache \
  -framework AppKit -framework SwiftUI -framework QuartzCore \
  Sources/*.swift -o "$EMOTE_APP/Contents/MacOS/EmoteWheel"
cp -R Resources/. "$EMOTE_APP/Contents/Resources/"
cp Info.plist "$EMOTE_APP/Contents/Info.plist"
if [[ "$EMOTE_SIGNING" == "-" ]]; then
  codesign --force --sign - --identifier studio.emotewheel.desktop "$EMOTE_APP"
else
  codesign --force --sign "$EMOTE_SIGNING" --options runtime --timestamp \
    --identifier studio.emotewheel.desktop "$EMOTE_APP"
fi
codesign --verify --strict "$EMOTE_APP"
echo "Built: $EMOTE_APP ($EMOTE_ARCH)"
