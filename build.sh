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

# Copy bundled resources (Claude logo)
if [ -f "ClaudeUsageWidget/Resources/claude-logo.png" ]; then
  cp "ClaudeUsageWidget/Resources/claude-logo.png" "${RESOURCES_PATH}/"
fi

# Generate the app/dock icon (.icns) from the Claude logo via sips upscaling.
LOGO="ClaudeUsageWidget/Resources/claude-logo.png"
if [ -f "${LOGO}" ]; then
  ICONSET_PATH="/tmp/ClaudeAppIcon.iconset"
  rm -rf "${ICONSET_PATH}"; mkdir -p "${ICONSET_PATH}"
  for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
              "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
              "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "${px}" "${px}" "${LOGO}" --out "${ICONSET_PATH}/${name}.png" >/dev/null 2>&1
  done
  iconutil -c icns "${ICONSET_PATH}" -o "${RESOURCES_PATH}/AppIcon.icns" 2>/dev/null
  rm -rf "${ICONSET_PATH}"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS_PATH}/Info.plist" 2>/dev/null || true
fi

echo "Built app bundle at: ${APP_PATH}"
echo "To run: open '${APP_PATH}'"
echo "To install: cp -R '${APP_PATH}' /Applications/"
