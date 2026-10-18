#!/usr/bin/env bash
# Control-server connection self-test (PLAN 0.3 §2.10, R5-5).
#
#   scripts/selftest-control-server.sh <path to the Snaptic executable>
#
# Starts `Snaptic --selftest-control-server <token-file>` (no modules, only a ControlServer with a test registry:
# `selftest hold` (holds), `selftest slow` (3 s), `selftest echo`; pings every second) on a socket in a fresh 0700
# directory, then drives real `Snaptic cli …` clients (token mode: SNAPTIC_SELFTEST_TOKEN, …_TOKEN_FILE, …_SOCKET)
# and python3 raw-socket clients through the nine cases of R5-5, plus the retired `prevent-sleep` verb (R5-12, case 10).
# The server prints `held=<n> active=<n>` on every pool change and `closed <eof|extra|ping|limit|server|pid>` per
# hold; the checks read that log.
set -uo pipefail

BIN=${1:?usage: selftest-control-server.sh <Snaptic executable>}
[ -x "$BIN" ] || { echo "selftest: $BIN is not executable" >&2; exit 1; }
command -v python3 >/dev/null || { echo "selftest: python3 is required" >&2; exit 1; }

dir=$(mktemp -d)
chmod 700 "$dir"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -9 "$pid" 2>/dev/null; done
  [ -n "${server:-}" ] && kill -9 "$server" 2>/dev/null
  rm -rf "$dir"
}
trap cleanup EXIT

token=$(head -c 30 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '%s\n' "$token" > "$dir/token"
chmod 600 "$dir/token"
export SNAPTIC_SELFTEST_TOKEN="$token"
export SNAPTIC_SELFTEST_TOKEN_FILE="$dir/token"
export SNAPTIC_SELFTEST_SOCKET="$dir/s.sock"
log="$dir/server.log"
failures=0

say() { echo "selftest: control server: $*"; }
fail() { echo "selftest: control server FAILED: $*" >&2; failures=$((failures + 1)); }

# GNU timeout if present; otherwise perl's alarm.
with_timeout() {
  local seconds=$1; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$seconds" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
  fi
}

cli() { with_timeout 20 "$BIN" cli "$@"; }

# Starts a server instance with a fresh log and waits until it listens.
start_server() {
  : > "$log"
  "$BIN" --selftest-control-server "$dir/token" >>"$log" 2>&1 </dev/null &
  server=$!
  for _ in $(seq 1 50); do
    grep -q '^listening$' "$log" && return 0
    kill -0 "$server" 2>/dev/null || break
    sleep 0.1
  done
  fail "the server didn't start"; cat "$log" >&2
  exit 1
}

stop_server() {
  kill -TERM "$server" 2>/dev/null
  for _ in $(seq 1 30); do kill -0 "$server" 2>/dev/null || break; sleep 0.1; done
  kill -9 "$server" 2>/dev/null
  wait "$server" 2>/dev/null
  server=""
}

pool() { grep -E '^held=[0-9]+ active=[0-9]+$' "$log" | tail -1; }
count() { grep -c -x -- "$1" "$log"; }

# wait_pool "<held=n active=m>" <tenths of a second>
wait_pool() {
  for _ in $(seq 1 "$2"); do [ "$(pool)" = "$1" ] && return 0; sleep 0.1; done
  return 1
}

# wait_count "<line>" <at least n> <tenths of a second>
wait_count() {
  for _ in $(seq 1 "$3"); do [ "$(count "$1")" -ge "$2" ] && return 0; sleep 0.1; done
  return 1
}

# A real client that holds until it is killed; its stdout and stderr go to files. Sets $client (no subshell, so
# the client stays our child and is cleaned up on exit).
hold_client() {
  "$BIN" cli selftest hold >"$dir/hold-$1.out" 2>"$dir/hold-$1.err" </dev/null &
  client=$!
  pids+=("$client")
}

# A raw python client in the background; it prints its own pid first (the wrapper's pid isn't python's). Sets $rawpid.
raw_bg() {
  local name=$1; shift
  : > "$dir/$name.out"
  with_timeout 150 python3 "$dir/raw.py" "$@" >"$dir/$name.out" 2>&1 </dev/null &
  pids+=($!)
  rawpid=""
  for _ in $(seq 1 50); do
    rawpid=$(head -1 "$dir/$name.out" 2>/dev/null)
    [ -n "$rawpid" ] && break
    sleep 0.1
  done
  [ -n "$rawpid" ] && pids+=("$rawpid")
}

cat > "$dir/raw.py" <<'PY'
import json, os, select, socket, subprocess, sys, time

PATH = os.environ["SNAPTIC_SELFTEST_SOCKET"]
PING = b'{"ping":true}'

def request(*args):
    return (json.dumps({"verb": "selftest", "arguments": list(args)}) + "\n").encode()

def connect(rcvbuf=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    if rcvbuf:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcvbuf)
    s.connect(PATH)
    return s

class Lines:
    def __init__(self, s):
        self.s, self.buf, self.eof = s, b"", False
    def next(self, timeout):
        """The next line, None on timeout, b'' at EOF."""
        end = time.time() + timeout
        while b"\n" not in self.buf:
            if self.eof:
                return b""
            left = end - time.time()
            if left <= 0:
                return None
            ready, _, _ = select.select([self.s], [], [], left)
            if not ready:
                return None
            data = self.s.recv(4096)
            if not data:
                self.eof = True
                continue
            self.buf += data
        line, self.buf = self.buf.split(b"\n", 1)
        return line

def held(s):
    lines = Lines(s)
    first = lines.next(5)
    if not first or not json.loads(first).get("holding"):
        print("not holding: %r" % first, flush=True)
        sys.exit(1)
    return lines

def wait_eof(lines, seconds):
    end = time.time() + seconds
    while time.time() < end:
        line = lines.next(end - time.time())
        if line == b"":
            return True
    return False

mode = sys.argv[1]
if mode in ("inherit", "stall"):
    print(os.getpid(), flush=True)
if mode == "extra-same":
    s = connect()
    s.sendall(request("hold") + b"x")
    lines = Lines(s)
    got = lines.next(5)
    print("eof" if got == b"" else "reply %r" % got, flush=True)
elif mode == "extra-later":
    s = connect()
    s.sendall(request("hold"))
    lines = held(s)
    s.sendall(b"x")
    print("eof" if wait_eof(lines, 3) else "open", flush=True)
elif mode == "early-close":
    s = connect()
    s.sendall(request("hold"))
    s.close()
    print("closed", flush=True)
elif mode == "inherit":
    s = connect()
    s.sendall(request("hold"))
    held(s)
    child = subprocess.Popen(["sleep", "30"], pass_fds=[s.fileno()])
    print("child %d" % child.pid, flush=True)
    time.sleep(60)
elif mode == "pings":
    s = connect()
    s.sendall(request("hold"))
    lines = held(s)
    end, pings, other = time.time() + float(sys.argv[2]), 0, 0
    while time.time() < end:
        line = lines.next(end - time.time())
        if line is None:
            break
        if line == b"":
            print("eof", flush=True)
            sys.exit(1)
        if line == PING:
            pings += 1
        else:
            other += 1
    print("%d %d" % (pings, other), flush=True)
elif mode == "idle":
    s = connect()
    s.sendall(request("hold"))
    lines = held(s)
    print("eof" if wait_eof(lines, float(sys.argv[2])) else "open", flush=True)
elif mode == "stall":
    s = connect(rcvbuf=256)
    s.sendall(request("hold"))
    held(s)
    print("stalled", flush=True)
    time.sleep(300)      # never reads again
elif mode == "echo":
    s = connect()
    start = time.time()
    s.sendall(request("echo", "hi"))
    line = Lines(s).next(5)
    ms = int((time.time() - start) * 1000)
    ok = line is not None and line != b"" and json.loads(line).get("output") == "hi"
    print("%d %s" % (ms, "ok" if ok else "bad %r" % line), flush=True)
else:
    sys.exit(2)
PY
raw() { with_timeout 120 python3 "$dir/raw.py" "$@"; }

start_server
say "listening at $SNAPTIC_SELFTEST_SOCKET"

# 1. One hold, then 4 slow requests are accepted and a 5th is busy.
hold_client 1
c=$client
wait_pool "held=1 active=0" 30 || fail "case 1: the hold didn't move to the held pool ($(pool))"
grep -q '^Holding until this command ends' "$dir/hold-1.out" || fail "case 1: the client didn't print the holding line"
slow=()
for i in 1 2 3 4; do
  cli selftest slow >"$dir/slow-$i.out" 2>&1 &
  slow+=($!)
  sleep 0.1
done
wait_pool "held=1 active=4" 20 || fail "case 1: 4 slow requests weren't all accepted ($(pool))"
cli selftest slow >"$dir/slow-5.out" 2>&1
status=$?
[ "$status" -eq 5 ] && grep -q busy "$dir/slow-5.out" || fail "case 1: the 5th request wasn't busy (exit $status: $(cat "$dir/slow-5.out"))"
for pid in "${slow[@]}"; do
  wait "$pid" || fail "case 1: a slow request failed"
done
kill -TERM "$c"; wait "$c" 2>/dev/null
wait_pool "held=0 active=0" 20 || fail "case 1: the hold wasn't released ($(pool))"
say "case 1 done"

# 2. Eight holds; the ninth is refused with exit 4, held stays 8, and `closed limit` is logged.
holders=()
for i in $(seq 1 8); do hold_client "h$i"; holders+=("$client"); sleep 0.1; done
wait_pool "held=8 active=0" 40 || fail "case 2: 8 holds weren't all held ($(pool))"
cli selftest hold >"$dir/ninth.out" 2>&1
status=$?
[ "$status" -eq 4 ] || fail "case 2: the 9th hold exited $status, not 4 ($(cat "$dir/ninth.out"))"
grep -q 'already holding for 8' "$dir/ninth.out" || fail "case 2: the 9th hold's refusal text is missing"
wait_count "closed limit" 1 20 || fail "case 2: no 'closed limit'"
wait_pool "held=8 active=0" 20 || fail "case 2: held didn't stay 8 ($(pool))"
say "case 2 done"

# 3. kill -9 of a holding client: `closed eof` within 1 s, and held drops exactly once.
before=$(count "closed eof")
kill -9 "${holders[0]}"; wait "${holders[0]}" 2>/dev/null
wait_count "closed eof" $((before + 1)) 10 || fail "case 3: no 'closed eof' within 1 s of kill -9"
wait_pool "held=7 active=0" 10 || fail "case 3: held isn't 7 ($(pool))"
sleep 0.5
[ "$(pool)" = "held=7 active=0" ] || fail "case 3: held changed again ($(pool))"
[ "$(count "closed pid")" -eq 0 ] || fail "case 3: the client's exit was reported as 'pid', not 'eof'"
for pid in "${holders[@]:1}"; do kill -TERM "$pid"; done
for pid in "${holders[@]:1}"; do wait "$pid" 2>/dev/null; done
wait_pool "held=0 active=0" 30 || fail "case 3: the other holds weren't released ($(pool))"
say "case 3 done"

# 4. A client that writes its request and closes before it is served: no held leak.
raw early-close >/dev/null
sleep 0.5
wait_pool "held=0 active=0" 20 || fail "case 4: a slot leaked ($(pool))"
[ "$(raw echo | awk '{print $2}')" = ok ] || fail "case 4: the server stopped answering"
say "case 4 done"

# 5. The holding client's fd is inherited by a child (sleep); killing the client still ends the hold (`closed pid`).
raw_bg inherit inherit
holder=$rawpid
child=""
for _ in $(seq 1 50); do
  child=$(awk '$1 == "child" { print $2 }' "$dir/inherit.out")
  [ -n "$child" ] && break
  sleep 0.1
done
[ -n "$child" ] && pids+=("$child")
[ -n "$holder" ] && [ -n "$child" ] || fail "case 5: the raw client didn't start ($(cat "$dir/inherit.out"))"
wait_pool "held=1 active=0" 20 || fail "case 5: the raw hold wasn't held ($(pool))"
kill -9 "$holder"
wait_count "closed pid" 1 20 || fail "case 5: no 'closed pid' after the client died with its fd still open in sleep"
wait_pool "held=0 active=0" 20 || fail "case 5: the hold wasn't released ($(pool))"
kill -0 "$child" 2>/dev/null || fail "case 5: the child holding the fd isn't alive (the test proved nothing)"
kill -9 "$child" 2>/dev/null
say "case 5 done"

# 6. A byte after the request ends the hold, in the same first chunk and later.
before=$(count "closed extra")
[ "$(raw extra-same)" = eof ] || fail "case 6: a request with a trailing byte got a reply"
wait_count "closed extra" $((before + 1)) 20 || fail "case 6: no 'closed extra' for a byte in the first chunk"
[ "$(raw extra-later)" = eof ] || fail "case 6: a byte after the holding reply didn't close the connection"
wait_count "closed extra" $((before + 2)) 20 || fail "case 6: no 'closed extra' for a later byte"
wait_pool "held=0 active=0" 20 || fail "case 6: a slot leaked ($(pool))"
say "case 6 done"

# 7. Pings arrive every second and never reach the client's stdout.
hold_client 7
c=$client
read -r pings other < <(raw pings 3.5)
[ "${pings:-0}" -ge 3 ] || fail "case 7: only ${pings:-0} pings in 3.5 s"
[ "${other:-1}" -eq 0 ] || fail "case 7: $other non-ping lines on a held connection"
kill -TERM "$c"; wait "$c" 2>/dev/null
lines=$(wc -l < "$dir/hold-7.out" | tr -d ' ')
[ "$lines" -eq 1 ] || fail "case 7: the client printed $lines lines (pings must not reach stdout)"
grep -q ping "$dir/hold-7.out" && fail "case 7: a ping reached the client's stdout"
wait_pool "held=0 active=0" 20 || fail "case 7: a slot leaked ($(pool))"
say "case 7 done"

# 9. An idle hold stays open for 5 s: there is no read timeout once held.
[ "$(raw idle 5)" = open ] || fail "case 9: an idle hold was closed within 5 s"
wait_pool "held=0 active=0" 20 || fail "case 9: a slot leaked ($(pool))"
say "case 9 done"

# 10. The retired 0.2 verb (R5-12): `prevent-sleep` answers exit 2 with its pointer, and help doesn't list it.
cli prevent-sleep off >"$dir/retired.out" 2>&1
status=$?
[ "$status" -eq 2 ] || fail "case 10: prevent-sleep exited $status, not 2 ($(cat "$dir/retired.out"))"
grep -q 'Moved to Awake: use “snaptic awake …”.' "$dir/retired.out" || fail "case 10: prevent-sleep's text is missing ($(cat "$dir/retired.out"))"
cli help >"$dir/help.out" 2>&1 || fail "case 10: help failed ($(cat "$dir/help.out"))"
grep -q 'selftest echo' "$dir/help.out" || fail "case 10: help doesn't list the test verbs"
grep -q 'prevent-sleep' "$dir/help.out" && fail "case 10: help lists prevent-sleep"
say "case 10 done"

stop_server

# 8. A client that never reads: `closed ping` once its buffer fills; meanwhile echo answers in < 100 ms (L5).
start_server
raw_bg stall stall
staller=$rawpid
wait_pool "held=1 active=0" 50 || fail "case 8: the stalled hold wasn't held ($(pool))"
slowest=0
slow=0
closed=0
for _ in $(seq 1 55); do
  read -r ms verdict < <(raw echo)
  [ "$verdict" = ok ] || fail "case 8: echo failed while a hold stalled ($verdict)"
  [ "${ms:-999}" -gt "$slowest" ] && slowest=${ms:-999}
  [ "${ms:-999}" -ge 100 ] && slow=$((slow + 1))
  if [ "$(count "closed ping")" -ge 1 ]; then closed=1; break; fi
  sleep 2
done
[ "$closed" -eq 1 ] || fail "case 8: no 'closed ping' within 110 s for a client that never reads"
# One scheduling hiccup on a shared CI runner is tolerated; a server blocked on the stalled client is not
# (it would be slow on every sample, and stalls last until `closed ping`).
[ "$slow" -le 1 ] || fail "case 8: echo took >= 100 ms on $slow samples while a hold stalled (slowest ${slowest} ms)"
[ "$slowest" -lt 1000 ] || fail "case 8: echo took ${slowest} ms while a hold stalled (must be < 1 s even once)"
wait_pool "held=0 active=0" 20 || fail "case 8: the stalled hold wasn't released ($(pool))"
[ -n "$staller" ] && kill -9 "$staller" 2>/dev/null
say "case 8 done (slowest echo ${slowest} ms, ${slow} sample(s) >= 100 ms)"
stop_server

echo "--- server log"
cat "$log"
if [ "$failures" -ne 0 ]; then
  echo "selftest: control server: $failures check(s) failed" >&2
  exit 1
fi
say "all cases passed"
