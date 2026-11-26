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

# Import: Mermaid in, a sheet out, byte-exact (spec §18.1 promises determinism).
for fixture in tests/fixture/mmd/*.mmd; do
    [ -e "$fixture" ] || continue
    name=$(basename "$fixture" .mmd)
    expected="tests/expected/import_$name.deck.yaml"
    got="tests/out/import_$name.deck.yaml"
    total=$((total + 1))
    rm -f "$got"
    if ! "$BIN" --import "$fixture" --out "$got" 2>/dev/null; then
        echo "[ FAIL ] $name (import) -- exited non-zero"
        failed=$((failed + 1))
        continue
    fi
    if diff -u "$expected" "$got"; then
        echo "[  OK  ] $name (import)"
    else
        echo "[ FAIL ] $name -- imported sheet differs from $expected"
        failed=$((failed + 1))
    fi
done

# An import must refuse to write over a sheet that already exists (§18.1): the
# layout it invents would replace one somebody arranged.
total=$((total + 1))
guard="tests/out/import_guard.deck.yaml"
: > "$guard"
if "$BIN" --import tests/fixture/mmd/klein.mmd --out "$guard" 2>/dev/null; then
    echo "[ FAIL ] import ueberschreibt eine vorhandene Datei"
    failed=$((failed + 1))
else
    echo "[  OK  ] import refuses an existing target"
fi

# PPTX: the parts byte-exact, and a real reader must open the package (spec §17.2).
if ! command -v unzip >/dev/null; then
    echo "[ SKIP ] pptx -- no unzip; a silent skip would read like a pass, so this says so"
else
    for fixture in tests/fixture/*.deck.yaml tests/fixture/*.chart.yaml; do
        [ -e "$fixture" ] || continue
        name=$(basename "$fixture" | sed -E 's/\.(chart|deck)\.yaml$//')
        case "$fixture" in *.deck.yaml) flag=--deck ;; *) flag=--sheet ;; esac
        expected="tests/expected/pptx_$name"
        [ -d "$expected" ] || continue
        got="tests/out/pptx_$name"
        file="tests/out/$name.pptx"
        total=$((total + 1))
        rm -rf "$got" "$file"
        if ! "$BIN" "$flag" "$fixture" --pptx "$file"; then
            echo "[ FAIL ] $name (pptx) -- exporter exited non-zero"
            failed=$((failed + 1))
            continue
        fi
        mkdir -p "$got"
        if ! unzip -q -o "$file" -d "$got"; then
            echo "[ FAIL ] $name (pptx) -- the package does not unpack"
            failed=$((failed + 1))
            continue
        fi
        if diff -ru "$expected" "$got"; then
            echo "[  OK  ] $name (pptx parts)"
        else
            echo "[ FAIL ] $name -- pptx parts differ from $expected"
            failed=$((failed + 1))
        fi
    done
fi

# An external reader is the only honest check that the container is valid.
if ! command -v soffice >/dev/null; then
    echo "[ SKIP ] pptx reader -- no soffice on this machine"
else
    for file in tests/out/*.pptx; do
        [ -e "$file" ] || continue
        name=$(basename "$file" .pptx)
        total=$((total + 1))
        rm -f "tests/out/$name.pdf"
        if soffice --headless --convert-to pdf --outdir tests/out "$file" >/dev/null 2>&1 \
           && [ -s "tests/out/$name.pdf" ]; then
            echo "[  OK  ] $name (pptx opens in LibreOffice)"
        else
            echo "[ FAIL ] $name -- LibreOffice cannot read the package"
            failed=$((failed + 1))
        fi
    done
fi

echo "chart: $((total - failed))/$total passed"
[ "$failed" -eq 0 ]
