#!/usr/bin/env bash
# Helper fd-inheritance self-test (PLAN §14.1, R4C §4.3).
#
#   scripts/selftest-helpers.sh <path to the Snaptic executable>
#   SELFTEST_ARCH=x86_64 scripts/selftest-helpers.sh <universal executable>   # under Rosetta
#
# Runs `Snaptic --selftest-helpers <token-file>` with a fresh token. The app spawns two
# helper children through HelperSpawner, prints "child <pid> <startTime>" for each and
# SIGKILLs itself (exit 137 is expected) once both children reported that they passed
# HelperPrologue (fd closing, parent identity check). Both children must then exit within 3 s: they
# only see EOF on stdin if no pipe end leaked into a sibling or stayed open in the parent.
# Command substitution also waits for EOF on our pipe, so a child that inherited stdout
# makes the `timeout` fire, which fails the test too.
set -uo pipefail

BIN=${1:?usage: selftest-helpers.sh <Snaptic executable>}
[ -x "$BIN" ] || { echo "selftest: $BIN is not executable" >&2; exit 1; }
run=("$BIN")
if [ -n "${SELFTEST_ARCH:-}" ]; then
  # arch execs the binary in place, so the pid that SIGKILLs itself is still ours.
  run=(/usr/bin/arch "-$SELFTEST_ARCH" "$BIN")
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
token=$(head -c 30 /dev/urandom | od -An -tx1 | tr -d ' \n')
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
# Output goes to a file, not a pipe: a leaked descriptor must not be able to hang us.
SNAPTIC_SELFTEST_TOKEN="$token" "${run[@]}" --selftest-helpers "$dir/token" >"$dir/out" 2>"$dir/err" </dev/null &
parent=$!
status=""
for _ in $(seq 1 150); do
  if ! kill -0 "$parent" 2>/dev/null; then wait "$parent"; status=$?; break; fi
  sleep 0.1
done
if [ -z "$status" ]; then
  kill -9 "$parent" 2>/dev/null; wait "$parent" 2>/dev/null
  status=124
fi
out=$(cat "$dir/out")
elapsed=$(( $(date +%s) - start ))
echo "selftest: exit $status after ${elapsed}s"
echo "$out"
[ -s "$dir/err" ] && { echo "selftest: stderr:"; head -50 "$dir/err"; }

if [ "$status" -eq 124 ] || [ "$status" -eq 142 ]; then
  echo "selftest: the parent did not finish within 15 s" >&2
  pkill -9 -f -- "--selftest-child" 2>/dev/null || true
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
