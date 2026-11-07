#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p macos/build
xcrun clang -std=gnu11 -O1 -c macos/settings-test-support.c -o macos/build/settings-test-support.o
xcrun clang -std=gnu11 -fobjc-arc -Wall -Wextra \
    macos/settings-tests.m macos/EPMotionSettings.m macos/ElectropaintView.m \
    macos/build/settings-test-support.o \
    -framework ScreenSaver -framework Cocoa -framework Metal -framework QuartzCore -framework CoreVideo \
    -o macos/build/settings-tests
macos/build/settings-tests
