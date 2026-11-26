#!/bin/bash
# Fetch the aiml toolchain from kontor into a venv -- no aiml clone, no exodus,
# no compiler build (doc/spec/chart.md §Build; aiml spec/68 §1).
#
# kontor's GENERIC store keeps the finished, relocatable venv (bin/ lib/ env) that
# aiml's CI puts there, under the COMMIT and under `latest`. aiml carries one version
# across all commits, which is why it is not the /exodus/<name>/<version>/ store:
# there name and version must match the manifest and every build would overwrite the
# last.
#
#   tools/aiml_from_kontor.sh [latest|<commit-sha>] [<venv-dir>]
#
# Settings, in this order: environment, tools/kontor.conf, default.
set -eu
cd "$(dirname "$0")/.."

[ -f tools/kontor.conf ] && . tools/kontor.conf

REF="${1:-latest}"
VENV="${2:-$PWD/.aimlvenv}"
URL="${KONTOR_URL:-}"
CA="${KONTOR_CA:-../kontor/tls/ca.crt}"
TOKEN_FILE="${KONTOR_TOKEN_FILE:-$HOME/.kontor-ci.token}"

if [ -z "$URL" ]; then
    echo "KONTOR_URL is not set -- put it in the environment or in tools/kontor.conf" >&2
    exit 1
fi
if [ ! -f "$TOKEN_FILE" ]; then
    echo "no token at $TOKEN_FILE -- kontor answers 401 without one (its anonymous role is not reader here)" >&2
    exit 1
fi
if [ ! -f "$CA" ]; then
    echo "no CA at $CA -- kontor serves a private certificate" >&2
    exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
target="$URL/generic/aiml/$REF/aiml-x86_64-linux.tar.gz"
echo "fetching $target"

# No `curl -k`: without certificate checking a man in the middle could take the token.
# One request, not several in parallel -- this instance drops parallel TLS handshakes.
if ! curl --silent --show-error --fail --max-time 1800 \
          --cacert "$CA" \
          -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
          -o "$stage/aiml.tar.gz" "$target"; then
    echo "not in kontor: generic/aiml/$REF/ -- try 'latest', or a commit that CI has built" >&2
    exit 1
fi

mkdir -p "$VENV"
tar -xzf "$stage/aiml.tar.gz" -C "$VENV"
if [ ! -x "$VENV/bin/aiml" ] || [ ! -f "$VENV/lib/libaiml.so" ]; then
    echo "the archive is not a venv: $VENV/bin/aiml or lib/libaiml.so is missing" >&2
    exit 1
fi

# A bundle from before the library bundling does not resolve its pinned libraries.
missing="$(ldd "$VENV/bin/aiml" "$VENV/lib/libaiml.so" | grep 'not found' || true)"
if [ -n "$missing" ]; then
    echo "incomplete bundle -- these are unresolved:" >&2
    echo "$missing" >&2
    exit 1
fi

# `env` still names the place the bundle was made in; running the venv against itself
# rewrites only that file (aiml spec/68 F68-14), and the binaries are relocatable.
"$VENV/bin/aiml" venv "$VENV" >/dev/null

echo
echo "aiml $("$VENV/bin/aiml" --version 2>/dev/null || echo "(ready)") in $VENV"
echo "use it with:  . $VENV/env"
