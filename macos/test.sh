#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p macos/build
xcrun clang -std=gnu11 -g -O1 -fsanitize=address,undefined \
    macos/EPAdapter.c macos/tests.c -o macos/build/engine-tests
macos/build/engine-tests
case "${1:-}" in
    --engine-only) exit 0 ;;
    '') ;;
    *) printf 'Usage: bash macos/test.sh [--engine-only]\n' >&2; exit 2 ;;
esac
xcrun clang -std=gnu11 -O2 -DTEST -DOPENGL10 -include macos/ReferenceNames.h \
    -c macos/vendor/ep.c -o macos/build/reference.o
xcrun clang -std=gnu11 -O2 -Wno-deprecated-declarations macos/reference-tests.c \
    macos/EPAdapter.c macos/build/reference.o -framework OpenGL -o macos/build/reference-tests
macos/build/reference-tests
