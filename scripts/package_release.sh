#!/usr/bin/env bash
set -euo pipefail

# Translate Assist — Package Release (Build → Sign → DMG → Notarize → Staple)
#
# Prereqs:
# - Xcode 15+
# - Developer ID Application certificate installed in Keychain
# - Apple ID with app-specific password for notarytool, or a notarytool keychain profile
# - Team ID and Bundle ID configured (defaults read from project)
#
# Usage examples:
#   scripts/package_release.sh \
#     --scheme "translate assist" \
#     --config Release \
#     --team-id 597KGSTZWJ \
#     --bundle-id com.klewrsolutions.translate-assist \
#     --apple-id "your-appleid@example.com" \
#     --password "app-specific-password"
#
# Or with a notarytool profile:
#   scripts/package_release.sh --scheme "translate assist" --notary-profile "AC_NOTARY"

SCHEME="translate assist"
CONFIG="Release"
TEAM_ID=""
BUNDLE_ID=""
APPLE_ID=""
PASSWORD=""
NOTARY_PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme) SCHEME="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --apple-id) APPLE_ID="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/TranslateAssist.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
APP_NAME="translate assist"
APP_PRODUCT="$EXPORT_DIR/$APP_NAME.app"
DMG_NAME="TranslateAssist.dmg"

rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR" "$EXPORT_DIR" "$DMG_DIR"

echo "[1/6] Archive $SCHEME ($CONFIG)"
xcodebuild archive \
  -project "$ROOT_DIR/translate assist.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  ENABLE_HARDENED_RUNTIME=YES \
  DEVELOPMENT_TEAM="$TEAM_ID"

cat >"$BUILD_DIR/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
EOF

echo "[2/6] Export Developer ID–signed app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/exportOptions.plist"

echo "[3/6] Verify codesign"
codesign --verify --deep --strict --verbose=2 "$APP_PRODUCT"
spctl -a -vv "$APP_PRODUCT"

echo "[4/6] Create DMG"
STAGING="$DMG_DIR/stage"
rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R "$APP_PRODUCT" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# If create-dmg is installed, use it for a nicer DMG; otherwise fall back to hdiutil
if command -v create-dmg >/dev/null 2>&1; then
  echo "Using create-dmg for styled DMG"
  rm -f "$DMG_DIR/$DMG_NAME"
  create-dmg \
    --volname "Translate Assist" \
    --window-pos 200 120 \
    --window-size 640 400 \
    --icon-size 96 \
    --text-size 12 \
    --app-drop-link 480 200 \
    "$DMG_DIR/$DMG_NAME" \
    "$STAGING"
else
  echo "create-dmg not found; using hdiutil"
  hdiutil create -volname "Translate Assist" -srcfolder "$STAGING" -ov -format UDZO "$DMG_DIR/$DMG_NAME"
fi

echo "[5/6] Notarize DMG"
if [[ -n "$NOTARY_PROFILE" ]]; then
  # Team ID is embedded in the stored notarytool credentials; no need to pass explicitly
  xcrun notarytool submit "$DMG_DIR/$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "$APPLE_ID" && -n "$PASSWORD" && -n "$TEAM_ID" ]]; then
  xcrun notarytool submit "$DMG_DIR/$DMG_NAME" --apple-id "$APPLE_ID" --password "$PASSWORD" --team-id "$TEAM_ID" --wait
else
  echo "Provide either --notary-profile or (--apple-id, --password, --team-id) for notarization." >&2
  exit 1
fi

echo "[6/6] Staple ticket"
xcrun stapler staple "$DMG_DIR/$DMG_NAME"
echo "Done: $DMG_DIR/$DMG_NAME"


