#!/usr/bin/env bash
# Helper fd-inheritance self-test (PLAN §14.1, R4C §4.3).
#
#   scripts/selftest-helpers.sh <path to the Snaptic executable>
#
# Runs `Snaptic --selftest-helpers <token-file>` with a fresh token. The app spawns two
# helper children through HelperSpawner, prints "child <pid> <startTime>" for each and
# SIGKILLs itself (exit 137 is expected). Both children must then exit within 3 s: they
# only see EOF on stdin if no pipe end leaked into a sibling or stayed open in the parent.
# Command substitution also waits for EOF on our pipe, so a child that inherited stdout
# makes the `timeout` fire, which fails the test too.
set -uo pipefail

BIN=${1:?usage: selftest-helpers.sh <Snaptic executable>}
[ -x "$BIN" ] || { echo "selftest: $BIN is not executable" >&2; exit 1; }

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
token=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)
printf '%s\n' "$token" > "$dir/token"
chmod 600 "$dir/token"

# GNU timeout if present (exit 124 on expiry); otherwise perl's alarm (exit 142).
with_timeout() {
  local seconds=$1; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$seconds" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
  fi
}

start=$(date +%s)
out=$(SNAPTIC_SELFTEST_TOKEN="$token" with_timeout 10 "$BIN" --selftest-helpers "$dir/token")
status=$?
elapsed=$(( $(date +%s) - start ))
echo "selftest: exit $status after ${elapsed}s"
echo "$out"

if [ "$status" -eq 124 ] || [ "$status" -eq 142 ]; then
  echo "selftest: timed out: a child kept our stdout open (leaked descriptor)" >&2
  exit 1
fi
if [ "$status" -ne 137 ]; then
  echo "selftest: expected the parent to die by SIGKILL (137), got $status" >&2
  exit 1
fi

pids=$(printf '%s\n' "$out" | awk '$1 == "child" { print $2 }')
count=$(printf '%s\n' "$pids" | grep -c '[0-9]' || true)
if [ "$count" -ne 2 ]; then
  echo "selftest: expected 2 children, saw $count" >&2
  exit 1
fi

for _ in $(seq 1 30); do
  alive=0
  for pid in $pids; do
    if kill -0 "$pid" 2>/dev/null; then alive=1; fi
  done
  [ "$alive" -eq 0 ] && { echo "selftest: both children exited"; exit 0; }
  sleep 0.1
done

echo "selftest: children still alive 3 s after the parent died:" >&2
for pid in $pids; do kill -0 "$pid" 2>/dev/null && { ps -o pid,ppid,stat,command -p "$pid" >&2; kill -9 "$pid"; }; done
exit 1
