#!/bin/bash
set -euo pipefail

APP_NAME="StudioSwitch"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

swift build -c release --product StudioSwitchApp

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
cp "${BUILD_DIR}/StudioSwitchApp" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp -R Resources/DAWIcons "${APP_BUNDLE}/Contents/Resources/"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.simonrenard.studioswitch</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>StudioSwitch lit le titre de la fenêtre de UAD Console pour savoir quelle session est ouverte.</string>
</dict>
</plist>
PLIST

# Sign with the local "StudioSwitch Dev" certificate when it's in the keychain: macOS then ties the
# Accessibility permission to that certificate, so it survives rebuilds. Ad-hoc signing ("-")
# gives every build a new identity and the permission silently stops working after each one.
SIGNING_IDENTITY="${STUDIOSWITCH_SIGNING_IDENTITY:-StudioSwitch Dev}"
if security find-identity -v -p codesigning | grep -q "\"${SIGNING_IDENTITY}\""; then
    codesign --force --deep --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
    echo "Signed with \"${SIGNING_IDENTITY}\"."
else
    codesign --force --deep --sign - "${APP_BUNDLE}"
    echo "Signing identity \"${SIGNING_IDENTITY}\" not found: ad-hoc signed (Accessibility will need re-granting after this build)."
fi

echo "Built ${APP_BUNDLE}. Move it to /Applications and add it to Login Items to run it automatically."
