#!/bin/bash
# Build, Developer ID-sign, notarize, and staple Masque, producing a distributable
# build/Masque.zip and printing its sha256 (for the Homebrew cask).
#
# Prereqs (one-time):
#   - A "Developer ID Application" certificate in your keychain.
#   - Notarization credentials: a stored notarytool keychain profile, or an
#     App Store Connect API key (.p8 + key id + issuer id).
#
# Usage (keychain profile — recommended):
#   xcrun notarytool store-credentials masque-notary \
#       --key ~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 \
#       --key-id XXXX --issuer <issuer-uuid>          # one-time
#   NOTARY_PROFILE=masque-notary tools/build_macos_notarized.sh
#
# Usage (API key directly):
#   ASC_KEY_ID=XXXX ASC_ISSUER_ID=<uuid> \
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 \
#   tools/build_macos_notarized.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO/macos"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

echo "==> Generating project…"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate >/dev/null

echo "==> Archiving (Release, hardened runtime)…"
rm -rf build
xcodebuild -project Masque.xcodeproj -scheme Masque -configuration Release \
  -archivePath build/Masque.xcarchive archive \
  ENABLE_HARDENED_RUNTIME=YES >/dev/null

echo "==> Exporting with Developer ID…"
xcodebuild -exportArchive \
  -archivePath build/Masque.xcarchive \
  -exportOptionsPlist ci/ExportOptions-DeveloperID.plist \
  -exportPath build/export >/dev/null

APP="build/export/Masque.app"
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="build/Masque.zip"; rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarizing (waits for Apple)…"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
else
  : "${ASC_KEY_ID:?set NOTARY_PROFILE, or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
  : "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
  xcrun notarytool submit "$ZIP" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
fi

echo "==> Stapling…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Done: $REPO/macos/$ZIP"
echo "    sha256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
