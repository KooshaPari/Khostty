#!/usr/bin/env bash
# =============================================================================
# Agent IPC runtime check - prove the socket ANSWERS against a running app
# =============================================================================
# Run inside the project dev shell (`nix develop -c bash nix/ipc-runtime-check.sh`)
# so `Xvfb` and GTK are on PATH.
#
# Launches the real GTK runtime on a private Xvfb display, waits for the Unix
# socket, then runs `ipc-probe`, which performs the handshake a client actually
# performs (`ping` then `pane.list`).
#
# Xvfb is managed directly rather than through `xvfb-run`. Measured on
# ubuntu-latest: `/usr/bin/xvfb-run` exists but the matching `Xvfb` binary does
# not, so the wrapper exits 1 having printed nothing at all - indistinguishable
# from the app crashing. Starting Xvfb ourselves makes a missing display server
# an explicit, named failure.
#
# Exit codes: 0 = the app answered; 2 = environment is wrong; 1 = it did not
# answer, and the reason is on stderr along with the app log.
#
# FORK: KooshaPari/Khostty#48 (Phase B1 verification).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/zig-out/bin/ghostty"
PROBE="$ROOT/zig-out/bin/ipc-probe"
SOCK="$ROOT/khostty-ci.sock"
LOG="$ROOT/app.log"
XVFB_LOG="$ROOT/xvfb.log"
DISPLAY_NUM="${KHOSTTY_CI_DISPLAY:-:97}"

for f in "$APP" "$PROBE"; do
  if [ ! -x "$f" ]; then
    echo "error: missing $f (build it first: zig build -Dapp-runtime=gtk," \
         "zig build-exe src/ipc_probe.zig -femit-bin=zig-out/bin/ipc-probe)" >&2
    exit 2
  fi
done

if ! command -v Xvfb >/dev/null 2>&1; then
  echo "error: Xvfb is not on PATH; run this inside the dev shell" >&2
  exit 2
fi

rm -f "$SOCK" "$LOG" "$XVFB_LOG"

export KHOSTTY_IPC_SOCKET="$SOCK"
# A random per-run token. The probe is an ordinary client; this proves the auth
# path is exercised rather than bypassed.
KHOSTTY_IPC_TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export KHOSTTY_IPC_TOKEN

# Software rendering: a virtual display has no GPU, and GTK4 aborts while
# probing GL before any window is mapped if left to pick a renderer itself.
export GSK_RENDERER=cairo
export GDK_BACKEND=x11
export NO_AT_BRIDGE=1

# The app renders through renderer.OpenGL and sets GDK_DEBUG=opengl itself, so
# GSK_RENDERER alone is not enough: it needs a real GL stack. Point Mesa at
# llvmpipe, which is software but complete.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

# ReleaseSafe resolves resources through GHOSTTY_RESOURCES_DIR rather than the
# debug sentinel walk; without it the GTK runtime cannot load its blueprint UI.
if [ -d "$ROOT/zig-out/share/ghostty" ]; then
  export GHOSTTY_RESOURCES_DIR="$ROOT/zig-out/share/ghostty"
  echo "resources: $GHOSTTY_RESOURCES_DIR"
else
  echo "warning: $ROOT/zig-out/share/ghostty is missing" >&2
fi

echo "--- preflight ---"
if timeout 20 "$APP" --version 2>&1 | head -n 3; then
  echo "  binary runs"
else
  echo "  warn: --version exited ${PIPESTATUS[0]:-?}"
fi

XVFB_PID=""
APP_PID=""
cleanup() {
  for pid in "$APP_PID" "$XVFB_PID"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT INT TERM

echo "starting Xvfb on $DISPLAY_NUM"
Xvfb "$DISPLAY_NUM" -screen 0 1280x800x24 -nolisten tcp >"$XVFB_LOG" 2>&1 &
XVFB_PID=$!

# Socket file appears once the server is accepting; poll instead of sleeping.
xready=""
for _ in $(seq 1 40); do
  if [ -e "/tmp/.X11-unix/X${DISPLAY_NUM#:}" ]; then xready=1; break; fi
  if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "error: Xvfb exited before creating a display" >&2
    cat "$XVFB_LOG" >&2
    exit 1
  fi
  sleep 0.5
done
if [ -z "$xready" ]; then
  echo "error: display $DISPLAY_NUM never became available" >&2
  cat "$XVFB_LOG" >&2
  exit 1
fi
export DISPLAY="$DISPLAY_NUM"
echo "display ready: $DISPLAY"

echo "launching the GTK runtime"
echo "  app: $APP ($(stat -c%s "$APP") bytes)"
"$APP" >"$LOG" 2>&1 &
APP_PID=$!

# The IPC server starts from App.init, before the GTK loop, so the socket should
# appear early.
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
    echo "--- xvfb log ---" >&2
    cat "$XVFB_LOG" >&2
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
