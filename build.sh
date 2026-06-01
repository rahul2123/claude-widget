#!/bin/bash

set -e

BINARY_NAME="ClaudeUsageWidget"
APP_DISPLAY_NAME="Claude Usage Monitor"
APP_PATH="build/${APP_DISPLAY_NAME}.app"
CONTENTS_PATH="${APP_PATH}/Contents"
MACOS_PATH="${CONTENTS_PATH}/MacOS"
RESOURCES_PATH="${CONTENTS_PATH}/Resources"

rm -rf "${APP_PATH}"
mkdir -p "${MACOS_PATH}"
mkdir -p "${RESOURCES_PATH}"

# Copy executable
cp "bin/${BINARY_NAME}" "${MACOS_PATH}/"

# Copy Info.plist
cp "ClaudeUsageWidget/Info.plist" "${CONTENTS_PATH}/"

# Build .icns from PNGs if an icon set is present (optional — falls back to default icon)
ICONS_DIR="ClaudeUsageWidget/Assets.xcassets/AppIcon.appiconset"
if [ -f "${ICONS_DIR}/app-icon-512.png" ]; then
  ICONSET_PATH="/tmp/ClaudeAppIcon.iconset"
  rm -rf "${ICONSET_PATH}"
  mkdir -p "${ICONSET_PATH}"
  cp "${ICONS_DIR}/app-icon-16.png"   "${ICONSET_PATH}/icon_16x16.png"
  cp "${ICONS_DIR}/app-icon-32.png"   "${ICONSET_PATH}/icon_16x16@2x.png"
  cp "${ICONS_DIR}/app-icon-32.png"   "${ICONSET_PATH}/icon_32x32.png"
  cp "${ICONS_DIR}/app-icon-64.png"   "${ICONSET_PATH}/icon_32x32@2x.png"
  cp "${ICONS_DIR}/app-icon-128.png"  "${ICONSET_PATH}/icon_128x128.png"
  cp "${ICONS_DIR}/app-icon-256.png"  "${ICONSET_PATH}/icon_128x128@2x.png"
  cp "${ICONS_DIR}/app-icon-256.png"  "${ICONSET_PATH}/icon_256x256.png"
  cp "${ICONS_DIR}/app-icon-512.png"  "${ICONSET_PATH}/icon_256x256@2x.png"
  cp "${ICONS_DIR}/app-icon-512.png"  "${ICONSET_PATH}/icon_512x512.png"
  cp "${ICONS_DIR}/app-icon-1024.png" "${ICONSET_PATH}/icon_512x512@2x.png"
  iconutil -c icns "${ICONSET_PATH}" -o "${RESOURCES_PATH}/AppIcon.icns"
  rm -rf "${ICONSET_PATH}"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS_PATH}/Info.plist" 2>/dev/null || true
fi

echo "Built app bundle at: ${APP_PATH}"
echo "To run: open '${APP_PATH}'"
echo "To install: cp -R '${APP_PATH}' /Applications/"
