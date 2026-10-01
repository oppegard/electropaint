#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="$PWD/macos/build"
source_revision=$(git rev-parse --verify HEAD 2>/dev/null || true)
if [[ "$source_revision" =~ ^[0-9a-f]{40,64}$ ]]; then
    source_revision=${source_revision:0:7}
else
    source_revision=unknown
fi
mkdir -p "$output/Electropaint.saver/Contents/MacOS" "$output/Electropaint.saver/Contents/Resources"
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun swift macos/generate-icon.swift "$output/Electropaint.iconset"
iconutil -c icns "$output/Electropaint.iconset" -o "$output/Electropaint.icns"
for arch in arm64 x86_64; do
    xcrun clang -arch "$arch" -isysroot "$sdk" -mmacosx-version-min=11.0 \
        -std=gnu11 -O2 -c macos/EPAdapter.c -o "$output/adapter-$arch.o"
    xcrun clang -arch "$arch" -isysroot "$sdk" -mmacosx-version-min=11.0 \
        -fobjc-arc -O2 -Wall -Wextra -bundle macos/ElectropaintView.m "$output/adapter-$arch.o" \
        -framework ScreenSaver -framework Cocoa -framework Metal -framework QuartzCore \
        -o "$output/saver-$arch"
    xcrun clang -arch "$arch" -isysroot "$sdk" -mmacosx-version-min=11.0 \
        -fobjc-arc -O2 -Wall -Wextra macos/Preview.m macos/ElectropaintView.m "$output/adapter-$arch.o" \
        -framework ScreenSaver -framework Cocoa -framework Metal -framework QuartzCore \
        -o "$output/preview-$arch"
done
xcrun lipo -create "$output/saver-arm64" "$output/saver-x86_64" \
    -output "$output/Electropaint.saver/Contents/MacOS/Electropaint"
cp macos/Info.plist "$output/Electropaint.saver/Contents/Info.plist"
cp macos/vendor/LICENSE.md macos/LICENSE "$output/Electropaint.saver/Contents/Resources/"
cp LICENSE "$output/Electropaint.saver/Contents/Resources/GPL-2.0.txt"
cp "$output/Electropaint.icns" "$output/Electropaint.saver/Contents/Resources/"
mkdir -p "$output/Electropaint Preview.app/Contents/MacOS"
mkdir -p "$output/Electropaint Preview.app/Contents/Resources"
cp macos/vendor/LICENSE.md macos/LICENSE "$output/Electropaint Preview.app/Contents/Resources/"
cp LICENSE "$output/Electropaint Preview.app/Contents/Resources/GPL-2.0.txt"
cp "$output/Electropaint.icns" "$output/Electropaint Preview.app/Contents/Resources/"
xcrun lipo -create "$output/preview-arm64" "$output/preview-x86_64" \
    -output "$output/Electropaint Preview.app/Contents/MacOS/Electropaint"
cp macos/Info.plist "$output/Electropaint Preview.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundlePackageType APPL' "$output/Electropaint Preview.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.oppegard.electropaint.preview' "$output/Electropaint Preview.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :NSPrincipalClass NSApplication' "$output/Electropaint Preview.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :ElectropaintGitRevision string $source_revision" "$output/Electropaint Preview.app/Contents/Info.plist"
codesign --force --sign - "$output/Electropaint.saver"
codesign --force --sign - "$output/Electropaint Preview.app"
plutil -lint "$output/Electropaint.saver/Contents/Info.plist"
codesign --verify --strict "$output/Electropaint.saver"
printf 'Built %s\n' "$output/Electropaint.saver"
