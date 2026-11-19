#!/usr/bin/env bash
set -euo pipefail

PORT="${NETEASE_CHROME_CDP_PORT:-9223}"
PROFILE_DIR="${NETEASE_CHROME_PROFILE_DIR:-$HOME/.chrome-agent-profile}"

detect_chrome() {
  if [[ -n "${CHROME_BIN:-}" && -x "${CHROME_BIN}" ]]; then
    echo "$CHROME_BIN"
    return 0
  fi
  if [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
    echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    return 0
  fi
  for bin in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$bin" >/dev/null 2>&1; then
      command -v "$bin"
      return 0
    fi
  done
  return 1
}

check_cdp() {
  curl -sf --max-time 2 "http://127.0.0.1:${PORT}/json/version"
}

if OUT=$(check_cdp); then
  echo "$OUT"
  exit 0
fi

CHROME_EXEC="$(detect_chrome)" || {
  echo "ERROR: Google Chrome / Chromium executable not found. Set CHROME_BIN to override." >&2
  exit 1
}

mkdir -p "$PROFILE_DIR"

# Launch an isolated persistent Chrome instance in the background:
# - Separate from the user's primary browser profile
# - Zero Chrome 144+ per-connection remote-debugging consent popups
# - Persistent login cookies across sessions and reboots
nohup "$CHROME_EXEC" \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$PROFILE_DIR" \
  --no-first-run \
  --no-default-browser-check \
  --disable-background-timer-throttling \
  "about:blank" >/dev/null 2>&1 &

for _ in $(seq 1 20); do
  sleep 0.5
  if OUT=$(check_cdp); then
    echo "$OUT"
    exit 0
  fi
done

echo "ERROR: Dedicated Chrome CDP failed to start on 127.0.0.1:${PORT}" >&2
exit 1
