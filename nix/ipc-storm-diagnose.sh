#!/usr/bin/env bash
# =============================================================================
# Diagnose the post-split render storm (KooshaPari/Khostty#78)
# =============================================================================
# After a split, the GTK runtime under llvmpipe enters a loop:
#   debug(app): mailbox message=surface_message
#   warning(opengl): failed to export DMABUF, falling back to CPU presentation
# ... repeated without end.
#
# This captures the log and reports WHICH line repeats and how fast, so the
# cause is identified from evidence rather than from reading code.
#
# Run inside the dev shell: nix develop -c bash nix/ipc-storm-diagnose.sh
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/zig-out/bin/ghostty"
PROBE="$ROOT/zig-out/bin/ipc-probe"
LOG="$ROOT/storm.log"
XVFB_LOG="$ROOT/storm-xvfb.log"
SOCK="$ROOT/storm.sock"
DISPLAY_NUM="${KHOSTTY_CI_DISPLAY:-:95}"
CAPTURE_SECONDS="${STORM_CAPTURE_SECONDS:-25}"

for f in "$APP" "$PROBE"; do
  if [ ! -x "$f" ]; then
    echo "error: missing $f" >&2
    exit 2
  fi
done
if ! command -v Xvfb >/dev/null 2>&1; then
  echo "error: Xvfb is not on PATH; run this inside the dev shell" >&2
  exit 2
fi

rm -f "$LOG" "$XVFB_LOG" "$SOCK"

export GSK_RENDERER=cairo
export GDK_BACKEND=x11
export NO_AT_BRIDGE=1
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export KHOSTTY_IPC_SOCKET="$SOCK"
export KHOSTTY_IPC_TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
if [ -d "$ROOT/zig-out/share/ghostty" ]; then
  export GHOSTTY_RESOURCES_DIR="$ROOT/zig-out/share/ghostty"
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

Xvfb "$DISPLAY_NUM" -screen 0 1280x800x24 -nolisten tcp >"$XVFB_LOG" 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 40); do
  [ -e "/tmp/.X11-unix/X${DISPLAY_NUM#:}" ] && break
  sleep 0.5
done
export DISPLAY="$DISPLAY_NUM"

echo "launching the runtime"
"$APP" >"$LOG" 2>&1 &
APP_PID=$!

# Wait for the socket, then for a pane.
for _ in $(seq 1 60); do
  [ -S "$SOCK" ] && break
  sleep 0.5
done
if [ ! -S "$SOCK" ]; then
  echo "error: no socket; the app failed to start" >&2
  tail -n 20 "$LOG" >&2
  exit 1
fi

# Let the first pane settle.
sleep 2
echo "--- baseline (before the split) ---"
BASE_LINES=$(wc -l < "$LOG")
echo "log lines: $BASE_LINES"

echo "requesting a split"
timeout 20 "$PROBE" --split-only 2>&1 | tail -n 5 || true

echo "capturing $CAPTURE_SECONDS seconds after the split"
sleep "$CAPTURE_SECONDS"

echo "--- analysis ---"
TOTAL=$(wc -l < "$LOG")
echo "total log lines: $TOTAL (baseline was $BASE_LINES)"
AFTER=$((TOTAL - BASE_LINES))
echo "lines emitted during the capture: $AFTER"

if [ "$AFTER" -eq 0 ]; then
  echo "NO STORM: the log did not grow after the split."
else
  echo "lines per second: $(awk -v a="$AFTER" -v s="$CAPTURE_SECONDS" 'BEGIN{printf "%.1f", a/s}')"
  echo
  echo "top repeating log lines (message text only):"
  sed -E 's/^[0-9T:.Z-]+ //; s/[0-9]+/N/g' "$LOG" \
    | sed -n "$((BASE_LINES + 1)),\$p" \
    | sort | uniq -c | sort -rn | head -12 \
    | sed 's/^/    /'
fi

echo
echo "--- app log tail ---"
tail -n 12 "$LOG" || true
