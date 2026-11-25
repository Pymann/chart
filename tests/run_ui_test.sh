#!/bin/bash
# The editor smoke test (doc/spec/chart.md §9).
#
# SEPARATE from tests/run_tests.sh on purpose: this one needs a display, and a test
# that opens a window runs until the window closes. aiml's run_all_tests.sh has no
# timeout, so one blocking test stops everything behind it -- which is why chart's
# editor takes --frames and exits by itself instead of waiting for a human.
#
# It asserts what a headless suite cannot: that the window opens, that a frame is
# rendered, and that the rendering is not a blank or one-colour image. It does NOT
# check what the picture shows; there is no oracle for that here.
set -u
cd "$(dirname "$0")/.."
BIN="${CHART_BIN:-./chart}"
if [ ! -x "$BIN" ]; then
    echo "chart: no executable at '$BIN' -- build first"
    exit 1
fi
if ! command -v xvfb-run >/dev/null; then
    echo "[ SKIP ] editor -- no xvfb-run; a silent skip would read like a pass, so this says so"
    exit 0
fi
mkdir -p tests/out
failed=0
total=0
run_case() {
    local name="$1"; shift
    total=$((total + 1))
    local shot="tests/out/ui_$name.png"
    rm -f "$shot"
    if ! xvfb-run -a "$BIN" --deck examples/demo.deck.yaml --frames 12 --shot "$shot" "$@"; then
        echo "[ FAIL ] $name -- chart exited non-zero"
        failed=$((failed + 1))
        return
    fi
    if [ ! -s "$shot" ]; then
        echo "[ FAIL ] $name -- no capture written"
        failed=$((failed + 1))
        return
    fi
    # A one-colour frame means the canvas drew nothing: the window opened and the
    # capture worked, which is exactly the failure a size check would wave through.
    local colours
    colours=$(python3 -c "
import struct, zlib, sys
raw = open('$shot','rb').read()
pos, idat = 8, b''
while pos < len(raw):
    ln = struct.unpack('>I', raw[pos:pos+4])[0]; typ = raw[pos+4:pos+8]
    if typ == b'IDAT': idat += raw[pos+8:pos+8+ln]
    pos += 12 + ln
print(len(set(zlib.decompress(idat)[:200000])))
" 2>/dev/null || echo 0)
    if [ "${colours:-0}" -lt 8 ]; then
        echo "[ FAIL ] $name -- the frame has $colours distinct byte values; nothing was drawn"
        failed=$((failed + 1))
        return
    fi
    echo "[  OK  ] $name"
}
run_case editor      --start 1
run_case shapes      --start 2
run_case images      --start 3
run_case presentation --start 1 --present 1 --notes 1
echo "chart ui: $((total - failed))/$total passed"
[ "$failed" -eq 0 ]
