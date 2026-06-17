#!/usr/bin/env bash
# ntp-uninstall.sh
# Cleanly revert what the setup scripts did to a host.
#
# By default this:
#   1. Stops and disables the chrony service.
#   2. Restores the most recent /etc/chrony*/chrony.conf.bak.* backup that the
#      setup scripts created (or, with --remove-config, deletes the generated
#      config when no backup exists).
#   3. Re-enables systemd-timesyncd (best effort) so the host keeps some time
#      source after chrony is gone.
#
# It does NOT remove the chrony package unless you pass --purge.
#
# Works on Debian/Ubuntu (service "chrony", config /etc/chrony/chrony.conf)
# and RHEL/CentOS/Fedora (service "chronyd", config /etc/chrony.conf).
#
# Options:
#   -n, --dry-run        show what would happen, change nothing
#   -p, --purge          also remove the chrony package (apt/dnf/yum)
#       --remove-config  if no backup exists, delete the generated config
#   -y, --yes            do not prompt for confirmation
#   -h, --help           show this help
#
# Exit codes:
#   0  success (or dry-run completed)
#   1  an action failed
#   3  not run as root
set -euo pipefail

DRY_RUN="no"
PURGE="no"
REMOVE_CONFIG="no"
ASSUME_YES="no"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN="yes" ;;
    -p|--purge) PURGE="yes" ;;
    --remove-config) REMOVE_CONFIG="yes" ;;
    -y|--yes) ASSUME_YES="yes" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; echo "Try --help." >&2; exit 2 ;;
  esac
  shift
done

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run this script as root or with sudo." >&2
    exit 3
  fi
}

# run CMD...  -> execute, or just print it in dry-run mode.
run() {
  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# Detect the chrony service name and config path for this distro.
detect_layout() {
  if [[ -f /etc/chrony/chrony.conf ]]; then
    CONF="/etc/chrony/chrony.conf"
  elif [[ -f /etc/chrony.conf ]]; then
    CONF="/etc/chrony.conf"
  elif [[ -d /etc/chrony ]]; then
    CONF="/etc/chrony/chrony.conf"
  else
    CONF="/etc/chrony.conf"
  fi

  # chrony on RHEL/Fedora ships the unit as chronyd.service; Debian as chrony.service.
  if systemctl list-unit-files 2>/dev/null | grep -q '^chronyd\.service'; then
    SERVICE="chronyd"
  else
    SERVICE="chrony"
  fi
}

# Find the newest backup that sits next to the active config.
latest_backup() {
  local dir base
  dir="$(dirname "$CONF")"
  base="$(basename "$CONF")"
  # Backups are named <conf>.bak.YYYY-MM-DD_HHMMSS; lexical sort == chronological.
  ls -1 "${dir}/${base}.bak."* 2>/dev/null | sort | tail -n 1 || true
}

require_root
detect_layout

echo "=== NTP UNINSTALL ==="
echo "Service:      $SERVICE"
echo "Config:       $CONF"
echo "Dry run:      $DRY_RUN"
echo "Purge pkg:    $PURGE"
echo

BACKUP="$(latest_backup)"
if [[ -n "$BACKUP" ]]; then
  echo "Most recent backup found: $BACKUP"
else
  echo "No chrony.conf backup found next to $CONF."
fi
echo

if [[ "$ASSUME_YES" != "yes" && "$DRY_RUN" != "yes" ]]; then
  read -rp "Proceed with revert? [y/N]: " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# 1. Stop and disable chrony.
echo "Stopping and disabling $SERVICE..."
run systemctl stop "$SERVICE" 2>/dev/null || true
run systemctl disable "$SERVICE" 2>/dev/null || true

# 2. Restore the backup, or optionally remove the generated config.
if [[ -n "$BACKUP" ]]; then
  echo "Restoring config from backup..."
  run cp "$BACKUP" "$CONF"
elif [[ "$REMOVE_CONFIG" == "yes" ]]; then
  echo "No backup; removing generated config (--remove-config given)..."
  run rm -f "$CONF"
else
  echo "No backup to restore. Leaving $CONF in place."
  echo "  (Pass --remove-config to delete the generated config instead.)"
fi

# 3. Re-enable systemd-timesyncd so the host still tracks time (best effort).
if command -v systemctl >/dev/null 2>&1 \
   && systemctl list-unit-files 2>/dev/null | grep -q '^systemd-timesyncd\.service'; then
  echo "Re-enabling systemd-timesyncd..."
  run systemctl enable --now systemd-timesyncd 2>/dev/null || true
  run timedatectl set-ntp true 2>/dev/null || true
else
  echo "systemd-timesyncd not available; skipping (no fallback time source set)."
fi

# 4. Optionally purge the chrony package.
if [[ "$PURGE" == "yes" ]]; then
  echo "Removing the chrony package..."
  if command -v apt-get >/dev/null 2>&1; then
    run env DEBIAN_FRONTEND=noninteractive apt-get purge -y chrony
  elif command -v dnf >/dev/null 2>&1; then
    run dnf remove -y chrony
  elif command -v yum >/dev/null 2>&1; then
    run yum remove -y chrony
  else
    echo "No supported package manager found; cannot purge chrony." >&2
  fi
fi

echo
if [[ "$DRY_RUN" == "yes" ]]; then
  echo "Dry-run complete. No changes were made."
else
  echo "Done. chrony reverted."
  if command -v timedatectl >/dev/null 2>&1; then
    echo
    timedatectl status 2>/dev/null || true
  fi
fi
exit 0
