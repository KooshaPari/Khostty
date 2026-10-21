#!/usr/bin/env bash
# =============================================================================
# Agent IPC runtime check - prove the socket ANSWERS against a running app
# =============================================================================
# Run inside the project dev shell (`nix develop -c bash nix/ipc-runtime-check.sh`)
# so `xvfb-run` and GTK are on PATH.
#
# Launches the real GTK runtime under Xvfb, waits for the Unix socket, then runs
# `ipc-probe`, which performs the handshake a client actually performs
# (`ping` then `pane.list`).
#
# Exit codes: 0 = the app answered; non-zero = it did not, and the reason is on
# stderr along with the app log.
#
# FORK: KooshaPari/Khostty#48 (Phase B1 verification).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/zig-out/bin/ghostty"
PROBE="$ROOT/zig-out/bin/ipc-probe"
SOCK="$ROOT/khostty-ci.sock"
LOG="$ROOT/app.log"

for f in "$APP" "$PROBE"; do
  if [ ! -x "$f" ]; then
    echo "error: missing $f (build it first: zig build -Dapp-runtime=gtk," \
         "zig build-exe src/ipc_probe.zig -femit-bin=zig-out/bin/ipc-probe)" >&2
    exit 2
  fi
done

rm -f "$SOCK" "$LOG"

export KHOSTTY_IPC_SOCKET="$SOCK"
# A random per-run token. The probe is an ordinary client; this proves the auth
# path is exercised rather than bypassed.
KHOSTTY_IPC_TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export KHOSTTY_IPC_TOKEN

# Software rendering: Xvfb has no GPU, and GTK4 aborts while probing GL before
# any window is mapped if left to pick a renderer itself.
export GSK_RENDERER=cairo
export GDK_BACKEND=x11
export NO_AT_BRIDGE=1

# ReleaseSafe closes the resources-dir search over GHOSTTY_RESOURCES_DIR rather
# than the debug sentinel walk, so point it at the installed share tree. Without
# it the GTK runtime cannot load its blueprint UI resources.
if [ -d "$ROOT/zig-out/share/ghostty" ]; then
  export GHOSTTY_RESOURCES_DIR="$ROOT/zig-out/share/ghostty"
  echo "resources: $GHOSTTY_RESOURCES_DIR"
else
  echo "warning: $ROOT/zig-out/share/ghostty is missing; the app may fail to start" >&2
fi

APP_PID=""
cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "error: xvfb-run is not on PATH; this script must run inside the dev shell" >&2
  exit 2
fi

echo "launching the GTK runtime under Xvfb"
echo "  app:  $APP ($(stat -c%s "$APP") bytes)"
echo "  Xvfb: $(command -v xvfb-run)"
xvfb-run -a "$APP" >"$LOG" 2>&1 &
APP_PID=$!

# The IPC server starts from App.init, before the GTK loop, so the socket should
# appear early. Poll rather than sleep a fixed time: a fixed sleep is either
# flaky or needlessly slow.
ready=""
for _ in $(seq 1 90); do
  if [ -S "$SOCK" ]; then ready=1; break; fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    # Report the real exit status: "exited" alone cannot distinguish a crash,
    # a usage error, and a clean exit because there was nothing to open.
    wait "$APP_PID" 2>/dev/null && code=0 || code=$?
    echo "error: the app exited before creating the socket (status $code)" >&2
    echo "--- app log ($(stat -c%s "$LOG" 2>/dev/null || echo 0) bytes) ---" >&2
    cat "$LOG" >&2
    echo "--- retry in the foreground, to surface anything buffered ---" >&2
    timeout 10 xvfb-run -a "$APP" 2>&1 | head -n 60 >&2 || true
    exit 1
  fi
  sleep 1
done

if [ -z "$ready" ]; then
  echo "error: no socket at $SOCK after 90s" >&2
  echo "--- app log ---" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "socket appeared: $SOCK"

# The real assertion: a client handshake against the live app.
if ! "$PROBE"; then
  echo "error: ipc-probe failed against the running app" >&2
  echo "--- app log ---" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "--- app log (tail) ---"
tail -n 40 "$LOG" || true
echo "PASS: a running khostty answered ping and pane.list over its socket"
