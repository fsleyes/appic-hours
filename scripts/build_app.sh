#!/bin/zsh
# Builds "APPIC Hours.app" in this folder (no Xcode needed — Command Line Tools only).
#   ./scripts/build_app.sh            build only
#   ./scripts/build_app.sh --install  build, then copy it into /Applications (replacing any
#                                     existing "APPIC Hours.app" there; your data is not touched)
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
APP="$HERE/APPIC Hours.app"
BUILD="$HERE/.build"

echo "→ Compiling (release)…"
swift build -c release --product APPICHours

echo "→ Rendering icon…"
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make_icon.swift "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "→ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/release/APPICHours" "$APP/Contents/MacOS/APPIC Hours"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>APPIC Hours</string>
  <key>CFBundleDisplayName</key><string>APPIC Hours</string>
  <key>CFBundleIdentifier</key><string>local.appic-hours</string>
  <key>CFBundleExecutable</key><string>APPIC Hours</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Personal use</string>
  <key>ProjectDirectory</key><string>$HERE</string>
</dict>
</plist>
PLIST

echo "→ Signing (ad hoc)…"
/usr/bin/codesign --force --sign - "$APP"

echo "✓ Built $APP"

if [[ "$1" != "--install" ]]; then
  echo "  Double-click it to run, or re-run with --install to copy it into /Applications."
  exit 0
fi

DEST="/Applications/APPIC Hours.app"
echo "→ Installing to /Applications…"
STAGE="/Applications/.APPIC Hours.app.new"
rm -rf "$STAGE"
ditto "$APP" "$STAGE"
rm -rf "$DEST"
mv "$STAGE" "$DEST"
echo "✓ Installed $DEST"
if pgrep -f "APPIC Hours.app/Contents/MacOS/" > /dev/null; then
  echo "  APPIC Hours is open — quit it and reopen it from Applications to use the new version."
fi
