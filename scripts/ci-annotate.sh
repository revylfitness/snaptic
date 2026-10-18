#!/usr/bin/env bash
# Turns error lines from CI logs into a few multi-line GitHub annotations, so
# results are readable through the check-runs API (lead-owned; CI only).
# Usage: ci-annotate.sh <title> <log>...
set -uo pipefail
title=$1; shift
tmp=$(mktemp)
cat "$@" 2>/dev/null \
  | grep -E ': error: |: error:|error: |FAILED|failed|lint: |selftest: |XCTAssert|Fatal error|fatal error|Test Case .* failed' \
  | grep -vE '^\s*$' | awk '!seen[$0]++' | head -400 > "$tmp" || true
[ -s "$tmp" ] || { echo "no error lines found"; exit 0; }
chunk=45; n=0
while [ $n -lt 5 ]; do
  part=$(sed -n "$((n*chunk+1)),$(((n+1)*chunk))p" "$tmp")
  [ -n "$part" ] || break
  # Annotation messages encode newlines as %0A and % as %25.
  msg=$(printf '%s' "$part" | cut -c1-400 | sed 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=$title ($((n+1)))::$msg"
  n=$((n+1))
done
