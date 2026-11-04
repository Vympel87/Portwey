#!/bin/bash
# Builds Portwey in Release mode, signs it ad-hoc (no Apple Developer account needed)
# and packages it as dist/Portwey-<version>.dmg.
set -euo pipefail

cd "$(dirname "$0")/.."

# Read the app version (MARKETING_VERSION). awk reads everything instead of stopping early,
# so xcodebuild isn't cut off mid-output (which made the script quit silently).
VERSION=$(xcodebuild -project Portwey.xcodeproj -scheme Portwey -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION / && !found { print $3; found = 1 }') || true
VERSION="${VERSION:-0.0.0}"

BUILD_DIR="build"
APP="${BUILD_DIR}/Build/Products/Release/Portwey.app"
STAGING="dist/staging"
DMG="dist/Portwey-${VERSION}.dmg"

echo "==> Building Portwey ${VERSION}..."
rm -rf "${BUILD_DIR}" "${STAGING}"
mkdir -p "${STAGING}"

xcodebuild \
  -project Portwey.xcodeproj \
  -scheme Portwey \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build > "${BUILD_DIR}.log" 2>&1 || { echo "Build failed, see ${BUILD_DIR}.log"; tail -n 20 "${BUILD_DIR}.log"; exit 1; }

if [ ! -d "${APP}" ]; then
  echo "Build finished but ${APP} wasn't found"
  exit 1
fi

echo "==> Signing (ad-hoc)..."
codesign --force --deep --sign - "${APP}"

echo "==> Packaging DMG..."
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

cat > "${STAGING}/How to open Portwey.txt" <<'EOF'
How to open Portwey for the first time
======================================

1. Drag Portwey into the Applications folder.
2. Open Portwey from Applications. macOS says it can't verify the app. Click "Done".
3. Open System Settings > Privacy & Security.
4. Scroll down to the message about Portwey and click "Open Anyway".
5. Confirm with your Mac password, then click "Open".

You only need to do this once. After that, Portwey opens normally.

Why? Portwey is made by an independent developer and isn't notarized by Apple.
EOF

rm -f "${DMG}"
hdiutil create -volname "Portwey ${VERSION}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG}" > /dev/null
rm -rf "${STAGING}"

echo "==> Done: ${DMG}"