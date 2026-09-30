#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun clang -fobjc-arc -Wall -Wextra macos/smoke-tests.m \
    -framework Cocoa -framework ScreenSaver -framework QuartzCore \
    -o macos/build/smoke-tests
macos/build/smoke-tests "$PWD/macos/build/Electropaint.saver"
