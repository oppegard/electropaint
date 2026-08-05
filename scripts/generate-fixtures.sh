#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
web_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
fixture_binary=$(mktemp "${TMPDIR:-/tmp}/electropaint-reference.XXXXXX")
trap 'rm -f "$fixture_binary"' EXIT HUP INT TERM

cc -std=c99 -Wall -Wextra -pedantic \
  "$web_dir/tests/reference/electropaint_reference.c" \
  -lm \
  -o "$fixture_binary"
"$fixture_binary" > "$web_dir/tests/fixtures/reference.json"
