#!/usr/bin/env bash
# Quick health/verify check for a chrony-based NTP server or client.
# Works without root; prints sync state and exits non-zero if not synchronized.
set -euo pipefail

if ! command -v chronyc >/dev/null 2>&1; then
  echo "chronyc not found — is chrony installed?"
  exit 2
fi

# Capture tracking output once so the report and the sync check stay consistent.
tracking="$(chronyc tracking 2>/dev/null || true)"

echo "==== chrony tracking ===="
echo "${tracking:-(no tracking output)}"
echo
echo "==== chrony sources ===="
chronyc sources -v || true
echo
echo "==== current time ===="
date

echo
# Leap status "Normal" means the clock is synchronized.
if printf '%s\n' "$tracking" | grep -q "Leap status.*Normal"; then
  echo "✅ Synchronized"
  exit 0
else
  echo "❌ Not synchronized yet"
  exit 1
fi
