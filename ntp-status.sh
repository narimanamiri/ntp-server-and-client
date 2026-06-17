#!/usr/bin/env bash
# ntp-status.sh
# Readable status report for a chrony-based NTP host.
#
# Parses `chronyc tracking` and `chronyc sources` and prints a compact table
# showing stratum, offset, frequency, RMS jitter and the currently selected
# upstream source. Each metric is graded against a threshold so the output is
# usable at a glance. Runs without root.
#
# Exit codes:
#   0  synchronized and all graded metrics within their thresholds
#   1  synchronized but one or more metrics exceeded a threshold (WARN)
#   2  chronyc not found
#   3  not synchronized (Leap status not Normal / no reference)
#
# Options:
#   -o SECONDS   max acceptable absolute offset   (default 0.1)
#   -j SECONDS   max acceptable RMS jitter        (default 0.05)
#   -s STRATUM   max acceptable stratum           (default 10)
#   -h           show help
set -euo pipefail

OFFSET_MAX="0.1"
JITTER_MAX="0.05"
STRATUM_MAX="10"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d'
}

while getopts ":o:j:s:h" opt; do
  case "$opt" in
    o) OFFSET_MAX="$OPTARG" ;;
    j) JITTER_MAX="$OPTARG" ;;
    s) STRATUM_MAX="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
  esac
done

if ! command -v chronyc >/dev/null 2>&1; then
  echo "chronyc not found - is chrony installed?" >&2
  exit 2
fi

# abs_le RESULT_VAR VALUE LIMIT
# Compares |VALUE| <= LIMIT without relying on bc/awk floats being present.
# Uses awk (POSIX, always available on Debian/RHEL) for the float math.
float_within() {
  # prints "OK" or "WARN" based on |value| <= limit
  local value="$1" limit="$2"
  awk -v v="$value" -v l="$limit" \
    'BEGIN { if (v < 0) v = -v; print (v <= l) ? "OK" : "WARN" }'
}

int_within() {
  local value="$1" limit="$2"
  if [[ "$value" =~ ^[0-9]+$ ]] && (( value <= limit )); then
    echo "OK"
  else
    echo "WARN"
  fi
}

tracking="$(chronyc tracking 2>/dev/null || true)"

if [[ -z "$tracking" ]]; then
  echo "Unable to read chrony tracking data (is chronyd running?)." >&2
  exit 3
fi

# Field extractors. `chronyc tracking` lines look like:
#   Stratum         : 2
#   Last offset     : +0.000123456 seconds
#   RMS offset      : 0.000234567 seconds
#   Frequency       : 12.345 ppm slow
#   Ref time (UTC)  : Wed Jun 17 12:00:00 2026   (note: value contains colons)
#   Leap status     : Normal
get_field() {
  # get_field "Field Name"  -> everything after the FIRST colon, trimmed.
  # We match on the label (text before the first colon) and must NOT touch the
  # remainder of the line, because some values (e.g. Ref time) contain colons.
  printf '%s\n' "$tracking" \
    | awk -v key="$1" '
        {
          pos = index($0, ":")
          if (pos == 0) next
          label = substr($0, 1, pos - 1)
          gsub(/^[ \t]+|[ \t]+$/, "", label)
          if (label == key) {
            val = substr($0, pos + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", val)
            print val
            exit
          }
        }'
}

ref_id="$(get_field "Reference ID")"
stratum="$(get_field "Stratum")"
ref_time="$(get_field "Ref time (UTC)")"
last_offset_raw="$(get_field "Last offset")"
rms_offset_raw="$(get_field "RMS offset")"
frequency="$(get_field "Frequency")"
jitter_raw="$(get_field "Root dispersion")"
leap="$(get_field "Leap status")"

# Strip the trailing " seconds" unit and keep the numeric token.
num() { printf '%s\n' "${1:-}" | awk '{print $1}'; }
last_offset="$(num "$last_offset_raw")"
rms_offset="$(num "$rms_offset_raw")"
jitter="$(num "$jitter_raw")"

# Selected source: the line in `chronyc sources` whose state column starts
# with '*' (current synced source) or '+' (combined). Format:
#   ^* 192.168.1.10  2  6  377  35  +12us[ +20us] +/- 1234us
selected_source="$(chronyc sources 2>/dev/null \
  | awk '/^\^\*/ {print $2; found=1; exit} END {if(!found) exit}')" || true
if [[ -z "${selected_source:-}" ]]; then
  selected_source="$(chronyc sources 2>/dev/null \
    | awk '/^\^\+/ {print $2; exit}')" || true
fi
[[ -n "${selected_source:-}" ]] || selected_source="(none selected)"

# Grade each numeric metric.
offset_grade="$(float_within "${last_offset:-999}" "$OFFSET_MAX")"
jitter_grade="$(float_within "${jitter:-999}" "$JITTER_MAX")"
stratum_grade="$(int_within "${stratum:-99}" "$STRATUM_MAX")"

# Synchronized iff Leap status is Normal.
synced="no"
if [[ "$leap" == "Normal" ]]; then
  synced="yes"
fi

hr() { printf '%s\n' "------------------------------------------------------------"; }

echo "======================  NTP STATUS  ======================"
printf '%-18s %s\n' "Reference ID:"   "${ref_id:-unknown}"
printf '%-18s %s\n' "Selected source:" "$selected_source"
printf '%-18s %s\n' "Ref time (UTC):"  "${ref_time:-unknown}"
printf '%-18s %s\n' "Frequency:"       "${frequency:-unknown}"
printf '%-18s %s\n' "System time:"     "$(date '+%Y-%m-%d %H:%M:%S %Z')"
hr
printf '%-14s %-20s %-12s %s\n' "METRIC" "VALUE" "THRESHOLD" "GRADE"
hr
printf '%-14s %-20s %-12s %s\n' "Stratum"   "${stratum:-?}"             "<= $STRATUM_MAX"  "$stratum_grade"
printf '%-14s %-20s %-12s %s\n' "Last offset" "${last_offset:-?} s"     "<= $OFFSET_MAX s" "$offset_grade"
printf '%-14s %-20s %-12s %s\n' "RMS offset"  "${rms_offset:-?} s"      "-"                "-"
printf '%-14s %-20s %-12s %s\n' "Root disp."  "${jitter:-?} s"          "<= $JITTER_MAX s" "$jitter_grade"
hr
printf '%-18s %s\n' "Leap status:" "${leap:-unknown}"
printf '%-18s %s\n' "Synchronized:" "$synced"
echo "=========================================================="

if [[ "$synced" != "yes" ]]; then
  echo "Result: NOT SYNCHRONIZED"
  exit 3
fi

if [[ "$offset_grade" == "WARN" || "$jitter_grade" == "WARN" || "$stratum_grade" == "WARN" ]]; then
  echo "Result: SYNCHRONIZED (with WARN - a metric exceeded its threshold)"
  exit 1
fi

echo "Result: OK"
exit 0
