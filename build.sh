#!/bin/sh
# Builds build/p-timer-mac.app (universal arm64 + x86_64) and build/p-timer-mac.dmg.
set -eu
cd "$(dirname "$0")"

APP=build/p-timer-mac.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -o "build/p-timer-mac-$arch" Sources/main.swift
done
lipo -create build/p-timer-mac-arm64 build/p-timer-mac-x86_64 -output "$APP/Contents/MacOS/p-timer-mac"
rm build/p-timer-mac-arm64 build/p-timer-mac-x86_64
strip -x "$APP/Contents/MacOS/p-timer-mac"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

mkdir build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname p-timer-mac -srcfolder build/dmg -format ULMO -ov build/p-timer-mac.dmg
rm -rf build/dmg

ls -lh build/p-timer-mac.dmg
du -sh "$APP"
