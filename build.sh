#!/bin/zsh
# Builds Drift.app (universal: Apple silicon + Intel), packages Drift.dmg + Drift.zip, and launches it.
# Usage: ./build.sh            build + launch
#        ./build.sh --no-run   build only
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0"
APP="build/Drift.app"
rm -rf build/Drift.app build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

# --- compile both architectures, then merge ---
for ARCH in arm64 x86_64; do
  swiftc -O -enforce-exclusivity=unchecked -swift-version 5 -target "$ARCH-apple-macos14.0" \
    -framework Cocoa -framework QuartzCore -framework ServiceManagement -framework SwiftUI \
    Sources/*.swift -o "build/obj/Drift-$ARCH"
done
lipo -create build/obj/Drift-arm64 build/obj/Drift-x86_64 -output "$APP/Contents/MacOS/Drift"

# --- icon ---
if [[ ! -f build/AppIcon.icns || tools/make_icon.swift -nt build/AppIcon.icns ]]; then
  swift tools/make_icon.swift build/icon_1024.png
  ICONSET=build/AppIcon.iconset; rm -rf $ICONSET; mkdir -p $ICONSET
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon_1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Drift</string>
  <key>CFBundleDisplayName</key><string>Drift</string>
  <key>CFBundleIdentifier</key><string>com.camerongroff.drift</string>
  <key>CFBundleExecutable</key><string>Drift</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Drift — weather for your desktop</string>
</dict>
</plist>
PLIST

# Sign with a stable identity when available so the Accessibility grant survives rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[[ -z "$IDENTITY" ]] && IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --options runtime --timestamp=none --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "Signed with: ${IDENTITY:-ad-hoc}"

# --- share packages ---
rm -f build/Drift.zip build/Drift.dmg
ditto -c -k --keepParent "$APP" build/Drift.zip
STAGE=build/dmg; rm -rf $STAGE; mkdir -p $STAGE
cp -R "$APP" $STAGE/
ln -s /Applications $STAGE/Applications
hdiutil create -volname "Drift" -srcfolder $STAGE -ov -format UDZO build/Drift.dmg >/dev/null
rm -rf $STAGE
echo "Built $PWD/$APP"
echo "Packages: $PWD/build/Drift.dmg  $PWD/build/Drift.zip"

if [[ "${1:-}" != "--no-run" ]]; then
  pkill -x Drift 2>/dev/null || true
  open "$APP"
fi
