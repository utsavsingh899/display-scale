#!/bin/bash
# Build Display Scale and the res command, then make the release zip.
#   ./build.sh          build into build/ and make dist/display-scale-<version>.zip
#   ./build.sh bench    also build the optional benchmark tools in bench/
# Needs an Apple silicon Mac with the Xcode Command Line Tools (xcode-select --install).
set -euo pipefail

cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" app/Info.plist)
BUILD=build
APP="$BUILD/Display Scale.app"
PKG="$BUILD/display-scale"

rm -rf "$BUILD" dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PKG" dist

# The command line tool.
swiftc -O -target arm64-apple-macos11 cli/displaymode.swift -o "$BUILD/displaymode"

# The app.
swiftc -O -target arm64-apple-macos13 app/Sources/*.swift -o "$APP/Contents/MacOS/DisplayScale"
cp app/Info.plist "$APP/Contents/Info.plist"

# The app icon at all icon sizes. app/icon/laptop.png is 1024 x 1024 and has its margin already.
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" app/icon/laptop.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) app/icon/laptop.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

# The release zip.
ditto "$APP" "$PKG/Display Scale.app"
cp cli/res install.sh README.md LICENSE NOTICE.md "$BUILD/displaymode" "$PKG/"
chmod +x "$PKG/res" "$PKG/displaymode" "$PKG/install.sh"
ditto -c -k --norsrc --noextattr --keepParent "$PKG" "dist/display-scale-$VERSION.zip"
echo "Built dist/display-scale-$VERSION.zip"

if [[ ${1:-} == bench ]]; then
  for tool in powermeter screenload gpuburn; do
    swiftc -O "bench/$tool.swift" -o "bench/$tool"
  done
  echo "Built the benchmark tools in bench/"
fi
