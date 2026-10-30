#!/bin/zsh
# Builds an unsigned device IPA for FlareStore / AltStore / SideStore.
# Testers re-sign it with their own Apple ID inside FlareStore.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen is required. brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

mkdir -p "$ROOT/build"
rm -rf "$ROOT/build/Gymship.xcarchive" "$ROOT/build/Payload"

xcodebuild \
  -project Gymship.xcodeproj \
  -scheme Gymship \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ROOT/build/Gymship.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

APP="$ROOT/build/Gymship.xcarchive/Products/Applications/Gymship.app"
if [[ ! -d "$APP" ]]; then
  echo "Archive did not produce Gymship.app" >&2
  exit 1
fi

mkdir -p "$ROOT/build/Payload"
cp -R "$APP" "$ROOT/build/Payload/Gymship.app"
rm -rf "$ROOT/build/Payload/Gymship.app/_CodeSignature"
rm -f "$ROOT/build/Payload/Gymship.app/embedded.mobileprovision"

IPA="$ROOT/build/Gymship.ipa"
rm -f "$IPA"
(
  cd "$ROOT/build"
  zip -qr Gymship.ipa Payload
)

echo "Wrote $IPA ($(du -h "$IPA" | awk '{print $1}'))"
