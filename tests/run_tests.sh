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
# Decks: one Markdown file per slide, plus the index (spec §13).
for fixture in tests/fixture/*.deck.yaml; do
    [ -e "$fixture" ] || continue
    name=$(basename "$fixture" .deck.yaml)
    expected="tests/expected/$name"
    got="tests/out/$name"
    total=$((total + 1))
    rm -rf "$got"
    if ! "$BIN" --deck "$fixture" --markdown "$got"; then
        echo "[ FAIL ] $name -- exporter exited non-zero"
        failed=$((failed + 1))
        continue
    fi
    if [ ! -d "$expected" ]; then
        echo "[ FAIL ] $name -- no expected directory at $expected"
        failed=$((failed + 1))
        continue
    fi
    # -r so a file the exporter forgot, or one it invented, is a failure too.
    if diff -ru "$expected" "$got"; then
        echo "[  OK  ] $name (markdown)"
    else
        echo "[ FAIL ] $name -- markdown differs from $expected"
        failed=$((failed + 1))
    fi
done

# SVG: one file per slide, byte-exact (spec §17.1).  The byte comparison is what
# checks the "deterministic" promise -- a stray timestamp or a float spelled two ways
# would pass any looser test.
for fixture in tests/fixture/*.chart.yaml tests/fixture/*.deck.yaml; do
    [ -e "$fixture" ] || continue
    name=$(basename "$fixture" | sed -E 's/\.(chart|deck)\.yaml$//')
    case "$fixture" in *.deck.yaml) flag=--deck ;; *) flag=--sheet ;; esac
    expected="tests/expected/svg_$name"
    got="tests/out/svg_$name"
    total=$((total + 1))
    rm -rf "$got"
    if ! "$BIN" "$flag" "$fixture" --svg "$got"; then
        echo "[ FAIL ] $name (svg) -- exporter exited non-zero"
        failed=$((failed + 1))
        continue
    fi
    if diff -ru "$expected" "$got"; then
        echo "[  OK  ] $name (svg)"
    else
        echo "[ FAIL ] $name -- svg differs from $expected"
        failed=$((failed + 1))
    fi
done

# HTML: one self-contained deck (spec §17.3)
for fixture in tests/fixture/*.deck.yaml; do
    [ -e "$fixture" ] || continue
    name=$(basename "$fixture" .deck.yaml)
    expected="tests/expected/$name.html"
    got="tests/out/$name.html"
    total=$((total + 1))
    rm -f "$got"
    if ! "$BIN" --deck "$fixture" --html "$got"; then
        echo "[ FAIL ] $name (html) -- exporter exited non-zero"
        failed=$((failed + 1))
        continue
    fi
    if diff -u "$expected" "$got"; then
        echo "[  OK  ] $name (html)"
    else
        echo "[ FAIL ] $name -- html differs from $expected"
        failed=$((failed + 1))
    fi
done

echo "chart: $((total - failed))/$total passed"
[ "$failed" -eq 0 ]
