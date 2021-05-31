#!/bin/bash

set -euo pipefail

exec /sbin/setuser chrome google-chrome \
  --no-sandbox \
  --headless \
  --user-data-dir=/home/chrome \
  --disk-cache-dir=/var/cache/chrome \
  --crash-dumps-dir=/tmp \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-translate \
  --disable-extensions \
  --disable-background-networking \
  --safebrowsing-disable-auto-update \
  --disable-sync \
  --disable-breakpad \
  --metrics-recording-only \
  --disable-default-apps \
  --no-first-run \
  --mute-audio \
  --hide-scrollbars \
  --remote-debugging-address=0.0.0.0 \
  --remote-debugging-port=9222 \
  "about:blank" > /proc/1/fd/1 2>&1
