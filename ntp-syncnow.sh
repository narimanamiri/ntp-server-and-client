#!/usr/bin/env bash
# ntp-syncnow.sh
# One-shot: force chrony to resynchronize immediately.
#
# Requests a measurement burst from all sources, then steps the system clock
# to the best estimate (chronyc makestep). Useful right after configuring a
# client or when the clock has drifted far enough that slewing would be slow.
#
# Requires root because `chronyc makestep` needs the chronyd command socket.
#
# Options:
#   -w SECONDS   how long to wait for the burst to gather samples (default 8)
#   -h           show help
#
# Exit codes:
#   0  step requested successfully
#   1  chronyd not running / makestep failed
#   2  chronyc not found
#   3  not run as root
set -euo pipefail

WAIT="8"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d'
}

while getopts ":w:h" opt; do
  case "$opt" in
    w) WAIT="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ ! "$WAIT" =~ ^[0-9]+$ ]]; then
  echo "Wait time must be a non-negative integer." >&2
  exit 2
fi

if ! command -v chronyc >/dev/null 2>&1; then
  echo "chronyc not found - is chrony installed?" >&2
  exit 2
fi

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run this script as root or with sudo." >&2
    exit 3
  fi
}

require_root

# Make sure chronyd is actually answering on its command socket.
if ! chronyc tracking >/dev/null 2>&1; then
  echo "chronyd does not appear to be running. Start it first, e.g.:" >&2
  echo "  systemctl start chrony   (Debian/Ubuntu)" >&2
  echo "  systemctl start chronyd  (RHEL/Fedora)" >&2
  exit 1
fi

echo "Current offset before sync:"
chronyc tracking 2>/dev/null | grep -E "Last offset|Leap status" || true
echo

# Trigger a burst on every source (4 good measurements out of up to 4 polls).
# Some chrony builds restrict 'burst' to authenticated/local clients, so allow
# it to fail softly and fall back to makestep alone.
echo "Requesting measurement burst from all sources..."
chronyc -a burst 4/4 >/dev/null 2>&1 || chronyc burst 4/4 >/dev/null 2>&1 || true

if (( WAIT > 0 )); then
  echo "Waiting ${WAIT}s for samples..."
  sleep "$WAIT"
fi

echo "Stepping the system clock to the new estimate (makestep)..."
if chronyc -a makestep >/dev/null 2>&1 || chronyc makestep >/dev/null 2>&1; then
  echo "Step requested."
else
  echo "makestep failed." >&2
  exit 1
fi

# Give chronyd a moment to apply the step before reporting.
sleep 2

echo
echo "Offset after sync:"
chronyc tracking 2>/dev/null | grep -E "Reference ID|Stratum|Last offset|Leap status" || true
echo
echo "Current system time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
exit 0
