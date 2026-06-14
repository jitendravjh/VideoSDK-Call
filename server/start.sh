#!/usr/bin/env bash
# Starts the signalling server and the Cloudflare tunnel together, so the public
# URL (https://signal.jitendravjh.in) is live whenever this is running. Press
# Ctrl+C to stop both.
set -u

cleanup() {
  echo ""
  echo "stopping server and tunnel..."
  kill "${SERVER_PID:-}" "${TUNNEL_PID:-}" 2>/dev/null
}
trap cleanup EXIT INT TERM

node index.js &
SERVER_PID=$!

cloudflared tunnel run videosdk-signal &
TUNNEL_PID=$!

echo "server (pid $SERVER_PID) + tunnel (pid $TUNNEL_PID) running. Ctrl+C to stop."
wait
