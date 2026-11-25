#!/bin/bash
# chart tests -- headless, byte-exact (doc/spec/chart.md §9).
#
# Byte-exact is the point: §2 promises the export is a pure function of the sheet, and
# only a byte comparison actually checks that promise.
set -u
cd "$(dirname "$0")/.."
BIN="${CHART_BIN:-./chart}"
if [ ! -x "$BIN" ]; then
    echo "chart: no executable at '$BIN' -- build with 'exodus build -c exodus-chart.json' first"
    exit 1
fi
mkdir -p tests/out
total=0
failed=0
for fixture in tests/fixture/*.chart.yaml; do
    name=$(basename "$fixture" .chart.yaml)
    expected="tests/expected/$name.mmd"
    got="tests/out/$name.mmd"
    total=$((total + 1))
    if ! "$BIN" --sheet "$fixture" --mermaid "$got"; then
        echo "[ FAIL ] $name -- exporter exited non-zero"
        failed=$((failed + 1))
        continue
    fi
    if [ ! -f "$expected" ]; then
        echo "[ FAIL ] $name -- no expected file at $expected"
        failed=$((failed + 1))
        continue
    fi
    if diff -u "$expected" "$got"; then
        echo "[  OK  ] $name"
    else
        echo "[ FAIL ] $name -- output differs from $expected"
        failed=$((failed + 1))
    fi
done
echo "chart: $((total - failed))/$total passed"
[ "$failed" -eq 0 ]
