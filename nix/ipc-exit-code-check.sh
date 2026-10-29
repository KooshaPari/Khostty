#!/usr/bin/env bash
# =============================================================================
# Assert the runtime exits NON-ZERO when it cannot start a terminal
# =============================================================================
# KooshaPari/Khostty#65. The GTK runtime used to exit 0 when no surface could
# ever be initialised (e.g. no EGL driver on a headless host), so a
# supervisor, a systemd unit or a CI check could not tell a failed startup from
# a clean shutdown.
#
# The unit tests in surface_init_state.zig cover the DECISION LOGIC. This
# covers the thing that actually matters: the process exit code.
#
# Run inside the dev shell: nix develop -c bash nix/ipc-exit-code-check.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/zig-out/bin/ghostty"
LOG="$ROOT/exit-code.log"
XVFB_LOG="$ROOT/xvfb-exit.log"
DISPLAY_NUM="${KHOSTTY_CI_DISPLAY:-:96}"

if [ ! -x "$APP" ]; then
  echo "error: missing $APP (build it first: zig build -Dapp-runtime=gtk)" >&2
  exit 2
fi
if ! command -v Xvfb >/dev/null 2>&1; then
  echo "error: Xvfb is not on PATH; run this inside the dev shell" >&2
  exit 2
fi

rm -f "$LOG" "$XVFB_LOG"

export GSK_RENDERER=cairo
export GDK_BACKEND=x11
export NO_AT_BRIDGE=1
# Deliberately break EGL so no surface can ever be initialised. This is the
# condition #65 is about: the runtime starts, cannot open a terminal, and
# used to exit 0.
export LIBGL_ALWAYS_SOFTWARE=0
export __EGL_VENDOR_LIBRARY_FILENAMES=/nonexistent/egl_vendor.json
export GHOSTTY_RESOURCES_DIR="$ROOT/zig-out/share/ghostty"

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
for _ in $(seq 1 40); do
  [ -e "/tmp/.X11-unix/X${DISPLAY_NUM#:}" ] && break
  sleep 0.5
done
export DISPLAY="$DISPLAY_NUM"

echo "launching the runtime with EGL deliberately broken"
set +e
timeout 60 "$APP" >"$LOG" 2>&1
code=$?
set -e

echo "exit code: $code"
echo "--- app log (tail) ---"
tail -n 30 "$LOG" || true

if [ "$code" -eq 0 ]; then
  echo "::error::the runtime exited 0 despite never opening a terminal (#65)" >&2
  exit 1
fi

# 124 means our own timeout fired, which is a different failure: the runtime
# hung rather than exiting. That is still a bug, but not this one.
if [ "$code" -eq 124 ]; then
  echo "::error::the runtime HUNG instead of exiting (#65 wants a non-zero exit)" >&2
  exit 1
fi

echo "PASS: the runtime exits $code when it cannot open a terminal"
